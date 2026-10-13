# The private `youtube` branch

`main` is public on GitHub (`martial/kidzy`). The YouTube downloader (yt-dlp) must not be
public, and a branch pushed to a public repo is public. So:

- The code lives on branch **`youtube`**, pushed only to the remote **`private`**
  (`martial/kidzy-private`, a private repo). `ops/git-hooks/pre-push` refuses to push that
  branch to `origin`; install the hooks with `git config core.hooksPath ops/git-hooks`.
- `main` contains the seam only: the `sources` plugin registry in `server/internal/sources`,
  the worker dispatch for unknown job kinds, `GET /api/admin/sources`, and the admin « Sources »
  page that renders `admin/src/sources/*/panel.tsx` (empty on main).
- The branch adds files, never edits main's: `server/cmd/kidzy/sources_youtube.go`,
  `server/internal/sources/youtube/`, `admin/src/sources/youtube/`, `docs/youtube.md`,
  `.claude/skills/youtube-download/`.
- Keeping it current: `git checkout youtube && git rebase main && git push -f private youtube`.
- Cookies for YouTube go to `~/.config/kidzy/cookies.txt`, never in a repo.
