# Designs

The reference for every screen. Change them before changing the app.

Live canvas (open it on the phone, pinch to zoom, Play on a frame to tap through):
https://claude.ai/artifact/GoP4FKyNQ9hWQqVZbCFYwm

The `.dc.html` files here are the sources of that canvas (one per frame, `canvas.json` is the
layout). They are static markup; the canvas renders them.

| File | Screen | Notes |
|---|---|---|
| `Main.dc.html` | Bibliothèque (kid) | sticker tiles and the sun mascot, nothing else (stars removed 2026-10-13 at Martial's request) |
| `Collection.dc.html` | Collection (kid) | episode tiles 16:9, house button back to the library |
| `Lecteur.dc.html` | Lecteur (landscape) | video only; a tap does nothing (no pause, Martial 2026-10-13) |
| `LecteurCoins.dc.html` | Lecteur, zones | for the parent: the secret corner and the tap zones |
| `Suivant.dc.html` | Suivant | end of a video: next tile with a 5 s ring, tap = play now |
| `CodeParent.dc.html` | Code parent | keypad after 4 taps top-left on the library |
| `Termine.dc.html` | Terminé pour aujourd'hui | the parent's picture (default: sleeping moon), nothing else |
| `EspaceParent.dc.html` | Espace parent | server, time left, limits, visible collections, PIN |
| `Mer.dc.html` | La mer (jouet, croquis 1) | water, sun, clouds, boat; in the app the water sloshes with the tilt, the boat slides and can be dragged, a tap splashes; the scene turns with the phone in quarter turns (upright, either side, upside down) and the rest of the tilt sloshes the water; the sun, the clouds, the water level and the boat's lane follow the part of the scene on screen; the sun giggles when tapped and can be dragged: low = sunset colours, below the sea = night with stars; sounds (splash, plop, bump, giggle, chime) respect the silent switch |
| _(no artboard)_ | Peinture (jouet, croquis 2) | phone flat on the table: fingers paint fluid colour that swirls and mixes like wet paint (GPU fluid simulation, multi-touch, one palette colour per finger), drops thrown when the toy opens or the table is bumped, paint fades over a minute; colours mix as weighted averages with a saturation boost so blends stay vivid (no brown); generative sound (dreamy style: slow attack and release, detuned twin, octave shimmer, stereo echo): each finger is a synth voice, pentatonic pitch by height bent up by speed, pan and timbre by direction, vibrato and loudness by speed, a boing on touch; the boat in « La mer » hums by drag speed |
| _(no artboard)_ | Formes (jouet, croquis 3) | a 5-column grid of geometric stickers (Truchet arcs that connect across tiles, half-square triangles, quarter discs) on a soft checker; a tap turns a tile a quarter turn with a spring bounce and a pentatonic note (row = pitch, column = pan); a swipe turns every tile it crosses; a bump on the table shuffles the grid with a chime |
| _(no artboard)_ | Animaux (jouet, croquis 4) | one big animal sticker at a time, ten animals (vache, chat, chien, canard, mouton, coq, lion, âne, grenouille, cochon); images generated with Gemini (gemini-2.5-flash-image on the screen-club project, prompt in `ios/Tools`-era history: flat sticker, navy outline, white background) and resized to 640 px in `Resources/Animals/`; a tap bounces it, says its name and performs its cry, both Gemini TTS clips (`ios/Tools/GenerateAnimalVoices.py`, checked by `TranscribeClips.py`); swipe for the next one |
| _(no artboard)_ | Guitare (jouet, croquis 5) | an acoustic silhouette with waist, wood gradient, rosette, pickguard, headstock with pegs, fret dots, strings fanned from nut to bridge; a finger across the strings strums the chord (Karplus-Strong, strings wobble) and real strums walk through Beatles-flavoured progressions (Let It Be, Hey Jude, Twist and Shout, I Want to Hold Your Hand); eight chord stickers in two rows (C, G, D, A, E, F, Am, Em) hold a chord for a few seconds; each chord has a mood colour that tints the sky and glows behind the guitar (majors warm, F ocean, minors violet and indigo), blending over half a second; the neck is a melody pad in the song's key; sound hole tap or table bump = next song |
| _(no artboard)_ | Perroquet (jouet, croquis 6) | a big parrot sticker on a branch among leaves (three Gemini frames: beak closed, beak open, head tilted with a wing up); it listens through the microphone: sound waves come toward its beak and it perks up with the voice; when the voice stops (0.8 s of silence) it repeats the phrase in a silly voice (chipmunk pitches, now and then a giant), beak flapping with the loudness, notes flying out; a tap replays the last phrase, or squawks before there is one; nothing is stored or sent |
| `AdminBibliotheque.dc.html` | Admin · Bibliothèque | Semantic UI, French |
| `AdminEnvoyer.dc.html` | Admin · Envoyer | dropzone, per-file progress |
| `AdminReglages.dc.html` | Admin · Réglages | limits, end-of-day picture, PIN, devices |

## « Sketches for kids! » (second app, the toys alone)

Its own canvas: https://claude.ai/artifact/RSLwADtiUHL5pJoQUEJQop (sources in `sketches/`; their
images are uploads of that canvas, the originals are in `sketches/art/`). Round 4 of the design,
2026-10-18, waiting for Martial's approval; the earlier sticker-style boards are retired.

Direction: a sunny toy cabinet. Each toy is a glossy 3D designer toy (Gemini 3 Pro Image, one
style reference, cut out with Vision) standing in its own coloured cubby of a white cabinet, on a
polka-dot yellow wall with a party garland. Free toys bob gently; locked toys stay still with a
yellow lock badge and lead to the gate. The grown-up zone is night blue. The parrot is the host:
the app icon, and it peeks over the gate. Kid screens have no text.

| File | Screen | Notes |
|---|---|---|
| `sketches/Main.dc.html` | Home | the cabinet, six cubbies (sea, paint, shapes, animals, guitar, parrot), garland, floor; parent button top-right |
| `sketches/HomeFree.dc.html` | Home, free | lock badges on paint, shapes, guitar, parrot; only sea and animals bob |
| `sketches/Gate.dc.html` | For grown-ups | night blue, the parrot peeking over the card, « What is seven plus five? » in words (children who read digits can't guess), two answer boxes, chunky keypad |
| `sketches/Unlock.dc.html` | Unlock all toys | the four toys fanned on a sunny panel, three ticks (pay once, family sharing, no ads), coral « Unlock for €2.99 », restore, privacy |
| `sketches/Parents.dc.html` | Parents page | a switch per toy with its 3D thumbnail, the unlock row, restore, privacy, help, the microphone line |
| `sketches/Toy.dc.html` | A toy | the real toy full screen, a 58 pt white home button with a coral house, top-left below the Dynamic Island |
| `sketches/Store1…5.dc.html` | App Store | 430 × 932 (export at 3× = 1290 × 2796): hero with the wordmark, then sea (tilted), paint, parrot, parents; one cubby colour per shot |
| `sketches/Icon.dc.html` | Icon | the 3D parrot on sunny orange, at 1024, 60, 40, 29 pt; « Sketches » under the icon |
| `sketches/Logo.dc.html` | Logo | white 3D « Sketches » with a glossy orange outline and a paint swirl on the S, the coral « for kids! » pill, the parrot waving from behind; on the wall, on night blue, on white; the round badge (parrot in a sunny disc) for avatars and stickers; `sketches/art/logo.png`, `logo-badge.png` |
| `sketches/Brand.dc.html` | Brand kit | wordmark, colours, Baloo 2, buttons, badge, home button, cubby |
| `sketches/Explore.dc.html` | Explorations | rounds 1 to 4: shelf / bubbles / cards, cabinet colours, lock styles, icons |

Tokens: wall sun `#FFC530` → `#FFD95C`, floor tangerine `#FF9F12`, CTA coral `#F04A43` (lip
`#C8322C`), ink `#1F2A44`, grown-up night `#2A3768` → `#3D57A6`, cabinet `#FFFFFF`/`#F4F0FA`
(lip `#E6DFF0`); cubbies sea `#8FD3FF`, paint `#FFA2C0`, shapes `#B6A2FF`, animals `#8FDB7C`,
guitar `#79D9CC`, parrot `#FFD45A`. Type: Baloo 2 (800 titles, 700 body, 600 small), bundled in
the app. Buttons are chunky: a darker lip under each, pressed = moves down 3–4 px.
Art: `ios/Tools/GenerateToyArt.py` (prompts) and `ios/Tools/Cutout.swift` (Vision subject lift).
