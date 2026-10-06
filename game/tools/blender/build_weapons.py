"""Black | White weapons: all 25 main-hand models, built from nothing.

    blender -b --factory-startup --python game/tools/blender/build_weapons.py
    blender -b --factory-startup --python game/tools/blender/build_weapons.py -- --only sword,axe

Writes (never hand-edit these; change this script and rebuild):
    game/art/weapons/<id>.glb          one rigid mesh per weapon, surfaces `body` + `accent`
    game/art/weapons/<id>_l.glb        fists only: the left-hand piece, mirrored in x
    game/art/weapons/<id>.glb.import   Godot import settings stub (only if missing; LODs off)
    game/art/weapons/weapons.json      sidecar metadata: class, hands, sockets, grip,
                                       second-hand target, trail tip, aura anchors, tris
    game/art/source/weapons.blend      every weapon laid out in a row with its metadata
                                       as empties (reference only, Godot ignores it)

Conventions (see design/art/WEAPON_MODELS.md and design/art/RIG.md "Weapons"):
  * The grip is the origin: the centre of the fist that holds it.
  * Modelled in "weapon space" (x, f, u): x = the wielder's left, f = forward
    (the edge / muzzle direction), u = up the blade or shaft.
    Blender = (x, -f, u). The glTF +Y-up export makes that Godot (x, u, f),
    i.e. blade along +Y, edge facing +Z, exactly the socket frame at rest.
  * Look: unlit. Vertex COLOR carries a grey value per face; the material
    slot says the role (`body` = the white weapon, `accent` = blade edges,
    gems, striking faces: the part an aura tints). Smooth normals on every
    island so the inverted hull never cracks (shading is unlit, so smooth
    normals cost nothing visually).

Deterministic: no randomness, fixed order, fixed sampling.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.geometry import tessellate_polygon

# ----------------------------------------------------------------- paths
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
ROOT = os.path.dirname(GAME)
OUT_DIR = os.path.join(GAME, "art", "weapons")
JSON_OUT = os.path.join(OUT_DIR, "weapons.json")
BLEND_OUT = os.path.join(GAME, "art", "source", "weapons.blend")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

WEAPONS_VERSION = 1   # bump when grip convention, metadata keys or ids change
RIG_VERSION = 1       # the base rig these were fitted to (build_base_rig.py)

# ----------------------------------------------------------- palette
# Grey values written into vertex COLOR (sRGB intent; the game shader
# treats COLOR as the displayed value). Kept to a few steps on purpose.
WHITE = 1.0     # blades, heads, metal: the weapon is white (brief)
WOOD = 0.82     # hafts and shafts: a step under white so heads pop
GRIP = 0.30     # wraps, grips: dark so the hand position reads
IRON = 0.55     # mechanisms: cams, hammers, locks
STRING = 0.12   # bow strings, cables
EDGE = 0.70     # accent default: a steel-grey bevel along cutting edges
GEM = 0.26      # accent default: dark gems / focus stones

BODY, ACCENT = 0, 1
STRING_MAT = 2  # bows only: the straight run of the string, its own surface so the
                # game can hide it and draw it bent to the draw hand (BWWeaponView)


def deg(a):
    return math.radians(a)


# ------------------------------------------------------------ builder
class WeaponMesh:
    """Collects islands in weapon space (x, f, u) and emits one Blender mesh
    with two material slots. Faces carry their own grey value (corner colour)."""

    def __init__(self):
        self.verts = []
        self.faces = []   # (indices, mat, value)
        self.string = None

    def v(self, p):
        self.verts.append(Vector(p))
        return len(self.verts) - 1

    def face(self, idx, mat, val):
        out = []
        for i in idx:
            if not out or out[-1] != i:
                out.append(i)
        if len(out) > 1 and out[0] == out[-1]:
            out.pop()
        if len(out) >= 3:
            self.faces.append((tuple(out), mat, val))

    # -- tubes, cones, rings ------------------------------------------
    def tube(self, pts, radii, sides=6, val=WHITE, mat=BODY, closed=False, ref=(1, 0, 0), phase=0.5):
        """Tube along a polyline; radius 0 at an end makes a cone apex.
        Parallel-transported ring frames, ngon caps."""
        pts = [Vector(p) for p in pts]
        if isinstance(radii, (int, float)):
            radii = [radii] * len(pts)
        n = len(pts)
        tans = []
        for i in range(n):
            if closed:
                t = pts[(i + 1) % n] - pts[i - 1]
            elif i == 0:
                t = pts[1] - pts[0]
            elif i == n - 1:
                t = pts[-1] - pts[-2]
            else:
                t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
            tans.append(t.normalized())
        ref = Vector(ref)
        if abs(ref.dot(tans[0])) > 0.9:
            ref = Vector((0, 1, 0)) if abs(tans[0].y) < 0.9 else Vector((0, 0, 1))
        nrm = None
        rings = []
        for c, t, r in zip(pts, tans, radii):
            nrm = (ref if nrm is None else nrm)
            nrm = (nrm - t * nrm.dot(t)).normalized()
            b = t.cross(nrm)
            if r <= 1e-6:
                rings.append([self.v(c)])
                continue
            rings.append([self.v(c + (nrm * math.cos(a) + b * math.sin(a)) * r)
                          for a in (2 * math.pi * (k + phase) / sides for k in range(sides))])
        pairs = list(zip(rings, rings[1:]))
        if closed:
            pairs.append((rings[-1], rings[0]))
        for r0, r1 in pairs:
            if len(r0) == 1 and len(r1) == 1:
                continue
            if len(r0) == 1:
                for k in range(sides):
                    self.face((r0[0], r1[k], r1[(k + 1) % sides]), mat, val)
            elif len(r1) == 1:
                for k in range(sides):
                    self.face((r0[k], r0[(k + 1) % sides], r1[0]), mat, val)
            else:
                for k in range(sides):
                    k2 = (k + 1) % sides
                    self.face((r0[k], r0[k2], r1[k2], r1[k]), mat, val)
        if not closed:
            if len(rings[0]) > 1:
                self.face(tuple(reversed(rings[0])), mat, val)
            if len(rings[-1]) > 1:
                self.face(tuple(rings[-1]), mat, val)

    def ring(self, center, radius, tube_r, axis="x", segs=8, sides=5, val=WHITE, mat=BODY):
        c = Vector(center)
        pts = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            if axis == "x":      # ring lies in the (f, u) plane
                pts.append(c + Vector((0, math.cos(a), math.sin(a))) * radius)
            else:                # ring lies in the (x, f) plane
                pts.append(c + Vector((math.cos(a), math.sin(a), 0)) * radius)
        self.tube(pts, tube_r, sides=sides, val=val, mat=mat, closed=True,
                  ref=(1, 0, 0) if axis == "x" else (0, 0, 1))

    def ellipsoid(self, center, radii, sides=6, rings=4, val=WHITE, mat=BODY):
        c = Vector(center)
        rx, rf, ru = radii if isinstance(radii, (tuple, list)) else (radii,) * 3
        top = self.v(c + Vector((0, 0, ru)))
        lat = []
        for i in range(1, rings):
            th = math.pi * i / rings
            lat.append([self.v(c + Vector((rx * math.sin(th) * math.cos(2 * math.pi * (j + 0.5) / sides),
                                           rf * math.sin(th) * math.sin(2 * math.pi * (j + 0.5) / sides),
                                           ru * math.cos(th)))) for j in range(sides)])
        bot = self.v(c - Vector((0, 0, ru)))
        for j in range(sides):
            k = (j + 1) % sides
            self.face((top, lat[0][j], lat[0][k]), mat, val)
            self.face((bot, lat[-1][k], lat[-1][j]), mat, val)
        for i in range(len(lat) - 1):
            for j in range(sides):
                k = (j + 1) % sides
                self.face((lat[i][j], lat[i + 1][j], lat[i + 1][k], lat[i][k]), mat, val)

    # -- boxes ---------------------------------------------------------
    def hexa(self, c8, val=WHITE, mat=BODY):
        """8 corners: bottom quad then top quad, same winding."""
        i = [self.v(p) for p in c8]
        for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face(tuple(i[k] for k in f), mat, val)

    def box(self, center, half, val=WHITE, mat=BODY):
        cx, cf, cu = center
        hx, hf, hu = half
        bot = [(cx - hx, cf - hf, cu - hu), (cx + hx, cf - hf, cu - hu), (cx + hx, cf + hf, cu - hu), (cx - hx, cf + hf, cu - hu)]
        top = [(x, f, cu + hu) for x, f, _ in bot]
        self.hexa(bot + top, val, mat)

    def slab(self, p0, p1, hf, hx, val=WHITE, mat=BODY):
        """A box running from p0 to p1 in the (f, u) plane, hf thick along
        its in-plane normal and hx along x (angled grips)."""
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        n = Vector((0, -d.z, d.y)) * hf if abs(d.x) < 0.99 else Vector((0, 1, 0)) * hf
        X = Vector((hx, 0, 0))
        bot = [p0 - X - n, p0 + X - n, p0 + X + n, p0 - X + n]
        top = [p1 - X - n, p1 + X - n, p1 + X + n, p1 - X + n]
        self.hexa(bot + top, val, mat)

    # -- bevelled plates (blades, axe heads, flukes, crescents) ---------
    def plate(self, outline, h, bevel=0.02, edges=(), val=WHITE, edge_val=EDGE,
              o=(0, 0, 0), A=(0, 1, 0), B=(0, 0, 1), N=(1, 0, 0), blunt=0.75, edge_mat=ACCENT):
        """A 2D outline (a, b) extruded to half-thickness h along N, with a
        bevel band of width `bevel` all round. Segment i runs from point i to
        i+1; segments listed in `edges` are cutting edges: their bevel faces
        go on the accent surface and their rim closes to a sharp edge."""
        pts = [Vector(p) for p in outline]
        n = len(pts)
        edge = [i in edges for i in range(n)]
        area = sum(pts[i].x * pts[(i + 1) % n].y - pts[(i + 1) % n].x * pts[i].y for i in range(n))
        if area < 0:
            pts = pts[::-1]
            edge = [edge[(n - 2 - j) % n] for j in range(n)]
        o, A, B, N = Vector(o), Vector(A), Vector(B), Vector(N)

        def P(a, b, w):
            return o + A * a + B * b + N * w

        ins = []
        for i in range(n):
            ep = (pts[i] - pts[i - 1]).normalized()
            en = (pts[(i + 1) % n] - pts[i]).normalized()
            npv = Vector((-ep.y, ep.x))
            nnv = Vector((-en.y, en.x))
            bis = npv + nnv
            bis = nnv if bis.length < 1e-6 else bis.normalized()
            m = min(bevel / max(bis.dot(nnv), 0.3), bevel * 2.4)
            ins.append(pts[i] + bis * m)
        sharp = [edge[i - 1] or edge[i] for i in range(n)]
        he = [0.0 if s else h * blunt for s in sharp]
        tq = [self.v(P(q.x, q.y, h)) for q in ins]
        bq = [self.v(P(q.x, q.y, -h)) for q in ins]
        tp, bp = [], []
        for p, e in zip(pts, he):
            t = self.v(P(p.x, p.y, e))
            tp.append(t)
            bp.append(t if e == 0.0 else self.v(P(p.x, p.y, -e)))
        for tri in tessellate_polygon([[Vector((q.x, q.y, 0)) for q in ins]]):
            a, b, c = tri
            self.face((tq[a], tq[b], tq[c]), BODY, val)
            self.face((bq[c], bq[b], bq[a]), BODY, val)
        for i in range(n):
            j = (i + 1) % n
            m, cv = (edge_mat, edge_val) if edge[i] else (BODY, val)
            self.face((tp[i], tp[j], tq[j], tq[i]), m, cv)
            self.face((bp[j], bp[i], bq[i], bq[j]), m, cv)
            self.face((tp[i], bp[i], bp[j], tp[j]), m, cv)

    # -- emit -----------------------------------------------------------
    def build(self, name, materials):
        me = bpy.data.meshes.new(name)
        me.from_pydata([(p.x, -p.y, p.z) for p in self.verts], [], [f for f, _, _ in self.faces])
        for i, (_, m, _) in enumerate(self.faces):
            me.polygons[i].material_index = m
        for m in materials:
            me.materials.append(m)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = True
        col = me.color_attributes.new("Color", 'BYTE_COLOR', 'CORNER')
        for poly, (_, _, val) in zip(me.polygons, self.faces):
            for li in poly.loop_indices:
                col.data[li].color = (val, val, val, 1.0)
        me.color_attributes.active_color = col
        me.color_attributes.render_color_index = 0
        me.update()
        return me


def mirror_f(outline):
    return [(-a, b) for a, b in outline]


# shared hilt pieces ----------------------------------------------------
def grip(w, u0, u1, r=0.026, val=GRIP, sides=6):
    w.tube([(0, 0, u0), (0, 0, u1)], [r, r * 0.94], sides=sides, val=val)


def haft(w, u0, u1, r, val=WOOD, sides=6):
    w.tube([(0, 0, u0), (0, 0, u1)], [r, r * 0.92], sides=sides, val=val)


# ------------------------------------------------------------ weapons
# Each builder fills a WeaponMesh and returns its metadata in weapon space
# (x, f, u). Points: tip / trail_base (trail ribbon), second (other hand's
# target), aura (particle anchors along the business end).

def build_sword(w):
    grip(w, -0.115, 0.105)
    w.ellipsoid((0, 0, -0.15), (0.042, 0.042, 0.038), sides=6, rings=3)
    w.plate([(-0.17, 0.10), (0.17, 0.10), (0.20, 0.165), (0.0, 0.145), (-0.20, 0.165)], h=0.036, bevel=0.012)
    w.plate([(0.068, 0.15), (0.068, 0.80), (0.0, 0.97), (-0.068, 0.80), (-0.068, 0.15)],
            h=0.03, bevel=0.03, edges=(0, 1, 2, 3))
    return dict(tip=(0, 0, 0.97), trail_base=(0, 0, 0.20),
                aura=[(0, 0, u) for u in (0.22, 0.42, 0.62, 0.82)] + [(0, 0.17, 0.13), (0, -0.17, 0.13)])


def build_scimitar(w):
    w.tube([(0, 0.012, -0.11), (0, 0.0, 0.0), (0, 0.0, 0.10)], [0.025, 0.025, 0.024], val=GRIP)
    w.ellipsoid((0, -0.03, -0.135), (0.03, 0.05, 0.032), sides=6, rings=3)
    w.plate([(-0.07, 0.095), (0.09, 0.095), (0.11, 0.14), (-0.08, 0.135)], h=0.034, bevel=0.01)
    front = [(0.05, 0.13), (0.062, 0.32), (0.078, 0.52), (0.078, 0.70), (0.045, 0.86), (-0.03, 0.97), (-0.12, 1.02)]
    spine = [(-0.15, 0.90), (-0.11, 0.72), (-0.065, 0.52), (-0.04, 0.32), (-0.038, 0.13)]
    w.plate(front + spine, h=0.028, bevel=0.028, edges=(0, 1, 2, 3, 4, 5))
    return dict(tip=(0, -0.12, 1.02), trail_base=(0, 0, 0.18),
                aura=[(0, 0.0, 0.25), (0, 0.01, 0.50), (0, -0.02, 0.72), (0, -0.08, 0.92)])


def build_flamberge(w):
    grip(w, -0.34, 0.13, r=0.028)
    w.tube([(0, 0, -0.11), (0, 0, -0.08)], 0.034, val=WHITE)          # grip collar between the hands
    w.ellipsoid((0, 0, -0.38), (0.052, 0.052, 0.048), sides=6, rings=3)
    w.plate([(-0.24, 0.12), (0.24, 0.12), (0.31, 0.24), (0.22, 0.19), (-0.22, 0.19), (-0.31, 0.24)],
            h=0.04, bevel=0.014)
    out = [(0.045, 0.18), (0.045, 0.30), (0.115, 0.33), (0.07, 0.37)]
    period, amp, half = 0.17, 0.03, 0.074
    u0, u_end, tip_u = 0.38, 1.36, 1.56
    fr, bk = [], []
    k = 0
    while True:
        u = u0 + k * period / 4
        if u > u_end + 1e-6:
            break
        c = amp * math.sin(2 * math.pi * (u - u0) / period)
        taper = 1.0 if u < 1.12 else 1.0 - 0.35 * (u - 1.12) / (u_end - 1.12)
        fr.append((c + half * taper, u))
        bk.append((c - half * taper, u))
        k += 1
    pts = out + fr + [(0.0, tip_u)] + bk[::-1] + [(-0.07, 0.37), (-0.115, 0.33), (-0.045, 0.30), (-0.045, 0.18)]
    nf = len(fr)
    first = len(out) - 1                     # segment from the lug into the first wave point
    edges = tuple(range(first + 1, first + 1 + nf)) + tuple(range(first + 1 + nf, first + 1 + 2 * nf))
    w.plate(pts, h=0.032, bevel=0.026, edges=edges)
    return dict(tip=(0, 0, tip_u), trail_base=(0, 0, 0.24), second=(0, 0, -0.24),
                aura=[(0, 0, u) for u in (0.30, 0.55, 0.80, 1.05, 1.30, 1.50)])


def build_axe(w):
    haft(w, -0.20, 0.74, 0.026)
    w.ellipsoid((0, 0, -0.21), 0.034, sides=6, rings=3, val=WOOD)
    grip(w, -0.10, 0.10, r=0.03)
    w.plate([(-0.03, 0.55), (0.10, 0.57), (0.20, 0.45), (0.31, 0.42), (0.33, 0.62), (0.29, 0.82),
             (0.18, 0.77), (0.10, 0.71), (-0.03, 0.71)], h=0.036, bevel=0.026, edges=(3, 4))
    w.box((0, -0.065, 0.63), (0.042, 0.04, 0.055))
    return dict(tip=(0, 0.33, 0.62), trail_base=(0, 0, 0.40),
                aura=[(0, 0.31, 0.45), (0, 0.33, 0.62), (0, 0.29, 0.80), (0, 0.12, 0.64), (0, 0, 0.30)])


def build_double_axe(w):
    haft(w, -0.40, 1.30, 0.031)
    w.ellipsoid((0, 0, -0.42), 0.04, sides=6, rings=3)
    grip(w, -0.33, 0.10, r=0.034)
    blade = [(0.03, 0.98), (0.16, 1.03), (0.34, 0.82), (0.46, 1.10), (0.34, 1.38), (0.16, 1.19), (0.03, 1.24)]
    w.plate(blade, h=0.038, bevel=0.03, edges=(2, 3))
    w.plate(mirror_f(blade), h=0.038, bevel=0.03, edges=(2, 3))
    w.box((0, 0, 1.11), (0.052, 0.05, 0.15))
    w.tube([(0, 0, 1.26), (0, 0, 1.46)], [0.04, 0.0], sides=4)
    return dict(tip=(0, 0.46, 1.10), trail_base=(0, 0, 0.70), second=(0, 0, -0.27),
                aura=[(0, 0.40, 0.92), (0, 0.46, 1.10), (0, 0.40, 1.28), (0, -0.40, 0.92), (0, -0.46, 1.10),
                      (0, -0.40, 1.28), (0, 0, 1.40)])


def build_hatchet(w):
    haft(w, -0.13, 0.44, 0.024)
    grip(w, -0.09, 0.09, r=0.028)
    w.plate([(-0.02, 0.31), (0.08, 0.32), (0.16, 0.27), (0.21, 0.37), (0.18, 0.48), (0.08, 0.44), (-0.02, 0.45)],
            h=0.032, bevel=0.022, edges=(2, 3))
    w.box((0, -0.07, 0.38), (0.036, 0.05, 0.05))
    return dict(tip=(0, 0.21, 0.37), trail_base=(0, 0, 0.22),
                aura=[(0, 0.18, 0.28), (0, 0.21, 0.38), (0, 0.17, 0.47), (0, -0.08, 0.38)])


def build_warhammer(w):
    haft(w, -0.36, 1.04, 0.033)
    w.ellipsoid((0, 0, -0.38), 0.042, sides=6, rings=3)
    grip(w, -0.30, 0.10, r=0.036)
    w.box((0, 0.0, 1.12), (0.105, 0.16, 0.125))
    w.box((0, 0.185, 1.12), (0.09, 0.03, 0.105), val=EDGE, mat=ACCENT)   # striking face
    w.tube([(0, -0.16, 1.12), (0, -0.40, 1.04)], [0.07, 0.0], sides=4)    # back spike
    w.tube([(0, 0, 1.24), (0, 0, 1.44)], [0.05, 0.0], sides=4)
    w.tube([(0, 0, 0.90), (0, 0, 1.00)], 0.045, val=WHITE)              # collar
    return dict(tip=(0, 0.215, 1.12), trail_base=(0, 0, 0.70), second=(0, 0, -0.24),
                aura=[(0, 0.2, 1.02), (0, 0.2, 1.22), (0, -0.05, 1.25), (0, -0.36, 1.06), (0, 0.0, 1.0)])


def build_anchor(w):
    w.tube([(0, 0, -0.38), (0, 0, 1.18)], [0.037, 0.044], sides=6)
    grip(w, -0.26, 0.10, r=0.044)
    w.ring((0, 0, -0.48), 0.095, 0.024, axis="x", segs=8, sides=5)
    w.tube([(-0.26, 0, -0.32), (0.26, 0, -0.32)], 0.03, sides=6)        # stock, across x
    w.ellipsoid((-0.27, 0, -0.32), 0.042, sides=6, rings=3)
    w.ellipsoid((0.27, 0, -0.32), 0.042, sides=6, rings=3)
    w.ellipsoid((0, 0, 1.20), (0.065, 0.09, 0.07), sides=6, rings=3)   # crown
    for s in (1, -1):
        arm = [(0, s * f, u) for f, u in ((0.03, 1.21), (0.15, 1.19), (0.28, 1.10), (0.37, 0.98), (0.41, 0.86))]
        w.tube(arm, [0.045, 0.043, 0.04, 0.036, 0.032], sides=6)
        fl = [(0.41, 0.66), (0.50, 0.84), (0.42, 0.96), (0.32, 0.86)]
        w.plate(fl if s > 0 else mirror_f(fl), h=0.032, bevel=0.022, edges=(0, 3) if s > 0 else (0, 3))
    w.tube([(0, 0, 1.24), (0, 0, 1.36)], [0.035, 0.0], sides=4)
    return dict(tip=(0, 0, 1.36), trail_base=(0, 0, 0.60), second=(0, 0, -0.17),
                aura=[(0, 0, 1.25), (0, 0.42, 0.72), (0, -0.42, 0.72), (0, 0.30, 1.10), (0, -0.30, 1.10), (0, 0, 0.8)])


def build_lance(w):
    w.ellipsoid((0, 0, -0.47), (0.042, 0.042, 0.06), sides=6, rings=3)
    grip(w, -0.44, 0.06, r=0.032)
    w.tube([(0, 0, 0.03), (0, 0, 0.08), (0, 0, 0.36)], [0.05, 0.17, 0.068], sides=8)   # vamplate
    w.tube([(0, 0, 0.36), (0, 0, 1.0), (0, 0, 1.76)], [0.068, 0.05, 0.03], sides=8)
    w.tube([(0, 0, 1.76), (0, 0, 2.08)], [0.03, 0.0], sides=8, val=EDGE, mat=ACCENT)
    return dict(tip=(0, 0, 2.08), trail_base=(0, 0, 0.60), second=(0, 0, -0.32),
                aura=[(0, 0, u) for u in (0.12, 0.55, 1.0, 1.45, 1.85, 2.02)])


def build_javelin(w):
    w.tube([(0, 0, -0.80), (0, 0, 0.86)], [0.018, 0.019], sides=6, val=WOOD)
    w.tube([(0, 0, -0.80), (0, 0, -0.90)], [0.02, 0.0], sides=4)
    grip(w, -0.09, 0.09, r=0.026)
    w.tube([(0, 0, 0.82), (0, 0, 0.96)], [0.022, 0.058], sides=4, phase=0.0)
    w.tube([(0, 0, 0.96), (0, 0, 1.16)], [0.058, 0.0], sides=4, phase=0.0, val=EDGE, mat=ACCENT)
    return dict(tip=(0, 0, 1.16), trail_base=(0, 0, 0.30),
                aura=[(0, 0, u) for u in (0.0, 0.45, 0.90, 1.08)])


def build_halberd(w):
    haft(w, -0.60, 1.46, 0.028)
    w.tube([(0, 0, -0.60), (0, 0, -0.74)], [0.028, 0.0], sides=4)
    grip(w, -0.10, 0.10, r=0.032)
    grip(w, 0.40, 0.56, r=0.032)
    w.tube([(0, 0, 1.04), (0, 0, 1.44)], 0.038, val=WHITE)
    w.tube([(0, 0, 1.42), (0, 0, 1.53)], [0.032, 0.055], sides=4, phase=0.0)
    w.tube([(0, 0, 1.53), (0, 0, 1.82)], [0.055, 0.0], sides=4, phase=0.0, val=EDGE, mat=ACCENT)
    w.plate([(0.02, 1.10), (0.12, 1.08), (0.29, 0.99), (0.35, 1.22), (0.30, 1.42), (0.13, 1.35), (0.02, 1.38)],
            h=0.034, bevel=0.026, edges=(2, 3))
    w.plate([(-0.02, 1.18), (-0.02, 1.30), (-0.10, 1.29), (-0.28, 1.42), (-0.16, 1.21)],
            h=0.03, bevel=0.016, edges=(2, 3))
    return dict(tip=(0, 0, 1.82), trail_base=(0, 0, 0.90), second=(0, 0, 0.48),
                aura=[(0, 0, 1.70), (0, 0.33, 1.05), (0, 0.35, 1.25), (0, 0.30, 1.40), (0, -0.25, 1.38), (0, 0, 1.1)])


def build_glaive(w):
    haft(w, -0.58, 1.20, 0.028)
    w.ellipsoid((0, 0, -0.60), 0.036, sides=6, rings=3)
    grip(w, -0.10, 0.10, r=0.032)
    grip(w, 0.40, 0.56, r=0.032)
    w.tube([(0, 0, 1.08), (0, 0, 1.22)], [0.036, 0.044], val=WHITE)
    w.plate([(-0.05, 1.19), (0.06, 1.19), (0.10, 1.36), (0.14, 1.56), (0.15, 1.74), (0.11, 1.88), (0.02, 1.98),
             (0.0, 1.82), (-0.03, 1.68), (-0.13, 1.62), (-0.05, 1.52)],
            h=0.03, bevel=0.028, edges=(1, 2, 3, 4, 5))
    return dict(tip=(0, 0.02, 1.98), trail_base=(0, 0, 1.0), second=(0, 0, 0.48),
                aura=[(0, 0.10, 1.35), (0, 0.14, 1.55), (0, 0.14, 1.75), (0, 0.04, 1.92), (0, -0.10, 1.62)])


def _dagger_hilt(w):
    grip(w, -0.075, 0.065, r=0.023)


def build_dagger(w):
    _dagger_hilt(w)
    w.ellipsoid((0, 0, -0.10), 0.032, sides=6, rings=3)
    w.plate([(-0.085, 0.06), (0.085, 0.06), (0.105, 0.10), (0.0, 0.09), (-0.105, 0.10)], h=0.027, bevel=0.01)
    w.plate([(0.046, 0.09), (0.052, 0.25), (0.0, 0.42), (-0.052, 0.25), (-0.046, 0.09)],
            h=0.023, bevel=0.02, edges=(0, 1, 2, 3))
    return dict(tip=(0, 0, 0.42), trail_base=(0, 0, 0.12),
                aura=[(0, 0, 0.15), (0, 0, 0.27), (0, 0, 0.38)])


def build_jagged_dagger(w):
    _dagger_hilt(w)
    w.tube([(0, 0, -0.075), (0, 0, -0.15)], [0.028, 0.0], sides=4)   # spike pommel
    w.plate([(-0.07, 0.06), (0.09, 0.06), (0.14, 0.12), (0.08, 0.10), (-0.07, 0.10)], h=0.027, bevel=0.01)
    front = [(0.05, 0.09), (0.068, 0.20), (0.064, 0.31), (0.025, 0.41), (-0.05, 0.47)]
    spine = [(-0.045, 0.38), (-0.09, 0.355), (-0.05, 0.31), (-0.095, 0.275), (-0.052, 0.235),
             (-0.095, 0.195), (-0.05, 0.155), (-0.05, 0.09)]
    pts = front + spine
    w.plate(pts, h=0.024, bevel=0.012, edges=(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10))
    return dict(tip=(0, -0.05, 0.47), trail_base=(0, 0, 0.12),
                aura=[(0, 0, 0.16), (0, -0.04, 0.28), (0, 0.0, 0.40)])


# bows: held in the LEFT hand (socket_offhand_l). Limbs along u, the bow's
# back faces forward (+f), the string sits behind it (-f, the archer's side).
def _string(w, pts, mat=STRING_MAT):
    w.tube(pts, 0.0065, sides=3, val=STRING, mat=mat)
    if mat == STRING_MAT:
        w.string = (pts[0], pts[-1])


def build_shortbow(w):
    n = 9
    up = [(0, -0.17 * (u / 0.5) ** 2, u) for u in (0.08 + 0.42 * k / (n - 1) for k in range(n))]
    for s in (1, -1):
        w.tube([(x, f, s * u) for x, f, u in up], [0.028 - 0.013 * k / (n - 1) for k in range(n)], sides=6, val=WHITE)
        w.ellipsoid((0, -0.17, s * 0.5), 0.022, sides=5, rings=3, val=EDGE, mat=ACCENT)
    grip(w, -0.11, 0.11, r=0.032)
    _string(w, [(0, -0.172, 0.5), (0, -0.172, -0.5)])
    return dict(tip=(0, 0.04, 0.05), trail_base=(0, -0.17, 0.0), second=(0, -0.172, 0.0),
                aura=[(0, -0.17, 0.5), (0, -0.17, -0.5), (0, -0.05, 0.3), (0, -0.05, -0.3), (0, 0.03, 0.0)])


def build_recurve_bow(w):
    w.plate([(-0.035, -0.22), (0.035, -0.22), (0.055, -0.08), (0.055, 0.08), (0.035, 0.22), (-0.035, 0.22),
             (-0.05, 0.06), (-0.05, -0.06)], h=0.03, bevel=0.012)
    grip(w, -0.075, 0.075, r=0.036)
    limb = [(0.0, 0.20), (-0.05, 0.33), (-0.11, 0.46), (-0.16, 0.57), (-0.165, 0.63), (-0.135, 0.68), (-0.08, 0.71)]
    radii = [0.03, 0.026, 0.023, 0.02, 0.018, 0.016, 0.014]
    for s in (1, -1):
        w.tube([(0, f, s * u) for f, u in limb], radii, sides=6)
        w.ellipsoid((0, -0.075, s * 0.715), 0.02, sides=5, rings=3, val=EDGE, mat=ACCENT)
    _string(w, [(0, -0.085, 0.70), (0, -0.183, 0.60)], mat=BODY)       # over the curls: stays put
    _string(w, [(0, -0.183, 0.60), (0, -0.183, -0.60)])
    _string(w, [(0, -0.183, -0.60), (0, -0.085, -0.70)], mat=BODY)
    return dict(tip=(0, 0.06, 0.05), trail_base=(0, -0.18, 0.0), second=(0, -0.183, 0.0),
                aura=[(0, -0.08, 0.71), (0, -0.08, -0.71), (0, -0.11, 0.46), (0, -0.11, -0.46), (0, 0.04, 0.0)])


def build_compound_bow(w):
    w.plate([(0.0, -0.32), (0.06, -0.27), (0.06, -0.12), (0.02, -0.07), (0.02, 0.09), (0.09, 0.13), (0.09, 0.27),
             (0.03, 0.33), (-0.035, 0.31), (-0.035, 0.17), (-0.065, 0.13), (-0.065, -0.09), (-0.035, -0.13),
             (-0.035, -0.28)], h=0.03, bevel=0.012)
    grip(w, -0.07, 0.07, r=0.034)
    for s in (1, -1):
        quad = [(-0.03, 0.27), (0.03, 0.31), (-0.15, 0.52), (-0.20, 0.47)]
        for xo in (0.03, -0.03):
            w.plate([(f, s * u) for f, u in quad], h=0.011, bevel=0.006, o=(xo, 0, 0))
        w.tube([(-0.035, -0.18, s * 0.50), (0.035, -0.18, s * 0.50)], 0.064, sides=8, val=IRON)
    w.tube([(0, 0.06, -0.03), (0, 0.32, -0.03)], 0.018, sides=6)
    w.ellipsoid((0, 0.34, -0.03), (0.036, 0.04, 0.036), sides=6, rings=3, val=GRIP)
    w.box((0, 0.12, 0.20), (0.012, 0.03, 0.03), val=GEM, mat=ACCENT)           # sight
    _string(w, [(0, -0.245, 0.50), (0, -0.245, -0.50)])
    _string(w, [(0, -0.13, 0.54), (0.0, -0.22, -0.46)], mat=BODY)     # the cable
    return dict(tip=(0, 0.08, 0.05), trail_base=(0, -0.24, 0.0), second=(0, -0.245, 0.0),
                aura=[(0, -0.18, 0.5), (0, -0.18, -0.5), (0, 0.32, -0.03), (0, 0.12, 0.2), (0, 0.0, 0.25)])


# pistols: grip through the fist, barrel forward (+f) above it.
def build_pistol(w):   # the revolver
    w.slab((0, -0.055, -0.13), (0, -0.008, 0.07), 0.034, 0.026, val=GRIP)
    w.box((0, 0.035, 0.09), (0.027, 0.075, 0.036))
    w.tube([(0, 0.025, 0.105), (0, 0.135, 0.105)], 0.05, sides=6, phase=0.0)
    w.tube([(0, 0.13, 0.118), (0, 0.39, 0.118)], 0.021, sides=6)
    w.tube([(0, 0.37, 0.118), (0, 0.40, 0.118)], 0.026, sides=6, val=EDGE, mat=ACCENT)
    w.box((0, 0.37, 0.145), (0.006, 0.012, 0.012))
    w.box((0, -0.045, 0.14), (0.012, 0.018, 0.026), val=IRON)
    w.tube([(0, 0.02, 0.055), (0, 0.045, 0.0), (0, 0.10, 0.02), (0, 0.105, 0.055)], 0.008, sides=4, val=IRON)
    return dict(tip=(0, 0.40, 0.118), trail_base=(0, 0.13, 0.118),
                aura=[(0, 0.40, 0.118), (0, 0.08, 0.105), (0, 0.25, 0.118)])


def build_flintlock(w):
    w.tube([(0, 0.0, 0.10), (0, 0.50, 0.10)], [0.026, 0.021], sides=8)
    w.tube([(0, 0.48, 0.10), (0, 0.53, 0.10)], [0.028, 0.032], sides=8, val=EDGE, mat=ACCENT)
    w.tube([(0, 0.0, 0.074), (0, 0.40, 0.074)], [0.022, 0.018], sides=6, val=IRON)          # fore-stock
    w.tube([(0, 0.02, 0.085), (0, -0.04, 0.0), (0, -0.085, -0.08), (0, -0.105, -0.13)],
           [0.034, 0.03, 0.03, 0.032], sides=6, val=IRON)
    w.ellipsoid((0, -0.115, -0.165), (0.044, 0.05, 0.048), sides=6, rings=3)                # butt cap
    w.box((0, 0.035, 0.095), (0.03, 0.05, 0.022), val=WHITE)                                # lock plate
    w.tube([(0, 0.0, 0.11), (0, -0.025, 0.16), (0, 0.005, 0.195)], 0.012, sides=4, val=IRON)  # cock
    w.box((0, 0.06, 0.135), (0.012, 0.012, 0.026))                                          # frizzen
    w.tube([(0, 0.055, 0.055), (0, 0.065, 0.005), (0, 0.0, 0.0), (0, -0.03, 0.04)], 0.007, sides=4, val=IRON)
    w.tube([(0, 0.06, 0.053), (0, 0.45, 0.053)], 0.007, sides=4, val=GRIP)                  # ramrod
    return dict(tip=(0, 0.53, 0.10), trail_base=(0, 0.10, 0.10),
                aura=[(0, 0.53, 0.10), (0, 0.30, 0.10), (0, -0.115, -0.165), (0, 0.0, 0.17)])


def build_m1911(w):
    w.slab((0, -0.09, -0.15), (0, -0.032, 0.06), 0.041, 0.031, val=GRIP)
    w.box((0, 0.10, 0.118), (0.029, 0.168, 0.037))                     # slide
    w.box((0, 0.065, 0.066), (0.026, 0.12, 0.02))                      # frame
    w.box((0, 0.20, 0.118), (0.0295, 0.03, 0.014), val=EDGE, mat=ACCENT)  # ejection port band
    w.tube([(0, 0.265, 0.118), (0, 0.285, 0.118)], 0.017, sides=6, val=IRON)
    w.box((0, -0.075, 0.135), (0.012, 0.016, 0.016), val=IRON)
    w.box((0, -0.055, 0.162), (0.022, 0.008, 0.008), val=IRON)
    w.box((0, 0.25, 0.162), (0.006, 0.008, 0.008), val=IRON)
    w.tube([(0, 0.035, 0.048), (0, 0.035, 0.002), (0, 0.125, 0.002), (0, 0.125, 0.048)], 0.009, sides=4, val=IRON)
    return dict(tip=(0, 0.285, 0.118), trail_base=(0, 0.0, 0.118),
                aura=[(0, 0.285, 0.118), (0, 0.10, 0.155), (0, 0.10, 0.08)])


def build_staff(w):
    w.tube([(0, 0, -0.72), (0.012, 0.01, -0.2), (-0.012, -0.01, 0.4), (0.01, 0.0, 1.0), (0, 0, 1.30)],
           [0.027, 0.031, 0.031, 0.033, 0.038], sides=6, val=WOOD)
    w.ellipsoid((0, 0, -0.72), 0.035, sides=6, rings=3, val=WOOD)
    grip(w, -0.10, 0.10, r=0.035)
    grip(w, 0.40, 0.56, r=0.035)
    w.ellipsoid((-0.005, -0.005, 0.80), (0.045, 0.045, 0.06), sides=6, rings=3, val=WOOD)   # knot
    for a in (90, 210, 330):
        d = Vector((math.cos(deg(a)), math.sin(deg(a)), 0))
        pts = [Vector((0, 0, 1.26)) + d * r + Vector((0, 0, h)) for r, h in
               ((0.0, 0.0), (0.06, 0.10), (0.10, 0.20), (0.08, 0.31), (0.025, 0.38))]
        w.tube(pts, [0.026, 0.022, 0.018, 0.014, 0.0], sides=5, val=WOOD)
    w.tube([(0, 0, 1.38), (0, 0, 1.48), (0, 0, 1.60)], [0.0, 0.08, 0.0], sides=6, val=GEM, mat=ACCENT)
    return dict(tip=(0, 0, 1.64), trail_base=(0, 0, 1.0), second=(0, 0, 0.48),
                aura=[(0, 0, 1.48), (0, 0.09, 1.46), (0, -0.09, 1.46), (0, 0, 1.62), (0, 0, 1.2)])


def build_moon_staff(w):
    w.tube([(0, 0, -0.72), (0, 0, 1.24)], [0.026, 0.03], sides=6)
    w.tube([(0, 0, -0.72), (0, 0, -0.84)], [0.026, 0.0], sides=4)
    grip(w, -0.10, 0.10, r=0.033)
    grip(w, 0.40, 0.56, r=0.033)
    w.ellipsoid((0, 0, 1.22), (0.05, 0.05, 0.04), sides=6, rings=3)
    w.ring((0, 0, 0.97), 0.036, 0.012, axis="z", segs=6, sides=4, val=WHITE)
    c1, r1 = Vector((0, 1.46)), 0.27
    c2, r2 = Vector((0, 1.56)), 0.225
    d = (c2 - c1).length
    a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    hh = math.sqrt(r1 * r1 - a * a)
    horn_r = Vector((hh, c1.y + a))
    th1 = math.atan2(horn_r.y - c1.y, horn_r.x)
    th2 = math.atan2(horn_r.y - c2.y, horn_r.x)
    outer = [c1 + Vector((math.cos(t), math.sin(t))) * r1
             for t in (th1 - (2 * th1 + math.pi) * k / 12 for k in range(13))]          # right horn -> left horn
    inner = [c2 + Vector((math.cos(t), math.sin(t))) * r2
             for t in (math.pi - th2 + (math.pi + 2 * th2) * k / 10 for k in range(1, 10))]  # left -> right, through the bottom
    pts = [(p.x, p.y) for p in outer + inner]
    w.plate(pts, h=0.038, bevel=0.024, edges=tuple(range(0, 12)))
    w.tube([(0, 0, 1.44), (0, 0, 1.53), (0, 0, 1.63)], [0.0, 0.065, 0.0], sides=6, val=GEM, mat=ACCENT)
    return dict(tip=(0, 0, 1.63), trail_base=(0, 0, 1.0), second=(0, 0, 0.48),
                aura=[(0, 0, 1.53), (0, 0.24, 1.66), (0, -0.24, 1.66), (0, 0.22, 1.32), (0, -0.22, 1.32), (0, 0, 1.2)])


# fists (D76): worn on both hands. Each builder models the RIGHT hand's piece
# in a hand-local frame (lx = along the knuckle row, lf = the back of the
# hand, lu = the punching direction, out through the knuckles); fist_frame()
# turns that into weapon space for the rest pose of hand_r, where the socket
# is world-aligned but the hand bone points down and out (35 deg A-pose).
# The left piece is the same mesh mirrored in x (socket_offhand_l), exported
# as <id>_l.glb with its winding rebuilt, so the hull stays whole.
#
# The rig's fist is an ink ball (r 0.043) with a 0.018 white hull: a covering
# piece (wraps, gauntlet shell) is >= 0.064 so no white rim shows through.

def _rig_hand_dir(side=-1.0):
    """The hand bone's rest direction (wrist -> knuckles) in weapon space
    (x, f, u), from build_base_rig.arm_points (A-pose 35 deg, wrist a touch
    forward)."""
    a = math.radians(35.0)
    d = Vector((side * math.sin(a), 0.08, -math.cos(a)))   # Blender (x, -y, z) -> (x, f, u)
    return d.normalized()


def fist_frame():
    """(Rx, Bf, Ku): weapon-space axes for hand-local (lx, lf, lu), right hand."""
    k = _rig_hand_dir(-1.0)
    lateral = Vector((-1.0, 0.0, 0.0))            # the back of a relaxed right hand faces out
    b = (lateral - k * lateral.dot(k)).normalized()
    r = b.cross(k).normalized()                   # same handedness as (x, f, u)
    return r, b, k


def _to_fist(w, start, pts):
    """Map the verts added since `start` (and the points dict) from the
    hand-local frame into weapon space."""
    r, b, k = fist_frame()

    def m(p):
        p = Vector(p)
        return r * p.x + b * p.y + k * p.z

    for i in range(start, len(w.verts)):
        w.verts[i] = m(w.verts[i])
    out = {}
    for key, val in pts.items():
        out[key] = [tuple(m(q)) for q in val] if key == "aura" else tuple(m(val))
    return out


def _band(w, lu, radius, tube_r, val=EDGE, mat=ACCENT, segs=8, squash=1.0):
    """A ring round the lu axis (a wrap band round the fist or the wrist)."""
    pts = [(radius * math.cos(2 * math.pi * (k + 0.5) / segs),
            radius * squash * math.sin(2 * math.pi * (k + 0.5) / segs), lu) for k in range(segs)]
    w.tube(pts, tube_r, sides=3, val=val, mat=mat, closed=True, ref=(0, 0, 1))


def build_hand_wraps(w):
    s = len(w.verts)
    w.ellipsoid((0, 0.0, 0.006), (0.068, 0.064, 0.066), sides=8, rings=5)          # the wrapped fist
    w.tube([(0, 0, -0.03), (0, 0, -0.07), (0, 0, -0.105)], [0.06, 0.056, 0.053], sides=8)   # forearm wrap
    for lu, rad in ((0.03, 0.064), (-0.014, 0.068)):                               # bands over the fist
        _band(w, lu, rad, 0.008)
    for lu in (-0.078,):                                                            # band on the wrist
        _band(w, lu, 0.058, 0.007)
    w.box((0, 0.0, 0.07), (0.05, 0.03, 0.008), val=EDGE, mat=ACCENT)               # knuckle pad
    w.tube([(0, 0, -0.105), (0, 0, -0.112)], [0.053, 0.046], sides=8, val=GRIP)    # tucked end
    return _to_fist(w, s, dict(tip=(0, 0, 0.078), trail_base=(0, 0, -0.10),
                               aura=[(0, 0, 0.07), (0.05, 0, 0.04), (-0.05, 0, 0.04), (0, 0.06, 0.0),
                                     (0, 0, -0.07)]))


def build_brass_knuckles(w):
    s = len(w.verts)
    xs = (-0.057, -0.019, 0.019, 0.057)
    for x in xs:                                                                   # the four finger rings
        w.ring((x, -0.012, 0.042), 0.03, 0.0105, axis="x", segs=8, sides=4)
    w.box((0, 0.006, 0.079), (0.084, 0.026, 0.011))                               # the striking bar
    for x in xs:                                                                   # knuckle studs: the face
        w.tube([(x, 0.006, 0.088), (x, 0.006, 0.112)], [0.022, 0.0], sides=4, phase=0.0, val=EDGE, mat=ACCENT)
    w.box((0, -0.058, 0.024), (0.072, 0.013, 0.013))                             # palm rest, across lx
    w.tube([(0, 0, -0.035), (0, 0, -0.085)], [0.054, 0.052], sides=8, val=GRIP)   # short wrist wrap
    _band(w, -0.06, 0.056, 0.006, val=IRON, mat=BODY)
    return _to_fist(w, s, dict(tip=(0, 0.006, 0.112), trail_base=(0, 0, -0.085),
                               aura=[(x, 0.006, 0.1) for x in xs] + [(0, -0.062, 0.02)]))


def build_gauntlets(w):
    s = len(w.verts)
    w.ellipsoid((0, 0.004, 0.004), (0.074, 0.07, 0.07), sides=8, rings=5)          # the plated fist
    w.box((0, 0.012, 0.074), (0.068, 0.04, 0.014), val=EDGE, mat=ACCENT)           # knuckle plate
    for x in (-0.048, -0.016, 0.016, 0.048):                                       # its four ridges
        w.box((x, 0.026, 0.09), (0.011, 0.024, 0.006), val=EDGE, mat=ACCENT)
    for k, lu in enumerate((0.046, 0.016, -0.014)):                                # overlapping back plates
        w.box((0, 0.058 - 0.004 * k, lu), (0.058 - 0.004 * k, 0.012, 0.018))
    w.tube([(0, 0, -0.035), (0, 0, -0.1), (0, 0, -0.17)], [0.064, 0.07, 0.088], sides=8)     # flared cuff
    _band(w, -0.172, 0.088, 0.009, val=IRON, mat=BODY)                             # cuff rim
    _band(w, -0.06, 0.068, 0.008, val=GRIP, mat=BODY)                              # strap
    return _to_fist(w, s, dict(tip=(0, 0.012, 0.096), trail_base=(0, 0, -0.17),
                               aura=[(0, 0.02, 0.09), (0.06, 0.0, 0.05), (-0.06, 0.0, 0.05),
                                     (0, 0.07, 0.0), (0, 0.0, -0.17)]))


# id, class, hands, builder, notes. Order = equipment.csv order.
WEAPONS = [
    ("sword", "sword", "one", build_sword, "Straight double edge, flared guard, round pommel."),
    ("scimitar", "sword", "one", build_scimitar, "Single edge, sweeps back and widens to a clipped point."),
    ("flamberge", "sword", "two", build_flamberge, "Wavy two-hander: undulating blade, parrying lugs, horned guard."),
    ("axe", "axe", "one", build_axe, "Bearded head on a one-hand haft, square poll."),
    ("double_axe", "axe", "two", build_double_axe, "Labrys: twin crescents and a top spike on a long haft."),
    ("hatchet", "axe", "one", build_hatchet, "Short, compact wedge head with a hammer poll."),
    ("warhammer", "axe", "two", build_warhammer, "Block head, grey striking face, back spike, top spike."),
    ("anchor", "axe", "two", build_anchor, "Ship's anchor held at the ring end; flukes point back at the wielder."),
    ("lance", "lance", "two", build_lance, "Vamplate cone over the hand, long tapering cone, steel point."),
    ("javelin", "lance", "one", build_javelin, "Thin, light, bound in the middle, four-sided head."),
    ("halberd", "lance", "two", build_halberd, "Spear top, axe blade forward, hook back."),
    ("glaive", "lance", "two", build_glaive, "Long single-edged knife blade on a pole, back spur."),
    ("dagger", "daggers", "pair", build_dagger, "Leaf blade, small guard; carried as a pair."),
    ("jagged_dagger", "daggers", "pair", build_jagged_dagger, "Hooked tip, sawtooth spine, spike pommel; a pair."),
    ("shortbow", "bow", "bow", build_shortbow, "Simple D arc, plain string."),
    ("recurve_bow", "bow", "bow", build_recurve_bow, "Taller, chunky riser, tips curl forward, string on the curls."),
    ("compound_bow", "bow", "bow", build_compound_bow, "Angular riser, split limbs, cams, cable, stabiliser rod."),
    ("pistol", "pistols", "one", build_pistol, "Revolver: hex cylinder bulge, thin barrel."),
    ("flintlock", "pistols", "one", build_flintlock, "Long thin barrel, curved stock, ball butt, cock on top."),
    ("m1911", "pistols", "one", build_m1911, "Boxy slide and frame, steep square grip."),
    ("staff", "staff", "two", build_staff, "Gnarled shaft, three-prong claw around a dark gem."),
    ("moon_staff", "staff", "two", build_moon_staff, "Straight shaft, crescent head, gem floating in the hollow."),
    ("hand_wraps", "fists", "fists", build_hand_wraps, "Wrapped fists: a fat cloth mitten, bands over the knuckles and up the wrist."),
    ("brass_knuckles", "fists", "fists", build_brass_knuckles, "Four-ring duster: striking bar and studs over a black fist, palm rest, wrist wrap."),
    ("gauntlets", "fists", "fists", build_gauntlets, "Plated fist, ridged knuckle plate, overlapping back plates, flared cuff."),
]

# Readability scale, applied about the grip after building. Pistols and
# daggers are true-ish to the 2.2 figure when modelled; at the combat camera
# (24 u, FOV 34) that is ~15 px, so they are drawn oversized, RuneScape-style.
SCALE = {"pistol": 1.4, "flintlock": 1.3, "m1911": 1.4, "dagger": 1.2, "jagged_dagger": 1.2}

# What each class shoots (game/tools/blender/build_projectiles.py builds them;
# art/weapons/projectiles/projectiles.json). Melee classes: null.
PROJECTILE = {"bow": "arrow", "pistols": "bullet", "staff": "bolt"}

HANDS = {
    # hands -> (socket, offhand socket for a mirrored copy, which hand the second point is for)
    "one": ("socket_weapon_r", None, None),
    "two": ("socket_weapon_r", None, "l"),
    "pair": ("socket_weapon_r", "socket_offhand_l", None),
    "bow": ("socket_offhand_l", None, "r"),
    "fists": ("socket_weapon_r", "socket_offhand_l", None),   # + a MIRRORED <id>_l.glb on the left
}


def gd(p):
    """weapon space (x, f, u) -> Godot (x, y=u, z=f), rounded."""
    return [round(p[0], 4), round(p[2], 4), round(p[1], 4)]


# ------------------------------------------------------------------ main
def make_material(name, rgba):
    m = bpy.data.materials.new(name)
    m.diffuse_color = rgba
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(attr.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


IMPORT_STUB = """[remap]

importer="scene"
type="PackedScene"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=false
meshes/generate_lods=false
meshes/create_shadow_meshes=false
meshes/light_baking=1
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
materials/extract=0
gltf/naming_version=2
"""


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    scn = bpy.context.scene
    only = None
    if "--only" in ARGS:
        only = set(ARGS[ARGS.index("--only") + 1].split(","))
    mat_body = make_material("body", (1, 1, 1, 1))
    mat_accent = make_material("accent", (0.7, 0.7, 0.7, 1))
    mat_string = make_material("string", (0.12, 0.12, 0.12, 1))
    os.makedirs(OUT_DIR, exist_ok=True)

    meta = {}
    if only and os.path.exists(JSON_OUT):
        with open(JSON_OUT, encoding="utf-8") as fh:
            meta = json.load(fh).get("weapons", {})
    lay_x = 0.0
    for wid, wclass, hands, fn, notes in WEAPONS:
        if only and wid not in only:
            continue
        wm = WeaponMesh()
        pts = fn(wm)
        k = SCALE.get(wid, 1.0)
        if k != 1.0:          # scaled about the grip: the fist stays put
            wm.verts = [p * k for p in wm.verts]
            pts = {key: ([tuple(c * k for c in q) for q in val] if key == "aura" else tuple(c * k for c in val))
                   for key, val in pts.items()}
        me = wm.build(wid, [mat_body, mat_accent] + ([mat_string] if wm.string else []))
        obj = bpy.data.objects.new(wid, me)
        scn.collection.objects.link(obj)
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        acc = sum(len(p.vertices) - 2 for p in me.polygons if p.material_index == ACCENT)
        xs = [v.x for v in wm.verts]
        fs = [v.y for v in wm.verts]
        us = [v.z for v in wm.verts]
        lo, hi = gd((min(xs), min(fs), min(us))), gd((max(xs), max(fs), max(us)))
        socket, off_socket, second_hand = HANDS[hands]
        entry = {
            "class": wclass,
            "hands": hands,
            "socket": socket,
            "offhand_socket": off_socket,
            "mount": {"position": [0.0, 0.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0]},
            "second_hand": ({"hand": second_hand, "point": gd(pts["second"])} if second_hand else None),
            "tip": gd(pts["tip"]),
            "trail_base": gd(pts["trail_base"]),
            "aura_points": [gd(p) for p in pts["aura"]],
            "length": round(max(us) - min(us), 3),
            "aabb": {"min": lo, "max": hi},
            "scale": SCALE.get(wid, 1.0),
            "tris": tris,
            "accent_tris": acc,
            "glb": "res://art/weapons/%s.glb" % wid,
            "projectile": PROJECTILE.get(wclass),
            "notes": notes,
        }
        if wm.string:
            # the drawable string's ends (Godot weapon space): BWWeaponView
            # bends it to the draw hand between nock and release
            entry["string"] = [gd(tuple(c * k for c in wm.string[0])), gd(tuple(c * k for c in wm.string[1]))]
        if hands == "fists":
            # the left hand's piece: the same mesh mirrored in x, its own glb
            # (a negative-scale copy would flip the winding and break the hull)
            wl = WeaponMesh()
            wl.verts = [Vector((-p.x, p.y, p.z)) for p in wm.verts]
            wl.faces = list(wm.faces)
            me_l = wl.build(wid + "_l", [mat_body, mat_accent])
            obj_l = bpy.data.objects.new(wid + "_l", me_l)
            scn.collection.objects.link(obj_l)
            entry["offhand_glb"] = "res://art/weapons/%s_l.glb" % wid
            entry["mirror_offhand"] = True
        meta[wid] = entry
        print("WEAPON %-14s %-8s %-4s tris %4d (accent %3d) length %.2f" % (wid, wclass, hands, tris, acc, entry["length"]))

        # export this weapon alone, at the origin
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        glb = os.path.join(OUT_DIR, wid + ".glb")
        bpy.ops.export_scene.gltf(
            filepath=glb, export_format='GLB', use_selection=True,
            export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
            export_materials='EXPORT', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
            export_skins=False, export_animations=False, export_morph=False,
            export_cameras=False, export_lights=False, export_extras=False,
        )
        imp = glb + ".import"
        if not os.path.exists(imp):
            with open(imp, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(IMPORT_STUB)
        if hands == "fists":
            for o in bpy.context.view_layer.objects:
                o.select_set(False)
            obj_l.select_set(True)
            bpy.context.view_layer.objects.active = obj_l
            glb_l = os.path.join(OUT_DIR, wid + "_l.glb")
            bpy.ops.export_scene.gltf(
                filepath=glb_l, export_format='GLB', use_selection=True,
                export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
                export_materials='EXPORT', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                export_skins=False, export_animations=False, export_morph=False,
                export_cameras=False, export_lights=False, export_extras=False,
            )
            if not os.path.exists(glb_l + ".import"):
                with open(glb_l + ".import", "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(IMPORT_STUB)
            obj_l.location = (lay_x + 0.3, 0, 0)

        # reference layout in the .blend: weapon + its metadata as empties
        obj.location = (lay_x, 0, 0)
        for key, p in [("tip", pts["tip"]), ("trail_base", pts["trail_base"])] + \
                ([("second_hand", pts["second"])] if second_hand else []) + \
                [("aura_%d" % i, p) for i, p in enumerate(pts["aura"])]:
            e = bpy.data.objects.new("%s.%s" % (wid, key), None)
            e.empty_display_type = 'SPHERE' if key.startswith("aura") else 'ARROWS'
            e.empty_display_size = 0.02 if key.startswith("aura") else 0.05
            scn.collection.objects.link(e)
            e.parent = obj
            e.location = (p[0], -p[1], p[2])
        obj["weapon_class"] = wclass
        obj["hands"] = hands
        lay_x += 0.9

    doc = {
        "version": WEAPONS_VERSION,
        "rig_version": RIG_VERSION,
        "generator": "game/tools/blender/build_weapons.py",
        "space": "Godot weapon-local: origin = centre of the holding fist, +Y along the blade/shaft, "
                 "+Z the edge/muzzle (the wielder's forward), +X the wielder's left. "
                 "Matches the rig sockets' rest frame, so mount is identity.",
        "hands": {
            "one": "right hand, socket_weapon_r",
            "two": "right hand on socket_weapon_r; second_hand.point is the LEFT hand's IK target",
            "pair": "right hand on socket_weapon_r plus an identical copy on socket_offhand_l",
            "fists": "worn on both hands: <id>.glb on socket_weapon_r, the x-mirrored offhand_glb on "
                     "socket_offhand_l (its points mirror too); tip = the knuckle face",
            "bow": "LEFT hand on socket_offhand_l; second_hand.point is the RIGHT hand's draw (nock) target",
        },
        "weapons": {k: meta[k] for k in [w[0] for w in WEAPONS] if k in meta},
    }
    with open(JSON_OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1, sort_keys=False)
        fh.write("\n")
    print("JSON", JSON_OUT)
    os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=False)
    print("BLEND", BLEND_OUT)


if __name__ == "__main__":
    main()
