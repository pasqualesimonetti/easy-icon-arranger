// Package layout converts the raw SpringBoard icon state into a simple model
// for the UI and back. Original entries are written back untouched: only their
// position changes, so no app can be lost or altered.
package layout

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"sync"

	"github.com/pasqualesimonetti/easy-icon-arranger/internal/device"
)

// Item is an app, widget or web clip.
type Item struct {
	ID     string `json:"id"`
	Type   string `json:"type"` // app | widget | webclip | other
	Name   string `json:"name"`
	Key    string `json:"key,omitempty"` // bundle id used for the icon
	Size   string `json:"size,omitempty"`
	Widget string `json:"widget,omitempty"`
}

// Folder holds its pages exactly as on the device (pages may be partly filled).
type Folder struct {
	Name  string     `json:"name"`
	Pages [][]string `json:"pages"`
}

// View is what the UI receives.
type View struct {
	Items   map[string]Item   `json:"items"`
	Folders map[string]Folder `json:"folders"`
	Dock    []string          `json:"dock"`
	Pages   [][]string        `json:"pages"`
	Sig     string            `json:"sig"`
	Count   int               `json:"count"`
	Metrics device.Metrics    `json:"metrics"`
}

// Payload is what the UI sends back.
type Payload struct {
	Dock    []string          `json:"dock"`
	Pages   [][]string        `json:"pages"`
	Folders map[string]Folder `json:"folders"`
	Sig     string            `json:"sig"`
	Force   bool              `json:"force"`
}

// UserError carries a message code plus arguments, translated by the UI.
type UserError struct {
	Code string
	Args []any
}

func (e *UserError) Error() string {
	parts := []string{e.Code}
	for _, a := range e.Args {
		parts = append(parts, strings.ReplaceAll(fmt.Sprint(a), "|", "/"))
	}
	return strings.Join(parts, "|")
}

func uerr(code string, args ...any) error { return &UserError{Code: code, Args: args} }

func Kind(v any) string {
	it, ok := v.(map[string]any)
	if !ok {
		return "other"
	}
	if it["elementType"] == "widget" {
		return "widget"
	}
	_, hasLists := it["iconLists"]
	if hasLists && it["listType"] == "folder" {
		return "folder"
	}
	if _, ok := it["webClipURL"]; ok {
		return "webclip"
	}
	if hasLists {
		return "other"
	}
	return "app"
}

func str(m map[string]any, k string) string {
	s, _ := m[k].(string)
	return s
}

func ident(v any) string {
	m, _ := v.(map[string]any)
	if s := str(m, "displayIdentifier"); s != "" {
		return s
	}
	return str(m, "bundleIdentifier")
}

func folderPages(v any) [][]any {
	m, _ := v.(map[string]any)
	var out [][]any
	lists, _ := m["iconLists"].([]any)
	for _, l := range lists {
		page, _ := l.([]any)
		out = append(out, page)
	}
	return out
}

func folderChildren(v any) []any {
	var out []any
	for _, p := range folderPages(v) {
		out = append(out, p...)
	}
	return out
}

func asPages(raw []any) [][]any {
	out := make([][]any, 0, len(raw))
	for _, p := range raw {
		page, _ := p.([]any)
		out = append(out, page)
	}
	return out
}

// Signature identifies a layout by order of identifiers and folder names.
func Signature(raw []any) string {
	var sig func(v any) any
	sig = func(v any) any {
		if Kind(v) == "folder" {
			m := v.(map[string]any)
			pages := []any{}
			for _, page := range folderPages(v) {
				kids := []any{}
				for _, c := range page {
					kids = append(kids, sig(c))
				}
				pages = append(pages, kids)
			}
			return []any{str(m, "displayName"), pages}
		}
		return ident(v)
	}
	out := [][]any{}
	for _, page := range asPages(raw) {
		row := []any{}
		for _, it := range page {
			row = append(row, sig(it))
		}
		out = append(out, row)
	}
	b, _ := json.Marshal(out)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// Count returns the number of entries (apps, widgets, web clips), folders excluded.
func Count(raw []any) int {
	n := 0
	for _, page := range asPages(raw) {
		for _, it := range page {
			if Kind(it) == "folder" {
				n += len(folderChildren(it))
			} else {
				n++
			}
		}
	}
	return n
}

// Session keeps the last layout read from the device and maps ids to entries.
type Session struct {
	mu      sync.Mutex
	Raw     []any
	Sig     string
	items   map[string]map[string]any
	folders map[string]map[string]any
	Metrics device.Metrics
}

func (s *Session) Lock()   { s.mu.Lock() }
func (s *Session) Unlock() { s.mu.Unlock() }

// Load builds the UI view. Ids are unique per load, so data from an older
// load can never be mistaken for entries of the current one.
func (s *Session) Load(raw []any, m device.Metrics) *View {
	s.Raw, s.Sig, s.Metrics = raw, Signature(raw), m
	s.items, s.folders = map[string]map[string]any{}, map[string]map[string]any{}
	gen := make([]byte, 3)
	_, _ = rand.Read(gen)
	prefix := hex.EncodeToString(gen)
	n := 0
	nid := func(p string) string { n++; return fmt.Sprintf("%s%s-%d", p, prefix, n) }
	v := &View{Items: map[string]Item{}, Folders: map[string]Folder{}, Sig: s.Sig, Count: Count(raw), Metrics: m}
	names := map[string]string{}

	var conv func(it any, inFolder bool) string
	conv = func(it any, inFolder bool) string {
		k := Kind(it)
		m, _ := it.(map[string]any)
		if m == nil {
			m = map[string]any{}
		}
		if k == "folder" && !inFolder {
			fid := nid("f")
			meta := map[string]any{}
			for key, val := range m {
				if key != "iconLists" && key != "listMetadata" {
					meta[key] = val
				}
			}
			s.folders[fid] = meta
			f := Folder{Name: str(m, "displayName"), Pages: [][]string{}}
			for _, page := range folderPages(it) {
				ids := []string{}
				for _, c := range page {
					ids = append(ids, conv(c, true))
				}
				f.Pages = append(f.Pages, ids)
			}
			v.Folders[fid] = f
			return fid
		}
		if k == "folder" {
			k = "other"
		}
		iid := nid("i")
		s.items[iid] = m
		item := Item{ID: iid, Type: k, Name: str(m, "displayName")}
		switch k {
		case "widget":
			item.Size = str(m, "gridSize")
			if item.Size == "" {
				item.Size = "small"
			}
			item.Key = str(m, "containerBundleIdentifier")
			item.Widget = str(m, "widgetIdentifier")
		case "app", "other":
			item.Key = ident(m)
			names[item.Key] = item.Name
		}
		v.Items[iid] = item
		return iid
	}

	pages := asPages(raw)
	if len(pages) > 0 {
		for _, it := range pages[0] {
			v.Dock = append(v.Dock, conv(it, false))
		}
	}
	for _, page := range pages[min(1, len(pages)):] {
		row := []string{}
		for _, it := range page {
			row = append(row, conv(it, false))
		}
		v.Pages = append(v.Pages, row)
	}
	if v.Dock == nil {
		v.Dock = []string{}
	}
	if v.Pages == nil {
		v.Pages = [][]string{}
	}
	for id, it := range v.Items {
		if it.Type == "widget" {
			app := names[it.Key]
			if app == "" {
				parts := strings.Split(it.Key, ".")
				app = parts[len(parts)-1]
			}
			it.Name = app
			v.Items[id] = it
		}
	}
	return v
}

// WidgetSlots returns how many grid cells a widget of the given size takes.
func WidgetSlots(size string, m device.Metrics) int {
	switch size {
	case "medium":
		return m.Columns * 2
	case "large":
		return m.Columns * 4
	case "extraLarge":
		return m.Columns * 4 * 2
	default:
		return 4
	}
}

// Build validates a payload and returns the raw layout to write.
func (s *Session) Build(p Payload) ([]any, error) {
	if s.Raw == nil {
		return nil, uerr("not_loaded")
	}
	m := s.Metrics
	folderCap := m.FolderColumns * m.FolderRows
	used, usedF := map[string]bool{}, map[string]bool{}
	label := func(id string) string {
		if it, ok := s.items[id]; ok && str(it, "displayName") != "" {
			return str(it, "displayName")
		}
		return id
	}
	take := func(id string) (map[string]any, error) {
		if _, ok := p.Folders[id]; ok {
			return nil, uerr("folder_in_folder")
		}
		if _, ok := s.folders[id]; ok {
			return nil, uerr("folder_in_folder")
		}
		it, ok := s.items[id]
		if !ok {
			return nil, uerr("unknown_item", id)
		}
		if used[id] {
			return nil, uerr("duplicate_item", label(id))
		}
		used[id] = true
		return it, nil
	}
	node := func(id, where string) (any, error) {
		if f, ok := p.Folders[id]; ok {
			if usedF[id] {
				return nil, uerr("duplicate_folder", f.Name)
			}
			usedF[id] = true
			name := strings.TrimSpace(f.Name)
			if name == "" {
				name = "Folder"
			}
			if len([]rune(name)) > 60 {
				name = string([]rune(name)[:60])
			}
			lists := []any{}
			for _, ids := range f.Pages {
				page := []any{}
				for _, c := range ids {
					it, err := take(c)
					if err != nil {
						return nil, err
					}
					if Kind(it) == "widget" {
						return nil, uerr("widget_in_folder")
					}
					page = append(page, it)
				}
				if len(page) > folderCap {
					return nil, uerr("folder_page_full", name, len(lists)+1, len(page), folderCap)
				}
				if len(page) > 0 { // empty folder pages disappear, as on the iPhone
					lists = append(lists, page)
				}
			}
			if len(lists) == 0 {
				return nil, nil // empty folders disappear too
			}
			if m.FolderMaxPages > 0 && len(lists) > m.FolderMaxPages {
				return nil, uerr("folder_too_many_pages", name, len(lists), m.FolderMaxPages)
			}
			out := map[string]any{}
			for k, v := range s.folders[id] {
				out[k] = v
			}
			out["displayName"] = name
			out["listType"] = "folder"
			out["iconLists"] = lists
			return out, nil
		}
		it, err := take(id)
		if err != nil {
			return nil, err
		}
		if where == "dock" && Kind(it) == "widget" {
			return nil, uerr("widget_in_dock")
		}
		return it, nil
	}

	dock := []any{}
	for _, id := range p.Dock {
		n, err := node(id, "dock")
		if err != nil {
			return nil, err
		}
		if n != nil {
			dock = append(dock, n)
		}
	}
	if len(dock) > m.DockMax {
		return nil, uerr("dock_full", len(dock), m.DockMax)
	}
	out := []any{dock}
	capacity := m.Columns * m.Rows
	for i, ids := range p.Pages {
		page, slots := []any{}, 0
		for _, id := range ids {
			n, err := node(id, "page")
			if err != nil {
				return nil, err
			}
			if n == nil {
				continue
			}
			if Kind(n) == "widget" {
				slots += WidgetSlots(str(n.(map[string]any), "gridSize"), m)
			} else {
				slots++
			}
			page = append(page, n)
		}
		if slots > capacity {
			return nil, uerr("page_full", i+1, slots, capacity)
		}
		if len(page) > 0 {
			out = append(out, page)
		}
	}
	if m.MaxPages > 0 && len(out)-1 > m.MaxPages {
		return nil, uerr("too_many_pages", len(out)-1, m.MaxPages)
	}
	var missing []string
	for id := range s.items {
		if !used[id] {
			missing = append(missing, label(id))
		}
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		return nil, uerr("missing_items", len(missing), strings.Join(missing[:min(8, len(missing))], ", "))
	}
	return out, nil
}
