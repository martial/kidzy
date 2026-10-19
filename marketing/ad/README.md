# « The toys break out » — the Sketches for kids! ad

A 20-second vertical ad (1080×1920, 30 fps, Instagram/TikTok/Reels): a finger taps the phone, the parrot
bursts out, the sea floods out with the boat, blue and yellow paint spiral out and turn green, the guitar
strums while the shapes rain down, the cow jumps out, three close-ups of the real app, a tornado sucks
every toy back in, end card « Six toys. Nothing to read. No ads. ».

Rendered in Blender (Cycles, headless): a real 3D table, light and phone, the toys as cut-out art on
cards that always face the camera, real 3D water, paint, shapes, confetti and tornado. **No AI video.**
The phone screens are clips of the real app, swappable (below). The sound is the app's own sounds and
instruments on a 120 bpm grid.

```
./render.sh               # the ad: build/sketches-ad-vertical.mp4 (+ -strip.png, one frame per shot)
./render.sh --preview     # a fast low-res animatic: build/preview/sketches-ad-preview.mp4
./render.sh --preview --every 3     # faster still (one frame in three, held)
./render.sh --shots 2,7   # only these shots; --force re-renders them even if nothing changed
```

Needs: Blender 4.3 in /Applications (or `BLENDER=/path/to/Blender`), ffmpeg, Xcode's `swiftc` (draws
the end-card text), python3. Only what changed is rendered again: each shot keeps a hash of everything
it uses (its code, the shared code, the art, its screens, the settings).

## Updating the screens

Every phone screen in the ad is one **role** in `screens.json`, fed by a file in `screens/`:

| Role | Shot | File it reads | What it shows |
|---|---|---|---|
| `home` | 1 (0–3 s) | `home` | the toy cabinet, tapped on the parrot |
| `sea` | 2 (3–5.5 s) | `sea` | the sea, under the wave that gushes out |
| `paint` | 3 (5.5–8 s) | `paint` | paint, under the paint spiral |
| `guitar` | 4 (8–10.5 s) | `guitar` | the guitar, small in the foreground |
| `animals` | 5 (10.5–12.5 s) | `animals` | the animal card the cow jumps out of |
| `closeup-paint` | 6a (12.5–13.5 s) | `paint` | **full screen close-up**: someone painting |
| `closeup-sea` | 6b (13.5–14.5 s) | `sea` | **full screen close-up**: the sea moving |
| `closeup-guitar` | 6c (14.5–15.5 s) | `guitar` | **full screen close-up**: the guitar played |
| `home-end` | 7 (15.5–17.5 s) | `home` | the cabinet everything goes back into |

Several roles can read the same file at different moments: `start` is the second of the clip shown
on the shot's first frame. Other fields: `speed` (playback speed), `crop` = `[top, bottom, left,
right]` fractions cut off the source before it is fitted to the phone's screen (filled, centred).

`file` is a name without extension: `paint` finds `screens/paint.mov`, else `paint.mp4`, else
`paint.png`. A `.mov` wins over the `.mp4` placeholders, so a new recording dropped next to a
placeholder replaces it. A still (`.png`/`.jpg`) works too: the screen just doesn't move.

The placeholders are simulator recordings (a little laggy). Real recordings from the iPhone are much
better.

### Recording the screens automatically (recommended)

`python3 -I scripts/record_phone.py` records every screen on the real iPhone, smooth (60 fps) and with
the app's sound: plug the iPhone in over USB, unlock it (Auto-Lock: Never while recording), and let
the terminal use the Camera the first time (that is how macOS sees an iPhone screen). A UI test plays
each toy on the phone while `ios/Tools/PhoneCapture.swift` records it; recording starts only once the
app is open, so nothing else on the phone ends up in a clip. Name screens to redo only some of them
(`record_phone.py sea paint`). Then set the `start` of their roles in `screens.json` and `./render.sh`.

### What to record on the iPhone by hand

Settings first: Do Not Disturb on, Sketches open with all toys unlocked. Control Centre → Screen
Recording (long-press: microphone off, the sound is not used). Record each toy separately, a few
seconds longer than needed, then AirDrop the clips to the Mac.

| File to make | Toy | Length | What to do |
|---|---|---|---|
| `screens/home.mov` | the toy cabinet (home) | 6 s | nothing: just the cabinet on screen (a screenshot as `home.png` is fine too) |
| `screens/sea.mov` | La mer | 10 s | tilt the phone left and right so the water sloshes and the boat slides, tap the water for a splash |
| `screens/paint.mov` | Peinture | 10 s | from a blank page: a big blue loop, then swirl yellow through it until green shows, then a coral stroke |
| `screens/guitar.mov` | Guitare | 6 s | strum the strings a few times, change chord once or twice |
| `screens/animals.mov` | Animaux | 5 s | tap the cow (it bounces), then swipe to the cat |

Then:

1. Rename each clip as in the table and put it in `marketing/ad/screens/`.
2. Watch the clip and set the `start` of its roles in `screens.json` to the second where the good part
   begins (for example the moment green appears in the paint, for `closeup-paint`).
3. `./render.sh`: only the shots showing those screens are rendered again, then the video is put back
   together. Count about 1 to 3 minutes per shot second.

## Sound

- **Effects** (`scripts/audio.py`): the app's sound files (squawk, moo, splash, plop, chime, giggle,
  bump), snippets recorded from the app (`sfx/`: water, boat motor, brush), and ports of the app's own
  synths: the mallets of « Formes » (marimba, glockenspiel, kalimba, same partials as
  `Tiles/MalletDSP.swift`), the whoosh, pop and boing of « Animaux », the nylon guitar samples.
- **Music**: undecided. Drop one file in `music/` (wav, mp3, m4a, aif or flac; the first one is used)
  and `render.sh` mixes it under the effects and fades it at the end. Without a file, a placeholder bed
  plays on the app's instruments (guitar strums, marimba melody and bass, glockenspiel) at 120 bpm.
  The cuts are on a 120 bpm grid (one beat = 0.5 s), so a 120 bpm track sits on them; the music must be
  licensed for advertising.
- **The parrot's « Sketches! »** (optional): record someone saying « Sketches! » as
  `sfx/sketches-voice.wav`; it plays at 1 s, pitched up like the parrot toy's chipmunk voice.
- The mix is normalised to −14 LUFS, −1.5 dBTP (Instagram's level).

## End card

The App Store badge is not drawn: once the app is live, download the official one from Apple's
marketing resources and save it as `badge.png` here; it is laid over the end card, centred, from 19 s.

## Files

| Path | What |
|---|---|
| `render.sh` | the one command |
| `screens.json`, `screens/` | the phone screens (placeholders: simulator recordings) |
| `scripts/build.py` | prepares the screens, renders the shots that changed, builds the sound, assembles |
| `scripts/timeline.py` | the clock: shots, beats, which screen each shot shows |
| `scripts/shots.py` | one function per shot: set, animation, camera (all keyframed) |
| `scripts/adlib.py` | the shared set, phone, materials, props, keyframe and billboard helpers |
| `scripts/audio.py` | the sound |
| `scripts/TextPNG.swift` | the end card's Baloo 2 text |
| `scripts/gen_art.py` | regenerates the 2K toy poses with Gemini 3 Pro Image (stills only) |
| `scripts/critique.py`, `critique_video.py` | ask Gemini to review a frame sheet or the video |
| `art/cut/` | the cut-out toys, hand, note and logo (WebP with alpha) |
| `art/kitchen.jpg`, `art/wood.jpg` | the blurred kitchen behind, the oak table |
| `sfx/` | the snippets recorded from the app |
| `build/` | everything generated (git-ignored) |

To change the art: `scripts/gen_art.py` makes new 2K images on white, `ios/Tools/Cutout.swift` lifts
the subject, then `cwebp -q 90 -alpha_q 100 -resize 1400 0 in.png -o art/cut/name.webp`.

## Later: the 16:9 cut

Not built yet. The plan: a `--wide` variant at 1920×1080 that re-frames every shot (wider lenses,
cameras pulled back, the end card laid out in a row), with the same timeline, screens and sound.
