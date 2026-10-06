"""Black | White hair archetypes, built from nothing.

    blender -b --factory-startup --python game/tools/blender/build_hair.py
    blender -b --factory-startup --python game/tools/blender/build_hair.py -- --only bob,mullet
    blender -b --factory-startup --python game/tools/blender/build_hair.py -- --no-blend

Writes (never hand-edit these; change this script and rebuild):
    game/art/hair/<style>.glb      one per archetype: mesh (+ hair bones for long styles)
    game/art/hair/alt/<style>.glb  variant 1 of each style (VARIANTS), same bones
    game/art/source/hair.blend     working file, one collection per style

Frame: socket space of `socket_hair` on base rig v1. Origin = head centre
(world 1.92), Blender Z up, the character faces -Y, its left is +X. The glTF
exporter's +Y-up conversion turns that into the socket's Godot frame (+Y up,
+Z forward). The head is the ellipsoid HEAD_R (0.31 x 0.295 x 0.28).

v2 crowns are built from locks (strand / drape / fan), not shells: a thin
scalp cap only fills gaps. See design/art/HAIR.md "Diagnosis".

Three material slots, all with vertex colour 1.0 (neutral white):
    hair        the fill. The game tints it with the element colour.
    hair_shade  inner contour: the inside of every shell, the head-facing
                face of every lock, shaved/stubble zones and ties.
                The game draws it as a darker value of the same hue.
    hair_shine  highlight streaks across the crown (an angel-ring band
                broken by the lock edges). The game mixes it toward white.
Separate locks are separate mesh islands, so the inverted-hull contour also
draws a strand line wherever one clump overlaps another.

Long styles carry their own small skeleton: `hair_root` (rigid, at the
origin) and a chain hair_tail_01..03 hanging under it, weighted by height
with short linear blends. Short styles are a single rigid mesh.

Deterministic: no randomness. Every lump and wave comes from closed-form
functions of the style parameters. See design/art/HAIR.md.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# ----------------------------------------------------------------- paths
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(GAME, "art", "hair")
BLEND_OUT = os.path.join(GAME, "art", "source", "hair.blend")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

HAIR_VERSION = 2      # bump when the frame, slots or bone names change (2: hair_shine, alt/)
RIG_VERSION = 1       # base rig this was fitted to

# ---------------------------------------------------------- rig landmarks
# (from build_base_rig.py / RIG.md; local = world - HEAD_Z)
HEAD_Z = 1.92
HEAD_R = Vector((0.31, 0.295, 0.28))
HEAD_PIVOT = Vector((0, 0, 1.66 - HEAD_Z))
GAP = 0.042           # hair inner surface sits this far off the head (head contour is 0.026)
FACE_HALF_X = 0.20    # the face window that must stay clear ...
FACE_TOP_Z = 0.03     # ... below this height (world 1.95) ...
FACE_FRONT_Y = -0.12  # ... in front of this depth


def V(x, y, z):
    return Vector((x, y, z))


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def smooth(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0)) if e1 != e0 else (1.0 if x >= e0 else 0.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def head_r(d):
    """Distance from the head centre to the head surface along unit d."""
    a, b, c = HEAD_R
    return 1.0 / math.sqrt((d.x / a) ** 2 + (d.y / b) ** 2 + (d.z / c) ** 2)


def sdir(theta, phi):
    """Unit direction. theta: degrees from the top. phi: degrees around,
    0 = front (-Y), 90 = the character's left (+X), 180 = back."""
    t, p = math.radians(theta), math.radians(phi)
    return V(math.sin(t) * math.sin(p), -math.sin(t) * math.cos(p), math.cos(t))


def on_head(theta, phi, off):
    d = sdir(theta, phi)
    return d * (head_r(d) + off)


def ring(phi, table):
    """Cosine-interpolate a value around the head. table: [(phi_deg, v)],
    any order, wraps at 360."""
    phi %= 360.0
    pts = sorted((p % 360.0, v) for p, v in table)
    pts = [(pts[-1][0] - 360.0, pts[-1][1])] + pts + [(pts[0][0] + 360.0, pts[0][1])]
    for (p0, v0), (p1, v1) in zip(pts, pts[1:]):
        if p0 <= phi <= p1:
            u = (phi - p0) / (p1 - p0) if p1 > p0 else 0.0
            u = 0.5 - 0.5 * math.cos(math.pi * u)
            return v0 + (v1 - v0) * u
    return pts[0][1]


def sym(table):
    """Mirror a half table (phi 0..180) to the character's right side."""
    out = list(table)
    for p, v in table:
        if 0 < p < 180:
            out.append((360 - p, v))
    return out


def soft_min(a, b, k):
    return -k * math.log(math.exp(-a / k) + math.exp(-b / k))


HAIR_M, SHADE_M, SHINE_M = 0, 1, 2
WHITE = (1.0, 1.0, 1.0, 1.0)


# -------------------------------------------------------- mesh builder
class HairMesh:
    """Verts + faces with a material index, or None = decide by facing:
    a face that looks back at the head / body axis is `hair_shade`."""

    def __init__(self):
        self.verts = []
        self.faces = []     # (indices, mat or None)
        self.islands = 0

    def v(self, co):
        self.verts.append(Vector(co))
        return len(self.verts) - 1

    def f(self, idx, mat):
        self.faces.append((tuple(idx), mat))

    # ---- shell over the head ------------------------------------------
    def cap(self, edge, off, cols=40, rows=7, gap=GAP, rim=0.03, rim_drop=0.0,
            strands=(), shade_rows=None, shade_fn=None, z_flat=None, flat_k=0.025):
        """A closed shell hugging the head from the crown down to edge(phi).

        edge(phi) -> theta of the hairline (deg). off(theta, phi) -> outer
        offset from the head surface. The rim is a rounded lip from the
        outer edge to the inner edge, bulging `rim` past the hairline.
        strands: [(phi, half_width_deg, t0, t1)] shade bands on the outer
        surface (part lines, strokes). shade_rows: rows with t > this go
        shade (a fade). shade_fn(theta, phi) -> bool for anything else.
        z_flat: clamp the outer surface to a flat top at that height."""
        self.islands += 1
        phis = [360.0 * j / cols for j in range(cols)]
        for p, hw, _, _ in strands:
            phis += [(p - hw) % 360.0, (p + hw) % 360.0]
        phis = sorted(set(round(p, 4) for p in phis))
        n = len(phis)

        def outer(theta, phi):
            d = sdir(theta, phi)
            r = head_r(d) + off(theta, phi)
            if z_flat is not None and d.z > 0.05:
                r = soft_min(r, z_flat / d.z, flat_k)
            return d * r

        top_o = self.v(outer(0.0, 0.0))
        top_i = self.v(on_head(0.0, 0.0, gap))
        O, I, R1, R2 = [], [], [], []
        for p in phis:
            te = edge(p)
            col_o, col_i = [], []
            for i in range(1, rows + 1):
                th = te * i / rows
                col_o.append(self.v(outer(th, p)))
                col_i.append(self.v(on_head(th, p, gap)))
            O.append(col_o)
            I.append(col_i)
            # rounded lip: two loops between the outer and the inner edge
            eo, ei = self.verts[col_o[-1]], self.verts[col_i[-1]]
            tr = math.radians(te)
            tang = V(math.cos(tr) * math.sin(math.radians(p)), -math.cos(tr) * math.cos(math.radians(p)), -math.sin(tr))
            tang = (tang + V(0, 0, -rim_drop)).normalized()
            R1.append(self.v(eo.lerp(ei, 0.3) + tang * rim * 0.95))
            R2.append(self.v(eo.lerp(ei, 0.72) + tang * rim * 0.75))

        def in_band(pa, pb, t):
            for p, hw, t0, t1 in strands:
                a, b = (p - hw) % 360.0, (p + hw) % 360.0
                mid = (pa + ((pb - pa) % 360.0) / 2.0) % 360.0
                inside = (a <= mid <= b) if a <= b else (mid >= a or mid <= b)
                if inside and t0 <= t <= t1:
                    return True
            return False

        for j in range(n):
            k = (j + 1) % n
            pa, pb = phis[j], phis[k]
            for i in range(rows):
                t = (i + 0.5) / rows
                th = edge(pa) * t
                m = HAIR_M
                if in_band(pa, pb, t) or (shade_rows is not None and t > shade_rows) \
                        or (shade_fn and shade_fn(th, pa + ((pb - pa) % 360) / 2)):
                    m = SHADE_M
                if i == 0:
                    self.f((top_o, O[k][0], O[j][0]), m)
                    self.f((top_i, I[j][0], I[k][0]), SHADE_M)
                else:
                    self.f((O[j][i - 1], O[k][i - 1], O[k][i], O[j][i]), m)
                    self.f((I[j][i - 1], I[j][i], I[k][i], I[k][i - 1]), SHADE_M)
            lip = SHADE_M if (shade_rows is not None and shade_rows < 1.0) else HAIR_M
            self.f((O[j][-1], O[k][-1], R1[k], R1[j]), lip)
            self.f((R1[j], R1[k], R2[k], R2[j]), SHADE_M)
            self.f((R2[j], R2[k], I[k][-1], I[j][-1]), SHADE_M)

    # ---- a clump / lock / spike ---------------------------------------
    def lock(self, pts, w, h=None, tip="round", base="flat", radial=8, mat=None, out=None, roll=0.0,
             sharp=1.6, shine=(), under=False):
        """Tapered tube along pts. w/h: half width (sideways) and half depth
        (away from the head) per point. Its depth axis points away from
        the head centre (or from the body axis below the head), or along
        out(p) if given. tip/base: 'round' | 'point' | 'flat'. sharp: how
        far a point tip runs past the last ring (x its half size). shine:
        segment indices whose outer faces are `hair_shine`. under: only the
        face toward the head is `hair_shade` (v2 locks: clean fills, the
        hull draws the lock edges), instead of the facing rule."""
        self.islands += 1
        pts = [Vector(p) for p in pts]
        n = len(pts)
        h = h or w
        tans = []
        for k in range(n):
            a, b = pts[max(k - 1, 0)], pts[min(k + 1, n - 1)]
            tans.append((b - a).normalized())
        rings, frames = [], []
        prev_n = None
        for k in range(n):
            c, t = pts[k], tans[k]
            ref = out(c) if out else body_out(c)
            nn = ref - t * ref.dot(t)
            if nn.length < 1e-4:
                nn = prev_n if prev_n is not None else V(1, 0, 0)
            nn.normalize()
            if roll:
                nn = Matrix.Rotation(math.radians(roll), 3, t) @ nn
            prev_n = nn
            b = t.cross(nn)
            frames.append((c, t, nn, b))
            rings.append([self.v(c + b * math.cos(a) * w[k] + nn * math.sin(a) * h[k])
                          for a in (2 * math.pi * r / radial for r in range(radial))])
        outer = [r for r in range(radial) if math.sin(2 * math.pi * (r + 0.5) / radial) > 0.45]
        for k in range(n - 1):
            for r in range(radial):
                r2 = (r + 1) % radial
                m = SHINE_M if (k in shine and r in outer) else mat
                if under and m is None:
                    m = SHADE_M if math.sin(2 * math.pi * (r + 0.5) / radial) < -0.7 else HAIR_M
                self.f((rings[k][r], rings[k][r2], rings[k + 1][r2], rings[k + 1][r]), m)

        def cap_mat(r):
            if under and mat is None:
                return SHADE_M if math.sin(2 * math.pi * (r + 0.5) / radial) < -0.7 else HAIR_M
            return mat

        def end(kind, idx, sign):
            c, t, nn, b = frames[idx]
            t = t * sign
            row = rings[idx]
            wr, hr = w[idx], h[idx]
            if kind == "round":
                for beta in (38.0, 72.0):
                    bb = math.radians(beta)
                    cc = c + t * min(wr, hr) * math.sin(bb) * 0.95
                    nr = [self.v(cc + b * math.cos(a) * wr * math.cos(bb) + nn * math.sin(a) * hr * math.cos(bb))
                          for a in (2 * math.pi * r / radial for r in range(radial))]
                    for r in range(radial):
                        r2 = (r + 1) % radial
                        q = (row[r], row[r2], nr[r2], nr[r]) if sign > 0 else (row[r], nr[r], nr[r2], row[r2])
                        self.f(q, cap_mat(r))
                    row = nr
                apex = self.v(c + t * min(wr, hr) * 0.95)
            elif kind == "point":
                apex = self.v(c + t * max(wr, hr) * sharp)
            else:
                apex = self.v(c)
            for r in range(radial):
                r2 = (r + 1) % radial
                self.f((row[r], row[r2], apex) if sign > 0 else (row[r2], row[r], apex), cap_mat(r))

        end(tip, n - 1, 1)
        end(base, 0, -1)

    # ---- a hanging sheet of hair -----------------------------------------
    def curtain(self, phi0, phi1, theta_top, z_end, cols=14, rows=6, off=0.06, thick=0.045,
                leave=100.0, r_bot=1.05, bow=0.04, flare=0.0, wave=0.0, wave_n=2.0,
                tips=0.05, tip_k=5, strands=(), side_lift=0.0, edge_z=None, gather=0.0):
        """One thick, closed sheet that follows the head from theta_top down
        to `leave`, then falls to z_end between azimuths phi0..phi1. Its
        plan radius goes from where it leaves the head to r_bot x that,
        bellies out by `bow`, flares by `flare` at the bottom and ripples
        by `wave`. The bottom edge has tip_k pointed tips `tips` deep.
        strands: [(u, half_width_u, v0, v1)] shade bands on the outer face
        (the reference's strand lines). edge_z(u) -> extra z for the hem.
        gather: the sheet narrows toward phi 180 as it falls (0 = straight
        down, 0.5 = half as wide at the hem): long hair converges down the
        back and stays clear of the arms when the head turns."""
        self.islands += 1
        us = [j / cols for j in range(cols + 1)]
        for u, hw, _, _ in strands:
            us += [clamp(u - hw), clamp(u + hw)]
        us = sorted(set(round(u, 5) for u in us))
        head_steps = 3
        nv = head_steps + rows
        O, I = [], []
        for u in us:
            ph = lerp(phi0, phi1, u)
            hd = V(math.sin(math.radians(ph)), -math.cos(math.radians(ph)), 0)
            col_o, col_i = [], []
            for k in range(head_steps):
                th = lerp(theta_top, leave, k / head_steps)
                col_o.append(self.v(on_head(th, ph, off)))
                col_i.append(self.v(on_head(th, ph, max(GAP * 0.6, off - thick))))
            L = on_head(leave, ph, off)
            rho_l = math.hypot(L.x, L.y)
            ze = z_end + tips * abs(math.sin(math.pi * tip_k * u)) + (edge_z(u) if edge_z else 0.0) \
                + side_lift * (abs(2 * u - 1) ** 2)
            for k in range(rows + 1):
                s = k / rows
                z = lerp(L.z, ze, s)
                pg = 180.0 + (ph - 180.0) * (1.0 - gather * smooth(0.0, 1.0, s))
                hd = V(math.sin(math.radians(pg)), -math.cos(math.radians(pg)), 0)
                rho = lerp(rho_l, rho_l * r_bot, s) + bow * math.sin(math.pi * s) + flare * s * s \
                    + wave * math.sin(math.pi * wave_n * s + 2 * math.pi * u * 1.5) * smooth(0, 0.3, s)
                p = hd * rho + V(0, 0, z)
                col_o.append(self.v(p))
                col_i.append(self.v(p - hd * thick))
            O.append(col_o)
            I.append(col_i)
        n = len(us)

        def band(ua, ub, v):
            um = (ua + ub) / 2
            return any(u - hw <= um <= u + hw and v0 <= v <= v1 for u, hw, v0, v1 in strands)

        nrow = len(O[0])
        for j in range(n - 1):
            for k in range(nrow - 1):
                v = (k + 0.5) / (nrow - 1)
                m = SHADE_M if band(us[j], us[j + 1], v) else HAIR_M
                self.f((O[j][k], O[j + 1][k], O[j + 1][k + 1], O[j][k + 1]), m)
                self.f((I[j][k], I[j][k + 1], I[j + 1][k + 1], I[j + 1][k]), SHADE_M)
            self.f((O[j][0], I[j][0], I[j + 1][0], O[j + 1][0]), SHADE_M)               # top (buried)
            self.f((O[j][-1], O[j + 1][-1], I[j + 1][-1], I[j][-1]), SHADE_M)           # hem
        for j in (0, n - 1):
            for k in range(nrow - 1):
                self.f((O[j][k], O[j][k + 1], I[j][k + 1], I[j][k]), HAIR_M)

    def blob(self, c, radii, seg=10, rings=6, mat=None, basis=None):
        """Ellipsoid (hair ties, curl puffs)."""
        self.islands += 1
        basis = basis or Matrix.Identity(3)
        c = Vector(c)
        top = self.v(c + basis @ V(0, 0, radii[2]))
        lat = []
        for i in range(1, rings):
            th = math.pi * i / rings
            lat.append([self.v(c + basis @ V(radii[0] * math.sin(th) * math.cos(2 * math.pi * j / seg),
                                             radii[1] * math.sin(th) * math.sin(2 * math.pi * j / seg),
                                             radii[2] * math.cos(th))) for j in range(seg)])
        bot = self.v(c + basis @ V(0, 0, -radii[2]))
        for j in range(seg):
            k = (j + 1) % seg
            self.f((top, lat[0][j], lat[0][k]), mat)
            self.f((bot, lat[-1][k], lat[-1][j]), mat)
        for i in range(len(lat) - 1):
            for j in range(seg):
                k = (j + 1) % seg
                self.f((lat[i][j], lat[i + 1][j], lat[i + 1][k], lat[i][k]), mat)


def body_axis_point(p):
    """Closest point on the head centre / spine axis (head centre down)."""
    return V(0, 0, clamp(p.z, -1.4, 0.0))


def body_out(p):
    v = p - body_axis_point(p)
    return v if v.length > 1e-5 else V(0, 1, 0)


def hang(start, end, sway=0.0, sway_dir=None, flick=0.0, flick_dir=None, waves=0.0, n=6, bow=0.0):
    """Points for a lock hanging from start to end. sway: sideways S-wave
    amplitude (waves = number of half periods). flick: the end kicks out
    along flick_dir. bow: the middle bellies outward from the body."""
    start, end = Vector(start), Vector(end)
    pts = []
    sd = sway_dir.normalized() if sway_dir is not None else V(1, 0, 0)
    for i in range(n):
        u = i / (n - 1)
        p = start.lerp(end, u)
        if sway:
            p += sd * math.sin(math.pi * waves * u) * sway * smooth(0, 0.35, u)
        if bow:
            o = body_out(p)
            o.z = 0
            if o.length > 1e-5:
                p += o.normalized() * math.sin(math.pi * u) * bow
        if flick and flick_dir is not None:
            p += flick_dir.normalized() * flick * smooth(0.55, 1.0, u) ** 1.5
        pts.append(p)
    return pts


def taper(n, w0, w_mid, w1, peak=0.4):
    out = []
    for i in range(n):
        u = i / (n - 1)
        out.append(lerp(w0, w_mid, smooth(0, peak, u)) if u <= peak else lerp(w_mid, w1, smooth(peak, 1, u)))
    return out


# ============================================================ lock paths
# v2 hair is built from LOCKS, not shells: every crown is a fan of flat,
# tapered locks radiating from a whorl or a parting, lifted off the head in
# the middle (volume) and ending in uneven tips. A thin scalp cap underneath
# only fills the gaps; its hem always sits under lock tips or is a flush,
# irregular hairline, so no straight hem shows. See HAIR.md "Diagnosis".

def as_dir(a):
    return a.normalized() if isinstance(a, Vector) else sdir(*a)


def ang(p):
    """(theta, phi) of a point, degrees, same convention as sdir."""
    d = p.normalized()
    return math.degrees(math.acos(clamp(d.z, -1.0, 1.0))), math.degrees(math.atan2(d.x, -d.y)) % 360.0


def in_arc(ph, arcs):
    ph %= 360.0
    for a, b in arcs:
        a, b = a % 360.0, b % 360.0
        if (a <= ph <= b) if a <= b else (ph >= a or ph <= b):
            return True
    return False


def slerp_dirs(d0, d1, n, bend=0.0, hook=0.0, side=None):
    """n unit directions along the great circle d0 -> d1, bowed sideways by
    `bend` (mid) and `hook` (toward the tip). side defaults to d0 x d1 (the
    lock's own left), so the same bend on every lock of a fan makes a swirl."""
    om = math.acos(clamp(d0.dot(d1), -1.0, 1.0))
    if side is None:
        side = d0.cross(d1)
        side = side.normalized() if side.length > 1e-6 else V(1, 0, 0)
    out = []
    for i in range(n):
        u = i / (n - 1)
        d = (d0 * math.sin((1 - u) * om) + d1 * math.sin(u * om)) / math.sin(om) if om > 1e-4 else d0.copy()
        d = d + side * (bend * math.sin(math.pi * u) + hook * smooth(0.45, 1.0, u) ** 2)
        out.append(d.normalized())
    return out


def bump(u, peak):
    """0 at both ends, 1 at u = peak."""
    if u <= peak:
        return math.sin(0.5 * math.pi * u / max(peak, 1e-4))
    return math.cos(0.5 * math.pi * (u - peak) / max(1.0 - peak, 1e-4))


def shine_segments(pts, band):
    """Segments of a lock whose middle falls inside band = (theta0, theta1,
    arcs | None). Those segments' outer faces become `hair_shine`."""
    if not band:
        return ()
    t0, t1, arcs = band
    out = []
    for k in range(len(pts) - 1):
        th, ph = ang((pts[k] + pts[k + 1]) * 0.5)
        if t0 <= th <= t1 and (arcs is None or in_arc(ph, arcs)):
            out.append(k)
    return tuple(out)


BROW_THETA = 79.0     # lowest fringe tip over the face window ...
BROW_PHI = 38.0       # ... within this many degrees of the front


def strand(m, a, b, w=0.07, h=0.024, n=7, off0=None, off1=None, lift=0.03, lift_at=0.45, flick=0.0,
           bend=0.0, hook=0.0, side=None, tip="point", base="flat", sharp=2.4, shine=None,
           wp=(0.75, 1.0, 0.07), hp=(0.8, 1.0, 0.35), peak=0.32, radial=6, mat=None):
    """One lock lying on the head from a to b (each (theta, phi) or a
    direction). off0/off1: centre-line offset off the head at the root /
    tip; lift raises the middle (volume, peaking at lift_at); flick kicks
    the tip away from the head. w/h: half width / half depth at the widest,
    scaled by wp/hp at root, peak and tip."""
    off0 = GAP + h * 1.05 if off0 is None else off0
    off1 = off0 if off1 is None else off1
    if not isinstance(b, Vector) and abs(((b[1] + 180.0) % 360.0) - 180.0) < BROW_PHI:
        b = (min(b[0], BROW_THETA), b[1])     # fringe tips stop at the brow: the face window stays clear
    ds = slerp_dirs(as_dir(a), as_dir(b), n, bend, hook, side)
    pts = []
    for i, d in enumerate(ds):
        u = i / (n - 1)
        o = lerp(off0, off1, u) + lift * bump(u, lift_at) + flick * smooth(0.5, 1.0, u) ** 2
        pts.append(d * (head_r(d) + o))
    m.lock(pts, taper(n, w * wp[0], w * wp[1], w * wp[2], peak), taper(n, h * hp[0], h * hp[1], h * hp[2], peak),
           tip=tip, base=base, radial=radial, sharp=sharp, shine=shine_segments(pts, shine), mat=mat, under=True)
    return pts


def drape(m, a, phi_end, leave, z_end, w=0.08, h=0.028, n_head=4, n_hang=5, off0=None, off1=None, lift=0.02,
          bend=0.0, side=None, bulge=0.03, flare=0.0, tuck=0.0, gather=0.0, sway=0.0, tip="point", sharp=2.4,
          shine=None, wp=(0.7, 1.0, 0.08), hp=(0.8, 1.0, 0.4), peak=0.3, radial=6, base="flat", mat=None):
    """A lock that lies on the head from a down to (leave, phi_end), then
    hangs to z_end: bellying out (bulge), flaring (flare), tucking its end
    back under (tuck), converging toward the spine (gather) and swaying
    sideways (sway, degrees)."""
    off0 = GAP + h * 1.05 if off0 is None else off0
    off1 = off0 if off1 is None else off1
    ds = slerp_dirs(as_dir(a), sdir(leave, phi_end), n_head + 1, bend, 0.0, side)
    pts = []
    for i, d in enumerate(ds):
        u = i / n_head
        pts.append(d * (head_r(d) + lerp(off0, off1, u) + lift * math.sin(math.pi * u * 0.5)))
    L = pts[-1]
    rho_l = math.hypot(L.x, L.y)
    dp = ((phi_end - 180.0 + 180.0) % 360.0) - 180.0      # signed offset from the back
    for k in range(1, n_hang + 1):
        s = k / n_hang
        pg = 180.0 + dp * (1.0 - gather * smooth(0.0, 1.0, s)) + sway * math.sin(math.pi * s)
        rho = rho_l + bulge * math.sin(math.pi * s) + flare * s * s - tuck * smooth(0.55, 1.0, s) ** 2
        pr = math.radians(pg)
        pts.append(V(math.sin(pr) * rho, -math.cos(pr) * rho, lerp(L.z, z_end, s)))
    n = len(pts)
    m.lock(pts, taper(n, w * wp[0], w * wp[1], w * wp[2], peak), taper(n, h * hp[0], h * hp[1], h * hp[2], peak),
           tip=tip, base=base, radial=radial, sharp=sharp, shine=shine_segments(pts, shine), mat=mat, under=True)
    return pts


def jag(i, amp, pattern=(0.0, 0.8, -0.5, 0.45, -0.9, 0.3, -0.2, 1.0, -0.65)):
    """Deterministic uneven tip lengths: a fixed, non-repeating-looking
    pattern so no two neighbours end at the same height."""
    return amp * pattern[i % len(pattern)]


# Shine: an 'angel ring' band across the crown, broken into streaks. Arcs
# are where around the head (phi) it may appear: front, and one patch per
# side toward the back, so every view shows 1-3 streaks.
SHINE_BAND = (18.0, 42.0, [(315, 45), (85, 135), (225, 275)])


def fan(m, whorl, tips, w, h, off0=None, lift=0.035, lift_at=0.45, flick=0.012, root_f=0.12, n=6, bend=0.0,
        sharp=2.4, shine=SHINE_BAND, tip="point", wp=(0.75, 1.0, 0.07), skip_shine=(), base="point"):
    """A rosette: one lock from near the whorl to each tip (theta, phi).
    Roots sit root_f of the way toward their tip so they ring the whorl."""
    dw = as_dir(whorl)
    for i, t in enumerate(tips):
        dt = as_dir(t)
        root = _toward(dw, dt, root_f)
        strand(m, root, dt, w=w, h=h, n=n, off0=off0, lift=lift, lift_at=lift_at, flick=flick, bend=bend,
               sharp=sharp, tip=tip, wp=(0.3, wp[1], wp[2]) if base == "point" else wp, base=base,
               shine=None if i in skip_shine else shine)


def _toward(d0, d1, f):
    om = math.acos(clamp(d0.dot(d1), -1.0, 1.0))
    if om < 1e-4:
        return d0.copy()
    return ((d0 * math.sin((1 - f) * om) + d1 * math.sin(f * om)) / math.sin(om)).normalized()


def wobble(p, amp, k=7.0, ph=0.0):
    return amp * math.sin(math.radians(p) * k + ph)


# ================================================================ styles
# Each archetype is a function of named shape parameters; the defaults are
# variant 0. Shared knobs (where they apply):
#   part     phi of the parting (0 = centre, + = the character's left)
#   sweep    how hard the fringe sweeps away from the part (>0 = toward the
#            character's right)
#   volume   how far the crown locks lift off the head
#   locks    lock count of the main fan
#   sharp    tip sharpness (apex length / half width of the last ring)
# Each returns (HairMesh, chain): chain is None (rigid) or the hair_tail
# joint points J0..Jn. VARIANTS below holds variant 1 of every style.
#
# Hairline angles are theta (degrees from the crown) at phi = front 0,
# temple ~40, side 90, back 180. Front fringe tips stay at theta <= ~82
# (world z >= ~1.95) so the face window is clear.

def nape_v(p, depth=10.0, width=34.0):
    """Extra theta that pulls the hairline down to a point at the nape."""
    d = abs(((p - 180.0 + 180.0) % 360.0) - 180.0)
    return depth * max(0.0, 1.0 - d / width) ** 1.5


def buzzed(volume=0.014, locks=15, sharp=2.4, sweep=0.12, part=20.0, fade=80.0):
    """Textured crop: short pointed tufts swirl out from a crown whorl over
    the whole head and flick their tips up, so the outline is spiky, not a
    dome. The front tufts come down as a short, choppy fringe; the lower
    sides and the nape are a dark fade, its line broken by tuft points and
    the nape tapered to a point. It stays close enough to fit under a cap."""
    m = HairMesh()
    edge = lambda p: ring(p, sym([(0, 56), (30, 60), (45, 70), (62, 78), (90, 100), (135, 122), (180, 130)])) \
        + wobble(p, 2.0, 9) + nape_v(p, 12.0)
    lo = lambda p: ring(p, sym([(0, 99), (40, 88), (60, fade), (90, fade + 4), (135, fade + 14), (180, fade + 20)])) \
        + wobble(p, 4.0, 13)
    m.cap(edge, lambda th, p: GAP + 0.010 + 0.006 * math.cos(math.radians(th)), cols=32, rows=5, rim=0.004,
          shade_fn=lambda th, p: th > lo(p))
    tipline = lambda p: ring(p, sym([(0, 72), (35, 74), (70, fade - 2), (110, fade + 6), (180, fade + 16)]))
    tips = [(tipline(part + 360.0 * i / locks) + jag(i, 5.0), part + 360.0 * i / locks) for i in range(locks)]
    fan(m, (18.0, 176.0), tips, w=0.085, h=0.017, off0=GAP + 0.018, lift=volume, flick=0.022, root_f=0.2, n=6,
        bend=sweep * 0.6, sharp=sharp, base="point", shine=(14.0, 40.0, [(320, 40), (95, 135), (225, 265)]))
    return m, None


def high_and_tight(volume=0.02, locks=13, sharp=2.4, sweep=0.12, part=-18.0, top_edge=52.0, spike=0.075):
    """Spiky top, tight sides: a crown of short locks swirls out from the
    whorl and kicks its tips up and out (spike), tallest at the front where
    they stand up as a messy quiff. Below the block the sides are a short
    band and then a dark fade to a pointed nape. The lifted, spiky top over
    the flat sides is the step."""
    m = HairMesh()
    edge = lambda p: ring(p, sym([(0, 64), (40, 74), (90, 90), (135, 112), (180, 124)])) + wobble(p, 2.0, 11) \
        + nape_v(p, 10.0)
    lo = lambda p: ring(p, sym([(0, 99), (40, 74), (90, top_edge + 12), (150, top_edge + 30), (180, top_edge + 44)]))         + wobble(p, 3.0, 14)
    m.cap(edge, lambda th, p: GAP + 0.008, cols=28, rows=5, rim=0.004, shade_fn=lambda th, p: th > lo(p))
    e2 = lambda p: ring(p, sym([(0, top_edge - 2), (60, top_edge - 6), (180, top_edge - 4)]))
    m.cap(e2, lambda th, p: GAP + 0.024, cols=24, rows=3, gap=GAP + 0.006, rim=0.006)
    tl = lambda p: ring(p, sym([(0, top_edge + 4), (60, top_edge + 6), (120, top_edge + 10), (180, top_edge + 14)]))
    tips = [(tl(part + 360.0 * i / locks) + jag(i, 5.0), part + 360.0 * i / locks) for i in range(locks)]
    dw = sdir(12.0, 180.0 + part)
    for i, t in enumerate(tips):
        front = 0.5 + 0.5 * math.cos(math.radians(t[1]))
        strand(m, _toward(dw, sdir(*t), 0.15), t, w=0.085, h=0.024, n=6, off0=GAP + 0.024, lift=volume,
               lift_at=0.4, flick=spike * (0.55 + 0.45 * front) * (1.0 + jag(i + 2, 0.25)), bend=sweep * 0.5,
               sharp=sharp, base="point", shine=(14.0, 36.0, [(320, 40), (110, 130), (230, 250)]))
    return m, None


def mullet(volume=0.035, locks=12, sharp=1.8, sweep=0.12, part=24.0, length=-0.46, flare=0.10, back_locks=7):
    """Business up front: a choppy, parted crop with a fringe that sweeps
    off the part. Party at the back: two layers of pointed locks down the
    neck, flaring out, wider than the neck so they show from the front."""
    m = HairMesh()
    edge = lambda p: ring(p, sym([(0, 62), (40, 74), (90, 98), (140, 112), (180, 116)])) + wobble(p, 2.0, 8)
    m.cap(edge, lambda th, p: GAP + 0.03, cols=28, rows=4, rim=0.008)
    # crown fan over the sides and back
    tips = []
    for i in range(locks):
        ph = lerp(52, 308, i / (locks - 1))
        tips.append((ring(ph, sym([(50, 86), (90, 100), (140, 112), (180, 116)])) + jag(i, 7.0), ph))
    fan(m, (24.0, 180.0 + part * 0.5), tips, w=0.085, h=0.03, lift=volume, flick=0.02, bend=sweep * 0.4,
        sharp=sharp, n=6)
    # fringe from the part: choppy, swept
    for i in range(5):
        u = i / 4
        a = (16 + 4 * u, part - 10 + 18 * u)
        b = (77 + jag(i, 4.0) + 3 * u, lerp(part + 26, -46, u))
        strand(m, a, b, w=0.07, h=0.026, n=6, lift=volume * 0.9, lift_at=0.35, flick=0.02, bend=-sweep * 0.6,
               side=V(1, 0, 0), sharp=sharp, shine=SHINE_BAND)
    # the party: two layers down the neck
    for layer, (cnt, z, wd, sp) in enumerate(((back_locks, length, 0.075, 136), (back_locks - 2, length * 0.62, 0.08, 110))):
        for i in range(cnt):
            u = i / (cnt - 1)
            ph = 180 + (u - 0.5) * sp
            drape(m, (60 + 10 * layer, ph), ph, 108 - 8 * layer, z + jag(i + layer, 0.05), w=wd, h=0.03,
                  n_head=3, n_hang=5, lift=0.02 + 0.015 * layer, bulge=0.025, flare=flare * (0.5 + abs(u - 0.5)),
                  sway=(u - 0.5) * 18, sharp=sharp, shine=None)
    return m, None


def short_mohawk(height=0.27, width=0.042, n_spikes=8, lean=26.0, stubble=0.016, sharp=2.4, splay=3.0):
    """Faded stubble everywhere and a fin of tapered, back-curving spikes,
    tallest over the crown, alternately splayed left and right so the fin
    has body from the front. Each spike is thin sideways and deep front to
    back, like a blade of gelled hair."""
    m = HairMesh()
    edge = lambda p: ring(p, sym([(0, 58), (30, 54), (90, 50), (140, 62), (165, 96), (180, 128)])) \
        + wobble(p, 2.5, 12) + nape_v(p, 8.0, 20.0)
    m.cap(edge, lambda th, p: GAP + stubble, cols=36, rows=5, rim=0.004, shade_rows=0.0)
    # a low ridge under the fin so the spikes grow out of hair, not scalp
    strand(m, (54, 0), (100, 180), w=0.05, h=0.02, n=7, off0=GAP + 0.03, lift=0.012, tip="round", base="round",
           shine=None)
    for i in range(n_spikes):
        u = i / (n_spikes - 1)
        al = lerp(-50, 108, u)
        th, ph = abs(al), (0 if al < 0 else 180)
        base = on_head(th, ph, GAP + 0.01)
        nrm = sdir(th, ph)
        back = V(0, 1, 0) - nrm * nrm.y
        back = back.normalized() if back.length > 1e-4 else V(0, 1, 0)
        hgt = height * (0.5 + 0.5 * math.sin(math.pi * clamp(u * 0.9 + 0.1))) * (1.0 + jag(i, 0.08))
        side = V(1, 0, 0) * math.sin(math.radians(splay * (1 if i % 2 else -1)))
        d = (nrm * math.cos(math.radians(lean)) + back * math.sin(math.radians(lean)) + side).normalized()
        pts = [base, base + d * hgt * 0.35, base + d * hgt * 0.68 + back * 0.02, base + d * hgt + back * 0.06]
        m.lock(pts, [width * 1.1, width, width * 0.7, width * 0.2], [0.085, 0.07, 0.045, 0.012], tip="point",
               radial=6, out=lambda p, b=back: b, sharp=sharp, shine=(1,) if i in (2, 4, 5) else ())
    return m, None


def bob(volume=0.05, locks=14, sharp=1.2, sweep=0.16, part=26.0, length=-0.17, tuck=0.035):
    """A layered bob to the jaw from a side part: locks fall from the part,
    round out over the sides and tuck their ends under toward the neck.
    A swept fringe crosses the forehead away from the part; the back is
    a touch shorter than the face-framing front locks."""
    m = HairMesh()
    edge = lambda p: ring(p, sym([(0, 62), (40, 72), (90, 98), (180, 108)]))
    m.cap(edge, lambda th, p: GAP + 0.03 + 0.012 * math.cos(math.radians(th)), cols=28, rows=4, rim=0.01)
    for i in range(locks):
        u = i / (locks - 1)
        ph = lerp(58, 302, u)
        side = 1 if ph < 180 else -1
        root = (12 + 6 * abs(math.cos(math.radians(ph))), part + side * 14)
        z = length + 0.06 * smooth(60, 180, ph if ph < 180 else 360 - ph) * 0.7 + jag(i, 0.025)
        drape(m, root, ph, 92, z, w=0.088, h=0.026, n_head=4, n_hang=4, lift=volume * 0.6, bulge=0.02 + volume * 0.3,
              tuck=tuck, tip="round", sharp=1.0, bend=0.0, shine=SHINE_BAND if i % 2 == 0 else None)
    # fringe: swept off the part across the brow
    for i in range(5):
        u = i / 4
        a = (14 + 6 * u, part - 4 - 10 * u)
        b = (77 + jag(i, 3.0) + 3 * math.sin(math.pi * u), lerp(part + 20, -44, u))
        strand(m, a, b, w=0.075, h=0.024, n=7, lift=volume * 0.8, lift_at=0.35, flick=0.015, bend=-sweep,
               side=V(1, 0, 0), sharp=sharp, tip="point", shine=SHINE_BAND)
    # face-framing front locks, a little longer than the sides
    for sd in (1, -1):
        drape(m, (30, sd * 30), sd * 56, 88, length - 0.03, w=0.07, h=0.026, n_head=4, n_hang=4, lift=volume * 0.5,
              bulge=0.015, tuck=tuck * 0.8, tip="point", sharp=sharp + 0.4, shine=None)
    return m, None


def _tension(m, tie_dir, front, back_th, n_locks, w=0.08, h=0.014, sharp=1.5, shine=SHINE_BAND, skip=()):
    """Locks pulled from the hairline to a tie: the tension lines of a
    ponytail. front(phi) -> hairline theta. Every other lock sits proud so
    the hull draws a line between them. Over the ears the locks start a
    third of the way back (behind the ear) so the sides stay sleek from the
    front; at the nape their roots taper to points."""
    for i in range(n_locks):
        if i in skip:
            continue
        ph = 360.0 * i / n_locks
        fold = min(ph, 360.0 - ph)
        a = sdir(front(ph) + jag(i, 2.5), ph)
        side = 48.0 < fold < 118.0
        if side:
            a = _toward(a, tie_dir, 0.38)
        pt = side or fold > 118.0
        up = 0.02 * (i % 2)
        strand(m, a, tie_dir, w=w, h=h, n=7, off0=GAP + h + 0.002 + up, off1=GAP + h + 0.006 + up, lift=0.006,
               lift_at=0.35, tip="round", base="point" if pt else "round", sharp=sharp,
               wp=(0.25 if pt else 0.85, 1.0, 0.22), peak=0.3, shine=shine if i % 2 else None)


def ponytail(tie_theta=110.0, length=-0.70, girth=0.09, swing=-0.12, part=34.0, sweep=0.18, sharp=1.9):
    """Hair pulled back to a low tie: lock lines run from the hairline to
    the tie (tension), a side-swept fringe falls from the part, two thin
    face-framing strands escape at the temples, and the tail is three
    pointed locks that swing to the character's right."""
    m = HairMesh()
    front = lambda p: ring(p, sym([(0, 66), (40, 76), (90, 98), (140, 120), (180, 130)]))
    m.cap(lambda p: front(p) - 3, lambda th, p: GAP + 0.012, cols=28, rows=4, rim=0.004)
    tie = on_head(tie_theta, 180, GAP + 0.05)
    _tension(m, sdir(tie_theta - 6, 180), front, tie_theta, 22, w=0.068)
    m.blob(tie + V(0, 0.015, 0), (0.062, 0.048, 0.062), seg=8, rings=5, mat=SHADE_M,
           basis=Matrix.Rotation(math.radians(80), 3, "X"))
    s = tie + V(0, 0.03, 0)
    base_pts = [s, s + V(0, 0.09, -0.07), s + V(swing * 0.3, 0.13, -0.22),
                V(swing * 0.75, s.y + 0.10, (s.z + length) * 0.62), V(swing, s.y + 0.04, length + 0.08),
                V(swing * 1.1, s.y + 0.01, length)]
    for k, (dx, dy, dl, g) in enumerate(((0.0, 0.0, 0.0, 0.8), (0.06, 0.025, 0.14, 0.6), (-0.055, 0.03, 0.22, 0.55))):
        pts = [p + V(dx * smooth(0, 5, i), dy * smooth(0, 3, i), dl * smooth(2, 5, i)) for i, p in enumerate(base_pts)]
        m.lock(pts, taper(6, 0.04 * g, girth * g, 0.012, 0.35), taper(6, 0.04 * g, girth * 0.8 * g, 0.012, 0.35),
               tip="point", radial=7, sharp=sharp, shine=(1, 2) if k == 0 else ())
    # fringe off the part
    for i in range(4):
        u = i / 3
        a = (12 + 4 * u, part - 4 - 8 * u)
        b = (76 + jag(i, 5.0) + 3 * math.sin(math.pi * u), lerp(part + 14, -40, u))
        strand(m, a, b, w=0.072, h=0.022, n=7, lift=0.028, lift_at=0.3, flick=0.015, bend=-sweep * 0.5, side=V(1, 0, 0),
               sharp=sharp, wp=(1.0, 1.0, 0.07), peak=0.25, shine=SHINE_BAND)
    for sd in (1, -1):
        drape(m, (68, sd * 54), sd * 64, 94, -0.14 + 0.03 * sd, w=0.036, h=0.016, n_head=3, n_hang=4, lift=0.006,
              bulge=0.01, sway=sd * -6, sharp=2.0, shine=None)
    J = [V(0, s.y + 0.10, -0.18), V(swing * 0.75, s.y + 0.10, (s.z + length) * 0.62), V(swing * 1.1, s.y + 0.01, length)]
    return m, J


def long_ponytail(tie_theta=46.0, length=-1.02, girth=0.12, arc=0.42, part=0.0, sweep=0.14, sharp=2.0):
    """A high tie at the crown: tension lines up the back and sides, a
    curtain fringe split at the part, face-framing tendrils, and a tail of
    three locks that arcs up and back, then falls to the waist."""
    m = HairMesh()
    front = lambda p: ring(p, sym([(0, 66), (40, 76), (90, 100), (140, 122), (180, 134)]))
    m.cap(lambda p: front(p) - 3, lambda th, p: GAP + 0.012, cols=28, rows=4, rim=0.004)
    tie = on_head(tie_theta, 180, GAP + 0.06)
    _tension(m, sdir(tie_theta - 4, 180), front, tie_theta, 22, w=0.068)
    m.blob(tie + V(0, 0.02, 0.01), (0.07, 0.07, 0.048), seg=8, rings=5, mat=SHADE_M,
           basis=Matrix.Rotation(math.radians(-30), 3, "X"))
    s = tie + V(0, 0.03, 0.02)
    base_pts = [s, s + V(0, 0.10, 0.10), s + V(0, arc * 0.62, 0.04), V(0, s.y + arc * 0.80, -0.20),
                V(0, s.y + arc * 0.70, -0.52), V(-0.02, s.y + arc * 0.50, -0.80), V(-0.03, s.y + arc * 0.36, length)]
    for k, (dx, dl, g) in enumerate(((0.0, 0.0, 0.85), (0.065, 0.16, 0.6), (-0.06, 0.28, 0.55))):
        pts = [p + V(dx * smooth(1, 6, i), 0.014 * k * smooth(1, 4, i), dl * smooth(3, 6, i)) for i, p in enumerate(base_pts)]
        m.lock(pts, taper(7, 0.05 * g, girth * g, 0.012, 0.4), taper(7, 0.05 * g, girth * 0.88 * g, 0.012, 0.4),
               tip="point", radial=7, sharp=sharp)
    # curtain fringe from the part
    for sd in (1, -1):
        for i in range(2):
            a = (14 + 4 * i, part + sd * 6)
            b = (77 + 4 * i + jag(i + (sd > 0), 3.0), part + sd * (16 + 22 * i))
            strand(m, a, b, w=0.07, h=0.022, n=7, lift=0.03, lift_at=0.3, flick=0.016, bend=sd * sweep * 0.6,
                   side=V(-1, 0, 0), sharp=sharp, shine=SHINE_BAND)
        drape(m, (64, sd * 50), sd * 64, 94, -0.18, w=0.042, h=0.018, n_head=3, n_hang=4, lift=0.008, bulge=0.02,
              sway=sd * -8, sharp=2.0, shine=None)
    J = [V(0, s.y + arc * 0.78, -0.12), V(0, s.y + arc * 0.68, -0.45), V(-0.02, s.y + arc * 0.50, -0.78),
         V(-0.03, s.y + arc * 0.36, length)]
    return m, J


def waterfall(length=-0.86, part=40.0, wave=0.035, volume=0.05, locks=11, sharp=1.9, sweep=0.2):
    """Long, layered and wavy from a deep side part: a crown of locks, a big
    swoop of three locks across the brow and down the far cheek, a short
    layer flicking out at the shoulders, and a long rippling under-layer
    down the back with pointed tips."""
    m = HairMesh()
    edge = lambda p: ring(p, [(0, 62), (part, 58), (90, 98), (180, 118), (270, 98), (320, 66)])
    m.cap(edge, lambda th, p: GAP + 0.04, cols=28, rows=4, rim=0.006)
    tips = [(ring(ph, sym([(50, 94), (90, 104), (180, 112)])) + jag(i, 6.0), ph)
            for i, ph in enumerate(lerp(56, 304, k / (locks - 1)) for k in range(locks))]
    fan(m, (14.0, part + 180 - 20), tips, w=0.09, h=0.032, lift=volume, flick=0.025, bend=0.05, sharp=sharp, n=6)
    # the swoop: locks sweep off the part across the brow, each ending in a
    # point lower than the last; the last one runs down past the far cheek
    for i in range(4):
        u = i / 3
        a = (12 + 5 * u, part + 2 - 8 * u)
        b = (76 + jag(i, 2.5) + 3 * u, lerp(part - 18, -34, u))
        strand(m, a, b, w=0.09, h=0.03, n=7, lift=volume * 0.8, lift_at=0.3, flick=0.016, bend=-sweep,
               side=V(1, 0, 0), sharp=sharp, shine=SHINE_BAND)
    for i in range(2):
        drape(m, (20 + 6 * i, part - 30), -50 - 10 * i, 86, -0.20 - 0.12 * i, w=0.08 - 0.01 * i, h=0.03, n_head=4,
              n_hang=4, lift=volume * 0.6, bend=-0.06, side=V(0, 0, 1), bulge=0.02, sway=-6, sharp=sharp,
              shine=SHINE_BAND if i == 0 else None)
    # near side of the part: two shorter locks down past the near temple
    for i in range(2):
        drape(m, (22 + 6 * i, part + 22), part + 28 + 10 * i, 84, -0.12 - 0.08 * i, w=0.075, h=0.028, n_head=4,
              n_hang=3, lift=volume * 0.5, bulge=0.02, sway=10, sharp=sharp, shine=SHINE_BAND if i == 0 else None)
    lines = [(0.18, 0.01, 0.3, 1.0), (0.38, 0.01, 0.25, 1.0), (0.6, 0.01, 0.3, 1.0), (0.82, 0.01, 0.3, 1.0)]
    m.curtain(116, 244, 94, length, cols=14, rows=8, off=GAP + 0.05, thick=0.05, leave=108, r_bot=0.95, gather=0.5,
              bow=0.05, flare=0.06, wave=wave, wave_n=3.0, tips=0.10, tip_k=6, side_lift=0.10, strands=lines)
    # the short over-layer as separate locks that flick out at the shoulders
    for i in range(7):
        u = i / 6
        ph = 180 + (u - 0.5) * 150
        drape(m, (50, ph), ph, 104, length * 0.5 + jag(i, 0.05), w=0.08, h=0.03, n_head=3, n_hang=5, lift=0.03,
              bulge=0.03, flare=0.07, gather=0.2, sway=(u - 0.5) * 24, sharp=sharp, shine=None)
    J = [V(0, 0.32, -0.16), V(0, 0.34, -0.40), V(0, 0.33, -0.64), V(0, 0.30, length)]
    return m, J


def ringlets(curls=10, length=-0.46, volume=0.06, coil=0.035, turns=2.5, thick=0.04, locks=13, part=-20.0):
    """A cloud of curls: a crown of short locks that each hook into a
    C-curl with a round end (a lumpy, never-smooth outline), a curly fringe
    and a ring of corkscrews to the shoulders (references 4 and 5)."""
    m = HairMesh()
    edge = lambda p: ring(p, sym([(0, 64), (40, 74), (90, 94), (180, 112)])) + wobble(p, 3.0, 10)
    m.cap(edge, lambda th, p: GAP + 0.04, cols=28, rows=4, rim=0.01)
    tips = [(ring(ph, sym([(40, 84), (90, 96), (180, 110)])) + jag(i, 6.0), ph)
            for i, ph in enumerate(lerp(44, 316, k / (locks - 1)) for k in range(locks))]
    for i, t in enumerate(tips):
        dw = sdir(18, 180 + part)
        strand(m, _toward(dw, sdir(*t), 0.18), t, w=0.085, h=0.04, n=6, lift=volume, lift_at=0.6, flick=0.03,
               hook=0.16 * (1 if i % 2 else -1), tip="round", sharp=1.0, wp=(0.7, 1.0, 0.6), peak=0.6,
               shine=SHINE_BAND)
    # curly fringe: short C-curls on the brow
    for i in range(5):
        u = i / 4
        ph = lerp(-44, 44, u) + part * 0.2
        strand(m, (20 + 4 * abs(u - 0.5), ph * 0.4 + part), (75 + jag(i, 3.0), ph), w=0.07, h=0.036, n=6,
               lift=volume * 0.9, lift_at=0.55, flick=0.025, hook=0.14 * (1 if i % 2 else -1), tip="round",
               sharp=1.0, wp=(0.75, 1.0, 0.65), peak=0.6, shine=SHINE_BAND)
    for i in range(curls):
        u = i / (curls - 1)
        ph = lerp(64, 296, u)
        sd = math.sin(math.radians(ph))
        s = on_head(edge(ph) - 6, ph, GAP + volume * 0.6 + coil)
        ln = lerp(length * 0.7, length, smooth(0.0, 0.6, -math.cos(math.radians(ph)) * 0.5 + 0.5)) + jag(i, 0.04)
        e = V(s.x * 1.12 + sd * 0.03, s.y * 1.05 + 0.04, ln)
        axis = e - s
        n = 16
        a1 = body_out(s)
        a1 = (a1 - axis.normalized() * a1.dot(axis.normalized())).normalized()
        a2 = axis.normalized().cross(a1)
        pts = []
        for k in range(n):
            t = k / (n - 1)
            ang_ = 2 * math.pi * turns * t + i * 1.3
            r = coil * smooth(0.0, 0.15, t)
            pts.append(s + axis * t + a1 * math.cos(ang_) * r + a2 * math.sin(ang_) * r)
        m.lock(pts, [thick * (1.0 - 0.3 * (k / (n - 1))) for k in range(n)], None, tip="round", radial=6)
    J = [V(0, 0.30, -0.10), V(0, 0.32, -0.28), V(0, 0.32, length)]
    return m, J


def long_hair(length=-1.0, part=0.0, volume=0.04, locks=11, sharp=1.8, sweep=0.12, sides=True):
    """Straight and sleek from a centre part: a crown of locks, curtain
    bangs that split at the part and frame the face, long face-framing
    locks to the collarbone, and a long curtain to the waist overlaid with
    pointed locks of staggered length (reference 2)."""
    m = HairMesh()
    edge = lambda p: ring(p, sym([(0, 62), (36, 70), (90, 100), (180, 118)]))
    m.cap(edge, lambda th, p: GAP + 0.035, cols=28, rows=4, rim=0.006)
    tips = [(ring(ph, sym([(50, 96), (90, 104), (180, 112)])) + jag(i, 5.0), ph)
            for i, ph in enumerate(lerp(58, 302, k / (locks - 1)) for k in range(locks))]
    fan(m, (12.0, part + 180), tips, w=0.09, h=0.03, lift=volume, flick=0.015, bend=0.0, sharp=sharp, n=6)
    lines = [(0.16, 0.01, 0.3, 1.0), (0.33, 0.01, 0.25, 1.0), (0.5, 0.01, 0.2, 1.0), (0.67, 0.01, 0.25, 1.0),
             (0.84, 0.01, 0.3, 1.0)]
    m.curtain(114, 246, 92, length, cols=16, rows=8, off=GAP + 0.045, thick=0.05, leave=104, r_bot=0.95, gather=0.5,
              bow=0.05, flare=0.03, tips=0.035, tip_k=6, side_lift=0.10, strands=lines)
    # curtain bangs + face-framing locks, both sides of the part
    for sd in (1, -1):
        for i in range(2):
            a = (10 + 4 * i, part + sd * 5)
            b = (77 + 4 * i + jag(i + (sd > 0) * 2, 3.0), part + sd * (14 + 20 * i))
            strand(m, a, b, w=0.072, h=0.024, n=7, lift=volume * 0.8, lift_at=0.3, flick=0.016,
                   bend=sd * sweep * 0.5, side=V(-1, 0, 0), sharp=sharp, shine=SHINE_BAND)
        drape(m, (26, part + sd * 22), sd * 58, 88, -0.30 + 0.03 * sd, w=0.07, h=0.028, n_head=4, n_hang=5,
              lift=volume * 0.5, bulge=0.02, sway=sd * -4, sharp=sharp, shine=SHINE_BAND)
        if sides:
            drape(m, (40, sd * 90), sd * 92, 98, -0.42, w=0.075, h=0.028, n_head=3, n_hang=5, lift=volume * 0.5,
                  bulge=0.02, gather=0.0, sharp=sharp, shine=None)
    # over-layer down the back: staggered pointed locks
    for i in range(5):
        u = i / 4
        ph = 180 + (u - 0.5) * 110
        drape(m, (40, ph), ph, 106, length * (0.62 + 0.3 * abs(math.sin(math.pi * (u + 0.25)))) , w=0.085, h=0.03,
              n_head=3, n_hang=6, lift=0.03, bulge=0.04, gather=0.5, sharp=sharp, shine=None)
    J = [V(0, 0.32, -0.20), V(0, 0.34, -0.45), V(0, 0.33, -0.72), V(0, 0.30, length)]
    return m, J


# Variant 1 of every style: the same archetype with other knobs, written
# to art/hair/alt/<style>.glb. BWHair picks variant 0 or 1 per character
# from a seed derived from the unit id (BWHair.variant_for) and may also
# mirror it, so two people with the same style don't look identical.
# Bone names and counts never change between variants.
VARIANTS = {
    "buzzed": dict(locks=13, sweep=-0.14, part=-34.0, volume=0.02, sharp=2.9, fade=74.0),
    "high_and_tight": dict(locks=11, spike=0.095, sweep=-0.1, part=24.0, volume=0.016),
    "mullet": dict(locks=10, sweep=0.22, part=-12.0, flare=0.14, back_locks=6, sharp=2.8, volume=0.045),
    "short_mohawk": dict(n_spikes=6, height=0.31, lean=34.0, width=0.05, sharp=2.0),
    "bob": dict(length=-0.12, part=10.0, sweep=0.08, locks=12, tuck=0.05, volume=0.058, sharp=1.6),
    "ponytail": dict(part=-8.0, sweep=0.08, length=-0.6, girth=0.1, sharp=2.4),
    "long_ponytail": dict(part=24.0, sweep=0.22, arc=0.5, length=-0.95, sharp=2.4),
    "waterfall": dict(part=26.0, wave=0.05, volume=0.065, locks=9, sweep=0.26, sharp=2.4),
    "ringlets": dict(curls=9, volume=0.075, coil=0.042, part=24.0, locks=11, turns=2.2),
    "long_hair": dict(part=22.0, sweep=0.2, volume=0.052, length=-0.9, locks=9, sharp=2.4),
}

STYLES = {
    "buzzed": buzzed,
    "high_and_tight": high_and_tight,
    "mullet": mullet,
    "short_mohawk": short_mohawk,
    "bob": bob,
    "ponytail": ponytail,
    "long_ponytail": long_ponytail,
    "waterfall": waterfall,
    "ringlets": ringlets,
    "long_hair": long_hair,
}


# ------------------------------------------------------------- Blender
def make_material(name, rgba):
    m = bpy.data.materials.new(name)
    m.diffuse_color = rgba
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = rgba
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def build_mesh(name, hm, mats):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in hm.verts], [], [f for f, _ in hm.faces])
    for m in mats:
        me.materials.append(m)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    # explicit materials first, then the facing rule for the rest
    for i, (_, mat) in enumerate(hm.faces):
        f = bm.faces[i]
        if mat is None:
            c = f.calc_center_median()
            toward = body_axis_point(c) - c
            mat = SHADE_M if toward.length > 1e-5 and f.normal.dot(toward.normalized()) > 0.35 else HAIR_M
        f.material_index = mat
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    col = me.color_attributes.new("Color", 'BYTE_COLOR', 'POINT')
    for i in range(len(me.vertices)):
        col.data[i].color = WHITE
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = 0
    me.update()
    return me


def make_rig(coll, style, joints):
    arm = bpy.data.armatures.new(style + "_hair_rig")
    obj = bpy.data.objects.new("hair_rig", arm)
    coll.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    root = eb.new("hair_root")
    root.head, root.tail = V(0, 0, 0), V(0, 0, 0.15)
    root.align_roll(V(0, -1, 0))
    parent = root
    for k in range(len(joints) - 1):
        b = eb.new("hair_tail_%02d" % (k + 1))
        b.head, b.tail = joints[k], joints[k + 1]
        b.align_roll(V(0, -1, 0))
        b.parent = parent
        b.use_connect = k > 0
        parent = b
    bpy.ops.object.mode_set(mode='OBJECT')
    return obj


def chain_weights(z, joints, band=0.07):
    """hair_root above J0, then hair_tail_k between J(k-1) and J(k), with
    linear blends of +-band around each joint height."""
    names = ["hair_root"] + ["hair_tail_%02d" % (k + 1) for k in range(len(joints) - 1)]
    bounds = [j.z for j in joints[:-1]]
    s = [1.0] + [clamp((b + band - z) / (2 * band)) for b in bounds] + [0.0]
    w = {}
    for k, n in enumerate(names):
        v = s[k] - s[k + 1]
        if v > 1e-4:
            w[n] = v
    return w


# ------------------------------------------------------------- checks
def arm_points(s):
    a = math.radians(35.0)
    sh = V(s * 0.06, 0, 1.48 - HEAD_Z)
    d1 = V(s * math.sin(a), 0.03, -math.cos(a)).normalized()
    el = sh + d1 * 0.36
    d2 = V(s * math.sin(a), -0.08, -math.cos(a)).normalized()
    wr = el + d2 * 0.33
    return sh, el, wr


def seg_dist(p, a, b):
    ab = b - a
    t = clamp((p - a).dot(ab) / ab.dot(ab))
    return (p - (a + ab * t)).length


# body volumes the hair must clear, as clothing-inflated capsules (local)
CAPSULES = [
    ("torso", V(0, 0, 0.85 - HEAD_Z), V(0, 0, 1.46 - HEAD_Z), 0.12),
    ("neck", V(0, 0, 1.46 - HEAD_Z), V(0, 0, 1.64 - HEAD_Z), 0.06),
]
for _s, _n in ((1, "l"), (-1, "r")):
    _sh, _el, _wr = arm_points(_s)
    CAPSULES += [("upper_arm_" + _n, _sh, _el, 0.075), ("forearm_" + _n, _el, _wr, 0.07)]


def check(verts):
    """Head clearance, the face window, and body clearance at rest and
    under head yaw +-30 (and pitch/roll +-15, informational)."""
    head = min(v.length - head_r(v.normalized()) for v in verts if v.length > 1e-6)
    bad = [v for v in verts if v.y < FACE_FRONT_Y and abs(v.x) < FACE_HALF_X and v.z < FACE_TOP_Z]
    face = len(bad)
    if bad:
        print("  face window hit at", ["(%.2f %.2f %.2f)" % tuple(v) for v in bad[:4]])
    body = {}
    for label, axis, angs in (("yaw", "Z", (-30, -15, 0, 15, 30)), ("pitch", "X", (-15, 15)), ("roll", "Y", (-15, 15))):
        worst = (9.0, "")
        for a in angs:
            R = Matrix.Rotation(math.radians(a), 3, axis)
            for v in verts:
                p = R @ (v - HEAD_PIVOT) + HEAD_PIVOT
                for name, ca, cb, r in CAPSULES:
                    d = seg_dist(p, ca, cb) - r
                    if d < worst[0]:
                        worst = (d, "%s %+d %s @(%.2f %.2f %.2f)" % (label, a, name, v.x, v.y, v.z))
        body[label] = worst
    return head, face, body


# ---------------------------------------------------------------- main
def export_style(style, fn, mats, coll, variant=0):
    hm, joints = fn(**VARIANTS[style]) if variant else fn()
    tag = style + ("@%d" % variant if variant else "")
    me = build_mesh("hair_" + tag.replace("@", "_v"), hm, mats)
    obj = bpy.data.objects.new("hair", me)
    coll.objects.link(obj)
    sel = [obj]
    bones = 0
    if joints:
        rig = make_rig(coll, tag.replace("@", "_v"), joints)
        for n in ["hair_root"] + ["hair_tail_%02d" % (k + 1) for k in range(len(joints) - 1)]:
            obj.vertex_groups.new(name=n)
        for i, v in enumerate(me.vertices):
            for n, w in chain_weights(v.co.z, joints).items():
                obj.vertex_groups[n].add([i], w, 'REPLACE')
        mod = obj.modifiers.new("Armature", 'ARMATURE')
        mod.object = rig
        obj.parent = rig
        sel = [rig, obj]
        bones = len(joints) - 1
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    shade = sum(1 for p in me.polygons if p.material_index == SHADE_M)
    head, face, body = check([v.co for v in me.vertices])
    zs = [v.co.z for v in me.vertices]
    # shine share: shine area over the area of every outward fill face
    # (hair + shine); rise: what BWEquipmentView.hair_rise measures (crown
    # height above the head top within 0.22 of the head axis)
    fill = sum(p.area for p in me.polygons if p.material_index in (HAIR_M, SHINE_M))
    shine = sum(p.area for p in me.polygons if p.material_index == SHINE_M)
    rise = max(v.co.z for v in me.vertices if math.hypot(v.co.x, v.co.y) < 0.22) - HEAD_R.z
    print("STYLE %-17s tris %5d  shade %4.0f%%  shine %4.1f%%  rise %.3f  islands %2d  bones %d  z %.2f..%.2f  "
          "head_clear %.3f  face_verts %d  body %s"
          % (tag, tris, 100.0 * shade / max(1, len(me.polygons)), 100.0 * shine / max(fill, 1e-9), rise, hm.islands,
             bones, min(zs), max(zs), head, face, "  ".join("%s %.3f(%s)" % (k, v[0], v[1]) for k, v in body.items())))
    if head < 0.0 or face > 0 or body["yaw"][0] < 0:
        print("WARN %s: head %.3f face %d yaw %.3f" % (tag, head, face, body["yaw"][0]))
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in sel:
        o.select_set(True)
    bpy.context.view_layer.objects.active = sel[0]
    path = os.path.join(OUT_DIR, "alt" if variant else "", style + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=False, export_texcoords=False, export_normals=True,
        export_materials='EXPORT', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_skins=True, export_def_bones=True, export_leaf_bone=False, export_influence_nb=4,
        export_animations=False, export_morph=False, export_cameras=False, export_lights=False,
        export_extras=False,
    )
    return {"tris": tris, "bones": bones}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    only = None
    if "--only" in ARGS:
        only = ARGS[ARGS.index("--only") + 1].split(",")
    os.makedirs(OUT_DIR, exist_ok=True)
    mats = [make_material("hair", (1, 1, 1, 1)), make_material("hair_shade", (0.55, 0.55, 0.55, 1)),
            make_material("hair_shine", (1, 1, 1, 1))]
    scn = bpy.context.scene
    summary = {}
    for k, (style, fn) in enumerate(STYLES.items()):
        if only and style not in only:
            continue
        coll = bpy.data.collections.new(style)
        scn.collection.children.link(coll)
        summary[style] = export_style(style, fn, mats, coll)
        coll1 = bpy.data.collections.new(style + "_alt")
        scn.collection.children.link(coll1)
        summary[style + "@1"] = export_style(style, fn, mats, coll1, variant=1)
        bpy.context.view_layer.layer_collection.children[style + "_alt"].hide_viewport = True
        if k > 0:
            bpy.context.view_layer.layer_collection.children[style].hide_viewport = True
    print("SUMMARY", summary)
    if "--no-blend" not in ARGS and not only:
        os.makedirs(os.path.dirname(BLEND_OUT), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT, compress=False)
        print("BLEND", BLEND_OUT)


main()
