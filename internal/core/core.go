// Package core is the engine of Easy Icon Arranger, independent of the UI:
// device access, layout model, validation, backups and icon cache.
package core

import (
	"errors"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/pasqualesimonetti/easy-icon-arranger/internal/device"
	"github.com/pasqualesimonetti/easy-icon-arranger/internal/layout"
	"github.com/pasqualesimonetti/easy-icon-arranger/internal/store"
)

type Core struct {
	dev     *device.Device
	store   *store.Store
	session *layout.Session
	failed  sync.Map // icon keys the device could not provide
	gen     atomic.Int64
}

// Status is the result of Connect.
type Status struct {
	Info    device.Info    `json:"info"`
	Metrics device.Metrics `json:"metrics"`
}

// SaveResult is returned by Save and Restore.
type SaveResult struct {
	OK       bool         `json:"ok"`
	Backup   string       `json:"backup"`
	Verified bool         `json:"verified"`
	Conflict string       `json:"conflict,omitempty"` // "stale" | "changed"
	Layout   *layout.View `json:"layout,omitempty"`
}

func New() (*Core, error) {
	st, err := store.New()
	if err != nil {
		return nil, err
	}
	return &Core{dev: device.New(), store: st, session: &layout.Session{}}, nil
}

func (c *Core) Close() { c.dev.Disconnect() }

// friendly turns errors into "code|detail" strings that the UI translates.
func friendly(err error) error {
	if err == nil {
		return nil
	}
	var ue *layout.UserError
	if errors.As(err, &ue) {
		return err
	}
	if errors.Is(err, device.ErrNoDevice) {
		return errors.New("no_device")
	}
	msg := err.Error()
	switch {
	case strings.Contains(msg, "usbmuxd"):
		return errors.New("usbmuxd|" + msg)
	case strings.Contains(strings.ToLower(msg), "pair"):
		return errors.New("not_paired|" + msg)
	}
	return errors.New("device_error|" + msg)
}

func (c *Core) metrics() device.Metrics {
	m, err := c.dev.Metrics()
	if err != nil || m.Columns == 0 {
		return device.DefaultMetrics
	}
	return m
}

// Connect returns device info and its Home Screen grid.
func (c *Core) Connect() (*Status, error) {
	info, err := c.dev.Info()
	if err != nil {
		return nil, friendly(err)
	}
	return &Status{Info: info, Metrics: c.metrics()}, nil
}

// LoadLayout reads the current layout from the iPhone.
func (c *Core) LoadLayout() (*layout.View, error) {
	raw, err := c.dev.IconState()
	if err != nil {
		return nil, friendly(err)
	}
	m := c.metrics()
	c.session.Lock()
	view := c.session.Load(raw, m)
	c.session.Unlock()
	c.prefetch(view)
	return view, nil
}

// Save validates and writes a new layout, after backing up the current one.
func (c *Core) Save(p layout.Payload) (*SaveResult, error) {
	c.session.Lock()
	defer c.session.Unlock()
	if p.Sig != c.session.Sig {
		return &SaveResult{Conflict: "stale"}, nil
	}
	newRaw, err := c.session.Build(p)
	if err != nil {
		return nil, err
	}
	current, err := c.dev.IconState()
	if err != nil {
		return nil, friendly(err)
	}
	if layout.Signature(current) != c.session.Sig && !p.Force {
		return &SaveResult{Conflict: "changed"}, nil
	}
	backup, err := c.store.SaveBackup(current, "before-save")
	if err != nil {
		return nil, errors.New("backup_failed|" + err.Error())
	}
	if err := c.dev.SetIconState(newRaw); err != nil {
		return nil, friendly(err)
	}
	after, err := c.dev.IconState()
	if err != nil {
		return nil, friendly(err)
	}
	verified := layout.Signature(after) == layout.Signature(newRaw)
	view := c.session.Load(after, c.session.Metrics)
	return &SaveResult{OK: true, Backup: backup, Verified: verified, Layout: view}, nil
}

// Backups returns saved layouts, newest first.
func (c *Core) Backups() []store.Backup { return c.store.ListBackups() }

func (c *Core) BackupsDir() string { return c.store.Backups }

// Restore writes a saved layout, after backing up the current one.
func (c *Core) Restore(name string) (*SaveResult, error) {
	raw, err := c.store.LoadBackup(name)
	if err != nil {
		return nil, errors.New("backup_not_found|" + name)
	}
	c.session.Lock()
	defer c.session.Unlock()
	current, err := c.dev.IconState()
	if err != nil {
		return nil, friendly(err)
	}
	backup, err := c.store.SaveBackup(current, "before-restore")
	if err != nil {
		return nil, errors.New("backup_failed|" + err.Error())
	}
	if err := c.dev.SetIconState(raw); err != nil {
		return nil, friendly(err)
	}
	after, err := c.dev.IconState()
	if err != nil {
		return nil, friendly(err)
	}
	m := c.session.Metrics
	if m.Columns == 0 {
		m = c.metrics()
	}
	view := c.session.Load(after, m)
	return &SaveResult{OK: true, Backup: backup, Verified: true, Layout: view}, nil
}

// IconPath returns the path of the cached icon for a bundle id, fetching it
// from the device when needed; "" when the device has no icon for it.
func (c *Core) IconPath(key string) string {
	if key == "" {
		return ""
	}
	if _, ok := c.store.CachedIcon(key); ok {
		return c.store.IconFile(key)
	}
	if _, bad := c.failed.Load(key); bad {
		return ""
	}
	data, err := c.dev.IconPNG(key)
	if err != nil {
		c.failed.Store(key, true)
		return ""
	}
	if _, err := c.store.PutIcon(key, data); err != nil {
		return ""
	}
	return c.store.IconFile(key)
}

// prefetch caches all icons in the background; a newer load cancels it.
func (c *Core) prefetch(v *layout.View) {
	gen := c.gen.Add(1)
	keys := []string{}
	seen := map[string]bool{}
	for _, it := range v.Items {
		if it.Key != "" && !seen[it.Key] {
			seen[it.Key] = true
			keys = append(keys, it.Key)
		}
	}
	go func() {
		for _, k := range keys {
			if c.gen.Load() != gen {
				return
			}
			c.IconPath(k)
		}
	}()
}
