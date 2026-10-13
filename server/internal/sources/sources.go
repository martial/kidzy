// Package sources is the seam for ways of adding videos beyond the upload and
// the inbox folder. A source registers itself at init; main enables the ones
// KIDZY_SOURCES allows. On the public branch nothing is registered.
package sources

import (
	"context"
	"log/slog"
	"net/http"

	"kidzy/server/internal/config"
	"kidzy/server/internal/ingest"
	"kidzy/server/internal/jobs"
	"kidzy/server/internal/store"
)

// Deps is what a source may use.
type Deps struct {
	Cfg    config.Config
	Store  *store.Store
	Log    *slog.Logger
	Ingest *ingest.Pipeline
}

// Source is a plugin: its own admin routes, job kinds and status line.
type Source interface {
	// ID is a short stable identifier, e.g. "youtube".
	ID() string
	// Label is shown in the admin.
	Label() string
	// Routes registers the source's routes; admin wraps a handler with the admin session check.
	Routes(mux *http.ServeMux, deps Deps, admin func(http.HandlerFunc) http.Handler)
	// Runners are the job kinds the source needs the worker to run.
	Runners(deps Deps) map[string]jobs.Runner
	// Status is shown on the admin status page.
	Status(ctx context.Context, deps Deps) map[string]any
}

var registry []Source

// Register adds a source (called from an init function).
func Register(s Source) { registry = append(registry, s) }

// All lists the registered sources.
func All() []Source { return registry }
