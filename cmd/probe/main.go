// Command probe is a read-only self test against the connected iPhone:
// it never writes to the device.
package main

import (
	"fmt"
	"os"
	"reflect"

	"howett.net/plist"

	"github.com/pasqualesimonetti/easy-icon-arranger/internal/device"
	"github.com/pasqualesimonetti/easy-icon-arranger/internal/layout"
)

func main() {
	d := device.New()
	defer d.Disconnect()
	info, err := d.Info()
	check("info", err)
	fmt.Printf("device: %s, iOS %s, %s, class %s, usb=%v\n", info.Name, info.IOS, info.Model, info.Class, info.USB)
	m, err := d.Metrics()
	check("metrics", err)
	fmt.Printf("metrics: %+v\n", m)
	if len(os.Args) > 1 && os.Args[1] == "-write-same" {
		writeSame(d, m)
		return
	}
	raw, err := d.IconState()
	check("icon state", err)
	fmt.Printf("layout: %d pages + dock, %d entries\n", len(raw)-1, layout.Count(raw))

	// binary plist round trip must be lossless
	b, err := plist.Marshal(raw, plist.BinaryFormat)
	check("marshal", err)
	var back []any
	_, err = plist.Unmarshal(b, &back)
	check("unmarshal", err)
	fmt.Println("plist round trip identical:", reflect.DeepEqual(raw, back))
	var diffs []string
	firstDiffs(raw, back, "", &diffs, 6)
	for _, d := range diffs {
		fmt.Println("  diff", d)
	}

	// model round trip: view -> payload -> raw must give the same layout
	s := &layout.Session{}
	v := s.Load(raw, m)
	p := layout.Payload{Dock: v.Dock, Pages: v.Pages, Folders: v.Folders, Sig: v.Sig}
	rebuilt, err := s.Build(p)
	check("build", err)
	fmt.Println("model round trip same signature:", layout.Signature(rebuilt) == layout.Signature(raw))
	fmt.Println("model round trip deep equal:", reflect.DeepEqual(rebuilt, raw))
	diffs = nil
	firstDiffs(raw, rebuilt, "", &diffs, 6)
	for _, d := range diffs {
		fmt.Println("  diff", d)
	}
	for i, pg := range v.Pages {
		fmt.Printf("page %d: %d entries\n", i+1, len(pg))
	}
	if len(v.Pages) < 4 {
		return
	}

	// validation must reject a missing app and an overfull page
	p2 := layout.Payload{Dock: v.Dock, Pages: [][]string{v.Pages[0][:len(v.Pages[0])-1]}, Folders: v.Folders}
	p2.Pages = append(p2.Pages, v.Pages[1:]...)
	_, err = s.Build(p2)
	fmt.Println("missing app rejected:", err)
	over := append(append([]string{}, v.Pages[0]...), v.Pages[2]...)
	p3 := layout.Payload{Dock: v.Dock, Pages: [][]string{over, v.Pages[1], v.Pages[3]}, Folders: v.Folders}
	_, err = s.Build(p3)
	fmt.Println("overfull page rejected:", err)

	png, err := d.IconPNG("com.apple.mobilephone")
	check("icon", err)
	fmt.Printf("icon: %d bytes\n", len(png))
}

func check(what string, err error) {
	if err != nil {
		fmt.Printf("%s: ERROR %v\n", what, err)
		os.Exit(1)
	}
}
