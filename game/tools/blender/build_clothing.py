"""Black | White clothing lane: 14 parametric garments on the base rig.

    blender -b --factory-startup --python game/tools/blender/build_clothing.py
    blender -b --factory-startup --python game/tools/blender/build_clothing.py -- --only hoodie,shorts
    blender -b --factory-startup --python game/tools/blender/build_clothing.py -- --no-check

Reads   game/art/source/base_rig.blend    (rig + fit_body proxy; never written)
Writes  game/art/clothing/<id>.glb         one skinned garment each, 20 rig bones
        game/art/clothing/clothing_palette.png   3x3 palette (fill / fold / contour per shade)
        game/art/source/clothing.blend     working file: rig + fit + every garment

Every garment is a parametric shell around the fit_body proxy: its radii are
MEASURED from fit_body at build time and grown by named parameters (offset,
hem/length, flare, bag, splay, ...). Weights are copied from fit_body
(nearest-face interpolated, per body part), then cleaned (allowed bones per
part, hinge re-profiling at knees / elbows / hips, 4 influences). The build
then poses the rig and measures coverage: every ink-limb contour point that
the garment covers at rest must stay covered in every test pose. It prints
CLIP lines and exits non-zero if anything is exposed (unless --no-check).

Deterministic: no randomness, fixed ordering. See design/art/CLOTHING.md.
"""

import math
import os
import struct
import sys
import zlib

import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
RIG_BLEND = os.path.join(GAME, "art", "source", "base_rig.blend")
OUT_DIR = os.path.join(GAME, "art", "clothing")
BLEND_OUT = os.path.join(GAME, "art", "source", "clothing.blend")
PALETTE_OUT = os.path.join(OUT_DIR, "clothing_palette.png")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = None
if "--only" in ARGS:
    ONLY = ARGS[ARGS.index("--only") + 1].split(",")

CLOTHING_VERSION = 1
RIG_VERSION_EXPECTED = 1

# --------------------------------------------------------------- shading
# Vertex colour channels (FLOAT_COLOR, corner domain):
#   R = 1.0 fill (palette row 0), 0.5 fold/seam line (row 1), 0.0 ink (black)
#   G = 1.0 gets the inverted-hull contour, 0.0 none (decals, strings)
FILL, FOLD, INK = 1.0, 0.5, 0.0

# 3-step palette, sRGB 0-255. Fill matches BWLook.GREY_DARK/MID/LIGHT.
# Contour rule (D42 extended): fill luminance < 0.5 -> white contour, else black.
SHADES = ("dark", "mid", "light")
PALETTE_FILL = (71, 140, 209)      # 0.28 0.55 0.82
PALETTE_FOLD = (31, 84, 148)       # 0.12 0.33 0.58
HULL = 0.018                       # ink contour width on the body (RIG.md); coverage target


def contour_for(v255):
    return 255 if v255 / 255.0 < 0.5 else 0


def write_palette(path):
    rows = [PALETTE_FILL, PALETTE_FOLD, tuple(contour_for(v) for v in PALETTE_FILL)]
    raw = b"".join(b"\x00" + bytes(sum(([v, v, v, 255] for v in row), [])) for row in rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 3, 3, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def V(x, y, z):
    return Vector((x, y, z))


def ss(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


SIDES = (("l", 1), ("r", -1))
TORSO_BONES = ["hips", "spine", "chest", "neck", "shoulder_l", "shoulder_r"]

# ============================================================ garments
# Lengths along a limb are chain distance `s` from the joint at the top
# (hip or shoulder). Leg: knee at s=0.42, ankle at 0.865. Arm: elbow at 0.36,
# wrist at 0.69. Torso heights are world z (hip 0.92, chest 1.22, shoulder 1.48).
#
# Bottoms
#   waist      z of the waistband top
#   offset     cloth clearance over fit_body everywhere (u)
#   hem        s of the leg hem
#   bag        extra radius at s=bag_at (gaussian, width bag_w): bagginess
#   flare      extra radius at the hem, ramping from the knee/crotch
#   splay      the cloth leg axis leans outward by splay*s/hem (shorts read as two legs)
#   cuff       length of an elastic ankle cuff (0 = none); cuff_r its clearance
#   band       waistband height (fold line under it)
#   inseam     medial clearance over the ink contour (keeps the crotch tight)
#   slant      how much higher the hem sits on the inner side of the leg (shorts)
#   seat       extra clearance round the hip balls (z 0.83-0.95), fading out by
#              s=0.25 down the leg: the seat folds hardest in hip flexion
BOTTOMS = {
    "baggy_sweatpants": dict(waist=1.00, offset=0.016, hem=0.80, bag=0.050, bag_at=0.58, bag_w=0.22,
                             flare=0.0, splay=0.035, cuff=0.045, cuff_r=0.012, band=0.04, drawstring=True,
                             inseam=0.012),
    "sweatpants": dict(waist=1.00, offset=0.012, hem=0.80, bag=0.022, bag_at=0.62, bag_w=0.16,
                       flare=0.0, splay=0.015, cuff=0.040, cuff_r=0.010, band=0.035, drawstring=True,
                       inseam=0.010),
    "tight_pants": dict(waist=0.99, offset=0.008, hem=0.81, bag=0.0, bag_at=0.5, bag_w=0.2,
                        flare=0.006, splay=0.0, cuff=0.0, cuff_r=0.0, band=0.022, drawstring=False,
                        inseam=0.007, seat=0.014),
    "ripped_tight_pants": dict(waist=0.99, offset=0.008, hem=0.81, bag=0.0, bag_at=0.5, bag_w=0.2,
                               flare=0.006, splay=0.0, cuff=0.0, cuff_r=0.0, band=0.022, drawstring=False,
                               inseam=0.007, seat=0.014, rips=True),
    "tight_shorts": dict(waist=0.99, offset=0.008, hem=0.25, bag=0.0, bag_at=0.2, bag_w=0.2,
                         flare=0.004, splay=0.01, cuff=0.0, cuff_r=0.0, band=0.022, drawstring=False,
                         inseam=0.007, seat=0.014, hem_line=True, slant=0.05),
    "shorts": dict(waist=1.00, offset=0.020, hem=0.36, bag=0.0, bag_at=0.2, bag_w=0.2,
                   flare=0.010, splay=0.022, cuff=0.0, cuff_r=0.0, band=0.03, drawstring=False,
                   inseam=0.010, hem_line=True, slant=0.13),
    "short_shorts": dict(waist=0.99, offset=0.012, hem=0.17, bag=0.0, bag_at=0.1, bag_w=0.2,
                         flare=0.006, splay=0.012, cuff=0.0, cuff_r=0.0, band=0.022, drawstring=False,
                         inseam=0.008, hem_line=True, slant=0.045),
}

# Tops
#   hem        z of the bottom edge
#   offset     torso clearance over fit_body; flare = extra at the hem; bag = extra mid-torso
#   sleeve     sleeve length s (None = sleeveless); s_off / s_flare / s_bag as for the torso
#   cuff       cuff length at the sleeve end (long sleeves), hem_band ribbed hem height
#   neck       neck opening radius; collar = fold band height around it
#   hood / pocket / strings / scarf / straps: extra parts
TOPS = {
    "tank_top": dict(hem=0.94, offset=0.020, flare=0.016, bag=0.0, sleeve=None, straps=True,
                     neck=None, collar=0.0, hem_band=0.0),
    "crop_top": dict(hem=1.20, offset=0.020, flare=0.006, bag=0.0, sleeve=0.075, s_off=0.012, s_flare=0.010,
                     s_bag=0.0, cuff=0.0, neck=0.092, collar=0.0, hem_band=0.0),
    "tshirt": dict(hem=0.93, offset=0.024, flare=0.016, bag=0.004, sleeve=0.17, s_off=0.016, s_flare=0.018,
                   s_bag=0.0, cuff=0.0, neck=0.072, collar=0.012, hem_band=0.0),
    "sweater": dict(hem=0.92, offset=0.030, flare=0.004, bag=0.010, sleeve=0.675, s_off=0.016, s_flare=0.0,
                    s_bag=0.010, cuff=0.045, neck=0.072, collar=0.022, hem_band=0.05),
    "sweater_scarf": dict(hem=0.92, offset=0.030, flare=0.004, bag=0.010, sleeve=0.675, s_off=0.016,
                          s_flare=0.0, s_bag=0.010, cuff=0.045, neck=0.072, collar=0.022, hem_band=0.05,
                          scarf=True),
    "hoodie": dict(hem=0.90, offset=0.036, flare=0.006, bag=0.016, sleeve=0.675, s_off=0.020, s_flare=0.0,
                   s_bag=0.014, cuff=0.045, neck=0.078, collar=0.0, hem_band=0.05, hood=True, pocket=True,
                   strings=True),
    "crop_hoodie": dict(hem=1.19, offset=0.034, flare=0.004, bag=0.010, sleeve=0.675, s_off=0.020,
                        s_flare=0.0, s_bag=0.012, cuff=0.045, neck=0.078, collar=0.0, hem_band=0.04,
                        hood=True, pocket=False, strings=True),
}
ALL_IDS = list(BOTTOMS) + list(TOPS)

# Hinge re-profiling (weights cleanup). Linear-blend skinning collapses a
# 50/50 ring to cos(theta/2) of its radius around the pivot (0.5 at 120 deg).
# Shifting the outer side's transition `c` down the child bone keeps the
# stretched side outside the joint ball; the inner side blends at the pivot.
# (child, parent, inner side as the child's local axis, c_outer, c_other, half width)
HINGES = [
    ("shin", "thigh", "-z", 0.105, 0.0, 0.05),       # knee flexes back: front is outer
    ("forearm", "upper_arm", "+z", 0.11, 0.0, 0.05),    # elbow flexes forward: back is outer
    ("thigh", "hips", "+z", 0.15, 0.08, 0.07),        # hip flexes forward: seat is outer
]

# Test poses for the coverage check: euler XYZ degrees in each bone's local
# frame (+X pitches a bone forward; knee flexion is -X). _r mirrors _l.
def mirror(pose):
    out = dict(pose)
    for k, v in pose.items():
        if k.endswith("_l") and k[:-2] + "_r" not in pose:
            out[k[:-2] + "_r"] = (v[0], -v[1], -v[2])
    return out


POSE_STRESS = {   # = the rig's rig_stress pose
    "upper_arm_l": (80, 0, -10), "forearm_l": (120, 0, 0), "hand_l": (30, 0, 0),
    "upper_arm_r": (-20, 0, -60), "forearm_r": (120, 0, 0), "hand_r": (-20, 0, 0),
    "thigh_l": (100, 0, 0), "shin_l": (-120, 0, 0), "foot_l": (25, 0, 0),
    "thigh_r": (-25, 0, 0), "shin_r": (-120, 0, 0), "foot_r": (-10, 0, 0),
    "spine": (8, 12, 0), "chest": (10, 12, 0), "neck": (-8, 0, 0), "head": (6, 0, 10),
}
ABDUCT = None   # sign of the outward (abduction) Z rotation on the left thigh, solved at build
POSES = {}


def make_poses():
    a = ABDUCT
    POSES.clear()
    POSES["stress"] = POSE_STRESS
    POSES["bend120"] = mirror({"forearm_l": (120, 0, 0), "shin_l": (-120, 0, 0), "upper_arm_l": (30, 0, 0)})
    POSES["squat"] = mirror({"thigh_l": (95, 0, a * 12), "shin_l": (-120, 0, 0), "foot_l": (25, 0, 0),
                             "upper_arm_l": (60, 0, 0), "forearm_l": (110, 0, 0), "spine": (12, 0, 0)})
    POSES["wide"] = mirror({"thigh_l": (10, 0, a * 38), "shin_l": (-45, 0, 0), "foot_l": (0, 0, -a * 20),
                            "upper_arm_l": (0, 0, a * 55), "forearm_l": (90, 0, 0)})
    POSES["stride"] = {"thigh_l": (45, 0, 0), "shin_l": (-60, 0, 0), "thigh_r": (-30, 0, 0),
                       "shin_r": (-30, 0, 0), "upper_arm_l": (-35, 0, 0), "upper_arm_r": (40, 0, 0),
                       "forearm_r": (60, 0, 0), "forearm_l": (20, 0, 0), "spine": (0, 8, 0)}
    POSES["reach"] = mirror({"upper_arm_l": (150, 0, 0), "forearm_l": (30, 0, 0), "chest": (-8, 0, 0)})


# ============================================================ rig/fit access
class Ctx:
    pass


C = Ctx()


def load_rig():
    bpy.ops.wm.open_mainfile(filepath=RIG_BLEND)
    C.rig = bpy.data.objects["base_rig"]
    C.body = bpy.data.objects["body"]
    C.fit = bpy.data.objects["fit_body"]
    rv = C.rig.get("rig_version", None)
    if rv is not None and int(rv) != RIG_VERSION_EXPECTED:
        print("WARNING rig_version %s != %d: re-check garments" % (rv, RIG_VERSION_EXPECTED))
    C.deform = [b.name for b in C.rig.data.bones if b.use_deform]
    bones = C.rig.data.bones
    C.leg = {}
    C.arm = {}
    for side, s in SIDES:
        C.leg[side] = [bones["thigh_" + side].head_local.copy(), bones["shin_" + side].head_local.copy(),
                       bones["foot_" + side].head_local.copy()]
        C.arm[side] = [bones["upper_arm_" + side].head_local.copy(), bones["forearm_" + side].head_local.copy(),
                       bones["hand_" + side].head_local.copy()]
    for side, _ in SIDES:
        C.rig["ik_leg_" + side] = 0.0
        C.rig["ik_arm_" + side] = 0.0
    if C.rig.animation_data:
        C.rig.animation_data.action = None
    reset_pose()


def reset_pose():
    for pb in C.rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()


def apply_pose(pose):
    reset_pose()
    for name, (rx, ry, rz) in pose.items():
        if name in C.rig.pose.bones:
            C.rig.pose.bones[name].rotation_quaternion = Euler(
                (math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_quaternion()
    bpy.context.view_layer.update()


def solve_abduct():
    """Which sign of local-Z rotation swings the left thigh outward (+X)?"""
    global ABDUCT
    apply_pose({"thigh_l": (0, 0, 30)})
    x = (C.rig.matrix_world @ C.rig.pose.bones["shin_l"].head).x
    reset_pose()
    ABDUCT = 1 if x > C.leg["l"][1].x else -1


def islands(me):
    parent = list(range(len(me.vertices)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[max(a, b)] = min(a, b)
    groups = {}
    for v in me.vertices:
        groups.setdefault(find(v.index), []).append(v.index)
    return list(groups.values())


def build_fit_sources():
    """Split fit_body into torso / arm_l / arm_r / leg_l / leg_r, with a BVH
    and per-vertex weights for each, and measure its radii."""
    me = C.fit.data
    names = [g.name for g in C.fit.vertex_groups]
    W = []
    for v in me.vertices:
        W.append({names[g.group]: g.weight for g in v.groups if g.weight > 0})
    C.fit_w = W
    C.src = {}
    for isl in islands(me):
        cen = sum((me.vertices[i].co for i in isl), Vector()) / len(isl)
        if abs(cen.x) < 0.02:
            key = "torso"
        elif cen.z > 1.0:
            key = "arm_" + ("l" if cen.x > 0 else "r")
        else:
            key = "leg_" + ("l" if cen.x > 0 else "r")
        iset = set(isl)
        polys = [p for p in me.polygons if p.vertices[0] in iset]
        verts = [v.co.copy() for v in me.vertices]
        bvh = BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in polys])
        C.src[key] = (bvh, [tuple(p.vertices) for p in polys], verts, isl)
    assert set(C.src) == {"torso", "arm_l", "arm_r", "leg_l", "leg_r"}, C.src.keys()
    # torso profile: half width a(z), half depth b(z) per ring of the proxy
    rings = {}
    for i in C.src["torso"][3]:
        co = me.vertices[i].co
        if abs(co.x) + abs(co.y) < 1e-6:
            continue
        k = round(co.z, 3)
        a, b = rings.get(k, (0, 0))
        rings[k] = (max(a, abs(co.x)), max(b, abs(co.y)))
    C.torso_prof = sorted((z, a, b) for z, (a, b) in rings.items())
    # limb radii along each chain, binned by s
    C.limb_r = {}
    for key, chain_of in (("leg", C.leg), ("arm", C.arm)):
        pts = chain_of["l"]
        bins = {}
        for i in C.src[key + "_l"][3]:
            co = me.vertices[i].co
            s, d, _ = chain_project(pts, co)
            if d < 1e-4:
                continue
            k = round(s / 0.02)
            bins.setdefault(k, []).append(d)
        C.limb_r[key] = sorted((k * 0.02, max(v)) for k, v in bins.items())


def table_lerp(tab, x, idx=1):
    if x <= tab[0][0]:
        return tab[0][idx]
    for p0, p1 in zip(tab, tab[1:]):
        if p0[0] <= x <= p1[0]:
            u = (x - p0[0]) / (p1[0] - p0[0])
            return lerp(p0[idx], p1[idx], u)
    return tab[-1][idx]


def torso_ab(z):
    return table_lerp(C.torso_prof, z, 1), table_lerp(C.torso_prof, z, 2)


def fit_limb_r(kind, s):
    tab = [t for t in C.limb_r[kind] if 0.03 <= t[0]]
    return table_lerp(tab, s)


# ------------------------------------------------------------ chains
def chain_lengths(pts):
    return [(pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)]


def chain_project(pts, p):
    """(s, distance, foot point) of p onto the polyline."""
    best = None
    acc = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ab = b - a
        L = ab.length
        t = max(0.0, min(1.0, (p - a).dot(ab) / (L * L)))
        f = a + ab * t
        d = (p - f).length
        if best is None or d < best[1]:
            best = (acc + t * L, d, f)
        acc += L
    return best


def chain_at(pts, s, miter=0.05):
    """Centre and smoothed tangent at chain distance s (extrapolates past ends)."""
    Ls = chain_lengths(pts)
    dirs = [(pts[i + 1] - pts[i]).normalized() for i in range(len(pts) - 1)]
    acc = 0.0
    for i, L in enumerate(Ls):
        if s <= acc + L or i == len(Ls) - 1:
            c = pts[i] + dirs[i] * (s - acc)
            t = dirs[i]
            # blend tangents across joints so rings don't fold
            if i + 1 < len(Ls) and s > acc + L - miter:
                u = ss(-miter, miter, s - (acc + L))
                t = (dirs[i] * (1 - u) + dirs[i + 1] * u).normalized()
            if i > 0 and s < acc + miter:
                u = ss(-miter, miter, s - acc)
                t = (dirs[i - 1] * (1 - u) + dirs[i] * u).normalized()
            return c, t
        acc += L
    return pts[-1], dirs[-1]


def frame(t, ref=V(0, -1, 0)):
    n = (ref - t * ref.dot(t)).normalized()
    return n, t.cross(n)


# ============================================================ mesh builder
class G:
    """Garment geometry: verts carry a part (weight source + allowed bones)
    and an axis point (for outward orientation); faces carry a channel."""

    def __init__(self, gid):
        self.id = gid
        self.verts = []
        self.part = []
        self.axis = []
        self.faces = []       # (indices, channel R, hull G, hint or None)

    def v(self, co, part, axis):
        self.verts.append(co.copy())
        self.part.append(part)
        self.axis.append(axis.copy())
        return len(self.verts) - 1

    def f(self, idx, ch=FILL, hull=1.0, hint=None):
        self.faces.append((tuple(idx), ch, hull, hint))

    def bridge(self, r0, r1, ch=FILL, closed=True, hull=1.0):
        n = len(r0)
        assert n == len(r1)
        for k in range(n if closed else n - 1):
            k2 = (k + 1) % n
            self.f((r0[k], r0[k2], r1[k2], r1[k]), ch, hull)

    def tube_along(self, path, radii, part, sides=6, ch=FILL, hull=1.0, flat=1.0, cap=True, ref=V(0, -1, 0)):
        """Small closed tube along a list of points (strings, straps, scarf tail)."""
        rings = []
        for i, p in enumerate(path):
            if i == 0:
                t = (path[1] - path[0]).normalized()
            elif i == len(path) - 1:
                t = (path[-1] - path[-2]).normalized()
            else:
                t = (path[i + 1] - path[i - 1]).normalized()
            n, b = frame(t, ref)
            row = []
            for k in range(sides):
                a = 2 * math.pi * (k + 0.5) / sides
                row.append(self.v(p + (n * math.cos(a) * flat + b * math.sin(a)) * radii[i], part, p))
            rings.append(row)
        for r0, r1 in zip(rings, rings[1:]):
            self.bridge(r0, r1, ch, hull=hull)
        if cap:
            for row, p in ((rings[0], path[0]), (rings[-1], path[-1])):
                c = self.v(p, part, p)
                tip = (path[0] - path[1]) if row is rings[0] else (path[-1] - path[-2])
                for k in range(sides):
                    self.f((c, row[k], row[(k + 1) % sides]), ch, hull, hint=tip.normalized())
        return rings

    def to_mesh(self):
        me = bpy.data.meshes.new(self.id)
        me.from_pydata([tuple(v) for v in self.verts], [], [f[0] for f in self.faces])
        me.update()
        # orient each face outward from its axis points (or along its hint)
        flips = []
        for i, (idx, ch, hull, hint) in enumerate(self.faces):
            p = me.polygons[i]
            if hint is None:
                cen = sum((self.verts[j] for j in idx), Vector()) / len(idx)
                ax = sum((self.axis[j] for j in idx), Vector()) / len(idx)
                hint = cen - ax
            if p.normal.dot(hint) < 0:
                flips.append(i)
        if flips:
            import bmesh
            bm = bmesh.new()
            bm.from_mesh(me)
            bm.faces.ensure_lookup_table()
            bmesh.ops.reverse_faces(bm, faces=[bm.faces[i] for i in flips])
            bm.to_mesh(me)
            bm.free()
        for p in me.polygons:
            p.use_smooth = True
        col = me.color_attributes.new("Color", 'FLOAT_COLOR', 'CORNER')
        shell = me.attributes.new("shell", 'INT', 'FACE')
        for i, p in enumerate(me.polygons):
            ch, hull = self.faces[i][1], self.faces[i][2]
            shell.data[i].value = 1 if hull > 0.5 else 0
            for li in p.loop_indices:
                col.data[li].color = (ch, hull, 0.0, 1.0)
        me.color_attributes.active_color = col
        me.color_attributes.render_color_index = me.color_attributes.find("Color")
        me.update()
        return me


# ============================================================ bottoms
LEG_RADIAL = 12
WAIST_RADIAL = 16
TORSO_RADIAL = 16
SLEEVE_RADIAL = 10


def ink_env(kind, s):
    """Radius of the ink limb tube (joint balls included) plus its contour,
    at chain distance s. Mirrors R_LEG / R_ARM / BALL in build_base_rig.py."""
    if kind == "leg":
        mid, L2, r0, r1, r2 = 0.42, 0.445, 0.045, 0.040, 0.034
    else:
        mid, L2, r0, r1, r2 = 0.36, 0.33, 0.040, 0.036, 0.031
    r = lerp(r0, r1, s / mid) if s < mid else lerp(r1, r2, min(1.0, (s - mid) / L2))
    if abs(s - mid) < r1 * 1.08:
        r = max(r, r1 * 1.08)
    if s < r0 * 1.08:
        r = max(r, r0 * 1.08)
    return r + HULL


SEAT = 0.010   # default `seat`


def seat_extra(P, z=None, s=None):
    e = P.get("seat", SEAT)
    if z is not None:
        return e * ss(0.98, 0.93, z)
    return e * ss(0.25, 0.12, s)


def leg_radius(P, s):
    r = fit_limb_r("leg", s) + P["offset"] + seat_extra(P, s=s)
    if P["bag"]:
        r += P["bag"] * math.exp(-((s - P["bag_at"]) / P["bag_w"]) ** 2)
    if P["flare"]:
        r += P["flare"] * ss(0.0, 1.0, s / max(P["hem"], 0.1)) ** 1.5
    if P["cuff"] > 0:
        cz = P["hem"] - P["cuff"]
        rc = fit_limb_r("leg", s) + P["cuff_r"]
        r = lerp(r, rc, ss(cz - 0.035, cz, s))
    return r


def leg_point(P, side, s, ang):
    """Surface point of a trouser leg at chain distance s, angle ang
    (0 = front, in the ring frame). Returns (point, ink centre)."""
    sgn = 1 if side == "l" else -1
    lat = V(sgn, 0, 0)
    if P.get("slant"):
        # inseam shorter than the outseam: the inner side of the leg is
        # compressed upward so the hem rises toward the crotch (a notch, not a skirt)
        c, t = chain_at(C.leg[side], s)
        nn, bb = frame(t)
        med = max(0.0, -(nn * math.cos(ang) + bb * math.sin(ang)).dot(lat))
        s = s - P["slant"] * med * max(0.0, min(1.0, (s - 0.12) / max(P["hem"] - 0.12, 0.05)))
    c, t = chain_at(C.leg[side], s)
    nn, bb = frame(t)
    shift = P["splay"] * min(1.0, s / max(P["hem"], 0.1))
    env = ink_env("leg", s)
    r = max(leg_radius(P, s), shift + env + P["inseam"])
    p = c + lat * shift + (nn * math.cos(ang) + bb * math.sin(ang)) * r
    # inner thigh: compress anything reaching further medially than the ink
    # contour + inseam, so the two legs overlap only where they must
    m_max = env + P["inseam"]
    m = -(p - c).dot(lat)
    if m > m_max:
        p = p + lat * ((m - m_max) * 0.8)
    return p, c


def leg_samples(P):
    hem, cuff = P["hem"], P["cuff"]
    base = [0.12, 0.155, 0.19, 0.23, 0.27, 0.32, 0.36, 0.40, 0.44, 0.48, 0.52, 0.56, 0.61, 0.67, 0.73]
    stop = hem - (cuff + 0.03 if cuff > 0 else 0.025)
    out = [s for s in base if s < stop]
    bands = []
    if cuff > 0:
        out += [hem - cuff - 0.012, hem - cuff]
        bands.append((hem - cuff - 0.012, hem - cuff))
    if P.get("hem_line"):
        out.append(hem - 0.016)
        bands.append((hem - 0.016, hem))
    out.append(hem)
    return sorted(set(round(s, 4) for s in out)), [(round(a, 4), round(b, 4)) for a, b in bands]


def build_bottom(gid, P):
    g = G(gid)
    z_split, z_crotch = 0.905, 0.815
    # ---- waist: torso-ellipse rings from the waistband down to the leg split
    zs = sorted({round(z, 4) for z in (P["waist"], P["waist"] - P["band"], P["waist"] - P["band"] - 0.012,
                                       0.955, z_split) if z >= z_split - 1e-6}, reverse=True)
    rings = []
    for z in zs:
        a, b = torso_ab(z)
        a, b = a + P["offset"] + seat_extra(P, z=z), b + P["offset"] + seat_extra(P, z=z)
        rings.append([g.v(V(a * math.sin(2 * math.pi * i / WAIST_RADIAL),
                            -b * math.cos(2 * math.pi * i / WAIST_RADIAL), z), "waist", V(0, 0, z))
                      for i in range(WAIST_RADIAL)])
    for k in range(len(rings) - 1):
        band = abs(zs[k] - (P["waist"] - P["band"])) < 1e-4
        g.bridge(rings[k], rings[k + 1], FOLD if band else FILL)
    W = rings[-1]
    bz = torso_ab(z_split)[1] + P["offset"] + seat_extra(P, z=z_split)
    seam = [g.v(V(0, bz * 0.55, z_crotch + 0.024), "seam", V(0, 0, z_split)),
            g.v(V(0, 0, z_crotch), "seam", V(0, 0, z_split)),
            g.v(V(0, -bz * 0.55, z_crotch + 0.024), "seam", V(0, 0, z_split))]
    half = WAIST_RADIAL // 2
    ring0 = {"l": [W[i] for i in range(0, half + 1)] + seam,
             "r": [W[i % WAIST_RADIAL] for i in range(half, WAIST_RADIAL + 1)] + seam[::-1]}
    if P.get("drawstring"):
        zt = P["waist"] - P["band"] * 0.55
        b = torso_ab(zt)[1] + P["offset"]
        for sx in (1, -1):
            top = V(sx * 0.02, -b - 0.004, zt)
            g.tube_along([top, top + V(sx * 0.004, -0.006, -0.05), top + V(sx * 0.010, -0.004, -0.10)],
                         [0.007, 0.007, 0.008], "waist", sides=5, ch=FOLD, hull=0.0)
    # ---- legs (pair-of-pants topology: ring 0 = half the waist + the crotch seam)
    samples, bands = leg_samples(P)
    for side, sgn in SIDES:
        r0 = ring0[side]
        c1, t1 = chain_at(C.leg[side], samples[0])
        n1, b1 = frame(t1)
        ang, prev = [], None
        for vi in r0:
            d = g.verts[vi] - c1
            a = math.atan2(d.dot(b1), d.dot(n1))
            if prev is not None:
                while a > prev + math.pi:
                    a -= 2 * math.pi
                while a < prev - math.pi:
                    a += 2 * math.pi
            ang.append(a)
            prev = a
        n = len(r0)
        dirn = 1 if ang[-1] > ang[0] else -1
        even = [ang[0] + dirn * 2 * math.pi * k / n for k in range(n)]
        rows = [r0]
        for ri, s in enumerate(samples):
            e = (0.55, 0.85)[ri] if ri < 2 else 1.0
            row = []
            for k in range(n):
                p, c = leg_point(P, side, s, lerp(ang[k], even[k], e))
                row.append(g.v(p, "leg_" + side, c))
            rows.append(row)
        prev_s = 0.0
        for k, s in enumerate(samples):
            g.bridge(rows[k], rows[k + 1], FOLD if (prev_s, s) in bands else FILL)
            prev_s = s
        if P.get("rips"):
            add_rips(g, P, side)
    return g


RIPS = {   # (s, angle deg from the front toward the leg's own outside, half width, half height)
    "l": [(0.20, -12, 0.046, 0.017), (0.30, 20, 0.034, 0.012), (0.455, -4, 0.050, 0.019), (0.65, 10, 0.030, 0.011)],
    "r": [(0.24, 8, 0.042, 0.015), (0.44, -10, 0.046, 0.018), (0.57, 16, 0.032, 0.012)],
}
JAG = (0.25, 1.0, 0.45, 1.15, 0.35, 0.95, 0.55, 1.05, 0.3)


def add_rips(g, P, side):
    """Ink slashes: jagged lenses laid 3 mm over the cloth, no contour."""
    for s0, adeg, w, h in RIPS[side]:
        a0 = -math.radians(adeg)
        r = leg_radius(P, s0)
        pts = []
        m = len(JAG)
        for i in range(m):                      # top edge, left to right
            x = -w + 2 * w * i / (m - 1)
            taper = math.sqrt(max(0.0, 1 - (x / w) ** 2))
            pts.append((x, h * JAG[i] * taper))
        for i in range(m - 2, 0, -1):           # bottom edge back, shallower
            x = -w + 2 * w * i / (m - 1)
            taper = math.sqrt(max(0.0, 1 - (x / w) ** 2))
            pts.append((x, -h * 0.55 * JAG[(i + 3) % m] * taper))

        def at(x, y):
            p, c = leg_point(P, side, s0 - y, a0 + x / r)
            return p + (p - c).normalized() * 0.003, c
        cp, cc = at(0, 0)
        ci = g.v(cp, "leg_" + side, cc)
        ring = []
        for x, y in pts:
            p, c = at(x, y)
            ring.append(g.v(p, "leg_" + side, c))
        for k in range(len(ring)):
            g.f((ci, ring[k], ring[(k + 1) % len(ring)]), INK, 0.0, hint=(cp - cc))


# ============================================================ tops
def torso_r(P, z):
    """Half width / half depth of the top's torso at height z."""
    a, b = torso_ab(min(z, 1.42))
    extra = P["offset"]
    extra += P.get("bag", 0.0) * math.exp(-((z - 1.12) / 0.16) ** 2)
    if P["hem"] < 1.15:
        extra += P.get("flare", 0.0) * ss(1.15, P["hem"], z)
    else:
        extra += P.get("flare", 0.0) * ss(P["hem"] + 0.1, P["hem"], z)
    return a + extra, b + extra


def torso_point(P, z, ph, out=0.0):
    a, b = torso_r(P, z)
    return V((a + out) * math.sin(ph), -(b + out) * math.cos(ph), z)


def tank_top_z(ph):
    d = math.degrees(ph) % 360
    d = d if d <= 180 else 360 - d          # mirror left/right
    d = d if d <= 90 else 180 - d           # mirror front/back
    tab = [(0, 1.375), (22.5, 1.43), (45, 1.40), (67.5, 1.35), (90, 1.33)]
    return table_lerp(tab, d)


def build_top(gid, P):
    g = G(gid)
    hem = P["hem"]
    zs = [hem]
    bands = []
    if P.get("hem_band"):
        zs += [hem + P["hem_band"] - 0.012, hem + P["hem_band"]]
        bands.append((round(hem + P["hem_band"] - 0.012, 4), round(hem + P["hem_band"], 4)))
    top = 1.30 if P.get("straps") else 1.42
    z = max(zs) + 0.07
    while z < top - 0.03:
        zs.append(z)
        z += 0.075
    zs.append(top)
    zs = sorted(set(round(z, 4) for z in zs))
    rings = []
    for z in zs:
        shrink = -0.006 if P.get("hem_band") and z <= hem + P["hem_band"] - 0.012 + 1e-4 else 0.0
        rings.append([g.v(torso_point(P, z, 2 * math.pi * i / TORSO_RADIAL, shrink), "torso", V(0, 0, z))
                      for i in range(TORSO_RADIAL)])
    for k in range(len(rings) - 1):
        g.bridge(rings[k], rings[k + 1], FOLD if (zs[k], zs[k + 1]) in bands else FILL)
    last = rings[-1]
    if P.get("straps"):
        # tank top: scooped top edge with armholes, two straps over the shoulders
        rowt = []
        for i in range(TORSO_RADIAL):
            ph = 2 * math.pi * i / TORSO_RADIAL
            zz = tank_top_z(ph)
            rowt.append(g.v(torso_point(P, zz, ph), "torso", V(0, 0, zz)))
        g.bridge(last, rowt, FILL)
        for side, sgn in SIDES:
            f_i, b_i = (1, 7) if sgn > 0 else (15, 9)
            pf, pb = g.verts[rowt[f_i]], g.verts[rowt[b_i]]
            x = sgn * 0.046
            path = [pf + V(0, 0, -0.012), V(x, pf.y * 0.85, 1.49), V(x, pf.y * 0.4, 1.538), V(x, 0, 1.551),
                    V(x, pb.y * 0.4, 1.538), V(x, pb.y * 0.85, 1.49), pb + V(0, 0, -0.012)]
            g.tube_along(path, [0.012] * len(path), "yoke", sides=4, flat=0.55, ref=V(0, 0, 1))
        return g
    # yoke: shoulder slope up to the neck opening
    zB, zN = 1.51, 1.565
    a42, b42 = torso_r(P, 1.42)
    nr = P["neck"]
    rowB, rowN, rowC = [], [], []
    for i in range(TORSO_RADIAL):
        ph = 2 * math.pi * i / TORSO_RADIAL
        rowB.append(g.v(V(a42 * 0.88 * math.sin(ph), -b42 * 0.95 * math.cos(ph), zB), "yoke", V(0, 0, zB)))
        if P["collar"]:
            zc = zN - P["collar"]
            rowC.append(g.v(V((nr + 0.008) * math.sin(ph), -(nr * 0.88 + 0.008) * math.cos(ph), zc), "yoke",
                            V(0, 0, zc)))
        rowN.append(g.v(V(nr * math.sin(ph), -nr * 0.88 * math.cos(ph), zN), "yoke", V(0, 0, zN - 0.05)))
    g.bridge(last, rowB, FILL)
    if P["collar"]:
        g.bridge(rowB, rowC, FILL)
        g.bridge(rowC, rowN, FOLD)
    else:
        g.bridge(rowB, rowN, FILL)
    if P.get("sleeve"):
        for side, _ in SIDES:
            build_sleeve(g, P, side)
    if P.get("hood"):
        build_hood(g, P)
    if P.get("pocket"):
        build_pocket(g, P)
    if P.get("strings"):
        for sx in (1, -1):
            tp = V(sx * 0.03, -(nr * 0.88) - 0.014, 1.545)
            g.tube_along([tp, tp + V(sx * 0.004, -0.012, -0.07), tp + V(sx * 0.006, -0.016, -0.14)],
                         [0.0065, 0.0065, 0.0085], "yoke", sides=5, ch=FOLD, hull=0.0)
    if P.get("scarf"):
        build_scarf(g, P)
    return g


def sleeve_radius(P, s):
    r = fit_limb_r("arm", max(s, 0.03)) + P["s_off"]
    r += P.get("s_bag", 0.0) * math.exp(-((s - 0.50) / 0.14) ** 2)
    r += P.get("s_flare", 0.0) * ss(0.0, P["sleeve"], s)
    if P.get("cuff"):
        cz = P["sleeve"] - P["cuff"]
        r = lerp(r, fit_limb_r("arm", max(s, 0.03)) + 0.008, ss(cz - 0.04, cz, s))
    return max(r, ink_env("arm", max(s, 0.0)) + 0.008)


def build_sleeve(g, P, side):
    pts = C.arm[side]
    part = "sleeve_" + side
    hem = P["sleeve"]
    base = [0.0, 0.05, 0.10, 0.16, 0.22, 0.28, 0.32, 0.36, 0.40, 0.44, 0.48, 0.53, 0.58]
    ss_ = [s for s in base if s < hem - 0.03]
    bands = []
    if P.get("cuff"):
        ss_ = [s for s in ss_ if s < hem - P["cuff"] - 0.03]
        ss_ += [hem - P["cuff"] - 0.012, hem - P["cuff"]]
        bands.append((round(hem - P["cuff"] - 0.012, 4), round(hem - P["cuff"], 4)))
    ss_.append(hem)
    ss_ = sorted(set(round(s, 4) for s in ss_))
    R0 = sleeve_radius(P, 0.0)
    c0, t0 = chain_at(pts, 0.0)
    n0, b0 = frame(t0)
    rows = []
    pole = g.v(c0 - t0 * R0, part, c0)           # domed cap over the shoulder ball
    for al in (32, 58, 78):
        a = math.radians(al)
        c = c0 - t0 * (R0 * math.cos(a))
        rows.append([g.v(c + (n0 * math.cos(2 * math.pi * k / SLEEVE_RADIAL) + b0 * math.sin(2 * math.pi * k / SLEEVE_RADIAL))
                         * R0 * math.sin(a), part, c0) for k in range(SLEEVE_RADIAL)])
    for s in ss_:
        c, t = chain_at(pts, s)
        n, b = frame(t)
        r = sleeve_radius(P, s)
        rows.append([g.v(c + (n * math.cos(2 * math.pi * k / SLEEVE_RADIAL) + b * math.sin(2 * math.pi * k / SLEEVE_RADIAL)) * r,
                         part, c) for k in range(SLEEVE_RADIAL)])
    for k in range(SLEEVE_RADIAL):
        g.f((pole, rows[0][k], rows[0][(k + 1) % SLEEVE_RADIAL]), FILL, 1.0, hint=-t0)
    for i in range(len(rows) - 1):
        key = (ss_[i - 3], ss_[i - 2]) if i >= 3 else None
        g.bridge(rows[i], rows[i + 1], FOLD if key in bands else FILL)


def build_hood(g, P):
    """Hood down: a rolled collar round the back of the neck plus the hood
    bag lying on the upper back."""
    path = []
    for k in range(9):
        deg = lerp(38, 322, k / 8)                   # 0 = front, through the back
        th = math.radians(deg)
        back = deg if deg <= 180 else 360 - deg
        rho = lerp(0.082, 0.090, ss(40, 120, back))
        z = lerp(1.535, 1.575, ss(40, 150, back))
        path.append(V(rho * math.sin(th), -rho * math.cos(th), z))
    radii = [0.022, 0.030, 0.034, 0.036, 0.036, 0.036, 0.034, 0.030, 0.022]
    g.tube_along(path, radii, "hood", sides=8, ref=V(0, 0, 1))
    c = V(0, torso_r(P, 1.40)[1] + 0.012, 1.445)
    rx, ry, rz = 0.092, 0.030, 0.088
    seg, nr = 10, 6
    topv = g.v(c + V(0, 0, rz), "hood", c)
    lat = []
    for i in range(1, nr):
        th = math.pi * i / nr
        row = []
        for j in range(seg):
            ph = 2 * math.pi * j / seg
            p = V(rx * math.sin(th) * math.cos(ph), ry * math.sin(th) * math.sin(ph), rz * math.cos(th))
            if p.y < 0:
                p.y *= 0.4            # flat against the back
            if p.z < 0:
                p.z *= 1.0 + 0.35 * (1 - abs(math.cos(ph)))   # the point hangs lower in the middle
            row.append(g.v(c + p, "hood", c))
        lat.append(row)
    botv = g.v(c + V(0, 0, -rz * 1.35), "hood", c)
    for j in range(seg):
        k = (j + 1) % seg
        g.f((topv, lat[0][j], lat[0][k]), FILL)
        g.f((botv, lat[-1][k], lat[-1][j]), FILL)
    for i in range(len(lat) - 1):
        g.bridge(lat[i], lat[i + 1], FILL)
    # the hood's opening: a fold line across the bag
    line = []
    for k in range(7):
        ph = math.radians(lerp(200, 340, k / 6))
        p = c + V(rx * 0.80 * math.cos(ph), 0, rz * 0.50 * math.sin(ph) + 0.03)
        p.y = c.y + ry + 0.003
        line.append(p)
    surface_line(g, line, V(0, 1, 0), "hood", c, width=0.011)


def surface_line(g, pts, normal_hint, part, axis, width=0.012, ch=FOLD, normals=None):
    """A thin decal strip along pts (already lifted over the surface)."""
    left, right = [], []
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        nrm = normals[i] if normals else normal_hint
        w = nrm.cross(t).normalized() * (width * 0.5)
        left.append(g.v(p + w, part, axis))
        right.append(g.v(p - w, part, axis))
    for i in range(len(pts) - 1):
        nrm = normals[i] if normals else normal_hint
        g.f((left[i], right[i], right[i + 1], left[i + 1]), ch, 0.0, hint=nrm)


def build_pocket(g, P):
    """Kangaroo pocket outline on the hoodie front (fold-line decal)."""
    z0 = P["hem"] + P.get("hem_band", 0.0) + 0.03
    corners = [(z0 + 0.15, -0.30), (z0 + 0.15, 0.30), (z0 + 0.10, 0.50), (z0, 0.56), (z0, -0.56),
               (z0 + 0.10, -0.50), (z0 + 0.15, -0.30)]
    pts, nrms = [], []
    for (za, pa), (zb, pb) in zip(corners, corners[1:]):
        for k in range(4):
            u = k / 4
            p = torso_point(P, lerp(za, zb, u), lerp(pa, pb, u), 0.004)
            pts.append(p)
            nrms.append(V(p.x, p.y, 0).normalized())
    p = torso_point(P, corners[-1][0], corners[-1][1], 0.004)
    pts.append(p)
    nrms.append(V(p.x, p.y, 0).normalized())
    surface_line(g, pts, None, "torso", V(0, 0, z0), width=0.012, normals=nrms)


def build_scarf(g, P):
    """Scarf: a fat loop round the neck and one tail down the front, the
    tail skinned to the documented extra bone `scarf_tail` (sways in Godot)."""
    loop = []
    n = 12
    for k in range(n):
        th = 2 * math.pi * k / n
        z = 1.545 + 0.012 * (1 - math.cos(th))
        loop.append(V(0.084 * math.sin(th), -0.084 * math.cos(th), z))
    rings = []
    sides = 8
    for k in range(n):
        p = loop[k]
        t = (loop[(k + 1) % n] - loop[k - 1]).normalized()
        nr = V(p.x, p.y, 0).normalized()
        up = t.cross(nr).normalized()
        if up.z < 0:
            up = -up
        rings.append([g.v(p + nr * math.cos(2 * math.pi * (j + 0.5) / sides) * 0.030
                          + up * math.sin(2 * math.pi * (j + 0.5) / sides) * 0.034, "scarf", p)
                      for j in range(sides)])
    for k in range(n):
        g.bridge(rings[k], rings[(k + 1) % n], FOLD if k in (1,) else FILL)
    knot = V(0.040, -0.112, 1.525)
    path = [knot, V(0.046, -0.124, 1.45), V(0.052, -0.128, 1.36), V(0.056, -0.128, 1.27), V(0.058, -0.127, 1.20)]
    C.scarf_bone = (V(0.040, -0.115, 1.53), V(0.058, -0.127, 1.20))
    rows = []
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = t.cross(V(0, -1, 0)).normalized()
        nrm = side.cross(t).normalized()
        w = 0.036 + 0.004 * i / (len(path) - 1)
        th = 0.012
        rows.append([g.v(q, "tail", p) for q in (p + side * w + nrm * th, p - side * w + nrm * th,
                                                   p - side * w - nrm * th, p + side * w - nrm * th)])
    for i in range(len(rows) - 1):
        g.bridge(rows[i], rows[i + 1], FOLD if i == len(rows) - 3 else FILL)
    end = path[-1]
    g.f(tuple(rows[-1]), FILL, 1.0, hint=(path[-1] - path[-2]).normalized())
    g.f(tuple(rows[0]), FILL, 1.0, hint=(path[0] - path[1]).normalized())
    for k in (-1, 0, 1):           # fringe
        a = end + V(k * 0.024, -0.0135, 0)
        surface_line(g, [a, a + V(0.001 * k, -0.002, -0.03)], V(0, -1, 0), "tail", end, width=0.011)


# ============================================================ weights
PART_SRC = {"waist": "torso", "seam": "torso", "torso": "torso", "yoke": "torso", "hood": "torso",
            "scarf": "torso", "tail": "torso", "leg_l": "leg_l", "leg_r": "leg_r",
            "sleeve_l": "arm_l", "sleeve_r": "arm_r"}


def allowed(part):
    if part == "waist":
        return {"hips", "spine", "thigh_l", "thigh_r"}
    if part == "seam":
        return {"hips"}                     # the crotch never rides up with a thigh
    if part.startswith("leg_"):
        s = part[-1]
        return {"hips", "thigh_" + s, "shin_" + s, "foot_" + s}
    if part == "torso":
        return {"hips", "spine", "chest", "neck", "shoulder_l", "shoulder_r"}
    if part in ("yoke", "hood"):
        return {"spine", "chest", "neck", "shoulder_l", "shoulder_r"}
    if part == "scarf":
        return {"chest", "neck"}
    if part == "tail":
        return {"chest", "scarf_tail"}
    if part.startswith("sleeve_"):
        s = part[-1]
        return {"chest", "shoulder_" + s, "upper_arm_" + s, "forearm_" + s, "hand_" + s}
    raise KeyError(part)


def transfer(g):
    """Nearest Face Interpolated, per part: each garment vertex takes the
    barycentric blend of the nearest fit_body face on its source part."""
    out = []
    for i, co in enumerate(g.verts):
        bvh, polys, verts, _ = C.src[PART_SRC[g.part[i]]]
        loc, nrm, fi, dist = bvh.find_nearest(co)
        poly = polys[fi]
        ws = poly_3d_calc([verts[j] for j in poly], loc)
        acc = {}
        for j, wj in zip(poly, ws):
            for bn, bw in C.fit_w[j].items():
                acc[bn] = acc.get(bn, 0.0) + wj * bw
        out.append(acc)
    return out


def bone_axes(name):
    m = C.rig.data.bones[name].matrix_local
    return m.col[3].xyz.copy(), m.col[1].xyz.normalized(), m.col[2].xyz.normalized()


def reprofile(g, W):
    """Hinge cleanup: re-split parent/child weight by position around the joint."""
    for child_base, parent_base, inner, c_out, c_oth, hw in HINGES:
        for side, _ in SIDES:
            child = child_base + "_" + side
            parent = parent_base if parent_base == "hips" else parent_base + "_" + side
            piv, yax, zax = bone_axes(child)
            n_in = zax * (1 if inner == "+z" else -1)
            want = ("leg_" + side) if child_base in ("shin", "thigh") else ("sleeve_" + side)
            for i, w in enumerate(W):
                if g.part[i] != want:
                    continue
                tot = w.get(parent, 0.0) + w.get(child, 0.0)
                if tot < 1e-4:
                    continue
                d = g.verts[i] - piv
                t = d.dot(yax)
                rad = d - yax * t
                o = -rad.normalized().dot(n_in) if rad.length > 1e-6 else 0.0
                c = c_oth + (c_out - c_oth) * ss(-0.6, 1.0, o)
                wc = ss(c - hw, c + hw, t)
                w[parent] = tot * (1 - wc)
                w[child] = tot * wc


def rigid_sleeve_root(g, W):
    """The shoulder ball is a sphere rigid on upper_arm, centred on the pivot.
    A sleeve cap rigid on upper_arm is a sphere about the same pivot, so it
    covers the ball at any arm angle; a shoulder/upper_arm blend would
    collapse round it. Rigid to s=0.10, back to the copied weights by 0.18
    (so short sleeves are rigid to the hem)."""
    for side, _ in SIDES:
        piv, yax, _ = bone_axes("upper_arm_" + side)
        for i, w in enumerate(W):
            if g.part[i] != "sleeve_" + side:
                continue
            k = ss(0.10, 0.18, (g.verts[i] - piv).dot(yax))
            if k >= 1.0:
                continue
            ua = "upper_arm_" + side
            out = {b: v * k for b, v in w.items()}
            out[ua] = out.get(ua, 0.0) + (1 - k)
            W[i] = out


def tail_weights(g, W):
    a, b = C.scarf_bone
    axis = b - a
    L2 = axis.length_squared
    for i in range(len(W)):
        if g.part[i] != "tail":
            continue
        k = ss(0.0, 0.22, (g.verts[i] - a).dot(axis) / L2)
        W[i] = {"chest": 1 - k, "scarf_tail": k} if k < 1 else {"scarf_tail": 1.0}


def finalize(g, W):
    out = []
    for i, w in enumerate(W):
        ok = allowed(g.part[i])
        w = {k: v for k, v in w.items() if k in ok and v > 0.0}
        items = sorted(w.items(), key=lambda kv: (-kv[1], kv[0]))[:4]
        tot = sum(v for _, v in items)
        items = [(k, v / tot) for k, v in items if v / tot >= 0.015]
        tot = sum(v for _, v in items)
        out.append({k: v / tot for k, v in items})
    return out


# ============================================================ objects
def make_material():
    m = bpy.data.materials.get("cloth")
    if m:
        return m
    m = bpy.data.materials.new("cloth")
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Color"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(col.outputs["Color"], sep.inputs["Color"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    nt.links.new(sep.outputs["Red"], mr.inputs["Value"])
    mr.inputs["To Min"].default_value = 0.0
    mr.inputs["To Max"].default_value = 0.55
    nt.links.new(mr.outputs["Result"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    m.diffuse_color = (0.55, 0.55, 0.55, 1)
    return m


def make_scarf_rig():
    if "clothing_rig_scarf" in bpy.data.objects:
        return bpy.data.objects["clothing_rig_scarf"]
    r2 = C.rig.copy()
    r2.data = C.rig.data.copy()
    r2.name = "clothing_rig_scarf"
    r2.animation_data_clear()
    bpy.context.scene.collection.objects.link(r2)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = r2
    r2.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = r2.data.edit_bones
    b = eb.new("scarf_tail")
    b.head, b.tail = C.scarf_bone
    b.align_roll(V(0, -1, 0))
    b.parent = eb["chest"]
    b.use_deform = True
    bpy.ops.object.mode_set(mode='OBJECT')
    if "Deform" in r2.data.collections:
        r2.data.collections["Deform"].assign(r2.data.bones["scarf_tail"])
    for side, _ in SIDES:
        r2["ik_leg_" + side] = 0.0
        r2["ik_arm_" + side] = 0.0
    return r2


def build_object(gid, coll):
    P = BOTTOMS.get(gid) or TOPS[gid]
    C.scarf_bone = None
    g = build_bottom(gid, P) if gid in BOTTOMS else build_top(gid, P)
    me = g.to_mesh()
    me.materials.append(make_material())
    obj = bpy.data.objects.new(gid, me)
    coll.objects.link(obj)
    W = transfer(g)
    reprofile(g, W)
    rigid_sleeve_root(g, W)
    if C.scarf_bone:
        tail_weights(g, W)
    W = finalize(g, W)
    rig = make_scarf_rig() if C.scarf_bone else C.rig
    names = list(C.deform) + (["scarf_tail"] if C.scarf_bone else [])
    for n in names:
        obj.vertex_groups.new(name=n)
    for i, w in enumerate(W):
        for bn, bw in w.items():
            obj.vertex_groups[bn].add([i], bw, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    mod.use_deform_preserve_volume = False      # Godot skins linearly
    obj.parent = rig
    obj["clothing_version"] = CLOTHING_VERSION
    obj["params"] = str(P)
    return obj, rig


# ============================================================ coverage check
def eval_mesh(obj, shell_only=False):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    mw = obj.matrix_world
    m3 = mw.to_3x3()
    co = np.array([tuple(mw @ v.co) for v in me.vertices])
    nr = np.array([tuple((m3 @ v.normal).normalized()) for v in me.vertices])
    me.calc_loop_triangles()
    shell = me.attributes.get("shell")
    tris = [tuple(lt.vertices) for lt in me.loop_triangles
            if not (shell_only and shell is not None and shell.data[lt.polygon_index].value == 0)]
    ev.to_mesh_clear()
    return co, nr, np.array(tris, dtype=np.int64)


def winding(points, co, tris):
    """Generalised winding number of each point w.r.t. the triangle soup:
    ~1 inside, ~0 outside, robust to open hems and overlapping legs."""
    A, B, Cc = co[tris[:, 0]], co[tris[:, 1]], co[tris[:, 2]]
    out = np.zeros(len(points))
    for k in range(0, len(points), 200):
        P = points[k:k + 200][:, None, :]
        a, b, c = A[None] - P, B[None] - P, Cc[None] - P
        la, lb, lc = (np.linalg.norm(x, axis=2) for x in (a, b, c))
        det = np.einsum("ijk,ijk->ij", a, np.cross(b, c))
        den = la * lb * lc + np.einsum("ijk,ijk->ij", a, b) * lc + np.einsum("ijk,ijk->ij", b, c) * la \
            + np.einsum("ijk,ijk->ij", c, a) * lb
        out[k:k + 200] = (2 * np.arctan2(det, den)).sum(axis=1) / (4 * math.pi)
    return out


def body_ink_points():
    """Ink-limb body vertices worth checking (no head, hands or feet)."""
    me = C.body.data
    ink = set()
    for p in me.polygons:
        if p.material_index == 0:
            ink.update(p.vertices)
    names = [vg.name for vg in C.body.vertex_groups]
    keep = []
    for v in me.vertices:
        if v.index not in ink:
            continue
        top = names[max(v.groups, key=lambda e: e.weight).group]
        if top.startswith(("hand_", "foot_", "head")):
            continue
        # tube cap centres sit on the bone axis inside the limb: no contour there
        b = C.rig.data.bones[top]
        h, t = b.head_local, b.tail_local
        u = max(0.0, min(1.0, (v.co - h).dot(t - h) / (t - h).length_squared))
        if (v.co - (h + (t - h) * u)).length < 0.02:
            continue
        keep.append(v.index)
    return np.array(keep)


def set_all_poses(pose, rigs):
    for r in rigs:
        for pb in r.pose.bones:
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = (1, 0, 0, 0)
        for name, (rx, ry, rz) in pose.items():
            if name in r.pose.bones:
                r.pose.bones[name].rotation_quaternion = Euler(
                    (math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_quaternion()
    bpy.context.view_layer.update()


def check_coverage(obj, rig, idx):
    rigs = [C.rig] + ([rig] if rig is not C.rig else [])
    set_all_poses({}, rigs)
    bco, bnr, _ = eval_mesh(C.body)
    gco, _, gt = eval_mesh(obj, shell_only=True)
    wc = winding(bco[idx], gco, gt)
    exp = idx[wc > 0.85]
    names = [vg.name for vg in C.body.vertex_groups]

    def where(bad):
        out = {}
        for vi in bad:
            v = C.body.data.vertices[int(vi)]
            top = names[max(v.groups, key=lambda e: e.weight).group]
            out[top] = out.get(top, 0) + 1
        return out
    w = winding(bco[exp] + bnr[exp] * HULL, gco, gt)
    res = {"covered": int(len(exp)), "rest": int((w < 0.5).sum())}
    if res["rest"]:
        res["rest_where"] = where(exp[w < 0.5])
    for pname, pose in POSES.items():
        set_all_poses(pose, rigs)
        bco, bnr, _ = eval_mesh(C.body)
        gco, _, gt = eval_mesh(obj, shell_only=True)
        w = winding(bco[exp] + bnr[exp] * HULL, gco, gt)
        res[pname] = int((w < 0.5).sum())
        if res[pname]:
            res[pname + "_where"] = where(exp[w < 0.5])
    set_all_poses({}, rigs)
    return res


def check_layering(tops, bottoms):
    """Bottom waistband vertices under a top's hem must stay inside the top."""
    out = {}
    for tid, (tobj, trig) in tops.items():
        hem = TOPS[tid]["hem"]
        for bid, (bobj, _) in bottoms.items():
            if hem > BOTTOMS[bid]["waist"] - 0.03:
                continue
            rigs = [C.rig] + ([trig] if trig is not C.rig else [])
            set_all_poses({}, rigs)
            bco, _, _ = eval_mesh(bobj)
            sel = np.where((bco[:, 2] > hem + 0.03) & (bco[:, 2] < BOTTOMS[bid]["waist"] + 0.001))[0]
            worst = 0
            for pname, pose in [("rest", {})] + list(POSES.items()):
                set_all_poses(pose, rigs)
                bco, _, _ = eval_mesh(bobj)
                tco, _, tt = eval_mesh(tobj, shell_only=True)
                w = winding(bco[sel], tco, tt)
                worst = max(worst, int((w < 0.5).sum()))
            out[(tid, bid)] = worst
    set_all_poses({}, [C.rig])
    return out


# ============================================================ export
IMPORT_TMPL = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=0
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
import_script/path=""
materials/extract=0
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=1
"""

PALETTE_IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
mipmaps/generate=false
roughness/mode=0
process/fix_alpha_border=false
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_if_missing(path, text):
    if not os.path.exists(path):
        with open(path, "w", newline="\n") as f:
            f.write(text)


def export(obj, rig):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    rig.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    path = os.path.join(OUT_DIR, obj.name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
        export_materials='EXPORT', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_skins=True, export_def_bones=True, export_leaf_bone=False, export_influence_nb=4,
        export_animations=False, export_reset_pose_bones=True, export_rest_position_armature=True,
        export_morph=False, export_cameras=False, export_lights=False, export_extras=False,
    )
    write_if_missing(path + ".import", IMPORT_TMPL)
    return path


# ============================================================ main
def main():
    load_rig()
    bpy.context.preferences.filepaths.save_version = 0     # no clothing.blend1
    solve_abduct()
    make_poses()
    build_fit_sources()
    os.makedirs(OUT_DIR, exist_ok=True)
    write_palette(PALETTE_OUT)
    write_if_missing(PALETTE_OUT + ".import", PALETTE_IMPORT)
    coll = bpy.data.collections.new("clothing")
    bpy.context.scene.collection.children.link(coll)
    ids = [i for i in ALL_IDS if ONLY is None or i in ONLY]
    idx = body_ink_points()
    built = {}
    failures = 0
    for gid in ids:
        obj, rig = build_object(gid, coll)
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print("STATS %-20s tris=%4d verts=%4d groups=%d" % (gid, tris, len(obj.data.vertices), len(obj.vertex_groups)))
        if "--no-check" not in ARGS:
            res = check_coverage(obj, rig, idx)
            bad = sum(v for k, v in res.items() if isinstance(v, int) and k != "covered")
            print("CLIP  %-20s %s" % (gid, res))
            failures += 1 if bad else 0
        built[gid] = (obj, rig)
    if "--no-check" not in ARGS and ONLY is None:
        lay = check_layering({k: v for k, v in built.items() if k in TOPS},
                             {k: v for k, v in built.items() if k in BOTTOMS})
        bad = {"%s/%s" % k: v for k, v in lay.items() if v}
        print("LAYER pairs=%d failing=%s" % (len(lay), bad))
    for gid, (obj, rig) in built.items():
        print("GLB", export(obj, rig))
    if ONLY is None:
        bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=False)
        print("BLEND", BLEND_OUT)
    print("CLIP_FAILURES", failures)
    if failures and "--allow-clip" not in ARGS:
        sys.exit(1)


main()
