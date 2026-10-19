"""App Store screenshots and preview footage of « Sketches for kids! », from the simulator.

Usage:
  python3 -I ios/Tools/StoreMedia.py capture OUT_DIR [Test ...]
  python3 -I ios/Tools/StoreMedia.py preview OUT_DIR
  python3 -I ios/Tools/StoreMedia.py screenshots OUT_DIR

capture: builds the Debug app and its UI tests for the "Store iPhone" simulator (iPhone 17 Pro
Max, iOS 26.2, 1320 x 2868: the 6.9-inch slot; created if missing), records the screen while
StoreMediaUITests plays each toy, and says a sentence through the Mac for the parrot (the
simulator hears the Mac's microphone). OUT_DIR gets screen-<toy>.mp4 (+ .json, the wall-clock
time of its first frame), timeline.txt (marks from the test), shots/*.png (1320 x 2868) and
audio-<toy>.raw (+ .json): what the toys played, captured inside the app, the speakers muted.
Name tests (testPaint, testSea, ...) to run only those.

preview: cuts preview.mp4 from that footage: 886 x 1920, 30 fps, H.264 + stereo AAC 48 kHz,
the toys' own sound. Edit CUTS to change the story.

screenshots: OUT_DIR/framed/{en,fr,es,it}/NN-<toy>.png, the screenshots on their toy's colour with a
line for parents (ios/Tools/FrameScreenshots.swift holds the captions and the order).
"""
import json, os, subprocess, sys, threading, time

IOS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_NAME = "Store iPhone"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
BUNDLE = "com.screenclub.sketchesforkids"
DERIVED = os.path.join(IOS, "build", "store")

# (toy, from mark, seconds after it, length): the preview, in order, under 30 s. A mark
# "<mark>.sound" is the first sound the toy started after <mark> (the paint's first stroke, the
# parrot's answer, a tap), "<mark>.motion" the first movement on its screen after a still one
# (a swipe, while the cow still moos): the test's marks come a little before what they trigger.
CUTS = [
    ("paint", "paint.ready.sound", 1.3, 4.5),
    ("sea", "sea.ready", 1.6, 4.0),
    ("tiles", "tiles.ready.sound", -0.15, 3.2),
    ("guitar", "guitar.ready.sound", -0.15, 3.4),
    ("animals", "animals.ready.sound", -0.2, 1.7),
    ("animals", "animals.swipe0.motion", -0.15, 2.3),
    ("parrot", "parrot.ready.sound", -0.5, 3.0),
    ("sea", "sea.ready", 12.4, 3.0),
    ("home", "home.ready", 0.6, 2.2),
]
SENTENCE = "Bonjour petit perroquet !"


def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw).stdout


def simulator():
    devices = json.loads(run("xcrun", "simctl", "list", "-j", "devices"))["devices"]
    for d in devices.get(RUNTIME, []):
        if d["name"] == SIM_NAME and d["isAvailable"]:
            return d["udid"]
    return run("xcrun", "simctl", "create", SIM_NAME, DEVICE_TYPE, RUNTIME).strip()


def marks(out):
    found = {}
    with open(os.path.join(out, "timeline.txt")) as f:
        for line in f:
            label, t = line.split()
            found.setdefault(label, float(t))
    return found


def capture(out, tests):
    os.makedirs(out, exist_ok=True)
    for name in os.listdir(out):
        if name.startswith(("audio-", "screen", "timeline")):
            os.remove(os.path.join(out, name))
    udid = simulator()
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True)
    run("xcrun", "simctl", "bootstatus", udid, "-b")
    subprocess.run(["xcrun", "simctl", "privacy", udid, "grant", "microphone", BUNDLE], capture_output=True)
    subprocess.run(["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged",
                    "--batteryLevel", "100", "--wifiBars", "3", "--cellularBars", "4"], capture_output=True)
    destination = f"platform=iOS Simulator,id={udid}"
    project = ["-project", os.path.join(IOS, "Kidzy.xcodeproj"), "-scheme", "SketchesForKids", "-configuration", "Debug",
               "-destination", destination, "-derivedDataPath", DERIVED]
    print("building...", flush=True)
    build = subprocess.run(["xcodebuild", *project, "build-for-testing"], capture_output=True, text=True)
    if build.returncode:
        sys.exit("\n".join(l for l in build.stdout.splitlines() if "error:" in l) or build.stdout[-2000:])

    # each toy's screen, recorded from the moment it is up, with the wall-clock time of its
    # first frame (simctl shortens the time the screen stands still: during a launch, so one
    # long recording drifts, and in a toy, which the app's FrameTicker prevents)
    timeline = os.path.join(out, "timeline.txt")
    done = threading.Event()

    def record(label):
        screen = os.path.join(out, f"screen-{label}.mp4")
        recorder = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", screen],
                                    stderr=subprocess.PIPE, text=True)
        for line in recorder.stderr:
            if "Recording started" in line:
                json.dump({"start": time.time()}, open(screen + ".json", "w"))
                break
        threading.Thread(target=recorder.stderr.read, daemon=True).start()
        return recorder

    def director():
        seen, recorders = 0, {}
        while not done.is_set() or recorders:
            lines = open(timeline).read().splitlines() if os.path.exists(timeline) else []
            for line in lines[seen:]:
                label = line.split()[0]
                if label.endswith(".ready"):
                    recorders[label[:-6]] = record(label[:-6])
                elif label.endswith(".end") and label[:-4] in recorders:
                    r = recorders.pop(label[:-4])
                    r.send_signal(2)
                    r.wait(30)
                elif label == "parrot.say":
                    threading.Thread(target=subprocess.run, args=(["say", "-v", "Flo", SENTENCE],), daemon=True).start()
            seen = len(lines)
            if done.is_set():
                for r in recorders.values():
                    r.send_signal(2)
                    r.wait(30)
                recorders = {}
            time.sleep(0.05)
    directing = threading.Thread(target=director)
    directing.start()

    only = [f"-only-testing:SketchesForKidsUITests/StoreMediaUITests/{t}" for t in tests] or \
           ["-only-testing:SketchesForKidsUITests/StoreMediaUITests"]
    env = dict(os.environ, TEST_RUNNER_STORE_MEDIA_OUT=out)
    print("playing the toys...", flush=True)
    test = subprocess.run(["xcodebuild", *project, "test-without-building", *only], capture_output=True, text=True, env=env)
    done.set()
    directing.join()
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
    print("\n".join(l for l in test.stdout.splitlines() if "Test Case" in l or "error" in l))
    print("out:", out)


# The preview frame: the 1320 x 2868 capture without the Dynamic Island's band (the simulator
# draws it into recordings; a phone's own recordings leave it out), at App Store size.
CROP = "crop=1250:2708:35:160,scale=886:1920:flags=lanczos,setsar=1"
# small grey frames for matching the recordings against the screenshots
SW, SH, FPS = 66, 143, 30


def grey(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-vf", f"scale={SW}:{SH},format=gray", "-f", "rawvideo", "-"],
                         capture_output=True, check=True).stdout
    n = SW * SH
    return [raw[i:i + n] for i in range(0, len(raw) - n + 1, n)]


def distance(a, b):
    return sum(abs(x - y) for x, y in zip(a, b))


def normalized(out, toy):
    """A toy's recording cropped to the preview frame at a constant 30 fps (simctl writes a
    variable rate with jittery timestamps that ffmpeg cannot seek in)."""
    path = os.path.join(out, f"screen30-{toy}.mp4")
    if not os.path.exists(path):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", os.path.join(out, f"screen-{toy}.mp4"), "-vf", f"fps={FPS},{CROP}",
                        "-c:v", "libx264", "-preset", "fast", "-crf", "10", "-g", "15", "-pix_fmt", "yuv420p", path], check=True)
    return path


def drift(out, found, toy, screen, start):
    """How far a toy's recording runs from the wall clock (`video = wall - start + drift`),
    from the screenshots found in it; a still screen matches many frames and is left out.
    (Near zero since the app's FrameTicker keeps the recorder's clock running; this checks it.)"""
    frames = grey(screen)
    os.makedirs(os.path.join(out, "parts"), exist_ok=True)
    values = []
    for name in sorted(os.listdir(os.path.join(out, "shots"))):
        label = name[:-4]
        if label.split("-")[0] != toy or "pre." + label not in found:
            continue
        small = os.path.join(out, "parts", f"shot-{label}.png")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", os.path.join(out, "shots", name), "-vf", CROP, small], check=True)
        shot = grey(small)[0]
        wall = found["pre." + label] - start + 0.03
        lo, hi = max(1, int((wall - 1) * FPS)), min(len(frames), int((wall + 1) * FPS))
        if lo >= hi:
            continue
        scored = sorted((distance(frames[i], shot), i) for i in range(lo, hi))
        best, index = scored[0]
        rival = next((d for d, i in scored if abs(i - index) > 6), best)
        if rival > best * 1.15:
            values.append(index / FPS - wall)
    values.sort()
    # each recording starts with its toy on screen, so it should not drift: a lone large value is a
    # false match (two strums look alike), two screenshots must agree
    if len(values) >= 2 and values[-1] - values[0] < 0.1 or len(values) == 1 and abs(values[0]) < 0.1:
        return values[len(values) // 2], values
    return 0.0, values


def first_sound(out, toy, after):
    """The wall-clock time a sound starts in the toy's capture after `after`: the first 5 ms
    above -40 dBFS that is 12 dB louder than the 50 ms before it."""
    import array, math
    path = os.path.join(out, f"audio-{toy}.raw")
    info = json.load(open(path + ".json"))
    rate = int(info["rate"])
    samples = array.array("f")
    samples.frombytes(open(path, "rb").read())
    hop = rate // 200
    first = max(0, int((after - info["start"]) * rate) // hop)
    levels = []
    # from 50 ms before, so a sound already playing at `after` is not taken for a new one
    for k in range(max(0, first - 10), len(samples) // 2 // hop - 1):
        chunk = samples[2 * k * hop:2 * (k + 1) * hop]
        levels.append(10 * math.log10(sum(x * x for x in chunk) / len(chunk) + 1e-12))
        if k >= first and levels[-1] > -40 and levels[-1] - min(levels[-11:-1] or [-120]) > 12:
            return info["start"] + k * hop / rate
    sys.exit(f"{toy}: no sound after {after}")


def first_motion(screen, start, lag, after):
    """The wall-clock time the toy's screen starts moving after `after`, having stood still."""
    frames = grey(screen)
    motion = [0.0] + [distance(a, b) / len(a) for a, b in zip(frames, frames[1:])]
    for k in range(max(4, int((after - start + lag) * FPS)), len(motion)):
        if motion[k] > 1.5 and max(motion[k - 4:k]) < 0.8:
            return start - lag + k / FPS
    sys.exit(f"no movement on {screen} after {after}")


def loudness_of(path):
    """Integrated loudness (LUFS) of a file's sound."""
    report = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True).stderr
    summary = report[report.rfind("Summary:"):]
    return float(summary.split("I:")[1].split()[0])


def preview(out):
    found = marks(out)
    parts = os.path.join(out, "parts")
    os.makedirs(parts, exist_ok=True)
    screens, clips = {}, []
    for toy in dict.fromkeys(c[0] for c in CUTS):
        start = json.load(open(os.path.join(out, f"screen-{toy}.mp4.json")))["start"]
        path = normalized(out, toy)
        lag, values = drift(out, found, toy, path, start)
        screens[toy] = (path, start, lag)
        print(f"{toy:8s} drift {lag:+.3f} s (screenshots: {', '.join(f'{v:+.3f}' for v in values) or 'none distinct'})")
    for toy, mark, _, _ in CUTS:
        if mark.endswith(".sound"):
            found[mark] = first_sound(out, toy, found[mark[:-6]])
        elif mark.endswith(".motion"):
            found[mark] = first_motion(*screens[toy], found[mark[:-7]])
    for i, (toy, mark, after, length) in enumerate(CUTS):
        path, start, lag = screens[toy]
        t0 = found[mark] + after
        clip = os.path.join(parts, f"{i:02d}-{toy}.mov")
        audio = os.path.join(out, f"audio-{toy}.raw")
        if os.path.exists(audio):
            info = json.load(open(audio + ".json"))
            sound_in = ["-ss", f"{max(0, t0 - info['start']):.4f}", "-f", "f32le", "-ar", str(int(info["rate"])), "-ac", "2", "-i", audio]
        else:
            sound_in = ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
        # hard cuts; a short fade on the sound only, so nothing clicks
        sound = f"[1:a]aresample=48000,atrim=duration={length},apad=whole_dur={length},afade=t=in:d=0.02,afade=t=out:st={length - 0.04}:d=0.04[a]"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{t0 - start + lag:.4f}", "-i", path, *sound_in,
                        "-filter_complex", f"[0:v]trim=duration={length},setpts=PTS-STARTPTS[v];{sound}", "-map", "[v]", "-map", "[a]",
                        "-t", f"{length}", "-c:v", "prores_ks", "-profile:v", "3", "-c:a", "pcm_s16le", clip], check=True)
        clips.append(clip)
    # each toy at about the same loudness (the brush is soft, the guitar loud), then a ceiling
    # 3 dB down, which leaves AAC room for its overshoot
    inputs, chain, gains = [], [], []
    for i, clip in enumerate(clips):
        inputs += ["-i", clip]
        level = loudness_of(clip)
        gain = min(8.0, max(-6.0, -16 - level)) if level > -60 else 0.0
        gains.append(f"{CUTS[i][0]} {gain:+.1f} dB")
        chain.append(f"[{i}:v]setpts=PTS-STARTPTS[v{i}];[{i}:a]volume={gain:.2f}dB,asetpts=PTS-STARTPTS[a{i}]")
    total = sum(c[3] for c in CUTS)
    joined = "".join(f"[v{i}][a{i}]" for i in range(len(clips)))
    mix = ";".join(chain) + f";{joined}concat=n={len(clips)}:v=1:a=1[v][m];" \
          f"[m]alimiter=limit=0.7:level=false,afade=t=out:st={total - 0.6}:d=0.6[a]"
    print("levels:", ", ".join(gains))
    final = os.path.join(out, "preview.mp4")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", *inputs, "-filter_complex", mix, "-map", "[v]", "-map", "[a]",
                    "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-profile:v", "high", "-level", "4.2", "-pix_fmt", "yuv420p",
                    "-r", "30", "-g", "30", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", final], check=True)
    print(final)


def screenshots(out):
    """The parrot's screenshot is the one taken while it talked (the loudest moment of its sound);
    then FrameScreenshots.swift lays every screenshot out with its caption, in English, French, Spanish and Italian."""
    import array, math
    found = marks(out)
    info = json.load(open(os.path.join(out, "audio-parrot.raw.json")))
    samples = array.array("f")
    samples.frombytes(open(os.path.join(out, "audio-parrot.raw"), "rb").read())
    rate = int(info["rate"])

    def level(t):
        i = int((t - info["start"]) * rate)
        chunk = samples[max(0, 2 * (i - rate // 10)):max(0, 2 * (i + rate // 10))]
        return sum(x * x for x in chunk) / max(1, len(chunk))
    talking = max((n[:-4] for n in os.listdir(os.path.join(out, "shots")) if n.startswith("parrot-")), key=lambda label: level(found["pre." + label]))
    subprocess.run(["cp", os.path.join(out, "shots", talking + ".png"), os.path.join(out, "shots", "parrot.png")], check=True)
    print("parrot:", talking)
    subprocess.run(["swift", os.path.join(IOS, "Tools", "FrameScreenshots.swift"), os.path.join(out, "shots"), os.path.join(out, "framed")],
                   check=True, cwd=IOS)


if __name__ == "__main__":
    command, out = sys.argv[1], os.path.abspath(sys.argv[2])
    if command == "capture":
        capture(out, sys.argv[3:])
    elif command == "preview":
        preview(out)
    elif command == "screenshots":
        screenshots(out)
    else:
        sys.exit(__doc__)
