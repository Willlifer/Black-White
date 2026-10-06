"""Black | White base character rig, built from nothing.

    blender -b --factory-startup --python game/tools/blender/build_base_rig.py
    blender -b --factory-startup --python game/tools/blender/build_base_rig.py -- --no-sheet

Writes (never hand-edit these; change this script and rebuild):
    game/art/source/base_rig.blend     working file: deform rig + IK controls + fit proxy
    game/art/characters/base_rig.glb   runtime: body + deform bones + socket empties + test actions
    design/art/base_rig_sheet.png      proportion / turntable / stress sheet (Workbench)

Coordinates are Blender's (Z up, character faces -Y). The glTF exporter's
+Y-up conversion maps that to Godot's Y up, facing +Z. Character left = +X in
both. Units are metres-as-world-units; the figure is 2.20 tall, feet at 0.

Everything is deterministic: no randomness, fixed generation order. See
design/art/RIG.md for the why behind each number.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

# ----------------------------------------------------------------- paths
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
ROOT = os.path.dirname(GAME)
BLEND_OUT = os.path.join(GAME, "art", "source", "base_rig.blend")
GLB_OUT = os.path.join(GAME, "art", "characters", "base_rig.glb")
SHEET_OUT = os.path.join(ROOT, "design", "art", "base_rig_sheet.png")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

RIG_VERSION = 1  # bump when bone names, socket names or proportions change


def V(x, y, z):
    return Vector((x, y, z))


# ----------------------------------------------------------- proportions
# Read off the five reference panels: ~3.9 heads tall, head ~25% of height,
# neck+torso ~33%, legs ~42%; one line weight for limbs and torso; arms
# leave the spine a short neck-length under the chin and hang to the hip.
HEIGHT = 2.20
HEAD_C = V(0, 0, 1.92)
HEAD_R = V(0.31, 0.295, 0.28)          # x (width), y (depth), z (height): slightly squashed
PELVIS_Z = 0.92
SPINE_Z = 1.02
CHEST_Z = 1.22
NECK_Z = 1.50
HEAD_Z = 1.66                            # neck/head pivot, just above the chin (1.64)
SHOULDER_Z = 1.48
SHOULDER_X = 0.06                        # arms branch from the spine, not from a yoke
ARM_ABDUCT = 35.0                        # A-pose: degrees from vertical
UPPER_ARM = 0.36
FOREARM = 0.33
HAND = 0.085

# limb line radii (taper root -> tip)
R_TORSO = (0.046, 0.045, 0.045, 0.041, 0.040)   # pelvis, spine, chest, neck, head-joint
R_ARM = (0.040, 0.036, 0.031)                    # shoulder, elbow, wrist
R_LEG = (0.045, 0.040, 0.034)                    # hip, knee, ankle
BALL = 1.08                                      # joint ball radius / tube radius
R_HAND = 0.043
R_FOOT = (0.043, 0.065, 0.050)                   # nub radii x, y (length), z
R_PELVIS = 0.052

RADIAL = 10            # tube sides
BALL_SEG, BALL_RINGS = 10, 5
HEAD_SEG, HEAD_RINGS = 28, 12

INK = (0.0, 0.0, 0.0, 1.0)
SKIN = (1.0, 1.0, 1.0, 1.0)

FORWARD = V(0, -1, 0)
UP = V(0, 0, 1)


def arm_points(s):
    """s = +1 left, -1 right. Elbow sits a touch back, wrist a touch forward,
    so the arm has a readable bend direction for IK and for the eye."""
    a = math.radians(ARM_ABDUCT)
    sh = V(s * SHOULDER_X, 0, SHOULDER_Z)
    d1 = V(s * math.sin(a), 0.03, -math.cos(a)).normalized()
    el = sh + d1 * UPPER_ARM
    d2 = V(s * math.sin(a), -0.08, -math.cos(a)).normalized()
    wr = el + d2 * FOREARM
    tip = wr + d2 * HAND
    return sh, el, wr, tip


def leg_points(s):
    # Hips almost meet (author, 2026-10-04: "leg pivots closer together, in
    # true stick figure fashion"); the legs splay to an inverted V below.
    hip = V(s * 0.025, 0, PELVIS_Z)
    knee = V(s * 0.065, -0.015, 0.50)
    ankle = V(s * 0.10, 0.0, 0.055)
    toe = V(s * 0.10, -0.11, 0.03)
    return hip, knee, ankle, toe


SIDES = (("l", 1), ("r", -1))

# ----------------------------------------------------------------- bones
# (name, head, tail, parent, connected, roll_z_hint, deform)
# Roll convention: every bone's local Z points to the character's front
# (or up, for the forward-pointing foot), so +X rotation pitches a bone's tip
# forward on every bone, both sides: hip/shoulder/elbow flexion is +X, knee
# flexion is -X. Bones that point up (root, hips, spine...) get identity rest
# rotation in Godot.


def bone_table():
    t = [
        ("root", V(0, 0, 0), V(0, 0, 0.25), None, False, FORWARD, True),
        ("hips", V(0, 0, PELVIS_Z), V(0, 0, SPINE_Z), "root", False, FORWARD, True),
        ("spine", V(0, 0, SPINE_Z), V(0, 0, CHEST_Z), "hips", True, FORWARD, True),
        ("chest", V(0, 0, CHEST_Z), V(0, 0, NECK_Z), "spine", True, FORWARD, True),
        ("neck", V(0, 0, NECK_Z), V(0, 0, HEAD_Z), "chest", True, FORWARD, True),
        ("head", V(0, 0, HEAD_Z), V(0, 0, HEIGHT), "neck", True, FORWARD, True),
    ]
    for side, s in SIDES:
        sh, el, wr, tip = arm_points(s)
        hip, knee, ankle, toe = leg_points(s)
        t += [
            ("shoulder_" + side, V(s * 0.012, 0, SHOULDER_Z), sh, "chest", False, FORWARD, True),
            ("upper_arm_" + side, sh, el, "shoulder_" + side, True, FORWARD, True),
            ("forearm_" + side, el, wr, "upper_arm_" + side, True, FORWARD, True),
            ("hand_" + side, wr, tip, "forearm_" + side, True, FORWARD, True),
            ("thigh_" + side, hip, knee, "hips", False, FORWARD, True),
            ("shin_" + side, knee, ankle, "thigh_" + side, True, FORWARD, True),
            ("foot_" + side, ankle, toe, "shin_" + side, True, UP, True),
        ]
    # animator controls: .blend only, never exported
    for side, s in SIDES:
        sh, el, wr, tip = arm_points(s)
        hip, knee, ankle, toe = leg_points(s)
        t += [
            ("ik_foot_" + side, ankle, toe, "root", False, UP, False),
            ("pole_knee_" + side, knee + V(0, -0.45, 0), knee + V(0, -0.55, 0), "root", False, UP, False),
            ("ik_hand_" + side, wr, tip, "root", False, FORWARD, False),
            ("pole_elbow_" + side, el + V(0, 0.45, 0), el + V(0, 0.55, 0), "root", False, UP, False),
        ]
    return t


DEFORM_BONES = [b[0] for b in bone_table() if b[6]]

# socket empties: name -> (parent bone, Blender world position)
def socket_table():
    _, _, wr_r, tip_r = arm_points(-1)
    _, _, wr_l, tip_l = arm_points(1)
    return [
        ("socket_hair", "head", HEAD_C.copy()),
        ("socket_hat", "head", V(0, 0, HEIGHT)),
        ("socket_weapon_r", "hand_r", wr_r + (tip_r - wr_r).normalized() * 0.03),
        ("socket_offhand_l", "hand_l", wr_l + (tip_l - wr_l).normalized() * 0.03),
        ("socket_chest", "chest", V(0, 0, 1.36)),
        ("socket_back", "chest", V(0, 0.075, 1.36)),
    ]


# -------------------------------------------------------- mesh builders
class MeshBuilder:
    """Collects verts / faces / weights / material index / colour, then
    emits one Blender mesh. Pieces stay separate islands so each keeps its
    own smooth normals (the inverted hull pushes along those)."""

    def __init__(self):
        self.verts = []
        self.weights = []   # per vert: {bone: w}
        self.faces = []     # (indices, material index)
        self.colors = []

    def add_vert(self, co, w, color):
        self.verts.append(co.copy())
        tot = sum(w.values())
        self.weights.append({k: v / tot for k, v in w.items() if v > 1e-6})
        self.colors.append(color)
        return len(self.verts) - 1

    def ellipsoid(self, center, radii, w, mat, color, seg, rings, basis=None, front_stretch=1.0):
        """UV ellipsoid, poles along basis Z (default world Z)."""
        basis = basis or Matrix.Identity(3)
        top = self.add_vert(center + basis @ V(0, 0, radii.z), w, color)
        lat = []
        for i in range(1, rings):
            th = math.pi * i / rings
            row = []
            for j in range(seg):
                ph = 2 * math.pi * j / seg
                p = V(radii.x * math.sin(th) * math.cos(ph), radii.y * math.sin(th) * math.sin(ph), radii.z * math.cos(th))
                if p.y < 0:
                    p.y *= front_stretch
                row.append(self.add_vert(center + basis @ p, w, color))
            lat.append(row)
        bot = self.add_vert(center + basis @ V(0, 0, -radii.z), w, color)
        for j in range(seg):
            k = (j + 1) % seg
            self.faces.append(((top, lat[0][j], lat[0][k]), mat))
            self.faces.append(((bot, lat[-1][k], lat[-1][j]), mat))
        for i in range(len(lat) - 1):
            for j in range(seg):
                k = (j + 1) % seg
                self.faces.append(((lat[i][j], lat[i + 1][j], lat[i + 1][k], lat[i][k]), mat))

    def tube(self, rings, mat, color, radial=RADIAL):
        """rings: list of (center, tangent, radius, weights). Parallel
        transport keeps the ring frames from twisting. Both ends capped."""
        n = None
        loops = []
        for c, t, r, w in rings:
            if n is None:
                ref = FORWARD if abs(t.dot(FORWARD)) < 0.9 else V(1, 0, 0)
                n = (ref - t * ref.dot(t)).normalized()
            else:
                n = (n - t * n.dot(t)).normalized()
            b = t.cross(n)
            row = []
            for k in range(radial):
                a = 2 * math.pi * k / radial
                row.append(self.add_vert(c + (n * math.cos(a) + b * math.sin(a)) * r, w, color))
            loops.append(row)
        for i in range(len(loops) - 1):
            for k in range(radial):
                k2 = (k + 1) % radial
                self.faces.append(((loops[i][k], loops[i][k2], loops[i + 1][k2], loops[i + 1][k]), mat))
        for row, (c, t, r, w) in ((loops[0], rings[0]), (loops[-1], rings[-1])):
            ctr = self.add_vert(c, w, color)
            for k in range(radial):
                self.faces.append(((ctr, row[(k + 1) % radial], row[k]), mat))

    def build(self, name, materials):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], [f for f, _ in self.faces])
        for i, (_, m) in enumerate(self.faces):
            me.polygons[i].material_index = m
        for m in materials:
            me.materials.append(m)
        # consistent outward normals per island (mirrored sides flip winding)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = True
        col = me.color_attributes.new("Color", 'BYTE_COLOR', 'POINT')
        for i, c in enumerate(self.colors):
            col.data[i].color = c
        me.color_attributes.active_color = col
        me.color_attributes.render_color_index = 0
        me.update()
        return me


def chain_rings(points, radii, bones, start_bone=None, end_bone=None,
                blend=None, loops=5, extra_step=None, smooth=False):
    """Rings along a joint chain. points[i] -> points[i+1] belongs to bones[i].
    Around each pivot the weights blend over +-blend[i] (linear, so the 5
    loops read 0/.25/.5/.75/1). `extra_step` adds evenly spaced loops (fit
    proxy). `smooth` uses smoothstep falloff instead of linear."""
    nseg = len(bones)
    dirs = [(points[i + 1] - points[i]).normalized() for i in range(nseg)]
    lens = [(points[i + 1] - points[i]).length for i in range(nseg)]
    out = []

    def f(x):
        x = max(0.0, min(1.0, x))
        return x * x * (3 - 2 * x) if smooth else x

    for i in range(nseg):
        L = lens[i]
        b0 = blend[i]          # blend half-width at this segment's start pivot
        b1 = blend[i + 1]      # ... at its end pivot
        ds = {0.0}
        if loops >= 5:
            ds |= {b0 * 0.5, b0, L - b1, L - b1 * 0.5}
        else:
            ds |= {b0, L - b1}
        if extra_step:
            k = 1
            while k * extra_step < L:
                ds.add(k * extra_step)
                k += 1
        if i == nseg - 1:
            ds.add(L)
        ds = sorted(d for d in ds if 0 <= d <= L + 1e-9)
        clean = []
        for d in ds:
            if not clean or d - clean[-1] > 0.006:
                clean.append(d)
        for d in clean:
            if d >= L - 1e-9 and i < nseg - 1:
                continue
            c = points[i] + dirs[i] * d
            r = radii[i] + (radii[i + 1] - radii[i]) * (d / L)
            t = dirs[i]
            if d < 1e-9 and i > 0:
                t = (dirs[i - 1] + dirs[i]).normalized()
            w = {bones[i]: 1.0}
            prev = bones[i - 1] if i > 0 else start_bone
            nxt = bones[i + 1] if i < nseg - 1 else end_bone
            if prev and b0 > 0 and d < b0:
                wp = 0.5 * (1 - f(d / b0))
                w = {bones[i]: 1 - wp, prev: wp}
            if nxt and b1 > 0 and L - d < b1:
                wn = 0.5 * (1 - f((L - d) / b1))
                w = dict(w)
                w[bones[i]] = w.get(bones[i], 0) - wn
                w[nxt] = w.get(nxt, 0) + wn
            out.append((c, t, r, w))
    return out


def build_body(mat_ink, mat_skin):
    mb = MeshBuilder()
    INK_M, SKIN_M = 0, 1

    # torso line: pelvis -> spine -> chest -> neck -> (inside the head)
    tp = [V(0, 0, PELVIS_Z), V(0, 0, SPINE_Z), V(0, 0, CHEST_Z), V(0, 0, NECK_Z), V(0, 0, HEAD_Z), V(0, 0, 1.71)]
    tr = list(R_TORSO) + [R_TORSO[-1]]
    tb = ["hips", "spine", "chest", "neck", "head"]
    mb.tube(chain_rings(tp, tr, tb, blend=[0, 0.04, 0.04, 0.04, 0.04, 0], loops=3), INK_M, INK)
    mb.ellipsoid(V(0, 0, PELVIS_Z), V(R_PELVIS, R_PELVIS, R_PELVIS), {"hips": 1}, INK_M, INK, BALL_SEG, BALL_RINGS)

    for side, s in SIDES:
        sh, el, wr, tip = arm_points(s)
        hip, knee, ankle, toe = leg_points(s)
        ua, fa, hd = "upper_arm_" + side, "forearm_" + side, "hand_" + side
        th, sn, ft = "thigh_" + side, "shin_" + side, "foot_" + side
        # arm: one tapered tube shoulder -> wrist
        ra = R_ARM
        mb.tube(chain_rings([sh, el, wr], ra, [ua, fa], start_bone="shoulder_" + side, end_bone=hd,
                            blend=[ra[0] * 0.9, ra[1] * 0.9, ra[2] * 0.9]), INK_M, INK)
        mb.ellipsoid(sh, V(1, 1, 1) * ra[0] * BALL, {ua: 1}, INK_M, INK, BALL_SEG, BALL_RINGS)
        mb.ellipsoid(el, V(1, 1, 1) * ra[1] * BALL, {fa: 1}, INK_M, INK, BALL_SEG, BALL_RINGS)
        hand_c = wr + (tip - wr).normalized() * 0.03
        mb.ellipsoid(hand_c, V(1, 1, 1) * R_HAND, {hd: 1}, INK_M, INK, BALL_SEG, BALL_RINGS)
        # leg: one tapered tube hip -> ankle
        rl = R_LEG
        mb.tube(chain_rings([hip, knee, ankle], rl, [th, sn], start_bone="hips", end_bone=ft,
                            blend=[rl[0] * 0.9, rl[1] * 0.9, rl[2] * 0.9]), INK_M, INK)
        mb.ellipsoid(hip, V(1, 1, 1) * rl[0] * BALL, {th: 1}, INK_M, INK, BALL_SEG, BALL_RINGS)
        mb.ellipsoid(knee, V(1, 1, 1) * rl[1] * BALL, {sn: 1}, INK_M, INK, BALL_SEG, BALL_RINGS)
        foot_c = V(ankle.x, -0.025, R_FOOT[2])
        mb.ellipsoid(foot_c, V(*R_FOOT), {ft: 1}, INK_M, INK, BALL_SEG, BALL_RINGS)

    # the head: big, white, blank
    mb.ellipsoid(HEAD_C, HEAD_R, {"head": 1}, SKIN_M, SKIN, HEAD_SEG, HEAD_RINGS)
    return mb.build("body", [mat_ink, mat_skin]), mb


def build_fit(mat_fit):
    """Clothing fit proxy (.blend only). A slim torso volume plus limb
    sleeves, weighted with LONG smoothstep falloffs. Clothing is fitted
    against it and gets its weights by Data Transfer from it, so cloth bends
    in soft arcs while the ink body keeps its ball joints."""
    mb = MeshBuilder()
    grey = (0.6, 0.6, 0.6, 1)
    # torso volume: elliptical, built ring by ring with z-driven weights
    zs = [0.80 + 0.03 * i for i in range(25)]   # 0.80 .. 1.52
    prof = [(0.80, 0.075, 0.055), (0.88, 0.100, 0.068), (0.98, 0.095, 0.066), (1.10, 0.085, 0.060),
            (1.25, 0.098, 0.064), (1.40, 0.105, 0.066), (1.52, 0.080, 0.055)]

    def lerp_prof(z):
        for (z0, a0, b0), (z1, a1, b1) in zip(prof, prof[1:]):
            if z0 <= z <= z1:
                u = (z - z0) / (z1 - z0)
                return a0 + (a1 - a0) * u, b0 + (b1 - b0) * u
        return prof[-1][1], prof[-1][2]

    def ss(e0, e1, x):
        x = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
        return x * x * (3 - 2 * x)

    def torso_w(p):
        z = p.z
        w = {}
        # spine chain, smooth over +-0.08 around each pivot
        chain = [("hips", -1, SPINE_Z), ("spine", SPINE_Z, CHEST_Z), ("chest", CHEST_Z, NECK_Z), ("neck", NECK_Z, 9)]
        for name, z0, z1 in chain:
            lo = ss(z0 - 0.08, z0 + 0.08, z) if z0 > 0 else 1
            hi = 1 - ss(z1 - 0.08, z1 + 0.08, z) if z1 < 9 else 1
            if lo * hi > 0:
                w[name] = lo * hi
        # crotch: hand weight down to the thighs by side
        leg = 1 - ss(0.80, 0.97, z)
        if leg > 0 and abs(p.x) > 0.005:
            side = "l" if p.x > 0 else "r"
            k = leg * ss(0.0, 0.06, abs(p.x))
            w = {n: v * (1 - k) for n, v in w.items()}
            w["thigh_" + side] = k
        # shoulder line: outer top edge follows the shoulders
        sh = ss(1.38, 1.50, z) * ss(0.05, 0.10, abs(p.x))
        if sh > 0:
            side = "l" if p.x > 0 else "r"
            w = {n: v * (1 - sh) for n, v in w.items()}
            w["shoulder_" + side] = sh
        return w

    loops = []
    for z in zs:
        a, b = lerp_prof(z)
        row = []
        for k in range(16):
            ang = 2 * math.pi * k / 16
            p = V(a * math.cos(ang), b * math.sin(ang), z)
            row.append(mb.add_vert(p, torso_w(p), grey))
        loops.append(row)
    for i in range(len(loops) - 1):
        for k in range(16):
            k2 = (k + 1) % 16
            mb.faces.append(((loops[i][k], loops[i][k2], loops[i + 1][k2], loops[i + 1][k]), 0))
    for row, z in ((loops[0], zs[0]), (loops[-1], zs[-1])):
        c = mb.add_vert(V(0, 0, z), torso_w(V(0, 0, z)), grey)
        for k in range(16):
            mb.faces.append(((c, row[(k + 1) % 16], row[k]), 0))

    for side, s in SIDES:
        sh, el, wr, tip = arm_points(s)
        hip, knee, ankle, toe = leg_points(s)
        mb.tube(chain_rings([sh, el, wr], (0.062, 0.058, 0.05),
                            ["upper_arm_" + side, "forearm_" + side], start_bone="shoulder_" + side,
                            end_bone="hand_" + side, blend=[0.07, 0.11, 0.05], loops=5,
                            extra_step=0.04, smooth=True), 0, grey, radial=12)
        mb.tube(chain_rings([hip, knee, ankle], (0.075, 0.064, 0.052),
                            ["thigh_" + side, "shin_" + side], start_bone="hips",
                            end_bone="foot_" + side, blend=[0.08, 0.12, 0.06], loops=5,
                            extra_step=0.04, smooth=True), 0, grey, radial=12)
    return mb.build("fit_body", [mat_fit]), mb


# ------------------------------------------------------------- materials
def make_material(name, rgba, viewport=None):
    m = bpy.data.materials.new(name)
    m.diffuse_color = viewport or rgba
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")       # unlit, like the game
    em.inputs["Color"].default_value = rgba
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


# ------------------------------------------------------------------ rig
def build_armature():
    arm = bpy.data.armatures.new("base_rig_armature")
    arm.display_type = 'OCTAHEDRAL'
    obj = bpy.data.objects.new("base_rig", arm)
    obj.show_in_front = True
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    for name, head, tail, parent, conn, zhint, deform in bone_table():
        b = eb.new(name)
        b.head, b.tail = head, tail
        b.align_roll(zhint)
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
            b.use_connect = conn
    bpy.ops.object.mode_set(mode='OBJECT')
    col_def = arm.collections.new("Deform")
    col_ik = arm.collections.new("IK")
    for b in arm.bones:
        (col_def if b.use_deform else col_ik).assign(b)
        b.inherit_scale = 'FULL'
    return obj


def add_prop(obj, key, val, desc):
    obj[key] = float(val)
    obj.id_properties_ui(key).update(min=0.0, max=1.0, soft_min=0.0, soft_max=1.0, description=desc)


def drive(con, obj, key):
    fc = con.driver_add("influence")
    d = fc.driver
    d.type = 'AVERAGE'
    var = d.variables.new()
    var.name = "v"
    var.type = 'SINGLE_PROP'
    var.targets[0].id_type = 'OBJECT'
    var.targets[0].id = obj
    var.targets[0].data_path = '["%s"]' % key


def make_widgets():
    coll = bpy.data.collections.new("widgets")
    bpy.context.scene.collection.children.link(coll)

    def wire(name, pts, edges):
        me = bpy.data.meshes.new(name)
        me.from_pydata(pts, edges, [])
        o = bpy.data.objects.new(name, me)
        coll.objects.link(o)
        return o

    n = 24
    circ = [(math.cos(2 * math.pi * i / n) * 0.5, 0, math.sin(2 * math.pi * i / n) * 0.5) for i in range(n)]
    circle = wire("WGT_circle", circ, [(i, (i + 1) % n) for i in range(n)])
    dia = [(0.5, 0, 0), (0, 0.5, 0), (-0.5, 0, 0), (0, -0.5, 0), (0, 0, 0.5), (0, 0, -0.5)]
    diamond = wire("WGT_diamond", dia, [(0, 1), (1, 2), (2, 3), (3, 0), (0, 4), (1, 4), (2, 4), (3, 4),
                                       (0, 5), (1, 5), (2, 5), (3, 5)])
    bpy.context.view_layer.layer_collection.children["widgets"].exclude = True
    return circle, diamond


def solve_pole_angle(obj, con, chain, key):
    """Find the pole angle at which the IK chain reproduces the rest pose."""
    obj[key] = 1.0
    vl = bpy.context.view_layer
    con.pole_angle = 0.0
    vl.update()

    def err():
        vl.update()
        e = 0.0
        for b in chain:
            m = obj.pose.bones[b].matrix
            r = obj.data.bones[b].matrix_local
            e += (m.col[0].xyz - r.col[0].xyz).length + (m.col[2].xyz - r.col[2].xyz).length
            e += (m.col[3].xyz - r.col[3].xyz).length * 10
        return e

    best = (1e9, 0.0)
    for deg in range(-180, 180, 2):
        con.pole_angle = math.radians(deg)
        best = min(best, (err(), float(deg)))
    lo = best[1]
    for k in range(-20, 21):
        deg = lo + k * 0.1
        con.pole_angle = math.radians(deg)
        best = min(best, (err(), deg))
    con.pole_angle = math.radians(best[1])
    vl.update()
    return best


def setup_ik(obj):
    circle, diamond = make_widgets()
    pb = obj.pose.bones
    for name in pb.keys():
        b = pb[name]
        b.rotation_mode = 'QUATERNION'
        if name.startswith("ik_"):
            b.custom_shape = circle
            b.custom_shape_scale_xyz = (1.6, 1.6, 1.6)
        elif name.startswith("pole_"):
            b.custom_shape = diamond
            b.custom_shape_scale_xyz = (1.2, 1.2, 1.2)
    report = {}
    for side, _ in SIDES:
        add_prop(obj, "ik_leg_" + side, 1.0, "IK/FK blend for the %s leg (1 = IK)" % side)
        add_prop(obj, "ik_arm_" + side, 0.0, "IK/FK blend for the %s arm (1 = IK)" % side)
        for limb, mid, tipb, tgt, pole, key in (
                ("leg", "shin_", "foot_", "ik_foot_", "pole_knee_", "ik_leg_"),
                ("arm", "forearm_", "hand_", "ik_hand_", "pole_elbow_", "ik_arm_")):
            c = pb[mid + side].constraints.new('IK')
            c.name = "IK"
            c.target = obj
            c.subtarget = tgt + side
            c.pole_target = obj
            c.pole_subtarget = pole + side
            c.chain_count = 2
            c.use_tail = True
            r = pb[tipb + side].constraints.new('COPY_ROTATION')
            r.name = "IK rotation"
            r.target = obj
            r.subtarget = tgt + side
            r.target_space = 'WORLD'
            r.owner_space = 'WORLD'
            drive(c, obj, key + side)
            drive(r, obj, key + side)
            chain = [("thigh_" if limb == "leg" else "upper_arm_") + side, mid + side]
            report[key + side] = solve_pole_angle(obj, c, chain, key + side)
        obj["ik_arm_" + side] = 0.0
    bpy.context.view_layer.update()
    return report


def bind(mesh_obj, rig, mb):
    for name in DEFORM_BONES:
        mesh_obj.vertex_groups.new(name=name)
    for i, w in enumerate(mb.weights):
        for bone, val in w.items():
            mesh_obj.vertex_groups[bone].add([i], val, 'REPLACE')
    mod = mesh_obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    mod.use_deform_preserve_volume = False   # Godot is linear-blend; match it
    mesh_obj.parent = rig


# ---------------------------------------------------------------- poses
def q(rx, ry, rz):
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_quaternion()


def mirror(pose):
    """Keys ending _l are mirrored onto _r (x kept, y/z negated) unless the
    _r key is given explicitly."""
    out = dict(pose)
    for k, v in pose.items():
        if k.endswith("_l"):
            r = k[:-2] + "_r"
            if r not in pose:
                out[r] = (v[0], -v[1], -v[2])
    return out


POSE_IDLE_A = mirror({
    "upper_arm_l": (4, 0, -23), "forearm_l": (14, 0, 0), "hand_l": (6, 0, 0),
    "spine": (1, 0, 0), "chest": (1, 0, 0), "head": (-2, 0, 0),
})
POSE_IDLE_B = mirror({
    "upper_arm_l": (2, 0, -21), "forearm_l": (17, 0, 0), "hand_l": (8, 0, 0),
    "spine": (2, 0, 0), "chest": (-1.5, 0, 0), "neck": (1, 0, 0), "head": (-3, 0, 0),
})
# elbows and knees at 120 degrees, hips flexed past 90, spine twisted: the
# joint stress test. Asymmetric on purpose.
POSE_STRESS = {
    "upper_arm_l": (80, 0, -10), "forearm_l": (120, 0, 0), "hand_l": (30, 0, 0),
    "upper_arm_r": (-20, 0, -60), "forearm_r": (120, 0, 0), "hand_r": (-20, 0, 0),
    "thigh_l": (100, 0, 0), "shin_l": (-120, 0, 0), "foot_l": (25, 0, 0),
    "thigh_r": (-25, 0, 0), "shin_r": (-120, 0, 0), "foot_r": (-10, 0, 0),
    "spine": (8, 12, 0), "chest": (10, 12, 0), "neck": (-8, 0, 0), "head": (6, 0, 10),
}


def apply_pose(obj, pose):
    for pb in obj.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    for name, rot in pose.items():
        obj.pose.bones[name].rotation_quaternion = q(*rot)


def key_pose(obj, pose, frame, props):
    apply_pose(obj, pose)
    for k, v in props.items():
        obj[k] = v
        obj.keyframe_insert('["%s"]' % k, frame=frame)
    for name in DEFORM_BONES:
        pb = obj.pose.bones[name]
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=name)


def make_actions(obj):
    obj.animation_data_create()
    acts = []
    specs = [
        # idle: 2 s breathing loop, legs on IK so feet stay planted
        ("rig_idle", [(0, POSE_IDLE_A), (24, POSE_IDLE_B), (48, POSE_IDLE_A)], 0, 48, 1.0),
        # stress: rest -> stress pose over 1.5 s, hold. FK legs.
        ("rig_stress", [(0, {}), (36, POSE_STRESS), (48, POSE_STRESS)], 0, 48, 0.0),
    ]
    for name, keys, f0, f1, ik in specs:
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        obj.animation_data.action = act
        props = {"ik_leg_l": ik, "ik_leg_r": ik, "ik_arm_l": 0.0, "ik_arm_r": 0.0}
        for f, pose in keys:
            key_pose(obj, pose, f, props)
        act.use_frame_range = True
        act.frame_start, act.frame_end = f0, f1
        act.use_cyclic = name == "rig_idle"
        track = obj.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, f0, act)
        strip.name = name
        track.mute = True
        obj.animation_data.action = None
        acts.append(act)
    apply_pose(obj, {})
    for side, _ in SIDES:
        obj["ik_leg_" + side] = 1.0
        obj["ik_arm_" + side] = 0.0
    return acts


# ------------------------------------------------------------- sockets
def make_sockets(rig, coll):
    out = []
    vl = bpy.context.view_layer
    for name, bone, pos in socket_table():
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = 'ARROWS'
        e.empty_display_size = 0.08
        coll.objects.link(e)
        e.parent = rig
        e.parent_type = 'BONE'
        e.parent_bone = bone
        vl.update()
        e.matrix_world = Matrix.Translation(pos)   # world-aligned at rest
        out.append(e)
    vl.update()
    return out


# ------------------------------------------------------------- checks
def stats(body, rig):
    me = body.data
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    zs = [v.co.z for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    return {"tris": tris, "verts": len(me.vertices), "min_z": min(zs), "max_z": max(zs),
            "min_y": min(ys), "max_y": max(ys)}


# ---------------------------------------------------------------- sheet
def render_sheet(rig, body, fit):
    """One orthographic Workbench render: front, 3/4, side, back (rest),
    relaxed idle, and the 120-degree stress pose, with height guides. Inverted
    hull outlines via a flipped Solidify + backface culling, the same idea
    as the game shader (white around ink, black around skin)."""
    scn = bpy.context.scene
    for side, _ in SIDES:
        rig["ik_leg_" + side] = 0.0
        rig["ik_arm_" + side] = 0.0
    fit.hide_render = True
    fit.hide_viewport = True
    ol_ink = make_material("sheet_outline_ink", (1, 1, 1, 1))
    ol_skin = make_material("sheet_outline_skin", (0, 0, 0, 1))
    guide = make_material("sheet_guide", (0.35, 0.35, 0.35, 1))
    label = make_material("sheet_label", (0.05, 0.05, 0.05, 1))
    coll = bpy.data.collections.new("sheet")
    scn.collection.children.link(coll)

    figures = [("front", 0, {}), ("3/4", -40, {}), ("side", -90, {}), ("back", 180, {}),
               ("idle", -20, POSE_IDLE_A), ("stress 120°", -35, POSE_STRESS)]
    gap = 1.35
    x0 = -gap * (len(figures) - 1) / 2
    body.hide_render = True
    rig.hide_render = True
    for i, (lab, yaw, pose) in enumerate(figures):
        r = rig.copy()
        r.animation_data_clear() if r.animation_data else None
        coll.objects.link(r)
        r.location = (x0 + gap * i, 0, 0)
        r.rotation_euler = (0, 0, math.radians(yaw))
        r.hide_render = True
        b = body.copy()
        coll.objects.link(b)
        b.parent = r
        b.matrix_parent_inverse = Matrix.Identity(4)
        b.location = (0, 0, 0)
        b.hide_render = False
        b.modifiers["Armature"].object = r
        b.data = body.data.copy()
        b.data.materials.append(ol_ink)
        b.data.materials.append(ol_skin)
        sol = b.modifiers.new("hull", 'SOLIDIFY')
        sol.thickness = 0.022
        sol.offset = 1.0
        sol.use_flip_normals = True
        sol.use_rim = False
        sol.material_offset = 2
        bpy.context.view_layer.update()
        apply_pose(r, pose)
        t = bpy.data.curves.new("lab_%d" % i, 'FONT')
        t.body = lab
        t.size = 0.11
        t.align_x = 'CENTER'
        to = bpy.data.objects.new("lab_%d" % i, t)
        to.data.materials.append(label)
        to.location = (x0 + gap * i, 0, -0.22)
        to.rotation_euler = (math.radians(90), 0, 0)
        coll.objects.link(to)

    width = gap * len(figures) + 0.9
    for z, txt in ((0.0, "0.00 floor"), (PELVIS_Z, "%.2f hip" % PELVIS_Z), (SHOULDER_Z, "%.2f shoulder" % SHOULDER_Z),
                   (1.64, "1.64 chin"), (HEAD_C.z, "%.2f head centre" % HEAD_C.z), (HEIGHT, "%.2f top" % HEIGHT)):
        bpy.ops.mesh.primitive_plane_add(size=1, location=(0.25, 0.6, z))
        p = bpy.context.active_object
        p.scale = (width, 0.004, 1)
        p.rotation_euler = (math.radians(90), 0, 0)
        p.data.materials.append(guide)
        for c in p.users_collection:
            c.objects.unlink(p)
        coll.objects.link(p)
        t = bpy.data.curves.new("g_" + txt, 'FONT')
        t.body = txt
        t.size = 0.075
        t.align_x = 'RIGHT'
        to = bpy.data.objects.new("g_" + txt, t)
        to.data.materials.append(label)
        to.location = (x0 - 0.62, 0.5, z + 0.012)
        to.rotation_euler = (math.radians(90), 0, 0)
        coll.objects.link(to)
    t = bpy.data.curves.new("title", 'FONT')
    t.body = "Black | White  base rig v%d   %.2f u tall   rest = A-pose %d°   grey bg so both contours show" % (RIG_VERSION, HEIGHT, ARM_ABDUCT)
    t.size = 0.085
    t.align_x = 'LEFT'
    to = bpy.data.objects.new("title", t)
    to.data.materials.append(label)
    to.location = (x0 - 1.3, 0.5, HEIGHT + 0.22)
    to.rotation_euler = (math.radians(90), 0, 0)
    coll.objects.link(to)

    cam_d = bpy.data.cameras.new("sheet_cam")
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = width + 1.2
    cam = bpy.data.objects.new("sheet_cam", cam_d)
    coll.objects.link(cam)
    cam.location = (0.25, -10, HEIGHT / 2 + 0.05)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scn.camera = cam

    scn.render.engine = 'BLENDER_WORKBENCH'
    sh = scn.display.shading
    sh.light = 'FLAT'
    sh.color_type = 'MATERIAL'
    sh.show_backface_culling = True
    sh.show_object_outline = False
    sh.show_cavity = False
    sh.show_shadows = False
    scn.world = scn.world or bpy.data.worlds.new("World")
    scn.world.color = (0.62, 0.62, 0.62)
    scn.render.film_transparent = False
    scn.render.resolution_x = 3000
    scn.render.resolution_y = int(3000 * (HEIGHT + 0.75) / (width + 1.2))
    scn.render.resolution_percentage = 100
    scn.display.render_aa = '8'
    scn.view_settings.view_transform = 'Standard'
    scn.render.image_settings.file_format = 'PNG'
    scn.render.filepath = SHEET_OUT
    os.makedirs(os.path.dirname(SHEET_OUT), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("SHEET", SHEET_OUT)
    render_stress_closeups(coll, cam, x0 + gap * (len(figures) - 1))


def render_stress_closeups(coll, cam, stress_x):
    """Joint close-ups of the stress figure from four sides, stitched into
    one strip: this is where gaps or creases at 120 degrees would show."""
    import numpy as np
    scn = bpy.context.scene
    stress_rig = [o for o in coll.objects if o.type == 'ARMATURE'][-1]
    for o in coll.objects:
        if o.type == 'FONT' or o.type == 'MESH' and o.parent is None:
            o.hide_render = True
    scn.render.resolution_x = 900
    scn.render.resolution_y = 1100
    cam.data.ortho_scale = 1.75
    out = os.path.join(os.path.dirname(SHEET_OUT), "base_rig_stress.png")
    tiles = []
    for k, yaw in enumerate((0, 90, 180, 270)):
        stress_rig.rotation_euler = (0, 0, math.radians(yaw - 35))
        a = math.radians(0)
        cam.location = (stress_x, -10, 1.35)
        tmp = os.path.join(bpy.app.tempdir, "stress_%d.png" % k)
        scn.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
        tiles.append(px)
        bpy.data.images.remove(img)
    strip = np.concatenate(tiles, axis=1)
    h, w = strip.shape[:2]
    im = bpy.data.images.new("stress_strip", w, h, alpha=True)
    im.pixels[:] = strip.ravel()
    im.filepath_raw = out
    im.file_format = 'PNG'
    im.save()
    print("STRESS", out)


# ----------------------------------------------------------------- main
def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scn = bpy.context.scene
    scn.render.fps = 24
    scn.frame_start, scn.frame_end = 0, 48
    scn.unit_settings.system = 'METRIC'

    mat_ink = make_material("ink", INK, (0.02, 0.02, 0.02, 1))
    mat_skin = make_material("skin", SKIN)
    mat_fit = make_material("fit", (0.5, 0.5, 0.5, 1), (0.55, 0.6, 0.7, 0.35))

    rig = build_armature()
    me, mb = build_body(mat_ink, mat_skin)
    body = bpy.data.objects.new("body", me)
    scn.collection.objects.link(body)
    bind(body, rig, mb)

    fit_coll = bpy.data.collections.new("fit")
    scn.collection.children.link(fit_coll)
    fme, fmb = build_fit(mat_fit)
    fit = bpy.data.objects.new("fit_body", fme)
    fit_coll.objects.link(fit)
    bind(fit, rig, fmb)
    fit.display_type = 'WIRE'
    fit.hide_render = True
    fit["note"] = "Clothing fit + weight source. Data Transfer weights from here. Not exported."

    sockets = make_sockets(rig, scn.collection)
    poles = setup_ik(rig)
    make_actions(rig)
    rig["rig_version"] = RIG_VERSION
    bpy.context.view_layer.update()

    st = stats(body, rig)
    print("STATS", st)
    print("POLES", {k: round(v[1], 1) for k, v in poles.items()}, "err", {k: round(v[0], 5) for k, v in poles.items()})

    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    os.makedirs(os.path.dirname(GLB_OUT), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=False)

    # export: body + deform bones + sockets + baked actions
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in [rig, body] + sockets:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=GLB_OUT, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
        export_materials='EXPORT', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_skins=True, export_def_bones=True, export_leaf_bone=False, export_influence_nb=4,
        export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True,
        export_anim_slide_to_zero=True, export_reset_pose_bones=True, export_rest_position_armature=True,
        export_morph=False, export_cameras=False, export_lights=False, export_extras=False,
    )
    print("GLB", GLB_OUT)
    print("BLEND", BLEND_OUT)

    if "--no-sheet" not in ARGS:
        render_sheet(rig, body, fit)


main()
