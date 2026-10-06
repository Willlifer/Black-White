"""Black | White armour pieces (head / chest / legs), built from nothing.

    blender -b --factory-startup --python game/tools/blender/build_equipment.py
    blender -b --factory-startup --python game/tools/blender/build_equipment.py -- --only crown,vest

Reads  game/art/source/base_rig.blend   (armature + fit_body proxy; build_base_rig.py makes it)
Writes (never hand-edit these; change this script and rebuild):
    game/art/equipment/<id>.glb                 one per armour id in data/equipment.csv
    game/art/equipment/<id>.glb.import          only if missing: LODs/shadow meshes off
    game/art/equipment/equipment_models.json    manifest BWEquipmentView reads
    game/art/source/equipment.blend             working file: every piece on the rig

Look: chunky low poly (old-school RuneScape). Every face is one flat
greyscale tone baked into vertex COLOR, shaded per face by a fixed light, so
the facets read inside the game's unlit shader. Normals stay smooth so the
inverted-hull contour is closed. Two material slots: `armour` (greyscale)
and `accent` (the element splash: feather, gem, plume, trim; vertex colour
is the facet shade only, the game multiplies in the element colour).

Attachment (design/art/EQUIPMENT_MODELS.md):
    socket   rigid, unskinned, modelled in socket space (origin at the socket)
    skinned  exported with the 20 deform bones. Islands are either rigid
             (100% one bone: plates, pauldrons, manica) or cloth (weights
             copied from fit_body by nearest-face interpolation, the same
             transfer the clothing lane uses), or `skirt` (procedural
             hips -> thighs blend for robes and tassets).

Coordinates are Blender's (Z up, character faces -Y, left = +X); the glTF
exporter maps them to Godot (Y up, faces +Z). Deterministic: no randomness.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# ----------------------------------------------------------------- paths
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
RIG_BLEND = os.path.join(GAME, "art", "source", "base_rig.blend")
OUT_DIR = os.path.join(GAME, "art", "equipment")
BLEND_OUT = os.path.join(GAME, "art", "source", "equipment.blend")
MANIFEST = os.path.join(OUT_DIR, "equipment_models.json")
CSV = os.path.join(GAME, "data", "equipment.csv")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

RIG_VERSION = 1          # must match build_base_rig.py / character_rig.gd
MODELS_VERSION = 1       # bump when ids, attach types or material slots change


def V(x, y, z):
    return Vector((x, y, z))


# ------------------------------------------------- rig landmarks (RIG.md)
HEAD_C = V(0, 0, 1.92)
HEAD_R = V(0.31, 0.295, 0.28)
CROWN_Z = 2.20
HAIR_PAD = 0.08          # hats clear head + 0.08: buzzed/bob/long_hair crowns sit 0.08-0.12 up (HAIR.md GAP 0.042 + thickness)
SOCKETS = {"socket_hat": V(0, 0, 2.20), "socket_hair": V(0, 0, 1.92), "socket_chest": V(0, 0, 1.36)}
SHOULDER_Z, SHOULDER_X, ARM_ABDUCT = 1.48, 0.06, 35.0
UPPER_ARM, FOREARM = 0.36, 0.33
DEFORM_BONES = [
    "root", "hips", "spine", "chest", "neck", "head",
    "shoulder_l", "upper_arm_l", "forearm_l", "hand_l",
    "thigh_l", "shin_l", "foot_l",
    "shoulder_r", "upper_arm_r", "forearm_r", "hand_r",
    "thigh_r", "shin_r", "foot_r",
]

# Layering over the fit_body proxy. Clothing shells sit at about +0.01..0.03
# (baggy pieces more); armour sits outside them. Legs armour waists sit under
# chest armour hems, so chest pieces take the larger offset.
# build_clothing.py offsets: pants 0.008-0.016 (+bag up to 0.05 on baggy
# sweatpants), tops 0.020-0.036 (+bag 0.016 on the hoodie).
OFF_SNUG = 0.030         # tights, chain sleeves (over tight clothing; baggy pants poke through: covers=legs)
OFF_LEGS = 0.055         # chaps, legs waistbands
OFF_CHEST = 0.062        # vest, cuirass, brigandine, robe bodice: clear the hoodie
OFF_PLATE = 0.078        # platemail, platelegs
# The rig's hips are 0.05 apart and fit_body's leg sleeves overlap down to
# the knee, so full-round leg tubes fuse into one block. Leg armour is
# squashed side to side (x radius x LEG_XS) so the inverted V reads.
LEG_XS = 0.72


def arm_points(s):
    a = math.radians(ARM_ABDUCT)
    sh = V(s * SHOULDER_X, 0, SHOULDER_Z)
    d1 = V(s * math.sin(a), 0.03, -math.cos(a)).normalized()
    el = sh + d1 * UPPER_ARM
    d2 = V(s * math.sin(a), -0.08, -math.cos(a)).normalized()
    wr = el + d2 * FOREARM
    return sh, el, wr


def leg_points(s):
    return V(s * 0.025, 0, 0.92), V(s * 0.065, -0.015, 0.50), V(s * 0.10, 0.0, 0.055)


FIT_PROF = [(0.80, 0.075, 0.055), (0.88, 0.100, 0.068), (0.98, 0.095, 0.066), (1.10, 0.085, 0.060),
            (1.25, 0.098, 0.064), (1.40, 0.105, 0.066), (1.52, 0.080, 0.055)]


def prof(z):
    """fit_body torso half-widths (x, y) at height z (clamped)."""
    if z <= FIT_PROF[0][0]:
        return FIT_PROF[0][1], FIT_PROF[0][2]
    for (z0, a0, b0), (z1, a1, b1) in zip(FIT_PROF, FIT_PROF[1:]):
        if z0 <= z <= z1:
            u = (z - z0) / (z1 - z0)
            return a0 + (a1 - a0) * u, b0 + (b1 - b0) * u
    return FIT_PROF[-1][1], FIT_PROF[-1][2]


def env(theta_deg, pad=HAIR_PAD):
    """Head(+hair) envelope at elevation theta: (z, rx, ry)."""
    t = math.radians(theta_deg)
    return HEAD_C.z + (HEAD_R.z + pad) * math.sin(t), (HEAD_R.x + pad) * math.cos(t), (HEAD_R.y + pad) * math.cos(t)


def ss(e0, e1, x):
    x = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return x * x * (3 - 2 * x)


def angles(n, start=-90.0, a0=None, a1=None):
    """n angles (degrees). Closed ring from `start` (-90 = character front),
    or n points spanning a0..a1 inclusive (open)."""
    if a0 is not None:
        return [a0 + (a1 - a0) * j / (n - 1) for j in range(n)]
    return [start + 360.0 * j / n for j in range(n)]


def cs(a):
    r = math.radians(a)
    return math.cos(r), math.sin(r)


# --------------------------------------------------------------- palette
# Display (sRGB) grey values; written as BYTE_COLOR, which is sRGB, so the
# game shows these numbers. The facet shade multiplies on top.
TONES = {"white": 1.0, "light": 0.80, "mid": 0.56, "dark": 0.30, "ink": 0.0, "acc": 1.0}
LIGHT = V(0.35, -0.55, 0.76).normalized()      # upper-front-left key


def facet_shade(n):
    d = n.dot(LIGHT)
    return 1.0 if d > 0.45 else (0.88 if d > -0.05 else 0.76)


# ------------------------------------------------------------ the builder
class Piece:
    """Verts + faces + per-vertex weight mode for one armour piece."""

    def __init__(self, pid, attach, socket=None, hair_mode=None, accent_part="", covers=(), notes="", hair_clearance=0.0):
        self.id = pid
        self.attach = attach          # "socket" | "skinned"
        self.socket = socket
        self.hair_mode = hair_mode
        self.accent_part = accent_part
        self.covers = list(covers)
        self.notes = notes
        self.hair_clearance = hair_clearance   # how far hair may rise above the crown (2.20) under hide_top
        self.verts = []
        self.vmode = []
        self.faces = []               # (idx list, tone, inner)
        self.mode = "rigid:head"

    # --- low level
    def vert(self, p):
        self.verts.append(Vector(p))
        self.vmode.append(self.mode)
        return len(self.verts) - 1

    def face(self, idx, tone="white", inner=False):
        if len(set(idx)) >= 3:
            self.faces.append((list(idx), tone, inner))

    def mark(self):
        return len(self.verts)

    def transform(self, start, m):
        for i in range(start, len(self.verts)):
            self.verts[i] = m @ self.verts[i]

    # --- primitives (every one is a closed solid, so normals recalc cleanly)
    def loft(self, rings, tone="white", tone_fn=None, cap0=True, cap1=True, cap_tone=None, closed=True):
        """rings: lists of points (equal length) or single Vectors (apex)."""
        rows = []
        for r in rings:
            rows.append(self.vert(r) if isinstance(r, Vector) else [self.vert(p) for p in r])
        tf = tone_fn or (lambda i, j: tone)
        for i in range(len(rows) - 1):
            a, b = rows[i], rows[i + 1]
            if isinstance(a, int) and isinstance(b, int):
                continue
            n = len(b) if isinstance(a, int) else len(a)
            for j in range(n if closed else n - 1):
                k = (j + 1) % n
                if isinstance(a, int):
                    self.face([a, b[k], b[j]], tf(i, j))
                elif isinstance(b, int):
                    self.face([a[j], a[k], b], tf(i, j))
                else:
                    self.face([a[j], a[k], b[k], b[j]], tf(i, j))
        ct = cap_tone or tone
        if cap0 and not isinstance(rows[0], int):
            self.face(list(reversed(rows[0])), ct)
        if cap1 and not isinstance(rows[-1], int):
            self.face(rows[-1], ct)
        return rows

    def sheet(self, rings, dirs, th, tone="white", tone_fn=None, inner_tone="dark", closed=True, rim_tone=None):
        """A surface with thickness: outer = rings, inner = rings - dirs*th."""
        tf = tone_fn or (lambda i, j: tone)
        out = [[self.vert(p) for p in r] for r in rings]
        inn = [[self.vert(p - d * th) for p, d in zip(r, dr)] for r, dr in zip(rings, dirs)]
        n = len(rings[0])
        span = range(n) if closed else range(n - 1)
        for i in range(len(rings) - 1):
            for j in span:
                k = (j + 1) % n
                self.face([out[i][j], out[i][k], out[i + 1][k], out[i + 1][j]], tf(i, j))
                self.face([inn[i][j], inn[i + 1][j], inn[i + 1][k], inn[i][k]], inner_tone, inner=True)
        for i, ii in ((0, 0), (len(rings) - 1, max(0, len(rings) - 2))):
            for j in span:
                k = (j + 1) % n
                self.face([out[i][j], inn[i][j], inn[i][k], out[i][k]], rim_tone or tf(ii, j))
        if not closed:
            for j, jj in ((0, 0), (n - 1, n - 2)):
                for i in range(len(rings) - 1):
                    self.face([out[i][j], out[i + 1][j], inn[i + 1][j], inn[i][j]], rim_tone or tf(i, jj))
        return out, inn

    def box(self, c, half, basis=None, tone="white"):
        b = basis or Matrix.Identity(3)
        hx, hy, hz = half
        r0 = [c + b @ V(sx * hx, sy * hy, -hz) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        r1 = [c + b @ V(sx * hx, sy * hy, hz) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        self.loft([r0, r1], tone)

    def prism(self, poly, origin, u, v, depth, tone="white"):
        """Extrude a 2D polygon (u, v coords) along u x v by depth, centred."""
        n = u.cross(v).normalized()
        a = [origin + u * p[0] + v * p[1] - n * depth / 2 for p in poly]
        b = [origin + u * p[0] + v * p[1] + n * depth / 2 for p in poly]
        self.loft([a, b], tone)

    def gem(self, c, r, h, axis, n=6, tone="acc", ref=None):
        """Bipyramid: girdle radius r, half-height h along axis."""
        axis = axis.normalized()
        ref = ref or (V(0, 0, 1) if abs(axis.z) < 0.9 else V(1, 0, 0))
        e1 = (ref - axis * ref.dot(axis)).normalized()
        e2 = axis.cross(e1)
        ring = [c + (e1 * math.cos(2 * math.pi * j / n) + e2 * math.sin(2 * math.pi * j / n)) * r for j in range(n)]
        self.loft([c - axis * h * 0.6, ring, c + axis * h], tone)

    def tube(self, pts, radii, n=6, tone="white", tone_fn=None, ref=V(0, -1, 0), aspect=1.0, cap0=True, cap1=True,
             outward=None):
        """Rings perpendicular to a polyline. A radius of 0 makes an apex.
        aspect squashes the ring along `ref`. Angle 0 points along `outward`
        (or the side vector) so tone_fn columns are stable."""
        rings = []
        m = len(pts)
        for i in range(m):
            if i == 0:
                t = (pts[1] - pts[0]).normalized()
            elif i == m - 1:
                t = (pts[-1] - pts[-2]).normalized()
            else:
                t = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
            if radii[i] <= 1e-6:
                rings.append(pts[i].copy())
                continue
            f = (ref - t * ref.dot(t)).normalized()
            s = t.cross(f).normalized()
            if outward is not None and s.dot(outward) < 0:
                s = -s
                f = -f
            ring = []
            for j in range(n):
                a = 2 * math.pi * j / n
                ring.append(pts[i] + (s * math.cos(a) + f * math.sin(a) * aspect) * radii[i])
            rings.append(ring)
        return self.loft(rings, tone, tone_fn, cap0=cap0, cap1=cap1)


# ----------------------------------------------------------- shell helpers
def torso_rings(zs, off, angs, widen=None, front_push=0.0):
    """Rings hugging fit_body's torso at +off. zs: list of z (same for all
    columns) or callables z(a). widen(z) adds to both radii."""
    rings, dirs = [], []
    for zrow in zs:
        ring, dr = [], []
        for a in angs:
            z = zrow(a) if callable(zrow) else zrow
            fa, fb = prof(z)
            w = widen(z) if widen else 0.0
            c, s = cs(a)
            p = V(c * (fa + off + w), s * (fb + off + w), z)
            if front_push and s < -0.95:
                p.y -= front_push
            ring.append(p)
            dr.append(V(c * (fb + off), s * (fa + off), 0).normalized())
        rings.append(ring)
        dirs.append(dr)
    return rings, dirs


def ell_rings(levels, angs, cx=0.0, cy=0.0, circ=False):
    """levels: (z, rx, ry[, dy]) -> rings + radial dirs. circ: grow the
    radii by 1/cos(pi/n) so the polygon's flat sides clear the ellipse
    (hats over hair)."""
    k = 1.0 / math.cos(math.pi / len(angs)) if circ else 1.0
    rings, dirs = [], []
    for lv in levels:
        z, rx, ry = lv[0], lv[1] * k, lv[2] * k
        dy = lv[3] if len(lv) > 3 else 0.0
        ring, dr = [], []
        for a in angs:
            c, s = cs(a)
            ring.append(V(cx + c * rx, cy + dy + s * ry, z))
            dr.append(V(c * ry, s * rx, 0).normalized())
        rings.append(ring)
        dirs.append(dr)
    return rings, dirs


def limb_rings(pts, radii, n, outward, off_dirs=None, ref=V(0, -1, 0), xs=1.0):
    """Rings around a limb chain with angle 0 pointing `outward` (stable
    columns for stripes / fringe). Returns rings, dirs."""
    rings, dirs = [], []
    m = len(pts)
    for i in range(m):
        if i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == m - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
        f = (ref - t * ref.dot(t)).normalized()
        s = t.cross(f).normalized()
        if s.dot(outward) < 0:
            s = -s
        f = t.cross(s).normalized()
        if f.dot(ref) < 0:
            f = -f
        ring, dr = [], []
        for j in range(n):
            a = 2 * math.pi * j / n
            d = s * math.cos(a) * xs + f * math.sin(a)
            ring.append(pts[i] + d * radii[i])
            dr.append(d.normalized())
        rings.append(ring)
        dirs.append(dr)
    return rings, dirs


def lerp(a, b, t):
    return a + (b - a) * t


def chain_pts(points, per_seg):
    """Subdivide a polyline: per_seg[i] points on segment i (end excluded,
    final point included)."""
    out = []
    for i in range(len(points) - 1):
        for k in range(per_seg[i]):
            out.append(lerp(points[i], points[i + 1], k / per_seg[i]))
    out.append(points[-1].copy())
    return out


# ================================================================ HEAD
def feathered_cap():
    P = Piece("feathered_cap", "socket", "socket_hat", "hide_top", "feather",
              notes="Robin Hood cap: long front peak, crown rising to a back point, turned-up brim, tall feather on the left.",
              hair_clearance=0.13)
    n = 8
    angs = angles(n)                    # j0 = front
    z0, rx0, ry0 = env(8)
    z1, rx1, ry1 = env(46)
    r0 = [V(c * rx0 * 1.09, s * ry0 * 1.09 + 0.02, z0) for c, s in map(cs, angs)]
    r0[0] = r0[0] + V(0, -0.15, -0.035)            # the peak
    r0[1] = r0[1] + V(0, -0.03, 0)
    r0[7] = r0[7] + V(0, -0.03, 0)
    r1 = [V(c * rx1 * 1.12, s * ry1 * 1.12 + 0.05, z1 + 0.03) for c, s in map(cs, angs)]
    r1[0] = r1[0] + V(0, -0.05, -0.01)
    apex = V(0, 0.16, 2.43)
    P.loft([r0, r1, apex], "white", cap_tone="dark")
    # turned-up brim round the sides and back (open at the front peak)
    idx = [2, 3, 4, 5, 6]
    inner = [r0[j] + V(0, 0, -0.005) for j in idx]
    outer = [r0[j] + V(cs(angs[j])[0] * 0.07, cs(angs[j])[1] * 0.07, 0.10) for j in idx]
    inner = [r0[1] + V(0.01, 0, 0)] + inner + [r0[7] + V(-0.01, 0, 0)]
    outer = [r0[1] + V(0.04, -0.02, 0.05)] + outer + [r0[7] + V(-0.04, -0.02, 0.05)]
    dirs = [[V(cs(a)[0], cs(a)[1], 0) for a in [angs[1]] + [angs[j] for j in idx] + [angs[7]]]] * 2
    P.sheet([inner, outer], dirs, 0.028, "light", closed=False, inner_tone="mid")
    # the feather: a broad quill sweeping up and back from the left side
    root = V(0.33, 0.06, z0 + 0.04)
    path = [root, V(0.36, 0.16, 2.24), V(0.34, 0.27, 2.44), V(0.27, 0.37, 2.62), V(0.19, 0.43, 2.76)]
    widths = [0.025, 0.085, 0.095, 0.07, 0.0]
    nrm = V(0.7, -1.0, 0.0).normalized()
    rings = []
    for i, p in enumerate(path):
        t = (path[min(i + 1, 4)] - path[max(i - 1, 0)]).normalized()
        wv = t.cross(nrm).normalized()
        if widths[i] == 0:
            rings.append(p)
            continue
        th = 0.016
        rings.append([p + wv * widths[i], p + nrm * th, p - wv * widths[i], p - nrm * th])
    P.loft(rings, "acc")
    return P


def feathered_full_helm():
    P = Piece("feathered_full_helm", "socket", "socket_hat", "hide_all", "plume",
              notes="Great helm: octagonal bucket, eye slit, rim band, arched plume crest on top.")
    angs = angles(8)
    lv = [(1.60, 0.335, 0.325), (1.68, 0.365, 0.355), (1.92, 0.385, 0.372), (1.985, 0.385, 0.372),
          (2.16, 0.365, 0.352), (2.27, 0.29, 0.28)]
    rings, _ = ell_rings(lv, angs)
    for i in (1, 2, 3, 4):
        rings[i][0] = rings[i][0] + V(0, -0.04, 0)      # front ridge
    top = [p + V(0, 0, 0.035) for p in ell_rings([(2.27, 0.16, 0.155)], angs)[0][0]]

    def tone(i, j):
        if i == 0:
            return "light"
        if i == 2 and j in (6, 7, 0, 1):
            return "ink"                                # eye slit
        return "white"
    P.loft(rings + [top], tone_fn=tone, cap_tone="white")
    # breath holes: three dark slots on the right cheek
    for k in range(3):
        a = math.radians(-125)
        c = V(math.cos(a) * 0.375, math.sin(a) * 0.362, 1.80 - k * 0.045)
        P.box(c, (0.035, 0.01, 0.010), Matrix.Rotation(a + math.pi / 2, 3, "Z"), "ink")
    # plume holder + the plume (accent): a crest arching front to back
    P.box(V(0, -0.02, 2.315), (0.035, 0.05, 0.02), None, "light")
    pts = [V(0, -0.10, 2.32), V(0, -0.04, 2.47), V(0, 0.10, 2.56), V(0, 0.27, 2.52), V(0, 0.40, 2.38),
           V(0, 0.47, 2.18), V(0, 0.48, 2.02)]
    P.tube(pts, [0.04, 0.075, 0.09, 0.085, 0.07, 0.045, 0.0], n=6, tone="acc", ref=V(1, 0, 0), aspect=0.95)
    return P


def wizard_hat():
    P = Piece("wizard_hat", "socket", "socket_hat", "hide_top", "band and star",
              notes="Wide floppy brim, tall crooked cone, coloured band and star badge.", hair_clearance=0.22)
    n = 10
    angs = angles(n)
    zb, rxb, ryb = env(16)
    inner = [V(c * rxb * 0.96, s * ryb * 0.96, zb) for c, s in map(cs, angs)]
    outer = []
    for j, (c, s) in enumerate(map(cs, angs)):
        droop = -0.045 if j % 2 else -0.015
        outer.append(V(c * 0.60, s * 0.58, zb + droop))
    down = [V(0, 0, 1)] * n
    P.sheet([inner, outer], [down, down], 0.026, "white", inner_tone="mid", rim_tone="white")
    angs8 = angles(8)
    lv = [(zb - 0.01, 0.31, 0.30), (zb + 0.06, 0.31, 0.30), (zb + 0.17, 0.29, 0.28, 0.01),
          (2.42, 0.21, 0.20, 0.04), (2.66, 0.12, 0.115, 0.13)]
    rings, _ = ell_rings(lv, angs8, circ=True)
    tip = V(0.03, 0.42, 2.74)
    P.loft(rings + [tip], tone_fn=lambda i, j: "acc" if i == 1 else "white", cap_tone="dark")
    # star badge on the front of the cone (accent)
    star = []
    for k in range(10):
        r = 0.075 if k % 2 == 0 else 0.032
        a = math.radians(90 + 36 * k)
        star.append((math.cos(a) * r, math.sin(a) * r))
    zst = 2.31
    org = V(0, -0.255 + 0.02 + 0.012, zst)
    slope = V(0, -0.24, 1).normalized()          # roughly the cone's face
    P.prism(star, org, V(1, 0, 0), slope, 0.03, "acc")
    return P


def baseball_cap():
    P = Piece("baseball_cap", "socket", "socket_hat", "hide_top", "logo patch and button",
              notes="Six-panel dome, long forward bill (dark underside), logo patch, top button.", hair_clearance=0.10)
    angs = angles(8)
    pad = HAIR_PAD + 0.025
    lv = []
    for th in (18, 44, 68):
        z, rx, ry = env(th, pad)
        lv.append((z, rx, ry))
    rings, _ = ell_rings(lv, angs, circ=True)
    top = V(0, 0, HEAD_C.z + HEAD_R.z + pad + 0.03)
    P.loft(rings + [top], "white", cap_tone="dark")
    # bill
    z0 = lv[0][0]
    inner, outer = [], []
    for k in range(-2, 3):
        a = math.radians(-90 + k * 42)
        inner.append(V(math.cos(a) * lv[0][1], math.sin(a) * lv[0][2], z0 + 0.005))
        b = math.radians(k * 30)
        outer.append(V(0.28 * math.sin(b), -0.33 - 0.27 * math.cos(b), z0 - 0.035 - 0.02 * abs(k)))
    up = [V(0, 0, 1)] * 5
    P.sheet([inner, outer], [up, up], 0.026, "white", closed=False, inner_tone="dark")
    # logo patch on the front panel (accent): a chunky hexagon
    zf = (lv[0][0] + lv[1][0]) / 2 + 0.01
    yf = -((lv[0][2] + lv[1][2]) / 2) - 0.01
    hexa = [(math.cos(math.radians(30 + 60 * k)) * 0.12, math.sin(math.radians(30 + 60 * k)) * 0.095) for k in range(6)]
    P.prism(hexa, V(0, yf, zf), V(1, 0, 0), V(0, -0.45, 1).normalized(), 0.03, "acc")
    P.box(top + V(0, 0, 0.012), (0.05, 0.05, 0.022), None, "acc")
    return P


def tilted_beret():
    P = Piece("tilted_beret", "socket", "socket_hat", "hide_top", "pin",
              notes="Puffy disc tipped to the character's right, dark band, stalk, big pin and two ribbon tails.",
              hair_clearance=0.15)
    angs = angles(10)
    z0, rx0, ry0 = env(32)
    lv = [(z0 - 0.01, rx0 * 1.02, ry0 * 1.02), (z0 + 0.045, rx0 * 1.04, ry0 * 1.04), (z0 + 0.10, 0.43, 0.41),
          (z0 + 0.17, 0.40, 0.38), (z0 + 0.215, 0.24, 0.23)]
    rings, _ = ell_rings(lv, angs, circ=True)
    m0 = P.mark()
    P.loft(rings, tone_fn=lambda i, j: "dark" if i == 0 else "white", cap_tone="white")
    P.tube([V(0, 0, z0 + 0.20), V(0, 0, z0 + 0.26)], [0.025, 0.018], n=5, tone="dark")
    # pin: a four-point star on the band, front-left (the high side)
    a = math.radians(-68)
    c = V(math.cos(a) * rx0 * 1.06, math.sin(a) * ry0 * 1.06, z0 + 0.05)
    nrm = V(math.cos(a), math.sin(a), 0.15).normalized()
    u = nrm.cross(V(0, 0, 1)).normalized()
    v = u.cross(nrm).normalized()
    pin = []
    for k in range(8):
        r = 0.115 if k % 2 == 0 else 0.04
        b = math.radians(45 * k)
        pin.append((math.cos(b) * r, math.sin(b) * r))
    P.prism(pin, c + nrm * 0.012, u, v, 0.03, "acc")
    # two ribbon tails off the back of the band (accent), fluttering down
    for k, s in enumerate((1, -1)):
        a = math.radians(90 + s * 14)
        root = V(math.cos(a) * rx0 * 1.05, math.sin(a) * ry0 * 1.05, z0 + 0.02)
        rows, rd = [], []
        for t in range(4):
            p = root + V(s * 0.02 * t, 0.05 * t, -0.075 * t)
            w = 0.03
            rows.append([p + V(-w, 0, 0), p + V(w, 0, 0)])
            rd.append([V(0, 1, 0.3).normalized()] * 2)
        P.sheet(rows, rd, 0.016, "acc", closed=False, inner_tone="acc")
    # tip the whole beret toward the character's right (-X)
    pivot = V(0, 0, z0)
    m = Matrix.Translation(pivot + V(-0.04, 0.0, 0.0)) @ Matrix.Rotation(math.radians(-17), 4, "Y") @ Matrix.Translation(-pivot)
    P.transform(m0, m)
    return P


def tiara():
    P = Piece("tiara", "socket", "socket_hat", "show", "centre gem and side gems",
              notes="Band over the hair, rising to three peaks at the front; big centre gem.")
    n = 14
    angs = angles(n)
    pad = HAIR_PAD + 0.05            # sits on top of the hair (mullet/bob are ~0.12 thick)
    low, up, dl, du = [], [], [], []
    for a in angs:
        c, s = cs(a)
        th = 18 + 16 * (1 + s) / 2              # front lower, back higher (worn tipped back)
        z, rx, ry = env(th, pad)
        low.append(V(c * rx, s * ry, z))
        up.append(V(c * rx * 0.99, s * ry * 0.99, z + 0.055))
        d = V(c * ry, s * rx, 0).normalized()
        dl.append(d)
        du.append(d)
    P.sheet([low, up], [dl, du], 0.028, "light", inner_tone="dark", rim_tone="white")
    # peaks on the front five vertices
    heights = {0: 0.20, 1: 0.12, n - 1: 0.12, 2: 0.07, n - 2: 0.07}
    for j, h in heights.items():
        c, s = cs(angs[j])
        base = up[j] - dl[j] * 0.012
        tang = V(-s, c, 0)
        w = 0.06 if j == 0 else 0.045
        tri = [(-w, 0), (w, 0), (0, h)]
        P.prism(tri, base, tang, V(0, 0, 1), 0.026, "white")
    # gems (accent): big one at the centre peak, small ones on the side peaks
    P.gem(up[0] + V(0, -0.035, 0.02), 0.06, 0.03, V(0, -1, 0), n=6)
    for j in (2, n - 2):
        P.gem(up[j] - dl[j] * -0.022 + V(0, 0, 0.0), 0.035, 0.02, dl[j], n=4)
    for j in (1, n - 1):
        P.gem(up[j] + V(0, 0, h_or(heights, j) * 0.55) + dl[j] * 0.02, 0.026, 0.016, dl[j], n=4)
    return P


def h_or(d, k):
    return d.get(k, 0.0)


def crown():
    P = Piece("crown", "socket", "socket_hat", "show", "gems on the band and the point tips",
              notes="Six-point crown sitting on the crown of the head, gems on the band and tips.")
    n = 12
    angs = angles(n)
    z0, rx0, ry0 = env(40, HAIR_PAD + 0.04)
    rings, dirs = ell_rings([(z0 - 0.02, rx0, ry0), (z0 + 0.03, rx0 + 0.005, ry0 + 0.005),
                             (z0 + 0.11, rx0 + 0.02, ry0 + 0.02)], angs)
    top, tdir = [], []
    for j, (c, s) in enumerate(map(cs, angs)):
        if j % 2 == 0:
            top.append(V(c * (rx0 + 0.045), s * (ry0 + 0.045), z0 + 0.27))
        else:
            top.append(V(c * (rx0 + 0.03), s * (ry0 + 0.03), z0 + 0.13))
        tdir.append(dirs[0][j])

    def tone(i, j):
        return "light" if i == 0 else "white"
    P.sheet(rings + [top], dirs + [tdir], 0.03, tone_fn=tone, inner_tone="dark")
    for j in range(0, n, 2):
        P.gem(top[j] + V(0, 0, 0.02), 0.032, 0.03, V(0, 0, 1), n=4)
    for j in (0, 3, 6, 9):
        c, s = cs(angs[j])
        p = V(c * (rx0 + 0.012), s * (ry0 + 0.012), z0 + 0.07)
        P.gem(p + dirs[1][j] * 0.018, 0.04, 0.026, dirs[1][j], n=6)
    return P


def dragoon_helm():
    P = Piece("dragoon_helm", "socket", "socket_hat", "hide_all", "crest fin",
              notes="Beaked helm with swept-back horns and a jagged dragon-spine crest.")
    angs = angles(8)
    lv = [(1.62, 0.33, 0.32), (1.80, 0.365, 0.355), (1.93, 0.375, 0.365), (2.00, 0.375, 0.365),
          (2.16, 0.34, 0.33), (2.26, 0.24, 0.235)]
    rings, _ = ell_rings(lv, angs)
    rings[0][0] = rings[0][0] + V(0, -0.20, -0.06)          # beak
    rings[1][0] = rings[1][0] + V(0, -0.13, 0)
    rings[1][1] = rings[1][1] + V(0, -0.03, 0)
    rings[1][7] = rings[1][7] + V(0, -0.03, 0)
    rings[2][0] = rings[2][0] + V(0, -0.07, 0)
    rings[3][0] = rings[3][0] + V(0, -0.05, 0)
    top = V(0, 0.02, 2.31)

    def tone(i, j):
        if i == 2 and j in (6, 7, 0, 1):
            return "ink"
        if i == 0:
            return "light"
        return "white"
    P.loft(rings + [top], tone_fn=tone, cap_tone="white")
    # crest fin (accent): jagged spine over the top, front to back
    prof_pts = [(-0.24, 2.18), (-0.16, 2.43), (-0.06, 2.34), (0.06, 2.55), (0.16, 2.40), (0.30, 2.52),
                (0.40, 2.30), (0.46, 2.08), (0.30, 2.14), (0.12, 2.24), (-0.08, 2.25)]
    P.prism([(y, z) for y, z in prof_pts], V(0, 0, 0), V(0, 1, 0), V(0, 0, 1), 0.09, "acc")
    # horns sweeping back from the temples
    for s in (1, -1):
        pts = [V(s * 0.34, 0.02, 2.02), V(s * 0.40, 0.22, 2.12), V(s * 0.39, 0.44, 2.30), V(s * 0.32, 0.62, 2.48)]
        P.tube(pts, [0.06, 0.05, 0.033, 0.0], n=5, tone="light")
    return P


# =============================================================== CHEST
def single_shoulder_guard():
    P = Piece("single_shoulder_guard", "skinned", None, None, "strap", covers=[],
              notes="Layered pauldron on the left shoulder (rigid upper_arm_l), strap across the chest to the right armpit.")
    sh, el, wr = arm_points(1)
    d = (el - sh).normalized()
    out = V(1, 0, 0)
    P.mode = "rigid:upper_arm_l"
    # dome over the shoulder ball, axis tilted outward
    ax = (V(0, 0, 1) * 0.75 + out * 0.45).normalized()
    c = sh + V(0.07, 0, -0.035)
    basis_z = ax
    basis_x = (V(0, -1, 0) - ax * V(0, -1, 0).dot(ax)).normalized()
    basis_y = basis_z.cross(basis_x)
    rings = []
    for el_deg, rr in ((0, 1.0), (35, 0.88), (65, 0.55)):
        e = math.radians(el_deg)
        ring = []
        for j in range(8):
            a = 2 * math.pi * j / 8
            ring.append(c + (basis_x * math.cos(a) * 0.175 + basis_y * math.sin(a) * 0.16) * rr + basis_z * math.sin(e) * 0.13)
        rings.append(ring)
    rings[0] = [p - basis_z * 0.02 for p in rings[0]]
    P.loft(rings + [c + basis_z * 0.145], "white", cap_tone="dark")
    # two lames stepping down the arm
    for k, (t0, r0) in enumerate(((0.10, 0.13), (0.18, 0.112))):
        a0 = sh + d * t0
        a1 = sh + d * (t0 + 0.075)
        rr, dd = limb_rings([a0, a1], [r0, r0 - 0.008], 8, out)
        P.sheet(rr, dd, 0.02, "light" if k == 0 else "white", inner_tone="dark")
    # rivet on the dome (dark)
    P.gem(c + basis_z * 0.15, 0.028, 0.012, basis_z, n=4, tone="dark")
    # strap round the chest (rigid chest): shoulder top -> under the right arm
    P.mode = "rigid:chest"
    A = V(0.085, 0, 1.50)
    B = V(-0.14, 0, 1.16)
    mid = (A + B) / 2
    u = (A - B).normalized()
    half = (A - B).length / 2 + 0.015
    nrm = u.cross(V(0, 1, 0)).normalized()
    ring, dirs = [], []
    for j in range(14):
        a = 2 * math.pi * j / 14
        p = mid + u * math.cos(a) * half + V(0, -1, 0) * math.sin(a) * 0.115
        ring.append(p)
        dirs.append((p - mid - nrm * (p - mid).dot(nrm)).normalized())
    w = 0.026
    P.sheet([[p - nrm * w for p in ring], [p + nrm * w for p in ring]], [dirs, dirs], 0.016, "acc", inner_tone="dark")
    P.box(lerp(A, B, 0.5) + V(0, -0.125, 0), (0.035, 0.012, 0.03), Matrix.Rotation(math.atan2(u.z, u.x) - math.pi / 2, 3, "Y"), "light")
    return P


def vest():
    P = Piece("vest", "skinned", None, None, "lining (lapels)", covers=["torso"],
              notes="Open-front sleeveless vest with deep armholes, lapels show the lining, two pocket flaps.")
    P.mode = "fit:torso"
    n = 13
    angs = angles(n, a0=-90 + 22, a1=270 - 22)       # open at the front
    top = lambda a: 1.30 + 0.17 * (1 - abs(math.cos(math.radians(a)))) ** 1.4
    zs = [0.90, 1.00, 1.12, lambda a: lerp(1.12, top(a), 0.5), top]
    rings, dirs = torso_rings(zs, OFF_CHEST, angs)

    def tone(i, j):
        return "acc" if j in (0, n - 2) else "white"
    P.sheet(rings, dirs, 0.022, tone_fn=tone, inner_tone="mid", closed=False)
    # shoulder straps bridging front and back over each shoulder (rigid chest)
    P.mode = "rigid:chest"
    for s in (1, -1):
        P.box(V(s * 0.068, 0, 1.505), (0.03, 0.085, 0.018), None, "white")
    # pocket flaps
    P.mode = "fit:torso"
    for s in (1, -1):
        a = -90 + s * 45
        c, sn = cs(a)
        fa, fb = prof(1.02)
        p = V(c * (fa + OFF_CHEST + 0.008), sn * (fb + OFF_CHEST + 0.008), 1.02)
        P.box(p, (0.035, 0.008, 0.016), Matrix.Rotation(math.radians(a + 90), 3, "Z"), "mid")
    return P


def chain_mail():
    P = Piece("chain_mail", "skinned", None, None, "collar trim", covers=["torso", "upper_legs"],
              notes="Hauberk to mid-thigh with short sleeves; checker of greys reads as rings; padded collar.")
    n = 12
    angs = angles(n)

    def mail(i, j):
        return "light" if (i + j) % 2 == 0 else "mid"
    # body: fit-weighted torso + skirt-weighted hem
    P.mode = "fit:torso"
    zs = [0.98, 1.10, 1.24, 1.38, 1.47]
    rings, dirs = torso_rings(zs, OFF_CHEST - 0.01, angs)
    shoulder = [V(p.x * 0.80, p.y * 0.85, 1.535) for p in rings[-1]]
    rings.append(shoulder)
    dirs.append(dirs[-1])
    body_out, _ = P.sheet(rings, dirs, 0.02, tone_fn=mail, inner_tone="dark")
    P.mode = "skirt"
    hz = [(0.98, 0.0), (0.84, 0.03), (0.70, 0.065), (0.62, 0.08)]
    sk, sd = [], []
    for z, flare in hz:
        fa, fb = prof(max(z, 0.88))
        ring, dr = [], []
        for a in angs:
            c, s = cs(a)
            ring.append(V(c * (fa + OFF_CHEST - 0.008 + flare + 0.02), s * (fb + OFF_CHEST - 0.008 + flare * 0.8 + 0.02), z))
            dr.append(V(c, s, 0))
        sk.append(ring)
        sd.append(dr)
    P.sheet(sk, sd, 0.02, tone_fn=lambda i, j: mail(i + 1, j) if i < 2 else ("dark" if i == 2 and False else mail(i + 1, j)),
            inner_tone="dark")
    # short sleeves
    P.mode = "fit:arms"
    for s in (1, -1):
        sh, el, wr = arm_points(s)
        d = (el - sh).normalized()
        pts = [sh - d * 0.02, sh + d * 0.10, sh + d * 0.20]
        rr, dd = limb_rings(pts, [0.088, 0.086, 0.084], 8, V(s, 0, 0))
        P.sheet(rr, dd, 0.018, tone_fn=lambda i, j: mail(i, j), inner_tone="dark")
    # padded collar (accent): a chunky ring round the neck
    P.mode = "fit:torso"
    cl = []
    for z, r in ((1.49, 1.0), (1.545, 1.06), (1.60, 0.92)):
        ring, dr = [], []
        for a in angles(10):
            c, s = cs(a)
            ring.append(V(c * 0.115 * r, s * 0.095 * r, z))
            dr.append(V(c, s, 0))
        cl.append((ring, dr))
    P.sheet([c[0] for c in cl], [c[1] for c in cl], 0.035, "acc", inner_tone="dark")
    return P


def platemail():
    P = Piece("platemail", "skinned", None, None, "tabard", covers=["torso", "upper_legs"],
              notes="Rigid plates per bone: ridged breastplate (chest), two fauld hoops (spine, hips), big pauldrons (upper arms), gorget; cloth tabard hangs in front.")
    n = 10
    angs = angles(n)
    # breastplate, rigid chest
    P.mode = "rigid:chest"
    zs = [1.17, 1.26, 1.37, 1.46]
    rings, dirs = torso_rings(zs, OFF_PLATE, angs, front_push=0.035)
    rings.append([V(p.x * 0.78, p.y * 0.86, 1.53) for p in rings[-1]])
    dirs.append(dirs[-1])
    P.sheet(rings, dirs, 0.025, tone_fn=lambda i, j: "white", inner_tone="dark")
    # gorget
    gl = []
    for z, r in ((1.50, 1.05), (1.57, 0.95), (1.62, 0.85)):
        ring, dr = [], []
        for a in angles(8):
            c, s = cs(a)
            ring.append(V(c * 0.105 * r, s * 0.09 * r, z))
            dr.append(V(c, s, 0))
        gl.append((ring, dr))
    P.sheet([g[0] for g in gl], [g[1] for g in gl], 0.025, "light", inner_tone="dark")
    # faulds: hoops on spine and hips
    for bone, z0, z1, extra in (("spine", 1.06, 1.19, 0.004), ("hips", 0.93, 1.07, 0.012)):
        P.mode = "rigid:" + bone
        rr, dd = torso_rings([z0, z1], OFF_PLATE + extra, angs)
        rr[0] = [V(p.x * 1.05, p.y * 1.05, p.z) for p in rr[0]]
        P.sheet(rr, dd, 0.022, "light" if bone == "hips" else "white", inner_tone="dark")
    # belt
    P.mode = "rigid:hips"
    rr, dd = torso_rings([0.995, 1.03], OFF_PLATE + 0.022, angs)
    P.sheet(rr, dd, 0.012, "dark", inner_tone="dark")
    # pauldrons, rigid upper arms
    for s, side in ((1, "l"), (-1, "r")):
        P.mode = "rigid:upper_arm_" + side
        sh, el, wr = arm_points(s)
        d = (el - sh).normalized()
        out = V(s, 0, 0)
        ax = (V(0, 0, 1) * 0.8 + out * 0.4).normalized()
        c = sh + V(s * 0.045, 0, 0.0)
        bx = (V(0, -1, 0) - ax * V(0, -1, 0).dot(ax)).normalized()
        by = ax.cross(bx)
        rings = []
        for e_deg, rr_ in ((0, 1.0), (40, 0.86), (70, 0.5)):
            e = math.radians(e_deg)
            rings.append([c + (bx * math.cos(2 * math.pi * j / 8) * 0.165 + by * math.sin(2 * math.pi * j / 8) * 0.15) * rr_
                          + ax * (math.sin(e) * 0.11 - 0.03) for j in range(8)])
        P.loft(rings + [c + ax * 0.10], "white", cap_tone="dark")
        rr, dd = limb_rings([sh + d * 0.10, sh + d * 0.18], [0.115, 0.105], 8, out)
        P.sheet(rr, dd, 0.02, "light", inner_tone="dark")
    # tabard (accent): cloth panel hanging from the belt, skirt-weighted
    P.mode = "skirt"
    zs_t = [1.00, 0.86, 0.72, 0.60]
    rows, rdirs = [], []
    for k, z in enumerate(zs_t):
        fa, fb = prof(max(z, 0.92))
        y = -(fb + OFF_PLATE + 0.035 + 0.012 * k)
        w = 0.075 + 0.006 * k
        rows.append([V(-w, y, z), V(0, y - 0.01, z), V(w, y, z)])
        rdirs.append([V(0, -1, 0)] * 3)
    P.sheet(rows, rdirs, 0.018, "acc", closed=False, inner_tone="acc")
    return P


def silken_robe():
    P = Piece("silken_robe", "skinned", None, None, "sash", covers=["torso", "upper_legs", "arms"],
              notes="Robe to below the knee with wide bell sleeves, crossed collar and a coloured sash with a hanging tail.")
    n = 12
    angs = angles(n)
    P.mode = "fit:torso"
    zs = [1.00, 1.14, 1.30, 1.44]
    rings, dirs = torso_rings(zs, OFF_CHEST, angs)
    top = [V(p.x * 0.72, p.y * 0.80, 1.535) for p in rings[-1]]
    rings.append(top)
    dirs.append(dirs[-1])

    def bod(i, j):
        if i >= 2 and j in (0, 11):
            return "light"        # crossed collar
        return "white"
    P.sheet(rings, dirs, 0.02, tone_fn=bod, inner_tone="dark")
    # skirt
    P.mode = "skirt"
    sk, sd = [], []
    for z, w in ((1.00, 0.0), (0.82, 0.035), (0.62, 0.075), (0.42, 0.115)):
        fa, fb = prof(max(z, 0.90))
        ring, dr = [], []
        for a in angs:
            c, s = cs(a)
            ring.append(V(c * (fa + OFF_CHEST + 0.01 + w + 0.03), s * (fb + OFF_CHEST + 0.01 + w * 0.85 + 0.03), z))
            dr.append(V(c, s, 0))
        sk.append(ring)
        sd.append(dr)
    P.sheet(sk, sd, 0.02, tone_fn=lambda i, j: "light" if i == 2 and False else "white", inner_tone="dark")
    # sash (accent): wide band at the waist plus a tail down the left front
    P.mode = "fit:torso"
    rr, dd = torso_rings([0.985, 1.075], OFF_CHEST + 0.022, angs)
    P.sheet(rr, dd, 0.014, "acc", inner_tone="dark")
    P.mode = "skirt"
    fa, fb = prof(0.95)
    x0 = 0.06
    tail, td = [], []
    for k, z in enumerate((0.99, 0.86, 0.72)):
        y = -(fb + OFF_CHEST + 0.06 + 0.012 * k)
        tail.append([V(x0, y, z), V(x0 + 0.06, y + 0.004, z)])
        td.append([V(0, -1, 0)] * 2)
    P.sheet(tail, td, 0.014, "acc", closed=False, inner_tone="acc")
    # bell sleeves
    P.mode = "fit:arms"
    for s in (1, -1):
        sh, el, wr = arm_points(s)
        d1 = (el - sh).normalized()
        pts = [sh - d1 * 0.01, sh + d1 * 0.16, el, el + (wr - el) * 0.55, wr - (wr - el).normalized() * 0.02]
        rr, dd = limb_rings(pts, [0.085, 0.085, 0.092, 0.115, 0.14], 8, V(s, 0, 0))
        P.sheet(rr, dd, 0.018, tone_fn=lambda i, j: "white", inner_tone="dark")
    return P


def leather_cuirass():
    P = Piece("leather_cuirass", "skinned", None, None, "stitching", covers=["torso"],
              notes="Moulded leather barrel (light grey) with shoulder pads; coloured stitching down the front and round the hem.")
    n = 12
    angs = angles(n)
    P.mode = "fit:torso"
    top = lambda a: 1.26 + 0.21 * (1 - abs(math.cos(math.radians(a)))) ** 1.2
    zs = [0.96, 1.06, 1.16, lambda a: lerp(1.16, top(a), 0.5), top]
    rings, dirs = torso_rings(zs, OFF_CHEST, angs, front_push=0.012)
    P.sheet(rings, dirs, 0.024, tone_fn=lambda i, j: "light", inner_tone="dark", rim_tone="mid")
    # stitching (accent): dashes down the front seam and along the hem
    fa, fb = prof(1.10)
    for k in range(6):
        z = 1.00 + k * 0.075
        fa, fb = prof(z)
        P.box(V(0, -(fb + OFF_CHEST + 0.012 + 0.012), z), (0.012, 0.008, 0.024), None, "acc")
    for j in range(n):
        a = angs[j] + 15
        c, s = cs(a)
        fa, fb = prof(0.985)
        P.box(V(c * (fa + OFF_CHEST + 0.008), s * (fb + OFF_CHEST + 0.008), 0.985), (0.024, 0.008, 0.01),
              Matrix.Rotation(math.radians(a + 90), 3, "Z"), "acc")
    # shoulder pads (rigid upper arms)
    for s, side in ((1, "l"), (-1, "r")):
        P.mode = "rigid:upper_arm_" + side
        sh, el, wr = arm_points(s)
        d = (el - sh).normalized()
        rr, dd = limb_rings([sh + d * 0.005, sh + d * 0.10], [0.09, 0.085], 8, V(s, 0, 0))
        P.sheet(rr, dd, 0.02, "mid", inner_tone="dark")
    # straps over the shoulders
    P.mode = "rigid:chest"
    for s in (1, -1):
        P.box(V(s * 0.07, 0, 1.50), (0.032, 0.085, 0.016), None, "mid")
    return P


def brigandine():
    P = Piece("brigandine", "skinned", None, None, "cloth cover bands", covers=["torso"],
              notes="Riveted plate coat: white plate rows with dark rivets between coloured cloth bands; high collar.")
    n = 12
    angs = angles(n)
    P.mode = "fit:torso"
    top = lambda a: 1.28 + 0.21 * (1 - abs(math.cos(math.radians(a)))) ** 1.2
    fr = [0.0, 0.2, 0.26, 0.46, 0.52, 0.72, 0.78, 1.0]
    zs = [(lambda f: (lambda a: lerp(0.90, top(a), f)))(f) for f in fr]
    rings, dirs = torso_rings(zs, OFF_CHEST + 0.005, angs)

    def tone(i, j):
        return "acc" if i in (1, 3, 5) else "white"
    P.sheet(rings, dirs, 0.026, tone_fn=tone, inner_tone="dark")
    # rivets: dark studs on the front and sides of the three plate rows
    for i in (0, 2, 4, 6):
        for j in range(n):
            a = angs[j] + 15
            c, s = cs(a)
            if s > 0.55:
                continue                          # skip the back
            z = (zs[i](a) + zs[i + 1](a)) / 2
            fa, fb = prof(z)
            p = V(c * (fa + OFF_CHEST + 0.011), s * (fb + OFF_CHEST + 0.011), z)
            P.box(p, (0.011, 0.007, 0.011), Matrix.Rotation(math.radians(a + 90), 3, "Z"), "ink")
    P.mode = "rigid:chest"
    for s in (1, -1):
        P.box(V(s * 0.068, 0, 1.505), (0.034, 0.088, 0.018), None, "white")
    return P


def scarf():
    P = Piece("scarf", "skinned", None, None, "stripes and fringe (the scarf is the splash)", covers=[],
              notes="Chunky wrap round the neck with two striped tails down the front; the coloured stripes are the splash.")
    P.mode = "fit:torso"
    # wrap: a fat torus round the neck, 10 x 6
    rings = []
    R, rr_ = 0.115, 0.048
    for i in range(10):
        a = 2 * math.pi * i / 10
        c = V(math.cos(a) * R, math.sin(a) * R * 0.92, 1.56 + 0.012 * math.sin(a))
        radial = V(math.cos(a), math.sin(a), 0)
        ring = [c + (radial * math.cos(2 * math.pi * k / 6) + V(0, 0, 1) * math.sin(2 * math.pi * k / 6)) * rr_ for k in range(6)]
        rings.append(ring)
    rows = [P.loft([r], cap0=False, cap1=False)[0] for r in rings]   # verts only
    for i in range(10):
        a_, b_ = rows[i], rows[(i + 1) % 10]
        for k in range(6):
            k2 = (k + 1) % 6
            P.face([a_[k], a_[k2], b_[k2], b_[k]], "acc" if i % 2 == 0 else "white")
    # tails: two flat strips hanging down the chest, the left one longer
    for s, length, lean in ((1, 0.42, 0.018), (-1, 0.33, -0.012)):
        x0 = s * 0.045
        strip, sd = [], []
        zs = [1.55 - length * k / 4 for k in range(5)]
        for k, z in enumerate(zs):
            fa, fb = prof(max(z, 1.10))
            y = -(fb + 0.075) - (0.02 if k == 0 else 0.0)
            x = x0 + lean * k
            strip.append([V(x - 0.045, y, z), V(x + 0.045, y, z)])
            sd.append([V(0, -1, 0)] * 2)
        P.sheet(strip, sd, 0.03, tone_fn=lambda i, j: "acc" if i % 2 == 1 else "white", closed=False, inner_tone="white")
        # fringe teeth
        zb = zs[-1]
        fa, fb = prof(max(zb, 1.10))
        y = -(fb + 0.075) - 0.015
        for t in range(3):
            x = x0 + lean * 4 - 0.03 + t * 0.03
            P.prism([(-0.011, 0), (0.011, 0), (0, -0.05)], V(x, y, zb), V(1, 0, 0), V(0, 0, 1), 0.02, "acc")
    return P


def bandolier():
    P = Piece("bandolier", "socket", "socket_chest", None, "cartridge caps", covers=[],
              notes="Diagonal leather belt, left shoulder to right hip, with a row of cartridges (coloured caps) and a buckle. Rigid on socket_chest.")
    A = V(0.075, 0, 1.53)
    B = V(-0.17, 0, 0.98)
    mid = (A + B) / 2
    u = (A - B).normalized()
    half = (A - B).length / 2 + 0.01
    nrm = u.cross(V(0, 1, 0)).normalized()
    ring, dirs = [], []
    m = 16
    for j in range(m):
        a = 2 * math.pi * j / m
        depth = 0.125 if math.sin(a) > 0 else 0.11
        p = mid + u * math.cos(a) * half + V(0, -1, 0) * math.sin(a) * depth
        ring.append(p)
        dirs.append((p - mid - nrm * (p - mid).dot(nrm)).normalized())
    w = 0.048
    P.sheet([[p - nrm * w for p in ring], [p + nrm * w for p in ring]], [dirs, dirs], 0.02, "light", inner_tone="dark")
    # cartridges on the front run of the belt
    for k in range(6):
        t = 0.27 + k * 0.095
        a = math.pi / 2 + (t - 0.5) * 2.2
        p = mid + u * math.cos(a) * half + V(0, -1, 0) * math.sin(a) * 0.125
        out = (p - mid - nrm * (p - mid).dot(nrm)).normalized()
        b = Matrix((nrm, out.cross(nrm), out)).transposed()
        base = p + out * 0.012
        P.box(base + b @ V(0, 0, 0.02), (0.022, 0.028, 0.026), b, "white")      # case
        P.box(base + b @ V(0, 0.044, 0.024), (0.023, 0.017, 0.027), b, "acc")   # cap
    # buckle
    a = math.pi / 2 - 0.62
    p = mid + u * math.cos(a) * half + V(0, -1, 0) * math.sin(a) * 0.125
    out = (p - mid - nrm * (p - mid).dot(nrm)).normalized()
    b = Matrix((nrm, out.cross(nrm), out)).transposed()
    P.box(p + out * 0.01, (0.045, 0.03, 0.01), b, "light")
    return P


def gladiator_chestpiece():
    P = Piece("gladiator_chestpiece", "skinned", None, None, "belt", covers=["right_arm"],
              notes="Segmented manica on the right arm (rigid upper_arm_r / forearm_r), harness strap, round chest disc, wide coloured belt.")
    sh, el, wr = arm_points(-1)
    d1 = (el - sh).normalized()
    d2 = (wr - el).normalized()
    out = V(-1, 0, 0)
    # shoulder dome + 4 lames on the upper arm
    P.mode = "rigid:upper_arm_r"
    ax = (V(0, 0, 1) * 0.8 + out * 0.45).normalized()
    c = sh + V(-0.04, 0, -0.005)
    bx = (V(0, -1, 0) - ax * V(0, -1, 0).dot(ax)).normalized()
    by = ax.cross(bx)
    rings = []
    for e_deg, r in ((0, 1.0), (45, 0.8)):
        e = math.radians(e_deg)
        rings.append([c + (bx * math.cos(2 * math.pi * j / 8) * 0.12 + by * math.sin(2 * math.pi * j / 8) * 0.11) * r
                      + ax * (math.sin(e) * 0.08 - 0.02) for j in range(8)])
    P.loft(rings + [c + ax * 0.085], "white", cap_tone="dark")
    for k in range(4):
        t0 = 0.06 + k * 0.07
        r0 = 0.092 - k * 0.005
        rr, dd = limb_rings([sh + d1 * t0, sh + d1 * (t0 + 0.062)], [r0 + 0.006, r0], 8, out)
        P.sheet(rr, dd, 0.016, "white" if k % 2 == 0 else "light", inner_tone="dark")
    # bracer on the forearm
    P.mode = "rigid:forearm_r"
    for k in range(3):
        t0 = 0.04 + k * 0.085
        rr, dd = limb_rings([el + d2 * t0, el + d2 * (t0 + 0.075)], [0.074 - k * 0.004, 0.07 - k * 0.004], 8, out)
        P.sheet(rr, dd, 0.014, "light" if k % 2 == 0 else "white", inner_tone="dark")
    # harness: strap from the right shoulder to the left hip (rigid chest)
    P.mode = "rigid:chest"
    A = V(-0.075, 0, 1.52)
    B = V(0.15, 0, 1.03)
    mid = (A + B) / 2
    u = (A - B).normalized()
    half = (A - B).length / 2
    nrm = u.cross(V(0, 1, 0)).normalized()
    ring, dirs = [], []
    for j in range(14):
        a = 2 * math.pi * j / 14
        p = mid + u * math.cos(a) * half + V(0, -1, 0) * math.sin(a) * 0.115
        ring.append(p)
        dirs.append((p - mid - nrm * (p - mid).dot(nrm)).normalized())
    w = 0.024
    P.sheet([[p - nrm * w for p in ring], [p + nrm * w for p in ring]], [dirs, dirs], 0.014, "mid", inner_tone="dark")
    # round chest disc (phalera)
    disc_c = lerp(A, B, 0.42) + V(0, -0.13, 0)
    P.loft([[disc_c + V(math.cos(2 * math.pi * j / 8) * 0.05, -0.005, math.sin(2 * math.pi * j / 8) * 0.05) for j in range(8)],
            disc_c + V(0, -0.03, 0)], "light", cap_tone="dark")
    # belt (accent) round the waist + buckle, fit-weighted
    P.mode = "fit:torso"
    angs = angles(12)
    rr, dd = torso_rings([0.92, 0.985, 1.05], OFF_CHEST + 0.02, angs)
    P.sheet(rr, dd, 0.02, "acc", inner_tone="dark")
    fa, fb = prof(0.985)
    P.box(V(0, -(fb + OFF_CHEST + 0.042), 0.985), (0.05, 0.012, 0.045), None, "light")
    return P


# ================================================================ LEGS
def _leg_chain(s, top=0.86, bottom=0.10, per=(3, 3)):
    hip, knee, ankle = leg_points(s)
    d1 = (knee - hip).normalized()
    t_top = (hip.z - top) / (hip.z - knee.z) * (knee - hip).length
    a = hip + d1 * t_top
    d2 = (ankle - knee).normalized()
    b = knee + d2 * ((knee.z - bottom) / (knee.z - ankle.z)) * (ankle - knee).length
    return chain_pts([a, knee, b], per)


def _leg_radius(p):
    """fit_body leg sleeve radius at a point (0.075 hip -> 0.064 knee -> 0.052 ankle)."""
    z = p.z
    if z >= 0.50:
        return lerp(0.064, 0.075, (z - 0.50) / 0.42)
    return lerp(0.052, 0.064, max(0.0, (z - 0.055) / 0.445))


def chaps():
    P = Piece("chaps", "skinned", None, None, "fringe", covers=["legs"],
              notes="Leather leggings (light grey) with a fringe of teeth down each outer seam and a belt with a front V.")
    P.mode = "fit:legs"
    for s in (1, -1):
        pts = _leg_chain(s, top=0.88, bottom=0.12, per=(3, 3))
        rr, dd = limb_rings(pts, [_leg_radius(p) + OFF_LEGS for p in pts], 8, V(s, 0, 0), xs=LEG_XS)
        P.sheet(rr, dd, 0.02, "light", inner_tone="dark", rim_tone="mid")
        # fringe teeth along the outer seam (column 0)
        for i in range(1, len(pts) - 1):
            for half in (0.0, 0.5):
                if i == len(pts) - 2 and half:
                    continue
                p = lerp(rr[i][0], rr[i + 1][0], half)
                o = lerp(dd[i][0], dd[i + 1][0], half).normalized()
                t = (rr[i + 1][0] - rr[i][0]).normalized()
                P.prism([(0, 0.022), (0.06, -0.012), (0, -0.022)], p + o * 0.005, o, -t, 0.02, "acc")
    # belt with a front V (fit torso)
    P.mode = "fit:torso"
    angs = angles(12)
    zs = [lambda a: 0.90 - (0.05 if math.sin(math.radians(a)) < -0.8 else 0.0), 0.95]
    rr, dd = torso_rings(zs, OFF_LEGS + 0.01, angs)
    P.sheet(rr, dd, 0.018, "mid", inner_tone="dark")
    fa, fb = prof(0.93)
    P.box(V(0, -(fb + OFF_LEGS + 0.03), 0.925), (0.03, 0.01, 0.025), None, "light")
    return P


def platelegs():
    P = Piece("platelegs", "skinned", None, None, "knee rivets", covers=["legs"],
              notes="Rigid plates per bone: fauld hoop + front tassets (hips), ridged cuisses (thighs), knee cops with big rivets, greaves (shins), sabatons (feet).")
    n = 8
    for s, side in ((1, "l"), (-1, "r")):
        hip, knee, ankle = leg_points(s)
        out = V(s, 0, 0)
        d1 = (knee - hip).normalized()
        d2 = (ankle - knee).normalized()
        # cuisse
        P.mode = "rigid:thigh_" + side
        pts = [hip + d1 * 0.10, hip + d1 * 0.24, knee - d1 * 0.06]
        rr, dd = limb_rings(pts, [_leg_radius(p) + OFF_PLATE for p in pts], n, out, xs=LEG_XS + 0.04)
        for i in range(len(rr)):
            rr[i][6] = rr[i][6] + dd[i][6] * 0.025       # front ridge (column 6 faces -Y)
        P.sheet(rr, dd, 0.022, "white", inner_tone="dark")
        # greave
        P.mode = "rigid:shin_" + side
        pts = [knee + d2 * 0.06, knee + d2 * 0.22, ankle - d2 * 0.03]
        rr, dd = limb_rings(pts, [_leg_radius(p) + OFF_PLATE - 0.008 for p in pts], n, out, xs=LEG_XS + 0.04)
        for i in range(len(rr)):
            rr[i][6] = rr[i][6] + dd[i][6] * 0.02
        P.sheet(rr, dd, 0.022, tone_fn=lambda i, j: "white" if i == 0 else "light", inner_tone="dark")
        # knee cop: a dome on the front of the knee, wings to the sides; rivets accent
        fwd = V(0, -1, 0)
        kc = knee + fwd * (_leg_radius(knee) + OFF_PLATE - 0.01)
        ax = fwd
        bx = V(1, 0, 0)
        by = V(0, 0, 1)
        rings = []
        for e_deg, r in ((0, 1.0), (40, 0.78), (70, 0.42)):
            e = math.radians(e_deg)
            rings.append([kc + (bx * math.cos(2 * math.pi * j / 8) * 0.072 + by * math.sin(2 * math.pi * j / 8) * 0.08) * r
                          + ax * (math.sin(e) * 0.05) for j in range(8)])
        P.loft(rings, "white", cap_tone="dark")
        P.gem(kc + ax * 0.05, 0.042, 0.032, ax, n=6, tone="acc")
        for sx in (1, -1):
            P.gem(kc + bx * sx * 0.06 + ax * 0.012, 0.03, 0.022, (ax + bx * sx * 0.6).normalized(), n=4, tone="acc")
        for sz in (1, -1):
            P.gem(kc + by * sz * 0.066 + ax * 0.02, 0.026, 0.02, (ax + by * sz * 0.6).normalized(), n=4, tone="acc")
        # rivets round the greave top and the cuisse bottom (accent)
        for bone, base, dd_ in (("shin", knee + d2 * 0.07, d2), ("thigh", knee - d1 * 0.07, d1)):
            P.mode = "rigid:%s_%s" % (bone, side)
            for j in (1, 3, 5, 7):
                a = 2 * math.pi * j / 8
                o = (V(s, 0, 0) * math.cos(a) + V(0, -1, 0) * math.sin(a))
                o = (o - dd_ * o.dot(dd_)).normalized()
                r = _leg_radius(base) + OFF_PLATE + 0.004
                P.gem(base + o * r, 0.02, 0.016, o, n=4, tone="acc")
        P.mode = "rigid:shin_" + side
        # sabaton
        P.mode = "rigid:foot_" + side
        fc = V(ankle.x, -0.04, 0.06)
        P.loft([[fc + V(sx * 0.065, sy * 0.10, -0.045) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))],
                [fc + V(sx * 0.055, sy * 0.085 + 0.01, 0.035) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]],
               "light", cap_tone="dark")
    # fauld hoop + front tassets (hips)
    P.mode = "rigid:hips"
    angs = angles(10)
    rr, dd = torso_rings([0.88, 0.96], OFF_LEGS + 0.012, angs)
    rr[0] = [V(p.x * 1.08, p.y * 1.08, p.z) for p in rr[0]]
    P.sheet(rr, dd, 0.02, "white", inner_tone="dark")
    for s in (1, -1):
        fa, fb = prof(0.88)
        top = [V(s * 0.035, -(fb + OFF_LEGS + 0.035), 0.885), V(s * 0.155, -(fb + OFF_LEGS + 0.01), 0.885)]
        bot = [V(s * 0.04, -(fb + OFF_LEGS + 0.06), 0.74), V(s * 0.17, -(fb + OFF_LEGS + 0.035), 0.74)]
        P.sheet([top, bot], [[V(0, -1, 0)] * 2] * 2, 0.018, "light", closed=False, inner_tone="dark")
    return P


def leather_tassets():
    P = Piece("leather_tassets", "skinned", None, None, "lacing", covers=["upper_legs"],
              notes="Wide belt with five hanging leather plates over the thighs, tied on with coloured lacing.")
    P.mode = "fit:torso"
    angs = angles(12)
    rr, dd = torso_rings([0.92, 1.0], OFF_LEGS + 0.012, angs)
    P.sheet(rr, dd, 0.022, "mid", inner_tone="dark")
    P.mode = "skirt"
    plates = [(-90 - 34, -90 - 2), (-90 + 2, -90 + 34), (-90 + 40, -90 + 92), (-90 - 92, -90 - 40), (60, 120)]
    for k, (a0, a1) in enumerate(plates):
        cols = angles(3, a0=a0, a1=a1)
        rows, rd = [], []
        for z, fl in ((0.93, 0.0), (0.79, 0.035), (0.64, 0.065)):
            fa, fb = prof(0.92)
            ring, dr = [], []
            for a in cols:
                c, s = cs(a)
                ring.append(V(c * (fa + OFF_LEGS + 0.035 + fl), s * (fb + OFF_LEGS + 0.035 + fl), z))
                dr.append(V(c, s, 0))
            rows.append(ring)
            rd.append(dr)
        P.sheet(rows, rd, 0.02, tone_fn=lambda i, j: "light" if i == 0 else "white", closed=False, inner_tone="dark")
        # lacing: an X of two short accent bars where the plate hangs from the belt
        am = (a0 + a1) / 2
        c, s = cs(am)
        fa, fb = prof(0.95)
        p = V(c * (fa + OFF_LEGS + 0.045), s * (fb + OFF_LEGS + 0.045), 0.93)
        b = Matrix.Rotation(math.radians(am + 90), 3, "Z")
        for tilt in (35, -35):
            P.box(p, (0.008, 0.006, 0.042), b @ Matrix.Rotation(math.radians(tilt), 3, "Y"), "acc")
    return P


def robe_bottoms():
    P = Piece("robe_bottoms", "skinned", None, None, "hem band", covers=["legs"],
              notes="Floor-length flared skirt with a dark waist sash and a coloured hem band.")
    angs = angles(12)
    P.mode = "fit:torso"
    rr, dd = torso_rings([0.93, 1.01], OFF_LEGS + 0.004, angs)
    P.sheet(rr, dd, 0.018, "dark", inner_tone="dark")
    P.mode = "skirt"
    rows, rd = [], []
    for z, w in ((0.96, 0.0), (0.74, 0.05), (0.48, 0.10), (0.22, 0.15), (0.17, 0.16), (0.07, 0.175)):
        fa, fb = prof(max(z, 0.92))
        ring, dr = [], []
        for a in angs:
            c, s = cs(a)
            ring.append(V(c * (fa + OFF_LEGS + 0.008 + w + 0.02), s * (fb + OFF_LEGS + 0.008 + w * 0.9 + 0.035), z))
            dr.append(V(c, s, 0))
        rows.append(ring)
        rd.append(dr)
    P.sheet(rows, rd, 0.02, tone_fn=lambda i, j: "acc" if i == 4 else ("light" if i == 3 and j % 2 else "white"),
            inner_tone="dark", rim_tone="white")
    return P


def tights():
    P = Piece("tights", "skinned", None, None, "outer-seam stripe", covers=["legs"],
              notes="Skin-tight white leggings with a coloured stripe down each outer seam and a dark waistband.")
    P.mode = "fit:legs"
    n = 8
    for s in (1, -1):
        pts = _leg_chain(s, top=0.87, bottom=0.10, per=(3, 3))
        rr, dd = limb_rings(pts, [_leg_radius(p) + OFF_SNUG for p in pts], n, V(s, 0, 0), xs=LEG_XS - 0.04)
        # column faces j=7 and j=0 straddle the outer seam (angle 0)
        P.sheet(rr, dd, 0.014, tone_fn=lambda i, j: "acc" if j == 7 else "white", inner_tone="dark")
    P.mode = "fit:torso"
    angs = angles(12)
    rr, dd = torso_rings([0.80, 0.86, 0.93], OFF_SNUG, angs, widen=lambda z: 0.012 if z < 0.85 else 0.0)
    P.sheet(rr, dd, 0.014, "white", inner_tone="dark")
    rr, dd = torso_rings([0.93, 0.975], OFF_SNUG + 0.006, angs)
    P.sheet(rr, dd, 0.012, "dark", inner_tone="dark")
    return P


BUILDERS = [
    feathered_cap, feathered_full_helm, wizard_hat, baseball_cap, tilted_beret, tiara, crown, dragoon_helm,
    single_shoulder_guard, vest, chain_mail, platemail, silken_robe, leather_cuirass, brigandine, scarf, bandolier,
    gladiator_chestpiece,
    chaps, platelegs, leather_tassets, robe_bottoms, tights,
]


# ============================================================ weights
class FitSource:
    """Nearest-face-interpolated weights from fit_body, per island subset
    (torso / arms / legs) so a torso shell never picks up an arm sleeve."""

    def __init__(self, fit_obj):
        me = fit_obj.data
        names = {g.index: g.name for g in fit_obj.vertex_groups}
        self.w = []
        for v in me.vertices:
            self.w.append({names[g.group]: g.weight for g in v.groups if g.weight > 1e-6})
        self.co = [v.co.copy() for v in me.vertices]
        # islands by connectivity
        parent = list(range(len(me.vertices)))

        def find(a):
            while parent[a] != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a
        for e in me.edges:
            ra, rb = find(e.vertices[0]), find(e.vertices[1])
            if ra != rb:
                parent[ra] = rb
        kind = {}
        for i in range(len(me.vertices)):
            r = find(i)
            kind.setdefault(r, {})
            for b, x in self.w[i].items():
                kind[r][b] = kind[r].get(b, 0) + x
        self.island_kind = {}
        for r, tot in kind.items():
            if any(b.startswith("upper_arm") or b.startswith("forearm") for b in tot) and tot.get("spine", 0) == 0:
                self.island_kind[r] = "arms"
            elif any(b.startswith("shin") for b in tot) and tot.get("spine", 0) == 0:
                self.island_kind[r] = "legs"
            else:
                self.island_kind[r] = "torso"
        self.vkind = [self.island_kind[find(i)] for i in range(len(me.vertices))]
        self.tris = {}
        for k in ("torso", "arms", "legs"):
            tris = []
            for p in me.polygons:
                vs = list(p.vertices)
                if self.vkind[vs[0]] != k:
                    continue
                for t in range(1, len(vs) - 1):
                    tris.append((vs[0], vs[t], vs[t + 1]))
            self.tris[k] = tris
        self.bvh = {k: BVHTree.FromPolygons([tuple(c) for c in self.co], t) for k, t in self.tris.items()}

    def weights(self, p, subset):
        best = None
        for k in subset.split("+"):
            loc, _n, idx, dist = self.bvh[k].find_nearest(p)
            if loc is not None and (best is None or dist < best[3]):
                best = (loc, k, idx, dist)
        loc, k, idx, _ = best
        a, b, c = self.tris[k][idx]
        bary = barycentric(loc, self.co[a], self.co[b], self.co[c])
        w = {}
        for vi, f in zip((a, b, c), bary):
            for bone, x in self.w[vi].items():
                w[bone] = w.get(bone, 0) + x * f
        return w


def barycentric(p, a, b, c):
    v0, v1, v2 = b - a, c - a, p - a
    d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
    d20, d21 = v2.dot(v0), v2.dot(v1)
    den = d00 * d11 - d01 * d01
    if abs(den) < 1e-12:
        return (1.0, 0.0, 0.0)
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    v, w = max(0.0, v), max(0.0, w)
    u = max(0.0, 1 - v - w)
    t = u + v + w
    return (u / t, v / t, w / t)


def skirt_weights(p):
    """Robes and tassets: hips at the waist, sliding toward the thigh on
    that side further down (never fully: the cloth lags the leg)."""
    follow = 0.65 * ss(0.0, 1.0, (0.97 - p.z) / (0.97 - 0.45))
    left = ss(-0.06, 0.06, p.x)
    w = {"hips": 1.0 - follow}
    if follow > 0:
        w["thigh_l"] = follow * left
        w["thigh_r"] = follow * (1 - left)
    return w


def finalize_weights(w):
    w = {b: x for b, x in w.items() if x > 1e-4 and b in DEFORM_BONES}
    top = sorted(w.items(), key=lambda kv: (-kv[1], kv[0]))[:4]
    tot = sum(x for _, x in top) or 1.0
    return {b: x / tot for b, x in top}


# ============================================================ to Blender
def make_material(name, rgba):
    m = bpy.data.materials.new(name)
    m.diffuse_color = rgba
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    nt.links.new(attr.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def build_mesh(P, mats):
    """Piece -> Blender mesh with corner colours, material slots and smooth
    normals. Returns (mesh, stats)."""
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in P.verts]
    bm.verts.ensure_lookup_table()
    tone_layer = bm.faces.layers.int.new("tone")
    inner_layer = bm.faces.layers.int.new("inner")
    tone_ids = list(TONES.keys())
    for idx, tone, inner in P.faces:
        try:
            f = bm.faces.new([vs[i] for i in idx])
        except ValueError:
            continue
        f[tone_layer] = tone_ids.index(tone)
        f[inner_layer] = 1 if inner else 0
        f.material_index = 1 if tone == "acc" else 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    # facet colours (per corner, so each face is one flat tone)
    col = bm.loops.layers.color.new("Color")
    area = {"acc": 0.0, "all": 0.0}
    for f in bm.faces:
        tone = tone_ids[f[tone_layer]]
        shade = facet_shade(f.normal)
        g = TONES[tone] * shade
        for lp in f.loops:
            lp[col] = (g, g, g, 1.0)
        if not f[inner_layer]:
            a = f.calc_area()
            area["all"] += a
            if tone == "acc":
                area["acc"] += a
    me = bpy.data.meshes.new(P.id)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = True
    # bmesh colour layers become BYTE_COLOR corner attributes
    ca = me.color_attributes.get("Color")
    if ca is not None:
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = me.color_attributes.find("Color")
    me.update()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    return me, {"tris": tris, "accent_share": round(area["acc"] / max(area["all"], 1e-9), 3)}


def assign_weights(obj, P, fit):
    for name in DEFORM_BONES:
        obj.vertex_groups.new(name=name)
    used = set()
    for i, (p, mode) in enumerate(zip(P.verts, P.vmode)):
        if mode.startswith("rigid:"):
            w = {mode[6:]: 1.0}
        elif mode.startswith("fit:"):
            w = fit.weights(p, mode[4:])
        elif mode == "skirt":
            w = skirt_weights(p)
        else:
            raise ValueError("unknown weight mode %s" % mode)
        w = finalize_weights(w)
        for b, x in w.items():
            obj.vertex_groups[b].add([i], x, "REPLACE")
            used.add(b)
    return sorted(used, key=DEFORM_BONES.index)


def read_csv_armour():
    import csv
    out = {}
    with open(CSV, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["slot"] in ("head", "chest", "legs"):
                out[row["id"]] = row
    return out


def write_import(path):
    """Godot import settings for a piece, written only when missing (Godot
    then fills in its uid). LODs and shadow meshes off: auto-LOD would thin
    the silhouettes the hull outline exaggerates (see RIG.md)."""
    imp = path + ".import"
    if os.path.exists(imp):
        return
    with open(imp, "w", newline="\n") as f:
        f.write('[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n'
                'nodes/root_type=""\nnodes/root_name=""\nmeshes/ensure_tangents=false\nmeshes/generate_lods=false\n'
                'meshes/create_shadow_meshes=false\nmeshes/light_baking=0\nskins/use_named_skins=true\n'
                'animation/import=false\n')


def export_glb(path, objs, active):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
        export_materials="EXPORT", export_vertex_color="ACTIVE", export_all_vertex_colors=False,
        export_skins=True, export_def_bones=True, export_leaf_bone=False, export_influence_nb=4,
        export_animations=False, export_rest_position_armature=True,
        export_morph=False, export_cameras=False, export_lights=False, export_extras=False,
    )


def main():
    if not os.path.exists(RIG_BLEND):
        raise SystemExit("base_rig.blend missing: run build_base_rig.py first")
    bpy.ops.wm.open_mainfile(filepath=RIG_BLEND)
    rig = bpy.data.objects["base_rig"]
    if int(rig.get("rig_version", 0)) != RIG_VERSION:
        raise SystemExit("rig_version %s != %d: re-check the armour against the new rig" % (rig.get("rig_version"), RIG_VERSION))
    fit = FitSource(bpy.data.objects["fit_body"])
    for o in bpy.data.objects:
        if o.name.startswith("socket_"):
            want = SOCKETS.get(o.name)
            if want is not None and (o.matrix_world.translation - want).length > 1e-4:
                raise SystemExit("socket %s moved; update SOCKETS" % o.name)
    sockets = {o.name: o for o in bpy.data.objects if o.name.startswith("socket_")}
    mats = [make_material("armour", (1, 1, 1, 1)), make_material("accent", (0.9, 0.3, 0.2, 1))]
    coll = bpy.data.collections.new("equipment")
    bpy.context.scene.collection.children.link(coll)
    csv_rows = read_csv_armour()
    only = set()
    if "--only" in ARGS:
        only = set(ARGS[ARGS.index("--only") + 1].split(","))
    os.makedirs(OUT_DIR, exist_ok=True)
    manifest = {}
    if only and os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            manifest = json.load(f).get("pieces", {})
    built = set()
    for fn in BUILDERS:
        P = fn()
        built.add(P.id)
        if P.id not in csv_rows:
            raise SystemExit("%s is not an armour id in equipment.csv" % P.id)
        if only and P.id not in only:
            continue
        me, st = build_mesh(P, mats)
        obj = bpy.data.objects.new(P.id, me)
        coll.objects.link(obj)
        path = os.path.join(OUT_DIR, P.id + ".glb")
        if P.attach == "socket":
            origin = SOCKETS[P.socket]
            me.transform(Matrix.Translation(-origin))
            export_glb(path, [obj], obj)
            # in the working .blend, hang it on its socket
            obj.parent = sockets[P.socket]
            obj.matrix_parent_inverse = Matrix.Identity(4)
            bones = [{"socket_hat": "head", "socket_chest": "chest", "socket_hair": "head"}[P.socket]]
        else:
            bones = assign_weights(obj, P, fit)
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = rig
            mod.use_deform_preserve_volume = False
            obj.parent = rig
            export_glb(path, [rig, obj], rig)
        write_import(path)
        row = csv_rows[P.id]
        manifest[P.id] = {
            "slot": row["slot"], "weight": row["weight"], "attach": P.attach,
            "socket": P.socket or "", "hair_mode": P.hair_mode or "", "hair_clearance": round(P.hair_clearance, 3), "bones": bones,
            "tris": st["tris"], "accent_share": st["accent_share"], "accent_part": P.accent_part,
            "covers": P.covers, "notes": P.notes,
        }
        print("PIECE %-22s %-7s %-6s tris %4d accent %.0f%% bones %s" % (
            P.id, P.attach, row["slot"], st["tris"], st["accent_share"] * 100, ",".join(bones)))
    missing = set(csv_rows) - built
    if missing:
        raise SystemExit("armour ids without a builder: %s" % sorted(missing))
    with open(MANIFEST, "w", newline="\n") as f:
        json.dump({"version": MODELS_VERSION, "rig_version": RIG_VERSION,
                   "neutral_accent": "#8C8C8C", "pieces": {k: manifest[k] for k in sorted(manifest)}},
                  f, indent=1, sort_keys=False)
        f.write("\n")
    bpy.context.preferences.filepaths.save_version = 0
    if not only:
        bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=False)
        print("BLEND", BLEND_OUT)
    print("MANIFEST", MANIFEST)


main()
