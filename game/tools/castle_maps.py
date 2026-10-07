"""D335: builds the two castle maps (maps/keep.json for Defend the Castle,
maps/stronghold.json for Storm the Castle) and checks them.

    python tools/castle_maps.py          (from game/)

One castle, two sides: Defend has the keep at the bottom (the player's side),
Storm flips it top-to-bottom (17 rows, so every row keeps its parity and the
flip is exact in odd-r) and the player attacks from the bottom. Hand edits to
the JSON are fine; re-running this overwrites them.
"""
import json, os, sys
from collections import deque

COLS, ROWS = 19, 17
GATE = (9, 10)          # Defend coordinates (keep at the bottom)
KEEP_DOOR = (9, 14)


def neighbors(q, r):
    # odd-r offset (BWHex): odd rows sit half a hex to the right
    if r % 2 == 0:
        d = [(1, 0), (-1, 0), (0, -1), (-1, -1), (0, 1), (-1, 1)]
    else:
        d = [(1, 0), (-1, 0), (1, -1), (0, -1), (1, 1), (0, 1)]
    return [(q + a, r + b) for a, b in d]


def width(r):
    return COLS if r % 2 == 0 else COLS - 1      # odd rows one shorter: an exact left-right mirror


def mirror(q, r):
    return (width(r) - 1 - q, r)


def build_defend():
    cells = {}

    def put(q, r, t="neutral", e=0):
        cells[(q, r)] = [t, e]

    for r in range(ROWS):
        for q in range(width(r)):
            if r <= 9:
                put(q, r)                       # the field, the moat, the berm
            elif 3 <= q <= width(r) - 4:
                put(q, r)                       # the keep's footprint
    # the field: grass, cover rocks
    for (q, r) in [(2, 3), (3, 3), (2, 4), (1, 5), (2, 5), (6, 4), (7, 4), (6, 5)]:
        for h in [(q, r), mirror(q, r)]:
            put(*h, "grassy", 0)
    for (q, r) in [(4, 2), (8, 5), (1, 8)]:
        for h in [(q, r), mirror(q, r)]:
            put(*h, "jagged", 2)
    put(9, 3, "neutral", 1)                     # a low rise in the middle of the approach
    put(9, 4, "neutral", 1)
    put(8, 4, "neutral", 1)
    # the berm in front of the wall
    for q in range(width(9)):
        put(q, 9, "neutral", 0)
    # the curtain wall (row 10), corner towers, the gate, the two breaches
    for q in range(3, 16):
        put(q, 10, "neutral", 3)
    put(3, 10, "neutral", 4)
    put(15, 10, "neutral", 4)
    put(*GATE, "neutral", 0)
    for b in [5, 13]:
        put(b, 10, "neutral", 2)                # a broken stretch: rubble at 2
    put(5, 9, "neutral", 1)                     # the rubble spills out onto the berm
    put(12, 9, "neutral", 1)
    for h in [(4, 11), (5, 11), (12, 11), (13, 11)]:
        put(*h, "jagged", 3)                    # fallen masonry inside: the breach leads onto the wall walk only
    # the side walls and the back wall
    for r in range(11, ROWS):
        put(3, r, "neutral", 3)
        put(width(r) - 4, r, "neutral", 3)
    for q in range(3, 16):
        put(q, 16, "neutral", 3)
    # stairs from the courtyard up to the wall walk
    put(6, 12, "neutral", 1); put(6, 11, "neutral", 2)
    put(12, 12, "neutral", 1); put(11, 11, "neutral", 2)
    # the keep: a tower block behind the keep door
    for h in [(8, 15), (9, 15), (8, 16), (9, 16), (10, 16)]:
        put(*h, "jagged", 6)
    put(7, 15, "jagged", 5); put(10, 15, "jagged", 5)
    put(*KEEP_DOOR, "neutral", 0)
    # a little ground texture in the courtyard
    for h in [(5, 13), (13, 13), (5, 14), (13, 14)]:
        put(*h, "grassy", 0)
    # the outer flanks: drop away (void) beside the side walls below row 10
    statics = []
    for q in range(width(7)):
        statics.append((q, 7, -2, 0))
    for q in range(width(8)):
        statics.append((q, 8, -2, 0))
    bridge = {(8, 7), (9, 7), (8, 8), (9, 8), (10, 8)}
    statics = [s for s in statics if (s[0], s[1]) not in bridge and cells[(s[0], s[1])][0] != "jagged"]
    braziers = [(7, 9), (10, 9)]
    for (q, r) in braziers:
        statics.append((q, r, 2, 0))
    spawns_enemy = [(9, 1), (7, 1), (11, 1), (5, 0), (13, 0), (9, 0)]
    spawns_player = [(7, 10), (11, 10), (9, 12), (8, 12), (10, 12), (8, 11)]
    # zones of at most 24 (test_maps): the enemy's the middle of its three edge
    # rows; the squad's the wall walk, the row behind the gate and the yard's
    # front row (the castle's exception to "the three edge rows", D335)
    deploy_enemy = [(q, r) for r in range(0, 3) for q in (range(5, 14) if r == 0 else range(6, 13)) if cells[(q, r)][0] != "jagged"]
    deploy_player = [(q, 10) for q in range(4, 15) if (q, 10) != GATE]         + [(q, 11) for q in range(6, 12)] + [(q, 12) for q in range(6, 13)]
    return {
        "cells": cells, "statics": statics, "spawns": {"enemy": spawns_enemy, "player": spawns_player},
        "deploy": {"enemy": deploy_enemy, "player": deploy_player},
        "gate": GATE, "keep": [KEEP_DOOR], "braziers": braziers,
        "waves_at": [(1, 0), (3, 0), (15, 0), (17, 0), (0, 1), (17, 1), (2, 1), (15, 1)],
    }


def flip(h):
    return (h[0], ROWS - 1 - h[1])


def build_storm(d):
    cells = {flip(h): v for h, v in d["cells"].items()}
    statics = [(q, ROWS - 1 - r, a, b) for (q, r, a, b) in d["statics"]]
    gate = flip(d["gate"])
    throne = flip(KEEP_DOOR)                     # the throne stands where Defend's keep door is
    # the back door: a gap in the back wall (row 0) the reinforcements come through
    back = [(4, 0), (14, 0)]
    for h in back:
        cells[h] = ["neutral", 0]
    # the courtyard by the back door
    warden = (9, 3)
    spawns_enemy = [(7, 6), (11, 6), (6, 6), (12, 6), (9, 4), warden]  # four on the wall, one in the yard, the Warden
    spawns_enemy = [(8, 6), (10, 6), (6, 6), (12, 6), (9, 4), warden]
    spawns_player = [(9, 15), (7, 15), (11, 15), (5, 16), (13, 16), (9, 16)]
    deploy_player = [flip(h) for h in d["deploy"]["enemy"]]
    deploy_enemy = [flip(h) for h in d["deploy"]["player"]]
    deploy_enemy = sorted(set(deploy_enemy) | {warden, (9, 4)})
    return {
        "cells": cells, "statics": statics, "spawns": {"enemy": spawns_enemy, "player": spawns_player},
        "deploy": {"enemy": deploy_enemy, "player": deploy_player},
        "gate": gate, "throne": throne, "warden": warden, "braziers": [flip(h) for h in d["braziers"]],
        "back_door": [(4, 1), (5, 1), (13, 1), (12, 1), (4, 2), (13, 2)],
    }


def step_cost(cells, a, b):
    if b not in cells or cells[b][0] == "jagged":
        return -1
    rise = cells[b][1] - cells[a][1]
    if rise > 2:
        return -1
    return (2 if cells[b][0] == "muddy" else 1) + max(rise, 0)


def walk(cells, start, statics=()):
    water = {(q, r): (1 if a == -2 else 2 if a == -3 else 0) for (q, r, a, b) in statics}
    dist = {start: 0}
    pq = [(0, start)]
    while pq:
        pq.sort()
        c, h = pq.pop(0)
        if c > dist[h]:
            continue
        for n in neighbors(*h):
            sc = step_cost(cells, h, n)
            if sc < 0:
                continue
            sc += water.get(n, 0)
            if c + sc < dist.get(n, 1 << 30):
                dist[n] = c + sc
                pq.append((c + sc, n))
    return dist


def to_json(name, d, extra, notes):
    cells = [{"q": q, "r": r, "terrain": t, "elevation": e} for (q, r), (t, e) in sorted(d["cells"].items(), key=lambda kv: (kv[0][1], kv[0][0]))]
    out = {
        "name": name, "cols": COLS, "rows": ROWS, "deploy_count": 6,
        "cells": cells,
        "statics": [{"q": q, "r": r, "h": a, "v": b} for (q, r, a, b) in d["statics"]],
        "spawns": {k: [list(h) for h in v] for k, v in d["spawns"].items()},
        "deploy": {k: [list(h) for h in v] for k, v in d["deploy"].items()},
        "objective": extra,
        "notes": notes,
        "camera": {"focus": [9, 8]},
    }
    return out


def check(name, d, gate, extra_targets):
    errs = []
    cells = d["cells"]
    for team in ("enemy", "player"):
        sp = d["spawns"][team]
        if len(set(sp)) != 6:
            errs.append(f"{name}: {team} needs 6 distinct spawns")
        for h in sp:
            if h not in cells or cells[h][0] == "jagged":
                errs.append(f"{name}: {team} spawn {h} not standable")
            if h not in d["deploy"][team]:
                errs.append(f"{name}: {team} spawn {h} outside its zone")
    # the gate is the only ground way in (besides the breaches onto the wall walk)
    attackers = "enemy" if name == "keep" else "player"
    start = d["spawns"][attackers][0]
    blocked = dict(cells)
    blocked[gate] = ["jagged", 0]
    dist = walk(blocked, start, d["statics"])
    for t in extra_targets:
        if t not in dist:
            errs.append(f"{name}: {t} unreachable for the attackers with the gate shut")
    # every wall perch has a melee route of at most 2 turns (8 move) from the berm
    berm = [h for h in cells if h[1] == (9 if name == "keep" else 7) and cells[h][0] != "jagged"]
    perches = [h for h in cells if cells[h][1] >= 3 and cells[h][0] != "jagged" and h[1] == (10 if name == "keep" else 6)]
    far = []
    for p in perches:
        best = min((walk(blocked, b, d["statics"]).get(p, 99) for b in berm[::3]), default=99)
        if best > 8:
            far.append((p, best))
    if far:
        errs.append(f"{name}: perches beyond the 2-turn melee route: {far}")
    gd = walk(cells, start, d["statics"])
    adj = [n for n in neighbors(*gate) if n in gd]
    print(f"{name}: {len(cells)} cells, walk to the gate {min(gd[n] for n in adj) if adj else '?'} move, "
          f"perch routes ok={not far}")
    return errs


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    d = build_defend()
    s = build_storm(d)
    errs = check("keep", d, d["gate"], [KEEP_DOOR]) + check("stronghold", s, s["gate"], [s["throne"]])
    if errs:
        print("\n".join(errs))
        sys.exit(1)
    keep = to_json("Keep", d, {
        "mode": "defend", "gate": list(d["gate"]), "gate_kind": "iron",
        "keep": [list(h) for h in d["keep"]], "braziers": [list(h) for h in d["braziers"]],
        "waves_at": [list(h) for h in d["waves_at"]],
    }, "D335 Defend the Castle (6v6): a walled keep on the player's side. Curtain wall at elevation 3 (corner towers 4), "
       "an iron gate at (9,10) (an objective with HP), two breaches (rubble 1-2) that reach the wall walk only, inner stairs, "
       "a moat of static water 2 across rows 7-8 with a two-wide bridge, two braziers (static fire 2) on the berm, the keep door (9,14). "
       "Built by tools/castle_maps.py.")
    storm = to_json("Stronghold", s, {
        "mode": "storm", "gate": list(s["gate"]), "gate_kind": "wood",
        "throne": list(s["throne"]), "warden": list(s["warden"]), "braziers": [list(h) for h in s["braziers"]],
        "back_door": [list(h) for h in s["back_door"]],
    }, "D335 Storm the Castle (6v6): Defend's castle flipped top to bottom, the player attacking from the south. A wooden gate "
       "at (9,6) (fire x1.5), the throne at (9,2) with the Warden beside it, back doors in the north wall at (4,0) and (14,0) "
       "where reinforcements enter until the gate falls. Built by tools/castle_maps.py.")
    for fname, data in [("keep.json", keep), ("stronghold.json", storm)]:
        with open(os.path.join(root, "maps", fname), "w", newline="\n") as f:
            json.dump(data, f, indent=1)
        print("wrote maps/" + fname)


if __name__ == "__main__":
    main()
