package store

import (
	"database/sql"
	"errors"
)

// Device is a paired phone.
type Device struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Created  int64  `json:"created"`
	LastSeen int64  `json:"lastSeen"`
	Revoked  bool   `json:"revoked"`
}

// Session is a parent (10 min, in the app) or admin (browser) session.
type Session struct {
	TokenHash string
	Kind      string // parent | admin
	DeviceID  string
	CSRF      string
	Expires   int64
}

// PlaybackEvent is what the app reports while a video plays.
type PlaybackEvent struct {
	DeviceID  string
	ItemID    string
	SessionID string
	State     string // playing | paused | stopped | ended
	Position  float64
	Delta     float64 // seconds of watching credited by this event
	At        int64
	Day       string // local date YYYY-MM-DD
}

// InsertDevice pairs a device.
func (s *Store) InsertDevice(name, tokenHash string) (Device, error) {
	d := Device{ID: NewID(), Name: name, Created: Now(), LastSeen: Now()}
	_, err := s.DB.Exec("INSERT INTO devices(id,name,token_hash,created,last_seen) VALUES(?,?,?,?,?)", d.ID, d.Name, tokenHash, d.Created, d.LastSeen)
	return d, err
}

// DeviceByToken finds a live device by its token hash and updates last_seen.
func (s *Store) DeviceByToken(tokenHash string) (Device, error) {
	var d Device
	var revoked int
	err := s.DB.QueryRow("SELECT id,name,created,last_seen,revoked FROM devices WHERE token_hash=?", tokenHash).Scan(&d.ID, &d.Name, &d.Created, &d.LastSeen, &revoked)
	if errors.Is(err, sql.ErrNoRows) || revoked == 1 {
		return d, ErrNotFound
	}
	if err == nil {
		_, _ = s.DB.Exec("UPDATE devices SET last_seen=? WHERE id=?", Now(), d.ID)
	}
	return d, err
}

// Devices lists every device, live ones first.
func (s *Store) Devices() ([]Device, error) {
	rows, err := s.DB.Query("SELECT id,name,created,last_seen,revoked FROM devices ORDER BY revoked, created DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Device{}
	for rows.Next() {
		var d Device
		var revoked int
		if err := rows.Scan(&d.ID, &d.Name, &d.Created, &d.LastSeen, &revoked); err != nil {
			return nil, err
		}
		d.Revoked = revoked == 1
		out = append(out, d)
	}
	return out, rows.Err()
}

// RevokeDevice unpairs a device and ends its parent sessions.
func (s *Store) RevokeDevice(id string) error {
	if _, err := s.DB.Exec("UPDATE devices SET revoked=1 WHERE id=?", id); err != nil {
		return err
	}
	_, err := s.DB.Exec("DELETE FROM sessions WHERE device_id=?", id)
	return err
}

// InsertSession stores a session.
func (s *Store) InsertSession(sess Session) error {
	_, err := s.DB.Exec("INSERT INTO sessions(token_hash,kind,device_id,csrf,expires) VALUES(?,?,?,?,?)", sess.TokenHash, sess.Kind, sess.DeviceID, sess.CSRF, sess.Expires)
	return err
}

// SessionByToken returns a live session of the given kind.
func (s *Store) SessionByToken(tokenHash, kind string) (Session, error) {
	var sess Session
	err := s.DB.QueryRow("SELECT token_hash,kind,device_id,csrf,expires FROM sessions WHERE token_hash=? AND kind=? AND expires>?", tokenHash, kind, Now()).
		Scan(&sess.TokenHash, &sess.Kind, &sess.DeviceID, &sess.CSRF, &sess.Expires)
	if errors.Is(err, sql.ErrNoRows) {
		return sess, ErrNotFound
	}
	return sess, err
}

// DeleteSession ends a session.
func (s *Store) DeleteSession(tokenHash string) {
	_, _ = s.DB.Exec("DELETE FROM sessions WHERE token_hash=?", tokenHash)
}

// PurgeSessions drops expired sessions.
func (s *Store) PurgeSessions() {
	_, _ = s.DB.Exec("DELETE FROM sessions WHERE expires<=?", Now())
}

// AddPlayback records a playback event.
func (s *Store) AddPlayback(e PlaybackEvent) error {
	_, err := s.DB.Exec("INSERT INTO playback_events(device_id,item_id,session_id,state,position,delta,at,day) VALUES(?,?,?,?,?,?,?,?)",
		e.DeviceID, e.ItemID, e.SessionID, e.State, e.Position, e.Delta, e.At, e.Day)
	return err
}

// LastPlayback returns the previous event of a playback session.
func (s *Store) LastPlayback(sessionID string) (PlaybackEvent, error) {
	var e PlaybackEvent
	err := s.DB.QueryRow("SELECT device_id,item_id,session_id,state,position,delta,at,day FROM playback_events WHERE session_id=? ORDER BY at DESC, id DESC LIMIT 1", sessionID).
		Scan(&e.DeviceID, &e.ItemID, &e.SessionID, &e.State, &e.Position, &e.Delta, &e.At, &e.Day)
	if errors.Is(err, sql.ErrNoRows) {
		return e, ErrNotFound
	}
	return e, err
}

// WatchedSeconds sums the watching credited on a local day, all devices.
func (s *Store) WatchedSeconds(day string) float64 {
	var v sql.NullFloat64
	_ = s.DB.QueryRow("SELECT SUM(delta) FROM playback_events WHERE day=?", day).Scan(&v)
	return v.Float64
}

// PrunePlayback deletes events older than the given number of days.
func (s *Store) PrunePlayback(keepDays int) {
	_, _ = s.DB.Exec("DELETE FROM playback_events WHERE at < ?", Now()-int64(keepDays)*86400000)
}
