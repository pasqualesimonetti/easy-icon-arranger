// Package main builds libeia.a, the Go engine linked into the Swift app.
//
//	go build -buildmode=c-archive -o macos/Vendor/libeia.a ./libeia
//
// Every function returns a malloc'd JSON string {"ok":bool,"data":...,"error":"code|detail"}
// that the caller must release with EIAFree.
package main

// #include <stdlib.h>
import "C"

import (
	"encoding/json"
	"errors"
	"os/exec"
	"sync"
	"unsafe"

	"github.com/pasqualesimonetti/easy-icon-arranger/internal/core"
	"github.com/pasqualesimonetti/easy-icon-arranger/internal/layout"
)

var (
	once    sync.Once
	engine  *core.Core
	initErr error
)

func get() (*core.Core, error) {
	once.Do(func() { engine, initErr = core.New() })
	return engine, initErr
}

type envelope struct {
	OK    bool   `json:"ok"`
	Data  any    `json:"data,omitempty"`
	Error string `json:"error,omitempty"`
}

func reply(v any, err error) *C.char {
	e := envelope{OK: err == nil, Data: v}
	if err != nil {
		e.Data = nil
		e.Error = err.Error()
	}
	b, mErr := json.Marshal(e)
	if mErr != nil {
		b, _ = json.Marshal(envelope{Error: "generic|" + mErr.Error()})
	}
	return C.CString(string(b))
}

func with[T any](fn func(*core.Core) (T, error)) *C.char {
	c, err := get()
	if err != nil {
		return reply(nil, err)
	}
	return reply(fn(c))
}

//export EIAConnect
func EIAConnect() *C.char {
	return with(func(c *core.Core) (*core.Status, error) { return c.Connect() })
}

//export EIALoadLayout
func EIALoadLayout() *C.char {
	return with(func(c *core.Core) (*layout.View, error) { return c.LoadLayout() })
}

//export EIASave
func EIASave(payload *C.char) *C.char {
	return with(func(c *core.Core) (*core.SaveResult, error) {
		var p layout.Payload
		if err := json.Unmarshal([]byte(C.GoString(payload)), &p); err != nil {
			return nil, errors.New("generic|" + err.Error())
		}
		return c.Save(p)
	})
}

//export EIAListBackups
func EIAListBackups() *C.char {
	return with(func(c *core.Core) (any, error) { return c.Backups(), nil })
}

//export EIARestore
func EIARestore(name *C.char) *C.char {
	return with(func(c *core.Core) (*core.SaveResult, error) { return c.Restore(C.GoString(name)) })
}

//export EIARevealBackups
func EIARevealBackups() *C.char {
	return with(func(c *core.Core) (any, error) { return nil, exec.Command("open", c.BackupsDir()).Start() })
}

// EIAIconPath returns a plain path string ("" if unavailable), also to be freed.
//
//export EIAIconPath
func EIAIconPath(key *C.char) *C.char {
	c, err := get()
	if err != nil {
		return C.CString("")
	}
	return C.CString(c.IconPath(C.GoString(key)))
}

//export EIAShutdown
func EIAShutdown() {
	if c, err := get(); err == nil {
		c.Close()
	}
}

//export EIAFree
func EIAFree(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}
