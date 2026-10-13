// Package store is the SQLite catalogue: collections, items, media files,
// jobs, playback events, settings, devices and sessions. One file, WAL mode,
// a single connection, migrations by CREATE IF NOT EXISTS.
package store

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"

	_ "modernc.org/sqlite"
)

// Store wraps the database.
type Store struct {
	DB *sql.DB
}

// Open creates the directory and the database if needed and migrates it.
func Open(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	dsn := "file:" + path + "?_pragma=busy_timeout(10000)&_pragma=journal_mode(WAL)&_pragma=foreign_keys(ON)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	s := &Store{DB: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

// Close closes the database.
func (s *Store) Close() error { return s.DB.Close() }

func (s *Store) migrate() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS collections(
			id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'show',
			color TEXT NOT NULL DEFAULT '', sort_order INTEGER NOT NULL DEFAULT 0,
			poster_path TEXT NOT NULL DEFAULT '', visible INTEGER NOT NULL DEFAULT 1,
			created INTEGER NOT NULL, updated INTEGER NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS items(
			id TEXT PRIMARY KEY, collection_id TEXT NOT NULL DEFAULT '', title TEXT NOT NULL,
			sort_order INTEGER NOT NULL DEFAULT 0, visible INTEGER NOT NULL DEFAULT 1,
			status TEXT NOT NULL DEFAULT 'importing', duration REAL NOT NULL DEFAULT 0,
			thumb_path TEXT NOT NULL DEFAULT '', thumb_custom INTEGER NOT NULL DEFAULT 0,
			source TEXT NOT NULL DEFAULT 'upload', source_ref TEXT, error TEXT NOT NULL DEFAULT '',
			created INTEGER NOT NULL, updated INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS item_source ON items(source_ref) WHERE source_ref IS NOT NULL AND deleted=0`,
		`CREATE TABLE IF NOT EXISTS media(
			id TEXT PRIMARY KEY, item_id TEXT NOT NULL, path TEXT NOT NULL UNIQUE, bytes INTEGER NOT NULL,
			width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0,
			vcodec TEXT NOT NULL DEFAULT '', acodec TEXT NOT NULL DEFAULT '', container TEXT NOT NULL DEFAULT '',
			created INTEGER NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS jobs(
			id TEXT PRIMARY KEY, kind TEXT NOT NULL, params TEXT NOT NULL, status TEXT NOT NULL,
			log TEXT NOT NULL DEFAULT '', progress REAL NOT NULL DEFAULT 0, stage TEXT NOT NULL DEFAULT '',
			item_id TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL, started INTEGER NOT NULL DEFAULT 0,
			finished INTEGER NOT NULL DEFAULT 0, cancel INTEGER NOT NULL DEFAULT 0, dedup TEXT)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS active_job ON jobs(dedup) WHERE status IN ('queued','running')`,
		`CREATE TABLE IF NOT EXISTS playback_events(
			id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, item_id TEXT NOT NULL,
			session_id TEXT NOT NULL, state TEXT NOT NULL, position REAL NOT NULL, delta REAL NOT NULL,
			at INTEGER NOT NULL, day TEXT NOT NULL)`,
		`CREATE INDEX IF NOT EXISTS playback_day ON playback_events(day)`,
		`CREATE INDEX IF NOT EXISTS playback_session ON playback_events(session_id, at)`,
		`CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)`,
		`CREATE TABLE IF NOT EXISTS devices(
			id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE,
			created INTEGER NOT NULL, last_seen INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0)`,
		`CREATE TABLE IF NOT EXISTS sessions(
			token_hash TEXT PRIMARY KEY, kind TEXT NOT NULL, device_id TEXT NOT NULL DEFAULT '',
			csrf TEXT NOT NULL DEFAULT '', expires INTEGER NOT NULL)`,
	}
	for _, q := range stmts {
		if _, err := s.DB.Exec(q); err != nil {
			return fmt.Errorf("migrate: %w", err)
		}
	}
	if _, ok := s.Setting("server_id"); !ok {
		if err := s.SetSetting("server_id", NewID()); err != nil {
			return err
		}
	}
	return nil
}

// NewID returns 24 hex characters from crypto/rand.
func NewID() string {
	b := make([]byte, 12)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// Now is the current time in Unix milliseconds, the unit of every timestamp here.
func Now() int64 { return time.Now().UnixMilli() }

// Setting returns a settings value.
func (s *Store) Setting(key string) (string, bool) {
	var v string
	err := s.DB.QueryRow("SELECT value FROM settings WHERE key=?", key).Scan(&v)
	return v, err == nil
}

// SetSetting writes a settings value.
func (s *Store) SetSetting(key, value string) error {
	_, err := s.DB.Exec("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", key, value)
	return err
}

// DeleteSetting removes a settings value.
func (s *Store) DeleteSetting(key string) error {
	_, err := s.DB.Exec("DELETE FROM settings WHERE key=?", key)
	return err
}

// LibraryVersion is a counter the app and the admin compare to know when to reload.
func (s *Store) LibraryVersion() int64 {
	v, _ := s.Setting("library_version")
	n, _ := strconv.ParseInt(v, 10, 64)
	return n
}

// BumpLibrary increments the library version after any catalogue change.
func (s *Store) BumpLibrary() {
	_ = s.SetSetting("library_version", strconv.FormatInt(s.LibraryVersion()+1, 10))
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func nullIfEmpty(v string) any {
	if v == "" {
		return nil
	}
	return v
}
