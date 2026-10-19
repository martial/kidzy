"""Shared set, materials, props and animation helpers for the « The toys break out » ad (Blender 4.3,
run headless). Units are metres at real scale: the phone is an iPhone 15 (71.6 x 147.6 x 7.8 mm).

Everything that moves is keyframed (never set from a frame handler), so Cycles' vector pass sees the
motion and the compositor's vector blur smears it."""
import bpy, bmesh, glob, math, os, random
from mathutils import Vector, Matrix, kdtree

AD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(os.path.dirname(AD))
ART = os.path.join(AD, "art")
CUT = os.path.join(ART, "cut")
BUILD = os.environ.get("AD_BUILD", os.path.join(AD, "build"))
SCREENS = os.path.join(BUILD, "screens")
FONT = os.path.join(REPO, "ios", "SketchesForKids", "Resources", "Fonts", "Baloo2-ExtraBold.ttf")

def hexcol(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)

CORAL, LEMON, OCEAN, GRASS, BERRY, TANGERINE, SUN = (hexcol(x) for x in ("FF6B6B", "FFD23F", "4D96FF", "5FD068", "9B5DE5", "FF9F12", "FFC530"))
PINK, TURQ, INK = hexcol("FF8FB1"), hexcol("2EC4D6"), hexcol("1F2A44")
CANDY = [CORAL, LEMON, OCEAN, GRASS, BERRY, PINK, TANGERINE, hexcol("FFFFFF")]

# ---------------------------------------------------------------- scene / render
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(7)

def render_setup(samples=32, w=1080, h=1920, percent=100, look="AgX - Punchy", view="AgX", exposure=0.0, frames=1):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "METAL"
    sc.cycles.device = "GPU"
    sc.cycles.samples = samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.03
    sc.cycles.use_animated_seed = True
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.denoising_input_passes = "RGB_ALBEDO_NORMAL"
    sc.cycles.denoising_prefilter = "ACCURATE"
    sc.cycles.max_bounces = 8
    sc.cycles.transparent_max_bounces = 16
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.blur_glossy = 1.0
    sc.render.use_persistent_data = True
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = percent
    sc.render.film_transparent = False
    sc.view_settings.view_transform = view
    sc.view_settings.exposure = exposure
    try:
        sc.view_settings.look = look
    except TypeError:
        pass
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.fps = 30
    # no render motion blur: it washes out the glossy parts; the compositor's vector blur smears instead
    sc.render.use_motion_blur = False
    bpy.context.view_layer.use_pass_vector = True
    bpy.context.view_layer.use_pass_z = True
    sc.frame_start, sc.frame_end = 1, frames
    sc.frame_set(1)
    return sc

def world(color=(1.0, 0.93, 0.85), strength=0.55):
    wd = bpy.data.worlds.new("World")
    bpy.context.scene.world = wd
    wd.use_nodes = True
    bg = wd.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*color, 1)
    bg.inputs[1].default_value = strength
    return wd

def camera(loc, target, lens=50, fstop=2.0, focus=None, name="Cam"):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.sensor_fit = "VERTICAL"
    cd.sensor_height = 24
    cd.clip_start = 0.005
    cam = bpy.data.objects.new(name, cd)
    bpy.context.collection.objects.link(cam)
    cam.location = loc
    look_at(cam, target)
    cd.dof.use_dof = True
    cd.dof.aperture_fstop = fstop
    cd.dof.focus_distance = focus if focus else (Vector(target) - Vector(loc)).length
    bpy.context.scene.camera = cam
    return cam

def look_at(obj, target, roll=0.0):
    d = Vector(target) - obj.location
    q = d.to_track_quat("-Z", "Y")
    obj.rotation_euler = (q.to_matrix().to_4x4() @ Matrix.Rotation(roll, 4, "Z")).to_euler()

def light_area(loc, target, size, power, color=(1, 1, 1), name="Area", shape="DISK"):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape, ld.size, ld.energy, ld.color = shape, size, power, color
    ob = bpy.data.objects.new(name, ld)
    bpy.context.collection.objects.link(ob)
    ob.location = loc
    look_at(ob, target)
    return ob

def light_sun(direction, strength, color=(1.0, 0.86, 0.68), angle=2.5):
    ld = bpy.data.lights.new("Sun", "SUN")
    ld.energy, ld.color, ld.angle = strength, color, math.radians(angle)
    ob = bpy.data.objects.new("Sun", ld)
    bpy.context.collection.objects.link(ob)
    look_at(ob, Vector(direction))
    ob.location = (0, 0, 2)
    ob.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
    return ob

def compositor(glare=0.6, vignette=0.0, blur=1.0):
    """Vector blur (the motion blur of the film, from the vector pass), then glare. The vignette is added
    in the edit (ffmpeg), where it is cheap to tune. `blur` is the shutter: 1 = 180 degrees at 30 fps."""
    sc = bpy.context.scene
    sc.use_nodes = True
    nt = sc.node_tree
    nt.nodes.clear()
    rl = nt.nodes.new("CompositorNodeRLayers")
    img = rl.outputs["Image"]
    if blur > 0:
        vb = nt.nodes.new("CompositorNodeVecBlur")
        vb.samples = 32
        vb.factor = 0.5 * blur
        vb.speed_min = 0
        vb.speed_max = 160
        vb.use_curved = False
        nt.links.new(img, vb.inputs["Image"])
        depth = rl.outputs.get("Depth") or rl.outputs.get("Z")
        nt.links.new(depth, vb.inputs[1])
        nt.links.new(rl.outputs["Vector"], vb.inputs[2])
        img = vb.outputs["Image"]
    g = nt.nodes.new("CompositorNodeGlare")
    g.glare_type = "FOG_GLOW"
    g.quality = "HIGH"
    g.threshold = 0.95
    g.mix = -1 + glare * 0.5
    g.size = 8
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(img, g.inputs["Image"])
    nt.links.new(g.outputs["Image"], comp.inputs["Image"])

# ---------------------------------------------------------------- materials
def _mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m, m.node_tree.nodes, m.node_tree.links, m.node_tree.nodes["Principled BSDF"]

def glossy(name, color, rough=0.22, coat=0.6, sss=0.0, transmission=0.0, ior=1.45):
    m, n, l, p = _mat(name)
    p.inputs["Base Color"].default_value = color
    p.inputs["Roughness"].default_value = rough
    p.inputs["Coat Weight"].default_value = coat
    p.inputs["Coat Roughness"].default_value = 0.06
    p.inputs["IOR"].default_value = ior
    if sss:
        p.inputs["Subsurface Weight"].default_value = sss
        p.inputs["Subsurface Radius"].default_value = (0.02, 0.012, 0.008)
        p.inputs["Subsurface Scale"].default_value = 0.02
    if transmission:
        p.inputs["Transmission Weight"].default_value = transmission
    return m

def vcol_glossy(name, attr="Col", rough=0.16):
    m, n, l, p = _mat(name)
    a = n.new("ShaderNodeVertexColor")
    a.layer_name = attr
    l.new(a.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    p.inputs["Coat Weight"].default_value = 0.8
    p.inputs["Coat Roughness"].default_value = 0.04
    p.inputs["Subsurface Weight"].default_value = 0.15
    p.inputs["Subsurface Scale"].default_value = 0.01
    return m

def image_mat(name, path, emission=1.0, lit=0.25, alpha=True, rough=0.4, sequence=0):
    """A card from a cut-out: mostly its own (baked) light, a little of the scene's, alpha from the image.
    `sequence` = number of frames when `path` is the first image of a numbered sequence (0001.jpg...):
    frame k of the sequence then shows on local frame k of the shot."""
    m, n, l, p = _mat(name)
    tex = n.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(path, check_existing=True)
    tex.interpolation = "Cubic"
    if sequence > 1:
        tex.image.source = "SEQUENCE"
        u = tex.image_user
        u.frame_duration = sequence
        u.frame_start = 1
        u.frame_offset = 0
        u.use_auto_refresh = True
        u.use_cyclic = False
    em = n.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = emission
    l.new(tex.outputs["Color"], em.inputs["Color"])
    l.new(tex.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    add = n.new("ShaderNodeMixShader")
    add.inputs[0].default_value = lit
    l.new(em.outputs[0], add.inputs[1])
    l.new(p.outputs[0], add.inputs[2])
    out = n["Material Output"]
    if alpha:
        tr = n.new("ShaderNodeBsdfTransparent")
        mx = n.new("ShaderNodeMixShader")
        l.new(tex.outputs["Alpha"], mx.inputs[0])
        l.new(tr.outputs[0], mx.inputs[1])
        l.new(add.outputs[0], mx.inputs[2])
        l.new(mx.outputs[0], out.inputs["Surface"])
        m.blend_method = "HASHED"
    else:
        l.new(add.outputs[0], out.inputs["Surface"])
    return m, tex.image

def emissive(name, color, strength):
    m, n, l, p = _mat(name)
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    l.new(em.outputs[0], n["Material Output"].inputs["Surface"])
    return m

# ---------------------------------------------------------------- set
def table(size=4.0, uv_repeat=5.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    t = bpy.context.object
    t.name = "Table"
    m, n, l, p = _mat("Oak")
    tex = n.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(ART, "wood.jpg"), check_existing=True)
    mapping = n.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (uv_repeat, uv_repeat, 1)
    tc = n.new("ShaderNodeTexCoord")
    l.new(tc.outputs["UV"], mapping.inputs["Vector"])
    l.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    l.new(tex.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.42
    p.inputs["Coat Weight"].default_value = 0.25
    p.inputs["Coat Roughness"].default_value = 0.15
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.05
    l.new(tex.outputs["Color"], bump.inputs["Height"])
    l.new(bump.outputs["Normal"], p.inputs["Normal"])
    t.data.materials.append(m)
    return t

def backdrop(cam, dist=3.0, height_m=None, path=None, strength=1.0):
    """The kitchen photo on a card facing the camera, far behind the subject (DOF blurs it)."""
    path = path or os.path.join(ART, "kitchen.jpg")
    m, img = image_mat("Kitchen", path, emission=strength, lit=0.0, alpha=False)
    cd = cam.data
    fov_v = 2 * math.atan(cd.sensor_height / 2 / cd.lens)
    h = height_m or 2 * dist * math.tan(fov_v / 2) * 1.15
    w = h * img.size[0] / img.size[1]
    bpy.ops.mesh.primitive_plane_add(size=1)
    card = bpy.context.object
    card.name = "Backdrop"
    card.scale = (w, h, 1)
    fwd = cam.matrix_world.to_quaternion() @ Vector((0, 0, -1))
    card.location = cam.location + fwd * dist
    card.rotation_euler = cam.rotation_euler
    card.data.materials.append(m)
    card.visible_shadow = False
    return card

def rounded_plane(name, w, h, r, segments=10):
    bm = bmesh.new()
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(segments + 1):
            a = math.radians(a0 + 90 * i / segments)
            pts.append(bm.verts.new((cx + r * math.cos(a), cy + r * math.sin(a), 0)))
    f = bm.faces.new(pts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    # UVs from the bounding box
    me.uv_layers.new(name="UV")
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        me.uv_layers["UV"].data[loop.index].uv = (co.x / w + 0.5, co.y / h + 0.5)
    return ob

def screen_frames(role):
    """The prepared frames of a screen role (build.py writes build/screens/<role>/0001.jpg...)."""
    frames = sorted(glob.glob(os.path.join(SCREENS, role, "*.jpg")))
    if not frames:
        raise SystemExit(f"no prepared frames for screen role {role!r} in {SCREENS}: run render.sh")
    return frames[0], len(frames)

def phone(screen="home", loc=(0, 0, 0), rot_z=0.0, screen_strength=1.6):
    """iPhone 15-ish: black glass slab, satin aluminium band, screen = emission of the app, fed by the
    screen role `screen` (a clip or a still from screens/, see screens.json)."""
    W, H, T, R = 0.0716, 0.1476, 0.0078, 0.0105
    body = rounded_plane("PhoneBody", W, H, R, 12)
    sol = body.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = T
    sol.offset = 1
    bev = body.modifiers.new("bev", "BEVEL")
    bev.width = 0.0022
    bev.segments = 6
    bev.limit_method = "ANGLE"
    body.data.materials.append(glossy("Aluminium", hexcol("3A3F4A"), rough=0.32, coat=0.0))
    body.data.materials[0].node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 1.0
    glass = rounded_plane("PhoneGlass", W - 0.0012, H - 0.0012, R - 0.0006, 12)
    glass.location.z = T + 0.00005
    gm = glossy("BlackGlass", (0.004, 0.004, 0.005, 1), rough=0.03, coat=1.0)
    glass.data.materials.append(gm)
    scr = rounded_plane("PhoneScreen", W - 0.0055, H - 0.0055, R - 0.003, 12)
    scr.location.z = T + 0.0001
    first, count = screen_frames(screen)
    sm, simg = image_mat("Screen", first, emission=screen_strength, lit=0.0, alpha=False, sequence=count)
    # glossy reflection over the screen: mix in a near-black clear coat
    n, l = sm.node_tree.nodes, sm.node_tree.links
    out = n["Material Output"]
    emis_out = out.inputs["Surface"].links[0].from_socket
    gl = n.new("ShaderNodeBsdfGlossy")
    gl.inputs["Roughness"].default_value = 0.02
    gl.inputs["Color"].default_value = (0.35, 0.35, 0.35, 1)
    fr = n.new("ShaderNodeFresnel")
    fr.inputs["IOR"].default_value = 1.25
    mx = n.new("ShaderNodeMixShader")
    l.new(fr.outputs[0], mx.inputs[0])
    l.new(emis_out, mx.inputs[1])
    l.new(gl.outputs[0], mx.inputs[2])
    l.new(mx.outputs[0], out.inputs["Surface"])
    scr.data.materials.append(sm)
    island = rounded_plane("Island", 0.0185, 0.0055, 0.00275, 8)
    island.location = (0, H / 2 - 0.0028 - 0.0055 / 2 - 0.0012, T + 0.00015)
    island.data.materials.append(gm)
    root = bpy.data.objects.new("Phone", None)
    bpy.context.collection.objects.link(root)
    for o in (body, glass, scr, island):
        o.parent = root
    root.location = loc
    root.rotation_euler = (0, 0, rot_z)
    return root, scr

def screen_point(phone_root, u, v, lift=0.0):
    """World position of a point on the screen, u/v in -0.5..0.5, lifted along the phone's normal."""
    W, H, T = 0.0716 - 0.0055, 0.1476 - 0.0055, 0.0078
    bpy.context.view_layer.update()
    return phone_root.matrix_world @ Vector((u * W, v * H, T + lift))

def cut_path(file):
    """A cut-out by name: "parrot-burst", "parrot-burst.png" and "parrot-burst.webp" all find art/cut/parrot-burst.webp."""
    stem = os.path.splitext(os.path.basename(file))[0]
    for ext in (".webp", ".png"):
        p = os.path.join(CUT, stem + ext)
        if os.path.exists(p):
            return p
    if os.path.isabs(file) and os.path.exists(file):
        return file
    raise SystemExit(f"missing cut-out {file}")

def card(name, file, height, loc, face=None, rot=(0, 0, 0), emission=1.15, lit=0.2, shadow=True, anchor=None):
    """A cut-out toy on a plane `height` metres tall, upright (local +Y is up), facing `face` if given."""
    path = cut_path(file)
    m, img = image_mat(name + "Mat", path, emission=emission, lit=lit)
    w = height * img.size[0] / img.size[1]
    bpy.ops.mesh.primitive_plane_add(size=1)
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(m)
    ob.scale = (w, height, 1)
    bpy.ops.object.transform_apply(scale=True)
    if anchor:
        # put the image point `anchor` (0..1 from the bottom-left) at the object's origin
        ob.data.transform(Matrix.Translation((-(anchor[0] - 0.5) * w, -(anchor[1] - 0.5) * height, 0)))
    ob.location = loc
    if face is not None:
        look_at(ob, face)
        ob.rotation_euler.rotate_axis("Z", rot[2]) if rot[2] else None
        # look_at points -Z at the target; the plane's visible side is +Z, flip it
        ob.rotation_euler.rotate_axis("Y", math.pi)
    else:
        ob.rotation_euler = rot
    ob.visible_shadow = shadow
    return ob

# ---------------------------------------------------------------- props
def tube(name, pts, radius, mat=None, taper=None, res=4, bevel_res=8):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = res
    cu.bevel_depth = radius
    cu.bevel_resolution = bevel_res
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for p, co in zip(sp.points, pts):
        p.co = (*co, 1)
        p.radius = 1.0
    if taper:
        for p, r in zip(sp.points, taper):
            p.radius = r
    sp.use_endpoint_u = True
    sp.order_u = 4
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    if mat:
        ob.data.materials.append(mat)
    return ob

def to_mesh(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    new = bpy.data.objects.new(ob.name, me)
    bpy.context.collection.objects.link(new)
    new.matrix_world = ob.matrix_world
    bpy.data.objects.remove(ob)
    return new

def mix_paint(a, b, ca, cb, mixed, reach):
    """Vertex colours: each ribbon keeps its colour, and turns `mixed` where the other one is within `reach`."""
    def tree(ob):
        me = ob.data
        kd = kdtree.KDTree(len(me.vertices))
        for i, v in enumerate(me.vertices):
            kd.insert(ob.matrix_world @ v.co, i)
        kd.balance()
        return kd
    ta, tb = tree(a), tree(b)
    for ob, other, base in ((a, tb, ca), (b, ta, cb)):
        me = ob.data
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        for i, v in enumerate(me.vertices):
            _, _, d = other.find(ob.matrix_world @ v.co)
            t = max(0.0, min(1.0, (reach - d) / (reach * 0.6)))
            t = t * t * (3 - 2 * t)
            attr.data[i].color = tuple(base[k] * (1 - t) + mixed[k] * t for k in range(4))
        ob.data.materials.append(vcol_glossy(ob.name + "Paint"))

def drops(name, centre, count, spread, rmin, rmax, color, seed=1, mat=None, stretch=None):
    rnd = random.Random(seed)
    mat = mat or glossy(name + "Mat", color, rough=0.12, coat=0.8, sss=0.1)
    obs = []
    for i in range(count):
        r = rnd.uniform(rmin, rmax)
        off = Vector((rnd.gauss(0, spread[0]), rnd.gauss(0, spread[1]), rnd.gauss(0, spread[2])))
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=24, ring_count=12, location=Vector(centre) + off)
        o = bpy.context.object
        bpy.ops.object.shade_smooth()
        o.name = f"{name}{i}"
        if stretch:
            o.scale = (1, 1, stretch)
            look_at(o, Vector(centre) + off * 2)
        o.data.materials.append(mat)
        obs.append(o)
    return obs

def confetti(centre, count, spread, size=(0.006, 0.012), seed=3):
    rnd = random.Random(seed)
    mats = [glossy(f"Conf{i}", c, rough=0.3, coat=0.3) for i, c in enumerate(CANDY)]
    obs = []
    for i in range(count):
        off = Vector((rnd.uniform(-1, 1) * spread[0], rnd.uniform(-1, 1) * spread[1], rnd.uniform(0, 1) * spread[2]))
        bpy.ops.mesh.primitive_plane_add(size=1, location=Vector(centre) + off)
        o = bpy.context.object
        o.scale = (size[0], size[1], 1)
        o.rotation_euler = (rnd.uniform(0, 6.3), rnd.uniform(0, 6.3), rnd.uniform(0, 6.3))
        sol = o.modifiers.new("s", "SOLIDIFY")
        sol.thickness = 0.0006
        o.data.materials.append(rnd.choice(mats))
        obs.append(o)
    return obs

def _extrude_outline(name, outline, depth, bevel=0.004, mat=None):
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0)) for x, y in outline]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += depth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    bv = ob.modifiers.new("bev", "BEVEL")
    bv.width = bevel
    bv.segments = 5
    bv.limit_method = "ANGLE"
    bv.angle_limit = math.radians(30)
    bpy.context.view_layer.objects.active = ob
    for p in me.polygons:
        p.use_smooth = True
    ob.modifiers.new("ws", "WEIGHTED_NORMAL")
    # centre the origin
    me.transform(Matrix.Translation(-sum((v.co for v in me.vertices), Vector()) / len(me.vertices)))
    if mat:
        me.materials.append(mat)
    return ob

def shape(kind, size, color, name=None):
    """The app's tiles as chunky glossy blocks: quarter, triangle, half, square, arch."""
    s, n = size, 24
    if kind == "quarter":
        pts = [(0, 0)] + [(s * math.cos(a), s * math.sin(a)) for a in (math.pi / 2 * i / n for i in range(n + 1))]
    elif kind == "triangle":
        pts = [(0, 0), (s, 0), (s / 2, s * 0.9)]
    elif kind == "half":
        pts = [(s * math.cos(a), s * math.sin(a)) for a in (math.pi * i / n for i in range(n + 1))]
    elif kind == "square":
        r = s * 0.35
        pts = [(0, 0), (s, 0)] + [(s - r + r * math.cos(a), s - r + r * math.sin(a)) for a in (math.pi / 2 * i / 8 for i in range(9))] + [(0, s)]
    else:  # arch
        ro, ri = s, s * 0.45
        pts = [(ro * math.cos(a), ro * math.sin(a)) for a in (math.pi * i / n for i in range(n + 1))] + \
              [(ri * math.cos(a), ri * math.sin(a)) for a in (math.pi * (n - i) / n for i in range(n + 1))]
    return _extrude_outline(name or kind, pts, s * 0.42, bevel=s * 0.09, mat=glossy((name or kind) + "Mat", color, rough=0.2, coat=0.7))

def rays(name, centre, facing, count=14, length=0.5, width=0.05, color=(1.0, 0.92, 0.7, 1), strength=3.0, seed=5):
    """A fan of soft light rays behind a subject (emissive wedges fading out)."""
    rnd = random.Random(seed)
    m, n, l, p = _mat(name + "Mat")
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    grad = n.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    tc = n.new("ShaderNodeTexCoord")
    mp = n.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / length, 1 / length, 1 / length)
    l.new(tc.outputs["Object"], mp.inputs["Vector"])
    l.new(mp.outputs["Vector"], grad.inputs["Vector"])
    pw = n.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 1.6
    l.new(grad.outputs["Fac"], pw.inputs[0])
    tr = n.new("ShaderNodeBsdfTransparent")
    mx = n.new("ShaderNodeMixShader")
    l.new(pw.outputs[0], mx.inputs[0])
    l.new(tr.outputs[0], mx.inputs[1])
    l.new(em.outputs[0], mx.inputs[2])
    l.new(mx.outputs[0], n["Material Output"].inputs["Surface"])
    m.blend_method = "BLEND"
    bm = bmesh.new()
    c = bm.verts.new((0, 0, 0))
    for i in range(count):
        a = 2 * math.pi * (i + rnd.uniform(-0.2, 0.2)) / count
        wa = width * rnd.uniform(0.6, 1.4) / length
        L = length * rnd.uniform(0.7, 1.1)
        v1 = bm.verts.new((L * math.cos(a - wa), L * math.sin(a - wa), 0))
        v2 = bm.verts.new((L * math.cos(a + wa), L * math.sin(a + wa), 0))
        bm.faces.new((c, v1, v2)) if i == 0 else bm.faces.new((bm.verts.new((0, 0, 0)), v1, v2))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.location = centre
    look_at(ob, facing)
    ob.rotation_euler.rotate_axis("Y", math.pi)
    me.materials.append(m)
    ob.visible_shadow = False
    ob.visible_diffuse = False
    ob.visible_glossy = False
    return ob

def glow(name, centre, facing, radius, color=(1.0, 0.85, 0.55, 1), strength=4.0):
    """A soft round glow card (emission fading to transparent), always behind the subject."""
    m, n, l, p = _mat(name + "Mat")
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    grad = n.new("ShaderNodeTexGradient")
    grad.gradient_type = "QUADRATIC_SPHERE"
    tc = n.new("ShaderNodeTexCoord")
    mp = n.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1 / radius, 1 / radius, 1 / radius)
    l.new(tc.outputs["Object"], mp.inputs["Vector"])
    l.new(mp.outputs["Vector"], grad.inputs["Vector"])
    pw = n.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 2.2
    l.new(grad.outputs["Fac"], pw.inputs[0])
    tr = n.new("ShaderNodeBsdfTransparent")
    mx = n.new("ShaderNodeMixShader")
    l.new(pw.outputs[0], mx.inputs[0])
    l.new(tr.outputs[0], mx.inputs[1])
    l.new(em.outputs[0], mx.inputs[2])
    l.new(mx.outputs[0], n["Material Output"].inputs["Surface"])
    m.blend_method = "BLEND"
    bpy.ops.mesh.primitive_plane_add(size=radius * 2, location=centre)
    ob = bpy.context.object
    ob.name = name
    look_at(ob, facing)
    ob.rotation_euler.rotate_axis("Y", math.pi)
    ob.data.materials.append(m)
    ob.visible_shadow = False
    ob.visible_diffuse = False
    ob.visible_glossy = False
    return ob

def text3d(body, size, loc, rot=(math.radians(90), 0, 0), color=None, extrude=0.08, align="CENTER", name="Text", outline=None):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.font = bpy.data.fonts.load(FONT, check_existing=True)
    cu.size = size
    cu.extrude = extrude * size
    cu.bevel_depth = extrude * size * 0.35
    cu.bevel_resolution = 4
    cu.align_x = align
    cu.align_y = "CENTER"
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    ob.location, ob.rotation_euler = loc, rot
    m = glossy(name + "Mat", color or (1, 1, 1, 1), rough=0.45, coat=0.0)
    m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.15
    ob.data.materials.append(m)
    if outline:
        back = ob.copy()
        back.data = ob.data.copy()
        back.name = name + "Outline"
        bpy.context.collection.objects.link(back)
        back.data.offset = size * 0.045
        back.data.extrude = extrude * size * 0.6
        back.data.bevel_depth = 0
        back.data.materials.clear()
        back.data.materials.append(glossy(name + "OutlineMat", outline, rough=0.6, coat=0.0))
        fwd = Matrix(ob.rotation_euler.to_matrix()) @ Vector((0, 0, -1))
        back.location = Vector(loc) + fwd * size * 0.10 + Vector((0, 0, -size * 0.03))
    return ob

def render(path):
    sc = bpy.context.scene
    sc.frame_set(1)
    sc.render.filepath = path
    import time
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {path} in {time.time() - t:.1f}s")

def save(path):
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)

# ---------------------------------------------------------------- water
def water_mat(name="Water", foam=0.0):
    """Clear turquoise water; `foam` (0..1) streaks white foam over it with a stretched noise."""
    m, n, l, p = _mat(name)
    p.inputs["Base Color"].default_value = hexcol("8FDcFF")
    p.inputs["Roughness"].default_value = 0.02
    p.inputs["IOR"].default_value = 1.33
    p.inputs["Transmission Weight"].default_value = 0.86
    p.inputs["Subsurface Weight"].default_value = 0.14
    p.inputs["Subsurface Radius"].default_value = (0.2, 0.6, 0.7)
    p.inputs["Subsurface Scale"].default_value = 0.03
    p.inputs["Coat Weight"].default_value = 0.5
    vol = n.new("ShaderNodeVolumeAbsorption")
    vol.inputs["Color"].default_value = hexcol("9AE6FF")
    vol.inputs["Density"].default_value = 0.45
    out = n["Material Output"]
    l.new(vol.outputs[0], out.inputs["Volume"])
    if foam > 0:
        fp = n.new("ShaderNodeBsdfPrincipled")
        fp.inputs["Base Color"].default_value = (0.95, 0.99, 1.0, 1)
        fp.inputs["Roughness"].default_value = 0.35
        fp.inputs["Subsurface Weight"].default_value = 0.4
        fp.inputs["Subsurface Scale"].default_value = 0.01
        tc = n.new("ShaderNodeTexCoord")
        mp = n.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (90.0, 90.0, 40.0)
        l.new(tc.outputs["Object"], mp.inputs["Vector"])
        nz = n.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 1.0
        nz.inputs["Detail"].default_value = 6.0
        nz.inputs["Roughness"].default_value = 0.65
        l.new(mp.outputs["Vector"], nz.inputs["Vector"])
        ramp = n.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.60 - 0.08 * foam
        ramp.color_ramp.elements[1].position = 0.66 - 0.08 * foam
        l.new(nz.outputs["Fac"], ramp.inputs["Fac"])
        mx = n.new("ShaderNodeMixShader")
        l.new(ramp.outputs["Color"], mx.inputs[0])
        l.new(p.outputs[0], mx.inputs[1])
        l.new(fp.outputs[0], mx.inputs[2])
        l.new(mx.outputs[0], out.inputs["Surface"])
    return m

def wave(name, path, widths, thick, origin, yaw, mat=None, noise=0.006, seed=2, curl=0.0):
    """A sheet of water following `path` (list of (forward, up) in metres), as wide as `widths` along it,
    then thickened, subdivided and wobbled. `origin` and `yaw` place it; forward is local -Y (toward camera)."""
    bm = bmesh.new()
    rows = []
    N = 9
    for (f, z), w in zip(path, widths):
        row = []
        for j in range(N):
            u = j / (N - 1) - 0.5
            # edges lift a little: a curved trough, like a breaking wave
            row.append(bm.verts.new((u * w, -f, z + abs(u) ** 2 * w * curl)))
        rows.append(row)
    for a, b in zip(rows, rows[1:]):
        for j in range(N - 1):
            bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for p_ in me.polygons:
        p_.use_smooth = True
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = sub.render_levels = 3
    sol = ob.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = thick
    sol.offset = 0
    tex = bpy.data.textures.new(name + "Noise", "CLOUDS")
    tex.noise_scale = 0.03
    dsp = ob.modifiers.new("dsp", "DISPLACE")
    dsp.texture = tex
    dsp.strength = noise
    sub2 = ob.modifiers.new("sub2", "SUBSURF")
    sub2.levels = sub2.render_levels = 1
    ob.location = origin
    ob.rotation_euler = (0, 0, yaw)
    ob.data.materials.append(mat or water_mat())
    return ob

def gush(name, points, origin, seed=4, mat=None, res=0.0025):
    """Liquid from metaballs: `points` = [(x, y, z, radius)] in local metres, fused into one blobby body."""
    rnd = random.Random(seed)
    mb = bpy.data.metaballs.new(name)
    mb.resolution = res * 2
    mb.render_resolution = res
    mb.threshold = 0.6
    for x, y, z, r in points:
        e = mb.elements.new()
        e.co = (x, y, z)
        e.radius = r
        e.stiffness = 2.0
    ob = bpy.data.objects.new(name, mb)
    bpy.context.collection.objects.link(ob)
    ob.location = origin
    ob.data.materials.append(mat or water_mat())
    return ob

def fling(ob, vel=(0, 0, 0), spin=(0, 0, 0), fps=30):
    """Linear motion through frame 1 (keys at 0 and 2): what the motion blur of a still needs, and the
    seed of the animation. vel in m/s, spin in rad/s."""
    loc, rot = ob.location.copy(), ob.rotation_euler.copy()
    for f, k in ((0, -1), (2, 1)):
        ob.location = loc + Vector(vel) * (k / fps)
        ob.rotation_euler = (rot.x + spin[0] * k / fps, rot.y + spin[1] * k / fps, rot.z + spin[2] * k / fps)
        ob.keyframe_insert("location", frame=f)
        ob.keyframe_insert("rotation_euler", frame=f)
    ob.location, ob.rotation_euler = loc, rot
    ad = ob.animation_data
    if ad and ad.action:
        for fc in ad.action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"

def burst(obs, centre, speed=0.8, spin=12.0, seed=1, up=0.3):
    """Fling objects outward from a centre, tumbling."""
    rnd = random.Random(seed)
    for o in obs:
        d = (o.location - Vector(centre))
        d = d.normalized() if d.length > 1e-6 else Vector((0, 0, 1))
        v = d * speed * rnd.uniform(0.5, 1.3) + Vector((0, 0, up * speed))
        fling(o, v, (rnd.uniform(-spin, spin), rnd.uniform(-spin, spin), rnd.uniform(-spin, spin)))

def screen_light(phone_root, power=1.2, color=(1.0, 0.95, 0.85)):
    """The screen lights what is above it."""
    ld = bpy.data.lights.new("ScreenLight", "AREA")
    ld.shape, ld.size, ld.size_y = "RECTANGLE", 0.066, 0.142
    ld.energy, ld.color = power, color
    ob = bpy.data.objects.new("ScreenLight", ld)
    bpy.context.collection.objects.link(ob)
    ob.parent = phone_root
    ob.location = (0, 0, 0.0095)
    ob.rotation_euler = (math.pi, 0, 0)  # area lights shine along -Z: flip to shine up
    return ob

# ---------------------------------------------------------------- animation
def kf(ob, frame, **props):
    """Keyframe transform properties at `frame`: kf(ob, 10, location=(..), scale=(..))."""
    for k, v in props.items():
        setattr(ob, k, v)
        ob.keyframe_insert(k, frame=frame)

def set_interp(idblock, mode="BEZIER", easing=None, paths=None):
    ad = idblock.animation_data
    if not (ad and ad.action):
        return
    for fc in ad.action.fcurves:
        if paths and not any(fc.data_path.startswith(p) for p in paths):
            continue
        for kp in fc.keyframe_points:
            kp.interpolation = mode
            if easing:
                kp.easing = easing

def visible(ob, f_on, f_off=10 ** 6):
    """Rendered from f_on to f_off (inclusive) only: constant keys on hide_render (and its children's)."""
    for o in [ob] + list(ob.children_recursive):
        for f, hide in ((0, True), (f_on, False), (f_off + 1, True)):
            if f < 0:
                continue
            o.hide_render = hide
            o.keyframe_insert("hide_render", frame=f)
        set_interp(o, "CONSTANT", paths=["hide_render"])
        o.hide_render = False

def visible_ranges(ob, ranges):
    """Rendered only inside the given (first, last) frame ranges."""
    for o in [ob] + list(ob.children_recursive):
        o.hide_render = True
        o.keyframe_insert("hide_render", frame=0)
        for f_on, f_off in ranges:
            o.hide_render = False
            o.keyframe_insert("hide_render", frame=f_on)
            o.hide_render = True
            o.keyframe_insert("hide_render", frame=f_off + 1)
        set_interp(o, "CONSTANT", paths=["hide_render"])
        o.hide_render = False

def pop(ob, f0, dur=6, size=1.0, over=1.25, axes=(1, 1, 1)):
    """Scale from 0 through an overshoot to `size`."""
    z = tuple(0.0001 if a else size for a in axes)
    kf(ob, f0, scale=z)
    kf(ob, f0 + max(1, round(dur * 0.6)), scale=tuple(size * over if a else size for a in axes))
    kf(ob, f0 + dur, scale=(size, size, size))

def squash(ob, f, amount=0.25, dur=6, base=(1, 1, 1), axis_up=1):
    """A squash on landing at frame f (local Y is up for cards), then back to `base` with a little wobble."""
    def s(k):
        sx, sy, sz = base
        if axis_up == 1:
            return (sx * (1 + k), sy * (1 - k), sz)
        return (sx * (1 + k), sy, sz * (1 - k))
    kf(ob, f, scale=s(amount))
    kf(ob, f + max(1, dur // 3), scale=s(-amount * 0.45))
    kf(ob, f + dur, scale=s(0.0))

def path_keys(ob, f0, f1, fn, step=1, rot=None):
    """Keyframe ob.location = fn(t) for t in 0..1 over frames f0..f1 (linear between keys).
    `rot(t)` optionally gives rotation_euler."""
    n = max(1, f1 - f0)
    for f in range(f0, f1 + 1, step):
        t = (f - f0) / n
        ob.location = fn(t)
        ob.keyframe_insert("location", frame=f)
        if rot:
            ob.rotation_euler = rot(t)
            ob.keyframe_insert("rotation_euler", frame=f)
    set_interp(ob, "LINEAR", paths=["location", "rotation_euler"])

def ballistic(ob, f0, f1, p0, v0, g=(0, 0, -1.5), spin=(0, 0, 0), drag=0.0, floor=None, bounce=0.35, step=2, fps=30):
    """Fly from p0 at v0 (m/s) under a (slow-motion) gravity g, tumbling at `spin` rad/s, with air drag;
    bounce on z = floor if given. Hidden before f0. Keys every `step` frames, linear."""
    p, v, r = Vector(p0), Vector(v0), Vector(ob.rotation_euler[:])
    dt = 1 / fps
    visible(ob, f0)
    sp = Vector(spin)
    for f in range(f0, f1 + 1):
        if (f - f0) % step == 0 or f == f1:
            ob.location = p
            ob.rotation_euler = r[:]
            ob.keyframe_insert("location", frame=f)
            ob.keyframe_insert("rotation_euler", frame=f)
        v = v + Vector(g) * dt
        v = v * (1 - drag * dt)
        p = p + v * dt
        r = r + sp * dt
        if floor is not None and p.z < floor:
            p.z = floor
            v = Vector((v.x * 0.6, v.y * 0.6, -v.z * bounce))
            sp = sp * 0.5
    set_interp(ob, "LINEAR", paths=["location", "rotation_euler"])

def scatter(obs, f0, f1, centre, speed=0.6, up=0.4, spin=8.0, seed=1, g=(0, 0, -1.2), drag=0.8, floor=None, stagger=0):
    """Burst objects (already placed around `centre`) outward with ballistic motion."""
    rnd = random.Random(seed)
    for i, o in enumerate(obs):
        d = o.location - Vector(centre)
        d = d.normalized() if d.length > 1e-6 else Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 1)).normalized()
        v = d * speed * rnd.uniform(0.5, 1.3) + Vector((0, 0, up * speed * rnd.uniform(0.5, 1.2)))
        s = (rnd.uniform(-spin, spin), rnd.uniform(-spin, spin), rnd.uniform(-spin, spin))
        start = f0 + (rnd.randint(0, stagger) if stagger else 0)
        ballistic(o, start, f1, o.location.copy(), v, g, s, drag, floor)

def toy(name, file, height, loc=(0, 0, 0), anchor=None, emission=1.15, lit=0.2, shadow=True):
    """A cut-out character on a billboard: returns (pivot, card). Move the pivot (keyframes); squash,
    stretch and roll the card in its own plane (local X/Y scale, local Z rotation). bake_billboards()
    turns every pivot to face the camera on every frame, so the card never shows its edge."""
    pivot = bpy.data.objects.new(name + "Pivot", None)
    bpy.context.collection.objects.link(pivot)
    pivot.location = loc
    c = card(name, file, height, (0, 0, 0), rot=(0, 0, 0), emission=emission, lit=lit, shadow=shadow, anchor=anchor)
    c.parent = pivot
    c.location = (0, 0, 0)
    c.rotation_euler = (0, 0, 0)
    pivot["billboard"] = True
    return pivot, c

def bake_billboards(cam, f0, f1, extra=()):
    """Key, frame by frame, every billboard pivot so its +Z faces the camera with +Y up."""
    sc = bpy.context.scene
    pivots = [o for o in bpy.data.objects if o.get("billboard")] + list(extra)
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        cl = cam.matrix_world.translation
        for p in pivots:
            pl = p.matrix_world.translation
            q = (cl - pl).to_track_quat("Z", "Y")
            p.rotation_euler = q.to_euler()
            p.keyframe_insert("rotation_euler", frame=f)
    for p in pivots:
        set_interp(p, "LINEAR", paths=["rotation_euler"])

def ease(t, kind="inout"):
    t = max(0.0, min(1.0, t))
    if kind == "in":
        return t * t * t
    if kind == "out":
        return 1 - (1 - t) ** 3
    if kind == "back":  # overshoots then settles
        c = 1.9
        return 1 + (c + 1) * (t - 1) ** 3 + c * (t - 1) ** 2
    return t * t * (3 - 2 * t)

def camera_move(cam, keys, focus=None):
    """keys = [(frame, location, target[, roll])]; keyed with smooth interpolation. A whip is just two
    keys a few frames apart with a big change of target: the vector blur does the rest."""
    for k in keys:
        f, loc, tgt = k[0], Vector(k[1]), Vector(k[2])
        roll = k[3] if len(k) > 3 else 0.0
        cam.location = loc
        look_at(cam, tgt, roll)
        cam.keyframe_insert("location", frame=f)
        cam.keyframe_insert("rotation_euler", frame=f)
        if focus is not None:
            cam.data.dof.focus_distance = focus if not callable(focus) else focus(loc, tgt)
            cam.data.dof.keyframe_insert("focus_distance", frame=f)
    # quaternion-free euler keys can flip; keep them continuous
    ad = cam.animation_data
    if ad and ad.action:
        for i in range(3):
            fc = ad.action.fcurves.find("rotation_euler", index=i)
            if fc:
                prev = None
                for kp in fc.keyframe_points:
                    if prev is not None:
                        while kp.co[1] - prev > math.pi:
                            kp.co[1] -= 2 * math.pi
                        while kp.co[1] - prev < -math.pi:
                            kp.co[1] += 2 * math.pi
                    prev = kp.co[1]
                fc.update()

def key_value(socket, frames_values, mode="LINEAR"):
    """Keyframe a node socket's default_value: [(frame, value), ...]."""
    for f, v in frames_values:
        socket.default_value = v
        socket.keyframe_insert("default_value", frame=f)
    nt = socket.id_data
    set_interp(nt, mode)

def render_frames(out_dir, frames, prefix=""):
    """Render the listed local frames to out_dir/0001.png..., skipping frames already there."""
    import time
    sc = bpy.context.scene
    os.makedirs(out_dir, exist_ok=True)
    for f in frames:
        path = os.path.join(out_dir, f"{f:04d}.png")
        if os.path.exists(path):
            continue
        t = time.time()
        sc.frame_set(f)
        sc.render.filepath = path + ".tmp.png"
        bpy.ops.render.render(write_still=True)
        os.replace(path + ".tmp.png", path)
        print(f"FRAME {prefix}{f} {time.time() - t:.1f}s", flush=True)
