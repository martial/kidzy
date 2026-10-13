// Command kidzy runs the Kidzy media server: catalogue, ingest, API, Bonjour
// and the embedded admin, as one process on the family Mac.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"maps"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"kidzy/server/internal/api"
	"kidzy/server/internal/bonjour"
	"kidzy/server/internal/config"
	"kidzy/server/internal/ingest"
	"kidzy/server/internal/jobs"
	"kidzy/server/internal/sources"
	"kidzy/server/internal/store"
	"kidzy/server/internal/watch"
)

// version is set at build time (-ldflags "-X main.version=...").
var version = "dev"

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "kidzy:", err)
		os.Exit(1)
	}
}

func run() error {
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Parse()
	if *showVersion {
		fmt.Println(version)
		return nil
	}
	level := slog.LevelInfo
	if os.Getenv("KIDZY_DEBUG") != "" {
		level = slog.LevelDebug
	}
	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
	cfg := config.Load(version)
	for _, d := range []string{cfg.DataDir, cfg.StagingDir(), cfg.InboxDir(), cfg.LibraryDir()} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}
	st, err := store.Open(cfg.DBPath())
	if err != nil {
		return err
	}
	defer st.Close()
	serverID, _ := st.Setting("server_id")

	pipe := &ingest.Pipeline{Cfg: cfg, Store: st, Log: log}
	deps := sources.Deps{Cfg: cfg, Store: st, Log: log, Ingest: pipe}
	runners := map[string]jobs.Runner{ingest.Kind: pipe.Run}
	var enabled []sources.Source
	for _, src := range sources.All() {
		if cfg.SourceEnabled(src.ID()) {
			enabled = append(enabled, src)
			maps.Copy(runners, src.Runners(deps))
			log.Info("source enabled", "id", src.ID())
		}
	}
	if len(sources.All()) > 0 && len(enabled) == 0 {
		log.Info("sources present but none enabled: set KIDZY_SOURCES in ~/.config/kidzy/kidzy.env")
	}
	worker := &jobs.Worker{Store: st, Runners: runners, Log: log, Timeout: 6 * time.Hour}
	srv := &api.Server{Cfg: cfg, Store: st, Worker: worker, Ingest: pipe, Log: log, Sources: enabled, Deps: deps, Started: time.Now()}
	name := srv.Name()
	watcher := &watch.Watcher{Dir: cfg.InboxDir(), Log: log, OnFile: srv.ImportInbox}
	txt := map[string]string{"id": serverID, "path": "/api", "v": version, "port": cfg.Port()}
	if h := bonjour.LocalHostname(); h != "" {
		txt["host"] = h // the phone builds its URLs from this, no address resolution needed
	}
	adv := bonjour.New(name, cfg.Port(), txt, log)
	srv.NameChanged = adv.SetName

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go worker.Run(ctx)
	go func() {
		if err := watcher.Run(ctx); err != nil {
			log.Error("inbox watcher stopped", "err", err)
		}
	}()
	go adv.Run(ctx)
	go maintenance(ctx, st)

	httpSrv := &http.Server{Addr: cfg.Addr, Handler: srv.Handler(), ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 2 * time.Minute}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = httpSrv.Shutdown(shutdownCtx)
	}()
	log.Info("kidzy listening", "version", version, "addr", cfg.Addr, "media", cfg.MediaDir, "data", cfg.DataDir, "ffmpeg", cfg.FFmpeg, "name", name)
	if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	log.Info("kidzy stopped")
	return nil
}

// maintenance prunes what grows: sessions, old jobs, old playback events.
func maintenance(ctx context.Context, st *store.Store) {
	t := time.NewTicker(time.Hour)
	defer t.Stop()
	for {
		st.PurgeSessions()
		st.PruneJobs(7 * 24 * time.Hour)
		st.PrunePlayback(90)
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}
