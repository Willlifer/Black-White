# Expansion draft: big maps, new rooms, a mid-run boss

**Status: a draft for the author's review. Nothing here is built or ruled.**
The author approved the direction (bigger maps, Siege / Escort / Mirror /
Weather, a mid-run boss, more maps; no duel). All numbers are first passes
for the campaign sim. **NEW** marks engine work that doesn't exist yet.

The lens: **combo and kiting**. Each piece gives room to kite, ground to set
up on, or a reason to chain a detonation.

---

## 1. Big maps and squad size

### The class

- **Size:** 17×15 to 19×17 (about 230–300 cells; the Obelisks is 173).
- **Deploy 4v4.** Zones stay "3 rows at your own edge", up to 16 hexes.
- **First contact** as today: ranged on turn 2, melee on turn 3. Spawns sit
  12–16 apart, with free drops or fast lanes.
- **New checker rule** (from L-7's ravine archer): every perch needs a melee
  route of at most 2 turns.

### Squad: keep 6, bench 2 (recommended)

- Everyone levels every fight (D179, D194), so the bench never falls behind.
  It becomes a matchup choice.
- Every screen (pick 6, downtime, the hall) is sized for six.
- Recruits (D41) already grow the squad past 6. That stays the only way to
  grow.

### When big maps appear

- **Fights 5–7:** about half of the Hard rooms roll a big map (opt-in).
- **Fights 8–10:** every room is big, 4v4. The run widens after the boss
  (§3).
- **The Giant stays 3v1 on the arena** (see Q2).

### Engine

- **Camera:** a wider zoom, edge and drag pan, and a focus that follows the
  active unit. (M)
- **Turn order:** the D211 strip already shows 8 + 5 portraits.
- **Deploy UI:** a 4th pre-battle slot (D77's drag and drop handles any
  count), plus a per-map `deploy_count` field that the sims and `--combat`
  read. (M)
- **Enemies and performance:** `enemy_layout` already places 4. Prewarm-probe the tile FX at ~300 cells.

### Big map concepts

1. **Viaduct (19×15).** Two elevated decks over void, joined by three
   ladders. Each deck is a long sightline, with grass planks in the middle.
   Kite along one deck, drop to the other, and burn the planks behind you.
2. **Paddies (17×17).** Stepped terraces of seeded water 1–2, split by dry
   dykes. The floor conducts, so thunder is king. The dykes are fast lanes,
   and the paddies slow anyone who chases.
3. **Quarry (19×17).** A pit from elevation 0 to 6, with a spiral ramp and
   jagged blocks. The deep cut is seeded dark 2. Dropping in is free and
   climbing out is costly. The rim belongs to shooters, the cut to melee.
4. **Floe (17×15).** Static water 3 dotted with dry floes. Ice glazes a path
   across, and fire melts it behind you. Undertow makes the lake a magnet.
5. **Pass (19×15).** A central choke with two dark-seeded flank tunnels and
   grassy slopes. Hold the choke, or bait foes into the tunnels.
6. **Old Town (19×17).** Jagged houses and rooftops at elevation 3 reached by
   stairs, with a fountain plaza seeded light 2. The streets are sightlines
   and the alleys are flanks.

---

## 2. New Hard-room encounters

All take the D208 slot (a third of Hard rooms from fight 3, Hard pay, squad level).

### Siege: the Braziers

- **Setup:** 3 braziers on the enemy half, as neutral stone objects (like
  the obelisks), each in a ring of static fire 1.
- **Win:** break all 3. **Lose:** the squad is down.
- **Enemies:** 3 defenders. A downed defender comes back at the back edge
  2 cycles later, at 60% HP.
- **Why it's fun:** killing buys tempo; it isn't the goal. A breaking
  brazier blasts its ring like a fire 2 detonation, so you break the one
  next to the defenders.
- **Card:** "Break 3 braziers. Defenders return."
- **Engine:** reuses the D140 objective. **NEW:** respawns and waves, shared
  with Escort and Surrounded. (M)

### Escort: the Lamplighter

- **Setup:** a neutral walker (a hunched figure with a lantern on a pole)
  follows a fixed path, 2 hexes a cycle, to an exit. Each step paints
  light 1.
- **Win:** the walker reaches the exit. **Lose:** the walker or the squad is
  down.
- **Enemies:** 2 at the start, plus 2 ambushes from the flanks, each marked
  a cycle ahead. Daggers and bows.
- **The kiting rule:** the walker stops while a foe is adjacent, so you pull
  foes off it.
- **Card:** "Keep the lantern moving."
- **Engine:** the neutral team exists (D140). **NEW:** a path-following
  mover, waves, and an AI weight on the walker. (L)

### Mirror: the Negatives

- **Setup:** an AI copy of the units you deploy: same levels, gear, imbues,
  perks and picks. Wander's buffs don't carry over.
- **Win and lose:** a normal battle.
- **Look:** in negative, with black bodies and white ink. Hair keeps its
  element colour.
- **Fairness:** AI against AI is even, but the AI doesn't plan combos (L-7).
  **Start the copy at 85% HP** and let the sim tune it to the D212 band
  (about 60–65%). It's built after you deploy, and the card warns you, so
  choosing who to send is the puzzle.
- **Card:** "You face whoever you send."
- **Engine:** cloning is small. **NEW:** the negative material (small).
  (S–M)

### Weather: a modifier (recommended)

A tag on about 25% of rooms from fight 5 (never the Obelisks or a boss),
shown on the card; +1 drop on Hard. It multiplies what exists: a Horde in a
Gale is a new fight. It acts at the cycle tick.

| Weather | Each tick |
|---|---|
| **Rain** | Water +1 on every hex (cap water 1), and fire steps down one. Everything conducts. |
| **Ashfall** | Fire 2+ spreads to any neighbour except mud, not just grass. |
| **Eclipse** | Every hex is pulled toward dark 1, and light heals ×2. |
| **Blizzard** | 4 charged hexes glaze, each marked a cycle ahead. |
| **Gale** | Every unit is pushed 1 along a shown heading (D143 rules, with slams); the heading turns every 3 ticks. |

**Engine:** **NEW** `BWWeather`, a single tick hook (Gale reuses D143), plus
a HUD plate and ink-streak particles. (M)

### Claude's three

**The Hare.**
- **Setup:** one enemy with move 7 that never attacks, flees, and paints its
  element as it runs. 3 guards cut you off.
- **Win:** down the Hare. **Lose:** it reaches the exit 3 times, or the
  squad is down. Each escape respawns it, and its guards get +5%.
- **Why it's fun:** kiting inverted. Mud, glaze, Pinned, Undertow, Gust and
  Uppercut become trap tools.
- **Card:** "Catch the Hare. Slow it first."
- **Engine:** **NEW** flee AI. (M)

**Powder Kegs.**
- **Setup:** 6–8 neutral kegs in the centre. An elemental blow or a
  detonation touching one sets it off: a fire 3 blast and a radius-1 push.
  Either side can trigger them.
- **Enemies:** 3, at ×1.15 HP.
- **Why it's fun:** kite foes next to a keg, light it, then chain the next.
- **Card:** "Kegs blow on any element."
- **Engine:** reuses the obelisk object, push and detonation. **NEW:** the
  trigger. (S)

**Surrounded.**
- **Setup:** you deploy on a raised centre dais. 6 Horde-weight enemies
  arrive from every edge in two waves.
- **Why it's fun:** area combos at full value, and kiting in a circle.
- **Card:** "From every side."
- **Engine:** a centre deploy zone and the shared waves. (S once waves
  exist)

---

## 3. Mid-run boss

**Fight 7 is fixed and has no room choice. Two bosses; the run seed picks
one.**
- Fight 5 would follow the Obelisks back to back. Fight 7 spaces 4, 7, 11,
  and is the hinge where big maps take over.

### The Twins (Noon and Dusk)

> **Built (D255–D260, 2026-10-07).** Fight 7, fixed. The phase framework is
> `BWPhases` (src/core/phases.gd), the boss `BWTwins` (src/core/twins.gd),
> the look `BWTwinsLook`, the VFX and plate `BWTwinsFX`, the map
> `court.json`, the codex's Bosses tab, glossary Beam and Rage. Numbers as
> built: paint +2 on radius 1 (rage: radius 2); heal 2% per point of own
> colour (×2 after the swap); beam when more than 4 apart, 10% max HP +
> Blinded / Shrouded once per turn; thunder breaks it for a cycle and jolts
> both 5%; HP 2.2× their D137 HP, stats ×1.15 (sim-tuned, D259).

- **Look:** two tall figures (scale about 1.6, 1 hex each). Noon is white
  with a halo-ring head. Dusk is black with white contour and a hollow ring
  head (the Well's motif). They mirror each other's pose.
- **Map:** a round court, half seeded light and half seeded dark.
- **Phase 1:** each paints its colour 2 around itself. Whenever they stand
  more than 4 apart, a painted beam joins them, and you must cross it.
- **Phase 2** (either one under 50%): their colours swap, and each heals ×2
  from its own colour.
- **Phase 3:** if one falls, the other rages 2 cycles later (+1 move,
  double paint). Down both within 2 cycles of each other and the rage never
  comes.
- **Counter:** overwrite their ground with the opposite colour, thunder the
  beam, and burst both together.
- **Reward:** every squad unit gets one extra pick (two offers, D174).

### The Procession

- **Look:** a dragon dance: a white cloth over 5 bearers, with a big inked
  mask on the head. It's 5 hexes long and snakes.
- **Map:** big (Quarry or Old Town).
- **Phase 1** (5 bearers): it moves 5 as a snake, and its trail paints its
  element 1 (the element is rolled per run).
- **Phase 2** (3 bearers): it coils round a ring, trapping whoever is
  inside, and its trail rises to 2.
- **Phase 3** (the head alone): move 7. It kites you.
- **Damage:** each bearer has its own HP. Downing one shortens the line and
  costs it 1 move for a cycle. The head takes ×0.5 until 2 bearers are
  down.
- **Counter:** glaze its path, detonate the trail under it, and block its
  turns.
- **Reward:** a choice of two A-tier weapons.

**Engine:** **NEW** a phase framework (HP thresholds that swap rules),
shared by both. (M) Twins: link and rage rules. (M) Procession: **NEW**
segmented snake movement. (L) **Ship the Twins first.**

---

## 4. More standard maps (13×13)

- **Orchard:** rows of grass under jagged trees. Burn a row and it becomes
  a fire corridor.
- **Sluice:** a static water channel with dry lock gates. Thunder a gate
  while foes cross it.
- **Bell Tower:** one tower at elevation 6 with a spiral stair. The climber
  sees everything, and everyone sees the climber.
- **Salt Flats:** almost bare, with seeded light patches. A pure kiting
  test.
- **Mire:** mud with dry islands joined by seeded water. With ice and
  Skate, it's a rink.

---

## 5. Build order

S is about one session, M two or three, L four or more. Reserve a DECISIONS
range per lane.

| # | Item | Size | Needs |
|---|---|---|---|
| 1 | Weather (5 kinds, HUD, card tag) | M | — |
| 2 | Mirror | S–M | — |
| 3 | Powder Kegs | S | — |
| 4 | Deploy-N plumbing (count, 4th slot, sims) | M | — |
| 5 | Big-board camera | M | — |
| 6 | Viaduct and Paddies, plus the checker rule | M | 4, 5 |
| 7 | Waves and respawns | M | — |
| 8 | Siege, then Surrounded | M + S | 7 |
| 9 | Hare (flee AI) | M | — |
| 10 | Escort | L | 7 |
| 11 | Standard maps (5) | S each | — |
| 12 | Phase framework, then the Twins at fight 7 (**built**, D255–D260) | M + M | — |
| 13 | The other big maps (4) | M each | 6 |
| 14 | The Procession | L | 12 |
| 15 | Run wiring (big rooms 5–7, all big 8–10) and a sim pass | M | 6, 12 |

**Parallel lanes:** A 1-2-3-9 (no new maps, playable at once) · B 4+5 → 6 →
13 (4 is the one serial gate) · C 7 → 8 → 10 · D 12 → 14 · E 11 anywhere.
Item 15 closes. Run `campaign_sim` (ENC, SHADOW) after each item.

---

## 6. Open questions

1. **Squad 6 with a bench of 2, or grow to 8?** *Recommend keeping 6;*
   recruits stay the growth path.
2. **The Giant at 3v1 or 4v1?** *Recommend 3v1:* your best three, and the
   500 HP stays untouched.
3. **Is weather its own room or a tag?** *Recommend a tag* on about 25% of
   rooms from fight 5.
4. **One boss or two?** *Recommend one slot at fight 7 and two bosses
   picked by the seed;* the Twins first.
5. **Mirror HP?** *Recommend starting at 85%* and letting the sim set the
   final value.
6. **Round limits?** *Recommend none, as on the Obelisks.* Siege has its
   respawns, and the Hare's 3 escapes are its clock.
