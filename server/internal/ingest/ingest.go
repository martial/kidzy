// Package ingest turns any dropped or downloaded video into a ready item:
// probe, normalise to MP4 (remux or VideoToolbox transcode), thumbnail,
// publish into the library folder.
package ingest

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"kidzy/server/internal/config"
	"kidzy/server/internal/jobs"
	"kidzy/server/internal/media"
	"kidzy/server/internal/store"
)

// Params are the ingest job's parameters.
type Params struct {
	ItemID    string `json:"itemId"`
	Input     string `json:"input"`               // staged source file
	ThumbFrom string `json:"thumbFrom,omitempty"` // optional image to use as thumbnail
	KeepInput bool   `json:"keepInput,omitempty"`
}

// Pipeline holds what the ingest needs.
type Pipeline struct {
	Cfg   config.Config
	Store *store.Store
	Log   *slog.Logger
}

// Kind is the job kind handled by Run.
const Kind = "ingest"

// ThumbWidth is the width of generated thumbnails and posters.
const ThumbWidth = 640

// ItemDir is where an item's published files live.
func (p *Pipeline) ItemDir(itemID string) string { return filepath.Join(p.Cfg.LibraryDir(), itemID) }

// StagingDir is where an item's source waits.
func (p *Pipeline) StagingDir(itemID string) string {
	return filepath.Join(p.Cfg.StagingDir(), itemID)
}

// StagedInput finds the staged source of an item, if any.
func (p *Pipeline) StagedInput(itemID string) (string, bool) {
	matches, _ := filepath.Glob(filepath.Join(p.StagingDir(itemID), "original.*"))
	if len(matches) == 0 {
		return "", false
	}
	return matches[0], true
}

// StagePath returns the staging path for a source file name.
func (p *Pipeline) StagePath(itemID, name string) string {
	ext := strings.ToLower(filepath.Ext(name))
	if ext == "" || len(ext) > 8 {
		ext = ".bin"
	}
	return filepath.Join(p.StagingDir(itemID), "original"+ext)
}

// Stage moves (or copies, across volumes) a file into the item's staging dir.
func (p *Pipeline) Stage(itemID, src string) (string, error) {
	dst := p.StagePath(itemID, src)
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return "", err
	}
	if err := os.Rename(src, dst); err == nil {
		return dst, nil
	}
	in, err := os.Open(src)
	if err != nil {
		return "", err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return "", err
	}
	if err := out.Close(); err != nil {
		return "", err
	}
	_ = os.Remove(src)
	return dst, nil
}

// NewItem creates an importing item for a source file.
func (p *Pipeline) NewItem(title, collectionID, source, sourceRef string) (store.Item, error) {
	it, err := p.Store.InsertItem(store.Item{Title: title, CollectionID: collectionID, Visible: true, Status: "importing", Source: source, SourceRef: sourceRef})
	if err == nil {
		p.Store.BumpLibrary()
	}
	return it, err
}

// Enqueue queues the ingest of a staged file (one active job per item).
func (p *Pipeline) Enqueue(itemID, input, thumbFrom string) (string, error) {
	return p.Store.Enqueue(Kind, Params{ItemID: itemID, Input: input, ThumbFrom: thumbFrom}, Kind+":"+itemID, itemID)
}

// CollectionFor finds a collection by title or creates it (empty title = none).
func (p *Pipeline) CollectionFor(title string) (string, error) {
	title = strings.TrimSpace(title)
	if title == "" {
		return "", nil
	}
	if c, err := p.Store.CollectionByTitle(title); err == nil {
		return c.ID, nil
	}
	cols, _ := p.Store.Collections()
	c, err := p.Store.InsertCollection(store.Collection{Title: title, Kind: "show", Color: store.NextColor(len(cols)), Visible: true})
	if err != nil {
		return "", err
	}
	p.Store.BumpLibrary()
	return c.ID, nil
}

// ImportFile stages a file as a new item of a collection and queues its ingest.
func (p *Pipeline) ImportFile(path, collectionTitle, source string) (store.Item, string, error) {
	collectionID, err := p.CollectionFor(collectionTitle)
	if err != nil {
		return store.Item{}, "", err
	}
	it, err := p.NewItem(TitleFromName(filepath.Base(path)), collectionID, source, "")
	if err != nil {
		return store.Item{}, "", err
	}
	staged, err := p.Stage(it.ID, path)
	if err != nil {
		return it, "", err
	}
	jobID, err := p.Enqueue(it.ID, staged, "")
	return it, jobID, err
}

var (
	junk   = regexp.MustCompile(`(?i)[\[(](?:\d{3,4}p|x26[45]|h\.?26[45]|hevc|web-?dl|bluray|hdtv|aac|ac3|\w+rip)[^\])]*[\])]`)
	spaces = regexp.MustCompile(`\s+`)
)

// TitleFromName makes a readable title from a file name.
func TitleFromName(name string) string {
	t := strings.TrimSuffix(name, filepath.Ext(name))
	t = junk.ReplaceAllString(t, " ")
	t = strings.NewReplacer("_", " ", ".", " ").Replace(t)
	t = strings.TrimSpace(spaces.ReplaceAllString(t, " "))
	if t == "" {
		return "Vidéo"
	}
	return t
}

// Run performs the ingest job.
func (p *Pipeline) Run(ctx context.Context, job store.Job, rep *jobs.Reporter) error {
	var pr Params
	if err := json.Unmarshal(job.Params, &pr); err != nil {
		return err
	}
	return p.Process(ctx, pr, rep)
}

// Process ingests a staged file for an item, marking the item failed on error.
// A source plugin calls it from its own job once its download is done.
func (p *Pipeline) Process(ctx context.Context, pr Params, rep *jobs.Reporter) error {
	it, err := p.Store.Item(pr.ItemID)
	if err != nil {
		return fmt.Errorf("item %s: %w", pr.ItemID, err)
	}
	err = p.process(ctx, it, pr, rep)
	if err != nil {
		if ctx.Err() == nil {
			it.Status, it.Error = "failed", err.Error()
			_ = p.Store.UpdateItem(it)
			p.Store.BumpLibrary()
		}
		return err
	}
	return nil
}

// Fail marks an item failed with a message (for a source whose download failed).
func (p *Pipeline) Fail(itemID, msg string) {
	if it, err := p.Store.Item(itemID); err == nil {
		it.Status, it.Error = "failed", msg
		_ = p.Store.UpdateItem(it)
		p.Store.BumpLibrary()
	}
}

func (p *Pipeline) process(ctx context.Context, it store.Item, pr Params, rep *jobs.Reporter) error {
	rep.Progress("probe", 0)
	rep.Log("source: %s", filepath.Base(pr.Input))
	probe, err := media.ProbeFile(ctx, p.Cfg.FFprobe, pr.Input)
	if err != nil {
		return err
	}
	rep.Log("%s %dx%d %s/%s %.0fs", probe.Container, probe.Width, probe.Height, probe.VCodec, probe.ACodec, probe.Duration)
	dir := p.ItemDir(it.ID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	partial := filepath.Join(dir, "video.partial.mp4")
	final := filepath.Join(dir, "video.mp4")
	rep.Progress("convert", 0)
	err = media.Normalise(ctx, p.Cfg.FFmpeg, pr.Input, partial, probe, func(pct float64) { rep.Progress("convert", pct) }, func(l string) { rep.Log("%s", l) })
	if err != nil {
		_ = os.Remove(partial)
		return err
	}
	if err := os.Rename(partial, final); err != nil {
		return err
	}
	out, err := media.ProbeFile(ctx, p.Cfg.FFprobe, final)
	if err != nil {
		return fmt.Errorf("result unreadable: %w", err)
	}
	rep.Progress("thumb", 0)
	thumb := filepath.Join(dir, "thumb.jpg")
	if !it.ThumbCustom {
		if pr.ThumbFrom != "" {
			if err := media.ResizeImage(ctx, p.Cfg.FFmpeg, pr.ThumbFrom, thumb, ThumbWidth); err != nil {
				rep.Log("thumbnail from image failed (%v), taking a frame", err)
				pr.ThumbFrom = ""
			}
		}
		if pr.ThumbFrom == "" {
			if err := media.Thumbnail(ctx, p.Cfg.FFmpeg, final, thumb, ThumbAt(out.Duration), ThumbWidth); err != nil {
				return err
			}
		}
	}
	st, err := os.Stat(final)
	if err != nil {
		return err
	}
	if _, err := p.Store.InsertMedia(store.Media{ItemID: it.ID, Path: final, Bytes: st.Size(), Width: out.Width, Height: out.Height, VCodec: out.VCodec, ACodec: out.ACodec, Container: "mp4"}); err != nil {
		return err
	}
	it.Status, it.Error, it.Duration, it.ThumbPath = "ready", "", out.Duration, thumb
	if err := p.Store.UpdateItem(it); err != nil {
		return err
	}
	if !pr.KeepInput {
		_ = os.RemoveAll(p.StagingDir(it.ID))
	}
	p.Store.BumpLibrary()
	rep.Log("ready: %dx%d, %s", out.Width, out.Height, humanBytes(st.Size()))
	return nil
}

// ThumbAt picks the thumbnail time: 10 % in, at least 5 s, inside the video.
func ThumbAt(duration float64) float64 {
	at := max(5, duration*0.1)
	if duration > 0 && at >= duration {
		at = duration / 2
	}
	return at
}

// Rethumb regenerates an item's thumbnail from a frame at the given second.
func (p *Pipeline) Rethumb(ctx context.Context, it store.Item, at float64) error {
	m, err := p.Store.MediaOf(it.ID)
	if err != nil {
		return errors.New("no video for this item yet")
	}
	thumb := filepath.Join(p.ItemDir(it.ID), "thumb.jpg")
	if err := media.Thumbnail(ctx, p.Cfg.FFmpeg, m.Path, thumb, max(0, min(at, max(0, it.Duration-0.1))), ThumbWidth); err != nil {
		return err
	}
	it.ThumbPath, it.ThumbCustom = thumb, true
	if err := p.Store.UpdateItem(it); err != nil {
		return err
	}
	p.Store.BumpLibrary()
	return nil
}

// ThumbFromImage sets an item's thumbnail from an uploaded image.
func (p *Pipeline) ThumbFromImage(ctx context.Context, it store.Item, image string) error {
	dir := p.ItemDir(it.ID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	thumb := filepath.Join(dir, "thumb.jpg")
	if err := media.ResizeImage(ctx, p.Cfg.FFmpeg, image, thumb, ThumbWidth); err != nil {
		return err
	}
	it.ThumbPath, it.ThumbCustom = thumb, true
	if err := p.Store.UpdateItem(it); err != nil {
		return err
	}
	p.Store.BumpLibrary()
	return nil
}

// RemoveItemFiles deletes an item's library and staging folders.
func (p *Pipeline) RemoveItemFiles(itemID string) {
	if itemID == "" {
		return
	}
	_ = os.RemoveAll(p.ItemDir(itemID))
	_ = os.RemoveAll(p.StagingDir(itemID))
}

// CollectionPosterPath is where a collection's poster is stored.
func (p *Pipeline) CollectionPosterPath(collectionID string) string {
	return filepath.Join(p.Cfg.LibraryDir(), "_collections", collectionID, "poster.jpg")
}

func humanBytes(n int64) string {
	switch {
	case n > 1<<30:
		return fmt.Sprintf("%.1f Go", float64(n)/(1<<30))
	case n > 1<<20:
		return fmt.Sprintf("%.0f Mo", float64(n)/(1<<20))
	default:
		return fmt.Sprintf("%d o", n)
	}
}
