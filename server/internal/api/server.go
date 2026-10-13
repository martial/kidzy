// Package api is the HTTP surface: a small Plex-like catalogue API for the
// phone (device token), a parent area (PIN session), and the admin API behind
// a cookie session with CSRF, plus the embedded admin page.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"kidzy/server/internal/auth"
	"kidzy/server/internal/config"
	"kidzy/server/internal/ingest"
	"kidzy/server/internal/jobs"
	"kidzy/server/internal/sources"
	"kidzy/server/internal/store"
	"kidzy/server/internal/web"
)

// Server holds the dependencies of every handler.
type Server struct {
	Cfg     config.Config
	Store   *store.Store
	Worker  *jobs.Worker
	Ingest  *ingest.Pipeline
	Log     *slog.Logger
	Sources []sources.Source
	Deps    sources.Deps
	Started time.Time
	// NameChanged is called with the new name when the parent renames the server.
	NameChanged func(string)

	limiter *auth.Limiter
}

// Name is the name shown everywhere: the parent's setting, else the config.
func (s *Server) Name() string {
	if v, ok := s.Store.Setting("server_name"); ok && strings.TrimSpace(v) != "" {
		return v
	}
	return s.Cfg.Name
}

type ctxKey int

const (
	ctxDevice ctxKey = iota
	ctxSession
)

const (
	adminCookie  = "kidzy_admin"
	adminTTL     = 12 * time.Hour
	parentTTL    = 10 * time.Minute
	maxJSONBytes = 1 << 20
)

// Handler builds the router.
func (s *Server) Handler() http.Handler {
	s.limiter = auth.NewLimiter(6, time.Minute)
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("GET /api/identity", s.identity)
	mux.HandleFunc("POST /api/pair", s.pair)

	mux.Handle("GET /api/collections", s.device(s.collections))
	mux.Handle("GET /api/collections/{id}", s.device(s.collection))
	mux.Handle("GET /api/collections/{id}/poster", s.device(s.poster))
	mux.Handle("GET /api/items/{id}", s.device(s.item))
	mux.Handle("GET /api/items/{id}/video", s.device(s.video))
	mux.Handle("GET /api/items/{id}/thumb", s.device(s.thumb))
	mux.Handle("GET /api/finished-image", s.device(s.finishedImage))
	mux.Handle("GET /api/hubs", s.device(s.hubs))
	mux.Handle("GET /api/limits", s.device(s.limitsGet))
	mux.Handle("POST /api/timeline", s.device(s.timeline))
	mux.Handle("POST /api/parent/unlock", s.device(s.parentUnlock))

	mux.Handle("GET /api/settings", s.parent(s.settingsGet))
	mux.Handle("PUT /api/settings", s.parent(s.settingsPut))
	mux.Handle("POST /api/settings/pin", s.parent(s.pinSet))

	mux.HandleFunc("POST /api/admin/setup", s.adminSetup)
	mux.HandleFunc("POST /api/admin/login", s.adminLogin)
	mux.HandleFunc("GET /api/admin/session", s.adminSession)
	mux.Handle("POST /api/admin/logout", s.admin(s.adminLogout))
	mux.Handle("GET /api/admin/status", s.admin(s.adminStatus))
	mux.Handle("GET /api/admin/library", s.admin(s.adminLibrary))
	mux.Handle("POST /api/admin/collections", s.admin(s.collectionCreate))
	mux.Handle("PUT /api/admin/collections/order", s.admin(s.collectionsOrder))
	mux.Handle("PUT /api/admin/collections/{id}", s.admin(s.collectionUpdate))
	mux.Handle("DELETE /api/admin/collections/{id}", s.admin(s.collectionDelete))
	mux.Handle("POST /api/admin/collections/{id}/poster", s.admin(s.collectionPoster))
	mux.Handle("GET /api/admin/collections/{id}/poster", s.admin(s.poster))
	mux.Handle("PUT /api/admin/items/order", s.admin(s.itemsOrder))
	mux.Handle("PUT /api/admin/items/{id}", s.admin(s.itemUpdate))
	mux.Handle("DELETE /api/admin/items/{id}", s.admin(s.itemDelete))
	mux.Handle("POST /api/admin/items/{id}/thumb", s.admin(s.itemThumb))
	mux.Handle("GET /api/admin/items/{id}/thumb", s.admin(s.thumb))
	mux.Handle("GET /api/admin/items/{id}/video", s.admin(s.video))
	mux.Handle("POST /api/admin/items/{id}/retry", s.admin(s.itemRetry))
	mux.Handle("POST /api/admin/upload", s.admin(s.upload))
	mux.Handle("GET /api/admin/jobs", s.admin(s.jobsList))
	mux.Handle("POST /api/admin/jobs/{id}/cancel", s.admin(s.jobCancel))
	mux.Handle("GET /api/admin/events", s.admin(s.events))
	mux.Handle("GET /api/admin/settings", s.admin(s.settingsGet))
	mux.Handle("PUT /api/admin/settings", s.admin(s.settingsPut))
	mux.Handle("POST /api/admin/settings/pin", s.admin(s.pinSet))
	mux.Handle("GET /api/admin/finished-image", s.admin(s.finishedImage))
	mux.Handle("POST /api/admin/finished-image", s.admin(s.finishedImageSet))
	mux.Handle("DELETE /api/admin/finished-image", s.admin(s.finishedImageDelete))
	mux.Handle("GET /api/admin/devices", s.admin(s.devices))
	mux.Handle("DELETE /api/admin/devices/{id}", s.admin(s.deviceRevoke))
	mux.Handle("GET /api/admin/sources", s.admin(s.sourcesList))
	for _, src := range s.Sources {
		src.Routes(mux, s.Deps, s.admin)
	}

	mux.Handle("/admin/", web.Handler())
	mux.HandleFunc("GET /admin", func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, "/admin/", http.StatusFound) })
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, "/admin/", http.StatusFound) })
	return s.logged(mux)
}

// ---------- helpers ----------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func fail(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func decode(r *http.Request, v any) error {
	body, err := io.ReadAll(io.LimitReader(r.Body, maxJSONBytes))
	if err != nil {
		return err
	}
	if len(strings.TrimSpace(string(body))) == 0 {
		return errors.New("empty body")
	}
	return json.Unmarshal(body, v)
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func (s *Server) rateLimited(w http.ResponseWriter, r *http.Request) bool {
	if !s.limiter.Allow(clientIP(r)) || !s.limiter.Allow("*") {
		fail(w, http.StatusTooManyRequests, "trop d'essais, attendez une minute")
		return true
	}
	return false
}

func (s *Server) pinHash() (string, bool) { return s.Store.Setting("pin_hash") }

func (s *Server) checkPIN(pin string) bool {
	h, ok := s.pinHash()
	return ok && auth.VerifyPIN(h, pin)
}

func sameOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		origin = r.Header.Get("Referer")
	}
	if origin == "" {
		return true // same-site requests from the SPA always carry one; tools without it are fine on the LAN
	}
	u, err := url.Parse(origin)
	if err != nil {
		return false
	}
	return strings.EqualFold(u.Host, r.Host)
}

// device requires a paired device token (header or ?token=).
func (s *Server) device(h http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		d, ok := s.deviceFrom(r)
		if !ok {
			fail(w, http.StatusUnauthorized, "appareil non appairé")
			return
		}
		h(w, r.WithContext(context.WithValue(r.Context(), ctxDevice, d)))
	})
}

func (s *Server) deviceFrom(r *http.Request) (store.Device, bool) {
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if token == "" || token == r.Header.Get("Authorization") {
		token = r.URL.Query().Get("token")
	}
	if token == "" {
		return store.Device{}, false
	}
	d, err := s.Store.DeviceByToken(auth.HashToken(token))
	return d, err == nil
}

func deviceOf(r *http.Request) store.Device {
	d, _ := r.Context().Value(ctxDevice).(store.Device)
	return d
}

// parent accepts an admin session or a device with a live parent token.
func (s *Server) parent(h http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := s.adminSessionFrom(r); ok {
			h(w, r)
			return
		}
		d, ok := s.deviceFrom(r)
		if !ok {
			fail(w, http.StatusUnauthorized, "appareil non appairé")
			return
		}
		tok := r.Header.Get("X-Parent-Token")
		if tok == "" {
			tok = r.URL.Query().Get("parent")
		}
		sess, err := s.Store.SessionByToken(auth.HashToken(tok), "parent")
		if err != nil || sess.DeviceID != d.ID {
			fail(w, http.StatusUnauthorized, "code parent requis")
			return
		}
		h(w, r.WithContext(context.WithValue(r.Context(), ctxDevice, d)))
	})
}

func (s *Server) adminSessionFrom(r *http.Request) (store.Session, bool) {
	c, err := r.Cookie(adminCookie)
	if err != nil || c.Value == "" {
		return store.Session{}, false
	}
	sess, err := s.Store.SessionByToken(auth.HashToken(c.Value), "admin")
	return sess, err == nil
}

// admin requires the admin cookie, and a CSRF token on writes.
func (s *Server) admin(h http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sess, ok := s.adminSessionFrom(r)
		if !ok {
			fail(w, http.StatusUnauthorized, "connexion requise")
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			if r.Header.Get("X-CSRF-Token") != sess.CSRF || !sameOrigin(r) {
				fail(w, http.StatusForbidden, "jeton de session invalide, rechargez la page")
				return
			}
		}
		h(w, r.WithContext(context.WithValue(r.Context(), ctxSession, sess)))
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (sw *statusWriter) WriteHeader(code int) {
	sw.status = code
	sw.ResponseWriter.WriteHeader(code)
}

// Flush lets SSE through the wrapper.
func (sw *statusWriter) Flush() {
	if f, ok := sw.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (s *Server) logged(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sw := &statusWriter{ResponseWriter: w, status: 200}
		start := time.Now()
		next.ServeHTTP(sw, r)
		if sw.status >= 400 && sw.status != 401 && sw.status != 404 {
			s.Log.Warn("http", "method", r.Method, "path", r.URL.Path, "status", sw.status, "ms", time.Since(start).Milliseconds(), "ip", clientIP(r))
		} else {
			s.Log.Debug("http", "method", r.Method, "path", r.URL.Path, "status", sw.status, "ms", time.Since(start).Milliseconds())
		}
	})
}
