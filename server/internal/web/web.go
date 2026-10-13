// Package web serves the admin single-page app built by Vite and embedded in
// the binary.
package web

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

//go:embed all:dist
var dist embed.FS

// Handler serves /admin/ from the embedded build: hashed assets as immutable,
// everything else falls back to index.html so client-side routes work.
func Handler() http.Handler {
	sub, err := fs.Sub(dist, "dist")
	if err != nil {
		panic(err)
	}
	files := http.FS(sub)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := strings.TrimPrefix(strings.TrimPrefix(r.URL.Path, "/admin"), "/")
		if p == "" {
			p = "index.html"
		}
		name := path.Clean("/" + p)
		if !serve(w, r, files, name, strings.HasPrefix(p, "assets/")) {
			if !serve(w, r, files, "/index.html", false) {
				http.Error(w, "admin not built: run make admin", http.StatusNotFound)
			}
		}
	})
}

func serve(w http.ResponseWriter, r *http.Request, files http.FileSystem, name string, immutable bool) bool {
	f, err := files.Open(name)
	if err != nil {
		return false
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil || st.IsDir() {
		return false
	}
	if immutable {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	} else {
		w.Header().Set("Cache-Control", "no-cache")
	}
	http.ServeContent(w, r, st.Name(), st.ModTime(), f)
	return true
}
