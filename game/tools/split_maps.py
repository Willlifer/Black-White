"""D354: builds maps/fords.json, the second Split Front map (6v6).

The Fords, 19x15 (odd-r, the same frame as splitfront.json): a river cut
down column 9 (no hexes: an impassable gorge) splits a west and an east arena.
Three single-hex FORDS cross it at rows 4, 7 and 10; the divider stands on all
three (fire 3, ice pillars or a wind wall segment on each). Breaking any one
ford opens a way through, so the fronts can meet at the north, the middle or
the south: a different divider geometry from Split Front's one 3-hex gap.

  West: the reed marsh. Mud banks along the river, reeds (grass), a raised
        hummock mid-arena, marsh pools seeded water 1-2, two stumps.
  East: the stony bank. The east bank sits a level up (elevation 1) over the
        fords, a cairn hill (2) seeded light 1, rocks, a hollow seeded dark 1.
Each arena is mirrored north-south (rows r and 14-r share parity), so each
front is fair; west and east differ on purpose.

  python tools/split_maps.py        (writes maps/fords.json and prints it)
"""
import json
import os

COLS, ROWS = 19, 15
RIVER_Q = 9
FORDS = [4, 7, 10]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "maps", "fords.json")


def mirror_rows(pts):
    out = []
    for (q, r) in pts:
        out.append((q, r))
        if (q, ROWS - 1 - r) not in out:
            out.append((q, ROWS - 1 - r))
    return out


def build():
    cells = {}
    for r in range(ROWS):
        for q in range(COLS):
            if q == RIVER_Q and r not in FORDS:
                continue                        # the river gorge
            cells[(q, r)] = ["neutral", 0]

    def put(pts, t, e):
        for p in mirror_rows(pts):
            if p in cells:
                cells[p] = [t, e]

    # ---- west: the reed marsh
    put([(8, r) for r in range(0, 7) if r not in (4,)], "mud", 0)       # mud bank
    put([(7, 1), (7, 2), (6, 1), (7, 5), (8, 5)], "grass", 0)            # reeds
    put([(1, 4), (1, 5), (2, 5)], "grass", 0)
    put([(3, 7), (4, 7), (5, 7)], "grass", 1)                            # the hummock
    put([(4, 6), (4, 8)], "grass", 1)
    put([(2, 3)], "rock", 1)                                             # stumps
    # ---- east: the stony bank, a level up
    put([(10, r) for r in range(0, 8)], "neutral", 1)
    put([(11, r) for r in range(0, 8)], "neutral", 1)
    put([(14, 7), (13, 7), (15, 7)], "neutral", 2)                       # the cairn hill
    put([(14, 6), (13, 6), (14, 8), (13, 8)], "neutral", 1)
    put([(16, 4), (12, 3)], "rock", 2)                                   # rocks
    put([(17, 6)], "rock", 3)
    put([(11, 4), (10, 3)], "neutral", 1)
    put([(15, 4), (16, 3)], "mud", 0)                                    # the hollow
    # the fords themselves: level ground, nothing on them (the divider seeds them)
    for r in FORDS:
        cells[(RIVER_Q, r)] = ["neutral", 0]

    seeds = []
    for (q, r, h, v) in [(3, 5, -2, 0), (2, 6, -1, 0), (6, 4, -1, 0),     # marsh pools (water)
                         (14, 7, 0, 1),                                  # the cairn: light 1
                         (15, 4, 0, -1)]:                                # the hollow: dark 1
        for (mq, mr) in mirror_rows([(q, r)]):
            if (mq, mr) in cells and cells[(mq, mr)][0] != "rock":
                if not any(s["q"] == mq and s["r"] == mr for s in seeds):
                    seeds.append({"q": mq, "r": mr, "h": h, "v": v})

    spawns = {"enemy": [[4, 1], [3, 2], [5, 2], [14, 1], [13, 2], [15, 2]],
              "player": [[4, 13], [3, 12], [5, 12], [14, 13], [13, 12], [15, 12]]}
    deploy = {"enemy": [], "player": []}
    for (lo, hi) in [(3, 6), (12, 15)]:
        for r in range(0, 3):
            for q in range(lo, hi + 1):
                deploy["enemy"].append([q, r])
        for r in range(12, 15):
            for q in range(lo, hi + 1):
                deploy["player"].append([q, r])
    for team in deploy:
        for (q, r) in deploy[team]:
            t, e = cells[(q, r)]
            assert t != "rock", (team, q, r)
    out = {
        "name": "The Fords",
        "cols": COLS, "rows": ROWS, "deploy_count": 6,
        "cells": [{"q": q, "r": r, "terrain": t, "elevation": e} for (q, r), (t, e) in sorted(cells.items(), key=lambda kv: (kv[0][1], kv[0][0]))],
        "seeds": seeds,
        "spawns": spawns,
        "deploy": deploy,
        "objective": {"mode": "splitfront", "split_q": RIVER_Q, "divider": [[RIVER_Q, r] for r in FORDS]},
        "notes": "D354 Split Front, the second map (6v6): a river gorge (no hexes) down column 9 splits a west and an east "
                 "arena; three single-hex fords cross it at rows 4, 7 and 10 and the divider (fire, ice or wind, seeded "
                 "per card) stands on all three: break any one and the fronts can meet. West: a reed marsh (mud banks, "
                 "reeds, a raised hummock, marsh pools seeded water). East: a stony bank a level up over the fords, a "
                 "cairn hill seeded light 1, rocks, a hollow seeded dark 1. Each arena mirrored north-south. Built by "
                 "tools/split_maps.py.",
        "camera": {"focus": [9, 7]},
    }
    return out, cells


def show(cells):
    for r in range(ROWS):
        row = "  " if r % 2 else ""
        for q in range(COLS):
            c = cells.get((q, r))
            row += "  " if c is None else c[0][0] + str(c[1])
        print(row)


if __name__ == "__main__":
    data, cells = build()
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    show(cells)
    print("wrote", os.path.normpath(OUT), len(data["cells"]), "cells")
