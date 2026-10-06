"""Black | White obelisks (D140, D145): the two objective stones of the
Obelisks map, low-poly, in the weapon style: grey values per face (vertex
colour), a `body` surface and an `accent` surface (the carved glyphs, which
the game lights and pulses). Reuses build_weapons.py's mesh builder.

    blender -b --factory-startup --python game/tools/blender/build_obelisks.py

Writes (never hand-edit; change this script and rebuild):
    game/art/obelisks/<kind>.glb          surfaces `body` + `accent`
    game/art/obelisks/<kind>.glb.import   import stub (only if missing)
    game/art/obelisks/obelisks.json       sidecar metadata (height, heart point)

Object space (Godot): origin on the hex top centre, +Y up, about 3.2 tall
(a figure is 2.2): the stones tower over the squad. Modelled in the builder's
(x, f, u) space; gd() maps it to Godot (x, u, f).

    lantern  the White Lantern: a stepped hex plinth, a tall four-sided white
             shaft tapering to a pyramid cap, glyphs cut into every face
             (ACCENT), and a halo ring floating over the cap (ACCENT: its light).
    well     the Black Well: a dark plinth, two black glass shards leaning in
             like jaws, and between them a standing ring, the hole for a heart,
             its inner rim and the glyphs on the shards ACCENT (a cold glow).

Deterministic: fixed geometry, fixed order.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_weapons as bw  # noqa: E402  (main() is guarded; this only imports the builder)

OUT_DIR = os.path.join(bw.GAME, "art", "obelisks")
JSON_OUT = os.path.join(OUT_DIR, "obelisks.json")
OBELISKS_VERSION = 1

BODY, ACCENT = bw.BODY, bw.ACCENT
GLYPH = 1.0          # glyph faces are white in the vertex colour; the game tints and lights them


def plinth(w, r0, vals):
    """Stepped hex plinth: three short prisms, widest at the bottom."""
    u = 0.0
    for k, (h, r, v) in enumerate(zip((0.1, 0.1, 0.08), (r0, r0 * 0.84, r0 * 0.7), vals)):
        w.tube([(0, 0, u), (0, 0, u + h)], [r, r * 0.97], sides=6, val=v, phase=0.0)
        u += h
    return u


def glyph(w, centre, along, out, up, size, shape):
    """One carved mark on a face: a few thin boxes in the face's plane, raised
    a hair off it. `along` / `up` span the face, `out` its normal."""
    c = Vector(centre) + Vector(out) * 0.012
    A, U, N = Vector(along), Vector(up), Vector(out)
    s = size

    def bar(p0, p1, t=0.022):
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0)
        if d.length < 1e-6:
            return
        side = d.normalized().cross(N).normalized() * t
        n = N * 0.012
        a0, a1 = c + p0 - side, c + p0 + side
        b0, b1 = c + p1 - side, c + p1 + side
        w.hexa([a0 - n, a1 - n, b1 - n, b0 - n, a0 + n, a1 + n, b1 + n, b0 + n], val=GLYPH, mat=ACCENT)

    if shape == "eye":          # a lozenge with a dot
        pts = [U * s, A * s * 0.7, -U * s, -A * s * 0.7]
        for i in range(4):
            bar(pts[i], pts[(i + 1) % 4])
        bar(-U * s * 0.18, U * s * 0.18, 0.03)
    elif shape == "rise":       # a chevron over a stem
        bar(-A * s * 0.7 - U * s * 0.1, U * s * 0.6)
        bar(A * s * 0.7 - U * s * 0.1, U * s * 0.6)
        bar(-U * s, U * s * 0.2)
    elif shape == "wave":       # a zigzag
        pts = [-A * s * 0.8, -A * s * 0.3 + U * s * 0.5, A * s * 0.2 - U * s * 0.5, A * s * 0.8 + U * s * 0.2]
        for i in range(3):
            bar(pts[i], pts[i + 1])
    elif shape == "gate":       # two posts and a lintel
        bar(-A * s * 0.6 - U * s, -A * s * 0.6 + U * s * 0.8)
        bar(A * s * 0.6 - U * s, A * s * 0.6 + U * s * 0.8)
        bar(-A * s * 0.8 + U * s * 0.8, A * s * 0.8 + U * s * 0.8)
    else:                       # "bar": a single cut
        bar(-U * s, U * s)


def build_lantern(w):
    top = plinth(w, 0.86, (0.55, 0.7, 0.86))
    u0, u1 = top, 2.62
    r0, r1 = 0.42, 0.3
    w.tube([(0, 0, u0), (0, 0, u1)], [r0, r1], sides=4, val=1.0, phase=0.0)
    cap = 3.08
    w.tube([(0, 0, u1), (0, 0, u1 + 0.05), (0, 0, cap)], [r1 + 0.05, r1 + 0.05, 0.0], sides=4, val=0.94, phase=0.0)
    # glyphs: four faces, five marks each, a different order per face
    shapes = ["eye", "rise", "wave", "gate", "bar"]
    for k in range(4):
        a = math.radians(90 * k + 45)          # face normal direction (the 4-sided tube's faces sit between corners)
        out = Vector((math.cos(a), math.sin(a), 0))
        along = Vector((-math.sin(a), math.cos(a), 0))
        for j in range(5):
            u = u0 + 0.28 + j * 0.42
            t = (u - u0) / (u1 - u0)
            apothem = (r0 + (r1 - r0) * t) * math.cos(math.radians(45))
            glyph(w, out * apothem + Vector((0, 0, u)), along, out, Vector((0, 0, 1)), 0.11 - 0.008 * j,
                  shapes[(j + k) % len(shapes)])
    # the halo over the cap: the lantern's light
    w.ring((0, 0, cap + 0.22), 0.34, 0.035, axis="z", segs=12, sides=4, val=GLYPH, mat=ACCENT)
    return dict(height=cap + 0.3, heart=(0, 0, 1.7), halo=(0, 0, cap + 0.22))


def build_well(w):
    top = plinth(w, 0.9, (0.14, 0.09, 0.05))
    # two black glass shards leaning in like jaws (five-sided, pointed)
    for s in (1, -1):
        base = Vector((s * 0.5, 0, top))
        mid = Vector((s * 0.52, 0, top + 1.3))
        tip = Vector((s * 0.2, 0, top + 2.75))
        w.tube([base, mid, tip], [0.2, 0.17, 0.0], sides=5, val=0.012, phase=0.25 if s > 0 else 0.75)
        for j in range(3):                   # glyphs down the inner faces
            u = top + 0.55 + j * 0.55
            x = s * (0.52 - 0.17 * 0.9 + 0.02 * j)
            glyph(w, (x * 0.98, 0.0, u), (0, 1, 0), (-s, 0, 0), (0, 0, 1), 0.09, ["wave", "eye", "bar"][j])
    # the standing ring between them: the hole for a heart
    hc = (0, 0, top + 1.45)
    w.ring(hc, 0.5, 0.11, axis="x", segs=10, sides=6, val=0.02)
    w.ring(hc, 0.385, 0.022, axis="x", segs=20, sides=4, val=GLYPH, mat=ACCENT)
    # a lip under the ring, so it stands on something
    w.tube([(0, 0, top), (0, 0, hc[2] - 0.5)], [0.11, 0.08], sides=5, val=0.03)
    return dict(height=top + 2.85, heart=hc, halo=hc)


OBELISKS = [
    ("lantern", build_lantern, "The White Lantern: white shaft, glyphs on every face, a halo of light over the cap."),
    ("well", build_well, "The Black Well: two black shards leaning in, a standing ring between them (the hole for a heart)."),
]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    mat_body = bw.make_material("body", (1, 1, 1, 1))
    mat_accent = bw.make_material("accent", (0.7, 0.7, 0.7, 1))
    os.makedirs(OUT_DIR, exist_ok=True)
    meta = {}
    for oid, fn, notes in OBELISKS:
        wm = bw.WeaponMesh()
        pts = fn(wm)
        me = wm.build(oid, [mat_body, mat_accent])
        obj = bpy.data.objects.new(oid, me)
        scn.collection.objects.link(obj)
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        acc = sum(len(p.vertices) - 2 for p in me.polygons if p.material_index == ACCENT)
        xs = [v.x for v in wm.verts]
        fs = [v.y for v in wm.verts]
        us = [v.z for v in wm.verts]
        meta[oid] = {
            "height": round(pts["height"], 3),
            "heart": bw.gd(pts["heart"]),
            "halo": bw.gd(pts["halo"]),
            "aabb": {"min": bw.gd((min(xs), min(fs), min(us))), "max": bw.gd((max(xs), max(fs), max(us)))},
            "tris": tris,
            "accent_tris": acc,
            "glb": "res://art/obelisks/%s.glb" % oid,
            "notes": notes,
        }
        print("OBELISK %-8s tris %4d (accent %3d) height %.2f" % (oid, tris, acc, meta[oid]["height"]))
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        glb = os.path.join(OUT_DIR, oid + ".glb")
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
                fh.write(bw.IMPORT_STUB)
    doc = {
        "version": OBELISKS_VERSION,
        "generator": "game/tools/blender/build_obelisks.py",
        "space": "Godot object-local: origin on the hex top centre, +Y up. `heart` is the pulse's origin, `halo` the light.",
        "obelisks": meta,
    }
    with open(JSON_OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print("JSON", JSON_OUT)


if __name__ == "__main__":
    main()
