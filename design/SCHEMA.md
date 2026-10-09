# Shared data schema

Every data file under `game/data/` follows this. Phase 1 lanes write to it;
the game reads it. If two files disagree, this file wins. Change it here
first, then fix the data.

## Stats (7)

| Key | Name | Does |
|---|---|---|
| `con` | Constitution | HP = 100 + 2·con + 15·level (D34, D137, D178; the Giant is a fixed 5000, D138, D485: CON is untouched; its % effects read 500) |
| `str` | Strength | Martial weapon damage, skill damage |
| `dex` | Dexterity | Dexterous weapon damage, hit, crit, avoid, skill damage |
| `wil` | Willpower | Spell damage. Replaces wisdom and intelligence. |
| `def` | Defense | Glance chance, weapon damage reduction |
| `res` | Resistance | Resist chance, spell damage reduction |
| `spd` | Speed | Turn order |

Starting values are 1–6. Stats reach around 100 late in a run and are hard-capped at 1000. Move is 4 hexes for everyone; equipment and skills change it.

## Elements (7)

`fire water ice thunder wind dark light`. Life does not exist.

Opposites (for resistance, +2.5% per affinity rank): fire↔water, light↔dark,
thunder↔wind, ice→all (ice ranks give 2.5% resistance against every element).

Hair colour per element:

| Element | Hex |
|---|---|
| fire | `#E8432E` |
| water | `#2E6FE8` |
| ice | `#5FD8F0` |
| thunder | `#8B3DF0` |
| wind | `#3CCB5A` |
| dark | `#3A2A5C` (deep violet, so it still reads against black) |
| light | `#F5D23A` |

## Weapon classes (8) and model variants (25)

| Class | Damage type | Level-up bias | Variants |
|---|---|---|---|
| sword | martial (str) | str +2 | sword, scimitar, flamberge, rapier, katana (D501) |
| axe | martial (str) | str +2 | axe, double_axe, hatchet, warhammer, anchor, scythe (D501) |
| lance | martial (str) | str +2 | lance, javelin, halberd, glaive, trident, naginata (D501); each comes with a cosmetic shield (D505) |
| daggers | dexterous (dex) | dex +2 | dagger, jagged_dagger, kunai, karambit (D501) |
| bow | dexterous (dex) | dex +2 | shortbow, recurve_bow, compound_bow, longbow, ancestral_bow (D501) |
| pistols | dexterous (dex) | dex +2 | pistol, flintlock, m1911 · **benched (D419)** |
| staff | spell (wil) | wil +2 | staff, moon_staff, divine_staff, orb_scepter (D501) |
| fists | martial (str) | str +2 | hand_wraps, brass_knuckles, gauntlets (D76; worn on both hands) · **benched (D419)** |

Weapon skills come from V8 (`MeleeSkills`). Pistols inherit the flintlock's
skills; staff skills are new, and so are the fists' (Flurry, Uppercut,
Palm Burst; D76).

**Benched classes (D419).** `weapons.csv` has a `benched` column (1 = benched).
A benched class keeps its rows, skills, models and rules but never appears in
play: no drops, shop stock, wander or downtime finds, roster or reserve rolls,
enemy gear, recruit gifts, Branch out cards, skill picks for it, or
enchantments whose every item is benched (`pummeling`, `rebound`, `welling`).
The one source of truth is `BWRun.is_benched(wc)` / `BWRun.weapon_classes()`
(active only; `all_weapon_classes()` lists every row) and `BWRun.gear_rows()`
(equipment.csv without benched weapons). Saves holding a benched class are
converted on load (D420: pistols → bow, fists → daggers, `BWRun.BENCH_SWAP`).
Clear the cell to bring a class back.

## Ranks and tiers

Weapon expertise: `E D C B A` (E is the starting rank). Equipping a weapon needs expertise at its rank or higher.

Gear tiers, stat bonus range per stat line, and when they drop:

| Tier | Stat range | Drops after fight |
|---|---|---|
| E | +0 – +3 | 1–2 |
| D | +1 – +6 | 3–4 |
| C | +2 – +9 | 5–6 |
| B | +3 – +12 | 7–8 |
| A | +4 – +15 | 9–10 |

Affinity: ranks 0–10, at 10 points per rank. Each rank gives +5% damage with that element, +5% resistance to it, and +2.5% resistance to its opposite.

## Progression

- **No XP (D179).** Every squad unit, deployed or benched, gains exactly 1 level after **every fight, won or lost** (D194: `BWProgression.LEVEL_ON_LOSS` = true; false would level on wins only). Squad level = the fight number. Each level adds 1–2 to stats, biased by equipped weapon and armour (see the brief).
- An attack gives +1 affinity in the element used and +1 expertise in the weapon used.
- A knockout gives +3 affinity and +3 expertise.
- **At most 3 elements (D417).** A unit is attuned to an element once it has any affinity points in it; it holds at most `BWUnit.MAX_ELEMENTS` = 3. Every gain goes through `BWUnit.add_affinity`, which drops a gain in a 4th element (battle awards, Whistling/Attuned bonuses, downtime). Branch out offers no new element and Wander's "+1 rank in a random element" picks only owned elements once a unit holds 3. A save with more: the 3 with the most points are kept (ties: native, focus, element order; the native element is always kept, it's the hair), each dropped element's points are cleared and half of them (rounded down) go to the focus element (else native), and its perks and keystones are removed; whatever the new ranks owe is asked through the normal pick flow (`BWUnit.enforce_element_cap`).
- Recruits join at the squad's level. Enemies are levelled by the room's stage (`BWRooms`), not the squad.
- HP = 100 + 2·CON + 15·level (D178).

## Downtime (D127–D132, D175–D177, D179)

Each unit takes one choice a day. **A day offers each unit 2 of the 3** (`BWRun.day_choices`: seeded by the run, the day and the unit, stable all day), shown by name only:

- **Specialize**: +½ rank in the focus element and the held class; 50% a free skill pick (else a weapon of the class), 50% a free perk pick (else armour attuned to the element).
- **Branch out**: two cards, each a new element (rank 0; none once the unit holds 3 elements, D417) + a new class (at E). **The cards are rolled when the day starts and shown on the Branch out tile** (`BWRun.branch_preview`); pressing a card is the choice. It gives a full rank in each, a weapon of the class and armour of the element, both at the fight's tier (D192: no cap at the new expertise letter). Choosing another activity discards the cards. Nothing new left: +1 to a random stat.
- **Wander**: nine effects, each at 20%: +1 to a random stat (permanent); +1 rank in a random element (an owned one once the unit holds 3, D417); +1 rank in a random class; a weapon find; an armour find; a recruit from the last fight (one a day, squad-wide); a status immunity, an element brace and +10 to a stat for the next fight. All nine missed: +1 to a random stat, unless the 5% jackpot roll lands: "a being of unlimited benevolence" rerolls the nine at 30% each (still one recruit a day); if that misses too, +1 to a random stat.
- No XP from any choice (D179). There is no rogue (D177).

## Equipment slots

`head chest legs main_hand`. Armour weight classes: `heavy ranger wizard`.
Every piece has stats plus one built-in enchantment. Armour enchantments
change how an element behaves; weapon enchantments change how the weapon
attacks. `enchantments.csv` (D196–D205) adds `tier` (E–A, the lowest tier a
row drops at), `family`, `cursed` (0/1), `cost_text`, `also` (extra records,
`key(a=1;b=2) | ...`), `drawback` (the cost's params) and `strength` (D380: 1-3,
an internal tier weight; it only ranks the shop's Featured scroll, never shown); see
ENCHANTMENTS-v2.md §0. The shop's imbuement scrolls are run state
(`BWRun.scrolls`, save v8), not a table.

## Friendliness

`unfriendly neutral friendly`. Trust stages for barks are `strangers`
(squad's first fights), `acquainted`, and `trusted`.

## File formats

- CSV, UTF-8, header row, comma-separated. Quote any field that contains a comma.
- IDs are `snake_case` and unique within their file.
- List fields are `|`-separated inside one cell.

## Roster (`roster.csv`)

`id,name,gender,seat,element_lock,friendliness,hair_style,voice_pitch,pool` (D150: identity only)

- `pool` (D379): 0 = one of the 20 core seats (`BWData.identities()`), 1 = the rolling pool
  (`BWData.pool_identities()`; seat 21+ is only its csv order, a seated pool member takes
  the seat it fills). See design/ROSTER.md.

- The rest of a roster row (`weapon_class,weapon_model,element,con..spd,top,bottom,clothing_shade`)
  is rolled per game by `BWRosterGen.roll(identities, seed)`; see design/ROSTER.md. No `tagline` (D153).
- `id`: the lowercase name. `seat`: 1–20, front row left→right then rear.
- `element_lock`: blank, or the element the roll always gives (Aureli light, Rem ice).
- `gender`: `m` / `f` / `a` (ambiguous). Only steers the clothing pools.
- `hair_style`: buzzed, high_and_tight, mullet, short_mohawk, bob, ponytail, long_ponytail, waterfall, ringlets, long_hair
- `top`: tank_top, crop_top, hoodie, crop_hoodie, tshirt, sweater, sweater_scarf
- `bottom`: baggy_sweatpants, sweatpants, tight_pants, ripped_tight_pants, tight_shorts, shorts, short_shorts
- `clothing_shade`: dark / mid / light
- `voice_pitch`: 0.75–1.35, the pitch-shift factor applied to the recorded barks
- Everyone starts at affinity rank 1 (10 points) in their `element` and at expertise E in every weapon.

## Barks (`barks.csv`)

`id,event,action,speaker_friendliness,toward_friendliness,trust,line,voice_clip`

- `event`: ally_attacking, ally_ko, healing_received, downtime_advice, self_ko, crit_landed, dodged, enemy_ko, battle_start, battle_won, level_up, recruited
- `action` (downtime only, blank elsewhere; `ask` = the unit asks for advice): train_element, train_weapon, train_ability, search_equipment, improve_equipment, enchant_equipment, rest, recruit. **The downtime UI uses these same ids.**
- `toward_friendliness`: unfriendly / neutral / friendly / `any`
- `voice_clip`: an `Audio Barks/` filename without `.wav`. It may contain a space (`Ouch grunt`).
- How lines are chosen and how trust advances: see `design/BARKS.md`.

## Perks (`perks.csv`, D90)

`id,element,name,effect_text,effect_key,params`

- Five rows per element, 35 in all (D93, final; rules in ELEMENTS.md §13). Rank 1 in an element =
  the first pick, rank 2 = a second, rank 3 = all of them. CSV order is the card order and the AI's
  pick order. Columns unchanged.
- `effect_key` / `params`: the enchantment vocabulary (EQUIPMENT.md §1) plus the perk keys
  (`BWEffects.PERK_KEYS`: move_cost, stand_on_mod, start_move, undertow, heat_rush, ember_skin,
  wildfire, skate, rime_armour, fault_lines, frostbite, frost_ward, bolt_step, grounded, overcharge,
  static_field, lightning_rod, tailwind, eye_of_storm, gust, slipstream, shadowstep, nightborn,
  hit_status, cover, radiant_guard, judgement, glare, sanctuary). Common params: `on` (the element
  read under a unit), `per_point` or `l1`/`l2`/`l3` (by the hex's charge level), `side`
  (att/def/either), `stage` (avoid/glance/crit/dmg), `team` (1 = the holder's allies too).
