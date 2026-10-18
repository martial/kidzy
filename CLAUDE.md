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
| Source plugins | `server/internal/sources`, `docs/sources.md` | seam; the plugins themselves are linked in from private repos |
| Admin UI | `admin/` (Vite + React + TS, Semantic UI) | built into `server/internal/web/dist`, served at `/admin/` |
| iPhone apps | `ios/project.yml` (XcodeGen → `ios/Kidzy.xcodeproj`, targets `Kidzy` and `SketchesForKids`) | `ios/Kidzy/` = the video app; `ios/Kidzy/Shared/` = `KidzyCore` package tested with `swift test` (`Shared/Toys/` = the toys' pure logic) |
| Toys (shared) | `ios/Toys/Sources/` (`Kit/` = Theme, stickers, ToyHost, registry, sensors, synths; one folder per toy), `ios/Toys/Resources/` | compiled into both apps as plain sources: nothing in `Toys/` may reference an app's model; toys leave through `\.toyExit`; all toy sound goes through one AudioKit engine, `Kit/ToyAudio.swift` (bus → reverb send → compressor → limiter → clipper; instruments `attach`/`detach` a Fader, `acquire`/`release` the engine; play-and-record only while the parrot listens), offline-render tests in `SketchesForKids/Tests/ToyAudioTests.swift` |
| « Sketches for kids! » | `ios/SketchesForKids/` | the toys alone, free + one unlock purchase (`Store.freeToys`), Kids Category; store texts `docs/store/sketches-for-kids.md`, privacy/support pages `docs/sketches/`; debug `KIDZY_SHOW=sketch:<id>|gate|unlock:<id>|parent`, `KIDZY_UNLOCK=1`; purchase tests `xcodebuild test -project ios/Kidzy.xcodeproj -scheme SketchesForKids -destination 'platform=iOS Simulator,name=Banana iPhone,OS=26.2'` |
| Toy details | `ios/Toys/Sources/*`, `ios/Kidzy/Shared/Toys/*`, `ios/Toys/Resources/Shaders/Fluid.metal.txt` | registry (`Toys.all`) + full-screen host (`ToyHost`); « La mer » = spring-column water + boat, tilt via CoreMotion; « Peinture » = Metal stable-fluids paint, shaders compiled at runtime from the .txt (Xcode 26 ships no Metal compiler by default); « Perroquet » = microphone → `Shared/RepeatDetector.swift` (phrase ends after 0.8 s of silence) → pitched playback (AVAudioUnitTimePitch), frames in `Resources/Parrot/` (simulator check: grant the mic with `simctl privacy`, `say` a sentence through the Mac speaker, read `log show --predicate 'subsystem == "com.screenclub.kidzy"'`, `KIDZY_PARROT_TRACE=1` logs levels four times a second); `KIDZY_SHOW=sketch:sea|paint|tiles|animals|guitar|parrot` opens one in the simulator |
| Designs | `docs/design/` | approved mock-ups: change them before changing the app's look |
| Ops | `ops/`, `ios/scripts/` | launchd agent, install on phone, TestFlight upload |

## Commands
- `make build` then `make run` (or `ops/install-launchd.sh` for the background service)
- `make test` (Go with `-race` + vet, admin vitest, Swift core tests)
- `npm --prefix admin run dev` (Vite with `/api` proxied to `127.0.0.1:8800`)
- `make xcodeproj` after editing `ios/project.yml` or adding files
- `ios/scripts/install-phone.sh [kidzy|sketches]` (install on the phone), `ios/scripts/archive-upload.sh [kidzy|sketches]` (TestFlight)

## Skills
| Skill | When |
|---|---|
| `run-server` | start/stop/log the server on this Mac, reset data |
| `install-phone` | build and install on Martial's iPhone over USB |
| `release-testflight` | archive, upload, what to check in App Store Connect |
| `design-review` | show mock-ups on the phone and record approval |

## Rules that hold everywhere
- Downloaders and other extra sources are **not in this repo**: they live in private repos
  (`martial/kidzy-private`, checkout `~/Documents/dev/kidzy-private`) linked into gitignored paths
  and switched on by `KIDZY_SOURCES` in `~/.config/kidzy/kidzy.env`. See `docs/sources.md`.
  Never copy their code into tracked files.
- Secrets live in `~/.config/kidzy/` (`asc.env`, `AuthKey_*.p8`, `cookies.txt`): never in the
  repo, never printed.
- UI text in French; code, comments and docs in English.
- Kid screens: nothing to read, no setting reachable without the parent gate (4 taps + PIN).
- Commit and push only with Martial's yes; `main` is public.
