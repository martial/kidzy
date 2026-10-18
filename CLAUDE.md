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
| Toys (shared) | `ios/Toys/Sources/` (`Kit/` = Theme, stickers, ToyHost, registry, sensors, synths; one folder per toy), `ios/Toys/Resources/` | compiled into both apps as plain sources: nothing in `Toys/` may reference an app's model; toys leave through `\.toyExit`; all toy sound goes through one AudioKit engine, `Kit/ToyAudio.swift` (bus → reverb send → compressor → limiter → clipper; instruments `attach`/`detach` a Fader, `acquire`/`release` the engine; play-and-record only while the parrot listens), offline-render tests in `SketchesForKids/Tests/ToyAudioTests.swift` and `VoicesAudioTests.swift` |
| « Sketches for kids! » | `ios/SketchesForKids/` | the toys alone, free + one unlock purchase (`Store.freeToys`), Kids Category; look = `Sources/Brand/Brand.swift` (sunny wall, toy cabinet, night-blue grown-up zone, chunky lip buttons, bundled Baloo 2), 3D toy art in `Resources/Toys3D/` and logo in `Resources/logo.png` + `LaunchLogo` (sources and prompts: `docs/design/sketches/`, `ios/Tools/GenerateToyArt.py`, `Cutout.swift`, `Keyout.swift`); gate = `GateQuestion` (sum in words); debug builds on a phone start with all toys open (switch on the parents page; simulator and tests start locked); store texts `docs/store/sketches-for-kids.md`, privacy/support pages `docs/sketches/`; debug `KIDZY_SHOW=sketch:<id>|gate|unlock:<id>|parent`, `KIDZY_UNLOCK=1`; purchase tests `xcodebuild test -project ios/Kidzy.xcodeproj -scheme SketchesForKids -destination 'platform=iOS Simulator,name=Banana iPhone,OS=26.2'` |
| Toy details | `ios/Toys/Sources/*`, `ios/Kidzy/Shared/Toys/*`, `ios/Toys/Resources/Shaders/Fluid.metal.txt` | registry (`Toys.all`) + full-screen host (`ToyHost`); « La mer » = spring-column water + boat, tilt via CoreMotion, sound = real water synthesized in `Sea/SeaDSP.swift` (swell and wash, bubbles and babble, wall slaps, poke bloop and droplet plips, a tin putt-putt motor while the boat is held, knock and hull laps), driven every frame by `Shared/Toys/SeaAcoustics.swift` (water motion, wall and hull hits), tests in `SketchesForKids/Tests/SeaAudioTests.swift`; « Formes » = each shape strikes a modelled mallet instrument (`Tiles/MalletDSP.swift`, modal synthesis matched to the General MIDI bank's sampled instruments: arcs = marimba with its resonator tube, triangles = glockenspiel, quarter discs = kalimba; row = pentatonic note, column = pan; a shake = a glockenspiel run), tests in `SketchesForKids/Tests/TilesAudioTests.swift`; « Peinture » = Metal stable-fluids paint that behaves like thick paint (calm flow, opaque strokes from a round tip, pigment as Kubelka-Munk K/S so blue + yellow = green, bristle grooves carried by the flow), rendered as relief on cold-pressed paper (satin GGX sheen, ray-marched shadows, crease occlusion): the paper and its noises are baked once, the surface is computed per frame on the pigment grid, splats go in one pass per grid, the drawable is sized by hand at 2× (~5.3 ms GPU per frame on an iPhone 15 with five fingers; `KIDZY_PAINT_PERF=1` prints fps and GPU time to stderr, `KIDZY_PAINT_DEMO=2` is a five-finger load test, read on the phone with `xcrun devicectl device process launch --console --environment-variables ...`), shaders compiled at runtime from the .txt (Xcode 26 ships no Metal compiler by default), sound = a synthesized brush on paper (`Paint/BrushDSP.swift`: friction crackle, bristle grain, wet squish and bubbles, dab and lift; render-callback DSPs use `Kit/DSP.swift` + `Kit/RenderNode.swift`), `KIDZY_PAINT_DEMO=1` paints swirls for simulator captures; « Perroquet » = microphone → `Shared/RepeatDetector.swift` (phrase ends after 0.8 s of silence) → a voice character per repeat (`Parrot/VoiceDSP.swift`: chipmunk, squawk, singing robot, bouncy echo, choir, underwater; never twice in a row; it listens again only after the character's tail; `KIDZY_PARROT_VOICE=<name>` forces one in debug), « Guitare » = a recorded nylon guitar (`Guitar/NylonDSP.swift` plays `Resources/Guitar/guitar-nylon-<midi>.m4a`, one note every two semitones from MIDI 40 to 92, rendered from the MIT FluidR3 GM SoundFont, decoded once by `GuitarSamples`, preloaded at app start; three voices per string, spare voices fade a re-plucked note; the neck is low at the head and rises toward the body, frets spaced by semitones, a string the chord leaves out plays a chord tone); « Animaux » whoosh, pop and boing = `Animals/AnimalFX.swift`; parrot frames in `Resources/Parrot/` (simulator check: grant the mic with `simctl privacy`, `say` a sentence through the Mac speaker, read `log show --predicate 'subsystem == "com.screenclub.kidzy"'`, `KIDZY_PARROT_TRACE=1` logs levels four times a second); `KIDZY_SHOW=sketch:sea|paint|tiles|animals|guitar|parrot` opens one in the simulator |
| Designs | `docs/design/` | approved mock-ups: change them before changing the app's look |
| Ops | `ops/`, `ios/scripts/` | launchd agent, install on phone, TestFlight upload; `ios/scripts/make-licenses.sh` rebuilds `Toys/Resources/Licenses.txt` (every shipped package and recording, shown on the parents page) after a package change |

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
