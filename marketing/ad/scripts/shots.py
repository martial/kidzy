"""The shots of « The toys break out », animated on the 120 bpm grid (scripts/timeline.py).

  Blender -b --factory-startup -P shots.py -- --shot 1 [--samples 32] [--percent 100] [--every 1]
          [--out DIR] [--still FRAME] [--save file.blend]

Each shot builds its set, keys its animation on local frames 1..N (beat b = frame 1 + 15 b), then
renders. The phone screens come from build/<variant>/screens/<role>/ (build.py prepares them from
screens.json), so a new recording changes the ad without touching this file."""
import argparse, bpy, math, os, random, sys
from mathutils import Vector, kdtree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adlib as A
import timeline as T

B = T.beat_frame          # B(2) = local frame of beat 2
FOCUS = lambda loc, tgt: (tgt - loc).length


# ---------------------------------------------------------------- shared set
def kitchen_card(y=1.4, z=0.45, h=1.6):
    m, img = A.image_mat("Kitchen", os.path.join(A.ART, "kitchen.jpg"), emission=1.1, lit=0.0, alpha=False)
    bpy.ops.mesh.primitive_plane_add(size=1)
    c = bpy.context.object
    c.name = "Backdrop"
    c.scale = (h * img.size[0] / img.size[1], h, 1)
    c.location = (0, y, z)
    c.rotation_euler = (math.radians(90), 0, 0)
    c.data.materials.append(m)
    c.visible_shadow = False
    return c


def base_set(role, phone_rot=0.0, sun=2.4, world=0.3, backdrop=(1.4, 0.45, 1.6)):
    A.world((1.0, 0.93, 0.84), world)
    A.table()
    kitchen_card(*backdrop)
    A.light_sun((0.55, -0.45, -0.7), sun)
    A.light_area((0.45, -0.35, 0.35), (0, 0, 0.03), 0.6, 5, (0.92, 0.95, 1.0), "Fill")
    A.light_area((-0.25, 0.45, 0.4), (0, 0, 0.05), 0.4, 12, (1.0, 0.9, 0.78), "Rim")
    ph, scr = A.phone(role, rot_z=phone_rot)
    return ph, scr


def away(cam_loc, p, d):
    """A point `d` metres further from the camera than p, on the same line of sight."""
    return p + (p - Vector(cam_loc)).normalized() * d


def screen_emission(scr):
    m = scr.data.materials[0]
    return next(n for n in m.node_tree.nodes if n.type == "EMISSION").inputs["Strength"]


def flash_screen(scr, frames_values):
    A.key_value(screen_emission(scr), frames_values)


def light_keys(light_ob, frames_values):
    for f, v in frames_values:
        light_ob.data.energy = v
        light_ob.data.keyframe_insert("energy", frame=f)


def bob(pivot, f0, f1, base, amp=0.006, period=T.BEAT, phase=0.0, step=2, drift=(0, 0, 0)):
    """Hover: a gentle up and down on the beat."""
    base = Vector(base)
    A.path_keys(pivot, f0, f1, lambda t: base + Vector(drift) * t + Vector((0, 0, amp * math.sin(phase + 2 * math.pi * t * (f1 - f0) / period))), step)


def flap(card, f0, f1, period=4, amount=0.12, base=(1, 1, 1)):
    """Wing beats faked in the card's plane: a quick vertical squash and stretch."""
    for f in range(f0, f1 + 1, max(1, period // 2)):
        k = amount if ((f - f0) // max(1, period // 2)) % 2 == 0 else -amount
        A.kf(card, f, scale=(base[0] * (1 - k * 0.4), base[1] * (1 + k), base[2]))


def roll_keys(card, keys):
    """In-plane roll (degrees) of a card: [(frame, degrees)]."""
    for f, d in keys:
        A.kf(card, f, rotation_euler=(0, 0, math.radians(d)))


def ripple(ph, f0, u=0.0, v=0.0, dur=12, radius=0.034, color=(1.0, 0.95, 0.8, 1), strength=6.0):
    """A ring of light running out over the screen from (u, v): where a toy breaks out of the glass."""
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.035, major_segments=64, minor_segments=8)
    ring = bpy.context.object
    ring.name = f"Ripple{f0}"
    m = A.emissive(ring.name + "Mat", color, strength)
    em = next(n for n in m.node_tree.nodes if n.type == "EMISSION")
    ring.data.materials.append(m)
    ring.visible_shadow = False
    ring.location = A.screen_point(ph, u, v, 0.0012)
    ring.rotation_euler = ph.rotation_euler
    A.visible(ring, f0, f0 + dur)
    A.kf(ring, f0, scale=(0.002, 0.002, 0.002))
    A.kf(ring, f0 + dur, scale=(radius, radius, radius * 0.5))
    A.set_interp(ring, "BEZIER", "EASE_OUT", paths=["scale"])
    A.key_value(em.inputs["Strength"], [(f0, strength), (f0 + dur, 0.0)])
    return ring


def white_card(cam, f_values, dist=0.05):
    """A white card just in front of the lens, for the flash between shots 7 and 8."""
    m, n, l, p = A._mat("FlashMat")
    em = n.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 3.0
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    tr = n.new("ShaderNodeBsdfTransparent")
    mx = n.new("ShaderNodeMixShader")
    l.new(tr.outputs[0], mx.inputs[1])
    l.new(em.outputs[0], mx.inputs[2])
    l.new(mx.outputs[0], n["Material Output"].inputs["Surface"])
    m.blend_method = "BLEND"
    bpy.ops.mesh.primitive_plane_add(size=0.2)
    c = bpy.context.object
    c.name = "Flash"
    c.data.materials.append(m)
    c.parent = cam
    c.location = (0, 0, -dist)
    c.visible_shadow = False
    A.key_value(mx.inputs[0], f_values)
    return c


# ---------------------------------------------------------------- 1 · the parrot bursts out
def shot1(N):
    ph, scr = base_set("home", math.radians(-8))
    cam = A.camera((0.03, -0.40, 0.25), (0.0, 0.01, 0.07), lens=40, fstop=2.8, focus=0.43)
    top = A.screen_point(ph, 0.0, 0.08, 0.0)
    pc = top + Vector((0, 0.0, 0.085))
    tap = B(1)
    A.camera_move(cam, [
        (1, (0.03, -0.30, 0.17), (0.0, 0.0, 0.015)),
        (tap - 1, (0.035, -0.335, 0.19), (0.0, 0.005, 0.025)),
        (tap + 6, (0.035, -0.39, 0.23), (0.0, 0.01, 0.06)),
        (B(3), (0.03, -0.40, 0.25), (0.0, 0.01, 0.075)),
        (N - 5, (0.02, -0.37, 0.26), (0.0, 0.01, 0.085)),
        (N, (0.03, -0.37, 0.26), (0.32, 0.05, 0.13)),          # whip right, into shot 2
    ], focus=FOCUS)

    # the finger taps the parrot's tile on beat 1
    tip = A.screen_point(ph, 0.42, -0.36, 0.006)
    A.light_area((0.25, 0.15, 0.15), (0.05, -0.05, 0.03), 0.15, 6, (1.0, 0.85, 0.75), "HandRim")
    hp, hc = A.toy("Hand", "hand", 0.085, tip, anchor=(0.03, 0.04), lit=0.45)
    roll_keys(hc, [(1, 8)])
    for f, off in ((1, (0.13, -0.07, 0.07)), (tap - 4, (0.006, -0.002, 0.016)), (tap, (0, 0, 0)),
                   (tap + 3, (0.002, 0, 0.006)), (tap + 16, (0.12, -0.09, 0.06))):
        A.kf(hp, f, location=tip + Vector(off))
    A.visible(hp, 1, tap + 18)

    # the tap: the screen flashes, a glow and rays open, confetti and sparks burst
    flash_screen(scr, [(1, 1.6), (tap - 1, 1.6), (tap, 5.0), (tap + 8, 2.2), (tap + 24, 1.6)])
    ripple(ph, tap, 0.25, -0.30, 12, 0.045)
    ripple(ph, tap + 3, 0.0, 0.08, 14, 0.06, strength=4.0)
    sl = A.screen_light(ph, 1.5)
    light_keys(sl, [(1, 1.0), (tap, 7.0), (tap + 14, 1.8)])
    gp = bpy.data.objects.new("GlowPivot", None)
    bpy.context.collection.objects.link(gp)
    gp.location = away(cam.location, pc, 0.05)
    gp["billboard"] = True
    g = A.glow("Glow", (0, 0, 0), (0, 0, 1), 0.11, strength=3.0)
    g.parent, g.location, g.rotation_euler = gp, (0, 0, 0), (0, 0, 0)
    A.pop(g, tap, 7, over=1.35)
    A.kf(g, B(4) + 4, scale=(1, 1, 1))
    A.kf(g, B(4) + 14, scale=(0.0001, 0.0001, 0.0001))
    rp = bpy.data.objects.new("RaysPivot", None)
    bpy.context.collection.objects.link(rp)
    rp.location = away(cam.location, pc, 0.06)
    rp["billboard"] = True
    r = A.rays("Burst", (0, 0, 0), (0, 0, 1), count=24, length=0.19, width=0.007, strength=1.3)
    r.parent, r.location, r.rotation_euler = rp, (0, 0, 0), (0, 0, 0)
    A.pop(r, tap, 9, over=1.2)
    A.kf(r, B(4), scale=(1, 1, 1))
    A.kf(r, B(4) + 12, scale=(0.0001, 0.0001, 0.0001))
    A.kf(r, tap, rotation_euler=(0, 0, 0))
    A.kf(r, N, rotation_euler=(0, 0, math.radians(35)))
    A.set_interp(r, "LINEAR", paths=["rotation_euler"])
    conf = A.confetti(top + Vector((0, 0, 0.015)), 90, (0.028, 0.028, 0.012), seed=2)
    A.scatter(conf, tap, N, top, speed=0.6, up=0.8, spin=9, seed=2, g=(0, 0, -0.9), drag=1.6, stagger=4)
    sparks = A.drops("Spark", pc - Vector((0, 0, 0.05)), 14, (0.01, 0.01, 0.01), 0.0015, 0.004, A.LEMON, seed=4)
    A.scatter(sparks, tap + 2, N, pc - Vector((0, 0, 0.05)), speed=0.9, up=0.5, seed=3, g=(0, 0, -0.6), drag=1.2)

    # the parrot: out of the screen on the tap, hovering and calling on the beats, then flies off
    pp, pcard = A.toy("Parrot", "parrot-burst", 0.105, top - Vector((0, 0, 0.12)))
    A.visible(pp, tap, B(4))
    A.kf(pp, tap, location=top - Vector((0, 0, 0.03)))
    A.kf(pp, tap + 5, location=pc + Vector((0, 0, 0.018)))
    A.kf(pp, tap + 9, location=pc)
    bob(pp, tap + 10, B(4), pc, amp=0.005, drift=(0.0, 0.0, 0.012))
    A.kf(pcard, tap, scale=(0.7, 1.4, 1))
    A.kf(pcard, tap + 6, scale=(1.12, 0.9, 1))
    A.kf(pcard, tap + 10, scale=(1, 1, 1))
    for b in (2, 3):                                  # a squawk on beats 2 and 3
        A.kf(pcard, B(b) - 1, scale=(1, 1, 1))
        A.kf(pcard, B(b) + 2, scale=(1.1, 1.08, 1))
        A.kf(pcard, B(b) + 7, scale=(1, 1, 1))
    roll_keys(pcard, [(tap, -14), (tap + 9, -6), (B(2), -10), (B(3), -3), (B(4), -8)])
    fp, fcard = A.toy("ParrotFly", "parrot-fly", 0.11, pc)
    A.visible(fp, B(4) + 1)
    end = Vector((-0.30, 0.12, 0.33))
    A.path_keys(fp, B(4) + 1, N, lambda t: pc + Vector((0, 0, 0.012)) + (end - pc) * A.ease(t, "in") + Vector((0, 0, 0.03 * math.sin(math.pi * t))), 1)
    flap(fcard, B(4) + 1, N, period=4, amount=0.14)
    roll_keys(fcard, [(B(4) + 1, 8)])
    A.compositor(glare=0.7)
    return cam


# ---------------------------------------------------------------- 2 · the sea floods out
def shot2(N):
    ph, scr = base_set("sea", math.radians(-30))
    ph.location = (-0.075, 0.0, 0)
    cam = A.camera((0.02, -0.43, 0.19), (0.035, -0.02, 0.08), lens=25, fstop=4.0, focus=0.44)
    A.camera_move(cam, [
        (1, (0.0, -0.47, 0.17), (-0.28, -0.04, 0.12)),          # the whip from shot 1 lands
        (5, (0.02, -0.46, 0.17), (0.04, -0.02, 0.125)),
        (B(1), (0.022, -0.45, 0.17), (0.045, -0.02, 0.122)),
        (N - 5, (0.03, -0.41, 0.165), (0.055, -0.02, 0.12)),
        (N, (0.04, -0.41, 0.175), (0.10, 0.05, 0.44)),          # whip up, into shot 3
    ], focus=FOCUS)
    o = A.screen_point(ph, 0.0, 0.05, 0.0)
    rnd = random.Random(5)

    def arc(t):
        a = t * math.pi * 0.92
        return Vector((0.10 * (1 - math.cos(a)), -0.07 * t ** 1.3, 0.12 * math.sin(a) + 0.008 * (1 - t)))

    crash = Vector((0.20, -0.07, 0.003))
    front = lambda f: A.ease((f - 1) / (B(1) - 1), "out") if f < B(1) else 1.0

    mb = bpy.data.metaballs.new("Wave")
    mb.resolution, mb.render_resolution, mb.threshold = 0.005, 0.0025, 0.6
    wave = bpy.data.objects.new("Wave", mb)
    bpy.context.collection.objects.link(wave)
    wave.location = o
    wave.data.materials.append(A.water_mat(foam=0.8))
    elems = []
    # the column, rising from the screen, arcing over toward the camera and crashing on the table
    for i in range(80):
        t = i / 79
        base = arc(t) + Vector((rnd.gauss(0, 0.004), rnd.gauss(0, 0.004), rnd.gauss(0, 0.004)))
        r = (0.011 + 0.022 * math.sin(math.pi * min(1, t * 1.15))) * (0.8 + 0.4 * rnd.random())
        elems.append(("arc", t, base, r))
    for i in range(40):                       # the crash: a spreading puddle
        a, d = rnd.uniform(0, 2 * math.pi), rnd.uniform(0.0, 0.08)
        elems.append(("pool", d / 0.08, crash + Vector((d * math.cos(a), d * math.sin(a) * 0.7, 0)), rnd.uniform(0.009, 0.018)))
    for i in range(16):                       # and its crown
        a = 2 * math.pi * i / 16
        elems.append(("crown", i / 16, crash + Vector((0.07 * math.cos(a), 0.05 * math.sin(a), 0.014 + rnd.uniform(0, 0.022))), rnd.uniform(0.005, 0.01)))
    for i in range(70):                       # lumps riding along the column: it flows and splashes
        n_ = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1))).normalized()
        elems.append(("flow", rnd.random(), n_ * rnd.uniform(0.7, 1.15), rnd.uniform(0.004, 0.010)))
    for i in range(12):                       # the swell on the screen
        elems.append(("src", 0, Vector((rnd.gauss(0, 0.012), rnd.gauss(0, 0.02), 0.004)), rnd.uniform(0.012, 0.02)))
    for kind, t, base, r in elems:
        e = mb.elements.new()
        e.co, e.radius, e.stiffness = base, r, 2.0
        ph_ = rnd.uniform(0, 6.28)
        for f in range(1, N + 1, 2):
            if kind == "flow":
                tt = (t + 0.022 * (f - 1)) % 1.0
                rr = 0.011 + 0.022 * math.sin(math.pi * min(1, tt * 1.15))
                e.co = arc(tt) + base * rr
                rad = r * math.sin(math.pi * tt) ** 0.5 if front(f) >= tt else 0.0
                e.radius = rad
                e.keyframe_insert("radius", frame=f)
                e.keyframe_insert("co", frame=f)
                continue
            if kind == "arc":
                grown = front(f) >= t
                rad = r * (1.0 + 0.12 * math.sin(ph_ + f * 0.7)) if grown else 0.0
            elif kind == "pool":
                k = (f - B(1) + 2) / 22 - t
                rad = r * max(0.0, min(1.0, k * 2.5))
            elif kind == "crown":
                k = (f - B(1)) / 18
                rad = r * (math.sin(math.pi * k) if 0 < k < 1 else 0.0)
            else:
                rad = r * min(1.0, f / 4)
            wob = Vector((math.sin(ph_ + f * 0.5), math.cos(ph_ * 1.3 + f * 0.43), math.sin(ph_ * 0.7 + f * 0.61))) * 0.0018
            e.co = base + wob
            e.radius = max(0.0, rad)
            e.keyframe_insert("radius", frame=f)
            e.keyframe_insert("co", frame=f)

    # the boat, bigger, rides the wave out of the screen and surfs its crest
    bp, bc = A.toy("Boat", "boat-surf", 0.088, o, anchor=(0.5, 0.2))
    A.visible(bp, 3)
    def boat_t(f):
        # thrown up with the water, over the top, then surfing down the face toward the camera
        if f < 12:
            return 0.03 + 0.45 * A.ease((f - 3) / 9, "out")
        return min(0.78, 0.48 + 0.22 * A.ease((f - 12) / 28, "inout") + 0.0012 * max(0, f - 40))
    for f in range(3, N + 1):
        t = boat_t(f)
        p = o + arc(t) + Vector((0, -0.012, 0.004 + 0.011 + 0.022 * math.sin(math.pi * min(1, t * 1.15))))
        hop = 0.018 * math.sin(math.pi * (f - B(3)) / 10) if B(3) <= f <= B(3) + 10 else 0.0
        p += Vector((0, 0, hop + 0.003 * math.sin(f * 0.8)))
        bp.location = p
        bp.keyframe_insert("location", frame=f)
        bc.rotation_euler = (0, 0, math.radians(22 - 60 * t + 5 * math.sin(f * 0.5)))
        bc.keyframe_insert("rotation_euler", frame=f)
    A.set_interp(bp, "LINEAR", paths=["location"])
    A.kf(bc, B(3), scale=(1, 1, 1))
    A.kf(bc, B(3) + 4, scale=(0.9, 1.12, 1))
    A.kf(bc, B(3) + 10, scale=(1.1, 0.92, 1))
    A.kf(bc, B(3) + 14, scale=(1, 1, 1))

    # spray: off the crest while it grows, at the crash on beat 1, from the crest on the next beats
    water = A.water_mat("DropMat")
    foam = A.glossy("Foam", (0.97, 0.99, 1.0, 1), rough=0.15, coat=0.3, sss=0.5)
    crest = o + arc(0.55) + Vector((0, 0, 0.03))
    for i, (f0, centre, n, sp, mat, seed) in enumerate([
            (6, crest, 18, 0.6, water, 9), (B(1), o + crash + Vector((0, 0, 0.01)), 34, 0.9, water, 10),
            (B(1), o + crash + Vector((0, 0, 0.01)), 24, 0.6, foam, 11), (B(2), crest, 16, 0.55, water, 12),
            (B(3), crest, 18, 0.6, foam, 13), (B(4), o + crash + Vector((0, 0, 0.01)), 18, 0.6, water, 14)]):
        ds = A.drops(f"Spray{i}_", centre, n, (0.012, 0.012, 0.008), 0.0015, 0.006, None, seed=seed, mat=mat, stretch=1.4)
        A.scatter(ds, f0, N, centre, speed=sp, up=0.9, spin=3, seed=seed, g=(0, 0, -1.6), drag=0.6, floor=0.002)
    # and a constant spray off the outside of the arc
    for k in range(0, N - 6, 3):
        t = min(0.97, front(k + 1)) * rnd.uniform(0.35, 1.0)
        c = o + arc(t) + Vector((0, 0, 0.02))
        ds = A.drops(f"Mist{k}_", c, 3, (0.006, 0.006, 0.006), 0.001, 0.0035, None, seed=100 + k, mat=water if k % 2 else foam, stretch=1.3)
        A.scatter(ds, k + 1, N, c - Vector((0.0, 0.0, 0.01)), speed=0.45, up=0.8, spin=2, seed=100 + k, g=(0, 0, -1.6), drag=0.5, floor=0.002)
    sl = A.screen_light(ph, 1.0, (0.7, 0.9, 1.0))
    light_keys(sl, [(1, 1.0), (4, 3.0), (B(1), 1.2)])
    flash_screen(scr, [(1, 1.6), (3, 3.0), (10, 1.6)])
    ripple(ph, 2, 0.0, 0.05, 12, 0.05, color=(0.7, 0.95, 1.0, 1))

    # the parrot crosses the sky behind
    fp, fc = A.toy("ParrotFly", "parrot-fly", 0.05, o + Vector((-0.16, 0.14, 0.24)))
    A.path_keys(fp, 1, N, lambda t: o + Vector((-0.16 + 0.34 * t, 0.14, 0.24 + 0.03 * math.sin(math.pi * t))), 2)
    flap(fc, 1, N, period=4, amount=0.14)
    A.compositor(glare=0.6)
    return cam


# ---------------------------------------------------------------- 3 · blue + yellow = green
def ribbon(name, pts, radius, taper, col, other=None):
    """A paint ribbon as a mesh with its colour (Col) and its position along the length (U, 0..1)."""
    tube = A.tube(name, pts, radius, taper=taper)
    line = A.tube(name + "Line", pts, 0.0, taper=taper)
    line.data.bevel_depth = 0
    centre = A.to_mesh(line)
    cv = [centre.matrix_world @ v.co for v in centre.data.vertices]
    lens = [0.0]
    for a, b in zip(cv, cv[1:]):
        lens.append(lens[-1] + (b - a).length)
    us = [l_ / lens[-1] for l_ in lens]
    kd = kdtree.KDTree(len(cv))
    for i, p in enumerate(cv):
        kd.insert(p, i)
    kd.balance()
    bpy.data.objects.remove(centre)
    mesh = A.to_mesh(tube)
    ua = mesh.data.attributes.new("U", "FLOAT", "POINT")
    for i, v in enumerate(mesh.data.vertices):
        _, j, _ = kd.find(mesh.matrix_world @ v.co)
        ua.data[i].value = us[j]
    return mesh, cv, us


def grow_material(ob, grow_keys):
    """The ribbon shows only where U <= grow (keyed): it extends along its length."""
    m = ob.data.materials[0]
    n, l = m.node_tree.nodes, m.node_tree.links
    out = n["Material Output"]
    surf = out.inputs["Surface"].links[0].from_socket
    at = n.new("ShaderNodeAttribute")
    at.attribute_name = "U"
    val = n.new("ShaderNodeValue")
    val.name = "Grow"
    gt = n.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    l.new(at.outputs["Fac"], gt.inputs[0])
    l.new(val.outputs[0], gt.inputs[1])
    tr = n.new("ShaderNodeBsdfTransparent")
    mx = n.new("ShaderNodeMixShader")
    l.new(gt.outputs[0], mx.inputs[0])
    l.new(surf, mx.inputs[1])
    l.new(tr.outputs[0], mx.inputs[2])
    l.new(mx.outputs[0], out.inputs["Surface"])
    m.blend_method = "HASHED"
    for f, v in grow_keys:
        val.outputs[0].default_value = v
        val.outputs[0].keyframe_insert("default_value", frame=f)


def point_at(cv, us, u):
    for i in range(1, len(us)):
        if us[i] >= u:
            k = (u - us[i - 1]) / max(1e-9, us[i] - us[i - 1])
            return cv[i - 1].lerp(cv[i], k)
    return cv[-1]


def shot3(N):
    ph, scr = base_set("paint", math.radians(-6))
    cam = A.camera((-0.04, -0.42, 0.26), (0.0, 0.0, 0.11), lens=27, fstop=3.5, focus=0.46)
    A.camera_move(cam, [
        (1, (-0.04, -0.42, 0.24), (0.0, -0.05, -0.20)),         # the whip from shot 2 lands from above
        (5, (-0.045, -0.43, 0.25), (0.0, 0.0, 0.10)),
        (B(2), (-0.02, -0.41, 0.26), (0.0, 0.0, 0.115)),
        (N - 5, (0.03, -0.39, 0.27), (0.0, 0.0, 0.12)),
        (N, (0.04, -0.39, 0.27), (0.36, 0.02, 0.14)),           # whip right, into shot 4
    ], focus=FOCUS)
    o = A.screen_point(ph, 0.0, 0.0, 0.0)

    def helix(phase, hand, turns=2.2, n=26, r0=0.012, r1=0.068, h=0.19):
        pts = []
        for i in range(n):
            t = i / (n - 1)
            a = phase + hand * t * turns * 2 * math.pi
            r = r0 + (r1 - r0) * t ** 0.8
            pts.append((o.x + r * math.cos(a), o.y + r * math.sin(a) * 0.8, o.z + 0.004 + h * t))
        return pts
    tb = [0.6 + 0.6 * (i / 25) for i in range(26)]
    ty = [0.6 + 0.5 * (i / 25) for i in range(26)]
    blue, bcv, bus = ribbon("Blue", helix(0.0, 1), 0.009, tb, None)
    yellow, ycv, yus = ribbon("Yellow", helix(math.pi * 0.5, -1, turns=1.8, h=0.175), 0.0085, ty, None)
    A.mix_paint(blue, yellow, A.hexcol("2F7BFF"), A.hexcol("FFD21F"), A.hexcol("3DC24E"), reach=0.017)
    for ob in (blue, yellow):                 # squeezed paint is lumpy, not a cable
        tex = bpy.data.textures.new(ob.name + "Lumps", "CLOUDS")
        tex.noise_scale = 0.006
        d = ob.modifiers.new("lumps", "DISPLACE")
        d.texture, d.strength, d.mid_level = tex, 0.0022, 0.5
        p_ = ob.data.materials[0].node_tree.nodes["Principled BSDF"]
        p_.inputs["Roughness"].default_value = 0.09
    rig = bpy.data.objects.new("PaintRig", None)
    bpy.context.collection.objects.link(rig)
    rig.location = o
    gkeys = {}
    for ob, cv, us, rad, tp, delay in ((blue, bcv, bus, 0.009, tb, 0), (yellow, ycv, yus, 0.0085, ty, 4)):
        keys = []
        for f in range(1, N + 1):
            g = A.ease((f - 1 - delay) / 34, "out") if f - 1 > delay else 0.0
            keys.append((f, g * 1.001))
        grow_material(ob, keys)
        gkeys[ob.name] = keys
        mw = ob.matrix_world.copy()
        ob.parent = rig
        ob.matrix_parent_inverse = rig.matrix_world.inverted()
        # the growing tip: a ball of paint at the end of the ribbon
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=24, ring_count=12)
        tip = bpy.context.object
        tip.name = ob.name + "Tip"
        bpy.ops.object.shade_smooth()
        tip.data.materials.append(A.glossy(ob.name + "TipMat", A.hexcol("2F7BFF") if ob is blue else A.hexcol("FFD21F"), rough=0.16, coat=0.8, sss=0.15))
        tip.parent = rig
        tip.matrix_parent_inverse = rig.matrix_world.inverted()
        for f, g in keys:
            u = min(1.0, g)
            p = point_at(cv, us, u)
            taper = tp[min(len(tp) - 1, int(u * (len(tp) - 1)))]
            s = rad * taper * (1.0 if g < 1.0 else 0.0001) * 1.02
            tip.location = p
            tip.scale = (max(s, 0.0001),) * 3
            tip.keyframe_insert("location", frame=f)
            tip.keyframe_insert("scale", frame=f)
        A.set_interp(tip, "LINEAR")
    # once grown, the twist keeps turning
    A.kf(rig, 1, rotation_euler=(0, 0, 0))
    A.kf(rig, N, rotation_euler=(0, 0, math.radians(-50)))
    A.set_interp(rig, "LINEAR", paths=["rotation_euler"])
    for i, (f0, seed, col) in enumerate(((B(1), 11, "2F7BFF"), (B(1) + 3, 12, "FFD21F"), (B(3), 13, "3DC24E"), (B(3) + 2, 14, "2F7BFF"))):
        c = o + Vector((0, 0, 0.13))
        ds = A.drops(f"Paint{i}_", c, 7, (0.02, 0.02, 0.02), 0.004, 0.011, A.hexcol(col), seed=seed, stretch=1.4)
        A.scatter(ds, f0, N, c, speed=0.55, up=0.4, spin=3, seed=seed, g=(0, 0, -1.2), drag=0.5)
    ripple(ph, 1, 0.0, 0.0, 12, 0.045, color=(0.75, 0.9, 1.0, 1), strength=4.0)
    rnd = random.Random(3)
    for col, cx in ((A.hexcol("2F7BFF"), -0.008), (A.hexcol("FFD21F"), 0.008)):
        pts = [(cx + rnd.gauss(0, 0.009), rnd.gauss(0, 0.014), 0.0015, rnd.uniform(0.006, 0.011)) for _ in range(14)]
        pud = A.gush("Puddle" + ("B" if cx < 0 else "Y"), pts, o, mat=A.glossy("PuddleMat", col, rough=0.14, coat=0.8, sss=0.15), res=0.0015)
        for e in pud.data.elements:
            r = e.radius
            for f, k in ((1, 0.3), (8, 1.0)):
                e.radius = r * k
                e.keyframe_insert("radius", frame=f)
    pp, pc = A.toy("Palette", "palette-fly", 0.07, o + Vector((-0.075, 0.06, 0.20)))
    A.path_keys(pp, 1, N, lambda t: o + Vector((-0.21 + 0.135 * A.ease(t * 1.6, "out") + 0.01 * t, 0.06, 0.34 - 0.14 * A.ease(t * 1.6, "out") + 0.004 * math.sin(6 * t))), 2)
    roll_keys(pc, [(1, 70), (30, 15), (N, -10)])
    A.compositor(glare=0.5)
    return cam


# ---------------------------------------------------------------- 4 · the guitar plays, the shapes rain
def shot4(N):
    ph, scr = base_set("guitar", math.radians(24))
    ph.location = (-0.075, -0.20, 0)
    cam = A.camera((0.0, -0.56, 0.08), (0.0, 0.0, 0.12), lens=32, fstop=2.8, focus=0.56)
    A.camera_move(cam, [
        (1, (-0.01, -0.56, 0.08), (-0.34, 0.0, 0.13)),          # the whip from shot 3 lands from the left
        (5, (0.0, -0.56, 0.08), (0.0, 0.0, 0.12)),
        (N - 5, (0.0, -0.50, 0.095), (0.0, 0.0, 0.125)),
        (N, (0.0, -0.50, 0.095), (-0.36, 0.0, 0.13)),           # whip left, into shot 5
    ], focus=FOCUS)
    gp, gc = A.toy("Guitar", "guitar-strum", 0.24, (0.0, 0.0, 0.118))
    A.light_area((-0.25, 0.25, 0.25), (0, 0, 0.12), 0.3, 4, (1.0, 0.55, 0.7), "PinkRim")
    A.light_area((0.25, 0.25, 0.2), (0, 0, 0.12), 0.3, 3, (0.5, 0.85, 1.0), "CyanRim")
    base = Vector((0.0, 0.0, 0.118))
    for b in range(5):                                # a strum on every beat: it hops and lands
        f = B(b)
        A.kf(gp, f, location=base)
        A.kf(gp, f + 4, location=base + Vector((0, 0, 0.014)))
        A.kf(gp, f + 9, location=base)
        A.kf(gc, f, scale=(1.1, 0.9, 1), rotation_euler=(0, 0, math.radians(-6 + (6 if b % 2 else -6))))
        A.kf(gc, f + 3, scale=(0.94, 1.08, 1))
        A.kf(gc, f + 9, scale=(1.06, 0.95, 1), rotation_euler=(0, 0, math.radians(-6)))
        A.kf(gc, min(N, f + 12), scale=(1, 1, 1))
    glp = bpy.data.objects.new("GlowPivot", None)
    bpy.context.collection.objects.link(glp)
    glp.location = (0.0, 0.05, 0.13)
    glp["billboard"] = True
    gl = A.glow("GuitarGlow", (0, 0, 0), (0, 0, 1), 0.16, color=(1.0, 0.8, 0.5, 1), strength=1.6)
    gl.parent, gl.location, gl.rotation_euler = glp, (0, 0, 0), (0, 0, 0)
    for b in range(5):
        A.kf(gl, B(b), scale=(1.15, 1.15, 1.15))
        A.kf(gl, B(b) + 8, scale=(1, 1, 1))
    # the shapes rain down, each one landing on an eighth note
    rnd = random.Random(21)
    kinds = ["quarter", "triangle", "half", "square", "arch"]
    cols = [A.CORAL, A.LEMON, A.OCEAN, A.GRASS, A.BERRY]
    for i in range(24):
        k = i % 5
        size = rnd.uniform(0.018, 0.034)
        ob = A.shape(kinds[k], size, cols[(k + i // 5) % 5], name=f"S{i}")
        side = -1 if i % 2 else 1
        y = rnd.uniform(-0.28, 0.08)
        x = side * rnd.uniform(0.03, 0.11) * (0.56 + y) / 0.56
        land = 3 + round(7.5 * i * 0.42)
        z_land = size * 0.25
        g = -1.7
        Tf = 26 / 30
        z0 = 0.42 + rnd.uniform(0, 0.08)
        v0z = (z_land - z0 - 0.5 * g * Tf * Tf) / Tf
        ob.rotation_euler = (rnd.uniform(0, 6.3), rnd.uniform(0, 6.3), rnd.uniform(0, 6.3))
        start = land - 26
        if start < 1:   # already falling when the shot opens
            frac = (1 - start) / 30
            z0 = z0 + v0z * frac + 0.5 * g * frac * frac
            v0z = v0z + g * frac
            start = 1
        A.ballistic(ob, start, N, (x, y, z0), (rnd.uniform(-0.02, 0.02), rnd.uniform(-0.02, 0.02), v0z), (0, 0, g),
                    (rnd.uniform(-5, 5), rnd.uniform(-5, 5), rnd.uniform(-5, 5)), 0.0, floor=z_land, bounce=0.3, step=1)
    # notes pop out of the sound hole on the beats
    for i, b in enumerate((1, 2, 3, 4)):
        npv, nc = A.toy(f"Note{i}", "note", 0.04, (0.0, -0.01, 0.10))
        start = Vector((0.0, -0.01, 0.10))
        endp = Vector(((-0.12, 0.11, -0.08, 0.13)[i], 0.0, 0.26 + 0.03 * (i % 2)))
        A.visible(npv, B(b), min(N, B(b) + 26))
        A.path_keys(npv, B(b), min(N, B(b) + 26), lambda t, s=start, e=endp: s.lerp(e, A.ease(t, "out")) + Vector((0.008 * math.sin(t * 9), 0, 0)), 1)
        A.pop(nc, B(b), 6, size=1.0, over=1.3)
        A.kf(nc, min(N, B(b) + 20), scale=(1, 1, 1))
        A.kf(nc, min(N, B(b) + 26), scale=(0.0001, 0.0001, 1))
        roll_keys(nc, [(B(b), (-20, 15, -10, 25)[i]), (min(N, B(b) + 26), (10, -15, 20, -5)[i])])
    A.compositor(glare=0.6)
    return cam


# ---------------------------------------------------------------- 5 · the cow jumps out
def shot5(N):
    ph, scr = base_set("animals", math.radians(-4))
    cam = A.camera((-0.02, -0.40, 0.16), (0.0, 0.0, 0.11), lens=34, fstop=3.2, focus=0.42)
    A.camera_move(cam, [
        (1, (-0.02, -0.40, 0.16), (0.34, 0.0, 0.11)),           # the whip from shot 4 lands from the right
        (5, (-0.02, -0.40, 0.16), (0.0, 0.0, 0.10)),
        (B(1), (-0.02, -0.40, 0.165), (0.0, -0.01, 0.11)),
        (B(2), (-0.02, -0.41, 0.15), (0.0, -0.045, 0.065)),
        (N, (-0.015, -0.39, 0.145), (0.0, -0.06, 0.055)),
    ], focus=FOCUS)
    o = A.screen_point(ph, 0.0, 0.0, 0.0)
    jp, jc = A.toy("Cow", "cow-jump", 0.125, o, anchor=(0.5, 0.0))
    sp, sc_ = A.toy("CowSit", "toy-animals", 0.10, o, anchor=(0.5, 0.0))
    land1 = Vector((0.0, -0.085, 0.0))
    land2 = Vector((0.01, -0.10, 0.0))
    apex1 = o + Vector((0.0, -0.04, 0.10))
    apex2 = Vector((0.012, -0.145, 0.05))
    # out of the screen (stretched), up to the apex on beat 1, down on the table on beat 2
    def arc(t, a, b, h):
        return a.lerp(b, t) + Vector((0, 0, h * 4 * t * (1 - t)))
    top = 22                                  # out fast, hang at the top, then drop like a toy
    start = o - Vector((0, 0, 0.11))
    for f in range(1, B(2) + 1):
        if f <= 7:
            p = start.lerp(o + Vector((0, -0.02, 0.07)), A.ease((f - 1) / 6, "out"))
        elif f <= top:
            p = (o + Vector((0, -0.02, 0.07))).lerp(apex1, A.ease((f - 7) / (top - 7), "out"))
        else:
            t = (f - top) / (B(2) - top)
            p = apex1.lerp(land1, t) * 1.0
            p.z = apex1.z + (land1.z - apex1.z) * t * t
        jp.location = p
        jp.keyframe_insert("location", frame=f)
    for f in range(B(2) + 3, B(3) + 1):   # the bounce: a parabola
        t = (f - B(2) - 3) / (B(3) - B(2) - 3)
        jp.location = arc(t, land1, land2, 0.05)
        jp.keyframe_insert("location", frame=f)
    A.set_interp(jp, "LINEAR", paths=["location"])
    A.kf(jc, 1, scale=(0.75, 1.35, 1))
    A.kf(jc, 8, scale=(0.9, 1.15, 1))
    A.kf(jc, top, scale=(1.05, 0.98, 1))
    A.kf(jc, B(2) - 3, scale=(0.9, 1.12, 1))
    A.kf(jc, B(2) + 3, scale=(0.85, 1.2, 1))
    A.kf(jc, B(2) + 9, scale=(1.05, 0.96, 1))
    A.kf(jc, B(3) - 2, scale=(0.92, 1.1, 1))
    roll_keys(jc, [(1, 0), (B(1), 10), (B(2), -6), (B(2) + 3, 8), (B(3), -4)])
    # the cow (sitting pose) squashes on each landing and stays
    A.visible_ranges(jp, [(1, B(2) - 1), (B(2) + 3, B(3) - 1)])
    A.visible(sp, B(2), B(2) + 2)
    sp2, sc2 = A.toy("CowSit2", "toy-animals", 0.10, land2, anchor=(0.5, 0.0))
    A.visible(sp2, B(3))
    A.kf(sp, B(2), location=land1)
    A.kf(sc_, B(2), scale=(1.3, 0.7, 1))
    A.kf(sc_, B(2) + 2, scale=(1.15, 0.85, 1))
    A.kf(sp2, B(3), location=land2)
    A.kf(sc2, B(3), scale=(1.3, 0.72, 1))
    A.kf(sc2, B(3) + 3, scale=(0.92, 1.08, 1))
    A.kf(sc2, B(3) + 7, scale=(1.04, 0.97, 1))
    A.kf(sc2, B(3) + 11, scale=(1, 1, 1))
    roll_keys(sc2, [(B(3), 0), (B(3) + 6, 4), (N, -2)])
    # the burst as it leaves the screen
    stars = A.drops("Star", o + Vector((0, -0.01, 0.02)), 14, (0.01, 0.01, 0.01), 0.002, 0.005, A.LEMON, seed=31)
    A.scatter(stars, 3, N, o, speed=0.8, up=1.0, seed=9, g=(0, 0, -0.8), drag=1.0)
    conf = A.confetti(o + Vector((0, 0, 0.012)), 50, (0.015, 0.015, 0.01), seed=32)
    A.scatter(conf, 3, N, o, speed=0.6, up=1.0, spin=7, seed=10, g=(0, 0, -0.8), drag=1.5, stagger=3)
    sl = A.screen_light(ph, 1.2)
    light_keys(sl, [(1, 6.0), (10, 1.2)])
    flash_screen(scr, [(1, 4.0), (8, 1.6)])
    ripple(ph, 1, 0.0, 0.0, 12, 0.05)
    glp = bpy.data.objects.new("GlowPivot", None)
    bpy.context.collection.objects.link(glp)
    glp.location = away(cam.location, o + Vector((0, -0.02, 0.12)), 0.08)
    glp["billboard"] = True
    gl = A.glow("CowGlow", (0, 0, 0), (0, 0, 1), 0.16, color=(1.0, 0.88, 0.6, 1), strength=1.5)
    gl.parent, gl.location, gl.rotation_euler = glp, (0, 0, 0), (0, 0, 0)
    A.pop(gl, 2, 8, over=1.3)
    A.kf(gl, B(2), scale=(1, 1, 1))
    A.kf(gl, B(3), scale=(0.0001, 0.0001, 0.0001))
    A.compositor(glare=0.6)
    return cam


# ---------------------------------------------------------------- 6 · the real app, close up
def shot6a(N):
    ph, scr = base_set("closeup-paint", math.radians(4))
    cam = A.camera((0.0, -0.19, 0.25), (0.0, 0.004, 0.008), lens=50, fstop=7.0, focus=0.31)
    A.camera_move(cam, [(1, (0.003, -0.198, 0.256), (0.0, 0.005, 0.008)), (N, (-0.002, -0.184, 0.242), (0.0, 0.003, 0.008))], focus=FOCUS)
    tip = A.screen_point(ph, 0.30, -0.30, 0.002)
    A.light_area((0.2, 0.1, 0.12), (0.03, -0.04, 0.03), 0.12, 4, (1.0, 0.85, 0.75), "HandRim")
    hp, hc = A.toy("Hand", "hand", 0.075, tip, anchor=(0.03, 0.04), lit=0.45)
    roll_keys(hc, [(1, 18), (N, 12)])
    A.path_keys(hp, 1, N, lambda t: tip + Vector((0.012 * math.sin(2.2 * t), -0.006 * t, 0.002 + 0.002 * math.sin(6 * t))), 1)
    A.compositor(glare=0.4)
    return cam


def shot6b(N):
    ph, scr = base_set("closeup-sea", math.radians(-14))
    cam = A.camera((0.04, -0.14, 0.21), (0.0, 0.0, 0.006), lens=42, fstop=7.0, focus=0.26)
    A.camera_move(cam, [(1, (0.045, -0.142, 0.212), (0.002, 0.001, 0.006), math.radians(3)),
                        (N, (0.03, -0.135, 0.202), (-0.001, 0.0, 0.006), math.radians(0))], focus=FOCUS)
    A.compositor(glare=0.4)
    return cam


def shot6c(N):
    ph, scr = base_set("closeup-guitar", math.radians(8))
    cam = A.camera((0.02, -0.11, 0.25), (0.0, 0.008, 0.006), lens=42, fstop=7.0, focus=0.27)
    A.camera_move(cam, [(1, (0.022, -0.115, 0.252), (0.0, 0.008, 0.006), math.radians(-3)),
                        (N, (0.01, -0.105, 0.24), (0.0, 0.007, 0.006), math.radians(2))], focus=FOCUS)
    A.compositor(glare=0.4)
    return cam


# ---------------------------------------------------------------- 7 · sucked back in
def funnel_radius(z):
    return 0.010 + 0.17 * (max(0.0, z) / 0.30) ** 1.25


def swirl_mat(name, tint=(1.0, 0.95, 0.88, 1), amount=0.7):
    """The funnel's dust: a stretched noise, emissive and mostly transparent."""
    m, n, l, p = A._mat(name)
    tc = n.new("ShaderNodeTexCoord")
    mp = n.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (6.0, 1.0, 1.0)
    l.new(tc.outputs["UV"], mp.inputs["Vector"])
    nz = n.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 5.0
    nz.inputs["Detail"].default_value = 3.0
    nz.inputs["Distortion"].default_value = 1.2
    l.new(mp.outputs["Vector"], nz.inputs["Vector"])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.44
    ramp.color_ramp.elements[1].position = 0.6
    l.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = tint
    em.inputs["Strength"].default_value = 1.8
    tr = n.new("ShaderNodeBsdfTransparent")
    mul = n.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = amount
    l.new(ramp.outputs["Color"], mul.inputs[0])
    mx = n.new("ShaderNodeMixShader")
    l.new(mul.outputs[0], mx.inputs[0])
    l.new(tr.outputs[0], mx.inputs[1])
    l.new(em.outputs[0], mx.inputs[2])
    l.new(mx.outputs[0], n["Material Output"].inputs["Surface"])
    m.blend_method = "BLEND"
    return m


def funnel_mesh(name, rings=24, segs=48, top=0.32, scale=1.0):
    import bmesh
    bm = bmesh.new()
    grid = []
    for i in range(rings + 1):
        z = top * i / rings
        r = funnel_radius(z) * scale
        grid.append([bm.verts.new((r * math.cos(2 * math.pi * j / segs), r * math.sin(2 * math.pi * j / segs) * 0.9, z)) for j in range(segs)])
    for i in range(rings):
        for j in range(segs):
            bm.faces.new((grid[i][j], grid[i][(j + 1) % segs], grid[i + 1][(j + 1) % segs], grid[i + 1][j]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    uv = me.uv_layers.new(name="UV")
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = ((math.atan2(v.y, v.x) / (2 * math.pi)) % 1.0, v.z / top)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for p_ in me.polygons:
        p_.use_smooth = True
    ob.visible_shadow = False
    return ob


def shot7(N):
    ph, scr = base_set("home-end", math.radians(-10))
    cam = A.camera((0.03, -0.40, 0.13), (0.0, 0.0, 0.12), lens=28, fstop=3.5, focus=0.40)
    rnd = random.Random(70)
    keys = [(1, (0.03, -0.40, 0.13), (-0.32, 0.0, 0.12)), (5, (0.03, -0.40, 0.13), (0.0, 0.0, 0.12))]
    for f in range(8, B(3), 3):                                # the wind shakes the camera
        keys.append((f, (0.03 + rnd.gauss(0, 0.0018), -0.40 + 0.04 * (f / N), 0.13 + rnd.gauss(0, 0.0018)), (rnd.gauss(0, 0.002), 0.0, 0.12 - 0.04 * f / N)))
    keys += [(B(3), (0.02, -0.31, 0.16), (0.0, 0.0, 0.06)), (N, (0.004, -0.13, 0.16), (0.0, 0.0, 0.006))]
    A.camera_move(cam, keys, focus=FOCUS)
    o = A.screen_point(ph, 0.0, 0.0, 0.0)
    rig = bpy.data.objects.new("Vortex", None)
    bpy.context.collection.objects.link(rig)
    rig.location = o
    A.kf(rig, 1, scale=(0.35, 0.35, 0.6), rotation_euler=(0, 0, 0))
    A.kf(rig, 9, scale=(1, 1, 1))
    A.kf(rig, B(3), scale=(1.05, 1.05, 1.0))
    A.kf(rig, N - 4, scale=(0.15, 0.15, 0.25))
    rig.rotation_euler = (0, 0, -4.0 * (N - 1) / 30)
    rig.keyframe_insert("rotation_euler", frame=N)
    A.set_interp(rig, "LINEAR", paths=["rotation_euler"])
    # the dust: two counter-turning funnels of stretched noise
    for k, (sc, spin, tint) in enumerate(((1.0, 0.0, (1.0, 0.94, 0.86, 1)), (0.8, 4.0, (0.9, 0.85, 1.0, 1)))):
        fm = funnel_mesh(f"Funnel{k}", scale=sc)
        fm.data.materials.append(swirl_mat(f"Dust{k}", tint, 0.24 if k == 0 else 0.16))
        fm.parent = rig
        A.kf(fm, 1, rotation_euler=(0, 0, 0))
        A.kf(fm, N, rotation_euler=(0, 0, spin))
        A.set_interp(fm, "LINEAR", paths=["rotation_euler"])
    # the swooshes: short streaks around the funnel at every height, candy and white
    cols = [A.LEMON, A.PINK, A.OCEAN, (1, 1, 1, 1), (1, 1, 1, 1)]
    for k in range(30):
        z = rnd.uniform(0.03, 0.31)
        a0, span = rnd.uniform(0, 2 * math.pi), rnd.uniform(1.6, 3.6)
        drop = rnd.uniform(0.03, 0.07)
        sc = rnd.uniform(0.98, 1.2)
        pts = []
        for i in range(18):
            t = i / 17
            a = a0 - span * t           # spiralling down and in, the way the rig turns
            zz = max(0.004, z - drop * t)
            rr = funnel_radius(zz) * sc
            pts.append((rr * math.cos(a), rr * math.sin(a) * 0.9, zz))
        pts.reverse()
        col = cols[k % len(cols)]
        strength = 1.4 if col[0] == 1 and col[1] == 1 and col[2] == 1 else 4.5
        tr = A.tube(f"Swoosh{k}", pts, rnd.choice((0.0022, 0.003, 0.004, 0.0055)), mat=A.emissive(f"SwooshMat{k}", col, strength * 1.2),
                    taper=[0.05 + 0.95 * (i / 17) ** 1.5 for i in range(18)])
        tr.parent = rig
        tr.visible_shadow = False
        A.kf(tr, 1, rotation_euler=(0, 0, 0))
        A.kf(tr, N, rotation_euler=(0, 0, -rnd.uniform(2.0, 6.0) * (1.4 - z / 0.3)))
        A.set_interp(tr, "LINEAR", paths=["rotation_euler"])
    # the toys and the shapes are pulled in, spiralling down, stretched toward the screen
    items = [("parrot-fly", 0.10, 1, 40), ("cow-jump", 0.09, 6, 46), ("boat-surf", 0.08, 1, 32), ("guitar-strum", 0.10, 10, 50),
             ("palette-fly", 0.07, 3, 37), ("note", 0.04, 12, 43), ("note", 0.035, 16, 48)]
    for i, (f, hgt, f0, f1) in enumerate(items):
        p, c = A.toy(f"Item{i}", f, hgt, o)
        th0, z0 = i * 0.9, 0.24 + 0.05 * (i % 3)
        def pos(t, th0=th0, z0=z0):
            z = z0 * (1 - t) ** 1.3
            r = funnel_radius(z) * (1.25 - 0.5 * t) + (0.10 * (1 - t / 0.25) if t < 0.25 else 0.0)
            a = th0 - t * 1.15 * math.pi
            return o + Vector((r * math.cos(a), r * math.sin(a) * 0.9, z + 0.006))
        A.visible(p, 1, f1)
        A.path_keys(p, 1, f1, lambda t, f0=f0, f1=f1: pos(max(0.0, (t * (f1 - 1) - (f0 - 1)) / (f1 - f0))), 1)
        for fr in range(1, f1 + 1, 2):
            t = max(0.0, (fr - f0) / (f1 - f0))
            k = max(0.0001, 1 - A.ease(max(0, t - 0.55) / 0.45, "in"))
            c.scale = ((1 - 0.25 * t) * k, (1 + 0.4 * t) * k, 1)
            c.rotation_euler = (0, 0, math.radians(25 * math.sin(i + fr * 0.25) - 40 * t))
            c.keyframe_insert("scale", frame=fr)
            c.keyframe_insert("rotation_euler", frame=fr)
    kinds = ["quarter", "triangle", "half", "square", "arch"]
    for i in range(10):
        ob = A.shape(kinds[i % 5], 0.024, (A.CORAL, A.LEMON, A.OCEAN, A.GRASS, A.BERRY)[i % 5], name=f"VS{i}")
        f0, f1 = 1 + 3 * i, 30 + 2 * i
        th0, z0 = i * 1.7, 0.18 + 0.1 * rnd.random()
        A.visible(ob, 1, f1)
        for fr in range(1, f1 + 1):
            t = max(0.0, (fr - f0) / (f1 - f0))
            z = z0 * (1 - t) ** 1.3
            r = funnel_radius(z) * (1.3 - 0.5 * t)
            a = th0 - t * 3.6 * math.pi
            ob.location = o + Vector((r * math.cos(a), r * math.sin(a) * 0.9, z + 0.008))
            ob.rotation_euler = (fr * 0.31 + i, fr * 0.23, fr * 0.17)
            s = max(0.0001, 1 - A.ease(max(0, t - 0.6) / 0.4, "in"))
            ob.scale = (s, s, s)
            for prop in ("location", "rotation_euler", "scale"):
                ob.keyframe_insert(prop, frame=fr)
        A.set_interp(ob, "LINEAR")
    conf = A.confetti(o + Vector((0, 0, 0.15)), 40, (0.16, 0.12, 0.15), seed=71)
    for j, c_ in enumerate(conf):
        th0, z0, f0 = math.atan2(c_.location.y - o.y, c_.location.x - o.x), max(0.03, c_.location.z - o.z), 1 + (j % 20)
        for fr in range(1, N + 1, 2):
            t = min(1.0, max(0.0, (fr - f0) / 36))
            z = z0 * (1 - t) ** 1.2
            r = funnel_radius(z) * (1.2 - 0.4 * t)
            a = th0 - t * 4 * math.pi
            c_.location = o + Vector((r * math.cos(a), r * math.sin(a) * 0.9, z + 0.004))
            c_.rotation_euler = (fr * 0.4 + j, fr * 0.3, j)
            s = 1.0 if t < 0.9 else max(0.0001, (1 - t) * 10)
            c_.scale = (0.006 * s, 0.012 * s, 1)
            for prop in ("location", "rotation_euler", "scale"):
                c_.keyframe_insert(prop, frame=fr)
        A.set_interp(c_, "LINEAR")
    # the screen glows brighter as it swallows everything, then flashes white into the end card
    vg = bpy.data.objects.new("VortexGlowPivot", None)
    bpy.context.collection.objects.link(vg)
    vg.location = A.screen_point(ph, 0, 0, 0.003)
    vg["billboard"] = True
    gl = A.glow("VortexGlow", (0, 0, 0), (0, 0, 1), 0.07, color=(1.0, 0.95, 0.85, 1), strength=4.0)
    gl.parent, gl.location, gl.rotation_euler = vg, (0, 0, 0), (0, 0, 0)
    A.kf(gl, 1, scale=(0.6, 0.6, 0.6))
    A.kf(gl, B(3), scale=(1.4, 1.4, 1.4))
    A.kf(gl, N, scale=(3.5, 3.5, 3.5))
    flash_screen(scr, [(1, 1.8), (B(3), 3.0), (N - 6, 6.0), (N, 14.0)])
    sl = A.screen_light(ph, 2.0)
    light_keys(sl, [(1, 2.0), (B(3), 4.0), (N, 16.0)])
    white_card(cam, [(1, 0.0), (N - 5, 0.0), (N, 1.0)])
    A.compositor(glare=0.6, blur=0.45)
    return cam


# ---------------------------------------------------------------- 8 · end card
def shot8(N):
    A.world((1.0, 0.95, 0.85), 0.5)
    wall = A.emissive("Wall", A.hexcol("FFC530"), 1.0)
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 1.2, 0.5), rotation=(math.radians(90), 0, 0))
    bpy.context.object.data.materials.append(wall)
    floor = A.glossy("Floor", A.hexcol("FFC530"), rough=0.4, coat=0.2)
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
    bpy.context.object.data.materials.append(floor)
    A.light_area((0.0, -0.9, 1.0), (0, 0.3, 0.2), 1.6, 45, (1.0, 0.97, 0.92), "Key")
    A.light_area((-0.8, -0.1, 0.4), (0, 0.3, 0.1), 0.8, 12, (1.0, 0.92, 0.85), "Side")
    cam = A.camera((0.0, -1.15, 0.40), (0.0, 0.45, 0.37), lens=40, fstop=11.0, focus=1.5)
    A.camera_move(cam, [(1, (0.0, -1.22, 0.42), (0.0, 0.45, 0.37)), (N, (0.0, -1.12, 0.40), (0.0, 0.45, 0.37))], focus=lambda l, t: 1.5)
    white_card(cam, [(1, 1.0), (3, 1.0), (10, 0.0)])
    logo = A.card("Logo", "logo", 0.185, (0.0, 0.5, 0.745), rot=(math.radians(90), 0, 0), emission=1.15, lit=0.1)
    A.pop(logo, 3, 9, over=1.18)
    A.kf(logo, B(2), scale=(1, 1, 1))
    A.kf(logo, B(2) + 4, scale=(1.06, 1.06, 1.06))
    A.kf(logo, B(2) + 9, scale=(1, 1, 1))
    # the six toys drop in one after another, on the eighth notes, and squash as they land
    row = [("toy-sea", 0.17, -0.19, 0.38), ("toy-paint", 0.12, -0.055, 0.44), ("toy-tiles", 0.15, 0.065, 0.43), ("toy-guitar", 0.21, 0.195, 0.38),
           ("toy-animals", 0.155, -0.12, 0.20), ("toy-parrot", 0.16, 0.115, 0.21)]
    for i, (f, hgt, x, y) in enumerate(row):
        c = A.card(f, f, hgt, (x, y, 0), rot=(math.radians(90), 0, math.radians(-x * 40)), emission=1.1, lit=0.15, anchor=(0.5, 0.0))
        land = 10 + round(3.75 * i)
        A.visible(c, max(1, land - 7))
        A.kf(c, max(1, land - 7), location=(x, y, 0.55))
        A.kf(c, land, location=(x, y, 0.0))
        A.set_interp(c, "BEZIER", "EASE_IN", paths=["location"])
        A.kf(c, land - 1, scale=(0.85, 1.2, 1))
        A.squash(c, land, amount=0.22, dur=8)
    # the line, word by word on the beats (Baloo 2 cards made by build.py)
    text = os.path.join(A.BUILD, "text")
    for i, z in enumerate((0.555, 0.47, 0.385)):
        t = A.card(f"Line{i + 1}", os.path.join(text, f"line{i + 1}.png"), 0.088, (0.0, 0.45, z), rot=(math.radians(90), 0, 0), emission=1.0, lit=0.0, shadow=False)
        A.visible(t, B(2) + 7 * i)
        A.pop(t, B(2) + 7 * i, 6, over=1.2)
    A.compositor(glare=0.3, blur=0.6)
    return cam


VIEWS = {"8": ("Standard", "None", 0.0)}
BUILDERS = {"1": shot1, "2": shot2, "3": shot3, "4": shot4, "5": shot5, "6a": shot6a, "6b": shot6b, "6c": shot6c, "7": shot7, "8": shot8}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", required=True)
    ap.add_argument("--samples", type=int, default=32)
    ap.add_argument("--percent", type=int, default=100)
    ap.add_argument("--every", type=int, default=1)
    ap.add_argument("--out", default="")
    ap.add_argument("--still", type=int, default=0)
    ap.add_argument("--frames", default="", help="comma-separated local frames")
    ap.add_argument("--save", default="")
    a = ap.parse_args(argv)
    N = T.frames(a.shot)
    A.reset()
    view, look, expo = VIEWS.get(a.shot, ("AgX", "AgX - Punchy", 0.0))
    A.render_setup(samples=a.samples, percent=a.percent, look=look, view=view, exposure=expo, frames=N)
    cam = BUILDERS[a.shot](N)
    A.bake_billboards(cam, 1, N)
    bpy.context.scene.frame_set(1)
    if a.save:
        A.save(a.save)
    out = a.out or os.path.join(A.BUILD, "frames", a.shot)
    if a.still:
        frames = [a.still]
    elif a.frames:
        frames = [int(x) for x in a.frames.split(",")]
    else:
        frames = list(range(1, N + 1, a.every))
    A.render_frames(out, frames, prefix=f"{a.shot}:")


if __name__ == "__main__":
    main()
