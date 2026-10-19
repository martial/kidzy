"""The ad's sound, from the app's own sounds and instruments, placed on the 120 bpm grid.

  <Blender's python3> -I audio.py OUT_DIR [music file]

- Sound effects: the app's sound files (ios/Toys/Resources/Sounds: squawk, moo, splash, plop, chime,
  giggle, bump), snippets recorded from the app (sfx/: water, boat motor, brush), and ports of the app's
  synths: the mallets (Tiles/MalletDSP.swift: marimba, glockenspiel, kalimba, modal synthesis with the
  same partials), the whoosh, pop and boing (Animals/AnimalFX.swift), the nylon guitar samples
  (ios/Toys/Resources/Guitar).
- Music: the file given (music/ in the ad folder) if any, else a placeholder bed played on the app's
  instruments (nylon guitar strums, marimba melody and bass, glockenspiel sparkles) at 120 bpm.
- Writes OUT_DIR/sfx.wav, bed.wav, mix.wav (normalised to -14 LUFS, -1.5 dBTP: Instagram's level).
Runs with numpy (Blender ships it); ffmpeg decodes and measures."""
import json, math, os, subprocess, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
AD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(AD))
SOUNDS = os.path.join(REPO, "ios", "Toys", "Resources", "Sounds")
GUITAR = os.path.join(REPO, "ios", "Toys", "Resources", "Guitar")
SFX = os.path.join(AD, "sfx")
sys.path.insert(0, HERE)
import timeline as T

SR = 48000
RNG = np.random.default_rng(7)


def load(path, rate=SR):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(rate), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


_cache = {}
def sound(name, start=0.0, length=None):
    if name not in _cache:
        for d, ext in ((SOUNDS, ".wav"), (SFX, ".m4a"), (SFX, ".wav")):
            p = os.path.join(d, name + ext)
            if os.path.exists(p):
                _cache[name] = load(p)
                break
        else:
            raise SystemExit(f"missing sound {name}")
    s = _cache[name][int(start * SR):]
    if length:
        s = s[:int(length * SR)]
        fade = min(len(s), int(0.05 * SR))
        s = s.copy()
        s[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return s


def resample(sig, ratio):
    """Play `sig` `ratio` times faster (pitch up by the same ratio), the way the app's sampler does."""
    n = int(len(sig) / ratio)
    x = np.arange(n) * ratio
    return np.stack([np.interp(x, np.arange(len(sig)), sig[:, c]) for c in range(sig.shape[1])], 1).astype(np.float32)


def db(x):
    return 10 ** (x / 20)


def stereo(mono, pan=0.0):
    a = (max(-1, min(1, pan)) + 1) * 0.25 * math.pi
    return np.stack([mono * math.cos(a), mono * math.sin(a)], 1).astype(np.float32)


class Track:
    def __init__(self, seconds):
        self.buf = np.zeros((int(seconds * SR), 2), dtype=np.float32)

    def add(self, sig, t, gain=0.0, pan=None):
        if sig.ndim == 1:
            sig = stereo(sig, pan or 0.0)
        elif pan is not None:
            m = sig.mean(1)
            sig = stereo(m, pan)
        i = int(round(t * SR))
        if i < 0:
            sig, i = sig[-i:], 0
        j = min(len(self.buf), i + len(sig))
        if j > i:
            self.buf[i:j] += sig[:j - i] * db(gain)


# ---------------------------------------------------------------- the app's synths, ported
class SVF:
    """Simper's trapezoidal state-variable filter (Kit/DSP.swift)."""
    def __init__(self, cutoff, q):
        f = min(cutoff, SR * 0.45)
        g = math.tan(math.pi * f / SR)
        self.k = 1 / max(0.05, q)
        self.a1 = 1 / (1 + g * (g + self.k))
        self.a2 = g * self.a1
        self.a3 = g * self.a2
        self.ic1 = self.ic2 = 0.0

    def band(self, x):
        out = np.empty_like(x)
        a1, a2, a3, k, ic1, ic2 = self.a1, self.a2, self.a3, self.k, self.ic1, self.ic2
        for i, v in enumerate(x):
            v3 = v - ic2
            v1 = a1 * ic1 + a2 * v3
            v2 = ic2 + a2 * ic1 + a3 * v3
            ic1, ic2 = 2 * v1 - ic1, 2 * v2 - ic2
            out[i] = v1 * k
        self.ic1, self.ic2 = ic1, ic2
        return out


def _mode(f, t60, level, n):
    """The impulse response of one two-pole resonator (MalletDSP.set)."""
    w = 2 * math.pi * f / SR
    r = 10 ** (-3 / (max(0.01, t60) * SR))
    k = np.arange(n)
    return (level * r ** k * np.sin((k + 1) * w)).astype(np.float64)


def fftconv(a, b):
    n = len(a) + len(b) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(a, size) * np.fft.rfft(b, size), size)[:n]


def mallet(instrument, f0, velocity=0.8):
    """One strike of the app's marimba, glockenspiel or kalimba (MalletDSP.strike), mono."""
    v = max(0.05, min(1.0, velocity))
    bright = 0.35 + 0.65 * v
    jit = lambda a: 1 + (RNG.random() - 0.5) * 2 * a
    f0 = f0 * 2 ** ((RNG.random() - 0.5) * 4 / 1200)
    parts, gain = [], 1.0
    if instrument == "marimba":
        t = (262 / f0) ** 0.75
        parts = [(1, 0.12, 0.3 * t), (4 * jit(0.002), 0.025 * jit(0.15), 1.5 * t), (10.2 * jit(0.004), 0.32 * bright * jit(0.2), 0.22 * t),
                 (10.55 * jit(0.004), 0.15 * bright * jit(0.3), 0.15 * t)]
        gain, pulse_s = 2.0, (0.0004 - 0.00015 * v) * jit(0.12)
        contact, contact_s, contact_hz = 0.12, 0.012, 2800
    elif instrument == "glockenspiel":
        t = (1000 / f0) ** 0.35
        parts = [(1, 1, 2.2 * t), (2.756, 0.18 * jit(0.3), 1.2 * t), (5.404 * jit(0.002), 2.2 * bright * jit(0.15), 1.7 * t),
                 (8.933, 0.12 * bright, 0.8 * t), (13.34 * jit(0.004), 0.3 * bright * jit(0.25), 1.4 * t)]
        gain, pulse_s = 0.16, (0.00016 - 0.00006 * v) * jit(0.12)
        contact, contact_s, contact_hz = 0.035, 0.0006, 9000
    else:  # kalimba
        t = (262 / f0) ** 0.4
        parts = [(1, 1, 1.6 * t), (2, 0.04, 0.5 * t), (5.87 * jit(0.01), 0.1 * bright * jit(0.2), 0.3 * t),
                 (11.9 * jit(0.01), 0.05 * bright * jit(0.3), 0.08), (0.59, 0.35, 0.3), (1.44, 0.045, 0.3)]
        pulse_s = (0.0005 - 0.0002 * v) * jit(0.12)
        contact, contact_s, contact_hz = 0.03, 0.004, 900
    longest = max(p[2] for p in parts)
    n = int(min(3.5, longest * 1.2 + 0.05) * SR)
    L = max(2, int(pulse_s * SR))
    area = (math.pi / 2) / L * 0.34 * gain * v ** 1.3 * jit(0.08)
    pulse = np.sin(math.pi * (np.arange(L) + 0.5) / L) * area
    fundamental = None
    y = np.zeros(n + L - 1)
    for k, (ratio, level, t60) in enumerate(parts):
        f = f0 * ratio
        if 20 < f < min(SR * 0.45, 18000):
            out = np.convolve(pulse, _mode(f, t60, level, n))
            y += out
            if k == 0:
                fundamental = out
    if instrument == "marimba" and fundamental is not None:
        # the resonator tube, driven by the bar's fundamental
        coupling = 0.0045 * 48000 / SR
        tube = fftconv(fundamental * coupling, _mode(f0 * 1.0015, 2.0 * (262 / f0) ** 0.75, 1, n))[:n + L - 1]
        y += tube
    m = int(contact_s * SR * 6)
    burst = RNG.uniform(-1, 1, m) * contact * v ** 1.5 * jit(0.2) * np.exp(-np.arange(m) / (contact_s * SR))
    y[:m] += SVF(contact_hz * jit(0.1), 0.9).band(burst)
    return y.astype(np.float32)


def whoosh(length=0.22, direction=1, f_lo=500, f_hi=3100, level=0.32):
    """AnimalFX's whoosh: noise through a band-pass sweeping up, across the stereo."""
    n = int(length * SR)
    noise = RNG.uniform(-1, 1, n)
    out = np.empty(n)
    blk = 256
    svf = SVF(f_lo, 1.3)
    for i in range(0, n, blk):
        t = i / n
        f = f_lo + (f_hi - f_lo) * t * t
        g = math.tan(math.pi * min(f, SR * 0.45) / SR)
        svf.a1 = 1 / (1 + g * (g + svf.k))
        svf.a2 = g * svf.a1
        svf.a3 = g * svf.a2
        out[i:i + blk] = svf.band(noise[i:i + blk])
    t = np.arange(n) / n
    env = np.where(t < 0.3, t / 0.3, (1 - t) / 0.7)
    w = out * env * env * level
    ang = (direction * (t * 1.6 - 0.8) + 1) * 0.25 * math.pi
    return np.stack([w * np.cos(ang), w * np.sin(ang)], 1).astype(np.float32)


def pop(freq=None):
    """AnimalFX's landing: a bubble pop gliding up and a 120 Hz thump."""
    n = int(0.25 * SR)
    t = np.arange(n)
    f = (freq or 650 + 300 * RNG.random())
    glide = 1.7 ** (t / (0.03 * SR))
    phase = np.cumsum(2 * math.pi * f * glide / SR)
    p = np.sin(phase) * 0.16 * np.exp(-t / (0.012 * SR))
    th = np.sin(2 * math.pi * 120 * t / SR) * 0.22 * np.exp(-t / (0.03 * SR))
    return (p + th).astype(np.float32)


def boing(f0=330):
    """AnimalFX's spring: 330 Hz wobbling ±18 % at 14 Hz, the wobble dying away."""
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.18 * np.exp(-t * 9) * np.sin(2 * math.pi * 14 * t))
    ph = np.cumsum(2 * math.pi * f / SR)
    env = np.minimum(1, t / 0.006) * np.exp(-t * 11)
    return ((np.sin(ph) + 0.25 * np.sin(2 * ph)) * env * 0.13).astype(np.float32)


_gsamples = {}
def guitar(midi, velocity=0.7, length=2.5):
    """One nylon note: the nearest recorded sample (every two semitones), repitched (GuitarSamples)."""
    m = max(40, min(92, int(round(midi / 2) * 2)))
    if m not in _gsamples:
        _gsamples[m] = load(os.path.join(GUITAR, f"guitar-nylon-{m}.m4a")).mean(1)
    s = _gsamples[m]
    if midi != m:
        x = np.arange(int(len(s) / 2 ** ((midi - m) / 12))) * 2 ** ((midi - m) / 12)
        s = np.interp(x, np.arange(len(s)), s)
    s = s[:int(length * SR)]
    if velocity < 0.6:     # a softer pluck is darker: a short moving average
        k = int(2 + (0.6 - velocity) * 10)
        s = np.convolve(s, np.ones(k) / k, mode="same")
    fade = int(0.08 * SR)
    s = s.copy()
    s[-fade:] *= np.linspace(1, 0, fade)
    return (s * (0.3 + 0.7 * velocity ** 1.3)).astype(np.float32)


CHORDS = {  # open-position voicings, low to high (MIDI)
    "C": [48, 52, 55, 60, 64], "G": [43, 47, 50, 55, 59, 67], "Am": [45, 52, 57, 60, 64],
    "F": [41, 48, 53, 57, 60, 65], "Dm": [50, 57, 62, 65], "Em": [40, 47, 52, 55, 59, 64],
}


def strum(track, chord, t, velocity=0.7, down=True, spread=0.011, gain=0.0, length=2.2):
    notes = CHORDS[chord] if down else list(reversed(CHORDS[chord]))[:4]
    for i, m in enumerate(notes):
        pan = -0.35 + 0.7 * (CHORDS[chord].index(m) / max(1, len(CHORDS[chord]) - 1))
        track.add(guitar(m, velocity * (1 - 0.04 * i), length), t + i * spread, gain, pan * 0.6)


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


# ---------------------------------------------------------------- the score
BAR = 4 * 60 / T.BPM          # 2 s
PROG = ["C", "G", "Am", "F", "C", "G", "Am", "F", "F", "C"]   # bar 9 is F then G
MELODY = {  # eighth notes per bar (None = rest), MIDI
    "C": [67, None, 64, 67, 72, None, 67, 64], "G": [74, None, 71, 74, 67, None, 71, 74],
    "Am": [76, None, 72, 76, 69, None, 72, 76], "F": [65, 69, 72, None, 69, 65, 67, None],
}


def chord_at(seconds):
    b = int(seconds // BAR)
    if b == 8 and (seconds % BAR) >= BAR / 2:
        return "G"
    return PROG[min(b, len(PROG) - 1)]


def bed(seconds):
    """The placeholder music: the app's guitar, marimba and glockenspiel at 120 bpm."""
    tr = Track(seconds + 3)
    for b, ch in enumerate(PROG):
        t0 = b * BAR
        last = b == len(PROG) - 1
        halves = [("F", 0), ("G", 2)] if b == 8 else [(ch, 0)]
        # guitar: down on 1 and 3, ups on the off-beats
        for c, half_at in halves:
            pat = [(0, 0.72, True), (1.5, 0.42, False), (2, 0.62, True), (3, 0.4, False), (3.5, 0.5, True)] if not last else [(0, 0.8, True)]
            for beat, vel, down in pat:
                if half_at == 2 and beat < 2 or (len(halves) > 1 and half_at == 0 and beat >= 2):
                    continue
                strum(tr, c, t0 + beat * 0.5, vel, down, gain=-6, length=3.5 if last else 1.6)
            # marimba bass: the root on 1 and 3
            root = CHORDS[c][0]
            while root > 52:
                root -= 12
            for beat in ((0, 2) if not last else (0,)):
                if (half_at == 2 and beat < 2) or (len(halves) > 1 and half_at == 0 and beat >= 2):
                    continue
                tr.add(mallet("marimba", hz(root + 12), 0.75), t0 + beat * 0.5, -2, -0.1)
        # marimba melody from bar 2, glockenspiel doubling from bar 5
        if 1 <= b <= 8:
            mel = MELODY[ch if ch in MELODY else "C"]
            for i, m in enumerate(mel):
                if m is None:
                    continue
                vel = 0.75 if i % 2 == 0 else 0.55
                tr.add(mallet("marimba", hz(m), vel), t0 + i * 0.25, -3, 0.25)
                if b >= 4 and i in (0, 4):
                    tr.add(mallet("glockenspiel", hz(m + 12), 0.5), t0 + i * 0.25, -10, 0.4)
        if last:
            for i, m in enumerate((72, 76, 79, 84)):
                tr.add(mallet("glockenspiel", hz(m), 0.6), t0 + 0.06 * i, -6, -0.2 + 0.15 * i)
        # a soft pulse on the beat (the app's bump), from bar 2 to bar 9
        if 1 <= b <= 8:
            for k in range(4):
                tr.add(sound("bump"), t0 + k * 0.5, -10)
    return tr.buf


def at(shot, frame):
    return T.global_seconds(shot, frame)


def effects(seconds):
    tr = Track(seconds + 3)
    B = T.beat_frame
    # 1 · the tap, the burst, the parrot
    tap = at("1", B(1))
    tr.add(pop(900), tap - 0.01, -2)
    for i, m in enumerate((84, 88, 91, 96)):
        tr.add(mallet("glockenspiel", hz(m), 0.75), tap + 0.03 * i, -4, -0.3 + 0.2 * i)
    tr.add(sound("chime"), tap + 0.02, -9)
    tr.add(sound("animal-perroquet", 0.05, 0.95), tap + 0.08, -3, 0.1)
    tr.add(sound("giggle"), at("1", B(3)), -8, -0.2)
    tr.add(whoosh(0.3, -1), at("1", B(4) - 2), -2)
    tr.add(whoosh(0.22, 1, 700, 3600), at("1", 84), 0)
    voice = next((os.path.join(SFX, f) for f in sorted(os.listdir(SFX)) if f.startswith("sketches-voice")), None)
    if voice:   # « Sketches! » recorded by a person, made a parrot (pitched up like the app's chipmunk)
        v = resample(load(voice), 2 ** (7 / 12))
        tr.add(v, at("1", B(2)), -2)
    # 2 · the sea floods out, the boat's motor
    tr.add(sound("water", 0.0, 3.0), at("2", 1), -4)
    tr.add(resample(sound("splash"), 0.85), at("2", 2), -2)
    tr.add(sound("splash"), at("2", B(1)), 0, 0.3)
    tr.add(pop(500), at("2", B(1)), -8, 0.3)
    tr.add(sound("putt", 0.0, 2.0), at("2", 8), -6, -0.1)
    for f in (B(2), B(3), B(4)):
        tr.add(resample(sound("plop"), 0.8 + 0.4 * RNG.random()), at("2", f), -9, RNG.uniform(-0.5, 0.5))
    tr.add(whoosh(0.22, 1, 600, 3400), at("2", 69), 0)
    # 3 · the paint: the brush, bloops as drops fly
    tr.add(sound("brush", 0.0, 2.4), at("3", 1), -2)
    for f in (B(1), B(1) + 3, B(3), B(3) + 2):
        tr.add(resample(sound("plop"), 0.6 + 0.2 * RNG.random()), at("3", f), -6, RNG.uniform(-0.4, 0.4))
    tr.add(whoosh(0.22, 1, 600, 3400), at("3", 69), 0)
    # 4 · the guitar strums itself on every beat, each shape rings as it lands
    for b in range(5):
        t = at("4", B(b))
        strum(tr, chord_at(t), t, 0.85 if b % 2 == 0 else 0.7, b % 2 == 0, 0.009, -1)
    kinds = ["quarter", "triangle", "half", "square", "arch"]
    instr = {"quarter": "kalimba", "triangle": "glockenspiel", "half": "marimba", "square": "marimba", "arch": "marimba"}
    penta = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81]
    for i in range(24):        # same landing frames as shots.py shot4
        land = 3 + round(7.5 * i * 0.42)
        if 1 <= land <= T.frames("4"):
            ins = instr[kinds[i % 5]]
            m = penta[(i * 3) % len(penta)] + (12 if ins == "glockenspiel" else 0)
            tr.add(mallet(ins, hz(m), 0.7), at("4", land), -5 if ins != "glockenspiel" else -9, -0.6 if i % 2 else 0.6)
    tr.add(whoosh(0.22, -1, 600, 3400), at("4", 69), 0)
    # 5 · the cow
    tr.add(pop(700), at("5", 2), -4)
    tr.add(boing(380), at("5", 3), -4)
    tr.add(resample(sound("animal-vache", 0.06, 1.25), 1.1), at("5", 19), 1)   # one moo, a touch brighter, as it hangs at the top
    tr.add(pop(420), at("5", B(2)), -2)
    tr.add(boing(300), at("5", B(2)), -3)
    tr.add(pop(480), at("5", B(3)), -5)
    tr.add(boing(340), at("5", B(3)), -6)
    # 6 · the real app, with its real sounds
    tr.add(sound("brush", 2.0, 1.0), at("6a", 1), -3)
    tr.add(sound("water", 1.5, 1.0), at("6b", 1), -3)
    t = at("6c", 1)
    strum(tr, chord_at(t), t, 0.8, True, 0.012, -2)
    strum(tr, chord_at(t + 0.5), t + 0.5, 0.6, False, 0.012, -4)
    # 7 · the tornado: a long rising whoosh, a falling glockenspiel as the toys go in
    tr.add(whoosh(2.0, 1, 250, 2600, 0.45), at("7", 1), 0)
    tr.add(whoosh(1.6, -1, 300, 1800, 0.3), at("7", 6), -3)
    for i, m in enumerate(range(96, 72, -2)):
        tr.add(mallet("glockenspiel", hz(m), 0.55), at("7", 8 + 3.2 * i), -10, math.sin(i))
    for f in (32, 37, 40, 43, 46, 48, 50):
        tr.add(resample(sound("plop"), 1.3 + 0.3 * RNG.random()), at("7", f), -8, RNG.uniform(-0.3, 0.3))
    tr.add(sound("chime"), at("7", T.frames("7") - 4), -3)
    # 8 · the end card
    tr.add(pop(800), at("8", 4), -4)
    for i, m in enumerate((84, 88, 91)):
        tr.add(mallet("glockenspiel", hz(m), 0.65), at("8", 5) + 0.05 * i, -6, -0.2 + 0.2 * i)
    for i in range(6):
        tr.add(pop(500 + 60 * i), at("8", 10 + round(3.75 * i)), -7, -0.5 + 0.2 * i)
    for i, m in enumerate((72, 76, 79)):
        tr.add(mallet("marimba", hz(m), 0.85), at("8", B(2) + 7 * i), -2, 0.0)
    return tr.buf


def loudnorm(src, dst, target=-14.0):
    """Two-pass EBU R128 normalisation with ffmpeg."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", src, "-af", f"loudnorm=I={target}:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-"],
                       capture_output=True, text=True)
    js = r.stderr[r.stderr.rfind("{"):r.stderr.rfind("}") + 1]
    m = json.loads(js)
    af = (f"loudnorm=I={target}:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
          f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-af", af, "-ar", str(SR), dst], check=True)


def write(path, buf):
    peak = float(np.abs(buf).max()) or 1.0
    if peak > 0.98:
        buf = buf * (0.98 / peak)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-c:a", "pcm_s24le", path],
                   input=buf.astype(np.float32).tobytes(), check=True)


def main():
    out = sys.argv[1]
    music = sys.argv[2] if len(sys.argv) > 2 else None
    os.makedirs(out, exist_ok=True)
    seconds = T.total_frames() / T.FPS
    n = int(seconds * SR)
    fx = effects(seconds)[:n]
    if music:
        m = load(music)[:n]
        m = np.pad(m, ((0, n - len(m)), (0, 0)))
        fade = int(0.8 * SR)
        m[-fade:] *= np.linspace(1, 0, fade)[:, None]
        music_gain = -8
    else:
        m = bed(seconds)[:n]
        music_gain = -4
    # duck the music under the real app's sounds (shot 6)
    env = np.ones(n, dtype=np.float32)
    a, b = int(at("6a", 1) * SR), int(at("7", 1) * SR)
    ramp = int(0.08 * SR)
    env[a:b] = db(-6)
    env[a - ramp:a] = np.linspace(1, db(-6), ramp)
    env[b:b + ramp] = np.linspace(db(-6), 1, ramp)
    mix = fx + m * db(music_gain) * env[:, None]
    fade = int(0.25 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    write(os.path.join(out, "sfx.wav"), fx)
    write(os.path.join(out, "bed.wav"), m)
    write(os.path.join(out, "premix.wav"), mix)
    loudnorm(os.path.join(out, "premix.wav"), os.path.join(out, "mix.wav"))
    print("wrote", os.path.join(out, "mix.wav"))


if __name__ == "__main__":
    main()
