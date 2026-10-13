// Package watch follows the inbox folder: a file dropped there (or in a
// sub-folder named after a collection) becomes an item once its size has
// been stable for a few seconds.
package watch

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// Watcher watches Dir and calls OnFile for each settled file.
type Watcher struct {
	Dir    string
	Log    *slog.Logger
	OnFile func(path, collection string)
	// Settle is how long a file's size must stay unchanged (default 3 s).
	Settle time.Duration

	mu         sync.Mutex
	candidates map[string]candidate
}

type candidate struct {
	size    int64
	changed time.Time
}

// Run loops until the context ends.
func (w *Watcher) Run(ctx context.Context) error {
	if w.Settle == 0 {
		w.Settle = 3 * time.Second
	}
	w.candidates = map[string]candidate{}
	if err := os.MkdirAll(w.Dir, 0o755); err != nil {
		return err
	}
	fw, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	defer fw.Close()
	w.addTree(fw, w.Dir)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case ev, ok := <-fw.Events:
			if !ok {
				return nil
			}
			if ev.Has(fsnotify.Create) || ev.Has(fsnotify.Write) || ev.Has(fsnotify.Rename) {
				if st, err := os.Stat(ev.Name); err == nil {
					if st.IsDir() {
						w.addTree(fw, ev.Name)
					} else {
						w.consider(ev.Name, st.Size())
					}
				}
			}
		case err, ok := <-fw.Errors:
			if ok && err != nil {
				w.Log.Warn("inbox watcher", "err", err)
			}
		case <-ticker.C:
			w.settle()
		}
	}
}

func (w *Watcher) addTree(fw *fsnotify.Watcher, root string) {
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if strings.HasPrefix(d.Name(), ".") && path != root {
				return filepath.SkipDir
			}
			if err := fw.Add(path); err != nil {
				w.Log.Warn("inbox watch", "dir", path, "err", err)
			}
			return nil
		}
		if st, err := d.Info(); err == nil {
			w.consider(path, st.Size())
		}
		return nil
	})
}

func ignored(name string) bool {
	base := filepath.Base(name)
	if strings.HasPrefix(base, ".") {
		return true
	}
	switch strings.ToLower(filepath.Ext(base)) {
	case ".part", ".crdownload", ".download", ".tmp", ".ds_store":
		return true
	}
	return false
}

func (w *Watcher) consider(path string, size int64) {
	if ignored(path) {
		return
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	c, seen := w.candidates[path]
	if !seen || c.size != size {
		w.candidates[path] = candidate{size: size, changed: time.Now()}
	}
}

func (w *Watcher) settle() {
	w.mu.Lock()
	var ready []string
	for path, c := range w.candidates {
		st, err := os.Stat(path)
		if err != nil {
			delete(w.candidates, path)
			continue
		}
		if st.Size() != c.size {
			w.candidates[path] = candidate{size: st.Size(), changed: time.Now()}
			continue
		}
		if time.Since(c.changed) >= w.Settle && st.Size() > 0 {
			ready = append(ready, path)
			delete(w.candidates, path)
		}
	}
	w.mu.Unlock()
	for _, path := range ready {
		rel, _ := filepath.Rel(w.Dir, path)
		collection := ""
		if dir := filepath.Dir(rel); dir != "." {
			collection = strings.Split(dir, string(filepath.Separator))[0]
		}
		w.Log.Info("inbox file", "file", rel, "collection", collection)
		w.OnFile(path, collection)
	}
}
