"""The ad's clock: 20 s at 30 fps on a 120 bpm grid (one beat = 15 frames = 0.5 s).

Every shot is rendered on its own local timeline, frames 1..N; beat b of a shot falls on local frame
1 + 15 * b. Cuts land on beats, so any 120 bpm music fits under the picture.
Shared by the Blender shot scripts, the audio builder and build.py (plain Python, no bpy)."""

FPS = 30
BPM = 120
BEAT = FPS * 60 // BPM  # 15 frames

# (shot id, beats, screen roles it shows, what happens)
SHOTS = [
    ("1", 6, ["home"], "a finger taps the toy cabinet; the parrot bursts out of the screen"),
    ("2", 5, ["sea"], "water gushes out of the sea toy; the boat surfs the wave"),
    ("3", 5, ["paint"], "blue and yellow paint spiral out and turn green where they cross"),
    ("4", 5, ["guitar"], "the guitar strums itself while the shapes rain down"),
    ("5", 4, ["animals"], "the cow jumps out and bounces on the table"),
    ("6a", 2, ["closeup-paint"], "the real app: paint, close up"),
    ("6b", 2, ["closeup-sea"], "the real app: the sea, close up"),
    ("6c", 2, ["closeup-guitar"], "the real app: the guitar, close up"),
    ("7", 4, ["home-end"], "a tornado sucks every toy back into the phone"),
    ("8", 5, [], "end card: logo, the six toys, « Six toys. Nothing to read. No ads. »"),
]


def frames(shot_id):
    return dict((s[0], s[1]) for s in SHOTS)[shot_id] * BEAT


def start(shot_id):
    """First global frame (0-based) of a shot."""
    t = 0
    for sid, beats, _, _ in SHOTS:
        if sid == shot_id:
            return t
        t += beats * BEAT
    raise KeyError(shot_id)


def total_frames():
    return sum(b for _, b, _, _ in SHOTS) * BEAT


def beat_frame(b):
    """Local frame of beat b (b may be fractional: 0.5 = an eighth note)."""
    return 1 + round(BEAT * b)


def global_seconds(shot_id, local_frame):
    return (start(shot_id) + local_frame - 1) / FPS


def roles():
    out = []
    for _, _, rs, _ in SHOTS:
        out += [r for r in rs if r not in out]
    return out
