// Package jobs runs background work from the SQLite queue, one job at a time,
// with cancel, timeout and live progress.
package jobs

import (
	"context"
	"fmt"
	"log/slog"
	"runtime/debug"
	"time"

	"kidzy/server/internal/store"
)

// Runner performs one kind of job.
type Runner func(ctx context.Context, job store.Job, rep *Reporter) error

// Reporter is how a runner logs and reports progress.
type Reporter struct {
	Store *store.Store
	ID    string
	last  time.Time
}

// Log appends a line to the job log.
func (r *Reporter) Log(format string, args ...any) {
	r.Store.JobLog(r.ID, fmt.Sprintf(format, args...))
}

// Progress records the stage and percentage, at most twice a second.
func (r *Reporter) Progress(stage string, pct float64) {
	if pct < 100 && time.Since(r.last) < 500*time.Millisecond {
		return
	}
	r.last = time.Now()
	r.Store.JobProgress(r.ID, stage, pct)
}

// Worker claims and runs jobs.
type Worker struct {
	Store   *store.Store
	Runners map[string]Runner
	Log     *slog.Logger
	Timeout time.Duration
	// Changed is called after a job changes state, so the SSE feed can wake up.
	Changed   func()
	heartbeat time.Time
}

// Online says whether the worker loop ran in the last ten seconds.
func (w *Worker) Online() bool { return time.Since(w.heartbeat) < 10*time.Second }

// Run loops until the context ends.
func (w *Worker) Run(ctx context.Context) {
	if n, _ := w.Store.RecoverInterrupted(); n > 0 {
		w.Log.Warn("jobs left running by a previous process marked interrupted", "count", n)
		w.changed()
	}
	for {
		w.heartbeat = time.Now()
		job, err := w.Store.Claim()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Second):
			}
			continue
		}
		w.changed()
		w.run(ctx, job)
		w.changed()
		if ctx.Err() != nil {
			return
		}
	}
}

func (w *Worker) changed() {
	if w.Changed != nil {
		w.Changed()
	}
}

func (w *Worker) run(parent context.Context, job store.Job) {
	rep := &Reporter{Store: w.Store, ID: job.ID}
	runner, ok := w.Runners[job.Kind]
	if !ok {
		rep.Log("no runner for job kind %q", job.Kind)
		w.Store.FinishJob(job.ID, "failed")
		return
	}
	timeout := w.Timeout
	if timeout == 0 {
		timeout = 6 * time.Hour
	}
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	stop := make(chan struct{})
	go func() {
		t := time.NewTicker(time.Second)
		defer t.Stop()
		for {
			select {
			case <-stop:
				return
			case <-t.C:
				if w.Store.JobCancelled(job.ID) {
					cancel()
					return
				}
			}
		}
	}()
	err := w.safeRun(ctx, runner, job, rep)
	close(stop)
	switch {
	case err == nil:
		rep.Progress(job.Stage, 100)
		w.Store.FinishJob(job.ID, "done")
	case w.Store.JobCancelled(job.ID):
		rep.Log("cancelled")
		w.Store.FinishJob(job.ID, "cancelled")
	case parent.Err() != nil:
		rep.Log("server stopping; the job will be retried")
		w.Store.FinishJob(job.ID, "interrupted")
	default:
		rep.Log("failed: %v", err)
		w.Store.FinishJob(job.ID, "failed")
		w.Log.Error("job failed", "id", job.ID, "kind", job.Kind, "err", err)
	}
}

func (w *Worker) safeRun(ctx context.Context, runner Runner, job store.Job, rep *Reporter) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("panic: %v\n%s", r, debug.Stack())
		}
	}()
	return runner(ctx, job, rep)
}
