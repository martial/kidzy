# Kidzy

Locked video player for the kids (iPhone) fed by a tiny Plex-like media server that runs on this
Mac. Everything is local: the parent drops videos in the admin or in `~/Kidzy/inbox/`, the server
normalises them to H.264/AAC MP4, the phone finds the server by Bonjour and plays. The only way out
of a video is 4 taps in the top-left corner; the parent area and the admin need the parent PIN.

## Where things are
| Area | Code | Notes |
|---|---|---|
| Server (Go 1.26) | `server/cmd/kidzy`, `server/internal/*` | stdlib `net/http`, `modernc.org/sqlite`, one process, one worker goroutine |
| Catalogue, jobs | `server/internal/store`, `server/internal/jobs` | SQLite in `~/Library/Application Support/Kidzy/kidzy.db` |
| Ingest (ffmpeg) | `server/internal/ingest`, `server/internal/media` | probe → remux or VideoToolbox transcode → thumb → `~/Kidzy/library/<id>/` |
| Inbox watcher | `server/internal/watch` | `~/Kidzy/inbox/<collection>/file` → job |
| HTTP API | `server/internal/api`, `docs/api.md` | device token for the app, PIN for parent/admin |
| Time limits | `server/internal/limits` | server-authoritative daily seconds + bedtime |
| Bonjour | `server/internal/bonjour` | spawns `/usr/bin/dns-sd -R` on macOS |
| Source plugins | `server/internal/sources` | seam for the private YouTube branch |
| Admin UI | `admin/` (Vite + React + TS, Semantic UI) | built into `server/internal/web/dist`, served at `/admin/` |
| iPhone app | `ios/Kidzy/` (`project.yml` → XcodeGen) | `Shared/` = `KidzyCore` package tested with `swift test` |
| Designs | `docs/design/` | approved mock-ups: change them before changing the app's look |
| Ops | `ops/`, `ios/scripts/` | launchd agent, install on phone, TestFlight upload |

## Commands
- `make build` then `make run` (or `ops/install-launchd.sh` for the background service)
- `make test` (Go with `-race` + vet, admin vitest, Swift core tests)
- `npm --prefix admin run dev` (Vite with `/api` proxied to `127.0.0.1:8800`)
- `make xcodeproj` after editing `ios/Kidzy/project.yml`
- `ios/scripts/install-phone.sh` (USB install), `ios/scripts/archive-upload.sh` (TestFlight)

## Skills
| Skill | When |
|---|---|
| `run-server` | start/stop/log the server on this Mac, reset data |
| `install-phone` | build and install on Martial's iPhone over USB |
| `release-testflight` | archive, upload, what to check in App Store Connect |
| `design-review` | show mock-ups on the phone and record approval |

## Rules that hold everywhere
- The YouTube downloader exists only on branch `youtube`, pushed to remote `private`
  (`martial/kidzy-private`). Never push `youtube` to `origin`: `ops/git-hooks/pre-push` refuses.
- Secrets live in `~/.config/kidzy/` (`asc.env`, `AuthKey_*.p8`, `cookies.txt`): never in the
  repo, never printed.
- UI text in French; code, comments and docs in English.
- Kid screens: nothing to read, no setting reachable without the parent gate (4 taps + PIN).
- Commit and push only with Martial's yes; `main` is public.
