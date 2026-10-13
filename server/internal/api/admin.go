package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"kidzy/server/internal/auth"
	"kidzy/server/internal/ingest"
	"kidzy/server/internal/media"
	"kidzy/server/internal/store"
)

// ---------- session ----------

func (s *Server) adminSetup(w http.ResponseWriter, r *http.Request) {
	if s.rateLimited(w, r) {
		return
	}
	if _, set := s.pinHash(); set {
		fail(w, http.StatusConflict, "le code parent existe déjà")
		return
	}
	var in struct {
		PIN string `json:"pin"`
	}
	if err := decode(r, &in); err != nil || !auth.ValidPIN(in.PIN) {
		fail(w, 400, "le code doit faire 4 à 6 chiffres")
		return
	}
	if err := s.savePIN(in.PIN); err != nil {
		fail(w, 500, err.Error())
		return
	}
	s.Log.Info("parent PIN set up")
	s.startAdminSession(w)
}

func (s *Server) adminLogin(w http.ResponseWriter, r *http.Request) {
	if s.rateLimited(w, r) {
		return
	}
	var in struct {
		PIN string `json:"pin"`
	}
	if err := decode(r, &in); err != nil || !s.checkPIN(in.PIN) {
		fail(w, http.StatusForbidden, "code incorrect")
		return
	}
	s.startAdminSession(w)
}

func (s *Server) startAdminSession(w http.ResponseWriter) {
	token, hash := auth.NewToken()
	csrf, _ := auth.NewToken()
	expires := time.Now().Add(adminTTL)
	if err := s.Store.InsertSession(store.Session{TokenHash: hash, Kind: "admin", CSRF: csrf, Expires: expires.UnixMilli()}); err != nil {
		fail(w, 500, err.Error())
		return
	}
	http.SetCookie(w, &http.Cookie{Name: adminCookie, Value: token, Path: "/", HttpOnly: true, SameSite: http.SameSiteLaxMode, Expires: expires})
	writeJSON(w, 200, map[string]any{"ok": true, "csrf": csrf})
}

func (s *Server) adminSession(w http.ResponseWriter, r *http.Request) {
	_, pinSet := s.pinHash()
	sess, ok := s.adminSessionFrom(r)
	out := map[string]any{"ok": ok, "pinSet": pinSet, "name": s.Name(), "version": s.Cfg.Version}
	if ok {
		out["csrf"] = sess.CSRF
	}
	writeJSON(w, 200, out)
}

func (s *Server) adminLogout(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie(adminCookie); err == nil {
		s.Store.DeleteSession(auth.HashToken(c.Value))
	}
	http.SetCookie(w, &http.Cookie{Name: adminCookie, Value: "", Path: "/", HttpOnly: true, MaxAge: -1})
	writeJSON(w, 200, map[string]bool{"ok": true})
}

// ---------- status ----------

func (s *Server) adminStatus(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	ready, importing, failed := s.Store.Counts()
	var st syscall.Statfs_t
	disk := map[string]uint64{}
	if err := syscall.Statfs(s.Cfg.MediaDir, &st); err == nil {
		disk["freeBytes"] = st.Bavail * uint64(st.Bsize)
		disk["totalBytes"] = st.Blocks * uint64(st.Bsize)
	}
	srcs := []map[string]any{}
	for _, src := range s.Sources {
		srcs = append(srcs, map[string]any{"id": src.ID(), "label": src.Label(), "status": src.Status(ctx, s.Deps)})
	}
	devices, _ := s.Store.Devices()
	writeJSON(w, 200, map[string]any{
		"version": s.Cfg.Version, "name": s.Name(), "addr": s.Cfg.Addr, "started": s.Started.Format(time.RFC3339),
		"uptimeSeconds": int(time.Since(s.Started).Seconds()),
		"mediaDir":      s.Cfg.MediaDir, "inboxDir": s.Cfg.InboxDir(), "dataDir": s.Cfg.DataDir,
		"ffmpeg": media.Version(ctx, s.Cfg.FFmpeg), "ffprobe": media.Version(ctx, s.Cfg.FFprobe),
		"workerOnline": s.Worker.Online(),
		"counts":       map[string]int{"ready": ready, "importing": importing, "failed": failed, "devices": len(devices)},
		"disk":         disk, "sources": srcs, "libraryVersion": s.Store.LibraryVersion(),
	})
}

// ---------- library ----------

type adminItem struct {
	store.Item
	ThumbURL string `json:"thumbUrl"`
	VideoURL string `json:"videoUrl"`
	Bytes    int64  `json:"bytes"`
	Width    int    `json:"width"`
	Height   int    `json:"height"`
}

type adminCollection struct {
	store.Collection
	PosterURL string      `json:"posterUrl"`
	Items     []adminItem `json:"items"`
}

func (s *Server) adminItem(it store.Item) adminItem {
	a := adminItem{Item: it}
	if it.ThumbPath != "" {
		a.ThumbURL = "/api/admin/items/" + it.ID + "/thumb?v=" + fmt.Sprint(it.Updated)
	}
	if m, err := s.Store.MediaOf(it.ID); err == nil {
		a.VideoURL = "/api/admin/items/" + it.ID + "/video"
		a.Bytes, a.Width, a.Height = m.Bytes, m.Width, m.Height
	}
	return a
}

func (s *Server) adminLibrary(w http.ResponseWriter, r *http.Request) {
	cols, err := s.Store.Collections()
	if err != nil {
		fail(w, 500, err.Error())
		return
	}
	items, err := s.Store.Items()
	if err != nil {
		fail(w, 500, err.Error())
		return
	}
	byCol := map[string][]adminItem{}
	for _, it := range items {
		byCol[it.CollectionID] = append(byCol[it.CollectionID], s.adminItem(it))
	}
	out := []adminCollection{}
	for _, c := range cols {
		ac := adminCollection{Collection: c, Items: byCol[c.ID]}
		if ac.Items == nil {
			ac.Items = []adminItem{}
		}
		if c.PosterPath != "" {
			ac.PosterURL = "/api/admin/collections/" + c.ID + "/poster?v=" + fmt.Sprint(c.Updated)
		} else if len(ac.Items) > 0 {
			ac.PosterURL = ac.Items[0].ThumbURL
		}
		out = append(out, ac)
	}
	orphans := byCol[""]
	if orphans == nil {
		orphans = []adminItem{}
	}
	writeJSON(w, 200, map[string]any{"collections": out, "orphans": orphans, "libraryVersion": s.Store.LibraryVersion()})
}

func (s *Server) collectionCreate(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Title string `json:"title"`
		Kind  string `json:"kind"`
	}
	if err := decode(r, &in); err != nil || strings.TrimSpace(in.Title) == "" {
		fail(w, 400, "titre requis")
		return
	}
	if in.Kind == "" {
		in.Kind = "show"
	}
	cols, _ := s.Store.Collections()
	c, err := s.Store.InsertCollection(store.Collection{Title: strings.TrimSpace(in.Title), Kind: in.Kind, Color: store.NextColor(len(cols)), Visible: true})
	if err != nil {
		fail(w, 500, err.Error())
		return
	}
	s.Store.BumpLibrary()
	writeJSON(w, 201, c)
}

func (s *Server) collectionUpdate(w http.ResponseWriter, r *http.Request) {
	c, err := s.Store.Collection(r.PathValue("id"))
	if err != nil {
		fail(w, 404, "collection introuvable")
		return
	}
	var in struct {
		Title   *string `json:"title"`
		Kind    *string `json:"kind"`
		Color   *string `json:"color"`
		Visible *bool   `json:"visible"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, 400, "requête invalide")
		return
	}
	if in.Title != nil && strings.TrimSpace(*in.Title) != "" {
		c.Title = strings.TrimSpace(*in.Title)
	}
	if in.Kind != nil {
		c.Kind = *in.Kind
	}
	if in.Color != nil {
		c.Color = *in.Color
	}
	if in.Visible != nil {
		c.Visible = *in.Visible
	}
	if err := s.Store.UpdateCollection(c); err != nil {
		fail(w, 500, err.Error())
		return
	}
	s.Store.BumpLibrary()
	writeJSON(w, 200, c)
}

func (s *Server) collectionDelete(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := s.Store.DeleteCollection(id); err != nil {
		fail(w, 500, err.Error())
		return
	}
	_ = os.RemoveAll(filepath.Dir(s.Ingest.CollectionPosterPath(id)))
	s.Store.BumpLibrary()
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) collectionsOrder(w http.ResponseWriter, r *http.Request) {
	var in struct {
		IDs []string `json:"ids"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, 400, "requête invalide")
		return
	}
	if err := s.Store.OrderCollections(in.IDs); err != nil {
		fail(w, 500, err.Error())
		return
	}
	s.Store.BumpLibrary()
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) collectionPoster(w http.ResponseWriter, r *http.Request) {
	c, err := s.Store.Collection(r.PathValue("id"))
	if err != nil {
		fail(w, 404, "collection introuvable")
		return
	}
	tmp, cleanup, err := s.uploadTemp(w, r, 50<<20)
	if err != nil {
		return
	}
	defer cleanup()
	dst := s.Ingest.CollectionPosterPath(c.ID)
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		fail(w, 500, err.Error())
		return
	}
	if err := media.ResizeImage(r.Context(), s.Cfg.FFmpeg, tmp, dst, ingest.ThumbWidth); err != nil {
		fail(w, 400, "image illisible : "+err.Error())
		return
	}
	c.PosterPath = dst
	if err := s.Store.UpdateCollection(c); err != nil {
		fail(w, 500, err.Error())
		return
	}
	s.Store.BumpLibrary()
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) itemUpdate(w http.ResponseWriter, r *http.Request) {
	it, err := s.Store.Item(r.PathValue("id"))
	if err != nil {
		fail(w, 404, "vidéo introuvable")
		return
	}
	var in struct {
		Title        *string `json:"title"`
		CollectionID *string `json:"collectionId"`
		Visible      *bool   `json:"visible"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, 400, "requête invalide")
		return
	}
	if in.Title != nil && strings.TrimSpace(*in.Title) != "" {
		it.Title = strings.TrimSpace(*in.Title)
	}
	if in.Visible != nil {
		it.Visible = *in.Visible
	}
	moved := false
	if in.CollectionID != nil && *in.CollectionID != it.CollectionID {
		if *in.CollectionID != "" {
			if _, err := s.Store.Collection(*in.CollectionID); err != nil {
				fail(w, 400, "collection inconnue")
				return
			}
		}
		it.CollectionID = *in.CollectionID
		moved = true
	}
	if err := s.Store.UpdateItem(it); err != nil {
		fail(w, 500, err.Error())
		return
	}
	if moved {
		siblings, _ := s.Store.ItemsOf(it.CollectionID)
		ids := []string{}
		for _, sib := range siblings {
			if sib.ID != it.ID {
				ids = append(ids, sib.ID)
			}
		}
		_ = s.Store.OrderItems(append(ids, it.ID))
	}
	s.Store.BumpLibrary()
	writeJSON(w, 200, s.adminItem(it))
}

func (s *Server) itemDelete(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if _, err := s.Store.Item(id); err != nil {
		fail(w, 404, "vidéo introuvable")
		return
	}
	jobs, _ := s.Store.Jobs(200)
	for _, j := range jobs {
		if j.ItemID == id && (j.Status == "queued" || j.Status == "running") {
			_ = s.Store.CancelJob(j.ID)
		}
	}
	if err := s.Store.DeleteItem(id); err != nil {
		fail(w, 500, err.Error())
		return
	}
	go func() {
		time.Sleep(2 * time.Second) // let a running ffmpeg die first
		s.Ingest.RemoveItemFiles(id)
	}()
	s.Store.BumpLibrary()
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) itemsOrder(w http.ResponseWriter, r *http.Request) {
	var in struct {
		IDs []string `json:"ids"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, 400, "requête invalide")
		return
	}
	if err := s.Store.OrderItems(in.IDs); err != nil {
		fail(w, 500, err.Error())
		return
	}
	s.Store.BumpLibrary()
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) itemThumb(w http.ResponseWriter, r *http.Request) {
	it, err := s.Store.Item(r.PathValue("id"))
	if err != nil {
		fail(w, 404, "vidéo introuvable")
		return
	}
	if strings.HasPrefix(r.Header.Get("Content-Type"), "multipart/") {
		tmp, cleanup, err := s.uploadTemp(w, r, 50<<20)
		if err != nil {
			return
		}
		defer cleanup()
		if err := s.Ingest.ThumbFromImage(r.Context(), it, tmp); err != nil {
			fail(w, 400, "image illisible : "+err.Error())
			return
		}
	} else {
		var in struct {
			At float64 `json:"at"`
		}
		if err := decode(r, &in); err != nil {
			fail(w, 400, "requête invalide")
			return
		}
		if err := s.Ingest.Rethumb(r.Context(), it, in.At); err != nil {
			fail(w, 400, err.Error())
			return
		}
	}
	it, _ = s.Store.Item(it.ID)
	writeJSON(w, 200, s.adminItem(it))
}

func (s *Server) itemRetry(w http.ResponseWriter, r *http.Request) {
	it, err := s.Store.Item(r.PathValue("id"))
	if err != nil {
		fail(w, 404, "vidéo introuvable")
		return
	}
	input, ok := s.Ingest.StagedInput(it.ID)
	if !ok {
		fail(w, http.StatusConflict, "le fichier d'origine n'est plus là : renvoyez la vidéo")
		return
	}
	it.Status, it.Error = "importing", ""
	_ = s.Store.UpdateItem(it)
	jobID, err := s.Ingest.Enqueue(it.ID, input, "")
	if err != nil {
		fail(w, http.StatusConflict, "déjà en cours")
		return
	}
	s.Store.BumpLibrary()
	writeJSON(w, 202, map[string]string{"jobId": jobID})
}

// ---------- uploads ----------

// uploadTemp saves the "file" part of a multipart request to a temp file.
func (s *Server) uploadTemp(w http.ResponseWriter, r *http.Request, limit int64) (string, func(), error) {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	mr, err := r.MultipartReader()
	if err != nil {
		fail(w, 400, "envoi multipart attendu")
		return "", nil, err
	}
	dir := filepath.Join(s.Cfg.StagingDir(), "_uploads")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		fail(w, 500, err.Error())
		return "", nil, err
	}
	for {
		part, err := mr.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			fail(w, 400, "envoi interrompu")
			return "", nil, err
		}
		if part.FormName() != "file" {
			continue
		}
		ext := strings.ToLower(filepath.Ext(part.FileName()))
		if ext == "" || len(ext) > 8 {
			ext = ".bin"
		}
		path := filepath.Join(dir, store.NewID()+ext)
		f, err := os.Create(path)
		if err != nil {
			fail(w, 500, err.Error())
			return "", nil, err
		}
		_, err = io.Copy(f, part)
		f.Close()
		if err != nil {
			os.Remove(path)
			fail(w, 400, "envoi interrompu")
			return "", nil, err
		}
		return path, func() { os.Remove(path) }, nil
	}
	fail(w, 400, "aucun fichier")
	return "", nil, errNotFound
}

func (s *Server) upload(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 8<<30)
	mr, err := r.MultipartReader()
	if err != nil {
		fail(w, 400, "envoi multipart attendu")
		return
	}
	var (
		collectionID string
		it           store.Item
		staged       string
		created      bool
	)
	for {
		part, err := mr.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			s.abortUpload(it, created)
			fail(w, 400, "envoi interrompu")
			return
		}
		switch part.FormName() {
		case "collectionId":
			b, _ := io.ReadAll(io.LimitReader(part, 200))
			collectionID = strings.TrimSpace(string(b))
		case "collectionTitle":
			b, _ := io.ReadAll(io.LimitReader(part, 200))
			if id, err := s.Ingest.CollectionFor(string(b)); err == nil {
				collectionID = id
			}
		case "file":
			if created {
				continue // one video per request
			}
			name := part.FileName()
			it, err = s.Ingest.NewItem(ingest.TitleFromName(name), collectionID, "upload", "")
			if err != nil {
				fail(w, 500, err.Error())
				return
			}
			created = true
			staged = s.Ingest.StagePath(it.ID, name)
			if err := os.MkdirAll(filepath.Dir(staged), 0o755); err != nil {
				s.abortUpload(it, created)
				fail(w, 500, err.Error())
				return
			}
			f, err := os.Create(staged)
			if err != nil {
				s.abortUpload(it, created)
				fail(w, 500, err.Error())
				return
			}
			_, err = io.Copy(f, part)
			f.Close()
			if err != nil {
				s.abortUpload(it, created)
				fail(w, 400, "envoi interrompu")
				return
			}
		}
	}
	if !created {
		fail(w, 400, "aucun fichier")
		return
	}
	if collectionID != "" && it.CollectionID != collectionID {
		it.CollectionID = collectionID
		_ = s.Store.UpdateItem(it)
	}
	jobID, err := s.Ingest.Enqueue(it.ID, staged, "")
	if err != nil {
		fail(w, 500, err.Error())
		return
	}
	s.Store.BumpLibrary()
	s.Log.Info("upload staged", "item", it.ID, "title", it.Title, "job", jobID)
	writeJSON(w, http.StatusAccepted, map[string]string{"itemId": it.ID, "jobId": jobID})
}

func (s *Server) abortUpload(it store.Item, created bool) {
	if !created {
		return
	}
	_ = s.Store.DeleteItem(it.ID)
	s.Ingest.RemoveItemFiles(it.ID)
	s.Store.BumpLibrary()
}

// ImportInbox is called by the inbox watcher for each settled file.
func (s *Server) ImportInbox(path, collection string) {
	it, jobID, err := s.Ingest.ImportFile(path, collection, "inbox")
	if err != nil {
		s.Log.Error("inbox import failed", "file", path, "err", err)
		return
	}
	s.Log.Info("inbox import queued", "item", it.ID, "title", it.Title, "job", jobID)
}

// ---------- jobs ----------

func (s *Server) jobsList(w http.ResponseWriter, r *http.Request) {
	jobs, err := s.Store.Jobs(60)
	if err != nil {
		fail(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"jobs": jobs, "workerOnline": s.Worker.Online()})
}

func (s *Server) jobCancel(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.CancelJob(r.PathValue("id")); err != nil {
		fail(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]bool{"ok": true})
}

// events streams job, library and status changes (polled every 500 ms).
func (s *Server) events(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		fail(w, 500, "streaming unsupported")
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(200)
	write := func(event string, v any) {
		b, _ := json.Marshal(v)
		fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, b)
		flusher.Flush()
	}
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	lastJobs, lastLib, lastOnline, lastPing := "", int64(-1), !s.Worker.Online(), time.Now()
	sess := r.Context().Value(ctxSession).(store.Session)
	for {
		if jobs, err := s.Store.Jobs(60); err == nil {
			if b, _ := json.Marshal(jobs); string(b) != lastJobs {
				lastJobs = string(b)
				write("jobs", map[string]any{"jobs": jobs})
			}
		}
		if lib := s.Store.LibraryVersion(); lib != lastLib {
			lastLib = lib
			write("library", map[string]any{"version": lib})
		}
		if online := s.Worker.Online(); online != lastOnline {
			lastOnline = online
			write("status", map[string]any{"workerOnline": online})
		}
		if time.Since(lastPing) > 15*time.Second {
			lastPing = time.Now()
			if sess.Expires < store.Now() {
				write("expired", map[string]bool{"expired": true})
				return
			}
			fmt.Fprint(w, ": ping\n\n")
			flusher.Flush()
		}
		select {
		case <-r.Context().Done():
			return
		case <-ticker.C:
		}
	}
}

// ---------- finished image, devices, sources ----------

func (s *Server) finishedImageSet(w http.ResponseWriter, r *http.Request) {
	tmp, cleanup, err := s.uploadTemp(w, r, 50<<20)
	if err != nil {
		return
	}
	defer cleanup()
	if err := media.ResizeImage(r.Context(), s.Cfg.FFmpeg, tmp, s.Cfg.FinishedImage(), 1200); err != nil {
		fail(w, 400, "image illisible : "+err.Error())
		return
	}
	s.Store.BumpLibrary()
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) finishedImageDelete(w http.ResponseWriter, r *http.Request) {
	_ = os.Remove(s.Cfg.FinishedImage())
	s.Store.BumpLibrary()
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) devices(w http.ResponseWriter, r *http.Request) {
	devices, err := s.Store.Devices()
	if err != nil {
		fail(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"devices": devices})
}

func (s *Server) deviceRevoke(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.RevokeDevice(r.PathValue("id")); err != nil {
		fail(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) sourcesList(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	out := []map[string]any{}
	for _, src := range s.Sources {
		out = append(out, map[string]any{"id": src.ID(), "label": src.Label(), "status": src.Status(ctx, s.Deps)})
	}
	writeJSON(w, 200, map[string]any{"sources": out})
}
