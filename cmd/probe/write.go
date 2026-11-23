package main

import (
	"fmt"
	"os"

	"github.com/pasqualesimonetti/easy-icon-arranger/internal/device"
	"github.com/pasqualesimonetti/easy-icon-arranger/internal/layout"
	"github.com/pasqualesimonetti/easy-icon-arranger/internal/store"
)

// writeSame backs up the layout, writes back the identical layout rebuilt from
// the model, and checks that the device reports the same layout afterwards.
func writeSame(d *device.Device, m device.Metrics) {
	raw, err := d.IconState()
	check("read", err)
	st, err := store.New()
	check("store", err)
	name, err := st.SaveBackup(raw, "before-write-test")
	check("backup", err)
	fmt.Println("backup:", name)

	s := &layout.Session{}
	v := s.Load(raw, m)
	rebuilt, err := s.Build(layout.Payload{Dock: v.Dock, Pages: v.Pages, Folders: v.Folders, Sig: v.Sig})
	check("build", err)
	if layout.Signature(rebuilt) != layout.Signature(raw) {
		fmt.Println("rebuilt layout differs: not writing")
		os.Exit(1)
	}
	check("write", d.SetIconState(rebuilt))
	after, err := d.IconState()
	check("read after", err)
	fmt.Println("write accepted, layout unchanged:", layout.Signature(after) == layout.Signature(raw))
}
