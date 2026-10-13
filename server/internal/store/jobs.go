package store

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// Job is a unit of background work (ingest, or a source plugin's own kinds).
type Job struct {
	ID       string          `json:"id"`
	Kind     string          `json:"kind"`
	Params   json.RawMessage `json:"params"`
	Status   string          `json:"status"` // queued | running | done | failed | cancelled | interrupted
	Log      string          `json:"log"`
	Progress float64         `json:"progress"`
	Stage    string          `json:"stage"`
	ItemID   string          `json:"itemId"`
	Created  int64           `json:"created"`
	Started  int64           `json:"started"`
	Finished int64           `json:"finished"`
	Cancel   bool            `json:"cancel"`
	Dedup    string          `json:"-"`
}

const jobCols = "id,kind,params,status,log,progress,stage,item_id,created,started,finished,cancel,COALESCE(dedup,'')"

func scanJob(row interface{ Scan(...any) error }) (Job, error) {
	var j Job
	var params string
	var cancel int
	err := row.Scan(&j.ID, &j.Kind, &params, &j.Status, &j.Log, &j.Progress, &j.Stage, &j.ItemID, &j.Created, &j.Started, &j.Finished, &cancel, &j.Dedup)
	if errors.Is(err, sql.ErrNoRows) {
		return j, ErrNotFound
	}
	j.Params = json.RawMessage(params)
	j.Cancel = cancel == 1
	return j, err
}

// Enqueue adds a queued job. A non-empty dedup key refuses a second queued or
// running job with the same key (partial unique index active_job).
func (s *Store) Enqueue(kind string, params any, dedup, itemID string) (string, error) {
	b, err := json.Marshal(params)
	if err != nil {
		return "", err
	}
	id := NewID()
	_, err = s.DB.Exec("INSERT INTO jobs(id,kind,params,status,item_id,created,dedup) VALUES(?,?,?,'queued',?,?,?)",
		id, kind, string(b), itemID, Now(), nullIfEmpty(dedup))
	if err != nil {
		return "", fmt.Errorf("job already queued or running: %w", err)
	}
	return id, nil
}

// Claim takes the oldest queued job and marks it running.
func (s *Store) Claim() (Job, error) {
	return scanJob(s.DB.QueryRow("UPDATE jobs SET status='running',started=? WHERE id=(SELECT id FROM jobs WHERE status='queued' AND cancel=0 ORDER BY created LIMIT 1) RETURNING "+jobCols, Now()))
}

// Job returns one job.
func (s *Store) Job(id string) (Job, error) {
	return scanJob(s.DB.QueryRow("SELECT "+jobCols+" FROM jobs WHERE id=?", id))
}

// Jobs lists running and queued jobs first, then the most recent finished ones.
func (s *Store) Jobs(limit int) ([]Job, error) {
	rows, err := s.DB.Query("SELECT "+jobCols+" FROM jobs ORDER BY CASE status WHEN 'running' THEN 0 WHEN 'queued' THEN 1 ELSE 2 END, created DESC LIMIT ?", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Job{}
	for rows.Next() {
		j, err := scanJob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	return out, rows.Err()
}

// JobLog appends a timestamped line to a job's log, keeping the last 24 kB.
func (s *Store) JobLog(id, line string) {
	line = strings.TrimRight(line, "\r\n")
	if len(line) > 2000 {
		line = line[:2000]
	}
	_, _ = s.DB.Exec("UPDATE jobs SET log=substr(log || ?, -24000) WHERE id=?", time.Now().Format("15:04:05")+"  "+line+"\n", id)
}

// JobProgress records the current stage and percentage.
func (s *Store) JobProgress(id, stage string, pct float64) {
	_, _ = s.DB.Exec("UPDATE jobs SET stage=?,progress=? WHERE id=?", stage, pct, id)
}

// FinishJob closes a job with a final status.
func (s *Store) FinishJob(id, status string) {
	_, _ = s.DB.Exec("UPDATE jobs SET status=?,finished=? WHERE id=?", status, Now(), id)
}

// CancelJob flags a job; a queued one is cancelled at once, a running one is
// stopped by the worker.
func (s *Store) CancelJob(id string) error {
	_, err := s.DB.Exec("UPDATE jobs SET cancel=1,status=CASE WHEN status='queued' THEN 'cancelled' ELSE status END,finished=CASE WHEN status='queued' THEN ? ELSE finished END WHERE id=? AND status IN ('queued','running')", Now(), id)
	return err
}

// JobCancelled says whether a cancel was requested.
func (s *Store) JobCancelled(id string) bool {
	var c int
	_ = s.DB.QueryRow("SELECT cancel FROM jobs WHERE id=?", id).Scan(&c)
	return c == 1
}

// RecoverInterrupted marks jobs left running by a previous process.
func (s *Store) RecoverInterrupted() (int64, error) {
	res, err := s.DB.Exec("UPDATE jobs SET status='interrupted',finished=? WHERE status='running'", Now())
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

// PruneJobs deletes finished jobs older than the given age, keeping the list short.
func (s *Store) PruneJobs(olderThan time.Duration) {
	_, _ = s.DB.Exec("DELETE FROM jobs WHERE status NOT IN ('queued','running') AND finished < ?", time.Now().Add(-olderThan).UnixMilli())
}
