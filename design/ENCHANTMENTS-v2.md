# Enchantments v2

**Current spec** (D196–D205). The data is `game/data/enchantments.csv`
(139 rows: the 64 originals, retuned, plus 75 new ones); the battle side is
`src/core/enchant_v2.gd` (`BWEnchant`) plus `src/core/effects.gd`. The draft
this replaced was reviewed by the author on 2026-10-06; his calls are folded
in, and the rows he cut are gone (Quickened, Plunder, Trophy, Vampiric,
Bloodletter, Stitchwork). `EQUIPMENT.md` covers items, the original keys and
the shop; this page covers what v2 added.

**Shorthand.** Slots: **W** weapon, **H** head, **C** chest, **L** legs.
Tiers are E–A.

## 0. The data

`enchantments.csv` columns beyond the originals (SCHEMA.md):

| Column | Meaning |
|---|---|
| `tier` | E–A. The lowest tier the row can drop at (§3). |
| `family` | `elemental`, `weapon` (the originals), `on_kill`, `recovery`, `rng`, `momentum`, `defensive`, `cursed`, `team`. Docs and tools only. |
| `cursed` | 1 = a cursed row (§2 G): it shows the curse mark and its cost. |
| `cost_text` | The cost, spelled out on the item card under the passive. |
| `also` | Extra records on the same row: `key(a=1;b=2) \| key(...)`. Hollow and Leaden add a `damage_taken_mod`. |
| `drawback` | The cost's params, as one `drawback` record. |

Slot letters are expanded to every base of that slot in `applies_to`, so the
roll code reads rows exactly as before. A row's element (the colour) is the
`element` column; element rows sleep until the element is learned, except
`damage_taken_mod`, `immune` and `drawback`.

### The four new keys

They make every v2 row data. All four are served by `BWEnchant`, called from
the battle at the lines marked `v2 hook:`.

- **`on_event`**: `on` × `do`.
  - `on`: `kill`, `ally_kill`, `ally_ko`, `ally_low` (an ally crosses `threshold`% HP), `dealt` (your direct hit), `hit` (your basic attack lands), `glanced` (a glance on you), `struck` (a hit on you), `avoided` (you avoid), `detonate` (your blast hurts foes), `chain` (your arc), `glaze` (your glaze), `gale` (your gale), `turn_start`, `turn_end`, `ally_turn_start`, `healed`.
  - `do`: `action` (one more attack), `move`, `heal`, `blast`, `paint`, `empower` (damage / crit / can't be avoided on a later attack or turn), `status`, `reflect`, `step` (1 hex away), `guard`, `shield` (the next hit −pct%), `assist` (an ally strikes too).
  - Common params: `target` (self, `allies`, `nearest_ally`, `lowest_ally`), `radius`, `pct` (of max HP), `pct_of` (of an amount), `hexes`, `per_turn`, `once`, `melee_only`, `threshold`, `uses` (`next_attack`, `turn`).
- **`pity`**: `kind` = `miss` (Steady Hand), `glance` (Follow-Through, `mult`), `crit` (Building Pressure, `per`, `cap`), `resist` (Advantage, `side` att/def, `cd`), `graze` (`pct`), `reroll` (Second Chance, once a battle).
- **`drawback`**: the cost of a cursed row: `hp_cost`, `status`, `no_heal`, `no_light_heal`, `taken_pct`, `move`, `no_glance`, `fire_taken_pct`, `conductive`, `inherent` (the cost is in the row's own numbers).
- **`swap`**: `mode=move` (Bodyguard: an ally within `radius` is a move target for `cost`, and you trade places) or `on=ally_low` (Lifeline: you trade places with an ally who drops below `threshold`%).

New params on old keys: `stand_on_bonus` `pct_per_point` / `pct` (§1);
`attack_mod` `crit_per_height`, `rear_pct`, `alone_dmg_pct`, `alone_avoid`,
`still_pct`, `vs_charged_per_level` + `charged_cap`, `per_hex_on` +
`per_hex_on_pct` + `on_max`, `dmg_per_missing10`, `nocrit_pct`; `aura_mod`
`avoid_per_hex_moved` + `avoid_cap`, `taken_pct`, `self_if_ally`;
`damage_taken_mod` `source=any`, `below_hp`, `per_adjacent_ally` + `max_pct`,
`cap_pct` + `excess`, `cover_pct`; `immune` `what=status|ko` with `once`;
`trigger_stat` `dmg_pct` + `cap_pct`; `element_damage_pct` `per_level`,
`chain_pct`; `guard` `when=avoided;until=next_hit`; `lay_on` `trigger=miss`,
`element=attuned`; `stand_on_mod` `own`, stages `def_ignore` and `crit_mult`;
`hit_status` `on=any`, `basic`; `move_cost` `once` (Waterwalking, D204).

### Readouts

Every number that changes a blow is a labelled forecast line ("Flanking
Sword (from behind): +20%", "Second Opinion: advantage …"). Everything that
fires outside a forecast emits an `enchant` event `{unit, name, text}`: the
combat screen floats the text over the unit and writes a feed line.

---

## 1. Scaling (D196)

Late game the best stat is about 34 and HP runs 105–600, so flat stat rows
faded. Now:

| Row | Before | Now |
|---|---|---|
| Sunlit / Blazing / Riptide / Shrouded | +1 WIL / STR / DEX / SPD per charge point | **+10% of the stat per point**, at least +1 per point |
| Rimed | +2 DEF on a glaze | **+20% DEF**, at least +2 |
| Geyser | 1% max HP per water point | **2%** |
| Fireproof, Grounded, Windbreak, Nightforged | 15% or 25% less | **20%** each |

The % reads the stat from base + gear + battle stacks (never other
situational bonuses, so nothing loops). The floor is the old flat value, so
nothing got weaker in fights 1–3.

Kept flat, deliberately: the step rows (Kindled, Abyssal, Dawning, Welling,
Tidal), the duration rows, the hex rows, Whistling, Quickdraw, Pummeling,
Keen. The reactive/aura *abilities* (Brace, Enrage, Crowd Pleaser, Guardian,
Grace) are still flat; the same `pct` param would fix them later.

---

## 2. The families

Notes on the author's calls:

- **Relentless** is one extra **attack** (no move, no skill), once per turn per unit (D197).
- **Sapping** heals 10%, **Leeching** 15% (D197).
- **Second Opinion and Stubborn are Advantage** (D198): the resist is rolled twice and the holder's side keeps the better, then 3 of the holder's turns to recharge. The forecast shows the effective chance (attacker: r², defender: 1 − (1 − r)²). If both sides hold it, it cancels. It's spent only on a blow that reached the resist roll.
- **Cursed rows** drop at the same weight as everything else (D201). Each shows a curse mark (†) on its tile, after its name and on the card's kind line, and the card spells out the cost under the passive.
- **Pursuit** is legs-only and **Feast** chest-only: the draft starts weapon on-kill and recovery rows at C, and these are D rows.
- **Element rows** (Wake, Hearthbound) exist for the four axis elements; the colour follows the row.

The tables below are generated from the CSV.

### A. On kill

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Relentless** (`relentless`) | B | W | — | A KO lets you attack once more this turn (an attack only, no move). Once per turn. | `on_event` on=kill; do=action; per_turn=1 |
| **… of Pursuit** (`pursuit`) | D | L | — | A KO lets you move 2 more this turn. | `on_event` on=kill; do=move; hexes=2 |
| **… of the Death Knell** (`death_knell`) | C | W/C | — | A KO bursts the victim's hex: foes within 1 take 10% of their max HP. A burst KO never sets off on-kill effects. | `on_event` on=kill; do=blast; pct=10; radius=1 |
| **… of Ash** (`wake_fire`) | C | H/C/L | fire | A KO lays 1 fire step on the victim's hex and the ring around it, as spread (it never fires a marker and skips glazes). | `on_event` on=kill; do=paint; step=1; radius=1 |
| **… of Brine** (`wake_water`) | C | H/C/L | water | A KO lays 1 water step on the victim's hex and the ring around it, as spread (it never fires a marker and skips glazes). | `on_event` on=kill; do=paint; step=1; radius=1 |
| **… of Dusk** (`wake_dark`) | C | H/C/L | dark | A KO lays 1 dark step on the victim's hex and the ring around it, as spread (it never fires a marker and skips glazes). | `on_event` on=kill; do=paint; step=1; radius=1 |
| **… of Dawn** (`wake_light`) | C | H/C/L | light | A KO lays 1 light step on the victim's hex and the ring around it, as spread (it never fires a marker and skips glazes). | `on_event` on=kill; do=paint; step=1; radius=1 |
| **Feasting** (`feast`) | D | C | — | A KO heals you 15% of your max HP. | `on_event` on=kill; do=heal; pct=15 |
| **Rallying** (`rallying`) | C | H/C | — | A KO gives allies within 2 +10% damage on their next turn. | `on_event` on=kill; do=empower; target=allies; radius=2; dmg_pct=10; uses=turn |

### B. Recovery

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Leeching** (`leeching`) | C | W | — | Heal 15% of the damage your direct hits deal (never tiles, arcs or bursts). | `on_event` on=dealt; do=heal; pct_of=15 |
| **Hearthbound** (`hearth_fire`) | E | H/C/L | fire | Start your turn on fire you laid: heal 3% of your max HP per fire level. | `on_event` on=turn_start; do=heal; pct=3; per_level=1; own=1 |
| **Hearthbound** (`hearth_water`) | E | H/C/L | water | Start your turn on water you laid: heal 3% of your max HP per water level. | `on_event` on=turn_start; do=heal; pct=3; per_level=1; own=1 |
| **Hearthbound** (`hearth_dark`) | E | H/C/L | dark | Start your turn on dark you laid: heal 3% of your max HP per dark level. | `on_event` on=turn_start; do=heal; pct=3; per_level=1; own=1 |
| **Hearthbound** (`hearth_light`) | E | H/C/L | light | Start your turn on light you laid: heal 3% of your max HP per light level. | `on_event` on=turn_start; do=heal; pct=3; per_level=1; own=1 |
| **Parrying** (`parry_shield`) | D | H/C/L | — | Avoid an attack and the next hit on you deals 30% less. | `guard` pct=30; when=avoided; until=next_hit |
| **… of Second Breath** (`second_breath`) | E | C/L | — | A glance against you heals you 4% of your max HP. | `on_event` on=glanced; do=heal; pct=4 |
| **Sapping** (`sapping`) | C | H/C | thunder | Heal 10% of the blast damage your detonations deal to foes. | `on_event` on=detonate; do=heal; pct_of=10 |
| **Mend-Linked** (`mend_link`) | B | C | — | Any heal you receive also heals the most-hurt ally within 2 for half as much. The echo never echoes. | `on_event` on=healed; do=heal; target=lowest_ally; radius=2; share=50 |

### C. RNG forgiveness

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Steady** (`steady_hand`) | D | W/H | — | After an action of yours misses completely, your next attack can't be avoided. | `pity` kind=miss |
| **… of Follow-Through** (`follow_through`) | C | W | — | After one of your hits glances, your next strike deals x2. That strike can't crit. | `pity` kind=glance; mult=2 |
| **Pressing** (`building_pressure`) | D | W/H | — | +8 crit for each of your hits that doesn't crit, up to +40. A crit resets it. | `pity` kind=crit; per=8; cap=40 |
| **… of Second Opinion** (`second_opinion`) | C | W/H | — | Advantage: when a foe rolls to resist your element, it rolls twice and you keep the better roll. Then 3 turns to recharge. | `pity` kind=resist; side=att; cd=3 |
| **Stubborn** (`stubborn`) | C | C/L | — | Advantage: when you roll to resist an element, roll twice and keep the better roll. Then 3 turns to recharge. | `pity` kind=resist; side=def; cd=3 |
| **Rerouted** (`rerouted`) | E | W | — | A missed attack still lays 1 step of your attuned element on the target's hex. | `lay_on` trigger=miss; where=target; step=1; chance=100; element=attuned |
| **Grazing** (`graze`) | D | W | — | A missed basic attack still deals 25% of its damage. | `pity` kind=graze; pct=25 |
| **… of Second Chance** (`second_chance`) | E | H | — | Once per battle, your first miss is re-rolled. | `pity` kind=reroll; once=1 |

### D. Momentum and positioning

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Stampeding** (`stampede`) | E | L | — | +5% damage for each hex moved this turn before attacking, up to +20%. | `attack_mod` dmg_per_hex_moved_pct=5; max_pct=20 |
| **Kiting** (`kiting`) | D | L | — | +5 avoid for each hex you moved this turn, up to +20, until your next turn. | `aura_mod` avoid_per_hex_moved=5; avoid_cap=20 |
| **… of the High Ground** (`high_ground`) | D | H | — | +8% damage and +8 crit for each level you stand above your target. | `attack_mod` dmg_per_height_pct=8; crit_per_height=8 |
| **Flanking** (`flanker`) | C | W/H | — | +20% damage on rear and rear-flank blows. | `attack_mod` rear_pct=20 |
| **Shieldwall** (`shieldwall`) | D | C | — | Take 5% less damage for each adjacent ally, up to 15%. | `damage_taken_mod` per_adjacent_ally=-5; max_pct=15 |
| **Lone Wolf** (`lone_wolf`) | C | H/L | — | With no ally within 2: +15% damage and +10 avoid. | `attack_mod` alone_dmg_pct=15; alone_avoid=10 |
| **Planted** (`planted`) | D | L | — | If you didn't move this turn: +20% damage, and you can't be displaced until your next turn. | `attack_mod` still_pct=20 |
| **Disengaging** (`disengage`) | C | L | — | Once per enemy turn, when an adjacent foe hits you, step 1 hex away. | `on_event` on=struck; do=step; hexes=1; melee_only=1; per_turn=1 |

### E. Element interplay

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Resonant** (`resonance`) | C | W | — | +4% damage per charge level on the target's hex, of any element (up to +24%). | `attack_mod` vs_charged_per_level=4; charged_cap=24 |
| **Overloading** (`overload`) | C | H/C | thunder | Your detonations deal +5% for each charge point they blow. | `element_damage_pct` per_level=5 |
| **Conductor's** (`conductor`) | B | C | thunder | Chain arcs you cause heal you 50% of the arc. | `on_event` on=chain; do=heal; pct_of=50 |
| **Cold Snap** (`cold_snap`) | C | H/L | ice | Glazing a foe's hex Pins it. | `on_event` on=glaze; do=status; status=pinned |
| **Permafrost** (`permafrost`) | C | C/L | ice | You and your allies standing on your glaze take 10% less damage. | `stand_on_mod` on=ice; side=def; stage=dmg; per_point=-10; team=1; own=1 |
| **Windrider** (`windrider`) | C | C/L | wind | Allies (you too) under your gale copies get +1 move on their next turn. | `on_event` on=gale; do=move; hexes=1; target=allies |
| **Forged** (`forge`) | D | H/C/L | fire | Standing on fire, your attacks ignore 5% of the target's defense per fire level. | `stand_on_mod` on=fire; side=att; stage=def_ignore; per_point=5 |
| **Tidewalker** (`tidewalker`) | D | L | water | +5% damage for each water hex you entered this turn, up to +20%. | `attack_mod` per_hex_on=water; per_hex_on_pct=5; on_max=20 |
| **Nightfall** (`nightfall`) | C | H | dark | Attacking from dark adds +0.1 to your crit multiplier per dark level. | `stand_on_mod` on=dark; side=att; stage=crit_mult; per_point=0.1 |
| **Beacon** (`beacon`) | C | C | light | Allies (you too) who start their turn on light you laid get +5 crit per light level that turn. | `on_event` on=ally_turn_start; do=empower; on_tile=light; own=1; crit=5; per_level=1; uses=turn |

### F. Defensive and reactive

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Last Stand** (`last_stand`) | C | C/L | — | Below 30% HP, take 25% less damage. | `damage_taken_mod` source=any; below_hp=30; pct=-25 |
| **Vengeful** (`vengeance`) | C | H | — | When an ally is knocked out, your next attack deals +50% and can't be avoided. | `on_event` on=ally_ko; do=empower; dmg_pct=50; sure=1; uses=next_attack |
| **Thorned** (`thorned`) | D | C | — | A foe that hits you in melee takes 20% of the damage it dealt. | `on_event` on=struck; do=reflect; pct_of=20; melee_only=1 |
| **Unshaken** (`unshaken`) | D | H | — | The first status laid on you each battle is ignored. | `immune` what=status; once=1 |
| **Bulwark** (`bulwark`) | B | C | — | A single hit above 20% of your max HP deals only half of the excess. | `damage_taken_mod` cap_pct=20; excess=50 |
| **Undying** (`undying`) | A | C | — | Once per battle, a blow that would knock you out leaves you at 1 HP. | `immune` what=ko; once=1 |
| **Furious** (`fury`) | E | L | — | Each time you're hurt, +4% damage for the rest of the battle, up to +20%. | `trigger_stat` trigger=damaged; dmg_pct=4; cap_pct=20 |
| **… of the Evasive Roll** (`evasive_roll`) | C | L | — | Once per enemy turn, after you avoid an attack, step 1 hex away. | `on_event` on=avoided; do=step; hexes=1; per_turn=1 |

### G. Cursed (risk and reward)

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Bloodpact** (`bloodpact`) | B | W | — | +25% damage. **Cost:** Every action costs 4% of your max HP (never below 1 HP). | `attack_mod` dmg_pct=25 + `drawback` hp_cost=4 |
| **Glass** (`glass`) | B | H | — | +20 crit, and your crits deal x2. **Cost:** You're always Scorched: attacks on you deal +10%. | `attack_mod` crit=20; crit_mult=0.5 + `drawback` status=scorched |
| **Forsaken** (`forsaken`) | B | W/L | — | +5% damage for every 10% of your HP missing. **Cost:** Light can't heal you. | `attack_mod` dmg_per_missing10=5 + `drawback` no_light_heal=1 |
| **Hollow** (`hollow`) | A | C | — | +15% damage and 15% less damage taken. **Cost:** Nothing can heal you. | `attack_mod` dmg_pct=15 + `damage_taken_mod(source=any;pct=-15)` + `drawback` no_heal=1 |
| **Gambler's** (`gamblers`) | B | W | — | Your crits deal x2.5. **Cost:** Your hits that don't crit deal 85%. | `attack_mod` crit_mult=1.0; nocrit_pct=85 + `drawback` inherent=1 |
| **Leaden** (`leaden`) | B | L | — | +30% damage and 20% less damage taken. **Cost:** -2 move. | `attack_mod` dmg_pct=30 + `damage_taken_mod(source=any;pct=-20)` + `drawback` move=-2 |
| **Pyre** (`pyre`) | B | H/C/L | fire | Your fire tiles are 50% stronger. **Cost:** You take 50% more damage from fire tiles (Ember Skin's halving still applies). | `tile_potency_pct` pct=50 + `drawback` fire_taken_pct=50 |
| **Lightning-Touched** (`lightning_touched`) | A | C | thunder | Chain arcs you cause deal 100% instead of 50%. **Cost:** You're always conductive: damage you take arcs 50% to your nearest ally. | `element_damage_pct` pct=0; chain_pct=100 + `drawback` conductive=1 |
| **Reckless** (`reckless`) | B | H | — | Weapon skills recover 1 turn faster. **Cost:** You can't glance. | `skill_cd_minus` amount=1; once_per_battle=0 + `drawback` no_glance=1 |
| **Martyr's** (`martyrs`) | B | C | — | Allies within 2 take 15% less damage. **Cost:** You take 15% more damage. | `aura_mod` radius=2; allies=1; taken_pct=-15 + `drawback` taken_pct=15 |

### H. Team and support

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Banner** (`banner`) | C | H | — | Allies within 2 deal +8% damage. | `aura_mod` radius=2; allies=1; dmg_pct=8 |
| **Bodyguard's** (`bodyguard`) | C | L | — | Once per turn, your move can be a swap: trade places with an ally within 2 for 1 move. | `swap` mode=move; radius=2; cost=1 |
| **Tag Team** (`tag_team`) | B | H | — | When an ally within 2 scores a KO, you get +2 move on your next turn. | `on_event` on=ally_kill; do=move; hexes=2; radius=2; next=1 |
| **Covering** (`covering`) | D | C | — | You take 25% of the damage aimed at an adjacent ally. | `damage_taken_mod` cover_pct=25; radius=1 |
| **Inspiring** (`inspiring`) | C | H/C | — | Your KOs heal allies within 2 for 8% of their max HP. | `on_event` on=kill; do=heal; target=allies; radius=2; pct=8 |
| **Spotter's** (`spotter`) | D | W/H | — | A foe your basic attack hits is Scorched (attacks on it deal +10%). | `hit_status` on=any; min=0; basic=1; status=scorched |
| **… of the Rally Cry** (`rally_cry`) | C | C | — | Once per ally per battle, an ally dropping below 35% HP gets a 25% guard until its next turn. | `on_event` on=ally_low; do=guard; pct=25; threshold=35; radius=99 |
| **Relay** (`relay`) | D | L | — | When you avoid an attack, your nearest ally gets +10 crit on its next attack. | `on_event` on=avoided; do=empower; target=nearest_ally; crit=10; uses=next_attack |
| **Tending** (`tending`) | C | C | — | End your turn: allies next to you heal 4% of their max HP. | `on_event` on=turn_end; do=heal; target=allies; radius=1; pct=4 |
| **Sheltering** (`sheltering`) | C | H | — | Start your turn: the most-hurt ally within 2 is Sheltered: the next hit on it deals 30% less. | `on_event` on=turn_start; do=shield; target=lowest_ally; radius=2; pct=30 |
| **… of the Pincer** (`pincer`) | B | W | — | Once per turn, when your basic attack hits, an ally next to that foe strikes it too for 50%. | `on_event` on=hit; do=assist; share=50; per_turn=1 |
| **Lockstep** (`lockstep`) | D | L | — | While an ally stands next to you, you both deal +10% damage. | `aura_mod` radius=1; allies=1; dmg_pct=10; self_if_ally=1 |
| **Lifeline** (`lifeline`) | B | C | — | Once per battle, when an ally within 3 drops below 25% HP, you trade places with it. | `swap` on=ally_low; threshold=25; radius=3; once=1 |

### The new team rows (D202, Claude)

Tending, Sheltering, Pincer, Lockstep and Lifeline (in table H) are new,
built on the hooks above:

- **Tending** (`on=turn_end;do=heal`): end your turn, allies beside you heal 4%. A slow aura that rewards holding a line.
- **Sheltering** (`on=turn_start;do=shield`): the most-hurt ally within 2 gets a Frost-Ward-style shelter: its next hit deals 30% less.
- **Pincer** (`on=hit;do=assist`): once per turn, an ally next to the foe your basic attack hit strikes it too, for 50% (a `counter` event, cause `assist`).
- **Lockstep** (`aura_mod self_if_ally`): a formation bonus; while an ally stands beside you, you both deal +10%.
- **Lifeline** (`swap on=ally_low`): once a battle, an ally within 3 dropping below 25% trades places with you: a rescue swap.

---

## 3. Tiers (D200)

Tiers only **unlock** rows; no number scales with tier. A drop rolls from
every row whose `tier` is at or below the item's, weighted 1, and the rows
at the item's own tier weigh **2** (from D up), so new rows show up when they
unlock. Cursed rows weigh the same as the rest.

| Tier | Rows (all slots) | What unlocks |
|---|---|---|
| E | 73 | The 64 originals plus Hearthbound ×4, Second Breath, Rerouted, Second Chance, Stampede, Fury |
| D | 18 | Momentum (Kiting, High Ground, Shieldwall, Planted), Forge, Tidewalker, Steady Hand, Building Pressure, Graze, Pursuit, Feast, Parry Shield, Thorned, Unshaken, Covering, Spotter, Relay, Lockstep |
| C | 30 | Element interplay, Lone Wolf, Flanker, Disengage, Last Stand, Vengeance, Evasive Roll, Leeching, Sapping, Follow-Through, Second Opinion, Stubborn, Death Knell, Wake ×4, Rallying, Banner, Bodyguard, Inspiring, Rally Cry, Tending, Sheltering |
| B | 15 | Relentless, Mend-Link, Conductor, Bulwark, Tag Team, Pincer, Lifeline and the cursed rows (Bloodpact, Glass, Forsaken, Gambler's, Leaden, Pyre, Reckless, Martyr's) |
| A | 3 | Undying, Hollow, Lightning-Touched |

With two weapon slots, every "once per turn" cap is **per unit**, and the
carried weapon's enchantment does nothing until drawn (D180).

---

## 4. Loop caps (§5 of the draft, applied exactly)

1. **Relentless**: once per turn per unit; the extra action is an attack only (no move) and can't refresh it.
2. **On-kill never triggers on-kill**, for anyone: while on-kill effects resolve (`BWBattle._onkill_depth`), a KO they cause sets nothing off. A Death Knell KO never bursts again.
3. **Kill paint arrives as spread**: Wake rows paint with `tiles.apply` `propagated`, so the charge never fires a fuse, stasis or gale, and glazed hexes are skipped.
4. **On-event healing is at most 20% of max HP per unit per action** (all rows together: Leeching, Feast, Inspiring, Second Breath, Conductor, Sapping, Hearthbound, Tending, Mend-Link). Leeching reads direct hits only, never tiles, arcs or bursts.
5. **Follow-Through's doubled strike can't crit**; Building Pressure caps at +40.

Watch in play: Relentless with Triumph, Undying against the Giant, Bloodpact
on fast multi-hit weapons, Pincer with Covering Fire overwatch.

---

## 5. The shop and the scrolls (D203)

The full shop rules live in `EQUIPMENT.md` §6. In short: per visit the stock
is 1 head, 1 chest, 1 legs and 2 weapons at the current tier, and seven
**imbuement scrolls** are featured, one per element. Each holds one element
row unlocked at the shop's tier (the §3 weights; the cursed element rows,
Pyre and Lightning-Touched, can appear). A scroll is **free** (D236; it
was 2 loose items) and is used at once on any item the squad owns, worn or loose:

- **Armour:** its enchantment is overwritten with the scroll's row.
- **A weapon (D206):** its **imbue** becomes the scroll's element **and** its row, replacing any old imbue; an E/D weapon gains one. The weapon's own enchantment stays (D38).

**The imbue (D206).** A weapon carries (a) its weapon enchantment and (b) an
imbue: an element plus one element row of that element (`imbue_enchant`).
C+ weapons roll both (the imbue's row from that element's rows unlocked at
the item's tier, D200 weights, its own rng). Every element row works from the
holder, so all of them qualify. The imbue's row works only while that weapon
is drawn (the carried weapon gives nothing, D180). The card shows three
lines: the weapon enchantment, the imbue, the imbue's row; the name stays
short ("Fire Flamberge of Cleaving"). Save v9 gives older imbued weapons a
rolled row.

The scrolls are re-rolled after every battle. Re-imbue is gone (D202).
