# Shared data schema

Every data file under `game/data/` follows this. Phase 1 lanes write to it;
the game reads it. If two files disagree, this file wins. Change it here
first, then fix the data.

## Stats (7)

| Key | Name | Does |
|---|---|---|
| `con` | Constitution | HP = 100 + 2·con + 10·level (D34, D137; the Giant is a fixed 500, D138) |
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
| sword | martial (str) | str +2 | sword, scimitar, flamberge |
| axe | martial (str) | str +2 | axe, double_axe, hatchet, warhammer, anchor |
| lance | martial (str) | str +2 | lance, javelin, halberd, glaive |
| daggers | dexterous (dex) | dex +2 | dagger, jagged_dagger |
| bow | dexterous (dex) | dex +2 | shortbow, recurve_bow, compound_bow |
| pistols | dexterous (dex) | dex +2 | pistol, flintlock, m1911 |
| staff | spell (wil) | wil +2 | staff, moon_staff |
| fists | martial (str) | str +2 | hand_wraps, brass_knuckles, gauntlets (D76; worn on both hands) |

Weapon skills come from V8 (`MeleeSkills`). Pistols inherit the flintlock's
skills; staff skills are new, and so are the fists' (Flurry, Uppercut,
Palm Burst; D76).

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

- 100 XP per level. Each level adds 1–2 to stats, biased by equipped weapon and armour (see the brief).
- An attack gives 10 XP, +1 affinity in the element used, and +1 expertise in the weapon used.
- A knockout gives 30 XP, +3 affinity, and +3 expertise.

## Equipment slots

`head chest legs main_hand`. Armour weight classes: `heavy ranger wizard`.
Every piece has stats plus one built-in enchantment. Armour enchantments
change how an element behaves; weapon enchantments change how the weapon
attacks.

## Friendliness

`unfriendly neutral friendly`. Trust stages for barks are `strangers`
(squad's first fights), `acquainted`, and `trusted`.

## File formats

- CSV, UTF-8, header row, comma-separated. Quote any field that contains a comma.
- IDs are `snake_case` and unique within their file.
- List fields are `|`-separated inside one cell.

## Roster (`roster.csv`)

`id,name,gender,seat,element_lock,friendliness,hair_style,voice_pitch` (D150: identity only)

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
