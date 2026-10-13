package api

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"kidzy/server/internal/auth"
	"kidzy/server/internal/limits"
	"kidzy/server/internal/store"
)

// ---------- what the phone sees ----------

type collectionJSON struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Kind      string `json:"kind"`
	Color     string `json:"color"`
	ItemCount int    `json:"itemCount"`
	PosterURL string `json:"posterUrl"`
}

type itemJSON struct {
	ID           string  `json:"id"`
	CollectionID string  `json:"collectionId"`
	Title        string  `json:"title"`
	Duration     float64 `json:"duration"`
	Color        string  `json:"color"`
	ThumbURL     string  `json:"thumbUrl"`
	VideoURL     string  `json:"videoUrl"`
}

func toItemJSON(it store.Item, color string) itemJSON {
	return itemJSON{ID: it.ID, CollectionID: it.CollectionID, Title: it.Title, Duration: it.Duration, Color: color,
		ThumbURL: "/api/items/" + it.ID + "/thumb", VideoURL: "/api/items/" + it.ID + "/video"}
}

func playable(it store.Item) bool { return it.Status == "ready" && it.Visible }

// orphanCollection gathers the playable videos that have no collection, so
// nothing the parent adds is ever invisible to the kid.
const orphanCollectionID = "_"

func orphanCollection() store.Collection {
	return store.Collection{ID: orphanCollectionID, Title: "Vidéos", Kind: "films", Color: "#FFD23F", Visible: true}
}

func (s *Server) identity(w http.ResponseWriter, r *http.Request) {
	id, _ := s.Store.Setting("server_id")
	_, pinSet := s.pinHash()
	writeJSON(w, 200, map[string]any{
		"name": s.Cfg.Name, "id": id, "version": s.Cfg.Version, "libraryVersion": s.Store.LibraryVersion(),
		"serverTime": time.Now().Format(time.RFC3339), "pinSet": pinSet,
	})
}

func (s *Server) pair(w http.ResponseWriter, r *http.Request) {
	if s.rateLimited(w, r) {
		return
	}
	var in struct {
		PIN        string `json:"pin"`
		DeviceName string `json:"deviceName"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, 400, "requête invalide")
		return
	}
	if _, ok := s.pinHash(); !ok {
		fail(w, http.StatusConflict, "le code parent n'est pas encore choisi : ouvrez l'admin sur le Mac")
		return
	}
	if !s.checkPIN(in.PIN) {
		fail(w, http.StatusForbidden, "code incorrect")
		return
	}
	name := strings.TrimSpace(in.DeviceName)
	if name == "" {
		name = "iPhone"
	}
	token, hash := auth.NewToken()
	d, err := s.Store.InsertDevice(name, hash)
	if err != nil {
		fail(w, 500, err.Error())
		return
	}
	s.Log.Info("device paired", "name", name, "id", d.ID)
	writeJSON(w, 200, map[string]any{"deviceId": d.ID, "token": token, "name": s.Cfg.Name})
}

// visibleCollections lists collections the kid sees, each with its playable items.
func (s *Server) visibleCollections() ([]store.Collection, map[string][]store.Item, error) {
	cols, err := s.Store.Collections()
	if err != nil {
		return nil, nil, err
	}
	items, err := s.Store.Items()
	if err != nil {
		return nil, nil, err
	}
	byCol := map[string][]store.Item{}
	for _, it := range items {
		if playable(it) {
			byCol[it.CollectionID] = append(byCol[it.CollectionID], it)
		}
	}
	out := cols[:0]
	for _, c := range cols {
		if c.Visible && len(byCol[c.ID]) > 0 {
			out = append(out, c)
		}
	}
	if len(byCol[""]) > 0 {
		orphans := orphanCollection()
		byCol[orphans.ID] = byCol[""]
		out = append(out, orphans)
	}
	return out, byCol, nil
}

func (s *Server) collectionJSON(c store.Collection, items []store.Item) collectionJSON {
	poster := ""
	if c.PosterPath != "" {
		poster = "/api/collections/" + c.ID + "/poster"
	} else if len(items) > 0 {
		poster = "/api/items/" + items[0].ID + "/thumb"
	}
	return collectionJSON{ID: c.ID, Title: c.Title, Kind: c.Kind, Color: c.Color, ItemCount: len(items), PosterURL: poster}
}

func (s *Server) collections(w http.ResponseWriter, r *http.Request) {
	cols, byCol, err := s.visibleCollections()
	if err != nil {
		fail(w, 500, err.Error())
		return
	}
	out := []collectionJSON{}
	for _, c := range cols {
		out = append(out, s.collectionJSON(c, byCol[c.ID]))
	}
	writeJSON(w, 200, map[string]any{"collections": out, "libraryVersion": s.Store.LibraryVersion()})
}

func (s *Server) collection(w http.ResponseWriter, r *http.Request) {
	var c store.Collection
	if r.PathValue("id") == orphanCollectionID {
		c = orphanCollection()
	} else {
		var err error
		c, err = s.Store.Collection(r.PathValue("id"))
		if err != nil || !c.Visible {
			fail(w, 404, "collection introuvable")
			return
		}
	}
	all, _ := s.Store.ItemsOf(strings.TrimPrefix(c.ID, orphanCollectionID))
	items := []itemJSON{}
	var raw []store.Item
	for _, it := range all {
		if playable(it) {
			raw = append(raw, it)
			items = append(items, toItemJSON(it, c.Color))
		}
	}
	writeJSON(w, 200, map[string]any{"collection": s.collectionJSON(c, raw), "items": items})
}

func (s *Server) item(w http.ResponseWriter, r *http.Request) {
	it, err := s.Store.Item(r.PathValue("id"))
	if err != nil || !playable(it) {
		fail(w, 404, "vidéo introuvable")
		return
	}
	color := orphanCollection().Color
	if c, err := s.Store.Collection(it.CollectionID); err == nil {
		color = c.Color
	}
	writeJSON(w, 200, toItemJSON(it, color))
}

func (s *Server) hubs(w http.ResponseWriter, r *http.Request) {
	items, _ := s.Store.Items()
	var ready []store.Item
	for _, it := range items {
		if playable(it) {
			ready = append(ready, it)
		}
	}
	sort.Slice(ready, func(i, j int) bool { return ready[i].Created > ready[j].Created })
	if len(ready) > 8 {
		ready = ready[:8]
	}
	recent := []itemJSON{}
	for _, it := range ready {
		recent = append(recent, toItemJSON(it, ""))
	}
	writeJSON(w, 200, map[string]any{"recentlyAdded": recent})
}

// ---------- files ----------

func serveFile(w http.ResponseWriter, r *http.Request, path, contentType string) {
	f, err := os.Open(path)
	if err != nil {
		fail(w, 404, "fichier absent")
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		fail(w, 404, "fichier absent")
		return
	}
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cache-Control", "private, max-age=3600")
	http.ServeContent(w, r, filepath.Base(path), st.ModTime(), f)
}

func (s *Server) video(w http.ResponseWriter, r *http.Request) {
	it, err := s.Store.Item(r.PathValue("id"))
	if err != nil || it.Status != "ready" {
		fail(w, 404, "vidéo introuvable")
		return
	}
	m, err := s.Store.MediaOf(it.ID)
	if err != nil {
		fail(w, 404, "vidéo introuvable")
		return
	}
	serveFile(w, r, m.Path, "video/mp4")
}

func (s *Server) thumb(w http.ResponseWriter, r *http.Request) {
	it, err := s.Store.Item(r.PathValue("id"))
	if err != nil || it.ThumbPath == "" {
		fail(w, 404, "pas de vignette")
		return
	}
	serveFile(w, r, it.ThumbPath, "image/jpeg")
}

func (s *Server) poster(w http.ResponseWriter, r *http.Request) {
	if r.PathValue("id") == orphanCollectionID {
		items, _ := s.Store.ItemsOf("")
		for _, it := range items {
			if playable(it) && it.ThumbPath != "" {
				serveFile(w, r, it.ThumbPath, "image/jpeg")
				return
			}
		}
		fail(w, 404, "pas d'affiche")
		return
	}
	c, err := s.Store.Collection(r.PathValue("id"))
	if err != nil {
		fail(w, 404, "collection introuvable")
		return
	}
	if c.PosterPath != "" {
		serveFile(w, r, c.PosterPath, "image/jpeg")
		return
	}
	items, _ := s.Store.ItemsOf(c.ID)
	for _, it := range items {
		if it.ThumbPath != "" && (playable(it) || !strings.HasPrefix(r.URL.Path, "/api/collections")) {
			serveFile(w, r, it.ThumbPath, "image/jpeg")
			return
		}
	}
	fail(w, 404, "pas d'affiche")
}

func (s *Server) finishedImage(w http.ResponseWriter, r *http.Request) {
	serveFile(w, r, s.Cfg.FinishedImage(), "image/jpeg")
}

// ---------- limits and playback ----------

func (s *Server) rules() limits.Rules {
	var r limits.Rules
	if v, ok := s.Store.Setting("limits"); ok {
		_ = jsonUnmarshal(v, &r)
	}
	return r
}

func (s *Server) verdict(now time.Time) limits.Verdict {
	return limits.Evaluate(now, s.Store.WatchedSeconds(limits.Day(now)), s.rules())
}

func (s *Server) limitsGet(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, s.verdict(time.Now()))
}

func (s *Server) timeline(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ItemID    string  `json:"itemId"`
		SessionID string  `json:"sessionId"`
		State     string  `json:"state"`
		Position  float64 `json:"position"`
	}
	if err := decode(r, &in); err != nil || in.SessionID == "" || in.ItemID == "" {
		fail(w, 400, "requête invalide")
		return
	}
	switch in.State {
	case "playing", "paused", "stopped", "ended":
	default:
		fail(w, 400, "état inconnu")
		return
	}
	now := time.Now()
	delta := 0.0
	if last, err := s.Store.LastPlayback(in.SessionID); err == nil && last.State == "playing" {
		delta = min(20, float64(now.UnixMilli()-last.At)/1000)
		if delta < 0 {
			delta = 0
		}
	}
	_ = s.Store.AddPlayback(store.PlaybackEvent{DeviceID: deviceOf(r).ID, ItemID: in.ItemID, SessionID: in.SessionID, State: in.State, Position: in.Position, Delta: delta, At: now.UnixMilli(), Day: limits.Day(now)})
	writeJSON(w, 200, s.verdict(now))
}

func (s *Server) parentUnlock(w http.ResponseWriter, r *http.Request) {
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
	token, hash := auth.NewToken()
	expires := time.Now().Add(parentTTL)
	if err := s.Store.InsertSession(store.Session{TokenHash: hash, Kind: "parent", DeviceID: deviceOf(r).ID, Expires: expires.UnixMilli()}); err != nil {
		fail(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]any{"token": token, "expires": expires.Format(time.RFC3339)})
}

// ---------- settings (parent area and admin) ----------

type settingsJSON struct {
	Limits           limits.Rules `json:"limits"`
	ServerName       string       `json:"serverName"`
	FinishedImageSet bool         `json:"finishedImageSet"`
	PinSet           bool         `json:"pinSet"`
	WatchedToday     int          `json:"watchedToday"`
	Collections      []struct {
		ID        string `json:"id"`
		Title     string `json:"title"`
		Color     string `json:"color"`
		Visible   bool   `json:"visible"`
		ItemCount int    `json:"itemCount"`
	} `json:"collections"`
}

func (s *Server) settingsGet(w http.ResponseWriter, r *http.Request) {
	out := settingsJSON{Limits: s.rules(), ServerName: s.Cfg.Name}
	_, out.PinSet = s.pinHash()
	_, err := os.Stat(s.Cfg.FinishedImage())
	out.FinishedImageSet = err == nil
	out.WatchedToday = int(s.Store.WatchedSeconds(limits.Day(time.Now())))
	cols, _ := s.Store.Collections()
	items, _ := s.Store.Items()
	counts := map[string]int{}
	for _, it := range items {
		if it.Status == "ready" && it.Visible {
			counts[it.CollectionID]++
		}
	}
	out.Collections = make([]struct {
		ID        string `json:"id"`
		Title     string `json:"title"`
		Color     string `json:"color"`
		Visible   bool   `json:"visible"`
		ItemCount int    `json:"itemCount"`
	}, 0, len(cols))
	for _, c := range cols {
		out.Collections = append(out.Collections, struct {
			ID        string `json:"id"`
			Title     string `json:"title"`
			Color     string `json:"color"`
			Visible   bool   `json:"visible"`
			ItemCount int    `json:"itemCount"`
		}{c.ID, c.Title, c.Color, c.Visible, counts[c.ID]})
	}
	writeJSON(w, 200, out)
}

func (s *Server) settingsPut(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Limits      *limits.Rules `json:"limits"`
		Collections []struct {
			ID      string `json:"id"`
			Visible bool   `json:"visible"`
		} `json:"collections"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, 400, "requête invalide")
		return
	}
	if in.Limits != nil {
		if in.Limits.DailySeconds < 0 || in.Limits.DailySeconds > 24*3600 {
			fail(w, 400, "limite quotidienne invalide")
			return
		}
		if in.Limits.Bedtime != nil && !in.Limits.Bedtime.Valid() {
			fail(w, 400, "heures de coucher invalides (HH:MM)")
			return
		}
		b, _ := jsonMarshal(in.Limits)
		if err := s.Store.SetSetting("limits", b); err != nil {
			fail(w, 500, err.Error())
			return
		}
	}
	changed := false
	for _, cv := range in.Collections {
		c, err := s.Store.Collection(cv.ID)
		if err != nil || c.Visible == cv.Visible {
			continue
		}
		c.Visible = cv.Visible
		if err := s.Store.UpdateCollection(c); err == nil {
			changed = true
		}
	}
	if changed {
		s.Store.BumpLibrary()
	}
	s.settingsGet(w, r)
}

func (s *Server) pinSet(w http.ResponseWriter, r *http.Request) {
	var in struct {
		PIN     string `json:"pin"`
		Current string `json:"current"`
	}
	if err := decode(r, &in); err != nil {
		fail(w, 400, "requête invalide")
		return
	}
	if !auth.ValidPIN(in.PIN) {
		fail(w, 400, "le code doit faire 4 à 6 chiffres")
		return
	}
	if _, set := s.pinHash(); set && !s.checkPIN(in.Current) {
		if s.rateLimited(w, r) {
			return
		}
		fail(w, http.StatusForbidden, "code actuel incorrect")
		return
	}
	if err := s.savePIN(in.PIN); err != nil {
		fail(w, 500, err.Error())
		return
	}
	writeJSON(w, 200, map[string]bool{"ok": true})
}

func (s *Server) savePIN(pin string) error {
	h, err := auth.HashPIN(pin)
	if err != nil {
		return err
	}
	return s.Store.SetSetting("pin_hash", h)
}

var errNotFound = errors.New("not found")
