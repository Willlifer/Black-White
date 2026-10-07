# Enchantments v2

**Current spec** (D196–D205; consolidated by D243–D247). The data is
`game/data/enchantments.csv` (97 rows since the Passives v2 consolidation,
`PASSIVES-v2.md` §2: 139 → 83 as approved, plus 14 element rows held for the
element pass; see "Deferred" below); the battle side is
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
| Fireproof, Grounded, Windbreak, Nightforged | 15% or 25% less | **20%** each (since D243 one Warded row, **25%**) |

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
- **Sapping** (now part of Conductor's) heals 10%, **Leeching** 15% (D197).
- **Second Opinion and Warded (was Stubborn) are Advantage** (D198): the resist is rolled twice and the holder's side keeps the better, then 3 of the holder's turns to recharge. The forecast shows the effective chance (attacker: r², defender: 1 − (1 − r)²). If both sides hold it, it cancels. It's spent only on a blow that reached the resist roll.
- **Cursed rows** drop at the same weight as everything else (D201). Each shows a curse mark (†) on its tile, after its name and on the card's kind line, and the card spells out the cost under the passive.
- **Pursuit** and **Feast** stay off weapons: the draft starts weapon on-kill and recovery rows at C, and these are D rows. (Since D244 Pursuit also rolls on head pieces and Feast on head and chest, from the rows they absorbed.)
- **Wake** (one row since D244) paints your attuned element; with none attuned it paints nothing.
- **Warded** (D243) is the old Fireproof, Grounded, Windbreak, Nightforged and Stubborn in one row: its element is rolled when it drops (a scroll or an imbue sets its own), stored on the item as `ward`, and shown in its name ("Fire-Warded Chaps") and colour. 25% less from that element and its tiles, and Advantage on resisting it.

**Deferred to the element pass** (left as they are; PASSIVES-v2 §2 moves them):
into perks: Tidewalker, Forge, Overloading, Permafrost, Cold Snap, Nightfall,
Beacon, Shattering, Wading; into sets: Blazing, Riptide, Shrouded, Sunlit,
Rimed.

The tables below are generated from the CSV.

### A. On kill

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Relentless** (`relentless`) | B | W | — | A KO lets you attack once more this turn (an attack only, no move). Once per turn. | `on_event` on=kill; do=action; per_turn=1 |
| **… of Pursuit** (`pursuit`) | D | H/L | — | A KO lets you move 2 more this turn; a KO by an ally within 2 gives you +2 move on your next turn. | `on_event` on=kill; do=move; hexes=2 + `on_event(on=ally_kill;do=move;hexes=2;radius=2;next=1)` |
| **… of the Death Knell** (`death_knell`) | C | W/C | — | A KO bursts the victim's hex: foes within 1 take 10% of their max HP. A burst KO never sets off on-kill effects. | `on_event` on=kill; do=blast; pct=10; radius=1 |
| **… of the Wake** (`wake`) | C | H/C/L | attuned | A KO lays 1 step of your attuned element on the victim's hex and the ring around it, as spread (it never fires a marker and skips glazes). | `on_event` on=kill; do=paint; step=1; radius=1; element=attuned |
| **Feasting** (`feast`) | D | H/C | — | A KO heals you 15% of your max HP and allies within 2 for 8% of theirs. | `on_event` on=kill; do=heal; pct=15 + `on_event(on=kill;do=heal;target=allies;radius=2;pct=8)` |
| **Rallying** (`rallying`) | C | H/C | — | A KO gives allies within 2 +10% damage on their next turn. | `on_event` on=kill; do=empower; target=allies; radius=2; dmg_pct=10; uses=turn |

### B. Recovery

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Leeching** (`leeching`) | C | W | — | Heal 15% of the damage your direct hits deal (never tiles, arcs or bursts). | `on_event` on=dealt; do=heal; pct_of=15 |
| **Mend-Linked** (`mend_link`) | B | C | — | Any heal you receive also heals the most-hurt ally within 2 for half as much. The echo never echoes. | `on_event` on=healed; do=heal; target=lowest_ally; radius=2; share=50 |

### C. RNG forgiveness

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Steady** (`steady_hand`) | D | W/H | — | A missed basic attack still deals 25% and lays 1 step of your attuned element on the target's hex; after an action of yours misses completely, your next attack can't be avoided. | `pity` kind=miss + `pity(kind=graze;pct=25)` + `lay_on(trigger=miss;where=target;step=1;chance=100;element=attuned)` |
| **… of Follow-Through** (`follow_through`) | C | W | — | After one of your hits glances, your next strike deals x2. That strike can't crit. | `pity` kind=glance; mult=2 |
| **Pressing** (`building_pressure`) | D | W/H | — | +8 crit for each of your hits that doesn't crit, up to +40. A crit resets it. | `pity` kind=crit; per=8; cap=40 |
| **… of Second Opinion** (`second_opinion`) | C | W/H | — | Advantage: when a foe rolls to resist your element, it rolls twice and you keep the better roll. Then 3 turns to recharge. | `pity` kind=resist; side=att; cd=3 |
| **… of Second Chance** (`second_chance`) | E | H | — | Once per battle, your first miss is re-rolled. | `pity` kind=reroll; once=1 |

### D. Momentum and positioning

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Kiting** (`kiting`) | D | L | — | +5 avoid for each hex you moved this turn, up to +20, until your next turn. | `aura_mod` avoid_per_hex_moved=5; avoid_cap=20 |
| **Flanking** (`flanker`) | C | W/H | — | +20% damage on rear and rear-flank blows. | `attack_mod` rear_pct=20 |
| **Lone Wolf** (`lone_wolf`) | C | H/L | — | With no ally within 2: +15% damage and +10 avoid. | `attack_mod` alone_dmg_pct=15; alone_avoid=10 |
| **Planted** (`planted`) | D | L | — | If you didn't move this turn: +20% damage, and you can't be displaced until your next turn. | `attack_mod` still_pct=20 |
| **Disengaging** (`disengage`) | C | L | — | Once per enemy turn, when an adjacent foe hits you or you avoid its attack, step 1 hex away. | `on_event` on=struck; do=step; hexes=1; melee_only=1; per_turn=1 + `on_event(on=avoided;do=step;hexes=1;melee_only=1;per_turn=1)` |
| **Lockstep** (`lockstep`) | D | C/L | — | For each adjacent ally (up to 3) you take 5% less damage and deal 5% more; allies next to you take 5% less and deal 5% more. | `damage_taken_mod` per_adjacent_ally=-5; max_pct=15 + `attack_mod(dmg_per_adjacent_ally=5;adj_max_pct=15)` + `aura_mod(radius=1;allies=1;dmg_pct=5;taken_pct=-5)` |

### E. Element interplay

The element rows above tier E. (The tier-E element rows, Warded among them,
are listed per item in `EQUIPMENT.md` §2.) Forge, Tidewalker, Overloading,
Permafrost, Cold Snap, Nightfall and Beacon are slated to move into perks in
the element pass (`PASSIVES-v2.md` §2) and stay as they are until then.

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Overloading** (`overload`) | C | H/C | thunder | Your detonations deal +5% for each charge point they blow. | `element_damage_pct` per_level=5 |
| **Conductor's** (`conductor`) | B | H/C | thunder | Chain arcs you cause heal you 50% of the arc, and your detonations heal you 10% of the blast damage they deal to foes. | `on_event` on=chain; do=heal; pct_of=50 + `on_event(on=detonate;do=heal;pct_of=10)` |
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
| **Thorned** (`thorned`) | D | C | — | A foe that hits you in melee takes 20% of the damage it dealt. | `on_event` on=struck; do=reflect; pct_of=20; melee_only=1 |
| **Unshaken** (`unshaken`) | D | H | — | The first status laid on you each battle is ignored. | `immune` what=status; once=1 |
| **Bulwark** (`bulwark`) | B | C | — | A single hit above 20% of your max HP deals only half of the excess. | `damage_taken_mod` cap_pct=20; excess=50 |
| **Undying** (`undying`) | A | C | — | Once per battle, a blow that would knock you out leaves you at 1 HP. | `immune` what=ko; once=1 |

### G. Cursed (risk and reward)

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Bloodpact** (`bloodpact`) | B | W | — | +25% damage. | `attack_mod` dmg_pct=25 + `drawback` hp_cost=4 |
| **Glass** (`glass`) | B | H | — | +20 crit, and your crits deal x2. | `attack_mod` crit=20; crit_mult=0.5 + `drawback` status=scorched |
| **Forsaken** (`forsaken`) | B | W/L | — | +5% damage for every 10% of your HP missing. | `attack_mod` dmg_per_missing10=5 + `drawback` no_light_heal=1 |
| **Hollow** (`hollow`) | A | C | — | +15% damage and 15% less damage taken. | `attack_mod` dmg_pct=15 + `damage_taken_mod(source=any;pct=-15)` + `drawback` no_heal=1 |
| **Gambler's** (`gamblers`) | B | W | — | Your crits deal x2.5. | `attack_mod` crit_mult=1.0; nocrit_pct=85 + `drawback` inherent=1 |
| **Leaden** (`leaden`) | B | L | — | +30% damage and 20% less damage taken. | `attack_mod` dmg_pct=30 + `damage_taken_mod(source=any;pct=-20)` + `drawback` move=-2 |
| **Pyre** (`pyre`) | B | H/C/L | fire | Your fire tiles are 50% stronger. | `tile_potency_pct` pct=50 + `drawback` fire_taken_pct=50 |
| **Lightning-Touched** (`lightning_touched`) | A | C | thunder | Chain arcs you cause deal 100% instead of 50%. | `element_damage_pct` pct=0; chain_pct=100 + `drawback` conductive=1 |
| **Reckless** (`reckless`) | B | H | — | Weapon skills recover 1 turn faster. | `skill_cd_minus` amount=1; once_per_battle=0 + `drawback` no_glance=1 |
| **Martyr's** (`martyrs`) | B | C | — | Allies within 2 take 15% less damage. | `aura_mod` radius=2; allies=1; taken_pct=-15 + `drawback` taken_pct=15 |

### H. Team and support

| Row | Tier | Slots | Element | Effect | Key · params |
|---|---|---|---|---|---|
| **Bodyguard's** (`bodyguard`) | C | C/L | — | Once per turn, your move can be a swap: trade places with an ally within 2 for 1 move. Once per battle, an ally within 3 dropping below 25% HP trades places with you. | `swap` mode=move; radius=2; cost=1 + `swap(on=ally_low;threshold=25;radius=3;once=1)` |
| **Covering** (`covering`) | D | C | — | You take 25% of the damage aimed at an adjacent ally. | `damage_taken_mod` cover_pct=25; radius=1 |
| **Spotter's** (`spotter`) | D | W/H | — | A foe your basic attack hits is Scorched (attacks on it deal +10%). | `hit_status` on=any; min=0; basic=1; status=scorched |
| **Sheltering** (`sheltering`) | C | H/C | — | Start your turn: the most-hurt ally within 2 is Sheltered (its next hit deals 30% less). Once per ally per battle, an ally dropping below 35% HP gets a 25% guard until its next turn. | `on_event` on=turn_start; do=shield; target=lowest_ally; radius=2; pct=30 + `on_event(on=ally_low;do=guard;pct=25;threshold=35;radius=99)` |
| **… of the Pincer** (`pincer`) | B | W | — | Once per turn, when your basic attack hits, an ally next to that foe strikes it too for 50%. | `on_event` on=hit; do=assist; share=50; per_turn=1 |

### The merges (D243–D246, Claude)

A merged row keeps the union of its sources' items and both effects (the
second as an `also` record), at the surviving row's tier:

- **Pursuit** carries Tag Team (an ally's KO within 2 banks +2 move), **Feasting** carries Inspiring (allies within 2 heal 8%).
- **Steady** carries Grazing (a missed basic deals 25%) and Rerouted (a miss lays 1 step of your attuned element).
- **Guarding** carries Parrying (an avoid: the next hit −30%), on every armour piece as well as its weapons.
- **Lockstep** (now momentum) carries Shieldwall: per adjacent ally (up to 3) you take 5% less and deal 5% more; allies beside you get 5% / 5%.
- **Disengaging** carries the Evasive Roll (an avoided melee attack also steps you away; one step per enemy turn).
- **Bodyguard's** carries Lifeline (once a battle, an auto-swap with an ally dropping below 25% within 3).
- **Sheltering** carries the Rally Cry (an ally dropping below 35% gets a 25% guard, once per ally per battle).
- **Wake** is one row for the four: it paints your attuned element.
- **Cut:** Hearthbound ×4, Second Breath, Relay, Tending, Whistling. High Ground, Vengeful, Furious and Banner folded into abilities (Dragoon's Descent, Heavy Is the Head, Bloodied, Royal Presence).

---

## 3. Tiers (D200)

Tiers only **unlock** rows; no number scales with tier. A drop rolls from
every row whose `tier` is at or below the item's, weighted 1, and the rows
at the item's own tier weigh **2** (from D up), so new rows show up when they
unlock. Cursed rows weigh the same as the rest.

| Tier | Rows (all slots) | What unlocks |
|---|---|---|
| E | 50 | The element rows (Warded among them), the weapon rows, Second Chance |
| D | 13 | Kiting, Planted, Lockstep, Forge, Tidewalker, Steady, Pressing, Pursuit, Feasting, Thorned, Unshaken, Covering, Spotter's |
| C | 18 | Element interplay (Overloading, Cold Snap, Permafrost, Windrider, Nightfall, Beacon), Lone Wolf, Flanking, Disengaging, Last Stand, Leeching, Follow-Through, Second Opinion, Death Knell, Wake, Rallying, Bodyguard's, Sheltering |
| B | 13 | Relentless, Mend-Link, Conductor's, Bulwark, Pincer and the cursed rows (Bloodpact, Glass, Forsaken, Gambler's, Leaden, Pyre, Reckless, Martyr's) |
| A | 3 | Undying, Hollow, Lightning-Touched |

With two weapon slots, every "once per turn" cap is **per unit**, and the
carried weapon's enchantment does nothing until drawn (D180).

---

## 4. Loop caps (§5 of the draft, applied exactly)

1. **Relentless**: once per turn per unit; the extra action is an attack only (no move) and can't refresh it.
2. **On-kill never triggers on-kill**, for anyone: while on-kill effects resolve (`BWBattle._onkill_depth`), a KO they cause sets nothing off. A Death Knell KO never bursts again.
3. **Kill paint arrives as spread**: Wake paints with `tiles.apply` `propagated`, so the charge never fires a fuse, stasis or gale, and glazed hexes are skipped.
4. **On-event healing is at most 20% of max HP per unit per action** (all rows together: Leeching, Feasting, Conductor's, Mend-Link). Leeching reads direct hits only, never tiles, arcs or bursts.
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

---

## 6. The consolidation (D243–D247)

The approved Passives v2 merges that don't depend on element identity
(`PASSIVES-v2.md` §2; the perks and the set bonuses wait for the element
rework). In short:

- **Element pairs** fold the duration row into its element's other row (D243): Kindled + Smouldering, Abyssal + Umbral, Dawning + Hallowed, Brimming + Deepwater, Glacial + Frozen, Gusting + Lingering (each `also` `tile_duration_plus`), Arcing + Jolting, Conductor's + Sapping. Warded replaces the four resist rows and Stubborn. Frostbitten: the first basic you land each turn glazes, no roll. Whistling is cut.
- **Weapon rows** (D244): Keen + Serrated (+10 crit, crits ×2), Longshot + Piercing (+2 range; a reach-1 weapon reaches 2), Cleaving + Channelling, Forceful = Impact + Hooking (push or pull, the player's call on the forecast; the AI pushes), Jousting + Stampeding, Conducting + Resonant (+5% per charge level, up to +25%).
- **The other families** are in §2 ("The merges").
- **Old saves** (D247, save v10): merged ids map to the row they joined, the resist rows become Warded of their element (Stubborn rolls one), and pure cuts (and the rows folded into abilities) re-roll on the same item from their old family and tier, else that family at the item's tier, else anything the item can roll. An imbue's row maps when the target keeps its element, else re-rolls in it. Scrolls naming a gone row re-roll.
