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
