package main

import (
	"fmt"
	"reflect"
)

// firstDiffs reports up to n differences between two decoded plist values.
func firstDiffs(a, b any, path string, out *[]string, n int) {
	if len(*out) >= n {
		return
	}
	if reflect.TypeOf(a) != reflect.TypeOf(b) {
		*out = append(*out, fmt.Sprintf("%s: type %T vs %T (%v vs %v)", path, a, b, a, b))
		return
	}
	switch x := a.(type) {
	case map[string]any:
		y := b.(map[string]any)
		for k := range x {
			if _, ok := y[k]; !ok {
				*out = append(*out, path+"/"+k+": missing")
				continue
			}
			firstDiffs(x[k], y[k], path+"/"+k, out, n)
		}
		for k := range y {
			if _, ok := x[k]; !ok {
				*out = append(*out, path+"/"+k+": added")
			}
		}
	case []any:
		y := b.([]any)
		if len(x) != len(y) {
			*out = append(*out, fmt.Sprintf("%s: len %d vs %d", path, len(x), len(y)))
			return
		}
		for i := range x {
			firstDiffs(x[i], y[i], fmt.Sprintf("%s[%d]", path, i), out, n)
		}
	default:
		if !reflect.DeepEqual(a, b) {
			*out = append(*out, fmt.Sprintf("%s: %#v vs %#v", path, a, b))
		}
	}
}
