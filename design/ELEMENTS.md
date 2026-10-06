# Element rules

The rulebook Phase 0 implements for elements on tiles. It is precise on
purpose: every number is named, every order of operations is stated, and
anything not written here does not happen. Where this file and the code
disagree, fix the code or change this file first, never quietly.

Sources: the brief (`design/KICKOFF.md`), `design/SCHEMA.md`, `DECISIONS.md` D4, D10,
D11, D12, and V8's charge grid (`scripts/slice/element_charge.gd`,
`tile_effects.gd`, `combat_scene.gd` tile code, ADR-0010/0013/0019,
`BR-MAP-004` §6, §11, §13, §14). V8 is read-only; logic is lifted, not linked.

Every number below is a first pass for Gate 2. They live as named constants
(§10) so tuning is a one-line change.

---

## 1. Vocabulary

| Term | Meaning |
|---|---|
| **cycle** | One full pass of the speed queue: every living unit has had one turn. Tiles tick once per cycle (§5), never per unit turn. |
| **axis element** | fire, water, light, dark. Each moves one of the two charge axes. |
| **operator element** | thunder, ice, wind. Each *acts on* whatever charge a tile holds. |
| **charge** | A tile's (h, v) pair. **h**: water −3 … 0 … +3 fire. **v**: dark −3 … 0 … +3 light. |
| **intensity** | The magnitude of one axis: fire intensity = h when h > 0, water = −h when h < 0, light = v when v > 0, dark = −v when v < 0. 0 to 3. |
| **marker** | An operator waiting on empty ground: `fuse` (thunder), `stasis` (ice), `gale` (wind). |
| **glaze** | Ice's lock on a charged tile. A counter of cycles. |
| **fresh** | An arrival caused directly by a unit's action. The opposite is **propagated**: a gale copy or a grass seed. |
| **source** | The unit id that last changed the tile, or −1. Used for KO credit and for "your fire tiles" enchantments. |
| **% HP** | Percent of the *affected unit's* max HP. All tile damage and healing is stated this way (§8). |

---

## 2. The tile state model

### 2.1 Stored entry

A hex with nothing on it has **no entry**. Neutral is absence (V8's core
rule). An entry has exactly these fields:

```
{
  h:         int   -3..3     # water(-) / fire(+)
  v:         int   -3..3     # dark(-)  / light(+)
  marker:    ""|"fuse"|"stasis"|"gale"
  timer:     int   cycles until the next decay step
  glaze:     int   cycles of ice lock left (0 = not glazed)
  source:    int   unit id, -1 for authored
  origin:    "cast"|"spread"   # may this tile ignite grass (§6.2)?
  permanent: bool  authored by the map; never decays (§5.4)
}
```

Invariants (assert them in the self-test):

1. `marker != ""` implies `h == 0 and v == 0 and glaze == 0`. A hex holds
   **either** charge **or** a marker, never both (V8).
2. `h == 0 and v == 0 and marker == ""` never exists as an entry. It is erased.
3. `glaze > 0` only on a charged entry.
4. Jagged hexes never have an entry (§6.4).

There are 48 reachable charge states (7×7 minus neutral). Unlike V8, they
are **not** a hand-written 49-row table: every property below is defined per
axis and the two axes simply add, so the code computes a state's effects from
(h, v). V8 needed a table because each state borrowed one tinted sticker; B|W
draws each axis as its own glow layer (§4), so there is nothing per-state to
declare.

### 2.2 What a charged tile does

Both axes apply at once. A tile at (h = +2, v = −1) burns *and* conceals.

| Axis | Intensity 1 | Intensity 2 | Intensity 3 |
|---|---|---|---|
| **Fire** (h > 0): start-of-turn damage to the occupant | 4% HP | 8% HP | 12% HP |
| **Fire**: damage per fire hex *entered* while moving | 2% HP | 4% HP | 6% HP |
| **Fire**: on grassy terrain | no spread | **ignites** neighbours (§6.2) | **ignites** neighbours |
| **Water** (h < 0): added move cost to enter | +0 | +1 | +2 |
| **Water**: conduction (§7.3): thunder attacks on the occupant | +10% dmg | +20% dmg | +30% dmg |
| **Water**: adds to a thunder detonation here | +2% HP | +4% HP | +6% HP |
| **Light** (v > 0): start-of-turn heal to the occupant | 3% HP | 6% HP | 9% HP |
| **Light**: hit chance of attacks *targeting* the occupant | +7 | +14 | +21 |
| **Dark** (v < 0): hit chance of attacks targeting the occupant | −7 | −14 | −21 |
| **Dark**: start-of-turn drain to the occupant | — | — | 3% HP |

Notes:

- Light both heals and exposes, and dark both hides and (at 3) drains. Each
  axis is a trade, as in V8, so neither is a pure buff to stand on.
- Fire with light (e.g. h = 2, v = 2) burns 8% and heals 6% on the same turn
  start. Damage is applied first, then healing (so a unit at 5% HP on that
  tile is knocked out, not saved).
- Hit-chance terms are percentage points added to the brief's hit-chance
  basis before avoid is subtracted, and shown as their own line in the
  forecast hover ("Target on Dark 2: −14").
- Crossing damage counts every hex entered along the path, excluding the
  starting hex (V8). Displacement (Charge's shove) is not moving and deals no
  crossing damage.

### 2.3 What a marker does

Nothing by being stood on (V8: every gameplay field zero). A marker only acts
when a **fresh** axis charge lands on its hex (§3.3). Markers last
`MARK_CYCLES = 3` cycles, then vanish.

### 2.4 Ice: glaze

Ice locks a charged tile in time for `GLAZE_CYCLES = 2` cycles (§3.2). While
glazed:

- the decay timer is frozen (glaze counts down instead);
- the tile's standing effects still apply (glazed fire still burns: the fire
  is frozen in place, not out);
- **one exception, new in B|W:** glazed *water* has **no move-cost penalty**.
  Frozen water is walkable ice. Freezing a flooded river to cross it is the
  intended play;
- glazed tiles never ignite grass and never accept gale copies.

### 2.5 Life is gone, and so are Purge and Ward

V8's fourth operator was life: *purge* (one step toward neutral on both axes,
plus 4 HP to the occupant) on charged ground, *ward* on empty ground. With
life dropped (D4) the operator is **dropped, not reassigned**:

- **Cleansing** already exists without it: the opposite axis element walks a
  tile back (fire undoes water, light undoes dark), thunder erases a tile
  outright (with a bang), and every tile decays on its own.
- **Healing** already moved to the light axis in V8 (ADR-0013 amendment), and
  D10 keeps it there.
- Giving purge to thunder, ice or wind would blur the three roles D12 keeps
  ("detonate, lock, spread"). Giving it to light would make light both the
  healer and the cleanser, which overloads one element.
- The *purge* effect survives as a weapon skill instead: the staff's
  **Siphon** (§9.3) strips a tile. It belongs to whoever carries a staff, not
  to an element.

---

## 3. Applying an element to a tile

All application goes through one **pure** function and one mutator, as in V8:

- `route(entry, element, fresh, steps) -> plan`: reads nothing else,
  writes nothing. Returns a plan.
- `apply_plans(plans)`: the only code that changes the board (§3.5).

`steps` is 1 for everything except Saturate (2). `fresh` is true for every
unit action and false for gale copies and grass seeds.

### 3.1 Axis element (fire, water, light, dark)

1. If the hex is **glazed**: the cast washes off. No change. (Fire is the
   exception, see §3.2.)
2. Shift: fire h += steps, water h −= steps, light v += steps, dark v −= steps.
   Clamp each axis to −3..3.
3. If the hex held a **marker**:
   - fresh arrival: the marker **fires** on the new (h, v) (§3.3), then is
     spent;
   - propagated arrival: nothing happens at all. The marker stays armed and
     the arriving charge is discarded. (V8 containment clause.)
4. Otherwise settle: if (h, v) = (0, 0), **erase** the entry. Else store it with
   `timer = STEP_CYCLES`, `source = caster`, `origin = "cast"` (fresh) or
   `"spread"` (propagated).

Because opposites share an axis, *fire on water steps it back toward neutral*.
Water 3 hit by one fire becomes water 2, not "steam". There are no compounds.

### 3.2 Operator element on a charged tile

| Element | Effect | Numbers |
|---|---|---|
| **Thunder: detonate** | The charge explodes and the tile is erased. The occupant takes the full blast; every unit on the six neighbours takes half (rounded down). Splash is damage only and never lays charge. | blast = `5% + 4% × (|h| + |v|)` + `2%` per water intensity, × `1.5` if glazed ("shatter") |
| **Ice: glaze** | Charge unchanged, `glaze = 2`. Decay paused. | 2 cycles |
| **Wind: gale** | Charge unchanged at the origin. A **copy** of (h, v) goes to each of the six neighbours (§3.4). | radius 1, copies at `timer = 1` |

Detonation examples: fire 1 alone = 9%. Fire 3 + dark 3 = 29%. Water 3 + dark
3 = 35%; glazed first, 52% to the occupant and 26% to each neighbour. The big
numbers need 6+ setup applications and a glaze, which is the combo we want to
pay off.

**On a glazed tile**, operators and fire behave as follows (V8 rules, kept):

| Arriving | Result |
|---|---|
| fire | the glaze melts (`glaze = 0`); the fire itself is spent, charge unchanged |
| thunder | shatter: detonate with the × 1.5 |
| ice | re-glaze: `glaze = 2` |
| wind, water, light, dark | washes off, no change |

### 3.3 Operator element on empty ground: arming

On a hex with no charge, an operator **arms** it: store `marker`, `timer =
MARK_CYCLES` (3). An operator on a hex that already has a marker **replaces**
it (newest wins, timer refreshed).

**Wind on wind (D95).** Wind arriving on a hex that holds a gale marker
upgrades it to **gale 2** (`gale_level = 2`, timer refreshed). Wind on a
gale 2 just refreshes it. When a gale 2 fires, its copies go to radius 2
(§3.4). Any other operator on a gale replaces it as above.

When a **fresh** axis arrival lands on a marked hex, the arrival is applied
first (giving the new (h, v)), then the marker fires on that state exactly as
§3.2 describes:

- `fuse` → detonate the new state (fire 1 onto a fuse = 9% blast, tile erased);
- `stasis` → the new state is stored and glazed for 2 cycles;
- `gale` → the new state is stored and copied to the six neighbours (a
  gale 2: to rings 1 and 2, the 18 hexes around it).

The marker is consumed either way. One rule, two timings: an operator either
acts now on charge that is there, or waits for charge to arrive.

### 3.4 Gale copies

A copy is not a cast. It is placed directly (it does **not** re-enter `route`,
which would shift the neighbour instead of copying, V8's reasoning). For each
of the six neighbours (a gale 2: each hex of rings 1 and 2; Gusting adds its
radius on top):

- skip it if out of bounds, jagged, holding a marker, glazed, or already
  changed by this same action;
- otherwise **overwrite** it with `{h, v copied, timer = 1, glaze = 0,
  source = caster, origin = "spread"}`.

Overwriting means a gale can also *lower* a neighbour (a fire 1 gale over a
fire 3 neighbour leaves fire 1). That is wind as dilution as well as spread.

### 3.5 Simultaneous resolution inside one action

A skill touches several hexes. To make the result independent of iteration
order:

1. Compute every hex's plan against the board **as it was before the action**.
2. Apply all charge/marker/glaze changes.
3. Apply all gale copies (rule 3.4 skips hexes changed in step 2).
4. Sum all detonation damage per unit, then deal it (one damage event per unit
   per action, so the feed and the cutscene show one number).
5. Run knockout checks once.

Gale copies and detonation splash never trigger anything further in the same
action. That, plus §5's containment, is what stops chain reactions.

---

## 4. Visual tiers

Tiles are white with black borders. Each axis renders as its **own glow layer**
at its own intensity, so a mixed tile shows two effects layered (fire flames
over a slow dark swirl). The dominant axis draws on top; ties draw fire/water
on top. Operators draw their own layer. Colours are in `game/data/elements.csv`.

| Element | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|
| **Fire** (smouldering) | *Smouldering*: ember glow along the hex edges, thin smoke wisps | *Burning*: low flames across the face, flicker | *Blazing*: tall flames, rising sparks, heat shimmer |
| **Water** (rippling) | *Damp*: wet sheen, slow single ripple | *Flooded*: standing water, concentric ripples | *Deep*: dark-blue depth, strong ripples, tile face appears to sink |
| **Light** (glowing yellow) | *First light*: soft yellow glow | *Lightfall*: bright glow, rising motes | *Pillar*: column of light rising off the hex |
| **Dark** (sinking, swirling) | *Gloaming*: faint swirl at the centre | *Deep shadow*: slow vortex, edges darken inward | *Abyss*: tile reads as sinking into a black-violet vortex, tendrils at the rim |

Operators:

| Element | Marker (empty ground) | Event |
|---|---|---|
| **Thunder** (crackling purple) | *Fuse*: purple arcs crackling along the hex edges | Detonation: purple-white flash, ring burst onto the neighbours |
| **Wind** (swirling green) | *Gale*: green eddies swirling over the face | Gale fires: green gust ring blowing outward to the six neighbours |
| **Ice** (pale cyan frost, proposed) | *Stasis*: pale cyan rime pattern on the face | Glaze: frost sheet over the existing glow layers, which dim to ~60%; cracks appear in the glaze's last cycle |

Readability notes for Phase 5: light yellow on a white tile is the weakest
read in the set, so the light layer needs either saturation (`#FFC81A`, not
pastel) or a faint darkening ring. Dark is the strongest read on white. Tier
must also read through **size and motion**, not hue alone (V8 gotcha #20),
for the four axis elements: tier 1 hugs the tile, tier 3 stands up off it.

### 4.1 As built (Phase 5, D82)

Procedural, unlit, alpha-blended shaders in `game/shaders/tile_*.gdshader`
(shared helpers in `tile_fx.gdshaderinc`, no textures). `BWTileFX`
(`src/game/combat/tile_fx.gd`) owns one shared material per element and the
pure entry → layer mapping; `BWBoardView` gives every hex five layer nodes:
an axis **face** (flat hex) and **cards** (a cluster of ten billboard cards
that stay upright toward the camera) for h and for v, plus one **mark** node
(marker or glaze). Per-tile values are instance uniforms (D55 slots: dim 0,
then tier 3, seed 4, frost 5, crack 6, age 7).

| Element | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|
| Fire | soot creeping in from the rim, pulsing ember band, 2–3 grey smoke wisps | heat bed across the face, low flames (≈0.4 u) on every card | white-hot bed, tall flames (≈1–1.2 u) with dark-red contour, sparks rising off the tips |
| Water | blue sheen, one slow ripple from a seeded point, a glint | standing water, concentric ripples, foam line | deep: a parallax floor 0.55 u down with inner walls, so the face reads sunk; hard ripples |
| Light | saturated yellow glow, amber-brown ring at the rim | brighter, turning rays, rising diamond motes | white core, a 3.2 u column of light (amber-edged) with motes |
| Dark | violet swirl pooled at the centre | near-opaque vortex over the whole face, ink creeping in from the edges | three parallax swirl layers falling to a black centre, tendrils curling up from the rim |

- **Markers**: fuse = two jagged purple bolts crawling round the rim (re-rolled
  11–15×/s) on a pulsing purple wash, the odd arc jumping across the face;
  gale = three green gust strokes orbiting the centre plus small curls;
  stasis = six-fold rime crystal in the ice hair hue (`#5FD8F0`, the pale
  tile glow vanished on white) with a teal under-stroke and a glint.
- **Glaze**: a faceted frost sheet (voronoi facets, rime at the rim); the
  layers under it dim to 60 % and slow to 12 % speed (frozen in place, not
  out). It spreads from the centre when it forms (0.7 s); in its last cycle
  ink cracks branch across it.
- **Mixed tiles**: both axes draw; the dominant one sorts on top (ties:
  fire/water).
- **Tier changes** retarget an animated tier float; any change (one step,
  three steps, a fade or an element swap) takes ~0.3 s, never pops. Every
  feature fades in by its own tier band, so growth is continuous.
- **One-shots** (`BWBoardView.on_tile_event`, called from combat_screen on
  `paint` / `detonate` / `tiles_tick`): detonation = purple-white flash star +
  a shock ring over the six neighbours with six bolts to their centres
  (scaled by the splash radius); gale firing = green gust ring blowing
  outward (detected from the paint: a gale marker that caught a charge, or
  wind on a charged tile); glaze forming = the spread above; a grass seed =
  orange ring + flash + a 0.6 s flame-card flare.
- **Layering**: the board is in the transparent pass at priority 0
  (`flat.gdshader` writes ALPHA), so the FX join it at priority 0 with
  sorting offsets (faces 0.3, marks 0.4, unit highlights 0.5, bursts 3.0).
  Raised tiles in front still cover them; `BWRangeOverlay` (priority 1)
  draws above everything. `BWLook.set_dim` fades all of it.
- **Colour**: literals are written as sRGB and linearised in-shader; the
  renderer blends in linear space, so darkening layers (soot, dark, ink
  under-strokes) need high opacity to read dark on white.
- Title, loading and pre-battle boards get FX too: `BWTileFX.authored()`
  reads a map's `effects` array or per-cell `effect` key (§5.4 kinds). No
  shipped map authors any yet, and `BWBattle` does not load them (core).
- Cost (RX 9070, 1600×900, 24 u camera, 14×14 board): clean 0.76 ms/frame,
  every tile charged 1.33 ms (GPU 0.35 → 0.89 ms), 702 visible FX meshes;
  a frame where all 196 tiles swap element at once costs 5.6 ms (GDScript).
- Review: `design/art/tilefx_grid_combat.png` / `_axes` / `_ops`,
  `tilefx_<element>.gif` (fire, water, light, dark, thunder, wind, ice),
  `tilefx_combat.png` (+ `_after`, `_dim`). Regenerate with
  `tools/tilefx_review.gd` (modes grid / gif / combat / perf) and
  `tools/tilefx_gif.py`.

---

## 5. Duration, decay and containment

### 5.1 The tick

Once per cycle, after the last unit in the queue acts and before the next
queue is built (V8 `tick_tile_fx`). Two phases, in order:

**Phase 1: decay** (every entry):

1. `permanent` → skip.
2. `glaze > 0` → `glaze -= 1`; skip the rest (timer frozen).
3. `timer -= 1`. If `timer > 0`, done.
4. Timer hit 0:
   - marker → erase;
   - charge → step the **dominant** axis one toward 0 (|h| > |v| → h;
     |v| > |h| → v; tie → both). If it lands on (0, 0), erase. Otherwise
     `timer = STEP_CYCLES`. `origin` and `source` are kept.

**Phase 2: grass spread** (§6.2), computed against the board phase 1 left.

`STEP_CYCLES = 2` (V8 used 3). A fresh cast **refreshes** the timer. So an
untouched fire 3 lasts 6 cycles (3 → 2 → 1 → gone, 2 cycles each). V8's 3 was
set for larger maps and longer fights; in a 3v3 a fire 3 would outlast most
fights.

### 5.2 Durations at a glance

| Thing | Lasts |
|---|---|
| Charge, per intensity step | 2 cycles, then steps down |
| Gale copy | 1 cycle at its copied level, then steps down normally |
| Marker | 3 cycles, or until fired |
| Glaze | 2 cycles; decay paused meanwhile |
| Grass seed (§6.2) | an ordinary fire 1: 2 cycles |

### 5.3 Containment: why nothing chain-reacts

The failure V8 spent most care on is a cascade that eats the map and hangs the
game. In B|W it is ruled out by arithmetic plus one stored flag:

1. **Propagated arrivals never fire markers** and never displace them (§3.1
   step 3, §3.4). A field of gales fires one, and the rest stay armed.
2. **Gale copies are placed, not cast**: they never shift, detonate, glaze or
   gale anything, and never touch glazed or marked hexes.
3. **Detonation splash is damage only.** It never lays charge.
4. **Decay only lowers.** Nothing on the tick ever raises an intensity.
5. **Grass spread is once per cast** (§6.2): only `origin = "cast"` tiles at
   fire ≥ 2 ignite, they flip to `"spread"` when they do, and seeds land at
   fire 1 with `origin = "spread"`.

Bound: one action touches its own shape plus one ring (gale). One tick adds at
most one ring of fire 1 around each freshly-cast grass fire. Nothing a tick
creates can act on the next tick.

Self-test must assert (V8 pattern): a 7-hex field of gale markers terminates
after one cast; a grass map completely covered in grass, with one fire 3
cast, never has more than 7 burning hexes and is empty within 8 cycles; no
tick ever raises |h| or |v|.

### 5.4 Authored tiles

A map may declare starting charges or markers (V8 map JSON `effects` array:
`charge_<h>_<v>` and `mark_fuse` / `mark_stasis` / `mark_gale`). They load
with `permanent = true`, `source = −1` and never decay. The first change to the
hex (any cast, copy or seed) clears `permanent`, after which it behaves
normally; an authored marker that fires is gone for the rest of the fight. V8's
categorical kinds (`burning`, `wet`, `steam` …) and `mark_ward` are ignored
with a warning.

### 5.5 Static tiles (D115)

A map hex may declare a **static** charge (`"static": {"h": -3}` per cell, or
a top-level `statics` list; format in MAPS.md). It is the hex's **floor
state**. Authored tiles (§5.4) are a one-off starting charge; a static is
permanent and renewable. `BWBoard.statics` holds them, `BWTiles` lays them at
the start (`source = ""`, `origin = "spread"`, flag `static`), and the tick
re-forms them.

- **Never decays.** Phase 1 of the tick skips a static hex. After grass
  spread, a third phase (`_static_phase`) runs on every static hex:
  - empty → the floor returns;
  - glazed → the glaze counts down and nothing else happens (frozen in time);
  - holding a marker (armed while it was spent) → the marker counts down on
    its own timer and the floor returns when it fades. A re-forming static is
    a propagated arrival, so it never fires the marker (§5.3 rule 1);
  - charged → every axis the static declares **snaps back** to its value.
    A free axis painted on top (dark painted on static water) steps toward 0
    on the entry's own timer, one step per `STEP_CYCLES`, as normal decay
    would.
- **Painting on it works for that cycle.** Every rule in §3 applies
  unchanged. Opposites step it (fire on static water 3 = water 2 until the
  tick), more of the same clamps at 3 and snaps back, ice glazes it (glazed
  static water is walkable), and wind copies it to the ring. A real fire cast
  on static fire still gets its once-per-cast grass ignition, because the
  static phase runs after grass spread.
- **Detonation spends it** (`STATIC_SCAR_TICKS = 1`). Thunder on a static hex
  blows it as normal (static water 3 = 23%, then the tile is erased), and the
  hex is **scarred**: the next tick only counts the scar down, so the hex
  stays empty through the whole following cycle and the floor returns at the
  tick after that. Consume (`BWTiles.clear`) spends it the same way. Siphon
  only strips it until the tick. *Why:* without the scar, a staff user could
  detonate the same water 3 every cycle for 23% plus splash at no setup cost.
  With it, a static is at best a bomb every other cycle, and the lake goes
  quiet while it is spent. Undertow sees no pool while every water 3 is spent.
- **Static fire** burns standing and crossing units like painted fire (§2.2).
  Restored entries are `origin = "spread"`, so a static fire **never ignites
  grass** on its own.
- **Perks and the AI** read static hexes as ordinary charge, through the same
  `intensity` / `level_at` / `standing` calls: Undertow pulls toward static
  water 3, Shadowstep jumps between static dark hexes, Coal Engine starts
  turns on static fire, Waterwalking enters static water for 0.
- **Look** (D116, BWBoardView `_static_rim`): an inlaid rim (ink / element
  band / ink) with six ink wedges notched in at the corners and a colour
  lozenge at each wedge's tip. It draws above the FX layers (sort 0.45) and
  stays while the static is stepped down or spent, so the player always
  sees that the hex will come back. A two-axis static draws its band in the
  dominant axis's colour and the lozenges in the other's.
- Tests: `tests/test_static_tiles.gd`.

### 5.6 Seeded tiles (D134)

A map hex may declare a **seeded** charge (`"seed": {"v": -2}` per cell, or a
top-level `seeds` list; format in MAPS.md). It is a starting charge, not a
floor state: `BWBoard.seeds` holds it, `BWTiles.seed_hex` lays it as an
authored entry (§5.4: `permanent`, `source = ""`) flagged `seeded`.

- **Holds without decay** until play changes it (phase 1 of the tick skips a
  permanent entry). It is not re-formed: there is nothing to come back.
- **Any change makes it ordinary charge, for good.** An axis paint writes a
  fresh entry (light on seeded dark 2 = dark 1, which then decays; fire on
  it = fire 1 + dark 2, which decays); ice, wind and a Transfer lift clear
  `permanent`; thunder and Consume erase it (a seed is never scarred);
  Siphon and grass drying it write ordinary charge. `BWTiles.is_seeded(hex)`
  is true only while it is untouched.
- **Static vs seeded**: a static (§5.5) is the hex's floor and returns every
  cycle; a seed is how the hex starts. Maps should seed by default and keep
  statics for a few landmarks (MAPS.md, "Static vs seeded").
- **Look** (D135, BWBoardView `_seed_rim`): one thin ring in the element
  colour with a white hairline inside it, no ink rings or wedges, hidden as
  soon as the hex is changed. Perks and the AI read seeds as normal charge.
- Tests: the seed tests in `tests/test_static_tiles.gd`.

---

## 6. Terrain

Terrain is the map's; elements are an overlay on it and never change it (V8
BR-MAP-004 §1). D11's four types:

### 6.1 Neutral

No interaction.

### 6.2 Grassy: spreads fire

In tick phase 2, for every **grassy** hex whose entry has `h >= 2`,
`origin == "cast"`, and `glaze == 0`:

1. For each of its six neighbours that is **grassy**, has no marker and is
   not glazed:
   - `h >= 1`: no change (seeds never stack);
   - `h == 0`: set `h = 1` (keep v), `timer = STEP_CYCLES`,
     `origin = "spread"`, `source` = the burning tile's source. Create the
     entry if the hex was empty;
   - `h < 0` (wet grass): `h += 1`. The fire dries it instead of igniting it.
     Erase if this reaches (0, 0). Timer unchanged.
2. Set the burning hex's `origin = "spread"`. It has used its ignition.

All seeds are computed from the post-decay board and written after, so order
does not matter. A propagated seed never ignites a marker (rule 5.3.1).

What this means in play: fire 1 on grass just burns. Fire 2 or 3 on grass
lights a ring of smoulder around it on the next tick. Re-casting fire on a
burnt-out patch lights it again: grass can be used every time, but only by
spending an action. A gale over grass fire spreads it but cannot *ignite*
anything further (copies are `"spread"`).

Ignition is grass-to-grass only: fire on grass does not seed a neutral or
muddy neighbour.

### 6.3 Muddy: 2× movement

Base move cost 2 instead of 1. Water's move penalty is **added** on top:
muddy + water 3 costs 4. Glazed water removes only the water part (cost back
to 2). No other element interaction.

### 6.4 Jagged: impassable

Impassable, and it **never holds an entry**: area shapes skip it, gale copies
skip it, seeds skip it, and a skill targeting it lays nothing there.
Detonation splash simply finds no unit on it.

### 6.5 Move cost formula

```
cost(hex) = terrain_base(hex)               # 1 neutral/grassy, 2 muddy, ∞ jagged
          + water_penalty(hex)              # 0/0/1/2 for water 0..3; 0 if glazed
cost is never below 1.
```

---

## 7. How attacks lay elements

### 7.1 The element an action carries

- **Learned elements:** any element in which the unit has affinity rank ≥ 1.
  Every unit starts at rank 1 in its own (hair) element (D22 in code).
- **Skills** with `needs_element` show one menu row per learned element (V8's
  submenu), and lay the chosen one.
- **Attuned element:** the element the unit last used this battle; at battle
  start, its own element. **Basic attacks** carry the attuned element for
  damage bonus, resist rolls and affinity growth (V8: `unit.element` becomes
  what was last thrown). The HUD shows it next to the unit's name.
- **Cooldowns** are per skill **and** element (V8 `melee_cd_key`):
  Cleave-fire on cooldown does not lock Cleave-water. Default 2 turns.

### 7.2 Which actions paint which tiles

**Basic attacks do not paint,** except the staff's. V8 learned this the hard
way (BR-MAP-004 §6): painting on every basic hit turned every attack into free
area denial. The staff is the exception because it is the mage weapon and
painting is its job, and it paints one hex only.

| Weapon | Action | Tiles it applies the element to | Damage (to enemies on shape) |
|---|---|---|---|
| all but staff | Basic attack | none | weapon |
| staff | **Basic: Channel** | the target's hex, 1 step | spell (weapon 11 + WIL) |
| bow | Arcing Shot | target hex + its six neighbours | skill 10 |
| bow | Energized Shot | every hex from the archer (exclusive) to the target (inclusive) | skill 12, target only |
| lance | Tridentpierce | 2 hexes forward + every hex adjacent to them, minus the wielder's hex | skill 10 |
| lance | Vault | the hexes passed over (no damage) | none; follow-up Basic or Tridentpierce |
| axe | Cleave | 3-hex arc beside the user; if any arc hex already *carries* the element (§7.4), the arc plus its ring, minus the user's hex | skill 13 |
| axe | Charge | the hexes charged through | none; shoves, then follow-up Basic |
| daggers | Daggerleap | ring around the landing hex. May leap up to 3, or to any free hex that carries the element at any range | skill 8 |
| daggers | Dualthrow (×2) | each throw: archer-exclusive trail to the target | skill 9 per throw |
| daggers | Consume | erases the target's hex; then lays the eaten element (§7.5) on the user's ring except the eaten hex | skill 14 + 2 per intensity point eaten |
| sword | Striketwice | the target hex; on the second cut, if it is the same element as the first, the target hex + its ring, minus the user's hex | skill 11 per cut |
| sword | Riposte | when it triggers: the duelist's ring | skill 10 to each enemy on it |
| pistols | Reload | none now. The next pistol shot (basic or Quick Shot) lays the loaded element on the trail to the target, then the load is spent | — |
| pistols | Quick Shot | as Reload above | weapon basic |
| staff | Surge, Saturate, Ley Line, Siphon | see §9 | see §9 |
| fists | Flurry (×3) | the target's hex, 1 step, after the last strike | skill 12 at 45% per strike, each rolled |
| fists | Uppercut | none; knocks the target 1 hex straight back (a secondary effect) | skill 12, +50% if jagged, a steep rise or a unit stops the push |
| fists | Palm Burst | the target's hex, **2 steps** (a melee Saturate) | skill 9 |

Skill damage uses the brief's skill formula (`skill power + ½ STR + ½ DEX`);
staff actions use the spell formula (`power + WIL`). Skill powers are V8's
constants unchanged (`MeleeSkills`). Skills hit enemies only (V8,
faction-based); **tile effects hurt everyone**, allies included.

### 7.3 Order of operations for one action

1. Compute the shape.
2. Resolve each direct hit through the combat resolver, reading tile state
   **before** this action: dark/light hit-chance terms, and conduction (a
   thunder hit on a target standing on water gets +10% damage per water
   intensity, applied after mitigation).
3. Paint the shape (§3.5), whatever the rolls were. Avoid, glance and resist
   do not stop the ground from changing: the brief says secondary effects
   still apply on an avoid, and the ground is not a roll. A resist protects
   the *unit* (80% damage, no status riders) but not the *tile*.
4. Detonation damage from step 3 is separate tile damage (§8). It is not
   rolled and a resist from step 2 does not reduce it.
5. Award XP once per action (§8.4).

### 7.4 "Carries the element"

Used by Cleave's extension and Daggerleap's long jump.

| Element | A hex carries it when |
|---|---|
| fire / water / light / dark | that axis is on that side (any intensity): fire ⇔ h > 0 |
| thunder | it holds a `fuse` |
| wind | it holds a `gale` |
| ice | it holds a `stasis`, or it is glazed |

### 7.5 Dominant element of a tile

Used by Consume. The axis with the larger intensity; a tie goes to the h axis
(fire/water), matching V8's table. A marker's element is its operator. Points
eaten = |h| + |v|, or 1 for a marker.

---

## 8. Damage, affinity and resistance

### 8.1 Tile damage is a share of max HP

All tile damage and healing is **% of the affected unit's max HP**, not a
flat number and not scaled by the caster's stats.

Why, the options considered:

| Option | Problem |
|---|---|
| Flat (V8: 3 per fire point) | Stats grow from 1–6 to ~100 (D7) and HP to ~600. A flat 9 is meaningful in fight 1 and invisible by fight 6. Combos stop being worth an action. |
| Scaled by caster's WIL or affinity | A tile is touched by several units (A lays fire, B adds dark, C detonates). "Whose stats?" has no clean answer, the source changes every touch, and the start-of-turn number would jump around with no visible cause. |
| Through the brief's mitigation (`− 0.75 × RES`) | Subtracting ~75 from a single-digit tile number zeroes it late. |
| **% of victim's max HP** (chosen) | Stays relevant from fight 1 to the boss, readable ("Fire 3: 12% per turn"), and does not care who painted the tile. |

Rounding: `round(max_hp × pct / 100 × multipliers)`, minimum 1 when pct > 0.

### 8.2 Affinity on tile damage

The brief puts affinity resistance into the **resist chance** (`10% + RES% +
elemental resistance`). Tile damage is not rolled, so the same percentage
becomes a straight reduction:

```
tile_damage = max_hp × pct × (1 + 0.05 × detonator_thunder_rank)   # detonations only
                            × (1 − min(elemental_resist(victim, element), 75) / 100)
```

- `elemental_resist` is the code's `BWFormulas.elemental_resist`: 5 per own
  rank, 2.5 per rank of the opposite, 2.5 per ice rank against every element
  except ice. Cap 75 so nothing becomes immune.
- **Element of each tile event:** fire standing/crossing → fire; dark drain →
  dark; detonation → thunder. Light healing is not reduced by anything.
- **Detonator bonus:** a detonation is an action, so it gets the detonating
  unit's thunder damage bonus (+5% per rank, as the brief gives attacks). For
  a fuse, the detonator is the unit that **armed** it (the marker's
  `source`). Standing and crossing damage have no caster bonus: the ground
  does not remember who is strong.
- Direct hits from skills and spells use the normal resolver, with the
  attacker's affinity bonus and the defender's resist roll, unchanged.

### 8.3 Combat-formula touch points (for the forecast hover)

| Brief formula | Tile term | Shown as |
|---|---|---|
| Hit chance | +7 / −7 per light / dark intensity on the **target's** hex | "Target on Light 2: +14" |
| Damage | thunder vs target on water: × (1 + 0.10 × water intensity), after mitigation | "Conducted through Water 3: ×1.3" |
| Resist chance | none (tiles never roll) | — |
| Avoid / glance | none; painting happens anyway | — |

The forecast also lists what the action will do to the ground ("Detonates
Fire 3 / Dark 1: 21% to occupant, 10% splash"), using §8.2 with the current
board.

### 8.4 Growth, credit, and the boss

- **XP and affinity:** one award per action (the brief's "each attack"), for
  the element the action carried, whether or not it hit. Tile damage itself
  awards nothing. Non-elemental actions (Siphon, Charge without a follow-up)
  award XP and expertise only.
- **Knockout credit** from tile damage goes to the tile's `source`, if that
  unit is hostile to the victim. A knockout of your own ally on your own fire
  credits nobody.
- **Multi-hex units (the boss):** tile effects read only the unit's **centre
  hex**. Otherwise a 7-hex boss would take seven tiles' worth per turn. Whether
  the boss also gets a flat tile-resistance is a Gate 2 tuning call: at 12% of
  500 HP, a burning boss loses 60 per turn.

---

### 8.5 Chain lightning, Spark, Shatter (D86, author-approved)

**Conductive.** A unit whose centre hex holds a **fuse** is conductive. Any
damage it takes (a hit, a skill, a riposte answer, a counter, or tile
damage such as detonation splash, steam or a slam) also arcs
`CHAIN_FRACTION = 0.5` of that damage to the **nearest other living unit of
its own team**, measured by hex distance (footprint gap), with no range
limit. Ties go to the earlier unit in setup order. The arc:

- is thunder ground damage: it is not rolled, the receiver's thunder
  resistance (§8.2, cap 75) and `tile_pct` damage_taken_mod apply, minimum 1;
- chains **once**. The arc itself never arcs, even when the receiver stands
  on a fuse too, so loops are impossible;
- credits a knockout to the attacker (for tile damage: the tile's source, if
  hostile, as E14);
- emits `chain {from, to, amount, hp, by, hex, to_hex}`. The view draws a
  purple bolt and floats the number, and the audio plays a zap.

The forecast says "Conductive (thunder tile): 50% arcs to <name>"; the AI
adds the expected arc (`arc_ev`) to its score.

**Conductive vs detonation.** Fuse markers still detonate on a fresh axis
arrival, unchanged (§3.3). Within one action the hit resolves first, on the
pre-action ground (§7.3), so it arcs. Then the paint lands, and an axis
element on the fuse detonates it and erases the tile. The blast on that
occupant therefore does **not** arc: the fuse is spent. A neighbour caught
in the splash while standing on its own fuse does arc. A thunder cast onto
a fuse just re-arms it, and the occupant stays conductive.

**Spark.** A thunder-element hit (a thunder skill or spell, a staff basic
attuned to thunder, a pistol shot with a thunder round seated) on a target
whose hex holds **no charge** (empty, or only a marker) deals
`SPARK_PCT = +10%`. Forecast: "Spark: +10%". It is the floor that gives a
mono-thunder squad something before setup.

**Shatter.** Any attack (basic, skill, spell, answer, counter) on a unit
standing on a **glazed** hex deals `SHATTER_HIT_PCT = +15%`. Forecast:
"Shatter (glazed): +15%". It does not consume the glaze.

**Stacking.** All three are "dmg" modifiers and multiply after mitigation
with the rest (§8.3). Spark and Shatter never meet, because a glazed hex is
always charged. A thunder hit on glazed water gets Shatter ×1.15 and
conduction ×(1 + 0.1 × water). If the same action then lays thunder on that
hex, the detonation is separate tile damage with its own ×1.5 shatter (§3.2):
the hit's Shatter and the blast's ×1.5 both apply, to different numbers.

| Name | Value |
|---|---|
| `CHAIN_FRACTION` | 0.5 |
| `SPARK_PCT` | 10 |
| `SHATTER_HIT_PCT` | 15 |

Tests: `tests/test_element_rules.gd`.

---

## 9. Staff skills (new)

Staff is the mage weapon (D5). Its identity is **depth over breadth**: the
other weapons spread single steps over shapes; the staff is the only way to
jump a tile's intensity, draw long lines, and strip a tile. Same shape as
V8's `MeleeSkills.SKILLS`; damage is the spell formula. These replace the
blank `skills` cell for staff in `weapons.csv`.

```
"surge": {
  "key": "surge", "name": "Surge", "weapon": "staff",
  "desc": "Burst your element over a hex and everything beside it",
  "targeting": "hex", "needs_element": true, "range": 4, "cd": 2,
  "radius": 1, "power": 9,
},
"saturate": {
  "key": "saturate", "name": "Saturate", "weapon": "staff",
  "desc": "Pour two steps of your element into a single hex",
  "targeting": "hex", "needs_element": true, "range": 4, "cd": 2,
  "steps": 2, "power": 13,
},
"ley_line": {
  "key": "ley_line", "name": "Ley Line", "weapon": "staff",
  "desc": "Draw your element in a straight line, then act again",
  "targeting": "dir", "needs_element": true, "range": 4, "cd": 2,
  "power": 0, "follow_up": ["basic"],
},
"siphon": {
  "key": "siphon", "name": "Siphon", "weapon": "staff",
  "desc": "Strip a hex back toward bare stone, then act again",
  "targeting": "hex", "needs_element": false, "range": 4, "cd": 2,
  "power": 0, "follow_up": ["basic"],
},
```

### 9.1 Surge

Applies the element, 1 step, to the target hex and its six neighbours (7 hexes,
jagged skipped). Spell power 9 to each enemy in the area. The staff's version
of Arcing Shot, at shorter range.

### 9.2 Saturate

One hex. **Axis element:** shifts by 2 steps (`steps = 2` into `route`), so
empty ground goes straight to intensity 2, and an opposite at 1 flips to your
side at 1. A marker there fires on the 2-step state. **Operator element:**
fires once, as a normal application (no doubling). Spell power 13 to an enemy
on the hex. On a glazed hex, the axis pour washes off like any other.

### 9.3 Siphon

One hex, no element chosen, no damage. Moves h and v each **2 steps toward 0**,
removes any marker, and removes any glaze. Then offers a follow-up basic
attack (the Channel, so the mage can strip a hex and repaint it in one turn).
This is where V8's *purge* lives now (§2.5).

### 9.4 Ley Line

Pick a heading (one of six). Applies the element, 1 step, to up to 4 hexes in
a straight line from the caster (exclusive), stopping at a jagged hex or the
map edge. No damage. Then a follow-up basic attack.

### 9.5 Basic: Channel

`weapons.csv` staff row: power 11, range 3. Spell damage to one enemy, and the
**target's hex** takes 1 step of the attuned element (§7.2).

---

## 10. Constants

| Name | Value | V8 |
|---|---|---|
| `AXIS_MAX` | 3 | 3 |
| `AXIS_STEP` | 1 | 1 |
| `STEP_CYCLES` | 2 | 3 (`turns`) |
| `MARK_CYCLES` | 3 | 4 |
| `GLAZE_CYCLES` | 2 | 2 |
| `FIRE_STAND_PCT` | 4 per intensity | 3 flat |
| `FIRE_CROSS_PCT` | 2 per intensity | 1 flat |
| `LIGHT_HEAL_PCT` | 3 per intensity | 1 flat |
| `HIT_PER_POINT` | 7 | 7 |
| `DARK3_DRAIN_PCT` | 3 | +2 flat on the v = −3 row |
| `WATER_MOVE` | 0 / 1 / 2 | `|h| − 1` |
| `DETONATE_BASE_PCT` | 5 | 4 flat |
| `DETONATE_PER_POINT_PCT` | 4 | 3 flat |
| `CONDUCT_DET_PCT` | 2 per water intensity | 2 flat |
| `CONDUCT_HIT_MULT` | 0.10 per water intensity | +3 flat (thunder rider) |
| `SHATTER_MULT` | 1.5 | 1.5 |
| `SPLASH_FRACTION` | 0.5, rounded down | 0.5 |
| `ELEM_RESIST_CAP` | 75 | — |
| `GRASS_IGNITE_MIN` | 2 | — |
| `SKILL_CD` | 2 | 2 |

---

## 11. V8 → B|W

| V8 feature | Status | B|W |
|---|---|---|
| Two charge axes h/v, −3..+3 | **kept** | The intensity levels (D12) |
| `AXIS_STEP` 1, clamp ±3 | kept | |
| Neutral is absence (0,0 erased) | kept | |
| Opposite element walks the axis back | kept | |
| 49-row hand-declared `STATES` table with names | **changed** | Effects computed per axis; no per-state names |
| Borrowed tinted plate + `artScale` per state | changed | Two layered glows, one per axis, by tier |
| Per-state `turns` 3 | changed | `STEP_CYCLES` 2 |
| Decay: dominant axis steps inward, tie both | kept | |
| Fresh cast refreshes timer | kept | |
| Fire: 3 / 1 flat per point (stand / cross) | changed | 4% / 2% HP per intensity |
| Water `moveDelta` `|h| − 1` | kept | +0/+1/+2 |
| Accuracy ±7 per point of v | kept | as hit-chance points |
| Light heal 1 per point | changed | 3% HP per intensity |
| v = −3 row +2 dmg | changed | Dark 3 drains 3% HP |
| Thunder detonate `4 + 3×charge`, +2/water, ×1.5 glazed, half splash, erase | changed | Same shape, in % HP (5 + 4×charge, +2/water) |
| Ice glaze 2 cycles; fire melts, thunder shatters, ice thickens, rest wash off | kept | |
| Glazed tile effects persist | kept | plus glazed water has no move penalty (new) |
| Wind gale: radius-1 copy at duration 1 | kept | |
| Gale copy overwrites glazed tiles | **changed** | Glazed tiles refuse copies |
| Life operator: purge + soothe 4 | **dropped** | D4; purge reborn as staff Siphon |
| Ward marker | dropped | |
| Fuse / stasis / gale markers | kept | 3 cycles instead of 4 |
| Marker fires on fresh arrival only, propagated arrival leaves it armed | kept | Containment rule 1 |
| A hex holds charge or a marker, never both | kept | |
| `route()` pure plan + single mutator | kept | Plus simultaneous resolution per action (new) |
| Tick once per cycle, two phases | kept | Phase 2 is now grass spread |
| Categorical layer: 32 effects, `PAIRS`, compounds, steam, `REACTIONS`, `burnt` | dropped | Grid is the only model |
| `spreads` flag (wildfire, ashblown …) and duration-1 seed containment | changed | Survives only as grassy fire spread, contained by `origin` |
| `stamp_scenery`, terrain hazards (lava) | dropped | Four terrains only (D11) |
| `elemDmg` (thundercloud +25%) | dropped | |
| `conducts()` (thunder on water) | kept | +10% per water intensity |
| Authored effects permanent until changed | kept | Charges and markers only |
| Basic attacks never paint (BR-MAP-004 §6) | kept | except the staff's Channel |
| Weapon skills with `needs_element`, per-element submenu | kept | Learned = affinity rank ≥ 1 |
| Cooldown per skill + element | kept | |
| `unit.element` = last thrown | kept | "attuned element" |
| Skill shapes and powers (`MeleeSkills`) | kept | Powers feed the brief's skill formula |
| Consume reads the ground's element | changed | Dominant axis, tie → h; +2 per point eaten |
| Cleave / Daggerleap "tile carries element" | changed | Defined for markers and glaze too (§7.4) |
| Flintlock Reload seats an element; shot lays trail | kept | Pistols (D9) |
| Element magic menus (`napalm`, `douse`, `tailwind`, `sleet`, `halo` …, 32 skills) | dropped | Gun-era augments; ideas available for enchantments |
| Zones (firestorm, thundercloud, sleet, wildfire), portals | dropped | |
| Unit statuses from elements (burning DoT, chilled, rattled …) | dropped | Tiles carry the damage instead |
| Prologue flourish | dropped | |
| `CLASS_NAMES` per weapon × element | dropped | Not element rules; roster doc's call |
| Splash and tile damage hit allies | kept | |
| Crossing damage skips start hex; shoves deal none | kept | |

---

## 12. Decisions I made (for review)

| # | Decision | Why |
|---|---|---|
| E1 | Life's operator is dropped, not handed to another element. Purge survives as the staff skill Siphon. | Opposites, thunder and decay already cleanse; keeps thunder/ice/wind as one job each (D12). |
| E2 | Tile damage and healing are % of the victim's max HP. | Stays meaningful from 105 HP to ~600 HP; avoids "whose stats?" on shared tiles. |
| E3 | Tile damage is reduced by elemental resistance as a straight %, capped at 75, and not rolled. | Brief's affinity resistance applies, but deterministic ground is plannable. |
| E4 | Only detonations get a caster bonus (detonator's thunder rank; for a fuse, its armer). | A detonation is an action; standing damage is the ground. |
| E5 | `STEP_CYCLES` 2 (V8 3), markers 3 cycles (V8 4). | 3v3 fights are short; V8's numbers outlast them. |
| E6 | Effects are computed per axis instead of a 49-row table; visuals are two layered glows. | Matches the brief's per-element glow list; nothing per-state to author. |
| E7 | Glazed water has no move penalty. | New emergent play (freeze a river), one line of code. |
| E8 | Glazed tiles refuse gale copies (V8 let them through). | "Locked" should mean locked. |
| E9 | Grass ignites at fire ≥ 2, once per cast, seeding fire 1 onto grassy neighbours only. Wet grass dries instead. | Intensity matters; arithmetic plus one flag stops runaway. |
| E10 | Basic attacks don't paint, except the staff's Channel (target hex, 1 step). | V8's lesson about free area denial; the mage weapon gets to paint. |
| E11 | The ground changes on every outcome (avoid, glance, resist). Resist protects the unit only. | The brief: secondary effects still apply on avoid. The ground does not roll. |
| E12 | Learned elements = affinity rank ≥ 1. Basic attacks carry the attuned element (last used, default own). | V8's element submenu and `unit.element`, mapped onto affinity ranks. |
| E13 | One action = one XP/affinity award, whatever it hit. | Brief's "each attack"; V8 awarded per action too. |
| E14 | Tile knockouts credit the tile's source if hostile; friendly fire credits nobody. | Rewards setting traps without rewarding team-kills. |
| E15 | Multi-hex units read only their centre hex. | Stops a 7-hex boss taking 7× tile damage. |
| E16 | Within one action, all hexes resolve against the pre-action board; gale copies apply last; detonation damage is summed per unit. | Order-independent results and one damage number per unit. |
| E17 | Ice tile glow: pale cyan frost `#BFF4FF`. | The brief gives none; reads as frost against the `#5FD8F0` hair. |
| E18 | Four staff skills: Surge, Saturate, Ley Line, Siphon. | Staff = depth (2-step pour), lines, and stripping; the other weapons already cover shapes. |
| E19 | Gale copies overwrite (and can lower) neighbours. | Kept from V8. Makes wind both spread and dilution. |
| E20 | Jagged hexes never hold elements. | Impassable rock; keeps shapes and spread simple. |

---

## 13. Element perks (D93, author's final calls)

Five per element (`data/perks.csv`; rank 1 = one pick, rank 2 = a second,
rank 3 = all five, D90). Passives only. **Level** = the charge level of the
hex (`BWEffects.level_at`: an axis element's intensity 1-3; for ice 1 on a
glazed or stasis hex, wind 1 on a gale, thunder 1 on a fuse). Every number is
a named forecast line, a named Move term (`BWUnit.move_notes`, the Move
hover) or an event. Keys: `BWEffects.PERK_KEYS`; hooks marked "D93" in
`battle.gd` and `tiles.gd` (via `paint_opts`).

| Element | Perk | Rule | Key |
|---|---|---|---|
| Water | Waterwalking | Entering a water hex (any level) costs this unit 0 move. Deliberately broken. | `move_cost` |
| Water | Flow State | You and allies standing in water: +3/+6/+9 avoid. | `stand_on_mod` def, team |
| Water | Current Push | Attacking from water: +5/+10/+15% damage. | `stand_on_mod` att |
| Water | Tidal Guard | Standing in water: +15 glance per level (15/30/45). Nothing else. | `stand_on_mod` def |
| Water | Undertow | While the holder lives and any water 3 exists, its enemies search with move+1 and keep a destination only if it is closer to the nearest water 3 (cost ≤ move+1), level with it (≤ move) or farther (≤ move−1). The range overlay shows the filtered reach. | `undertow` |
| Fire | Heat Rush | No fire crossing damage; the first fire hex entered each turn gives +1 move. | `heat_rush` |
| Fire | Ember Skin | An adjacent foe that hits you while you stand on fire takes 2/4/6% (your fire level); your fire standing damage is halved. | `ember_skin` |
| Fire | Kindling | +5/+10/+15% damage when you or the target stands on fire (the higher level). | `stand_on_mod` either |
| Fire | Wildfire | Your fresh fire at 2+ is `wild`: on the next tick it seeds fire 1 onto every neighbour whose fire axis is neutral, once per cast (origin flips to spread). Wild seeds never dry wet ground and never seed again. | `wildfire` |
| Fire | Coal Engine | Allies (you included) starting their turn on fire 1/2/3: +1/+2/+3 move that turn. | `start_move` team |
| Ice | Skate | Glazed and stasis hexes cost 1 (plus climb) even on mud; +1 move starting on one. | `skate` |
| Ice | Rime Armour | −10% damage taken on a glazed or stasis hex; Shatter doesn't apply to you. | `rime_armour` |
| Ice | Fault Lines | Your Shatter is +30% (base 15) and your Shatter hit breaks the glaze (glaze → 0, the charge stays). | `fault_lines` |
| Ice | Frostbite | A foe starting its turn on glaze you laid (`glaze_source`) is Drenched for that turn. | `frostbite` |
| Ice | Frost Ward | On your 1st turn and every 2nd turn after (the card shows "Frost Ward recharging" between), the nearest unwarded ally within 2 (else you) gains a Frost Ward (a status that keeps until it breaks; one per unit). It negates the next elemental effect on its holder, then breaks (`ward_break`). | `frost_ward` |
| Thunder | Bolt Step | After any action that detonated a tile: move 2 more. | `bolt_step` |
| Thunder | Grounded | Chain arcs reaching you deal half; detonation splash on you is halved again. Still conductive. | `grounded` |
| Thunder | Overcharge | An arc from a target you hit jumps once more: a second arc at 50% of the first's damage to the next-nearest of that team. With it, nobody is arced twice in one action. | `overcharge` |
| Thunder | Static Field | Your fuses last 5 cycles (base 3); a foe ending its move on one is Staggered. | `static_field` |
| Thunder | Lightning Rod | An arc that would hit an ally within 3 of you hits you instead at 50%. | `lightning_rod` |
| Wind | Tailwind | +2 move starting on a gale marker; after any wind action, move 1 more. | `tailwind` |
| Wind | Eye of the Storm | Immune to displacement; bow, pistol and thrown (daggers beyond 1) attacks on you get −15 hit. | `eye_of_storm` |
| Wind | Gale Force | +5% damage per hex moved this turn, up to +20%. | `attack_mod` |
| Wind | Gust | A foe your wind skill hits (unresisted) is pushed 1 away; if rock or a unit stops it, it slams for 8%. | `gust` |
| Wind | Slipstream | Allies starting their turn within 2 of you: +1 move. | `slipstream` |
| Dark | Shadowstep | Once per turn, from a dark hex, step to another dark hex within 3 for 1 move, ignoring the path. | `shadowstep` |
| Dark | Nightborn | No dark drain on you (dark 3, Shrouded). While you stand on dark, the first elemental effect each turn on you is negated (`ward_break`, source `nightborn`). | `nightborn` |
| Dark | Ambush | Attacking from dark 1/2/3: +5/+10/+15 crit. | `stand_on_mod` att |
| Dark | Pall | A foe you hit while it stands on dark 2+ is Blinded. | `hit_status` |
| Dark | Cover of Night | Attacks on allies adjacent to you: −7 hit. | `cover` |
| Light | Sunpath | +1 move starting on light, +2 on light 3. | `start_move` |
| Light | Radiant Guard | Light's hit bonus doesn't apply to attacks on you (shown as a 0 line). | `radiant_guard` |
| Light | Judgement | Your attacks on a foe standing on light can't glance. | `judgement` |
| Light | Glare | A foe starting its turn on light you laid isn't healed; on light 2+ it's Blinded. | `glare` |
| Light | Sanctuary | Your light heals your side 5/9/14% (base 3/6/9). Once per battle, an ally within 3 dropping under 35% HP gets light 2 on its hex. | `sanctuary` |

**Negation (D93).** "Elemental effect" = tile damage from an element (fire
standing or crossing, dark drain, Shrouded, a detonation blast or splash, an
eruption, steam, Ember Skin), a chain arc, an elemental status (Scorched,
Drenched, Shrouded, Blinded; Staggered when Static Field lays it), or
displacement by an element (gale, blast and eruption pushes, Gust). Nightborn
is checked first so a Frost Ward is kept when it can be.

### 13.1 Statuses (D94)

Every short status lasts until the end of the holder's next turn (one applied
at the holder's own turn start ends with that turn). None lowers hit any more.

| Status | Effect |
|---|---|
| Staggered | Can't use skills (basic attack only). The menu and the AI read `skills_for`, which is empty. When it ends the unit is **Steadied** for its next 2 turns: immune to Staggered (an attempt emits `status_resisted`; forecasts on it read "Steadied: immune to stagger"). |
| Blinded | Can't crit (a `crit_x` 0 line); can only target units within 2 hexes (basic and skills). |
| Pinned | −2 move. |
| Drenched, Scorched, Shrouded | Unchanged (D87). |

### 13.2 Facing (D96)

The defender's last facing (`BWUnit.facing`) adds one named line to every
blow, from the attacker's hex: directly behind "Rear attack +15 hit", the
rear flanks "Rear flank +5 hit", the front flanks "Front flank +5 glance",
straight ahead "Facing the blow +10 glance". Unknown facing adds nothing. The
AI scores hexes with forecasts made from that hex, so it flanks.
