// Package l10ncheck verifies the interface translations in macos/Localization:
// every file must be valid JSON, use only keys that exist in en.json and keep
// the same {n} placeholders as the English text.
package l10ncheck

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

const dir = "../../macos/Localization"

var placeholder = regexp.MustCompile(`\{\d+\}`)

func load(t *testing.T, path string) map[string]string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]string
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("%s: %v", path, err)
	}
	return m
}

func placeholders(s string) string {
	p := placeholder.FindAllString(s, -1)
	sort.Strings(p)
	return strings.Join(p, ",")
}

func TestTranslations(t *testing.T) {
	en := load(t, filepath.Join(dir, "en.json"))
	files, _ := filepath.Glob(filepath.Join(dir, "*.json"))
	if len(files) < 2 {
		t.Fatal("no translations found")
	}
	for _, f := range files {
		code := strings.TrimSuffix(filepath.Base(f), ".json")
		if code == "en" {
			continue
		}
		tr := load(t, f)
		for k, v := range tr {
			ref, ok := en[k]
			if !ok {
				t.Errorf("%s: unknown key %q", code, k)
				continue
			}
			if strings.TrimSpace(v) == "" {
				t.Errorf("%s: empty text for %q", code, k)
			}
			if placeholders(v) != placeholders(ref) {
				t.Errorf("%s: %q has placeholders %q, English has %q", code, k, placeholders(v), placeholders(ref))
			}
		}
		if missing := len(en) - len(tr); missing > 0 {
			t.Logf("%s: %d strings fall back to English", code, missing)
		}
	}
}
