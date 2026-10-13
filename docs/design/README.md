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
| `Mer.dc.html` | La mer (jouet, croquis 1) | water, sun, clouds, boat; in the app the water sloshes with the tilt, the boat slides and can be dragged, a tap splashes |
| `AdminBibliotheque.dc.html` | Admin · Bibliothèque | Semantic UI, French |
| `AdminEnvoyer.dc.html` | Admin · Envoyer | dropzone, per-file progress |
| `AdminReglages.dc.html` | Admin · Réglages | limits, end-of-day picture, PIN, devices |

Tokens: ground sky `#BFE3FF`, ink `#1F2A44`, stickers coral `#FF6B6B`, tangerine `#FFA62B`,
lemon `#FFD23F`, grass `#5FD068`, ocean `#4D96FF`, berry `#9B5DE5`, bubblegum `#FF8FAB`.
Type: Fredoka in the mock-ups, SF Rounded in the app. Tiles: 6 px ink border, 8 px hard offset
shadow, radius 28 (collections) / 24 (episodes), tilt ±2°.

Approval: _pending_ (Martial reviews on his phone; the date and remarks go here).
