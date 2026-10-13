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
| `Mer.dc.html` | La mer (jouet, croquis 1) | water, sun, clouds, boat; in the app the water sloshes with the tilt, the boat slides and can be dragged, a tap splashes; tilt works upright or upside down; the sun giggles when tapped and can be dragged: low = sunset colours, below the sea = night with stars; sounds (splash, plop, bump, giggle, chime) respect the silent switch |
| _(no artboard)_ | Peinture (jouet, croquis 2) | phone flat on the table: fingers paint fluid colour that swirls and mixes like wet paint (GPU fluid simulation, multi-touch, one palette colour per finger), drops thrown when the toy opens or the table is bumped, paint fades over a minute; colours mix as weighted averages with a saturation boost so blends stay vivid (no brown); generative sound (dreamy style: slow attack and release, detuned twin, octave shimmer, stereo echo): each finger is a synth voice, pentatonic pitch by height bent up by speed, pan and timbre by direction, vibrato and loudness by speed, a boing on touch; the boat in « La mer » hums by drag speed |
| _(no artboard)_ | Formes (jouet, croquis 3) | a 5-column grid of geometric stickers (Truchet arcs that connect across tiles, half-square triangles, quarter discs) on a soft checker; a tap turns a tile a quarter turn with a spring bounce and a pentatonic note (row = pitch, column = pan); a swipe turns every tile it crosses; a bump on the table shuffles the grid with a chime |
| _(no artboard)_ | Animaux (jouet, croquis 4) | one big animal sticker at a time, ten animals (vache, chat, chien, canard, mouton, coq, lion, âne, grenouille, cochon); images generated with Gemini (gemini-2.5-flash-image on the screen-club project, prompt in `ios/Tools`-era history: flat sticker, navy outline, white background) and resized to 640 px in `Resources/Animals/`; a tap bounces it, says its name and performs its cry, both Gemini TTS clips (`ios/Tools/GenerateAnimalVoices.py`, checked by `TranscribeClips.py`); swipe for the next one |
| _(no artboard)_ | Guitare (jouet, croquis 5) | an acoustic silhouette with waist, wood gradient, rosette, pickguard, headstock with pegs, fret dots, strings fanned from nut to bridge; a fingerpicking accompaniment runs on its own (96 bpm, Travis pattern, a chord every two bars) through Beatles-flavoured progressions (Let It Be, Hey Jude, Twist and Shout, I Want to Hold Your Hand); a finger across the strings strums the chord (Karplus-Strong, strings wobble); the neck is a melody pad in the song's key (pentatonic, high at the top, glides while sliding); four chord stickers hold a chord; sound hole tap or table bump = next song |
| `AdminBibliotheque.dc.html` | Admin · Bibliothèque | Semantic UI, French |
| `AdminEnvoyer.dc.html` | Admin · Envoyer | dropzone, per-file progress |
| `AdminReglages.dc.html` | Admin · Réglages | limits, end-of-day picture, PIN, devices |

Tokens: ground sky `#BFE3FF`, ink `#1F2A44`, stickers coral `#FF6B6B`, tangerine `#FFA62B`,
lemon `#FFD23F`, grass `#5FD068`, ocean `#4D96FF`, berry `#9B5DE5`, bubblegum `#FF8FAB`.
Type: Fredoka in the mock-ups, SF Rounded in the app. Tiles: 6 px ink border, 8 px hard offset
shadow, radius 28 (collections) / 24 (episodes), tilt ±2°.

Approval: _pending_ (Martial reviews on his phone; the date and remarks go here).
