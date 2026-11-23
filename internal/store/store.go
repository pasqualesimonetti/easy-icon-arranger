// Package store keeps backups, the icon cache and settings on disk.
package store

import (
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"errors"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/image/draw"
	"howett.net/plist"

	"github.com/pasqualesimonetti/easy-icon-arranger/internal/layout"
)

const appDir = "Easy Icon Arranger"

// oldAppDir is the folder name used by early builds; its data is moved once.
// Earlier names of the app, migrated on first launch.
var oldAppDirs = []string{"Easy Icon Arrange", "iPhone Home Manager"}

func migrate(base string) {
	cur := filepath.Join(base, appDir)
	if _, err := os.Stat(cur); err == nil {
		return
	}
	for _, name := range oldAppDirs {
		old := filepath.Join(base, name)
		if _, err := os.Stat(old); err == nil {
			_ = os.Rename(old, cur)
			return
		}
	}
}

type Store struct {
	Backups  string
	Icons    string
	settings string
	mu       sync.Mutex
}

type Settings struct {
	Language string `json:"language"`
}

type Backup struct {
	Name  string `json:"name"`
	Date  string `json:"date"`
	Pages int    `json:"pages"`
	Items int    `json:"items"`
}

func New() (*Store, error) {
	cfg, err := os.UserConfigDir()
	if err != nil {
		return nil, err
	}
	cache, err := os.UserCacheDir()
	if err != nil {
		return nil, err
	}
	migrate(cfg)
	migrate(cache)
	s := &Store{
		Backups:  filepath.Join(cfg, appDir, "Backups"),
		Icons:    filepath.Join(cache, appDir, "Icons"),
		settings: filepath.Join(cfg, appDir, "settings.json"),
	}
	for _, d := range []string{s.Backups, s.Icons} {
		if err := os.MkdirAll(d, 0o700); err != nil {
			return nil, err
		}
	}
	return s, nil
}

func (s *Store) LoadSettings() Settings {
	out := Settings{Language: "en"}
	if data, err := os.ReadFile(s.settings); err == nil {
		_ = json.Unmarshal(data, &out)
	}
	if out.Language != "it" {
		out.Language = "en"
	}
	return out
}

func (s *Store) SaveSettings(v Settings) error {
	data, _ := json.MarshalIndent(v, "", "  ")
	return os.WriteFile(s.settings, data, 0o600)
}

// SaveBackup writes a raw layout as a binary plist.
func (s *Store) SaveBackup(raw []any, label string) (string, error) {
	data, err := plist.Marshal(raw, plist.BinaryFormat)
	if err != nil {
		return "", err
	}
	name := time.Now().Format("20060102_150405") + "_" + label + ".plist"
	return name, os.WriteFile(filepath.Join(s.Backups, name), data, 0o600)
}

func (s *Store) LoadBackup(name string) ([]any, error) {
	if name != filepath.Base(name) || !strings.HasSuffix(name, ".plist") {
		return nil, errors.New("invalid backup name")
	}
	data, err := os.ReadFile(filepath.Join(s.Backups, name))
	if err != nil {
		return nil, err
	}
	var raw []any
	if _, err := plist.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	return raw, nil
}

func (s *Store) ListBackups() []Backup {
	files, _ := filepath.Glob(filepath.Join(s.Backups, "*.plist"))
	sort.Sort(sort.Reverse(sort.StringSlice(files)))
	out := []Backup{}
	for _, f := range files {
		raw, err := s.LoadBackup(filepath.Base(f))
		if err != nil {
			continue
		}
		date := ""
		if st, err := os.Stat(f); err == nil {
			date = st.ModTime().Format(time.RFC3339)
		}
		if parts := strings.SplitN(filepath.Base(f), "_", 3); len(parts) >= 2 {
			if t, err := time.ParseInLocation("20060102_150405", parts[0]+"_"+parts[1], time.Local); err == nil {
				date = t.Format(time.RFC3339)
			}
		}
		out = append(out, Backup{Name: filepath.Base(f), Date: date, Pages: max(len(raw)-1, 0), Items: layout.Count(raw)})
	}
	return out
}

func (s *Store) iconPath(key string) string {
	h := sha1.Sum([]byte(key))
	return filepath.Join(s.Icons, hex.EncodeToString(h[:])+".png")
}

// IconFile is the cache path of an icon (it may not exist yet).
func (s *Store) IconFile(key string) string { return s.iconPath(key) }

// CachedIcon returns a cached icon, if present.
func (s *Store) CachedIcon(key string) ([]byte, bool) {
	data, err := os.ReadFile(s.iconPath(key))
	return data, err == nil
}

// PutIcon resizes an icon to 128 px and caches it.
func (s *Store) PutIcon(key string, data []byte) ([]byte, error) {
	src, err := png.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	const size = 128
	b := src.Bounds()
	if b.Dx() > size || b.Dy() > size {
		dst := image.NewRGBA(image.Rect(0, 0, size, size*b.Dy()/max(b.Dx(), 1)))
		draw.CatmullRom.Scale(dst, dst.Bounds(), src, b, draw.Over, nil)
		var buf bytes.Buffer
		if err := png.Encode(&buf, dst); err == nil {
			data = buf.Bytes()
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	tmp := s.iconPath(key) + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return data, nil
	}
	_ = os.Rename(tmp, s.iconPath(key))
	return data, nil
}
