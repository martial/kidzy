"""Synthesises the sea toy's little sounds as 16-bit mono WAV files (stdlib only).
Usage: python3 ios/Tools/GenerateSounds.py ios/Kidzy/Resources/Sounds
"""
import math, random, struct, sys, wave, os

RATE = 44100
random.seed(7)

def write(name, samples, out):
    peak = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, s / peak * 0.9)) * 32767)) for s in samples)
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data)

def env(t, attack, decay):
    return min(1, t / attack) * math.exp(-t / decay) if attack > 0 else math.exp(-t / decay)

def splash():
    n = int(0.6 * RATE); out = []; lp = 0.0
    for i in range(n):
        t = i / RATE
        noise = random.uniform(-1, 1)
        lp += (noise - lp) * 0.18                      # low-pass: "psshh" not "hiss"
        plop = math.sin(2 * math.pi * (160 - 90 * t) * t) * env(t, 0.004, 0.06)
        out.append(lp * env(t, 0.01, 0.14) * 0.8 + plop * 0.9)
    return out

def plop():
    n = int(0.16 * RATE); out = []
    for i in range(n):
        t = i / RATE
        out.append(math.sin(2 * math.pi * (420 - 260 * t) * t) * env(t, 0.003, 0.05))
    return out

def bump():
    n = int(0.18 * RATE); out = []
    for i in range(n):
        t = i / RATE
        f = 190 - 110 * t
        out.append((math.sin(2 * math.pi * f * t) + 0.3 * math.sin(2 * math.pi * f * 2.01 * t)) * env(t, 0.002, 0.045))
    return out

def giggle():
    notes = [(523.25, 0.0), (659.25, 0.11), (783.99, 0.22), (1046.5, 0.33)]
    n = int(0.6 * RATE); out = [0.0] * n
    for f, start in notes:
        for i in range(int(start * RATE), n):
            t = i / RATE - start
            vib = 1 + 0.012 * math.sin(2 * math.pi * 9 * t)
            out[i] += (math.sin(2 * math.pi * f * vib * t) + 0.25 * math.sin(2 * math.pi * 2 * f * t)) * env(t, 0.006, 0.09)
    return out

def chime():
    n = int(1.2 * RATE); out = []
    for i in range(n):
        t = i / RATE
        out.append((math.sin(2 * math.pi * 880 * t) + 0.5 * math.sin(2 * math.pi * 1320 * t) + 0.25 * math.sin(2 * math.pi * 1760 * t)) * env(t, 0.004, 0.32))
    return out

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name, fn in [("splash", splash), ("plop", plop), ("bump", bump), ("giggle", giggle), ("chime", chime)]:
        write(name, fn(), out); print("wrote", name + ".wav")


# ---------- animal cries, cartoon style ----------

def tone(n, f_of_t, envelope, harmonics=((1, 1.0), (2, 0.3), (3, 0.12)), vib=(0, 0), noise=0.0):
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = f_of_t(t) * (1 + vib[1] * math.sin(2 * math.pi * vib[0] * t))
        phase += 2 * math.pi * f / RATE
        s = sum(a * math.sin(h * phase) for h, a in harmonics)
        if noise: s += noise * random.uniform(-1, 1)
        out.append(s * envelope(t))
    return out

def seg(parts):
    out = []
    for p in parts: out += p
    return out

def silence(d): return [0.0] * int(d * RATE)

def cow():     # a slow rising moo with a soft vibrato
    n = int(1.1 * RATE)
    return tone(n, lambda t: 120 + 50 * min(1, t / 0.6), lambda t: min(1, t / 0.12) * math.exp(-max(0, t - 0.7) / 0.25),
                harmonics=((1, 1), (2, 0.6), (3, 0.35), (4, 0.2), (5, 0.1)), vib=(5, 0.015))

def cat():     # meow: a formant sweep up then down
    n = int(0.55 * RATE)
    return tone(n, lambda t: 500 + 500 * math.sin(math.pi * min(1, t / 0.5)), lambda t: min(1, t / 0.05) * math.exp(-max(0, t - 0.35) / 0.08),
                harmonics=((1, 1), (2, 0.5), (3, 0.3), (4, 0.15)), vib=(7, 0.02))

def dog():     # two short barks: pitch drop with a noisy attack
    bark = lambda: tone(int(0.16 * RATE), lambda t: 320 - 180 * min(1, t / 0.12), lambda t: min(1, t / 0.01) * math.exp(-t / 0.05),
                        harmonics=((1, 1), (2, 0.5), (3, 0.3)), noise=0.25)
    return seg([bark(), silence(0.12), bark()])

def duck():    # quack: a pulsed square-ish tone, twice
    def quack():
        n = int(0.22 * RATE)
        return tone(n, lambda t: 380 - 60 * t, lambda t: min(1, t / 0.01) * math.exp(-t / 0.12) * (0.6 + 0.4 * math.sin(2 * math.pi * 24 * t)),
                    harmonics=((1, 1), (3, 0.6), (5, 0.3), (7, 0.2)))
    return seg([quack(), silence(0.08), quack()])

def sheep():   # baa: a deep fast vibrato bleat
    n = int(0.8 * RATE)
    return tone(n, lambda t: 420, lambda t: min(1, t / 0.05) * math.exp(-max(0, t - 0.5) / 0.12),
                harmonics=((1, 1), (2, 0.7), (3, 0.4), (4, 0.2)), vib=(9, 0.06))

def rooster(): # cock-a-doodle-doo: four glides
    notes = [(520, 640, 0.18), (700, 760, 0.16), (900, 980, 0.22), (640, 560, 0.4)]
    parts = []
    for a, b, d in notes:
        n = int(d * RATE)
        parts.append(tone(n, lambda t, a=a, b=b, d=d: a + (b - a) * t / d, lambda t, d=d: min(1, t / 0.02) * math.exp(-max(0, t - d * 0.7) / 0.08),
                          harmonics=((1, 1), (2, 0.5), (3, 0.3)), vib=(6, 0.01)))
        parts.append(silence(0.03))
    return seg(parts)

def lion():    # roar: low growl with a rough amplitude flutter
    n = int(1.0 * RATE)
    return tone(n, lambda t: 70 + 25 * math.sin(math.pi * t), lambda t: min(1, t / 0.15) * math.exp(-max(0, t - 0.6) / 0.2) * (0.7 + 0.3 * math.sin(2 * math.pi * 28 * t)),
                harmonics=((1, 1), (2, 0.8), (3, 0.6), (4, 0.4), (5, 0.3)), noise=0.35)

def donkey():  # hee-haw, twice
    hee = lambda: tone(int(0.28 * RATE), lambda t: 900 + 100 * math.sin(2 * math.pi * 4 * t), lambda t: min(1, t / 0.03) * math.exp(-max(0, t - 0.2) / 0.05),
                       harmonics=((1, 1), (2, 0.4)), noise=0.2)
    haw = lambda: tone(int(0.34 * RATE), lambda t: 260 - 60 * t, lambda t: min(1, t / 0.02) * math.exp(-max(0, t - 0.24) / 0.06),
                       harmonics=((1, 1), (2, 0.6), (3, 0.4)))
    return seg([hee(), haw(), silence(0.05), hee(), haw()])

def frog():    # croak: a pulse train, twice
    def croak():
        n = int(0.35 * RATE)
        return tone(n, lambda t: 150, lambda t: min(1, t / 0.02) * math.exp(-max(0, t - 0.25) / 0.05) * (0.5 + 0.5 * max(0, math.sin(2 * math.pi * 40 * t))),
                    harmonics=((1, 1), (2, 0.8), (3, 0.5), (4, 0.3)))
    return seg([croak(), silence(0.15), croak()])

def pig():     # oink: a nasal snort with noise, twice
    def oink():
        n = int(0.24 * RATE)
        return tone(n, lambda t: 420 - 170 * min(1, t / 0.2), lambda t: min(1, t / 0.02) * math.exp(-max(0, t - 0.15) / 0.05),
                    harmonics=((1, 1), (2, 0.7), (3, 0.5), (4, 0.3)), noise=0.3)
    return seg([oink(), silence(0.1), oink()])

ANIMALS = {"vache": cow, "chat": cat, "chien": dog, "canard": duck, "mouton": sheep, "coq": rooster, "lion": lion, "ane": donkey, "grenouille": frog, "cochon": pig}

if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[2] == "animals":
    for name, fn in ANIMALS.items():
        write("animal-" + name, fn(), out); print("wrote animal-" + name + ".wav")
