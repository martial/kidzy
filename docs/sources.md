# Source plugins (local, private)

Videos reach Kidzy by the admin upload or the inbox folder. A **source plugin** adds another way
(for example a downloader). Plugins are not part of this public repo: each one lives in a private
repo and is **linked** into gitignored paths of this checkout, then switched on by a setting in
`~/.config/kidzy/kidzy.env`, which is never in git either.

The seam on the public side:

- `server/internal/sources/sources.go`: the `Source` interface (`ID`, `Label`, `Routes`, `Runners`,
  `Status`) and `Register`. A plugin registers itself in an `init` function.
- `server/cmd/kidzy/sources_local.go` (gitignored): one blank import per plugin, e.g.
  `import _ "kidzy/server/internal/sources/<id>"`.
- `server/internal/sources/<id>/` (gitignored): the plugin's Go package.
- `admin/src/sources/<id>/panel.tsx` (gitignored): its admin panel; the « Sources » page lists every
  panel found by `import.meta.glob`. Export `meta = { id, label }` and a default component.
- `docs/sources-<id>.md`, `.claude/skills/source-<id>/` (gitignored): its docs and procedure.
- `KIDZY_SOURCES=<id>[,<id>]` in `~/.config/kidzy/kidzy.env` enables it at runtime. Nothing is
  enabled by default, so a plugin left on disk but not listed does nothing.
- `KIDZY_YTDLP` and `KIDZY_JS_RUNTIME` are read by the config for plugins that download.

A plugin repo ships an `install.sh` that makes the symlinks and adds the setting. Without the
plugin, `make build` produces the same binary from a clean clone.
