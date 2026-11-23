// Package device talks to an iPhone over usbmuxd using the
// com.apple.springboardservices lockdown service (the service iTunes used to
// arrange Home Screen icons).
package device

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/danielpaulus/go-ios/ios"
	"howett.net/plist"
)

// ErrNoDevice is returned when usbmuxd reports no connected device.
var ErrNoDevice = errors.New("no_device")

const (
	serviceName = "com.apple.springboardservices"
	ioTimeout   = 45 * time.Second
	maxMessage  = 64 << 20
)

// Info describes the connected device.
type Info struct {
	Name  string `json:"name"`
	IOS   string `json:"ios"`
	Model string `json:"model"`
	Class string `json:"deviceClass"`
	UDID  string `json:"udid"`
	USB   bool   `json:"usb"`
}

// Metrics is the Home Screen grid as reported by SpringBoard.
type Metrics struct {
	Columns        int `json:"columns"`
	Rows           int `json:"rows"`
	DockMax        int `json:"dockMax"`
	FolderColumns  int `json:"folderColumns"`
	FolderRows     int `json:"folderRows"`
	FolderMaxPages int `json:"folderMaxPages"`
	MaxPages       int `json:"maxPages"`
}

// DefaultMetrics are iPhone values, used only if the device does not answer.
var DefaultMetrics = Metrics{Columns: 4, Rows: 6, DockMax: 4, FolderColumns: 3, FolderRows: 3, FolderMaxPages: 15, MaxPages: 15}

// Device serialises every call on one springboardservices connection.
type Device struct {
	mu    sync.Mutex
	entry *ios.DeviceEntry
	conn  ios.DeviceConnectionInterface
}

func New() *Device { return &Device{} }

func (d *Device) ensure() error {
	if d.conn != nil {
		return nil
	}
	list, err := ios.ListDevices()
	if err != nil {
		return fmt.Errorf("usbmuxd: %w", err)
	}
	if len(list.DeviceList) == 0 {
		return ErrNoDevice
	}
	entry := list.DeviceList[0]
	for _, e := range list.DeviceList {
		if e.Properties.ConnectionType == "USB" {
			entry = e
			break
		}
	}
	conn, err := ios.ConnectToService(entry, serviceName)
	if err != nil {
		return fmt.Errorf("connect %s: %w", serviceName, err)
	}
	d.entry, d.conn = &entry, conn
	return nil
}

func (d *Device) reset() {
	if d.conn != nil {
		_ = d.conn.Close()
	}
	d.conn, d.entry = nil, nil
}

// Disconnect drops the current connection (used on app shutdown).
func (d *Device) Disconnect() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.reset()
}

// do runs fn with a live connection, reconnecting once on failure.
func (d *Device) do(fn func() error) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	var err error
	for attempt := 0; attempt < 2; attempt++ {
		if err = d.ensure(); err != nil {
			d.reset()
			if errors.Is(err, ErrNoDevice) {
				return err
			}
			continue
		}
		if c := d.conn.Conn(); c != nil {
			_ = c.SetDeadline(time.Now().Add(ioTimeout))
		}
		if err = fn(); err == nil {
			return nil
		}
		d.reset()
	}
	return err
}

func (d *Device) write(msg any) error {
	data, err := plist.Marshal(msg, plist.BinaryFormat)
	if err != nil {
		return fmt.Errorf("encode plist: %w", err)
	}
	buf := new(bytes.Buffer)
	_ = binary.Write(buf, binary.BigEndian, uint32(len(data)))
	buf.Write(data)
	_, err = d.conn.Writer().Write(buf.Bytes())
	return err
}

func (d *Device) read(v any) error {
	var n uint32
	if err := binary.Read(d.conn.Reader(), binary.BigEndian, &n); err != nil {
		return fmt.Errorf("read length: %w", err)
	}
	if n > maxMessage {
		return fmt.Errorf("message too large (%d bytes)", n)
	}
	data := make([]byte, n)
	if _, err := io.ReadFull(d.conn.Reader(), data); err != nil {
		return fmt.Errorf("read payload: %w", err)
	}
	_, err := plist.Unmarshal(data, v)
	return err
}

// Info returns name, iOS version and model of the connected device.
func (d *Device) Info() (Info, error) {
	var out Info
	err := d.do(func() error {
		lc, err := ios.ConnectLockdownWithSession(*d.entry)
		if err != nil {
			return err
		}
		defer lc.Close()
		v, err := lc.GetValues()
		if err != nil {
			return err
		}
		out = Info{Name: v.Value.DeviceName, IOS: v.Value.ProductVersion, Model: v.Value.ProductType,
			Class: v.Value.DeviceClass, UDID: d.entry.Properties.SerialNumber,
			USB: d.entry.Properties.ConnectionType == "USB"}
		return nil
	})
	return out, err
}

// Metrics returns the Home Screen grid of the connected device.
func (d *Device) Metrics() (Metrics, error) {
	var raw map[string]any
	err := d.do(func() error {
		if err := d.write(map[string]any{"command": "getHomeScreenIconMetrics"}); err != nil {
			return err
		}
		return d.read(&raw)
	})
	if err != nil {
		return DefaultMetrics, err
	}
	num := func(key string, def int) int {
		switch v := raw[key].(type) {
		case float64:
			if v > 0 {
				return int(v)
			}
		case uint64:
			if v > 0 {
				return int(v)
			}
		case int64:
			if v > 0 {
				return int(v)
			}
		}
		return def
	}
	m := DefaultMetrics
	return Metrics{
		Columns:        num("homeScreenIconColumns", m.Columns),
		Rows:           num("homeScreenIconRows", m.Rows),
		DockMax:        num("homeScreenIconDockMaxCount", m.DockMax),
		FolderColumns:  num("homeScreenIconFolderColumns", m.FolderColumns),
		FolderRows:     num("homeScreenIconFolderRows", m.FolderRows),
		FolderMaxPages: num("homeScreenIconFolderMaxPages", m.FolderMaxPages),
		MaxPages:       num("homeScreenIconMaxPages", m.MaxPages),
	}, nil
}

// IconState returns the raw icon layout (format version 2): a list whose first
// element is the Dock and the others are Home Screen pages.
func (d *Device) IconState() ([]any, error) {
	var out []any
	err := d.do(func() error {
		if err := d.write(map[string]any{"command": "getIconState", "formatVersion": "2"}); err != nil {
			return err
		}
		return d.read(&out)
	})
	return out, err
}

// SetIconState writes a raw icon layout. SpringBoard sends no reply.
func (d *Device) SetIconState(state []any) error {
	return d.do(func() error {
		return d.write(map[string]any{"command": "setIconState", "iconState": state})
	})
}

// IconPNG returns the Home Screen icon of an app as PNG.
func (d *Device) IconPNG(bundleID string) ([]byte, error) {
	var resp struct {
		PNG []byte `plist:"pngData"`
	}
	err := d.do(func() error {
		if err := d.write(map[string]any{"command": "getIconPNGData", "bundleId": bundleID}); err != nil {
			return err
		}
		return d.read(&resp)
	})
	if err == nil && len(resp.PNG) == 0 {
		err = errors.New("empty icon")
	}
	return resp.PNG, err
}
