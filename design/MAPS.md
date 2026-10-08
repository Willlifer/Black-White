# Black | White battle maps

The battle maps are in `game/maps/*.json`: the 3v3 maps (§1–§11) and the 6v6
maps (§12 on). They use the format that `BWBoard.from_dict()` loads
(`game/src/core/board.gd`), plus the extra fields `deploy` (the zones),
`deploy_count`, `notes` and `camera.focus`. On every map the enemy starts at
the top (row 0) and the player at the bottom.

**Deploy counts (D319).** `deploy_count` is how many units each side fields:
absent means 3 (every 3v3 map), 6 on a 6v6 map. The squad fields
min(deploy_count, its size); the enemy fields the map's count (as many as the
roster outside the squad can spare). A map needs `deploy_count` spawns a side,
all inside that side's zone (`tests/test_maps.gd`). Unplaced units start on
the spawns, then the free zone hexes nearest the first spawn (D320).

| Maps | deploy_count | Size | In the rotation |
|---|---|---|---|
| Arena … Court (§1–§11) | 3 (absent) | 9×17 to 17×13 | yes (Commons excepted) |
| Commons (§12) | 6 | 17×15 | no: a test map (`--combat commons`) |
| Keep, Stronghold (§13–§14) | 6 | 19×17 | the 6v6 pool: Defend / Storm the Castle cards, fights 7–10 (D353) |
| Split Front, The Fords (§15, §17) | 6 | 19×15 | fight 5's two cards; the 6v6 pool, fights 7–10 (D353, D354) |
| The Horde Road (§16) | 6 | 19×15 | the 6v6 pool: Stop the Horde cards, fights 7–10 (D353) |

## Reading the pictures

Each hex is a terrain letter followed by its elevation as a hex digit (0–f).
Odd rows are indented half a hex (pointy-top odd-r, as in `hex.gd`).

| Mark | Meaning |
|---|---|
| `n` | neutral |
| `g` | grassy: fire spreads across it |
| `m` | muddy: each step costs 2 |
| `j` | jagged: impassable and blocks sight. Its elevation only sets how tall it looks. |
| `.` | void (no cell) |
| `E` / `P` | default enemy / player spawn, on neutral ground |
| suffix `w`/`f`/`l`/`d` + 1–3 | static charge (D115): water / fire / light / dark at that level, e.g. `n0w3` |

In the four static maps (6–9) both halves are drawn and spawns show as `E`
on both sides; the bottom three are the player's.

These rules shaped the maps (D17, D20):
- Every unit moves 4 hexes (daggers 5).
- A step can rise at most the walker's jump (2; D371), and since D375 a
  climb within the jump costs no extra move. Drops are free.
- Line of sight is blocked by jagged hexes, and by any hex that stands 2 or
  more levels above both ends.

## Shared conventions

- **Spawns:** each side has `deploy_count` spawns (3, or 6 on a 6v6 map), all
  inside its own deploy zone. No two spawns overlap.
- **Deploy:** this is the brief's "3 rows opposite the enemy". Each zone takes
  the 3 rows at that team's own edge, keeps the hexes closest to the centre
  line, and holds at most 12 hexes. The player zone is an exact mirror of the
  enemy zone (an exact 180° rotation on Tinderbox). The one exception is
  Ravine, which is asymmetric.
- **Symmetry:** in odd-r layout, an exact left-right mirror needs odd rows to
  be one hex shorter than even rows. That is why the symmetric maps have a
  ragged right edge on odd rows. With an odd number of rows, every row keeps
  its parity when the map is flipped top to bottom, so that mirror is exact.
- **First contact:** on most maps the spawns are 8–12 hexes apart. Bridge is
  the exception at 16, but most of that distance is a free downhill walk.
  After one turn of moving, ranged units are in range on turn 2.
- **Script checks:** a script checked these things:
  - every spawn and deploy hex exists and is not jagged;
  - every spawn can walk to an enemy spawn, using the `step_cost` rule from
    `board.gd`;
  - no two spawns overlap.

  It also flags standable hexes that no unit can walk to. Only Tinderbox's
  berm has these, and that is on purpose.

---

## 1. Arena (`arena.json`, 11×11, 91 cells)

```
     0  1  2  3  4  5  6  7  8  9  10 
  0   .  .  . n0 E0 n0 n0 E0 n0  .  .
  1    .  . n0 j3 n0 E0 n0 j3 n0  .  .
  2   .  . n0 n0 n0 n0 n0 n0 n0 n0  .
  3    . n0 n0 n0 n1 n1 n1 n0 n0 n0  .
  4   . n0 g0 n0 n1 n2 n2 n1 n0 g0 n0
  5   n0 j3 g0 n1 n2 n2 n2 n1 g0 j3 n0
  6   . n0 g0 n0 n1 n2 n2 n1 n0 g0 n0
  7    . n0 n0 n0 n1 n1 n1 n0 n0 n0  .
  8   .  . n0 n0 n0 n0 n0 n0 n0 n0  .
  9    .  . n0 j3 n0 P0 n0 j3 n0  .  .
 10   .  .  . n0 P0 n0 n0 P0 n0  .  .
```

**Intent.** This is a symmetric hexagonal arena (radius 5 around (5,5)) and
the title-screen backdrop.
- A raised dais at elevation 2 sits in the middle, ringed by steps at
  elevation 1.
- Six jagged pillars stand one hex in from each corner.
- Two small grass wedges on the east and west flanks give fire users something
  to light.

From the dais a unit can see 79 of the 85 hexes within range 6, so the dais is
the obvious prize. Getting onto it from the floor costs 2 extra moves.

**Decisions I made**
- I made the arena a true hexagon, not a rectangle. It looks the same from
  either side, flipped top to bottom or left to right. That means it looks
  good from any point on the title-screen orbit. The orbit should circle
  `camera.focus` (5,5).
- I built the "ramps" as a full ring of elevation-1 hexes around the dais.
  Every approach is a 1-level step, so no face of the dais is a dead side.
- I used six pillars instead of four, one for each corner of the hexagon. They
  are jagged at elevation 3, so they read as columns.
- The spawns form a triangle: two on the back edge and one a row forward. On
  an odd-r edge row, this is the only way to place 3 spawns symmetrically.
- I kept the grass small (6 hexes), because this is the "fair" map.

## 2. Paintball (`paintball.json`, 11×11, 116 cells)

```
     0  1  2  3  4  5  6  7  8  9  10 
  0  n0 n0 n0 E0 n0 E0 n0 E0 n0 n0 n0
  1   n0 n0 n0 n0 n0 n0 n0 n0 n0 n0  .
  2  n0 j1 n0 n0 n0 n0 n0 n0 n0 j1 n0
  3   n0 n0 n2 n2 n0 n0 n2 n2 n0 n0  .
  4  n0 n0 n0 n0 j1 m0 j1 n0 n0 n0 n0
  5   n0 j1 m0 m0 m0 m0 m0 m0 j1 n0  .
  6  n0 n0 n0 n0 j1 m0 j1 n0 n0 n0 n0
  7   n0 n0 n2 n2 n0 n0 n2 n2 n0 n0  .
  8  n0 j1 n0 n0 n0 n0 n0 n0 n0 j1 n0
  9   n0 n0 n0 n0 n0 n0 n0 n0 n0 n0  .
 10  n0 n0 n0 P0 n0 P0 n0 P0 n0 n0 n0
```

**Intent.** This is a mirrored speedball field. Each half has:
- two 1-hex jagged "can" bunkers near the back corners;
- two 2-hex walls at elevation 2, which hide ground units from each other;
- a jagged pair on either side of a muddy centre alley.

A muddy band across row 5 makes rushing the middle cost double. The edge
columns stay open from end to end. They are long lanes for bows (range 6) and
pistols (range 5).

**Decisions I made**
- The "2-high walls" are neutral hexes at elevation 2, not jagged. They still
  block sight between ground units under D20, because they stand 2 levels
  above both ends. A unit can climb onto one for 2 extra moves. From there it
  sees 13 of the 25 far-half hexes within range 6, but it is fully exposed, so
  the wall works as a risky perch. The bunkers are jagged, as the brief asked.
- The field is mirrored both left-right and top-bottom, so it looks the same
  from any corner.
- The mud is 3 rows deep at the centre and 1 row deep on the flanks. Going
  through the middle is the shortest route but the slowest. Going round the
  edge is longer but stays out of the mud.

## 3. Bridge (`bridge.json`, 9×17, 85 cells)

```
     0  1  2  3  4  5  6  7  8  
  0   . n5 n5 E5 E5 E5 n5 n5  .
  1    . j6 n5 n5 n5 n5 j6  .  .
  2   . n5 n5 n5 n5 n5 n5 n5  .
  3    .  . n5 n5 n5 n5  .  .  .
  4   .  .  . n4 n4 n4  .  .  .
  5    .  . n3 n3 n3 n3  .  .  .
  6   .  .  . n2 n2 n2  .  .  .
  7   n0 n0 g2 g2 g2 g2  .  .  .
  8   . n0 n0 g2 g2 g2  .  .  .
  9   n0 n0 g2 g2 g2 g2  .  .  .
 10   .  .  . n2 n2 n2  .  .  .
 11    .  . n3 n3 n3 n3  .  .  .
 12   .  .  . n4 n4 n4  .  .  .
 13    .  . n5 n5 n5 n5  .  .  .
 14   . n5 n5 n5 n5 n5 n5 n5  .
 15    . j6 n5 n5 n5 n5 j6  .  .
 16   . n5 n5 P5 P5 P5 n5 n5  .
```

**Intent.** This map follows Hyrule Temple's bridge.
- Each end is a raised platform at elevation 5, with two jagged pillars for
  cover.
- Stairs lead down (5→4→3→2) to a span over void. The span is 3–4 hexes wide
  and sits at elevation 2.
- The middle of the span (rows 7–9) is grass, like wooden planks, so fire can
  cut the bridge in half.
- An under-ledge at elevation 0 sits on the west side. Stepping down onto it
  is free, and climbing back up is a 2-level step (free since D375). From the ledge, units can
  flank or shoot upward: it sees 31 hexes within range 6.

**Decisions I made**
- The bridge runs vertically (17 rows). That way "deploy in 3 rows" means the
  same thing here as on every other map.
- The span alternates between 3 and 4 hexes wide. In odd-r, a vertical strip
  of constant width zigzags, and alternating the width keeps it centred on
  x=4.
- The map is mirrored top to bottom, so there is one ledge, in the middle,
  and both teams can reach it equally.
- The spawns are 16 hexes apart. The stairs down are free drops, so each side
  reaches the top of the span on turn 1, and ranged units engage on turn 2.

## 4. Ravine (`ravine.json`, 12×13, 156 cells), asymmetric

```
     0  1  2  3  4  5  6  7  8  9  10 11 
  0  n3 n3 n3 n3 n3 n3 E3 n3 n3 n3 n3 n3
  1   n3 n3 n3 E3 n3 n3 n3 n3 E3 n3 n3 n3
  2  n3 n3 j4 n3 n3 n3 n3 n3 n3 j4 n3 n3
  3   n3 n3 n3 n3 n3 n3 j4 n3 n3 n3 n3 n3
  4  n3 n2 n3 n3 n3 n3 n3 n3 n3 n3 n3 n3
  5   m0 n1 m0 m0 m0 m0 m0 m0 m0 m0 m0 m0
  6  m0 m0 m0 m0 m0 j1 m0 m0 m0 n2 n2 m0
  7   g4 g4 g4 g4 g4 g4 g4 g4 g4 g4 g4 g4
  8  g3 g3 g4 g4 g3 g3 g3 g3 g3 g3 g3 g3
  9   g2 g2 g3 g3 g2 g2 j3 g2 g2 g2 g2 g2
 10  n1 g1 g2 g2 g1 g1 g1 g1 g1 g1 g1 n1
 11   n0 n0 n1 n1 P0 n0 n0 n0 P0 n0 n0 n0
 12  n0 n0 n0 n0 n0 n0 P0 n0 n0 n0 n0 n0
```

**Intent.** The player starts at the foot of a grassy hill. The hill climbs
0→1→2→3→4 in 1-level rows to a crest at elevation 4. Below the crest is a
muddy ravine floor at elevation 0, 2 rows deep. The enemy holds a flat neutral
plateau at elevation 3 on the far lip.

Both ravine walls are too steep to climb straight up: the enemy side rises 3
levels and the player side rises 4. Each side has one climbable path, and they
are at opposite ends:
- **West, enemy side:** floor 0 → 1 → 2 → plateau 3.
- **East, player side:** floor 0 → 2 → crest 4.

Anyone can drop into the ravine for free. Getting out means wading through mud
to the right ramp, so a melee crossing always runs on a diagonal.

**Which side gets the hill, and why that is fair.** The player gets it. The
crest is the highest ground on the map (4 against 3), but it has three
costs:
1. Climbing to it takes about 8 moves. The enemy reaches its lip in one
   turn.
2. The whole slope is grass, so one enemy fire spell can spread across the
   player's approach. The enemy's plateau cannot burn.
3. The crest has no cover.

The enemy keeps the cheap, safe ground, and the player pays for the view. From
the crest, a unit sees 25 of the 32 plateau hexes within range 6. From the lip,
an enemy sees 22 of the 33 hill hexes.

**Decisions I made**
- The ravine floor is made of low cells, not void. Dropping in is a real
  tactical option, not a death pit.
- There are two exits, one in each wall, at opposite corners. This forces a
  diagonal crossing, so no single choke can be held from both sides.
- A spur in columns 2–3 rises a level ahead of the rest of the slope. It is a
  cheaper partial climb on the west.
- Ranged units meet on turn 2. Melee units meet on turn 3. This map is a
  shooting gallery first.

## 5. Tinderbox (`tinderbox.json`, 13×13, 163 cells), my own map

```
     0  1  2  3  4  5  6  7  8  9  10 11 12 
  0  n0 n0 n0 E0 n0 n0 E0 n0 E0 n0 n0 n0 n0
  1   n0 n0 n0 n0 n0 n0 n0 n0 n0 n1 n2 n0  .
  2  g0 g0 n0 n0 g0 g0 n0 n0 n0 j3 n4 n4 n0
  3   g0 g0 g0 g0 g0 j1 g0 g0 g0 g0 n4 g0  .
  4  g0 g0 g0 g0 g0 g0 g0 g0 g0 g0 g0 g0 g0
  5   g0 g0 j1 g0 g0 g0 g0 g0 g0 g0 g0 g0  .
  6  m0 m0 n3 n3 n3 n3 g0 n3 n3 n3 n3 m0 m0
  7   g0 g0 g0 g0 g0 g0 g0 g0 g0 j1 g0 g0  .
  8  g0 g0 g0 g0 g0 g0 g0 g0 g0 g0 g0 g0 g0
  9   g0 n4 g0 g0 g0 g0 j1 g0 g0 g0 g0 g0  .
 10  n0 n4 n4 j3 n0 n0 n0 g0 g0 n0 n0 g0 g0
 11   n0 n2 n1 n0 n0 n0 n0 n0 n0 n0 n0 n0  .
 12  n0 n0 n0 n0 P0 n0 P0 n0 n0 P0 n0 n0 n0
```

**Intent.** An earth berm at elevation 3 cuts a grass meadow in half. Units on
the ground cannot climb it, and it hides each side's ground units from the
other. The berm has three gaps:
- **Two muddy fords at the edges.** These are slow chokepoints, and fire
  cannot cross them.
- **One grassy gap in the centre.** It works as a fuse: fire lit on one side
  can burn through to the other.

Each side has a stone sniper perch at elevation 4, on that side's left flank,
so the two perches face each other across the diagonal. A unit reaches its
perch by a back staircase (0→1→2→4), which takes two turns. From the perch it
can see over the berm into the near half of the enemy meadow: 13 of 16 hexes
within range 6. A ground unit standing beside the berm sees none of the far
side.

**What should emerge**
- Burning the meadow forces units out to the fords. Mud is slow, so the fords
  become killing lanes for the enemy perch.
- The centre gap is the fastest route, and it is also the fire's route.
  Holding it means standing on the fuse.
- A side can deny the enemy perch by burning the grass at the foot of its
  tower. The stairs are neutral, so the perch is never cut off, only dangerous
  to reach.

**Decisions I made**
- The map uses 180° rotational symmetry instead of a mirror. That puts each
  side's perch opposite the other side's weak flank, so the sniper duel runs
  on a diagonal.
- The berm is neutral at elevation 3, not jagged. Under D20, jagged hexes
  always block sight, so a jagged berm would block the perches too. At
  elevation 3 the berm blocks ground sight, but perches at elevation 4 see
  over it.
- No unit can walk onto the berm's 8 hexes, even though they are standable.
  The checker flags them as scenery, and that is on purpose. If a staircase
  reached the berm, the berm would become a free bridge, because dropping off
  either side costs nothing.
- I named it Tinderbox because the meadow is almost all grass.

---

## Static tiles (D115–D117)

A **static** hex has a permanent floor charge: the map's, nobody's. The
rules are ELEMENTS.md §5.5. In short:

- It is laid at the start, never decays, and **re-forms at every cycle
  tick**. Painting on it works for the rest of that cycle: fire steps static
  water 3 to water 2, a gale copies it, ice glazes it (a frozen lake is
  walkable), and a second axis painted on top decays normally while the
  static axis holds.
- **A detonation spends it.** Thunder on a static hex blows it as usual
  (static water 3 = a 23% blast), and the hex then stays empty through the
  *next* cycle too, re-forming at the tick after. Consume spends it the same
  way. So static water is a bomb every other cycle at best, not every turn.
- Static fire burns standing and crossing units like any fire. It never
  ignites grass (restored entries count as spread, not cast).
- Perks read it as normal ground: Undertow pulls toward static water 3,
  Shadowstep jumps between static dark hexes, Coal Engine and Heat Rush run
  on static fire, Waterwalking crosses its first static water hex each turn free (D204).
- **The look** (BWBoardView, D116): an inlaid rim cut into the tile, an ink
  ring, a band in the element's colour, an inner ink ring, and six ink
  wedges notched in from the corners with a small colour lozenge at each
  tip. It sits above the element FX, so it reads under blazing fire, while
  the charge is stepped down, and while the static is spent. The element
  FX draw on top of the face as for any charge.

## Static vs seeded: guidance for future maps (D134–D136)

Two kinds of map charge. Both use the same `h` / `v` values; they differ in
what happens once play touches them.

| | **Static** (`"static"`, D115) | **Seeded** (`"seed"`, D134) |
|---|---|---|
| Start | charged | charged |
| On its own | never decays, re-forms every tick | never decays (holds) |
| Painted / operated on | works for the cycle, then snaps back | becomes ordinary charge for good |
| Thunder / Consume | blows it, back two ticks later | blows it, gone for the fight |
| Look | inlaid rim with corner wedges (always) | thin element-colour ring with a white hairline, **only while untouched** |

Rules of thumb:

- **Seed the ground, make the landmarks static.** A floor that starts dark
  and gets overwritten is a fight about the floor; a floor that stays dark
  all game removes options (author, 2026-10-05). Default to seeded.
- Keep statics **few and small**: one hex or one line that defines the map
  (the tomb heart, the deep lake, the forge channel, the altar). A static
  area larger than ~10 hexes needs a reason.
- Every seeded area should be answerable by at least one common element: an
  opposite that steps it down (light vs dark, water vs fire), thunder that
  consumes it, or a second axis that adds to it.
- Format: the same two forms as statics, with the key `seed` per cell or a
  top-level `seeds` list (`{ "q", "r", "h", "v" }`). A hex is one or the
  other; both on one hex is a load error and the static wins.

### Map format (hand-edit)

The HexMapEditor only writes `q, r, terrain, elevation` per cell, so it
can't carry a static. It does keep unknown top-level keys when it re-saves.
Two forms load (`BWBoard.from_dict`); seeds use the same forms with `seed` /
`seeds`:

```json
{ "q": 6, "r": 5, "terrain": "neutral", "elevation": 0, "static": { "h": -3 } }
```
per cell (what the shipped maps use; a re-save in the editor drops it), or

```json
"statics": [ { "q": 6, "r": 5, "h": -3 }, { "q": 6, "r": 6, "v": 2 } ]
```
at the top level, which survives an editor round-trip. `h`: water −3 … +3
fire, `v`: dark −3 … +3 light; one or both. A static on a jagged hex, a
missing cell or (0, 0) is a load error. (The editor would also rename the
B|W terrain kinds on re-save, so these maps are edited by hand anyway.)

The four maps below are mirrored top to bottom (13 rows, so the mirror is
exact): both sides get the same ground. A script checked spawns, deploy
zones and walk costs, with static water's move cost included. Every spawn
reaches the nearest foe spawn in 12–14 move (3–3.5 turns), and no standable
hex is out of reach. `test_maps` plays an AI fight on each one, and
`test_static_tiles` plays another with the static-reading perks (rounds at
seed 11: lake 13, catacombs 12, forge 9, chapel 10).

Renders from the gameplay camera, battle start: `design/art/maps_lake.png`,
`maps_catacombs.png`, `maps_forge.png`, `maps_chapel.png`.

## 6. Lake (`lake.json`, 13×13, 159 cells, 10 static, 42 seeded)

```
     0    1    2    3    4    5    6    7    8    9    10   11   12
  0   .   g2   n2   n2   n2   E2   n2   E2   n2   n2   n2   g2    .
  1    g2   n2   j4   n2   n2   n2   E2   n2   n2   j4   n2   g2    .
  2  g2   g2   n2   n1   n1   n1   n1   n1   n1   n1   n2   g2   g2
  3    g1   g1   n1   n1   g1   j2   n1   j2   g1   n1   n1   g1    .
  4  n0w1 n0w1 n0w1 n1   n0w1 n0w1 n0w2 n0w1 n0w1 n1   n0w1 n0w1 n0w1
  5    n0w1 n0w2 n0w2 n1   n0w2 n0w3 n0w3 n0w3 n0w2 n1   n0w2 n0w2  .
  6  n0w2 n0w2 n0w2 n1   n0w3 n0w3 n1   n0w3 n0w3 n1   n0w2 n0w2 n0w2
  7    n0w1 n0w2 n0w2 n1   n0w2 n0w3 n0w3 n0w3 n0w2 n1   n0w2 n0w2  .
  8  n0w1 n0w1 n0w1 n1   n0w1 n0w1 n0w2 n0w1 n0w1 n1   n0w1 n0w1 n0w1
  9    g1   g1   n1   n1   g1   j2   n1   j2   g1   n1   n1   g1    .
 10  g2   g2   n2   n1   n1   n1   n1   n1   n1   n1   n2   g2   g2
 11    g2   n2   j4   n2   n2   n2   E2   n2   n2   j4   n2   g2    .
 12   .   g2   n2   n2   n2   E2   n2   E2   n2   n2   n2   g2    .
```

**Intent.** A basin around a deep lake. The deploy shelves (elev 2) step
down to a shore (elev 1), then to a lake at elev 0:
- the middle is **static water 3** (10 hexes, +2 move to enter) around a
  dry island at elev 1;
- water 2 (+1 move) and water 1 (free, still wet) shallows fill the rest.
  D136: the shallows are **seeded**: wet from the start, but fire dries
  them for good; only the deep water 3 is static;
- two **dry causeways** (elev 1) run straight across on columns 3 and 9.

Walking the causeways is fast but leaves a unit standing in a line. Wading
is slow. The island is the high point in the middle, but anyone reaching it
stands in a ring of deep water: one thunder detonation there is a 23% blast
with half splash. **Undertow** turns the whole lake into a magnet, because
static water 3 always exists. **Waterwalking** makes one lake hex a turn free (D204).
**Flow State**, **Tidal Guard** and **Current Push** have water everywhere.

## 7. Catacombs (`catacombs.json`, 13×13, 159 cells, 1 static, 58 seeded)

```
     0    1    2    3    4    5    6    7    8    9    10   11   12
  0   .   n2   n2   n2   n2   E2   n2   E2   n2   n2   n2   n2    .
  1    n2   n2   n2   n2   n2   n2   E2   n2   n2   n2   n2   n2    .
  2  j3   n2   n1   n1   j3   n1   n1   n1   j3   n1   n1   n2   j3
  3    j3   n0d2 j3   n0d2 j3   n0d2 n0d2 j3   n0d2 j3   n0d2 j3    .
  4  n0d2 n0d2 j3   n0d2 n0d2 n0d2 j3   n0d2 n0d2 n0d2 j3   n0d2 n0d2
  5    n0d2 j3   n0d2 n0d2 j3   n1d2 n1d2 j3   n0d2 n0d2 j3   n0d2  .
  6  n0d2 n0d2 n0d2 j3   n0d2 n1d2 n2d3 n1d2 n0d2 j3   n0d2 n0d2 n0d2
  7    n0d2 j3   n0d2 n0d2 j3   n1d2 n1d2 j3   n0d2 n0d2 j3   n0d2  .
  8  n0d2 n0d2 j3   n0d2 n0d2 n0d2 j3   n0d2 n0d2 n0d2 j3   n0d2 n0d2
  9    j3   n0d2 j3   n0d2 j3   n0d2 n0d2 j3   n0d2 j3   n0d2 j3    .
 10  j3   n2   n1   n1   j3   n1   n1   n1   j3   n1   n1   n2   j3
 11    n2   n2   n2   n2   n2   n2   E2   n2   n2   n2   n2   n2    .
 12   .   n2   n2   n2   n2   E2   n2   E2   n2   n2   n2   n2    .
```

**Intent.** Two lit galleries (elev 2, plain neutral) above a crypt. The
crypt floor (elev 0) is a maze of one-hex lanes of **seeded dark 2** (D136)
between jagged pillars. Anyone in a lane is −14 to hit. In the middle is a raised
tomb (elev 1–2) with a **dark 3** heart (−21 to hit, and it drains 3% a turn).
- Pillars break sight lines everywhere, so ranged units fight from the
  gallery lip and melee wins in the lanes.
- **Shadowstep** jumps from dark hex to dark hex within 3, ignoring the
  path, so the walls are porous for dark users only.
- **Ambush** (+10 crit from dark 2) and **Cover of Night** suit the narrow
  lanes. **Pall** blinds anyone hit on dark 2+, and that is the whole floor.
- D136: the lanes and the tomb ring are **seeded**. Light painted into a lane
  opens it for good, thunder blows it (13%) and leaves it bare, fire adds a
  fire axis that decays with it. The lanes start as the dark's map and
  become whoever fights over them. Only the **dark 3 heart** (6, 6) is
  static: it re-forms every cycle, a landmark that always hides and drains.
- The high pillars stay (author likes them).
- Render, mid-fight with lanes overwritten: `design/art/maps_catacombs_seeded.png`.

## 8. Forge (`forge.json`, 13×13, 159 cells, 11 static, 16 seeded)

```
     0    1    2    3    4    5    6    7    8    9    10   11   12
  0   .   n3   n3   n3   n3   E3   n3   E3   n3   n3   n3   n3    .
  1    n3   n3   j5   n3   n3   n3   E3   n3   n3   n3   j5   n3    .
  2  n3   n3   n3   n2   n2   n3   n3   n3   n2   n2   n3   n3   n3
  3    n2   n2f1 n2f1 n2f1 n2   n2   n2   n2   n2f1 n2f1 n2f1 n2    .
  4  m1   m1   n1   n1   n1   j3   n1   j3   n1   n1   n1   m1   m1
  5    m0   n0   n0   n0f2 n0   n0   n0   n0   n0f2 n0   n0   m0    .
  6  n0f2 n0f2 n0f2 n0f2 n0   n0f2 n0f2 n0f2 n0   n0f2 n0f2 n0f2 n0f2
  7    m0   n0   n0   n0f2 n0   n0   n0   n0   n0f2 n0   n0   m0    .
  8  m1   m1   n1   n1   n1   j3   n1   j3   n1   n1   n1   m1   m1
  9    n2   n2f1 n2f1 n2f1 n2   n2   n2   n2   n2f1 n2f1 n2f1 n2    .
 10  n3   n3   n3   n2   n2   n3   n3   n3   n2   n2   n3   n3   n3
 11    n3   n3   j5   n3   n3   n3   E3   n3   n3   n3   j5   n3    .
 12   .   n3   n3   n3   n3   E3   n3   E3   n3   n3   n3   n3    .
```

**Intent.** A stepped foundry. The terraces drop 3 → 2 → 1 → 0 toward a
central pit, so going in is free and coming back out costs climbs.
- A **static fire 2** channel runs the length of the pit (8% standing, 4%
  per hex crossed), with two dry bridges at columns 4 and 8. A fire 2 spur
  sits on each side of the channel.
- **Fire 1 runnels** (4% standing, 2% to cross) cut each elev-2 terrace on
  both flanks, so the edge routes cost a little fire too.
- Slag **mud** fills the pit's corners and the elev-1 flanks.
- Two jagged anvils per side guard the middle approach.

Crossing the channel is the risk: a bridge, a burn, or a long climb round.
**Coal Engine** (+2 move starting on fire 2) and **Heat Rush** (no crossing
damage, +1 move) turn the channel into a road. **Ember Skin** and
**Kindling** want to stand in it. Water painted on the channel quenches it
for one cycle. D136: only the channel row is static; the fire 2 spurs and
the fire 1 runnels are **seeded**, so water quenches them for good.

## 9. Chapel (`chapel.json`, 13×13, 159 cells, 1 static, 52 seeded)

```
     0    1    2    3    4    5    6    7    8    9    10   11   12
  0   .   n1   n1   n1   n1   E1   n1   E1   n1   n1   n1   n1    .
  1    n1   j4   n1   n1   n1   n1   E1   n1   n1   n1   n1   j4    .
  2  n1   n1d2 j4   n1   n1   n0l2 n0l2 n0l2 n1   n1   j4   n1d2 n1
  3    n1d2 n1d2 j4   n1   n1   n0l2 n0l2 n1   n1   j4   n1d2 n1d2  .
  4  j4   n1d2 j4   n2   n2   n0l2 n0l2 n0l2 n2   n2   j4   n1d2 j4
  5    n1d2 n1d2 n0   n0   n0   n0l2 n0l2 n0   n0   n0   n1d2 n1d2  .
  6  n1d1 n1d1 j4   n0   n1l2 n1l2 n2l3 n1l2 n1l2 n0   j4   n1d1 n1d1
  7    n1d2 n1d2 n0   n0   n0   n0l2 n0l2 n0   n0   n0   n1d2 n1d2  .
  8  j4   n1d2 j4   n2   n2   n0l2 n0l2 n0l2 n2   n2   j4   n1d2 j4
  9    n1d2 n1d2 j4   n1   n1   n0l2 n0l2 n1   n1   j4   n1d2 n1d2  .
 10  n1   n1d2 j4   n1   n1   n0l2 n0l2 n0l2 n1   n1   j4   n1d2 n1
 11    n1   j4   n1   n1   n1   n1   E1   n1   n1   n1   n1   j4    .
 12   .   n1   n1   n1   n1   E1   n1   E1   n1   n1   n1   n1    .
```

**Intent.** A nave. A **static light 2** aisle runs end to end down the
centre (elev 0). It heals 6% a turn but gives +14 to hit against anyone
standing in it. At the crossing it widens into a transept with a raised
**light 3** altar (elev 2: heals 9%, +21 to be hit). Low pews (elev 2) flank
the aisle. Behind the column rows (jagged, elev 4) on each side are **dark
2 alcoves** (elev 1, −14 to be hit), with dark 1 at the crossing.

The trade is positional: stand in the light and heal while exposed, or
hide in the dark alcoves and be far from the fight. Light and dark meet at
the transept, so painting either one walks the other back for a cycle.
D136: the aisle and the alcoves are **seeded** and only the light 3 altar
is static, so a dark user can take the aisle (and light can open an
alcove) for the rest of the fight.
**Sunpath**, **Judgement** (no glances on targets in light) and **Glare**
reward the aisle. **Radiant Guard** cancels its exposure.

## Rotation (D118)

*Superseded by D145 (below).* `BWRun.MAPS`, simplest first: arena, paintball, **lake**, bridge,
**chapel**, ravine, **catacombs**, tinderbox, **forge**. Fights 1–9 play
each map once. Fight 10 replays paintball (`map_for` skips the arena on the
second lap), and the boss fights on the arena, unchanged.

## Rotation (D145, author addendum 2026-10-05)

Fight 4 is always the **Obelisks** and the Giant stays on the arena. The
other nine slots (fights 1–3 and 5–10) take `BWRun.MAP_POOL` (arena,
paintball, bridge, lake, chapel, ravine, catacombs, tinderbox, forge) in a
seeded shuffle of the run's seed (`BWRun.shuffled_maps`, its own rng, so loot
rolls don't move): nine maps for nine slots, no repeats. The order is saved
(`map_order`); an older save re-derives it from its seed. The Bridge is back
in the pool.

## Rooms: the map queue (D186–D190, D208)

*Refines D145: the shuffle is now a queue, and each fight from 3 on offers two maps.*
**Fights 1 and 2 have no room choice** (D208): they go straight to one battle
on the queue's front map against the Standard squad, with no room screen.
From fight 3, before every fight except the Obelisks (4) and the Giant, the
run offers two rooms (`BWRooms`, src/core/rooms.gd), each with its own map and
enemies: Standard takes the queue's first map, Hard the second. The map you
play leaves the queue; the **unchosen map goes to the back** of the queue, so
it can come back, but the next offer shows fresh maps first. Always taking
Standard plays all nine pool maps once (queue slots 0, 1, 2, 4, 6, 8, 5, 3, 7
of the shuffle). `map_for(n)` is the chosen room's map for the current fight
and a projection (every room Standard) for later fights. The queue, the
current offer and the played rooms are saved (save v7; a room may carry an
`encounter`).

## Special encounters (D208–D213)

From fight 3, about a third of the offers (`BWEncounters.RATE` 0.34, seeded per
run and fight) put a **special encounter** in the Hard room's place, on the
Hard room's map. It is a Hard room: the Hard tag and Hard pay (4 drops a tier
up on a win, whatever the head count), and nobody from it can be recruited. It
is built when met at the **squad's level** (enemy level = squad level), base
stats from the class profiles × the fight's curve multiplier (held to
0.9–1.1, since there is no stage lag) × the Hard ×1.18 × the kind's own knob
(`src/core/encounters.gd`, tuned in D212):

| Encounter | Squad | Rules | Card hint |
|---|---|---|---|
| **Horde** | 10 grunts: sword / hatchet / axe / lance, elementless, no armour | low HP (a share of their own HP) | Ten weak foes |
| **Colossus** | 1 spear fighter on 7 hexes (size 2), elementless | a big HP pool; reach 2; **line thrust**: its basic hits every foe on the 3 hexes straight out from its body toward the target (the rest at 75%); can't be displaced | One giant spear |
| **Blanks** | 3, random weapons, no element | **immune to elemental damage** and every element effect; **×2 from melee** physical strikes | Immune to elements, ×2 from melee |
| **Elemental Beings** | 3, each a random (different) element and weapon | **immune to physical damage** | Immune to physical: use element skills and the ground |

**Damage classes** (author's ruling, `BWFormulas.damage_class`, the one place):
- **Physical**: weapon basic attacks, even with an imbued weapon; weapon skills cast without an element; slams.
- **Elemental**: any skill cast with an element; staff spells (the staff's basic too); tile damage (fire, dark, shroud, steam, eruptions); detonations; chain arcs.
- Neither: obelisk pulses, thorns, Death Knell, Covering shares.

An immune blow deals 0 and carries nothing (no status, no knockback); the
forecast says "Immune: physical" / "Immune: elemental" and the view floats
IMMUNE. Against a Blank an imbued basic strikes as plain steel: no element
bonus, no paint, no element riders, and no elemental status lands on it.
Melee is the D142 split (daggers and staves only adjacent). The AI reads all
of it from the forecasts (an immune blow is no target), so both sides play
the counters without special cases.

**Spawns** (D211): enemy i takes spawn i; past the map's three (the Horde) or
where a footprint doesn't fit (the Colossus), the free hex nearest the
spawns, inside the map's enemy deploy zone first (`BWBattle.enemy_layout`,
shared with the pre-battle screen). The turn order shows 8 + 5 portraits and
a "+N" for the rest of a crowd.

## 10. Obelisks (`obelisks.json`, 17×13, 173 cells, 31 seeded), objective map (D140–D145)

```
     0    1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16
  0 .    .    n2   n2   n2   n2   n2   E2   n2   E2   n2   n2   n2   n2   n2   .    .
  1   .    n2   n2   n2   n2   n2   n2   n2   E2   n2   n2   n2   n2   n2   n2   .    .
  2 .    .    .    .    n1   n2   n2   n2   n2   n2   n2   n2   j4   n2   n1   .    .
  3   .    .    .    n1   .    g1   g1   n1   n1   n1   n1   n2   m0d1 m0d1 m0d1 m0d1 .
  4 .    n1   n1   n1   .    .    j3   n2   n2   n2   n1   n2   m0d1 m0d1 m0d1 m0d1 m0d1
  5   n1   n1l1 n1l1 n1   .    .    n2   n3   n3   n2   n2   m0d1 m0d1 n4   n4   m0d1 .
  6 n1   n1l1 L2   n1l1 n1   n1   n2   n3   j5   n3   n2   n2   n3   n4   W4   n4   m0d1
  7   n1   n1l1 n1l1 n1   .    .    n2   n3   n3   n2   n2   m0d1 m0d1 n4   n4   m0d1 .
  8 .    n1   n1   n1   .    .    j3   n2   n2   n2   n1   n2   m0d1 m0d1 m0d1 m0d1 m0d1
  9   .    .    .    n1   .    g1   g1   n1   n1   n1   n1   n2   m0d1 m0d1 m0d1 m0d1 .
 10 .    .    .    .    n1   n2   n2   n2   n2   n2   n2   n2   j4   n2   n1   .    .
 11   .    n2   n2   n2   n2   n2   n2   n2   P2   n2   n2   n2   n2   n2   n2   .    .
 12 .    .    n2   n2   n2   n2   n2   P2   n2   P2   n2   n2   n2   n2   n2   .    .
```
`L` = the White Lantern, `W` = the Black Well; `l1` / `d1` = seeded light 1 / dark 1.

**Intent.** Two stones on the centre row, at the west and east ends, so both
teams (top and bottom, exact mirror) are equally far from each. **The stones
share one life (D378):** one pool of 220 HP (`BWObelisk.HP_MAX`), every blow on either
stone lowers it, and at 0 both crumble and the player wins. Each stone keeps
its own rules (the Lantern dodges ranged and pushes, the Well dodges melee
and pulls), so the squad picks whichever stone its weapons hit best; there's
no point in focusing one. The plate shows one bar ("The Stones 150 / 220");
each stone's own bar on the board mirrors it. The room card: "Break the
stones: they share one life."
- **West, the White Lantern** (dodges ranged): a raised island (elev 1, the
  stone on a dais at 2) cut off by a two-hex **void** moat, reached by exactly
  **three bridges**: east (shared), north-east (the enemy's), south-east (the
  player's). Its ring is **seeded light 1** (heals 3%, +7 to be hit): holding
  the stone heals you and exposes you. Void blocks sight (D20), so shooters
  must stand on a bridge to see it: it is the melee stone.
- **East, the Black Well** (dodges melee): a sheer plateau (elev 4) in a
  sunken tar moat (mud, elev 0, **seeded dark 1**: −7 to be hit). One way up,
  the **causeway** from the west (elev 2 then 3). The moat is open ground, so
  bows and pistols see the Well over it from the lip (elev 2): it is the
  ranged stone. The Well's pull drags anyone in the moat against its cliff
  (a slam a turn).
- **Middle**: a mound (elev 3) round a standing stone (j5), two broken
  pillars (j3) by the Lantern's bridgeheads, grass at the bridgeheads (fire
  can cut a bridge off), jagged teeth (j4) on the moat's rim.
- The map is built by a script (checks: spawn-to-stone walks, sight lines,
  mirror, reachability); walks from either side: 7–9 move to the Lantern's
  ring, 10–12 to the Well's plateau; a bow sees the Well within 2–4 move.
  `test_obelisks.test_obelisks_map` checks the three bridges, the one way up,
  the mirror distances and reachability.

Renders: `design/art/obelisks_map.png`, `obelisks_lantern.png`,
`obelisks_well.png`, `obelisks_push.png`, `obelisks_pull.png`,
`obelisks_ui.png`, `obelisks_forecast.png` (`tools/obelisk_shots.gd`).

## 11. The Court (`court.json`, 13×13, 127 cells, 80 seeded), the Twins' map (D256)

The Twins' card at fight 4, against the Obelisks' card (D353/D355; never
weather). A disc of radius 6
round the centre hex (6, 6): the rim (radius 6) and a one-hex dais at the
centre are elevation 1, the rest 0. **Seeded** (D134): radius 2–5 west of the
centre column is light 1, east is dark 1 (40 each); the centre column and the
ring round the dais are neutral. Enemy spawns (3, 2) Noon on the light side and
(9, 2) Dusk on the dark, six apart, so the beam runs along row 2 from the
first turn; the squad deploys on rows 10–11. The seeds are the Twins' heal
until play changes them: light on seeded dark is dark 1 and decays (ELEMENTS
§5.6), so painting the opposite colour starves them. Renders:
`design/art/twins_*.png` (`tools/twins_shots.gd`).

## 12. Commons (`commons.json`, 17×15, 248 cells, 12 seeded), the 6v6 test map (D319–D324)

```
     0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16
  0  n0 n0 n0 n0 n0 n0 n0 n0 E0 n0 n0 n0 n0 n0 n0 n0 n0
  1   n0 n0 n0 n0 E0 n0 n0 n0 n0 n0 n0 E0 n0 n0 n0 n0  .
  2  n0 n0 n0 j2 n0 n0 E0 n0 E0 n0 E0 n0 n0 j2 n0 n0 n0
  3   n0 n0 n1 n1 n0 n0 n0 n0 n0 n0 n0 n0 n1 n1 n0 n0  .
  4  n0 n0 n1 n2 n1 n0 n0 n0 n0 n0 n0 n0 n1 n2 n1 n0 n0
  5   n0 n0 g1 n1 n0 n0 j2 n0 n0 j2 n0 n0 n1 g1 n0 n0  .
  6  n0 g0 g0 g0 n0 n0 n0 n1 n1 n1 n0 n0 n0 g0 g0 g0 n0
  7   n0 j2 n0 n0 m0 m0 n1 n2 n2 n1 m0 m0 n0 n0 j2 n0  .
  8  n0 g0 g0 g0 n0 n0 n0 n1 n1 n1 n0 n0 n0 g0 g0 g0 n0
  9   n0 n0 g1 n1 n0 n0 j2 n0 n0 j2 n0 n0 n1 g1 n0 n0  .
 10  n0 n0 n1 n2 n1 n0 n0 n0 n0 n0 n0 n0 n1 n2 n1 n0 n0
 11   n0 n0 n1 n1 n0 n0 n0 n0 n0 n0 n0 n0 n1 n1 n0 n0  .
 12  n0 n0 n0 j2 n0 n0 P0 n0 P0 n0 P0 n0 n0 j2 n0 n0 n0
 13   n0 n0 n0 n0 P0 n0 n0 n0 n0 n0 n0 P0 n0 n0 n0 n0  .
 14  n0 n0 n0 n0 n0 n0 n0 n0 P0 n0 n0 n0 n0 n0 n0 n0 n0
```

**Intent.** Plain open ground for testing 6v6 (`deploy_count` 6): not in the
rotation, played with `--combat commons` or `campaign_sim` MAP=commons. The
6v6 modes (Split Front, the castles, the Horde; D325–D326) get their own maps.
- Mirrored left-right and top-bottom (odd rows one hex shorter, as in Shared
  conventions), so both sides start equal.
- A central knoll: two top hexes at elevation 2, **seeded light 1**, ringed by
  elevation 1. Four flank hills (summits at 2) with grass on their outer slopes.
- Six jagged rocks for cover (two near each edge, two either side of the
  middle), mud either side of the knoll, two **seeded water 2** ponds at the
  west and east edges, and **seeded dark 1** across the centre lanes (rows 4
  and 10) in front of each side.
- Spawns: a front line of three two hexes apart (the first three, for a
  3-unit fill), the two wings and the back centre; the zones are the three
  edge rows, 22 hexes each. Front lines 10 apart, so ranged units reach on
  turn 2.
- The combat camera (D322) opens a third of the way toward the squad at
  distance 34, with edge scroll and a pan clamp. Renders:
  `design/art/6v6_*.png` (`tools/sixes_shots.gd`). Generated by a script
  (symmetry checked); edit the JSON by hand.


## The schedule (D353–D358; supersedes D325's fixed 6v6 fights)

The run's schedule is data: `BWSchedule.TABLE` (src/core/schedule.gd), fight
→ the cards it offers. One card is no choice (no room screen); two are a
choice on the room screen (`BWRoomScreen`).

| Fight | Cards |
|---|---|
| 1–2 | one 3v3 battle, the queue's front map (no choice) |
| 3, 6 | 3v3 Standard vs Hard (a third of the Hard rooms are special encounters, D208) |
| 4 | **the Obelisks vs the Twins** (boss cards: boss art, two lines on how they fight) |
| 5 | **two Split Fronts**: Split Front (§15) and The Fords (§17), two different dividers (seeded) |
| 7, 9 | a 3v3 Standard room vs a 6v6 card from the pool |
| 8, 10 | two 6v6 cards from the pool, two different maps |
| 11 | the Giant |

**The 6v6 pool** (`BWSchedule.SIX_POOL`): Split Front, The Fords, Defend the
Castle (Keep), Storm the Castle (Stronghold), Stop the Horde (the Horde Road).
A card draws (seeded per run, fight and card; `BWSchedule.draw_six`) a mode
not yet played this run, else a map not yet played, else anything; never the
other card's map. Hard rooms and special encounters stay on 3v3 cards. A
**weather** tag can fall on 3v3 cards and the Split Front and Horde cards
(from fight 5), **never in a castle** (D357: the castle maps' gate, walls and
high ground already carry the fight) and never on a boss card.

**The 3v3 map queue** feeds fights 1–3, 6, and the 3v3 cards of 7 and 9:
taking every card 0 plays six pool maps once; an unchosen 3v3 card's map goes
to the back of the queue (D187). `map_for(n)` / `mode_for(n)` read the chosen
card for the current fight and a projection (every choice card 0) for later
ones. The room log, the save (v12, D358) and the results name the card
(`room_log[n]`: kind, map, and `mode`, `boss`, `divider`, `encounter`,
`weather` as they apply). A 6v6 card pays `MODE_DROPS` (5) on a win (D334);
the Twins pay a pick for every unit (D258). The pre-battle fields the chosen
card's deploy count (3 or 6). The rules live in `BWObjectives` and one
`BWObjectiveMode` file per mode; a Split Front card's divider reaches the
battle through `BWRooms.battle_opts` (game, sim and pre-battle plate alike).

## 13. The Keep (`keep.json`, 19×17, 273 cells, 32 static), Defend the Castle (D335-D339)

```
     0    1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   
  0  n0   n0   n0   n0   n0   E0   n0   n0   n0   E0   n0   n0   n0   E0   n0   n0   n0   n0   n0
  1    n0   n0   n0   n0   n0   n0   n0   E0   n0   E0   n0   E0   n0   n0   n0   n0   n0   n0   .
  2  n0   n0   n0   n0   j2   n0   n0   n0   n0   n0   n0   n0   n0   n0   j2   n0   n0   n0   n0
  3    n0   n0   g0   g0   n0   n0   n0   n0   n0   n1   n0   n0   n0   n0   g0   g0   n0   n0   .
  4  n0   n0   g0   n0   n0   n0   g0   g0   n1   n1   n0   g0   g0   n0   n0   n0   g0   n0   n0
  5    n0   g0   g0   n0   n0   n0   g0   n0   j2   j2   n0   g0   n0   n0   n0   g0   g0   n0   .
  6  n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0
  7    n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0   n0   n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 .
  8  n0w2 j2   n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0   n0   n0   n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 j2   n0w2
  9    n0   n0   n0   n0   n0   n1   n0   n0f2 n0   n0   n0f2 n0   n1   n0   n0   n0   n0   n0   .
 10  .    .    .    n4   n3   n2   n3   P3   n3   G0   n3   P3   n3   n2   n3   n4   .    .    .
 11    .    .    .    n3   j3   j3   n2   n0   n0   n0   n0   n2   j3   j3   n3   .    .    .    .
 12  .    .    .    n3   n0   n0   n1   n0   P0   P0   P0   n0   n1   n0   n0   n3   .    .    .
 13    .    .    .    n3   n0   g0   n0   n0   n0   P0   n0   n0   n0   g0   n3   .    .    .    .
 14  .    .    .    n3   n0   g0   n0   n0   n0   n0   n0   n0   n0   g0   n0   n3   .    .    .
 15    .    .    .    n3   n0   n0   n0   j5   j6   j6   j5   n0   n0   n0   n3   .    .    .    .
 16  .    .    .    n3   n3   n3   n3   n3   j6   j6   j6   n3   n3   n3   n3   n3   .    .    .
```
`G` = the gate (an objective object, D337), `w2` = static water 2 (the moat),
`f2` = static fire 2 (the braziers). Void (`.`) beside the keep below row 9.

**Intent.** One castle shared by both castle modes (`tools/castle_maps.py`
builds and checks both; hand edits are fine, a re-run overwrites them). The
squad holds the keep at the bottom; raiders come from the top (rows 0-2) and
go for the **iron gate** at (9, 10).
- **The curtain wall** (row 10) is a wall walk at **elevation 3** you can stand
  on, corner towers at 4; side walls and a back wall at 3. The gate stands in
  the wall line at ground level. **High ground** (D336): +5% damage per level
  above the target, up to +15%, both sides; the walk is 3 above the berm.
- **Perches with melee routes** (the 2-turn rule): two **breaches** (rubble 1-2
  at (5, 9)-(5, 10) and (12, 9)-(13, 10)) climb onto the wall walk from the
  berm; fallen masonry (jagged) inside means they reach the walk, not the
  yard. Every wall-walk hex is at most 8 move (two turns) from the berm. From
  the walk, inner stairs (elevation 2 then 1) lead down into the courtyard.
- **The moat**: rows 7-8, static water 2 (+1 move a hex, conductive: thunder
  electrifies it, ice glazes it), with a two-wide bridge on the gate's
  column. **Braziers**: static fire 2 at (7, 9) and (10, 9), either side of
  the gate's foot, drawn as iron bowls.
- **The keep** (back centre) is a rock block capped by a white tower; the
  keep door (9, 14) is decoration only (D339: no keep-door loss).
- Spawns: two squad units on the wall walk beside the gate, four in the yard
  behind it; the squad's zone is the wall walk and the courtyard. Wave hexes
  (`objective.waves_at`): the north corners. Walk from the enemy spawns to
  the gate: 8 move.
- **Defend the Castle** (`BWCastleDefend`): hold for **8 rounds**, or down
  every raider once no wave is left; **lose** if the gate breaks or the squad
  falls. Six raiders, then 3 at round 3 and 3 at round 5 (each rung a round
  ahead). The gate's HP is 4.25 x the squad's mean max HP. Raiders weigh the
  gate x3 and, with nothing to hit, march on it.

## 14. The Stronghold (`stronghold.json`, 19×17, 273 cells, 32 static), Storm the Castle (D335, D342)

```
     0    1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   
  0  .    .    .    n3   n0   n3   n3   n3   j6   j6   j6   n3   n3   n3   n0   n3   .    .    .
  1    .    .    .    n3   n0   n0   n0   j5   j6   j6   j5   n0   n0   n0   n3   .    .    .    .
  2  .    .    .    n3   n0   g0   n0   n0   n0   T0   n0   n0   n0   g0   n0   n3   .    .    .
  3    .    .    .    n3   n0   g0   n0   n0   n0   W0   n0   n0   n0   g0   n3   .    .    .    .
  4  .    .    .    n3   n0   n0   n1   n0   n0   E0   n0   n0   n1   n0   n0   n3   .    .    .
  5    .    .    .    n3   j3   j3   n2   n0   n0   n0   n0   n2   j3   j3   n3   .    .    .    .
  6  .    .    .    n4   n3   n2   E3   n3   E3   G0   E3   n3   E3   n2   n3   n4   .    .    .
  7    n0   n0   n0   n0   n0   n1   n0   n0f2 n0   n0   n0f2 n0   n1   n0   n0   n0   n0   n0   .
  8  n0w2 j2   n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0   n0   n0   n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 j2   n0w2
  9    n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0   n0   n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 n0w2 .
 10  n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0   n0
 11    n0   g0   g0   n0   n0   n0   g0   n0   j2   j2   n0   g0   n0   n0   n0   g0   g0   n0   .
 12  n0   n0   g0   n0   n0   n0   g0   g0   n1   n1   n0   g0   g0   n0   n0   n0   g0   n0   n0
 13    n0   n0   g0   g0   n0   n0   n0   n0   n0   n1   n0   n0   n0   n0   g0   g0   n0   n0   .
 14  n0   n0   n0   n0   j2   n0   n0   n0   n0   n0   n0   n0   n0   n0   j2   n0   n0   n0   n0
 15    n0   n0   n0   n0   n0   n0   n0   P0   n0   P0   n0   P0   n0   n0   n0   n0   n0   n0   .
 16  n0   n0   n0   n0   n0   P0   n0   n0   n0   P0   n0   n0   n0   P0   n0   n0   n0   n0   n0
```
`G` the wooden gate, `T` the throne, `W` the Warden's post. The gaps at (4, 0)
and (14, 0) are the **back doors** (open arches).

**Intent.** The Keep flipped top to bottom (17 rows: every row keeps its
parity, so the flip is exact in odd-r); the squad attacks from the south.
- **Phase 1:** break the **wooden gate** at (9, 6) (fire x1.5; thunder on a
  glazed gate x1.5). Four guards on the wall walk (ranged first) and one in
  the yard hold their posts with the high ground; the Warden holds the
  throne. Two guards come in by the back doors at rounds 3, 5 and 7 until
  the gate falls.
- **Phase 2** (D255's phase framework, a `ko` trigger): the gate falls, the
  reinforcements stop, the **throne** (9, 2) unseals (its ring of bars
  breaks) and the Warden takes the field. **Win:** break the throne or down
  the Warden. **Lose:** the squad falls.
- The moat, braziers and breaches are the Keep's: thunder an electrified
  moat under guards on the berm, burn the gate, climb a breach to fight the
  archers on the walk.
- Renders: `design/art/mode_defend_overview.png`, `mode_defend_gate.png`,
  `mode_storm_overview.png`, `mode_storm_break.png`, `mode_storm_throne.png`
  (`tools/castle_shots.gd`).

## 15. Split Front (`splitfront.json`, 19×15, 285 cells, 6 seeded), fight 5 and the pool (D328-D330, D353)

```
     (j = rock, D = the divider, P / E = spawns, w / l / d = seeded water 2 / light 1 / dark 1)
     0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18
  0 n0 n0 n0 n0 n0 n0 n0 n0 n1 j3 n1 n0 n0 n0 n0 n0 n0 n0 n0
  1  n0 n0 n0 n0 E0 n0 n0 n0 n1 j3 n1 n0 n0 n0 E0 n0 n0 n0 n0
  2 n0 n0 n0 E0 n0 E0 n0 n0 n1 j3 n1 n0 n0 E0 n0 E0 n0 n0 n0
  3  n0 n0 n0 n0 n0 n0 g0 g0 n1 j3 g1 g0 n0 n0 n0 n0 n0 n0 n0
  4 n0 n0 n0 j2 n0 n0 n1 n1 n1 j3 n1 n1 n1 n0 n0 j2 n0 n0 n0
  5  n0 g0 g0 n0 n0 n0 n0 n0 n0 j3 n0 n0 n0 n0 n0 g0 g0 n0 n0
  6 n0 g0 g0 n0 n0 n0 l0 n0 n0 D0 n0 n0 l0 n0 n0 n0 g0 g0 n0
  7  n0 n0 w0 n0 m0 m0 n0 n0 n0 D0 n0 n0 m0 m0 n0 n0 w0 n0 n0
  8 n0 j2 n0 n0 n0 n0 d0 n0 n0 D0 n0 n0 d0 n0 n0 n0 n0 j2 n0
  9  n0 n0 n1 n0 g0 g0 n0 n0 n0 j3 n0 n0 g0 g0 n0 n1 n0 n0 n0
 10 n0 n1 n2 n1 n0 n0 j2 n0 n1 j3 n1 n0 j2 n0 n0 n1 n2 n1 n0
 11  n0 n0 n1 n0 n0 n0 n0 n0 n1 j3 n1 n0 n0 n0 n0 n1 n0 n0 n0
 12 n0 n0 n0 P0 n0 P0 n0 n0 n1 j3 n1 n0 n0 P0 n0 P0 n0 n0 n0
 13  n0 n0 n0 n0 P0 n0 n0 n0 n1 j3 n1 n0 n0 n0 P0 n0 n0 n0 n0
 14 n0 n0 n0 n0 n0 n0 n0 n0 n1 j3 n1 n0 n0 n0 n0 n0 n0 n0 n0
```

**The author's concept:** "a 6v6 map that starts as 2 separate engagements,
with a 3-tile (wind wall or fire wall, or ice wall) spanning between
engagements. So you can unite 2 teams of 3 units or have them fight 2 other
squads of 3."
- Two arenas, **west** (q 0-8) and **east** (q 10-18), split by a rock spine
  (q 9, elevation 3, flanked by raised ground) except a **3-hex gap** at
  rows 6-8: the **divider** (`objective.divider`, `split_q` 9). A single
  column is leak-proof in odd-r offset (tested).
- Spawns 1-3 of each side are the west arena, 4-6 the east: three of the
  squad and three enemies in each. The pre-battle tags WEST FRONT / EAST FRONT
  with their counts and **Begin waits for three a front**.
- Mirrored left-right: a rock, grass, a mud strip and a hill per arena;
  water 2, light 1 and dark 1 seeded beside the gap.
- **The divider's element is seeded per run** (`BWSplitFront.element_for_seed`
  of the fight seed), telegraphed on the pre-battle plate and the intro banner:
  - **Fire Wall:** static fire 3 (seeded, holds until play changes it).
    Passable: crossing burns 6% a hex, ending a turn there 12%. **Water** on a
    hex (any) puts it out.
  - **Ice Wall:** ice pillars on water 3 (owner "divider"): impassable, they
    block sight. **Thunder** shatters one, **fire** melts one, and they thaw
    on their own after 6 ticks (the count shows on each), leaving water 3.
  - **Wind Wall:** a Wind Wall with no countdown: blocks moves and skills both
    ways, **basic attacks pierce** (the D269 ruling). Each hex holds a wall
    segment (60 HP, both sides may strike it): deal 60 to a hex, or land a
    **wind basic** on it (D407: every wind basic gusts), and that hex opens.
- One hex open (ice, wind) or all three out (fire): the fronts can merge.
- **The enemy breaks through** (D330): at the start of round 4, if it is
  behind on either front (fewer standing there, or as many with less HP), it
  tears the whole divider down ("The enemy breaks through: the fronts merge").
- Win: every enemy down. Renders `design/art/mode_split_fire|ice|wind.png`,
  `mode_split_prebattle.png`, `mode_split_merge.png` (`tools/mode_shots.gd`).

## 16. The Horde Road (`horde.json`, 19×15, 285 cells, 29 seeded), Stop the Horde (D331, D347-D352)

```
     (w = seeded water 2-3, P / E = spawns of the first wave, L = where the Lil Fella
      usually starts: a row behind the squad's centre, BWHordeMode.fella_start)
     0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18
  0 n0 n0 n0 n0 n0 E0 n0 n0 n0 E0 n0 n0 n0 E0 n0 n0 n0 n0 n0
  1  n0 n0 n0 n0 n0 n0 n0 E0 n0 E0 n0 E0 n0 n0 n0 n0 n0 n0 n0
  2 n0 n0 n0 n0 n0 n0 n0 g0 g0 n0 n0 g0 g0 n0 n0 n0 n0 n0 n0
  3  n0 n0 n0 n0 j2 n0 n0 n0 n0 n0 n0 n0 n0 n0 j2 n0 n0 n0 n0
  4 m0 w0 w0 w0 n0 w0 w0 w0 w0 w0 w0 w0 w0 w0 n0 w0 w0 w0 m0
  5  n0 n0 n0 n0 n0 n0 n0 n0 n0 j2 n0 n0 n0 n0 n0 n0 n0 n0 n0
  6 n0 n0 g0 g0 n0 n0 n0 n0 n0 n0 n0 n0 n0 n0 n0 g0 g0 n0 n0
  7  n0 n0 g0 n0 n0 n0 n0 n0 n0 n0 n0 n0 n0 n0 n0 n0 g0 n0 n0
  8 n0 n0 w0 w0 w0 w0 w0 w0 n0 n0 n0 w0 w0 w0 w0 w0 w0 n0 n0
  9  n0 j2 n0 n0 n0 n0 j2 n0 n0 n0 n0 n0 j2 n0 n0 n0 n0 j2 n0
 10 n0 n0 n0 n0 n0 n0 n0 n0 g0 g0 g0 n0 n0 n0 n0 n0 n0 n0 n0
 11  n0 n0 n0 n0 n0 n0 n0 n0 n0 n1 n0 n0 n0 n0 n0 n0 n0 n0 n0
 12 n0 n0 n0 n0 n0 P0 n0 n0 n1 P1 n1 n0 n0 P0 n0 n0 n0 n0 n0
 13  n0 n0 n0 n0 n0 n0 n0 P0 n0 P0 n0 P0 n0 n0 n0 n0 n0 n0 n0
 14 n0 n0 n0 n0 n0 n0 n0 n0 n0 L0 n0 n0 n0 n0 n0 n0 n0 n0 n0
```

**Intent.** Keep the little one alive. The squad guards the **Lil Fella**
(`BWLilFella`, D348): a small neutral figure with a pointed hat and a lantern,
ringed in ink on its hex, placed a row behind the squad's centre. Horde grunts
come in **waves** from the north edge (`objective.spawn_edge`, rows 0-1) and
hunt it. There is no exit any more (D349 replaced D331's exit and escape counter).
- **The Lil Fella:** HP = **half the highest max HP in the deployed squad** at
  battle start. Not player-controlled: on its own turn (the squad's median
  speed, move 3) it runs to the safest reachable hex (far from the enemy and
  out of its next reach, close to the squad, off the map's edge), never onto
  or across fire, a dark 3 drain, a shock field or a fuse (glaze is fine
  since D397: it no longer slides). On the
  squad's side for damage: **nothing of the squad's** hurts, moves or
  statuses it (blows, areas, ground, blasts, beams, chain arcs). **Enemy**
  blows and ground an enemy laid hurt it; map-seeded ground doesn't (and it
  never stands on any). No statuses or displacement from anyone.
- **Waves** (`BWHordeMode.WAVES`, [round, grunts, elites]): 4 on the board at
  the start; 4 at round 2; 4 + 1 elite at round 4; 4 + 1 elite at round 5
  (D351). Each wave is **rung on its hexes a round before it lands** with a
  WAVE n tag. Grunts are the D208 Horde's (elementless melee, stats x0.9, 42% HP), built
  at the squad's level; **elites** are roster enemies on the fight's curve
  x1.15.
- **One group turn** (D347): every living grunt acts in one slot of the turn
  order ("Horde ×N", at the fastest grunt's place). The rules resolve them one
  by one, nearest the Lil Fella first (walking cost, ties by id); the screen
  plays every walk at once, then every blow at once (Minimal), each number on
  its own target. Elites take their own turns.
- **Grunts go for the Lil Fella:** a stop they can strike it from, else the
  stop nearest it; then they strike it, or a squad unit in reach if it isn't.
  Elites use the usual AI and weigh a blow on it x1.5.
- **Lose** when the Lil Fella falls or the squad is down. **Win** when every
  wave has landed and no enemy is left. The plate reads "Wave n of 4 · next in
  r rounds" and "Lil Fella hp / max".
- Built for the area combos: two **water channels** (row 4 across the field
  with fords at q 4 and 14; row 8 on the flanks, water 3 pools at q 4-5 and
  13-14, a dry ford in the middle) for electrified pools and glaze; **grass**
  on the far bank and the flanks for fire and Overheat; open lanes between
  seven rocks for squalls and Vortex pulls. A low rise behind the line. (Mind
  the little one: your ground can't hurt it, but it won't walk through it.)
- Renders `design/art/mode_horde_prebattle.png`, `horde2_group_move.png`,
  `horde2_fella_flee.png`, `horde2_fella_close.png`, `horde2_plate.png`
  (`tools/mode_shots.gd ONLY=horde`); the D331 frames `mode_horde_waves.png`
  and `mode_horde_exit.png` show the old exit.

## 17. The Fords (`fords.json`, 19×15, 273 cells, 9 seeded), the second Split Front (D354)

Split Front's second map (fight 5's other card, and the 6v6 pool). A river
gorge (no hexes: impassable, nothing sees a way across) runs down column 9;
**three single-hex fords** cross it at rows 4, 7 and 10, and the divider
stands on all three (fire 3, an ice pillar on water 3, or a wind wall segment
on each; the element is seeded per card, D354). Break **any one** ford and the
fronts can meet, at the north, the middle or the south: where Split Front's
one 3-hex gap makes a single meeting point, the Fords make three. The enemy's
round-4 break-through (D330) opens all three.

- **West, the reed marsh:** mud banks along the river (2× move), reeds
  (grass, fire spreads), a raised grassy hummock mid-arena (elevation 1),
  marsh pools seeded water 1–2 (Undertow, thunder in the shallows), two stumps.
- **East, the stony bank:** the bank sits a level up (elevation 1) over the
  fords, so crossing east is a climb; a cairn hill (2) seeded light 1, rocks
  (2–3), a hollow seeded dark 1 on mud.
- Each arena is mirrored north–south (rows r and 14 − r), so each front is
  fair; west and east differ on purpose. Spawns and deploy zones as Split
  Front (spawns 1–3 west, 4–6 east; the three edge rows).
- Built by `python tools/split_maps.py` (edit the script, not the JSON).
  Render: `design/art/sched_fight5.png` (the card). `--combat fords --mode
  splitfront [--divider ice]`.

```
     (j = rock, D = a ford (the divider), P / E = spawns, w / l / d = seeded water / light 1 / dark 1, blank = the gorge)
      0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18
  0 n0 n0 n0 n0 n0 n0 n0 n0 m0    n1 n1 n0 n0 n0 n0 n0 n0 n0
  1  n0 n0 n0 n0 E0 n0 g0 g0 m0    n1 n1 n0 n0 E0 n0 n0 n0 n0
  2 n0 n0 n0 E0 n0 E0 n0 g0 m0    n1 n1 n0 E0 n0 E0 n0 n0 n0
  3  n0 n0 j1 n0 n0 n0 n0 n0 m0    n1 n1 j2 n0 n0 n0 m0 n0 n0
  4 n0 g0 n0 n0 n0 n0 w0 n0 n0 D0 n1 n1 n0 n0 n0 d0 j2 n0 n0
  5  n0 g0 g0 w0 n0 n0 n0 g0 g0    n1 n1 n0 n0 n0 n0 n0 n0 n0
  6 n0 n0 w0 n0 g1 n0 n0 n0 m0    n1 n1 n0 n1 n1 n0 n0 j3 n0
  7  n0 n0 n0 g1 g1 g1 n0 n0 n0 D0 n1 n1 n0 n2 l2 n2 n0 n0 n0
  8 n0 n0 w0 n0 g1 n0 n0 n0 m0    n1 n1 n0 n1 n1 n0 n0 j3 n0
  9  n0 g0 g0 w0 n0 n0 n0 g0 g0    n1 n1 n0 n0 n0 n0 n0 n0 n0
 10 n0 g0 n0 n0 n0 n0 w0 n0 n0 D0 n1 n1 n0 n0 n0 d0 j2 n0 n0
 11  n0 n0 j1 n0 n0 n0 n0 n0 m0    n1 n1 j2 n0 n0 n0 m0 n0 n0
 12 n0 n0 n0 P0 n0 P0 n0 g0 m0    n1 n1 n0 P0 n0 P0 n0 n0 n0
 13  n0 n0 n0 n0 P0 n0 g0 g0 m0    n1 n1 n0 n0 P0 n0 n0 n0 n0
 14 n0 n0 n0 n0 n0 n0 n0 n0 m0    n1 n1 n0 n0 n0 n0 n0 n0 n0
```
