"""Build « The toys break out »: prepare the phone screens, render the shots whose inputs changed,
build the sound, assemble the video. Run it through ../render.sh.

  render.sh                      the final ad: build/sketches-ad-vertical.mp4
  render.sh --preview            a fast low-res animatic: build/preview/sketches-ad-preview.mp4
  render.sh --preview --every 3  render one frame in three (the others are held): faster still
  render.sh --shots 2,7          only these shots (the others are reused if already rendered)
  render.sh --force              re-render the listed shots even if nothing changed

A shot is re-rendered when anything it uses changes: the scripts, the art, the screen files it shows
(or their entry in screens.json), the render settings. Its frames and a .hash live in
build/<variant>/frames/<shot>/."""
import argparse, glob, hashlib, json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
AD = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(AD))
BUILD = os.path.join(AD, "build")
sys.path.insert(0, HERE)
import timeline as T

BLENDER = os.environ.get("BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
SCREEN_W, SCREEN_H = 1024, 2202          # the phone's screen in the set: 66.1 x 142.1 mm
VIDEO_EXT = (".mov", ".mp4", ".m4v")
STILL_EXT = (".png", ".jpg", ".jpeg", ".webp")
PREP_VERSION = "2"
FONT = os.path.join(REPO, "ios", "SketchesForKids", "Resources", "Fonts", "Baloo2-ExtraBold.ttf")
TAGLINE = ["Six toys.", "Nothing to read.", "No ads."]


def log(*a):
    print(*a, flush=True)


def run(cmd, logfile=None, env=None):
    if logfile:
        with open(logfile, "w") as fh:
            r = subprocess.run(cmd, stdout=fh, stderr=subprocess.STDOUT, env=env)
    else:
        r = subprocess.run(cmd, env=env)
    if r.returncode:
        tail = open(logfile).read()[-3000:] if logfile else ""
        sys.exit(f"failed ({r.returncode}): {' '.join(cmd[:4])} ...\n{tail}")


def sha_bytes(*parts):
    h = hashlib.sha1()
    for p in parts:
        h.update(p if isinstance(p, bytes) else str(p).encode())
        h.update(b"\0")
    return h.hexdigest()


def sha_file(path):
    h = hashlib.sha1()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha_tree(*dirs):
    parts = []
    for d in dirs:
        for p in sorted(glob.glob(os.path.join(d, "**", "*"), recursive=True)):
            if os.path.isfile(p) and "__pycache__" not in p:
                parts += [os.path.relpath(p, AD), sha_file(p)]
    return sha_bytes(*parts)


def read_hash(d):
    p = os.path.join(d, ".hash")
    return open(p).read().strip() if os.path.exists(p) else None


def write_hash(d, h):
    open(os.path.join(d, ".hash"), "w").write(h)


# ---------------------------------------------------------------- screens
def manifest():
    return json.load(open(os.path.join(AD, "screens.json")))


def resolve(name):
    """screens/<name>: an explicit file, or the stem with the first extension found (.mov wins over .mp4,
    a clip over a still), so a recording dropped next to a placeholder replaces it."""
    d = os.path.join(AD, "screens")
    p = os.path.join(d, name)
    if os.path.splitext(name)[1] and os.path.exists(p):
        return p
    stem = os.path.splitext(name)[0]
    for ext in VIDEO_EXT + STILL_EXT:
        for e in (ext, ext.upper()):
            q = os.path.join(d, stem + e)
            if os.path.exists(q):
                return q
    sys.exit(f"screens.json names {name!r} but there is no screens/{stem}.(mov|mp4|png...)")


def frames_needed(role):
    return max(T.frames(sid) for sid, _, rs, _ in T.SHOTS if role in rs) + 4


def prepare_screen(role, entry, out_root):
    """Turn the role's clip or still into build/screens/<role>/0001.jpg..., cropped, fitted to the phone's
    screen, at 30 fps, starting at entry["start"] seconds, played at entry["speed"]."""
    src = resolve(entry["file"])
    out = os.path.join(out_root, role)
    h = sha_bytes(PREP_VERSION, sha_file(src), json.dumps(entry, sort_keys=True), frames_needed(role))
    if read_hash(out) == h:
        return h, False
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    top, bottom, left, right = (entry.get("crop") or [0, 0, 0, 0])
    crop = f"crop=iw*{1 - left - right:.4f}:ih*{1 - top - bottom:.4f}:iw*{left:.4f}:ih*{top:.4f}"
    fit = f"scale={SCREEN_W}:{SCREEN_H}:force_original_aspect_ratio=increase:flags=lanczos,crop={SCREEN_W}:{SCREEN_H}"
    is_video = os.path.splitext(src)[1].lower() in VIDEO_EXT
    if is_video:
        speed = float(entry.get("speed", 1.0))
        n = frames_needed(role)
        vf = f"{crop},setpts=PTS/{speed},fps={T.FPS},{fit},tpad=stop_mode=clone:stop_duration=30,format=yuvj420p"
        cmd = ["ffmpeg", "-v", "error", "-y", "-ss", str(entry.get("start", 0)), "-i", src, "-an", "-vf", vf,
               "-frames:v", str(n), "-q:v", "2", os.path.join(out, "%04d.jpg")]
    else:
        cmd = ["ffmpeg", "-v", "error", "-y", "-i", src, "-vf", f"{crop},{fit},format=yuvj420p", "-frames:v", "1",
               "-q:v", "2", os.path.join(out, "0001.jpg")]
    run(cmd)
    write_hash(out, h)
    return h, True


def prepare_screens(out_root):
    m = manifest()
    roles = m["roles"]
    hashes = {}
    for role in T.roles():
        if role not in roles:
            sys.exit(f"screens.json has no entry for role {role!r}")
        hashes[role], fresh = prepare_screen(role, roles[role], out_root)
        log(f"screen {role:15} <- {os.path.basename(resolve(roles[role]['file']))}{'  (prepared)' if fresh else ''}")
    return hashes


# ---------------------------------------------------------------- text
def textpng():
    exe = os.path.join(BUILD, "bin", "textpng")
    src = os.path.join(HERE, "TextPNG.swift")
    if not os.path.exists(exe) or os.path.getmtime(exe) < os.path.getmtime(src):
        os.makedirs(os.path.dirname(exe), exist_ok=True)
        run(["swiftc", "-O", src, "-o", exe])
    return exe


def prepare_text(out_root):
    """The end card's lines as Baloo 2 cards (white, ink outline), one PNG per line."""
    os.makedirs(out_root, exist_ok=True)
    exe = textpng()
    h = sha_bytes(sha_file(os.path.join(HERE, "TextPNG.swift")), sha_file(FONT), *TAGLINE)
    if read_hash(out_root) != h:
        for i, line in enumerate(TAGLINE):
            run([exe, FONT, "150", "1400", "220", os.path.join(out_root, f"line{i + 1}.png"), line])
        write_hash(out_root, h)
    return h


# ---------------------------------------------------------------- shots
def shot_source(sid):
    """shots.py as it matters to one shot: its own function and every shared helper, not the other shots,
    so editing shot 7 does not re-render shot 1."""
    import ast
    src = open(os.path.join(HERE, "shots.py")).read()
    parts = []
    for node in ast.parse(src).body:
        if isinstance(node, ast.FunctionDef) and node.name.startswith("shot") and node.name != "shot" + sid:
            continue
        parts.append(ast.get_source_segment(src, node) or "")
    return sha_bytes(*parts)


def shot_hash(sid, screen_hashes, text_hash, settings):
    roles = next(rs for s, _, rs, _ in T.SHOTS if s == sid)
    scripts = [sha_file(os.path.join(HERE, f)) for f in ("adlib.py", "timeline.py")] + [shot_source(sid)]
    return sha_bytes(sid, *scripts, ART_HASH, *[screen_hashes[r] for r in roles],
                     text_hash if sid == "8" else "", json.dumps(settings, sort_keys=True))


def render_shot(sid, variant_dir, h, settings, force):
    out = os.path.join(variant_dir, "frames", sid)
    n = T.frames(sid)
    want = list(range(1, n + 1, settings["every"]))
    if not force and read_hash(out) == h and all(os.path.exists(os.path.join(out, f"{f:04d}.png")) for f in want):
        log(f"shot {sid:3} up to date")
        return False
    if read_hash(out) != h or force:
        shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out, exist_ok=True)
    os.makedirs(os.path.join(variant_dir, "logs"), exist_ok=True)
    logfile = os.path.join(variant_dir, "logs", f"shot{sid}.log")
    t = time.time()
    log(f"shot {sid:3} rendering {len(want)} frames ...")
    env = dict(os.environ, AD_BUILD=os.path.join(variant_dir))
    run([BLENDER, "-b", "--factory-startup", "-P", os.path.join(HERE, "shots.py"), "--",
         "--shot", sid, "--samples", str(settings["samples"]), "--percent", str(settings["percent"]),
         "--every", str(settings["every"]), "--out", out], logfile, env)
    write_hash(out, h)
    took = time.time() - t
    log(f"shot {sid:3} rendered in {took / 60:.1f} min ({took / max(1, len(want)):.1f} s/frame)")
    return True


# ---------------------------------------------------------------- audio
def blender_python():
    found = sorted(glob.glob(os.path.join(os.path.dirname(os.path.dirname(BLENDER)), "Resources", "*", "python", "bin", "python3.*")))
    if not found:
        sys.exit("Blender's Python (with numpy) not found")
    return found[0]


def build_audio(variant_dir):
    out = os.path.join(variant_dir, "audio")
    os.makedirs(out, exist_ok=True)
    music = sorted(p for p in glob.glob(os.path.join(AD, "music", "*")) if os.path.splitext(p)[1].lower() in (".wav", ".mp3", ".m4a", ".aif", ".aiff", ".flac"))
    srcs = [sha_file(os.path.join(HERE, f)) for f in ("audio.py", "timeline.py")]
    h = sha_bytes(*srcs, sha_tree(os.path.join(AD, "sfx")), *[sha_file(m) for m in music[:1]])
    mix = os.path.join(out, "mix.wav")
    if read_hash(out) == h and os.path.exists(mix):
        log("sound up to date")
        return mix
    run([blender_python(), "-I", os.path.join(HERE, "audio.py"), out] + music[:1], os.path.join(out, "audio.log"))
    write_hash(out, h)
    log("sound built" + (f" with music {os.path.basename(music[0])}" if music else " with the placeholder bed"))
    return mix


# ---------------------------------------------------------------- assembly
def assemble(variant_dir, every, out_path, mix):
    seq = os.path.join(variant_dir, "seq")
    shutil.rmtree(seq, ignore_errors=True)
    os.makedirs(seq)
    g = 0
    for sid, beats, _, _ in T.SHOTS:
        d = os.path.join(variant_dir, "frames", sid)
        last = None
        for f in range(1, T.frames(sid) + 1):
            p = os.path.join(d, f"{f:04d}.png")
            if os.path.exists(p):
                last = p
            if last is None:
                sys.exit(f"shot {sid} has no frame {f}")
            g += 1
            os.symlink(last, os.path.join(seq, f"{g:05d}.png"))
    end_card = T.start("8") + 1
    vf = [f"vignette=angle=PI/9:enable='lt(n,{end_card - 1})'", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
    inputs = ["-framerate", str(T.FPS), "-i", os.path.join(seq, "%05d.png"), "-i", mix]
    badge = os.path.join(AD, "badge.png")
    filt = ",".join(vf)
    if os.path.exists(badge):
        inputs += ["-i", badge]
        t0 = T.start("8") / T.FPS + 1.6
        # in the gap between the line and the toys
        filt = f"[0:v]{filt}[v];[2:v]scale=-1:150[b];[v][b]overlay=(W-w)/2:H*0.585-h/2:enable='gte(t,{t0:.2f})'"
        fargs = ["-filter_complex", filt, "-map", "1:a"]
    else:
        fargs = ["-vf", filt, "-map", "0:v", "-map", "1:a"]
    run(["ffmpeg", "-v", "error", "-y", *inputs, *fargs, "-c:v", "libx264", "-preset", "slow", "-crf", "17",
         "-pix_fmt", "yuv420p", "-profile:v", "high", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
         "-shortest", "-movflags", "+faststart", out_path])
    # a strip of frames for review: the middle of every shot
    tiles = []
    for sid, _, _, _ in T.SHOTS:
        mid = T.start(sid) + T.frames(sid) // 2 + 1
        tiles.append(os.path.join(seq, f"{mid:05d}.png"))
    strip = os.path.splitext(out_path)[0] + "-strip.png"
    args = []
    for p in tiles:
        args += ["-i", p]
    run(["ffmpeg", "-v", "error", "-y", *args, "-filter_complex",
         "".join(f"[{i}]scale=270:480[t{i}];" for i in range(len(tiles))) + "".join(f"[t{i}]" for i in range(len(tiles))) + f"hstack={len(tiles)}",
         strip])
    log(f"video  {out_path}\nstrip  {strip}")


ART_HASH = None


def main():
    global ART_HASH
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--every", type=int, default=1)
    ap.add_argument("--shots", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--samples", type=int, default=0)
    ap.add_argument("--no-video", action="store_true")
    a = ap.parse_args()
    variant = os.path.join(BUILD, "preview" if a.preview else "final")
    settings = {"samples": a.samples or (8 if a.preview else 32), "percent": 33 if a.preview else 100,
                "every": a.every if a.preview else 1}
    ART_HASH = sha_tree(os.path.join(AD, "art"))
    os.makedirs(variant, exist_ok=True)
    screen_hashes = prepare_screens(os.path.join(variant, "screens"))
    text_hash = prepare_text(os.path.join(variant, "text"))
    wanted = [s for s in a.shots.split(",") if s] or [s for s, _, _, _ in T.SHOTS]
    for sid in wanted:
        render_shot(sid, variant, shot_hash(sid, screen_hashes, text_hash, settings), settings, a.force)
    if a.no_video:
        return
    mix = build_audio(variant)
    name = "sketches-ad-preview.mp4" if a.preview else "sketches-ad-vertical.mp4"
    out = os.path.join(variant if a.preview else BUILD, name)
    assemble(variant, settings["every"], out, mix)


if __name__ == "__main__":
    main()
