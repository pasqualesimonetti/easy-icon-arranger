package store

import (
	"os"
	"path/filepath"
	"testing"
)

func TestBackupFile(t *testing.T) {
	dir := t.TempDir()
	s := &Store{Backups: dir}
	good := "20261125_120000_before-save.plist"
	if err := os.WriteFile(filepath.Join(dir, good), []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if p, err := s.BackupFile(good); err != nil || p != filepath.Join(dir, good) {
		t.Fatalf("good name: %q %v", p, err)
	}
	for _, bad := range []string{
		"missing.plist",
		"../settings.json",
		"../../etc/passwd.plist",
		"sub/" + good,
		".hidden.plist",
		"notes.txt",
		"",
	} {
		if _, err := s.BackupFile(bad); err == nil {
			t.Errorf("%q should be refused", bad)
		}
	}
}
