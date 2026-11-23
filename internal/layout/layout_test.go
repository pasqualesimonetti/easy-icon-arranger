package layout

import (
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/pasqualesimonetti/easy-icon-arranger/internal/device"
)

func app(id string) map[string]any {
	return map[string]any{
		"displayIdentifier": id, "bundleIdentifier": id, "displayName": strings.ToUpper(id[:1]) + id[1:],
		"bundleVersion": "1", "iconModDate": time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC),
	}
}

func folder(name string, pages ...[]any) map[string]any {
	lists := []any{}
	for _, p := range pages {
		lists = append(lists, p)
	}
	return map[string]any{"displayName": name, "listType": "folder", "iconLists": lists}
}

func widget(size string) map[string]any {
	return map[string]any{
		"elementType": "widget", "gridSize": size, "iconType": "custom", "iconLists": []any{},
		"containerBundleIdentifier": "com.example.weather", "bundleIdentifier": "com.example.weather.widget",
		"displayIdentifier": "W-" + size,
	}
}

// sample: Dock with 2 apps; page 1 with a folder (pages of 9 and 3, as iOS
// allows partly filled pages) and 2 apps; page 2 with a widget and a web clip.
func sample() []any {
	nine := []any{}
	for _, c := range "abcdefghi" {
		nine = append(nine, app("f"+string(c)))
	}
	return []any{
		[]any{app("phone"), app("mail")},
		[]any{folder("Tools", nine, []any{app("fj"), app("fk"), app("fl")}), app("maps"), app("notes")},
		[]any{widget("small"), map[string]any{"displayIdentifier": "CLIP1", "displayName": "Site", "webClipURL": "/x"}},
	}
}

func load(t *testing.T) (*Session, *View, []any) {
	t.Helper()
	raw := sample()
	s := &Session{}
	return s, s.Load(raw, device.DefaultMetrics), raw
}

func payload(v *View) Payload {
	f := map[string]Folder{}
	for k, x := range v.Folders {
		pages := [][]string{}
		for _, p := range x.Pages {
			pages = append(pages, append([]string{}, p...))
		}
		f[k] = Folder{Name: x.Name, Pages: pages}
	}
	pages := [][]string{}
	for _, p := range v.Pages {
		pages = append(pages, append([]string{}, p...))
	}
	return Payload{Dock: append([]string{}, v.Dock...), Pages: pages, Folders: f, Sig: v.Sig}
}

func TestRoundTripIsLossless(t *testing.T) {
	s, v, raw := load(t)
	got, err := s.Build(payload(v))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, raw) {
		t.Fatalf("rebuilt layout differs from the original")
	}
	if Signature(got) != Signature(raw) {
		t.Fatal("signature changed")
	}
	if v.Count != 2+12+2+2 {
		t.Fatalf("count = %d", v.Count)
	}
}

func TestFolderPagesArePreserved(t *testing.T) {
	_, v, _ := load(t)
	for _, f := range v.Folders {
		if len(f.Pages) != 2 || len(f.Pages[0]) != 9 || len(f.Pages[1]) != 3 {
			t.Fatalf("folder pages = %v", f.Pages)
		}
	}
}

func TestIdsAreUniquePerLoad(t *testing.T) {
	s := &Session{}
	a := s.Load(sample(), device.DefaultMetrics)
	b := s.Load(sample(), device.DefaultMetrics)
	if a.Dock[0] == b.Dock[0] {
		t.Fatal("ids reused across loads")
	}
	if _, err := s.Build(payload(a)); err == nil {
		t.Fatal("payload from an older load must be rejected")
	}
}

func TestMovingAnAppChangesOnlyItsPosition(t *testing.T) {
	s, v, raw := load(t)
	p := payload(v)
	maps := p.Pages[0][1]
	p.Pages[0] = append(p.Pages[0][:1], p.Pages[0][2:]...)
	p.Dock = append(p.Dock, maps)
	got, err := s.Build(p)
	if err != nil {
		t.Fatal(err)
	}
	dock := got[0].([]any)
	if len(dock) != 3 || !reflect.DeepEqual(dock[2], raw[1].([]any)[1]) {
		t.Fatalf("maps not moved to the dock unchanged: %v", dock)
	}
}

func TestValidation(t *testing.T) {
	s, v, _ := load(t)
	fid := v.Pages[0][0]
	cases := map[string]func(p *Payload){
		"missing_items": func(p *Payload) { p.Pages[0] = p.Pages[0][:2] },
		"duplicate_item": func(p *Payload) {
			p.Pages[1] = append(p.Pages[1], p.Dock[0])
		},
		"widget_in_dock": func(p *Payload) {
			p.Dock = append(p.Dock, p.Pages[1][0])
			p.Pages[1] = p.Pages[1][1:]
		},
		"widget_in_folder": func(p *Payload) {
			f := p.Folders[fid]
			f.Pages[1] = append(f.Pages[1], p.Pages[1][0])
			p.Folders[fid] = f
			p.Pages[1] = p.Pages[1][1:]
		},
		"folder_page_full": func(p *Payload) {
			f := p.Folders[fid]
			f.Pages[0] = append(f.Pages[0], f.Pages[1][0])
			f.Pages[1] = f.Pages[1][1:]
			p.Folders[fid] = f
		},
		"dock_full": func(p *Payload) {
			p.Dock = append(p.Dock, p.Pages[0][1], p.Pages[0][2], p.Pages[1][1])
			p.Pages[0] = p.Pages[0][:1]
			p.Pages[1] = p.Pages[1][:1]
		},
		"page_full": func(p *Payload) {
			// 5 small widgets would be needed; instead fill one page with 25 one-cell icons
			all := append([]string{}, p.Dock...)
			all = append(all, p.Pages[0][1:]...)
			for _, x := range p.Folders[fid].Pages {
				all = append(all, x...)
			}
			all = append(all, p.Pages[1][1]) // 2 + 2 + 12 + 1 = 17 cells
			p.Dock = nil
			p.Folders[fid] = Folder{Name: "Tools", Pages: nil}
			p.Pages = [][]string{append(append([]string{}, all...), p.Pages[1][0], p.Pages[0][0])} // + widget (4) = 21 + folder
			p.Pages[0] = append(p.Pages[0], p.Pages[0]...)                                         // duplicates trip first
		},
	}
	for code, mutate := range cases {
		p := payload(v)
		mutate(&p)
		_, err := s.Build(p)
		if err == nil {
			t.Errorf("%s: expected an error", code)
			continue
		}
		if code == "page_full" {
			continue // built to fail; the exact rule is covered by TestPageCapacity
		}
		if !strings.HasPrefix(err.Error(), code) {
			t.Errorf("%s: got %v", code, err)
		}
	}
}

func TestPageCapacity(t *testing.T) {
	m := device.DefaultMetrics
	raw := []any{[]any{}}
	page := []any{widget("small")} // 4 cells
	for i := 0; i < 21; i++ {      // + 21 = 25 > 24
		page = append(page, app("app"+string(rune('a'+i))))
	}
	raw = append(raw, page)
	s := &Session{}
	v := s.Load(raw, m)
	_, err := s.Build(payload(v))
	if err == nil || !strings.HasPrefix(err.Error(), "page_full|1|25|24") {
		t.Fatalf("got %v", err)
	}
}

func TestWidgetSlots(t *testing.T) {
	m := device.DefaultMetrics
	for size, want := range map[string]int{"small": 4, "medium": 8, "large": 16} {
		if got := WidgetSlots(size, m); got != want {
			t.Errorf("%s = %d, want %d", size, got, want)
		}
	}
}
