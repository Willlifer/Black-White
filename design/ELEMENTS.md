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
| **Thunder: detonate** | (Not on unglazed water: since D264 that electrifies, §14.) The charge explodes and the tile is erased. The occupant takes the full blast; every unit on the six neighbours takes half (rounded down). Splash is damage only and never lays charge. | blast = `5% + 4% × (|h| + |v|)` + `2%` per water intensity, × `1.5` if glazed ("shatter") |
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
  turns on static fire, Waterwalking makes its first static water hex each turn free (D204).
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

**Rough terrain (D361):** axes and daggers are *Rough-Footed* (`weapons.csv`
`traits`): mud costs them 1, like neutral ground. Only the mud: water's
penalty and every other cost still apply (muddy water 3 costs them 3).

### 6.4 Jagged: impassable

Impassable, and it **never holds an entry**: area shapes skip it, gale copies
skip it, seeds skip it, and a skill targeting it lays nothing there.
Detonation splash simply finds no unit on it.

### 6.5 Move cost formula

```
cost(hex) = terrain_base(hex)               # 1 neutral/grassy, 2 muddy (1 Rough-Footed), ∞ jagged
          + water_penalty(hex)              # 0/0/1/2 for water 0..3; 0 if glazed
a step is refused when rise > jump; a rise within the jump costs nothing
extra (D375, superseding D20's +1 per level climbed).
cost is never below 1.
```

### 6.6 Move and jump by weapon (D359, D360, D371–D373, D375–D377)

**Move** is the weapon drawn when the unit's turn starts (`weapons.csv`
`move`): bow, pistols, staff **4**; sword, daggers, fists **5**; axe,
lance **4**. A mid-turn swap keeps this turn's move (and jump); the next turn
reads the new weapon. Between turns the sheets show the drawn weapon's.
Perks, sets, statuses, terrain bonuses and Wander add on top, named in the
Move hover: "Move 5 (Daggers) +1 Swift · Climb 2", "Move 4 (Lance) · Climb 4
(Lance)", "Move 4 (Bow) · Climb 4 (HighGrounder)", "Move 5 (Sword) · Climb 3
· Updraft +1 (Tailwind)".

**Jump** is the most levels one step may rise (D371, superseding D360's 1):
**2** for everyone, **4** (double) for the lance (`weapons.csv` `jump`).
**Climbing is free up to the jump (D375):** a step that rises at most the
jump costs the normal step (1, mud 2, …); a higher step is a wall; dropping
down is free and unlimited. Forced moves (shoves, charges, pulls) keep D20's cap of 2.

**Updraft (D376/D377)** is part of the wind perk **Tailwind**, not automatic
for wind units: the holder's jump gets **+1 after every other modifier** (a
lance 5, a HighGrounder bow 5), and any unit of the holder's team whose turn
starts on one of the holder's gale markers (a wind field included) gets
**+1 jump that turn** (read at turn start, like the move lock). They stack:
+2 at most (the holder on its own gale). The Move hover names it: "· Climb 3
· Updraft +1 (Tailwind)", "Updraft +1 (Tailwind, on Ana's gale)". The Move hover
always names the jump ("Climb 2"; "Climb 4 (Lance)").

**HighGrounder (D372)** is a **pickable bow passive**, not an innate trait:
the bow's expertise picks (D174's two cards) can offer it next to Improve /
Learn (`weapons.csv` `passives`, `BWWeaponMove.PASSIVES`). Taken, it doubles
the jump to **4 while a bow is drawn** (the turn-start lock, D359) and **takes
no skill slot** (its id rides in `known_skills` with no skill def, so no
loadout lists it). The unit card shows "■ HighGrounder jump 4 with a bow
drawn" once owned. Enemy bows may roll it at their stage picks (the AI takes
a passive whenever its two cards offer one).

**Maps (D373):** at jump 2 every map walks as it did under D20: Paintball's
8 and Tinderbox's 6 perch hexes are open to everyone again. Ravine keeps its
1-level stair (harmless at jump 2). Jump 4 adds lance / HighGrounder ground:
Tinderbox's berm (elevation 3, "unclimbable from the ground") and
Stronghold's north wall walk from inside the yard; no castle wall can be
climbed from outside, and the castles' 2-turn perch rule holds at jump 2
(`tools/castle_maps.py` JUMP = 2, `tools/jump_maps.gd`).

**High ground (D362):** Daggerleap, Charge, Vault and Dragoon Dive started 1+
level above the landing / the charge's first hex / the target reach 1 farther;
Daggerleap's and the Dive's landing ring widens to radius 2; Charge's shove
carries 2 hexes. See SKILLS.md.

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
5. Award affinity and expertise once per action (§8.4).

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

- **Affinity and expertise (no XP, D179):** one award per action (the brief's "each attack"), for
  the element the action carried, whether or not it hit. Tile damage itself
  awards nothing. Non-elemental actions (Siphon, Charge without a follow-up)
  award expertise only.
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
| E13 | One action = one affinity/expertise award, whatever it hit (no XP since D179). | Brief's "each attack"; V8 awarded per action too. |
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
| Water | Waterwalking | The first water hex this unit crosses each turn costs no move (D204; was "any water costs 0"). | `move_cost` `once=1` |
| Water | Flow State | You and allies standing in water: +3/+6/+9 avoid. | `stand_on_mod` def, team |
| Water | Current Push | Attacking from water: +5/+10/+15% damage. | `stand_on_mod` att |
| Water | Tidal Guard | Standing in water: +15 glance per level (15/30/45). Nothing else. | `stand_on_mod` def |
| Water | Undertow | While the holder lives and any water 3 exists, its enemies search with move+1 and keep a destination only if it is closer to the nearest water 3 (cost ≤ move+1), level with it (≤ move) or farther (≤ move−1). The range overlay shows the filtered reach. | `undertow` |
| Fire | Heat Rush | No fire crossing damage; the first fire hex entered each turn gives +1 move. | `heat_rush` |
| Fire | Ember Skin | An adjacent foe that hits you while you stand on fire takes 2/4/6% (your fire level); your fire standing damage is halved. | `ember_skin` |
| Fire | Kindling | +5/+10/+15% damage when you or the target stands on fire (the higher level). | `stand_on_mod` either |
| Fire | Wildfire | Your fresh fire at 2+ is `wild`: on the next tick it seeds fire 1 onto every neighbour whose fire axis is neutral, once per cast (origin flips to spread). Wild seeds never dry wet ground and never seed again. D307: your Overheat ring hexes at 2+ are wild too (spread origin; the flag is spent at the tick). | `wildfire` |
| Fire | Coal Engine | Allies (you included) starting their turn on fire 1/2/3: +1/+2/+3 move that turn. | `start_move` team |
| Ice | Skate | Glazed and stasis hexes cost 1 even on mud; +1 move starting on one. | `skate` |
| Ice | Rime Armour | −10% damage taken on a glazed or stasis hex; Shatter doesn't apply to you. | `rime_armour` |
| Ice | Fault Lines | Your Shatter is +30% (base 15) and your Shatter hit breaks the glaze (glaze → 0, the charge stays). | `fault_lines` |
| Ice | Frostbite | A foe starting its turn on glaze you laid (`glaze_source`) is Drenched for that turn. | `frostbite` |
| Ice | Frost Ward | On your 1st turn and every 2nd turn after (the card shows "Frost Ward recharging" between), the nearest unwarded ally within 2 (else you) gains a Frost Ward (a status that keeps until it breaks; one per unit). It negates the next elemental effect on its holder, then breaks (`ward_break`). | `frost_ward` |
| Thunder | Bolt Step | After any action that detonated a tile: move 2 more. | `bolt_step` |
| Thunder | Grounded | Chain arcs reaching you deal half; detonation splash on you is halved again. Still conductive. | `grounded` |
| Thunder | Overcharge | An arc from a target you hit jumps once more: a second arc at 50% of the first's damage to the next-nearest of that team. With it, nobody is arced twice in one action. | `overcharge` |
| Thunder | Static Field | Your fuses last 5 cycles (base 3); a foe ending its move on one is Staggered. D307: your allies' paint can't set off, re-arm or wash your fuses (`fuse_guard` in the paint opts). | `static_field` |
| Thunder | Lightning Rod | An arc that would hit an ally within 3 of you hits you instead at 50%. | `lightning_rod` |
| Wind | Tailwind | +2 move starting on a gale marker; after any wind action, move 1 more. **Updraft** (D376/D377): +1 jump after every other modifier; a unit of your team starting its turn on your gale marker gets +1 jump that turn (you on your own: +2). | `tailwind` |
| Wind | Eye of the Storm | Immune to displacement; bow, pistol and thrown (daggers beyond 1) attacks on you get −15 hit. | `eye_of_storm` |
| Wind | Gale Force | +5% damage per hex moved this turn, up to +20%. D307: after moving 4+, your first landed hit on a foe that turn applies your wind mode (within the wind caps). | `attack_mod` |
| Wind | Gust | A foe your wind skill hits (unresisted) is pushed 1 away; if rock or a unit stops it, it slams for 8%. | `gust` |
| Wind | Slipstream | Allies starting their turn within 2 of you: +1 move. | `slipstream` |
| Dark | Shadowstep | Once per turn, from a dark hex, step to another dark hex within 3 for 1 move, ignoring the path. | `shadowstep` |
| Dark | Nightborn | No dark drain on you (dark 3, Shrouded). While you stand on dark, the first elemental effect each turn on you is negated (`ward_break`, source `nightborn`). | `nightborn` |
| Dark | Ambush | Attacking from dark 1/2/3: +5/+10/+15 crit. | `stand_on_mod` att |
| Dark | Pall | A foe you hit while it stands on dark 2+ is Blinded. | `hit_status` |
| Dark | Cover of Night | Attacks on allies adjacent to you: −7 hit. | `cover` |
| Light | Sunpath | +1 move starting on light, +2 on light 3. D307: an ally on your beam (its hexes, the bend or the other end) starts its turn with +1 move, read live. | `start_move` |
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

---

## 14. The ice/water spine (D261-D268, Element Overhaul)

Built from `ELEMENTS-v3.md` §2 and §4 with the author's rulings of
2026-10-07. Code: `src/core/slides.gd` (BWSlides), `src/core/pools.gd`
(BWPools, which also owns pillars); hooks in `BWTiles.apply` / `tick`,
`BWBoard.blocker` / `sight_blocker`, `BWBattle.reachable` / `move` /
`_displace`. View: `BWIceWaterView` (`src/game/combat/icewater_view.gd`,
`shaders/icewater.gdshader`). Tests: `tests/test_icewater.gd`. Renders:
`design/art/v3_icewater_*.png` (`tools/icewater_shots.gd`).

### 14.1 Slides (D261)

- **Slippery** = glazed charge that isn't a pillar (stasis doesn't slip).
- A unit that **enters** one (walking, pushed, pulled, shoved) slides on in
  its direction of travel, free, one hex at a time:
  - next hex non-ice standable: it slides onto it and **stops there**;
  - next hex lower (a ledge of any height): onto it, stop, no fall damage;
  - next hex blocked (rock, a unit, a pillar or wall, a rise of 1+): stop
    before it; if it slid 1+ that's a **slam: 8% to it and to the unit hit**;
  - the map edge: stop, no slam; `SLIDE_MAX` 6 slide hexes.
- **A walk that slides ends there; then the unit may move 1 more hex**
  (once a turn). `reachable()` lists the slide's END hex (cost = the step
  onto the ice); ice hexes are never stops. A slam can't be undone.
- Crossing damage applies on slide hexes. Order in an action: hit, paint,
  pushes, slides, slams.
- Skate holders and multi-hex units never slide.

### 14.2 Pillars (D262, D263)

- A fresh glaze (ice, or a Blizzard mark) on **empty** water 3 raises a
  pillar: impassable, blocks line of sight (`has_los` reads it, so basic
  ranged attacks and `los` skills do), stops slides and pushes (slam).
- 3 ticks (decay frozen), then water 3 again. Fire melts it; thunder
  shatters it (34.5% centre, 17% ring). 4 per caster (a fifth melts the
  oldest). Re-icing doesn't refresh it.

### 14.3 Pools (D264, D265)

- A **pool**: connected unglazed water, BFS from the cast hex, nearest first,
  capped at 19 (`POOL_MAX`; 25 for a caster wearing the Water set (2), D307). Only fresh fire, ice and thunder react; light,
  dark, water and wind never travel through a pool.
- **Fire: steam** over the whole pool for 2 ticks. It blocks sight through
  it (not between hexes within 2), and a unit in steam can be single-targeted
  only from within 2.
- **Ice: rink** within radius 1 of the cast hex: those pool hexes glaze;
  empty water 3 among them become pillars.
- **Thunder: electrified** within radius 1 of the cast hex (always, even a
  1-hex puddle; water arriving on a fuse too; glazed water still shatters):
  - 15% thunder at an occupant's turn start (after fire, before the drain)
    and Staggered; 5% on entering, once per walk or slide; conductive;
  - each unit's ramp per field: full, 25%, then immune;
  - 2 ticks (decay frozen), then it discharges (each hex steps down 1 water;
    a static scars a tick);
  - never refreshed (one field per pool); fire on a hex clears it there.
- An area shape on water reacts within 1 of each of its water hexes.
- A seeded hex that reacts becomes ordinary water.

### 14.4 Readability (D266)

Blast preview: slide arrow + ghost ring + "SLIDE" / "SLAM 8%", the reacting
pool hatched with a dashed outline and a "STEAM" / "ELECTRIFIED" tag, a
rising "PILLAR". Move hover: the arrow runs over the ice, the hint names the
slide and any slam. Tile card: Rink, Pillar, Steam, Electrified (with the
occupant's next shock), Pool. Board: a slippery sheen, the inked ice pillar
with its ticks, steam puffs, the electrified outline with timer pips.

## 15. Fire, light and thunder (D285-D292, Element Overhaul)

Built from `ELEMENTS-v3.md` §3, §5 and §7 with the author's rulings of
2026-10-07 (fire as drafted; light without Dawn Relay, plus Magnify; Blast
Rider without the full ring). Code: `src/core/overheat.gd` (BWOverheat),
`src/core/beams.gd` (BWBeams), `src/core/thunder_keys.gd` (BWThunderKeys);
hooks marked D285-D291 in `BWTiles.apply`, `BWBattle` (paint, _tile_hurt,
_mods, _plan, use_skill, move, the turn start/end, the tick, _digest),
`BWEnchant.land`, `BWSlides` and `BWAI`. Keystones are read through
`BWKeystones.has` (or the dev flag `u.fx["ks:<id>"]`). View:
`BWElementsView` (`src/game/combat/elements_view.gd`). Tests:
`tests/test_fire_light_thunder.gd`. Renders: `design/art/v3_fire_*`,
`v3_light_*`, `v3_thunder_*` (`tools/flt_shots.gd`).

### 15.1 Fire: Overheat (D285)

- A **fresh** fire arrival on a hex that was **already fire 3** (unglazed,
  before the action) erupts. Propagated fire (spread, Trailblazer, on-kill
  paint) never erupts.
- **Ring:** each of the six neighbours gets a propagated **+2 fire**
  through `_route` (water 3 → water 1, fire 1 → fire 3, empty → fire 2,
  origin "spread", so it never ignites grass). Glazed and marked hexes,
  pillars, walls and hexes erupting in the same action are skipped. Fire on
  an electrified hex clears it there.
- **Damage:** 6% (fire class) to every unit on the ring, both teams,
  summed per unit over the action's eruptions (one event per unit, cause
  `overheat`). The centre's occupant isn't hit by its own eruption.
- **Centre:** vents to fire 2. A hex erupts once per action.
- **Telegraph:** fire 3 hexes carry a pulsing fire-on-ink rim; the forecast
  says "Overheat: … erupts, the ring to fire +2, 6% to every unit on it"
  (skills) or carries the note (a fire basic on fire 3); the blast preview
  hatches the ring with a dashed fire rim and tags "OVERHEAT 6%".

### 15.2 Fire keystones (D286)

- **Conflagration:** a ring hex the holder's eruption **raised** to fire 3
  erupts too, at depth 2 at most; every qualifying ring hex of a depth-1
  eruption chains (the preview tags "×2").
- **Trailblazer:** every hex the holder leaves on a walk gets propagated
  fire 1 (the start hex included, the end hex not), up to 4 a turn; no
  crossing burns on walks or slides. Undoing the move removes the trail.
- **Phoenix Heart:** its own fire (standing, crossing, Overheat) never hurts
  it; standing on fire 3 (anyone's) at turn start heals 12% instead; once a
  battle, a KO (a blow or ground damage) while it stands on fire leaves it at
  1 HP and Overheats its hex (as the holder's eruption).

### 15.3 Light: beams, Empowered, dawn (D287)

- **Beam:** two allies, each on light 1+, on one straight hex line **2 to 4
  apart** (adjacent allies don't beam: a beam needs a hex to cross), with no
  rock, pillar or wall between. Units never block. One beam per pair; each
  unit is the end of at most 2 (shortest pairs first, then setup order).
  Beams are read from the board whenever asked, so they form and break as
  units move.
- **The tick** (after the vortex pull, before decay): foes on beam hexes
  take **4% + 2% × the lower end's light** (light class, cause
  `light_beam`), once per tick (the strongest beam); allies on beam hexes and
  both ends become **Empowered**.
- **Empowered:** +15% damage on the unit's next attack made on its own turn
  (a basic or a damaging skill), spent by that action; it ends with the
  unit's next turn. A unit is Empowered once (the stronger one stands).
- **Dawn:** a unit starting its turn on light 2+ takes 1 off its longest
  cooldown (after the normal turn tick), once per turn.
- **Dawn Relay is removed** (the ruling).
- **Telegraph:** a thin dashed light line between the ends (over an ink
  stroke), "EMPOWERED +15%" over Empowered units, a light ribbon at the tick;
  the blast preview draws the beams the board would hold after the action,
  hatches their hexes and tags both ends "EMPOWERED".

### 15.4 Light keystones (D288, D289)

- **Prism:** a team with a holder may also beam two ends that aren't in
  line through a **bend** ally on light (each segment straight, clear, 2-4);
  the bend ally is on the beam but spends no end slot; one bend per beam.
  Allies on a beam the holder is part of heal 5% at the tick.
- **Overflow:** light healing the holder lays (its light tiles, its Prism
  heals) beyond max HP becomes a **Ward of Light**: a shield of the excess,
  up to 15% max HP, that absorbs the next damage (blow or ground) and breaks,
  or fades after 2 cycles. A beam the holder is part of Empowers +25%.
- **Magnify** (the ruling's enabler): an **ally** standing on the holder's
  light (not the holder) casts magnified, **once per turn**, on its first
  element or area skill:
  - an area skill whose shape has radius 1 or 2 gets **+1 radius**: the
    next ring joins the shape (hit and painted). Radius 2 becomes 3, never
    more; a radius-3 shape gets the step instead;
  - any other skill cast with an element gets **+1 charge step** on its
    paint (the axis still caps at 3);
  - basic attacks and elementless non-area skills aren't magnified (and
    don't spend it).
  The forecast's notes say "Magnify (X's light): +1 radius, 1 → 2" or "+1
  charge step"; the blast preview rims the new ring and tags "MAGNIFY".

### 15.5 Thunder keystones (D290, D291)

Thunder's base rules are kept (water electrifies, §14.3).

- **Static Blades:** each basic hit the holder lands arms **its fuse** on
  the target's hex if the hex holds nothing (one Static fuse per foe; not
  under a Blank). A **backstab** (the rear three, D96, judged from where the
  blow was struck) on a foe standing on the holder's fuse bursts it instead:
  **12%** to the occupant, **6%** to the ring, times the thunder bonus
  (affinity rank, Stormcaller's), once per turn. The burst counts as a
  detonation (Bolt Step, Daisy Chain, Blast Rider's immunity).
- **Blast Rider:** immune to its own detonations (blast and splash, cause
  `detonation` credited to it). A detonation from the holder's own action
  **on its own hex** launches it: **move 2** after the action, replacing
  Bolt Step's +2 (no stacking). The ring takes the **normal half** (the
  ruling: no full ring). Once per turn; the blast spends the charge and the
  holder can't re-arm that (empty) hex until its next turn.
- **Self-detonate (D306):** a FREE action for a Blast Rider holder standing
  on a charge thunder detonates (anything charged but unglazed water, which
  electrifies) or on its own fuse: it blows its own hex under the rules
  above (immune, the ring the normal half, launch 2, once per turn, the hex
  locked). An own empty fuse blows at the 5% base and counts as a fuse going
  off (Daisy Chain). It is the dagger bomber: Daggerleap into the pack onto a
  fuse or fire, Self-detonate, launch out. Any weapon may use it. The AI
  blows it when the simulated blast nets damage (free actions go last, then
  it walks the launch to its safest hex). Def `self_detonate`; renders
  `design/art/v3_final_dive_1|2|3.png`.
- **Daisy Chain:** once per turn, when the holder's fuse detonates (a fresh
  charge on it, or a blade burst), its nearest other fuse within 3 (ties by
  hex order) detonates in the same action at the 5% base (a fuse is empty).
  Nothing chains further.
- **Readability:** the holder's fuses carry two crossed ink blades; the
  blast preview tags "STATIC FUSE", "BLADE BURST 12%" and draws the launch
  arc with "LAUNCH: MOVE 2"; VFX: crossing slashes, the launch arc.

### 15.6 AI (D292)

`BWAI._best_hex` adds `BWBeams.ai_hex` (a hex on light in line with an ally
on light scores the beam's damage on the foes it would cross plus a little
for Empowered; a hex on a foe's beam costs its damage). `_best_target` adds
the blade burst a backstab would set off; `_best_skill` adds the Overheat
ring's damage on foes minus allies (and a little for fire 2 brought to 3
beside a foe) and, for a Blast Rider holder, a `simulate` of a thunder skill
covering its own charged hex (ground damage on foes minus allies, +3 for
the launch).

## 16. Wind, ice, water and dark keystones (D293-D300, Element Overhaul)

Built from `ELEMENTS-v3.md` §1, §2, §4 and §6 with the author's rulings of
2026-10-07 (C3; numbered §14.5-§14.9 until D305 moved them here, after
§15, so the overhaul reads §14 spine, §15 fire/light/thunder, §16 the other
keystones). Code: `src/core/ks_wind.gd`, `ks_ice.gd`, `ks_water.gd`,
`ks_dark.gd`, dispatched by `keystone_fx.gd` (BWKeystoneFx). Tests:
`tests/test_keystones_c3.gd`. Renders: `design/art/v3_c3_*.png`.

### 16.1 Wind keystones (D293)

Code: `src/core/ks_wind.gd` (BWKsWind), hooked from `BWWind`; who holds
what is `BWKeystones`. Every field move stays inside the wind caps (2 hexes
a cycle, a field once a turn).

- **Eye of the Vortex:** your Vortex fields pull everyone within 2 in, up to
  2, step by step toward the centre (each stops before the first blocked
  hex: no slam), when they fire and at the tick. Only your newest Vortex
  field acts per tick (fields carry a `born` serial). Board: a dashed ink
  ring at the field's 2-hex reach.
- **Wind Wall:** the D273 action, now granted only by the keystone (the
  `ks:wind_wall` flag and `wall_for_all` are gone). **AI (D304):** every legal
  wall is scored; it raises the best when a ranged foe (reach 3+) threatens 2+
  of its side along straight lines the wall cuts (8% of each screened unit's
  max HP), or a melee foe within move + reach of a hurt ally (under 50%)
  would approach across it ((10% + 20% x the missing share) of its max HP);
  never with a foe beside the caster or while its own wall stands. The score
  is in HP like an attack's, and the heading is passed as the second pick.
- **Jetstream:** wind by a holder on a gale 2 makes a **gale 3** (copies to
  radius 3; `gale_max` in the paint opts); the copies its paint makes, or its
  gales make, last 2 cycles; its Gust fields push 2. Board: a gale 3 gets a
  wide three-armed swirl.
- **Rink carry (the D272 TODO):** a glazed hex never fires a gale, so a gale
  that fires next to a rink carries it instead: its **water** copies glaze for
  1 cycle (a fire or light copy stays unglazed; never a pillar).

### 16.2 Ice keystones (D294)

Code: `src/core/ks_ice.gd` (BWKsIce); defs `flash_freeze`, `glacier_shatter`.

- **Skater:** never slides (pushed or pulled onto ice it stops there; a walk
  crosses ice like ground, so "where to stop on the slide line" is where the
  walk ends). Its first 4 ice hexes entered each turn cost 0 (climbs are
  free since D375), then 1; the count rides the walk search's state. **Skate** (the
  perk) stays the cheap version: it never slides and ice costs it 1; with
  both, Skater's free hexes come first.
- **Flash Freeze:** an action, once a battle (gone from the menu once spent),
  range 3, a foe: **Frozen** (a status kept until thawed). It skips its next
  turn (the turn starts, the ground acts, then it ends); a boss (the Twins, the
  Colossus, a multi-hex unit) doesn't skip. It can't be displaced, it counts as
  glazed for Shatter (+15%), and its next landed hit is x2, which thaws it.
  Unhit, it thaws at the tick after its (skipped) turn. AI: the foe whose best
  basic hurts its side most (a boss at 0.6).
- **Glacier Wall:** your pillars last all battle (999 ticks, shown as ∞;
  still 4 per caster) until melted or broken. **Break Pillar** (a menu row
  while you hold it; the pillar has no HP, so this is the "basic"): your own
  pillar within your weapon's reach. Any of your skills whose shape covers one
  of your pillars raised before that action breaks it too. The break: 12% ice
  to everyone on the six neighbours, both teams, then a push of 1 away (onto
  ice they slide); the hex is left bare.

### 16.3 Water keystones (D295)

Code: `src/core/ks_water.gd` (BWKsWater); def `tidal_release`.

- **Tidal Release:** an action, cooldown 4. A pool hex within 3, then a
  heading (the second pick; the AI picks its own). The pool drains (every hex
  loses its water; an electrified field there ends). A wave runs from that hex
  along the heading, length = the pool's size (max 6), stopping at the edge or
  rock. Everyone on the line is pushed 3 along it, front first; blocked, a slam
  (8% both); onto glaze, a slide. The line then gets water 2. AI: a line that
  pushes 2+ foes and no friend.
- **Riptide:** at the holder's turn start, each foe in unglazed water 2-4 away
  is pulled 1 toward it, closest first (a field move).
- **Wellspring:** at the tick, you and allies standing in YOUR water heal 4%
  per level; light on the same hex counts first (only the excess heals).

### 16.4 Dark keystones (D296)

Code: `src/core/ks_dark.gd` (BWKsDark), through BWCurse's hooks.

- **Contagion:** a foe with Rot is KO'd: every foe within 2 of it gets +1 Rot
  (cap 3). One jump per KO.
- **Doom:** a foe reaching 3 Rot is **Doomed** (once per foe per battle). At
  the end of its next turn (a Frozen skip counts) it takes 15% + 5% per Rot of
  its max HP (dark) and each adjacent foe half that % of theirs; then its Rot
  clears. A unit doomed during its own turn waits for the next one.
- **Event Horizon:** your dark 3's gravity reaches 2; at the tick each foe
  within 2 of it (not on it) is pulled exactly 1 toward the nearest (gravity
  doesn't add its extra hex here); a foe on your dark 3 can't be healed.

### 16.5 Readability and polish (D297-D299)

`combat/keystone_view.gd` (BWKeystoneView): the Frozen unit in an inked ice
prism with a "FROZEN x2" tag; a thorn ring and "DOOM n" under a Doomed unit;
the gale 3 swirl; the Eye's reach ring. One-shots: the tidal wave crest
running the line, Wellspring droplets, Contagion jump arcs, the Doom blast,
ice shards on a thaw or a break. Unit tags (ROT /, FROZEN x2, DOOM n, RAGE IN
n) sit on the HP bar (`BWKeystoneView.bar_mark`), so they follow its clamp
below the turn order and its cull behind panels; Rot now reads "ROT /". The
ice pillar has an ink hull and heavier side edges. The Twins hover (0.3 m, a
slow bob) and glide (the Beings' motion, D220) over a faint shadow. Glossary:
Frozen, Doomed, Gale 3. Renders `design/art/v3_c3_*.png`
(`tools/keystones_c3_shots.gd`).

## 17. Squall and Overfreeze (D309-D314, the author's 2026-10-07 additions)

The author: "Elements overlapping identity is completely fine." Code:
`src/core/squall.gd` (BWSquall), `src/core/overfreeze.gd` (BWOverfreeze);
hooks marked D309/D312 in `BWTiles.apply`, `BWPools.finish`, `BWBattle`
(paint, _plan, _mods), `BWWind.tick`, `BWAI._best_skill`, readability. View:
`BWSquallView` (`src/game/combat/squall_view.gd`). Tests:
`tests/test_squall_overfreeze.gd`. Renders: `design/art/v3_squall_*.png`,
`v3_overfreeze_*.png` (`tools/squall_shots.gd`).

### 17.1 Wind: Squall (D309-D311)

- **Start:** a FRESH wind arrival on a hex holding light 2+ or dark 2+ (a
  wind cast that gales it, or a fresh light/dark arrival that fires a gale
  marker and leaves the hex at 2+). Owner: the caster; a firing gale's owner
  is the gale's. The gale copies its ring as ever; the front starts one ring
  past the copies (ring 2; ring 3/4 for a gale 2/3).
- **Advance:** at each of the next **3 ticks** (in `BWWind.tick`, after the
  vortex fields, before the beams and the decay) the front moves one ring
  out. Each hex of that ring gets a **propagated +1** of the squall's light
  or dark (source = owner; never fires a marker; skips glazed hexes, pillars,
  walls; seeds and statics follow §5.5/§5.6). The unit on each ring hex is
  **pushed 1 outward**, both teams, as a wind field move: the wind caps (2
  hexes a cycle, a field once a turn), dark 3 gravity, a slam (8%) when
  blocked, a slide on ice. Wind set holders' allies are spared.
- **Always outward (Claude, D310):** the caster's Gust heading doesn't bend
  it; a squall is an explosion and the push already goes "away".
- Light and dark only. **One squall per owner**; a new one replaces it. One
  action over several light hexes starts one, from the strongest.
- Interplay: more light means more beam hexes (the beams resolve right after
  the advance); dark spread under foes is the owner's dark (Rot at their turn
  end); a dark 3 squall's own ring-1 copies hold ring-2 foes by gravity.
- **Readability (D311):** the board draws a spinning three-arm swirl and an
  outward-drifting chevron on every hex the front reaches next (light: yellow
  over ink; dark: violet over a white hairline). The blast preview draws a
  starting squall's first front with "SQUALL: NEXT TICK" and "SQUALL (LIGHT)".
  Tile card: "Squall: advances next tick (...)". Forecast note "Squall: ...".
  Glossary: Squall. VFX: the origin flares; each advance sweeps chevrons out.

### 17.2 Ice: Overfreeze (D312, D313)

- A FRESH ice arrival on a hex that was **glazed water** before the action
  (water, glaze > 0, no marker, not a pillar) overfreezes and shatters:
  **12% ice** (Shattering's potency of the centre's glazer applies) to every
  unit on the hex and its six neighbours, both teams, **once per unit per
  action** however many centres reach it.
- Then the hex and its ring become a **radius-1 rink** as a propagated
  arrival: charged unglazed hexes glaze, empty ground gets a thin ice sheet
  (water 1, glazed); already-glazed, marked hexes, pillars and walls are left.
- **No pillar (Claude, D313):** it just shattered; even empty water 3 stays a
  flat rink. Ice on a pillar doesn't overfreeze (Glacier Wall and thunder
  break pillars).
- Once per hex per action; the rink is propagated, so nothing chains.
  Thunder on glazed water still detonates with the x1.5 shatter. Blizzard
  glazes directly and never overfreezes.
- **Readability:** forecast "Overfreeze: ..." (skills and ice basics), the
  blast preview hatches the seven hexes ice-blue with "OVERFREEZE 12%", the
  tile card names it on glazed water, glossary Overfreeze. VFX: a white burst
  ring with an ice-cyan core and white/cyan spikes, white shards flung out,
  the seven hexes flashing white with cyan rims.

### 17.3 AI (D314)

`BWAI._best_skill` simulates only when cheap pre-checks pass: an ice skill
over glazed water scores the bursts on foes minus 1.5x on allies
(`BWOverfreeze.ai_skill`); a cast that would start a squall scores the
front's three rings (dark under foes, light under allies, 3% max HP each,
+1 per foe on the first ring) from the simulated `squall` event
(`BWSquall.ai_skill`).

## 18. Wind shaping (D365-D370, the author's "then what?")

Wind as built, for **skills**. A wind-tagged skill no longer carries the
abstract Gust / Vortex / Becalm mode; once its target is picked, the confirm
box shows **WIND SHAPING**, whose options follow the skill's shape. Code:
`src/core/wind_shape.gd` (BWWindShape), hooked from `BWWind.pre_hit` /
`after_paint` and `BWBattle.use_skill`; view `combat/wind_shape_view.gd`
(BWWindShapeView). Tests `tests/test_wind_shape.gd`. Renders
`design/art/wind2_*.png` (`tools/wind_shape_shots.gd`).

| Shape | Skills | Options |
|---|---|---|
| Line | Ley Line, Tridentpierce, Energized Shot, Earthsplitter, Shockwave Palm, Lunge | **Part left**, **Part right**: the foes ON the line are pushed 1 to that side (the caster's left / right, looking down the line). **Blast out**: foes beside the line pushed 1 straight away from it (past an end: on along it), foes on it to the open side (left first). **Hold** |
| Area | every ground-aimed or leap skill (Surge, Tempest, Rain of Arrows, Arcing Shot, Saturate, Daggerleap, Dragoon Dive), self rings (Whirlwind Blade, Fan of Knives), the Cleave and Sweep arcs | **Draw in**: BEFORE the hits, foes in or beside the area pulled 1 toward its centre (so more are caught). **Burst out**: hit first, then the area's foes pushed 1 away from the centre. **Hold** |
| Single | everything aimed at one unit, and Charge | **Push**: after the hit, the target pushed 1 along a chosen heading. **Hold** |

- **Hold** (every shape, Claude) Becalms the foes the skill touches (the
  area, the line, the target): move 0 until the end of its next turn, then
  Restless.
- **Order:** Draw in is before the hits; everything else lands after the hits
  and the paint (hit, paint, pushes, slides, slams). Only foes are moved.
- **Unchanged rules:** every move goes through `BWWind.push`: once per action,
  2 hexes a cycle (D272), dark 3 gravity (D276), slides onto glaze (D261) and
  8% slams on both when a push is blocked by rock, a unit, a pillar or a wall.
  Pulls never slam.
- **Memory:** the last choice per unit and skill (`BWUnit.wind_shapes`, not
  saved). Unset, an area **draws in** (D383, the author: was Burst out under
  Gust); lines and single targets follow the unit's basic mode: Gust → Blast
  out / push straight away; Vortex → Blast out / pull straight in; Becalm →
  Hold on every shape.
- **Gales:** a gale the skill lays stores the equivalent mode: Draw in →
  Vortex field, Hold → Becalm field, the rest → Gust field (Part: heading to
  the parting side; Push: the push heading; else away from the caster).
- **Basic attacks and plain paints** keep the three modes (§1 of v3,
  `BWUnit.wind_mode`), on the forecast's "Wind mode (basic)" toggle.

**Controls** (no extra click; the shaping is set while the box is up, Enter
or a click on the target fires):

- Line: move the mouse to either side of the line, or press the arrow key
  that points at a side; Tab, the wheel and the other arrows cycle Blast out
  and Hold.
- Area: Tab, the wheel or any arrow cycle Draw in / Burst out / Hold.
- Single: move the mouse around the target to aim the push; ←/→ turn it;
  Tab or ↑/↓ toggle Hold; the wheel turns it.
- The mouse acts only when it moves into a new region (dead bands of 16 px
  round the line and 26 px round the target), so clicking the target again
  never flips the choice. While shaping, the arrows and the wheel don't move
  the camera.

**Preview:** fat wind-green arrows (ink-edged) on the line's side, the area's
rim (inward for Draw in, outward for Burst out) or the target; a tag naming
the option; a dashed ghost ring where each pushed foe lands; "SLAM 8%" on a
blocked push; "INTO FIRE n%" / SHOCK / DARK / GUST FIELD where a foe would
land in a hazard; plus the blast preview's ink move arrows, slide ghosts and
damage stickers (the action is simulated with the shaping).

**AI (D368):** at most 4 options per skill, each simulated once (single:
the three best push headings by a cheap slam / hazard look, then Hold);
score = damage to foes − damage to its side + hazards foes are left on + 3
per Becalm; ties keep the stored choice.

**Wind Wall (D370):** kept as is. A keystone action, one wall per unit, 3
hexes, 2 ticks, cooldown 3: not paintable, not spammable.
