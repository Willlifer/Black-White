"""Black | White projectiles: arrow, bullet, bolt, built from nothing in the
weapon style (white body, black inverted hull in game, an `accent` surface the
element tints). Sibling of build_weapons.py and reuses its mesh builder.

    blender -b --factory-startup --python game/tools/blender/build_projectiles.py

Writes (never hand-edit; change this script and rebuild):
    game/art/weapons/projectiles/<id>.glb          surfaces `body` + `accent`
    game/art/weapons/projectiles/<id>.glb.import   import stub (only if missing)
    game/art/weapons/projectiles/projectiles.json  sidecar metadata

Projectile space (Godot): the ORIGIN IS THE POINT that leads (the arrow tip,
the bullet's nose, the bolt's centre), +Z is the flight direction, +Y up.
So `Basis.looking_at(velocity, UP, true)` orients one, and a stuck arrow's
origin is the point in the target. Modelled in the weapon builder's (x, f, u)
space with f forward; gd() maps it to Godot (x, u, f).

    arrow   shaft (wood grey), four-sided head (white), three vanes (ACCENT:
            the element), dark nock. 0.9 long: oversized like the bows.
    bullet  a slug (white) with an accent nose band and a tapering white
            tracer streak behind it (the hull draws its ink rim).
    bolt    a faceted crystal shard, back half white, front facets accent,
            two small satellite shards; flown with the aura shader + particles
            in the element colour (BWProjectileView.set_aura).

Deterministic: fixed geometry, fixed order.
"""

import json
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_weapons as bw  # noqa: E402  (main() is guarded; this only imports the builder)

OUT_DIR = os.path.join(bw.GAME, "art", "weapons", "projectiles")
JSON_OUT = os.path.join(OUT_DIR, "projectiles.json")
PROJECTILES_VERSION = 1


def vane(w, angle_deg, f0, f1, r0, height, h=0.0045):
    """One fletching vane: a thin swept quad prism standing out radially."""
    import math
    a = math.radians(angle_deg)
    rad = Vector((math.cos(a), 0, math.sin(a)))       # radial direction in (x, u)
    nrm = Vector((-math.sin(a), 0, math.cos(a)))      # vane thickness direction
    F = Vector((0, 1, 0))
    outline = [(f0, r0), (f1, r0), (f1 + 0.05, r0 + height * 0.85), (f0 + 0.015, r0 + height)]
    pts = [F * f + rad * r for f, r in outline]
    bot = [p - nrm * h for p in pts]
    top = [p + nrm * h for p in pts]
    w.hexa(bot + top, val=0.62, mat=bw.ACCENT)


def build_arrow(w):
    L = 0.9
    w.tube([(0, -L + 0.02, 0), (0, -0.095, 0)], 0.0135, sides=5, val=bw.WOOD)
    # head: a four-sided bodkin, white; a short socket where it meets the shaft
    w.tube([(0, -0.125, 0), (0, -0.095, 0)], 0.019, sides=5, val=bw.IRON)
    w.tube([(0, -0.095, 0), (0, -0.075, 0), (0, 0.0, 0)], [0.016, 0.04, 0.0], sides=4, val=bw.WHITE, phase=0.0)
    for k in range(3):
        vane(w, 90 + 120 * k, -L + 0.05, -L + 0.2, 0.012, 0.05)
    w.box((0, -L + 0.01, 0), (0.016, 0.014, 0.016), val=bw.GRIP)          # the nock
    return dict(tip=(0, 0, 0), tail=(0, -L, 0),
                aura=[(0, -L + 0.12, 0), (0, -0.45, 0), (0, -0.06, 0)])


def build_bullet(w):
    w.tube([(0, -0.05, 0), (0, 0.0, 0)], [0.03, 0.036], sides=6, val=bw.WHITE)
    w.tube([(0, 0.0, 0), (0, 0.03, 0), (0, 0.052, 0)], [0.036, 0.027, 0.0], sides=6, val=bw.EDGE, mat=bw.ACCENT)
    # the tracer: a tapering streak behind the slug (four-sided: reads from any side)
    w.tube([(0, -0.045, 0), (0, -0.3, 0), (0, -0.62, 0)], [0.024, 0.014, 0.0], sides=4, val=bw.WHITE, phase=0.0)
    return dict(tip=(0, 0.052, 0), tail=(0, -0.62, 0),
                aura=[(0, 0.0, 0), (0, -0.2, 0), (0, -0.4, 0)])


def build_bolt(w):
    w.tube([(0, -0.24, 0), (0, -0.03, 0)], [0.0, 0.075], sides=5, val=bw.WHITE)
    w.tube([(0, -0.03, 0), (0, 0.06, 0), (0, 0.19, 0)], [0.075, 0.058, 0.0], sides=5, val=bw.EDGE, mat=bw.ACCENT)
    for s in (1, -1):
        w.tube([(s * 0.1, -0.12, 0.02 * s), (s * 0.11, -0.04, 0.02 * s), (s * 0.1, 0.03, 0.02 * s)],
               [0.0, 0.026, 0.0], sides=4, val=bw.EDGE, mat=bw.ACCENT)
    return dict(tip=(0, 0.19, 0), tail=(0, -0.24, 0),
                aura=[(0, 0.0, 0), (0, 0.12, 0), (0, -0.15, 0), (0.1, -0.04, 0.02), (-0.1, -0.04, -0.02)])


PROJECTILES = [
    ("arrow", build_arrow, "bow", "Shaft, four-sided head, three accent vanes (the element), dark nock."),
    ("bullet", build_bullet, "pistols", "Slug with an accent nose and a white tracer streak behind it."),
    ("bolt", build_bolt, "staff", "Faceted crystal shard, accent front facets, two satellite shards; flies with the aura."),
]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    mat_body = bw.make_material("body", (1, 1, 1, 1))
    mat_accent = bw.make_material("accent", (0.7, 0.7, 0.7, 1))
    os.makedirs(OUT_DIR, exist_ok=True)
    meta = {}
    for pid, fn, used_by, notes in PROJECTILES:
        wm = bw.WeaponMesh()
        pts = fn(wm)
        me = wm.build(pid, [mat_body, mat_accent])
        obj = bpy.data.objects.new(pid, me)
        scn.collection.objects.link(obj)
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        acc = sum(len(p.vertices) - 2 for p in me.polygons if p.material_index == bw.ACCENT)
        xs = [v.x for v in wm.verts]
        fs = [v.y for v in wm.verts]
        us = [v.z for v in wm.verts]
        meta[pid] = {
            "used_by": used_by,
            "tip": bw.gd(pts["tip"]),
            "tail": bw.gd(pts["tail"]),
            "length": round(max(fs) - min(fs), 3),
            "aura_points": [bw.gd(p) for p in pts["aura"]],
            "aabb": {"min": bw.gd((min(xs), min(fs), min(us))), "max": bw.gd((max(xs), max(fs), max(us)))},
            "tris": tris,
            "accent_tris": acc,
            "glb": "res://art/weapons/projectiles/%s.glb" % pid,
            "notes": notes,
        }
        print("PROJECTILE %-7s tris %4d (accent %3d) length %.2f" % (pid, tris, acc, meta[pid]["length"]))
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        glb = os.path.join(OUT_DIR, pid + ".glb")
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
        "version": PROJECTILES_VERSION,
        "generator": "game/tools/blender/build_projectiles.py",
        "space": "Godot projectile-local: origin = the leading point (arrow tip, bullet nose, bolt centre), "
                 "+Z = the flight direction, +Y up. Basis.looking_at(velocity, UP, true) orients one.",
        "projectiles": meta,
    }
    with open(JSON_OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(doc, fh, indent=1)
        fh.write("\n")
    print("JSON", JSON_OUT)


if __name__ == "__main__":
    main()
