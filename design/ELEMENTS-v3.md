# Elements v3: every element is a build

## Author rulings (2026-10-07): these OVERRIDE the draft below

**Wind**
- Becalm immunity lasts **2 turns**, not 1.
- Becalm fields need a **strong, unmistakable visual**: still ink rings and a calm-zone border. The author worried they'd be hard to identify.
- **Wind on every weapon:** any skill cast WITH wind applies the caster's mode to foes in or adjacent to its shape BEFORE the hit resolves. A wind Cleave pulls foes into the arc, then swings. A wind Surge pulls foes into the AoE, then fires. One mode application per skill, within the field caps.
- **Wind Wall** blocks movement and skills on both sides, but **basic attacks pierce it** (they shoot or strike through).

**Ice**
- Approved as drafted, with **no rink cap** beyond the pool rule below.
- **After a slide, the unit gets +1 move** (its walk ends, then it may move 1 more hex). That replaces the hard stop.

**Light**
- **Dawn Relay is REMOVED** (too strong).
- Keep beams, AoE and Empowered. Light's third keystone becomes a **"magnify"** enabler: abilities and elements cast by allies standing on your light are magnified (e.g. +1 radius on AoE shapes, or +1 charge step on paints). Design it with caps.
- Lean light toward buffing teammates.

**Water**
- **Pools:** fire → steam over the whole connected pool (up to 19). **Ice and thunder react only within radius 1 of the cast hex** (7 hexes), not the whole pool.
- Light and dark never travel through pools.
- **Electrified:** it can't be refreshed. Fire on a hex clears it, which is fine.
- **Lockdown fix:** each unit builds resistance the longer it stays in an electrified field. Full damage on the first turn-start, 25% on the next, then immune for the rest of that field.
- Thunder on water ALWAYS electrifies, even a 1-hex puddle.

**Fire:** approved as drafted.

**Dark:** Eclipse Step stealth, Shadow Clone, Unseen Blade, Long Night and the sword-dark build are all **REMOVED**. The Twins' enemy keystone list drops Shadow Clone. The author: "dark is honestly fine, add some facets of curse and void." So dark KEEPS its current rules (concealment −hit per level, drain at dark 3, Shrouded, perks) and adds:
- **Curse facet (base):** a foe that ends its turn on YOUR dark gains **Rot** (stacks up to 3, until the battle ends or it's cleansed by light). Each Rot makes it take **+5% damage from all sources**. Rot is shown as small ink marks on the unit card and over the unit. Light healing on the unit removes 1 Rot.
- **Void facet (base): gravity, NOT erasure.** The author: "void is gravity, not overwriting tiles." Dark never consumes or overwrites other elements' paint or markers; tiles behave as normal. Instead, **dark 3 has gravity:**
  - Foes moving voluntarily **out of** a dark 3 hex pay +1 move for that step. It's heavy to climb out of.
  - Pushes and pulls **toward** a dark 3 hex go 1 further, and pushes **away** from it go 1 shorter (within the existing displacement and field caps).
  - This applies to the dark's owner's foes only. Show it as a subtle inward ink swirl on dark 3.
- **Keystones (3):**
  - **Contagion:** when a foe with Rot is KO'd, its Rot jumps to every foe within 2 (+1 stack each, capped).
  - **Doom:** a foe reaching 3 Rot is Doomed. At the end of its next turn it takes a burst of 15% max HP plus 5% per Rot to itself and 50% of that to adjacent foes, then its Rot clears. Once per foe per battle.
  - **Event Horizon:** your dark 3 gravity reaches further. At the tick, foes within 2 of your dark 3 are pulled 1 toward it (this counts against the wind field cap), and a foe standing on your dark 3 can't be healed.
- **The build:** a curse setup for the whole team. Paint dark under the enemy line, let Rot stack, and everyone's hits (thunder blasts, fire eruptions, electrified pools) land harder. Doom finishes the job. It pairs with any weapon; staff-dark and pistol-dark (Reload into a dark round) are natural.
- **Perks** stay as in v3 §10 minus the stealth reference: Pall no longer mentions stealth; it Blinds foes on dark 2+.

**Thunder**
- Keep Static Blades and Daisy Chain.
- **Blast Rider:** keep the immunity to your own blasts and the launch (move 2), but REMOVE "the ring takes the full blast". Self-detonation splashes at the normal half, because two full rings is "win more".

**Keystones:** the rank ladder is approved (rank 3 keystone, rank 6 second keystone, max 2 per unit, 3rd and 4th perks at ranks 4 and 5).

**Twins:** Noon and Dusk should float (a hover idle and gliding movement).

---

**Status:** the ice/water spine (§2 slides and pillars, §4 pools, steam,
rinks and electrified water, with the rulings above; build order items 2-4)
is **BUILT**, D261-D268; its rules as built are `ELEMENTS.md` §14. Fire
(§5), light (§3, with the rulings) and thunder's keystones (§7) are **BUILT**,
D285-D292: `ELEMENTS.md` §15. §9 (the ladder, keystone cards, enemy
keystones; `data/keystones.csv`, `BWKeystones`) and §10 (the 28 perks, the
element sets) are **BUILT**, D277-D284 (`PICKS.md` §1-2, `EQUIPMENT.md` §0).
Wind modes and dark (§1, §6) are **BUILT**, D269-D276, and the wind, ice,
water and dark keystones D293-D300: `ELEMENTS.md` §16. The final pass
(D301-D308, 2026-10-07) added Blast Rider's **Self-detonate** free action,
the §10 riders (Sunpath's beam move, Static Field's ally guard, Gale Force's
mode, Wildfire's wild ring, the Water set's 25-hex pools) and re-tuned the
curve with everything on. **The whole overhaul is built**; the text below is
the draft it was built from (the rulings above and `ELEMENTS.md` win).

**Draft for the author's review.** It adds to
`ELEMENTS.md` (the charge grid, the tick, containment), which stays the
rulebook for everything not named here. It also replaces the "rank 3 grants
all" rule in `PICKS.md` and re-cuts `PASSIVES-v2.md` §2–3. Weather (built
separately) and the dropped Hard rooms are out of scope.

**NEW** marks engine work that doesn't exist yet. ⚠ marks a balance watch.

## 0. The principles

- **The problem:** the one real archetype is trap, kite, explode. Thunder's
  double-ring blast (Arcing) is the only rule-changer builds form around.
- **The fix:** each element gets a **base rule** that changes the board its
  own way, and three **keystones** (rule-breakers), one picked at rank 3.
- **The hit rule (author, revised):** modest hit and dodge effects are fine.
  Don't stack big evasion. Statuses that change options come first:
  stealth, Becalmed, frozen and Blinded all remove choices rather than
  rolling misses.
- **Containment holds.** Every new reaction is placed, not cast (§3.5 of
  ELEMENTS). Nothing a reaction makes can fire a marker or react again in
  the same action. Every displacement and every extra action has a cap.

### The new tick (once per cycle, in order)

1. Erupt phase (existing `tile_erupt`).
2. **Vortex fields pull** (§1). Closest first, as in D143.
3. **Light beams resolve** (§3).
4. Decay. Pillars, Wind Walls, steam and electrified pools count down here.
5. Grass spread.
6. Static phase.

At turn start: fire burn, **shock**, dark drain, then light heal (damage
first, as now).

---

## 1. Wind: crowd control

*Pull them together, stop them dead, or blow them apart.*

### Base rule: the three modes

Every wind action carries a **mode**, chosen on the forecast as a
three-way toggle. It's remembered per unit and defaults to Gust.

- **Gust:** push 1 away from the action's origin.
- **Vortex:** pull 1 toward the origin.
- **Becalm:** the target is **Becalmed**: move 0 until the end of its next
  turn. It can still act and can still be displaced. When it ends, the
  unit is *Restless* for 1 turn (immune to Becalmed, like Steadied).

**Direct hits.** A wind skill or spell applies the mode to each foe it hits
unresisted. The origin is the caster for single-target hits and the shape's
centre for areas.

**Gale tiles are fields.** A gale marker stores its mode, shown as an arrow,
a spiral or a ring:

- **Gust gale:** has a heading (chosen when laid; by default away from
  the caster). A unit that **enters** or **starts its turn** on it is pushed
  1 along the heading.
- **Vortex gale:** at the tick (step 2), every unit within 1 is pulled 1
  toward it, onto it if it's free.
- **Becalm gale:** a unit that enters it stops there. Its move ends, and
  it can still act.

**When a gale fires** (a fresh charge arrives), it copies the charge as now
(radius 1, or 2 for a gale 2), then applies its mode once to every unit in
the copy area. Gust blows them out 1, Vortex draws them in 1, Becalm
Becalms the foes in it.

**Spreading, extended.** Gale copies now also carry a tile's reaction
state: steam, electrified (§4) and rink glaze (1 cycle). Wind is how a
combo leaves its pool.

**Slams.** These are D143's rules: a push stopped by rock, a unit or a
pillar slams for 8%, both units. A push or pull onto glaze slides (§2).

### Loop caps

- A unit is moved by **wind fields at most once per turn** and **2 hexes
  per cycle** in total. Direct hits are capped at once per action.
- A unit moved by a field isn't moved by another field in the same step.
- Fields never move a unit during a displacement. They read only voluntary
  entry and turn start.
- A slide caused by wind uses the slide cap (6).

### Keystones

**Eye of the Vortex** (approved). Your Vortex gales pull **everyone within
2**, up to 2 hexes, toward the centre, both when they fire and at the tick.
Each unit stops at the first blocked hex, so there's no slam on an inward
pull. One of your Vortex gales acts per tick (the newest).

**Wind Wall** (approved). A new action, cooldown 3. Raise a line of 3
gale-wall hexes (empty hexes only) starting within 3 of you. It lasts 2
ticks. The wall blocks all movement and every ranged attack whose line
crosses it, both ways. Gales and copies can't land on it. Thunder on it
does nothing. You can have one wall at a time.

**Jetstream.** Wind on a gale 2 makes a **gale 3** (copies to radius 3).
Your copies last 2 cycles, and your Gust fields push 2. The field cap
(2 hexes per cycle) still applies.

**The build:** lance-wind. Skewer and Sweep apply the mode down a line:
Vortex a pair onto your fire, Becalm the runner, Gust them into a pillar.
Also bow-wind (Split Arrow with a mode on each arrow).

---

## 2. Ice: the architect

*It builds the map: rinks to slide on, pillars to hide behind, slides
that throw people into walls.*

### Base rule: glaze is slippery

**What slips:** a glazed hex (a charged hex with glaze above 0). Stasis
markers don't slip.

**Slide resolution** (**NEW** `slide_path`, pure, like `push_path`):

1. A unit **enters** a glazed hex by walking, or by being pushed or
   pulled. Entering costs normal move (1; glazed water carries no
   penalty).
2. It keeps going in the direction of its last step, one hex at a time,
   at no cost.
3. The slide continues while the next hex is glazed and free.
4. If the next hex is **non-ice and standable**, the unit slides onto it
   and stops.
5. If the next hex is **blocked** (rock, a unit, a pillar, a wall, or a
   rise of 1 or more up), it stops before it. If it slid at least 1 hex,
   that's a **slam**: 8% to it and to the unit it hit.
6. **Ledges:** sliding off a drop of any height carries on to the lower
   hex and stops there. There's no fall damage.
7. **Map edge or void:** it stops at the edge, with no slam. Nothing is
   ever slid off the map.
8. **Cap:** 6 slide hexes (`SLIDE_MAX`).

**A slide ends the unit's walk.** Any move left is lost. That's the trap.
A rink is a fast lane (6 hexes for 1 move) that you don't steer.

**Crossing damage applies** to glazed fire entered on a slide (frozen
fire is a grill), whatever started the slide.

**Allies and enemies** follow the same rules. Ground hurts everyone. Only
Skate and Skater exempt a unit.

**Order inside one action:** the hit, then the paint, then pushes, then
slides, then slams. Damage is summed per unit (§3.5).

### Base rule: ice pillars

- A **fresh glaze on an empty water 3 hex** makes an **ice pillar**. If
  the hex is occupied, the glaze is normal.
- A pillar is impassable. It **blocks line of sight** for ranged attacks
  and `los` skills (**NEW**: `has_los` reads dynamic blockers). It stops
  slides and pushes, and those slam.
- It lasts **3 ticks** (`PILLAR_TICKS`), then thaws to water 3. While it
  stands, the water's decay is frozen.
- **Fire** melts it to water 3.
- **Thunder** shatters it: a shatter detonation, which is 34% to an
  empty centre, so the ring takes **17%**. A pillar is a bomb.
- You can have at most **4 pillars per caster**. A fifth melts your oldest.

### Keystones

**Skater** (approved). You never slide unless you choose to. On a slide
line you choose where to stop. Ice hexes cost you 0 for the **first 4 each
turn**, then 1.

**Flash Freeze** (approved). A once-per-battle action, range 3, on a foe.
It's **Frozen**: it skips its next turn, can't be displaced except by a
slide, counts as standing on glaze (Shatter), and its **next hit taken is
×2**, which thaws it. Against a boss, it doesn't skip a turn but still
takes the ×2.

**Glacier Wall** (approved). Your pillars last all battle (still capped at
4), until melted or shattered. You can **target your own pillar** with a
basic or a skill to shatter it: **12%** to all six neighbours, both teams,
and a push of 1 away (onto ice, so they slide).

**The build:** axe-ice. Cleave glazes an arc, Charge shoves onto it, and
the foe slides into your pillar and slams. Hook pulls one off the rink.
Also staff-ice, which rinks a whole pool (§4).

---

## 3. Light: support and enabler

*It doesn't win the fight. It makes your best unit take its turn twice.*

### Base rule: beams

- **Forming:** two allies, each on light 1 or more, in a straight hex line
  with **at most 4 hexes** between them. Nothing blocks it: no rock,
  pillar or wall. Every hex between them is a **beam** hex.
- **Resolving at tick step 3:** foes on beam hexes take **4% + 2% × the
  lower endpoint's light** (6/8/10%, light-class ground damage). **Allies on
  beam hexes, and both endpoints, become Empowered:** +15% damage on their
  next attack, until the end of their next turn.
- **Limits:** one beam per pair. Each unit can be the endpoint of 2 beams,
  and a unit is Empowered once.
- **Telegraph:** a beam draws as a thin dashed yellow line as soon as it
  forms, so foes can see it and step out.

### Base rule: dawn

An ally **starting its turn on light 2 or more** takes 1 off its longest
skill cooldown, once per turn. Healing stays as it is, and so does light's
+7 hit per level against the occupant (the trade).

### Keystones

The draft names were Prism, Overflow and Revelation. Revelation's "foes on
light are exposed" becomes the Judgement perk (§8); the keystone slot goes
to the enabler.

**Dawn Relay.** Once per battle (per keystone holder), an ally ending its
turn on **your** light gets a **relay turn** straight away:

- move 2 and one action at **60% damage**;
- no once-per-battle skills;
- it doesn't tick cooldowns, statuses or tiles;
- it **can't trigger a Dawn Relay itself**.

Several Relay holders still give each ally **at most one relay per
battle**.

**Prism.** Your beams can **bend once** at a third ally on light, so a
beam has up to 2 segments. Allies on your beams also **heal 5%** at the
tick.

**Overflow.** Light healing beyond max HP becomes a **Ward of Light**: a
shield up to 15% of max HP that lasts until hit or 2 cycles. Empowered
allies of yours get +25% instead of +15%.

**The build:** bow-light. Stand back on light, pair with a melee ally on
light, and run the beam through the enemy line. Relay your dagger for a
second dive.

---

## 4. Water: the network

*Connected water is one body. Touch it anywhere and the whole pool answers.*

### Base rule: pools

- **A pool** is the set of water hexes (h below 0, **not glazed**) joined
  through the six neighbours. Seeded and static water count.
- **BFS:** start from the cast hex and expand by hex distance, ties by hex
  index. Stop at **19 hexes** (`POOL_MAX`, one radius-2 flower). The BFS
  touches at most 19 nodes and ~114 edges, so it's cheap even on a
  300-hex board. Cache pools per action and rebuild them each tick.
- **Only reactions travel.** Fire, ice and thunder cast **fresh** on a water
  hex react across the pool. Water, light, dark and wind stay on their own
  hex (wind still gales normally). Propagated arrivals never trigger a
  pool.

| Cast on water | The pool becomes |
|---|---|
| Fire | **Steam** |
| Ice | **Rink** |
| Thunder | **Electrified** |

**Steam (fire).**

- The cast hex steps down 1 as now. Every pool hex gets **steam** for 2
  ticks.
- Steam blocks line of sight through it. A unit in steam can be targeted
  by single-target attacks only from within 2.
- It deals no damage. D87's 8% steam on the ring stays a Striketwice
  reaction.

**Rink (ice).** Every pool hex glazes (2 cycles, so they're slippery).
Empty water 3 hexes become pillars, within the 4-pillar cap.

**Electrified (thunder).** The author's ruling: the pairing makes a
hazard deadlier than fire alone. Thunder cast on water, or a fuse that
water lands on, **no longer detonates water**. It electrifies the pool.

- **Shock:** 15% at the start of an occupant's turn, against fire 3's
  12%. It's thunder-class, so thunder resistance applies. It hits **both
  teams**.
- Each pool hex entered deals **5%**, at most once per walk.
- **Payoff:** everyone in the pool is **Conductive** (arcs 50%, as with
  fuses), and anyone shocked at turn start is **Staggered** (no skills).
  One thunder cast denies a lake, stuns whoever's in it and chains your
  hits.
- **Lasts 2 ticks.** Decay is frozen meanwhile. When it ends, the pool
  **discharges**: every hex steps down 1 water, and static hexes scar for
  1 tick (D115).
- **No stacking:** thunder on a live field does nothing. It can't be
  refreshed, and only one field per pool.
- **Glazed water still shatters** (detonation ×1.5). Ice comes first.

**Static and seeded.** A static pool re-forms as now, so it can be steamed,
rinked or electrified again after its scar. A seeded hex becomes ordinary
water once it reacts (D134).

**Kept:** the water move penalty, conduction on hits (+10% per level), and
the old +2%-per-level detonation term (it applies only to mixed tiles that
detonate through dark or light).

### Keystones

**Tidal Release** (approved). A new action, cooldown 4.

- Pick a pool hex within 3 and a heading. The pool **drains**: every hex
  of it loses its water.
- A wave runs along the line from that hex, **length = the pool's size,
  max 6**.
- Every unit on the line is **pushed 3** along it (slams; slides on ice).
- The line gets **water 2**.

**Riptide** (approved). At the start of your turn, every foe standing in
water **within 4** of you is pulled 1 toward you. This counts against the
wind field cap.

**Wellspring** (approved). You and allies standing in **your** water heal
**4% per level at the tick** (4/8/12%). This doesn't stack with light
healing on the same hex; the higher one counts.

**The build:** staff-water. Ley Line draws a river. One Channel of thunder
then electrifies it, or ice turns it into a rink. Riptide drags foes into
the pool before you shock it.

---

## 5. Fire: chain-burn

### Base rule: Overheat

- A **fresh** fire arrival on a hex that was **already fire 3** erupts.
- **Ring:** each of the six neighbours gets a **propagated 2-step fire**
  (through `route`).
  - Water 3 becomes water 1.
  - Fire 1 becomes fire 3, ready for the next Overheat.
  - Glazed hexes, marked hexes, pillars and walls are skipped.
- **Damage:** 6% to every unit on the ring, both teams.
- **Centre:** vents to fire 2, so a second eruption needs a recast.
- **Containment:** a hex erupts once per action. Propagated fire never
  erupts and never ignites grass.
- **Telegraph:** a fire 3 hex shows a pulsing rim, and the forecast says
  "Overheat: ring to fire 2, 6%".

### Keystones

**Conflagration.** Your eruptions **chain once**: a ring hex your
eruption raised to fire 3 erupts too, at depth 2 at most. Each hex erupts
once per action. ⚠ Burst damage is summed per unit.

**Trailblazer.** Every hex you **leave** on a walk gets fire 1, up to 4
per turn. You take no crossing damage. Your kiting lays a fuse line for
Overheat.

**Phoenix Heart.**

- Your own fire never damages you.
- Starting your turn on fire 3, you **heal** what it would have burned
  (12%).
- Once per battle, a KO blow on you while you stand on fire leaves you at
  1 HP and Overheats your hex.

**The build:** fists-fire. Palm Burst pours 2, Flurry tops it to 3, and the
next touch erupts. Phoenix Heart lets the brawler stand in it.

---

## 6. Dark: the unseen

### Base rule: Eclipse Step

- A unit on dark (any level) **can't be targeted by single-target attacks
  or skills from more than 2 hexes away**. Area shapes that cover its hex
  still hit, and so do arcs and ground. Both teams.
- **Revealed:** a unit on dark that attacks from more than 2 is revealed
  until its next turn starts. Snipers can't shoot from cover forever.
  Melee from dark stays hidden.
- Dark's −7 hit per level and the dark 3 drain stay.
- **Telegraph:** stealthed units draw as a dashed ink outline, and the
  range overlay greys targets that can't be reached.

### Keystones

**Shadow Clone** (approved). When you **leave a dark hex** on your walk, a
**decoy** stays on it (once every 3 turns).

- It looks like you to the foe, with one HP and no actions.
- **Foes' next single-target attack within 4 of it must go to the decoy
  if it can reach it.** The AI is taunted, and the player's targeting
  says "Decoy?" only on their own decoys.
- Hit, it pops, and its hex goes **dark 2**.
- It lasts until hit or 2 ticks.

**Unseen Blade.** An attack you make on a foe that **couldn't target you**
at the start of your turn counts as a **rear attack** whatever the
facing, with +15 crit.

**Long Night.** Allies **adjacent to you** count as standing on your dark
for Eclipse Step (no drain). You can still be revealed.

**The build:** sword-dark. Step through dark, strike from it, and stay
hidden. Clone baits the archer's shot.

---

## 7. Thunder: the trap and the bomber

### Base rule (kept)

Detonate, fuse, chain lightning, Spark, Shatter, and the Arcing double ring
all stay. Two changes:

- **Water now electrifies instead of exploding** (§4).
- Fuses on empty ground are the bomber's tool (below).

### Keystones

**Static Blades.** Each **basic hit** you land arms **your fuse** on the
target's hex, if the hex holds no charge. A foe on your fuse is conductive,
as now. A **backstab** (the rear three, D96) on a foe standing on your fuse
**detonates** it as a blade burst: **12%** to the occupant and 6% splash,
plus your thunder bonus. One burst per turn, and one Static Blade fuse per
foe.

**Blast Rider** (from the author's note on Static Field: the bomber).

- **Immune** to your own detonations' damage, blast and splash.
- **Self-detonation:** when a detonation you cause is **on your own hex**,
  the ring takes the **full** blast, not half. Then you're **launched**:
  move 2 after the action (replacing Bolt Step's +2; they don't stack).
- **Cap:** one self-detonation per turn. It spends the charge, and your
  own hex can't be re-armed by you until your next turn.

**Daisy Chain.** Once per turn, when your fuse detonates, **one other fuse
of yours within 3** detonates in the same action. An empty fuse blows at
the 5% base. Nothing chains further.

**The build:** dagger-thunder.

- **The bomber:** Daggerleap into the pack, stand on fuse plus fire, Channel
  your own hex, then Blast Rider launches you out.
- **The assassin:** Static Blades arms a fuse with every stab; circle to
  the back and pop it.

---

## 8. Cross-element combos

| Pair | Result |
|---|---|
| Thunder + water | **Electrified pool**: 15%/turn, conductive, Staggered |
| Fire + water | **Steam** over the pool: LOS block, close-range only |
| Ice + water | **Rink**, and water 3 makes **pillars** |
| Thunder + glaze or pillar | Shatter blast ×1.5 |
| Fire + glaze or pillar | Melts it |
| Fire + fire 3 | **Overheat** eruption |
| Thunder + fire | Detonation (as now) |
| Thunder + dark/light | Detonation (as now) |
| Wind + any charge | Gale copies the charge, mode applies |
| Wind + steam/shock/rink | **Carries** the state to the copies |
| Wind push + glaze | Slide, and a slam on stop |
| Wind + pillar or Wall | Push stops: slam |
| Light vs dark | Same axis, they cancel (as now) |
| Light beam + dark | Stealthed foes on a beam can be targeted |
| Water + fire 3 | Steps it down (no eruption) |

---

## 9. Keystones: earning and showing

- **Rank 3** in an element: pick **1 of 2** keystones drawn from its 3.
  The draw is D174's seeded draw, so a reload shows the same cards.
- **Rank 6** in the same element: pick the **second** from the 2 left
  (shows 2). **A unit holds at most 2 keystones**, across all elements.
- **This replaces "rank 3 grants all".** The perk ladder:
  - rank 1: perk pick;
  - rank 2: perk pick;
  - rank 3: keystone;
  - rank 4: third perk (the remaining 2);
  - rank 5: the fourth perk;
  - rank 6: second keystone.

  Builds now differ even within one element.
- **On screen:**
  - the pick card is gold-ruled, with "KEYSTONE" over the name;
  - the unit card puts a keystone sigil next to the element dot;
  - the hall and the codex list them;
  - keystone actions (Wind Wall, Flash Freeze, Tidal Release) get their
    own menu row.
- **Enemy keystones by stage:**
  - fights 1–3: none;
  - 4–6: one enemy per squad;
  - 7 (the Twins): Prism and Shadow Clone;
  - 8–10: every enemy has one;
  - the Giant: one per phase.

  The enemy card names them. AI takes the first card (D174).

---

## 10. The 4 perks, re-cut

Slots: mobility, guard, offence, control. PASSIVES-v2 is kept unless
noted.

**Water**

- **Waterwalking** (v2).
- **Tidal Guard** (v2: +15 glance per level).
- **Current Push**: +8% per level from water. Your hit on a foe in your
  pool pushes it 1 *along the pool*.
- **Undertow** (v2).

**Fire**

- **Heat Rush** (v2).
- **Ember Skin**.
- **Kindling** (v2).
- **Wildfire**: your eruption ring is also `wild` (seeds once).

**Ice**

- **Skate**: glaze costs 1, and you may stop on the first ice hex you
  enter.
- **Rime Armour**: v2, plus you and allies on your glaze take no slam
  damage.
- **Fault Lines**: Shatter ×2, and slams you cause +8%.
- **Frostbite**: v2, plus a foe that slams into your pillar is Pinned.

**Thunder**

- **Bolt Step** (v2).
- **Lightning Rod** (v2).
- **Overcharge** (v2).
- **Static Field**: v2, plus your fuses can't be set off by your allies'
  paint.

**Wind**

- **Tailwind** (v2, with Slipstream).
- **Eye of the Storm** (v2: immune to displacement, ranged can't crit you).
- **Gale Force**: after moving 4+, your next hit is +20% and applies your
  mode.
- **Crosswind** (new control): your wind slams deal 12%, and a slammed
  foe is Becalmed.

**Dark**

- **Shadowstep**: v2, now needs LOS.
- **Nightborn** (v2).
- **Ambush** (v2).
- **Pall**: a Blinded foe also loses its 2-hex sight on stealthed units.

**Light**

- **Sunpath**: v2, plus allies on your beam start next turn with +1
  move.
- **Sanctuary** (v2).
- **Judgement**: v2, absorbing Revelation. Foes on your light can't
  glance and **can't be stealthed**.
- **Glare** (v2).

### Element sets (2 / 3 pieces)

| Set | 2 pieces | 3 pieces |
|---|---|---|
| Fire | On fire +10% STR per level, free crossing | **Flashpoint** (v2) |
| Water | On water +10% DEX per level; your pools reach 25 | **Breakwater**: once a battle, a foe hitting you is swept 2 along the pool and Drenched |
| Ice | On glaze +20% DEF; pillars +1 tick | **Frost Ward** (v2) |
| Thunder | Detonations +10%; your shocks deal you half | **Stormfront** (v2) |
| Wind | +1 move; your fields and modes skip your allies | **Slipstream** (v2) |
| Dark | On dark +10% SPD per level, no drain | **Vanish** (v2) |
| Light | On light +10% WIL per level; Empowered +5% more | **Dawnward** (v2) |

The water 3-piece is renamed from Riptide (now a keystone).

---

## 11. AI and readability

### What the AI must understand

Simulate-and-score (`BWBattle.simulate`) catches most of this, provided
each rule goes through the same functions as play.

- **Slides:** `reachable()` must return slide end hexes, not the entry
  hex. Score entering a rink as "where I end up". Avoid slides that end
  next to a foe.
- **Electrified pools:** it must never end a turn in one, and should
  score walking a foe into one (pushes, Vortex, Riptide).
- **Pillars and walls:** LOS-aware targeting, and it should step behind
  them against archers.
- **Stealth:** filter targets by range 2. Move into range or use areas.
  Value the dark hexes it stands on.
- **Decoy:** obey the taunt. As the owner, place clones when a sniper
  threatens.
- **Beams:** form them as a pair (move to light, in line), and step off
  enemy beams.
- **Modes:** choose Vortex when the targets are near its own fire or water
  3, Gust when they're near rock or a pillar, and Becalm on the fastest
  foe. The ⚠ is AI cost: limit simulation to 3 mode × target combos.
- **Keystone actions:** Flash Freeze the highest-damage foe. Dawn Relay is
  automatic. Tidal Release when the line hits 2+.

### Readability

- **The blast preview** draws every consequence of the action:
  - push and pull arrows;
  - **slide ghosts**, ending in a slam burst with its %;
  - eruption rings;
  - the **whole pool** that will react (outline + icon);
  - beams that form or break.
- **Tile hover** gains lines:
  - "Rink: slide",
  - "Pillar: 2 ticks",
  - "Electrified: 15% + Staggered, 1 tick left",
  - "Steam: blocks sight",
  - "Vortex gale: pulls 1 at the tick",
  - "Beam: 8% to foes".
- **Board marks:**
  - electrified pools get an outline that crackles (purple), with timer
    pips;
  - pillars get a tick count;
  - Gust fields get heading arrows, Vortex a spiral, Becalm a still ring;
  - the Wind Wall is a vertical sheet.
- **The tick preview** (hold Tab): the arrows of the coming Vortex pulls
  and beam hits.
- **The glossary** gets the new terms: Slide, Pillar, Pool, Steam,
  Electrified, Overheat, Beam, Empowered, Becalmed, Frozen, Stealth,
  Decoy, Keystone.

---

## 12. Build order

| # | Item | Size | NEW? |
|---|---|---|---|
| 1 | Keystone picks, ladder, cards, enemy grants | M | |
| 2 | Pool BFS + Electrified + Steam + Rink | M | **NEW** pool cache, field timers |
| 3 | Slide resolution + slams + reachable | M | **NEW** `slide_path` |
| 4 | Pillars + dynamic LOS blockers | M | **NEW** blockers in `has_los` and basic ranged |
| 5 | Overheat + fire keystones | S | |
| 6 | Wind modes, fields, caps, Wind Wall | L | **NEW** field step, mode toggle |
| 7 | Stealth targeting + Revealed | S | **NEW** target filter |
| 8 | Beams + Empowered + Dawn Relay | M | **NEW** beam step, relay turn |
| 9 | Decoys (Shadow Clone) | M | **NEW** decoy object, AI taunt |
| 10 | Thunder keystones | S | |
| 11 | Perk re-cut + sets data | S | |
| 12 | AI pass, previews, glossary, `campaign_sim` | M | |

- Items 2–4 are the ice/water spine; do them first. 3 needs 2 for rinks,
  and 4 needs 3 for slams into pillars.
- Wind (6) reuses D143 and the slide.
- Tests:
  - a 19-hex cap;
  - "an electrified pool never refreshes";
  - "a slide terminates at 6";
  - "fields move a unit at most 2 per cycle";
  - "an Overheat chain never passes depth 2";
  - "a relay can't relay".

---

## 13. ⚠ Balance watch

- **Electrified + Riptide or Vortex:** 15% and a stagger every turn is a
  lockdown. Watch the discharge timing.
- **Rink from one Channel:** 19 slippery hexes from one action. If it's
  too strong, cap rinks to the 7 nearest hexes.
- **Dawn Relay** is action economy. 60% and once per battle per ally
  should hold. Watch Relay + Empowered + Assassinate.
- **Blast Rider + Arcing:** two full rings with no self-cost. One per turn
  is the cap.
- **Stealth vs the bow:** archers may feel blanked by dark maps. Area
  shots and light are the answers.
- **Conflagration on grass maps:** eruption plus grass spread plus
  Wildfire.
- **Flash Freeze ×2** on a crit Assassinate is roughly a 5× blow.

## 14. Open questions

1. **Second keystone at rank 6, or never?** *Rec: rank 6, max 2 per unit.*
   Two keystones from different elements is where the wild builds live.
2. **Do light and dark travel through pools?** *Rec: no, only reactions.*
   Otherwise one Channel paints 19 hexes.
3. **Is a slide a full stop of the walk?** *Rec: yes.* It's the trap, and
   Skate and Skater exist to lift it.
4. **Wind Wall: block both sides, or only foes?** *Rec: both.* It's
   terrain, and a once-per-3 wall that let your side through would be too
   strong.
5. **Thunder on water: always electrify, or detonate a lone 1-hex pool?**
   *Rec: always electrify*, for one clear rule.
6. **The rank ladder past 3 (third and fourth perks at ranks 4 and 5)
   slows getting all perks.** *Rec: accept it.* Not owning everything is
   what makes builds.
