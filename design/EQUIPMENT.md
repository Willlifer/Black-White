# Equipment, enchantments and abilities

For review. The data lives in `game/data/equipment.csv`, `enchantments.csv`
and `abilities.csv`; this page is the readable view of them. `SCHEMA.md` wins
any disagreement. Every number here is a first pass, kept modest, and expected
to move once it is played.

Counts: 48 items (23 armour, 25 weapons), 139 enchantments (the 64 originals,
42 armour and 22 weapon, plus 75 from Enchantments v2: see
`ENCHANTMENTS-v2.md`, the current spec for the new families, keys, tiers and
caps), 46 abilities (12 reactive, 11 supportive, 23 passive). Every item can
roll at least 3 enchantments; every armour piece teaches at least 1 ability
(the brief's core pieces teach 2 or 3).

## 1. The effect_key vocabulary (25 keys)

**v2 (D196–D205):** four more generic keys (`on_event`, `pity`, `drawback`,
`swap`) and new params on these ones are specified in `ENCHANTMENTS-v2.md` §0.

Every enchantment and ability is one `effect_key` plus `params`. Code
implements each key once and the CSV rows just set numbers, so a new
enchantment is a new row, not new code.

**params format:** `name=value;name=value`. Semicolons, because `|` is the
list separator and commas need quoting. Values are numbers, except a few
enum words listed below (`trigger`, `where`, `source`, `what`, `pattern`,
`on`, `stat`, `from`, `to`, `vs`, `when`, `until`). Where a stat list is
needed it is joined with `+` (`stats=wil+res`). An absent param means "no
change".

**"Your" and the element column.** An armour enchantment's element is the
row's `element` column; it is not repeated in params. "Your fire tiles"
means fire charge that *this unit* laid, which needs tiles to remember who
charged them (see section 8). An enchantment for an element the wearer
doesn't use sleeps until they learn it, which is a reason to study a second
element. Defensive keys (`damage_taken_mod`, `immune`) work whatever the
wearer's elements are.

### Element keys (armour enchantments)

| Key | Params | Meaning |
|---|---|---|
| `tile_duration_plus` | `turns` | Charge you lay of this element lasts `turns` longer before it starts decaying. For ice the lock lasts longer; for wind the copied tiles do. |
| `tile_erupt` | `delay`, `dmg_per_point`, `heal_per_point`, `radius`, `push`, `consume` | `delay` turns after you lay this element, the tile goes off: damage (or healing, to allies) per charge point to its occupant and everyone within `radius`. `push` moves them (+ out, − in). `consume=1` returns the tile to neutral. |
| `effect_repeat` | `extra`, `scale_pct` | Your operator effect of this element resolves `extra` more times, each at `scale_pct`% strength, before the ground is spent. |
| `cast_step_plus` | `steps` | Your casts of this axis element (fire, water, dark, light) move the tile `steps` further along its axis. Still capped at ±3. |
| `element_area_plus` | `radius`, `step` | Your casts of this element reach `radius` more rings. Axis elements lay `step` intensity on the added ring; operators (thunder splash, ice lock, wind spread) apply at full effect and ignore `step`. |
| `tile_potency_pct` | `pct` | The per-point effect of your tiles of this element is `pct`% stronger: fire burn, water wading cost and its detonation bonus, light exposure and healing, dark concealment, ice's shatter multiplier. |
| `stand_on_bonus` | `stat`, `per_point`, `flat` | While you stand on a tile charged with this element (anyone's charge), gain `per_point` × charge points to `stat`, or `flat` for an operator state that has no points (a lock). |
| `lay_on` | `trigger`, `where`, `step`, `chance`, `melee_only` | When `trigger` happens (`hit`: you land a basic attack; `struck`: you are hit; `move`: you leave a tile; `cast`: you use the element), lay this element at `where` (`target`, `attacker`, `self`, `path`). `step` is axis intensity; operators just apply. |
| `element_damage_pct` | `pct`, `next_same` | Your damage with this element is `pct`% higher. With `next_same=1` it applies only to your next attack with the element you just used (Imbued); a blank element means any. |
| `damage_taken_mod` | `source`, `pct`, `tile_pct`, `crit_mult_minus` | Incoming damage from `source` (an element, or `spell`, `weapon`, `skill`, `crit`) changes by `pct`% (negative is less). `tile_pct` does the same for damage from tiles of that element. `crit_mult_minus` lowers the crit multiplier used against you. |
| `affinity_gain_plus` | `amount` | +`amount` affinity points each time you attack with this element (any element if blank). |
| `immune` | `what`, `radius` | You ignore `what` (`displace` for knockback/pull/shove, `muddy` terrain cost, `water_wading`). `radius ≥ 1` extends it to allies within that many hexes. |

### Weapon keys (weapon enchantments)

| Key | Params | Meaning |
|---|---|---|
| `aoe_radius_plus` | `radius`, `ring_pct`, `basic`, `skills`, `friendly` | Adds `radius` rings to the basic attack (`basic=1`) and/or AoE skills (`skills=1`). The added ring takes `ring_pct`% damage; `friendly=0` spares allies in it. |
| `range_mod` | `mult`, `plus`, `dmg_pct`, `ranged_only` | Basic attack range becomes `range × mult + plus`. Hits beyond the weapon's normal range deal `dmg_pct`%. `ranged_only=1` limits it to bows and pistols (used by an ability). |
| `multi_hit` | `count`, `dmg_pct`, `pattern` | A basic attack becomes `count` hits at `dmg_pct`% each. `pattern`: `same` (all on the target, each rolled separately), `fan` (one shot per line, across neighbouring headings), `line` (the target takes full damage and the next unit behind it in the same line takes `dmg_pct`%). |
| `move_after_attack` | `hexes` | After attacking you may move `hexes` more, even if you already moved this turn. |
| `knockback` | `hexes`, `on`, `chance` | Moves the target `hexes` away from you (negative pulls it toward you) when `on` happens: `hit` (your basic attack) or `trigger` (your operator of the row's element goes off; used by armour). |
| `counter_attack` | `dmg_pct`, `per_turn`, `range` | When an enemy within `range` attacks you, strike back at `dmg_pct`%, up to `per_turn` times per enemy turn. |
| `attack_mod` | `hit`, `crit`, `crit_mult`, `dmg_pct`, `def_ignore_pct`, `hit_per_hex`, `dmg_per_hex_moved_pct`, `max_pct`, `vs_charged_pct`, `min_range`, `dmg_per_height_pct` | A bag of flat modifiers on your attacks. `hit` and `crit` are percentage points; `crit_mult` adds to the ×1.5; `hit_per_hex` scales with distance; `dmg_per_hex_moved_pct` scales with hexes moved this turn, up to `max_pct`; `vs_charged_pct` applies when the target stands on any charge; `min_range` gates the whole row; `dmg_per_height_pct` is per elevation level above the target. |
| `skill_cd_minus` | `amount`, `once_per_battle` | Weapon skill cooldowns are `amount` shorter (minimum 0). `once_per_battle=1` makes it a single use. |
| `guard` | `pct`, `when`, `until` | After `when` (`after_attack`), take `pct`% less damage `until` (`next_turn`). |

**Skill riders (D76).** A weapon row may add `skill=<key>` to an existing key
to touch one skill instead of the basic attack; no new keys. `multi_hit`
`count` with `skill=flurry` sets Flurry's strike count (the basic attack
ignores the row). `knockback` `hexes` with `on=skill;skill=uppercut` adds to
Uppercut's push (`on=skill` keeps it off `hit` and `trigger`). `cast_step_plus`
`steps` with `skill=palm_burst` adds to Palm Burst's pour (a weapon row has
no element, so element casts in general never read it).

### Ability keys (also usable by enchantments)

Abilities reuse the keys above where they fit (`immune`, `attack_mod`,
`element_damage_pct`, `affinity_gain_plus`, `damage_taken_mod`,
`skill_cd_minus`, `range_mod`) and add four:

| Key | Params | Meaning |
|---|---|---|
| `trigger_stat` | `trigger`, `stats`, `amount`, `cap`, `threshold`, `once` | When `trigger` happens (`damaged`, `knockout`, `ally_ko`, `avoided`, `low_hp`), add `amount` to each of `stats` for the rest of the battle, up to `cap` in total. `low_hp` fires on crossing `threshold`% HP. `once=1` fires a single time. |
| `aura_mod` | `radius`, `allies`, then any of `str dex wil def res spd con avoid hit crit resist move dmg_pct` | Flat bonuses. `radius=0` is yourself only; `radius ≥ 1` with `allies=1` gives them to allies within range (not yourself). `avoid`, `hit`, `crit` and `resist` are percentage points on those chances. |
| `glance_mod` | `chance_mult`, `chance_plus`, `reduction_mult`, `cap`, `vs`, `radius`, `allies` | Changes glancing. `reduction_mult` multiplies the 50% glance reduction, held to `cap`%. `vs=melee` limits it to adjacent attackers. `radius`/`allies` work as in `aura_mod`. |
| `stat_share` | `from`, `to`, `pct` | Adds `pct`% of your `from` stat to your `to` stat. Computed from base + gear only, never from other shares, so Vest and Brigandine together can't loop. |

## 2. Items

Weights follow the brief: **heavy** leans str/def, **ranger** leans dex/spd,
**wizard** leans willpower/res. A few pieces carry a con line, or one
off-lean stat, to tell siblings apart. Weapons roll their class's damage stat
plus one other. Weapon damage, range and speed come from the class row in
`weapons.csv`.

Weight counts: head 2 heavy / 3 ranger / 3 wizard; chest 4 heavy / 4 ranger /
2 wizard; legs 2 heavy / 2 ranger / 1 wizard.

**Hair under headgear (D228):** head rows carry `hides_hair`: `all` hides the
hair (Feathered Full Helm, Dragoon Helm), `top` keeps only hair that fits under
the brim (Feathered Cap, Baseball Cap, Tilted Beret, Wizard Hat), `none` shows it
(Tiara, Crown). It wins over the model manifest's `hair_mode`.

### Head

| Item | Weight | Stats | Abilities (learned after 2 battles) | Enchantments it can roll |
|---|---|---|---|---|
| Feathered Cap | ranger | dex, spd | **Deadeye** (supportive): +5% hit chance for every hex between you and your target.<br>**Fletcher's Eye** (passive): +5% critical chance against targets 3 or more hexes away. | **Riptide Feathered Cap** (water): +10% dexterity per water point on the tile you stand on (at least +1 per point).<br>**Static Feathered Cap** (thunder): When an adjacent enemy strikes you, thunder lands on its tile (detonating any charge there).<br>**Gusting Feathered Cap** (wind): Your gales copy the tile 2 rings out instead of 1.<br>**Whistling Feathered Cap** (wind): +1 extra wind affinity point every time you use wind.<br>**Shrouded Feathered Cap** (dark): +10% speed per dark point on the tile you stand on (at least +1 per point).<br>**Gloaming Feathered Cap** (dark): Your dark tiles hide their occupant 50% better. |
| Feathered Full Helm | heavy | def, con | **Unflinching** (supportive): You and allies next to you cannot be knocked back, pulled or shoved.<br>**Visor** (passive): Critical hits against you deal x1.25 instead of x1.5. | **Fireproof Feathered Full Helm** (fire): Take 20% less fire damage and half damage from burning tiles.<br>**Frozen Feathered Full Helm** (ice): Your ice locks (glazes) last 1 turn longer.<br>**Rimed Feathered Full Helm** (ice): +20% defense (at least +2) while you stand on a locked (glazed) tile.<br>**Thundering Feathered Full Helm** (thunder): Your thunder effects trigger twice; the second resolves at 50%.<br>**Hallowed Feathered Full Helm** (light): Light tiles you lay last 1 turn longer. |
| Wizard Hat | wizard | wil, res | **Imbued** (supportive): When you use an element, your next attack with that same element deals 25% more damage.<br>**Attuned** (passive): +1 extra affinity point in any element you attack with. | **Kindled Wizard Hat** (fire): Your fire casts push the tile 1 extra step hotter (still capped at +3).<br>**Brimming Wizard Hat** (water): Your water tiles are 50% stronger: wading costs more and thunder gets +50% of the water bonus when it detonates them.<br>**Glacial Wizard Hat** (ice): Your ice also locks the 6 tiles around the one you target.<br>**Stormcaller's Wizard Hat** (thunder): Your thunder deals 20% more damage.<br>**Whistling Wizard Hat** (wind): +1 extra wind affinity point every time you use wind.<br>**Abyssal Wizard Hat** (dark): Your dark casts push the tile 1 extra step darker (still capped at -3).<br>**Dawning Wizard Hat** (light): Your light casts push the tile 1 extra step brighter (still capped at +3).<br>**Sunlit Wizard Hat** (light): +10% willpower per light point on the tile you stand on (at least +1 per point). |
| Baseball Cap | ranger | spd, dex | **Heads Up** (supportive): Allies within 2 hexes get +5% avoid. | **Emberstep Baseball Cap** (fire): Every tile you leave while moving gains 1 fire step.<br>**Wading Baseball Cap** (water): Water tiles never slow you.<br>**Jolting Baseball Cap** (thunder): Your detonations knock whoever stands on the tile 1 hex away from you.<br>**Howling Baseball Cap** (wind): Your gales push everyone on the spread tiles 1 hex outward.<br>**Shadowtrail Baseball Cap** (dark): Every tile you leave while moving gains 1 dark step.<br>**Sunlit Baseball Cap** (light): +10% willpower per light point on the tile you stand on (at least +1 per point). |
| Tilted Beret | ranger | dex, wil | **Flair** (passive): +5% critical chance.<br>**Encore** (reactive): When you knock out an enemy, +1 speed for the rest of the battle (up to +3). | **Deepwater Tilted Beret** (water): Water tiles you lay last 1 turn longer.<br>**Arcing Tilted Beret** (thunder): Your detonations splash 2 rings out instead of 1.<br>**Lingering Tilted Beret** (wind): Tiles copied by your gales last 1 turn longer.<br>**Umbral Tilted Beret** (dark): Dark tiles you lay last 1 turn longer.<br>**Gloaming Tilted Beret** (dark): Your dark tiles hide their occupant 50% better.<br>**Flaring Tilted Beret** (light): Light tiles you lay flare 1 turn later: allies on the tile and its neighbours heal 2 per light point, then the tile goes neutral. |
| Tiara | wizard | res, wil | **Grace** (supportive): Allies within 2 hexes get +2 resistance.<br>**Poise** (reactive): When you avoid an attack, +1 willpower for the rest of the battle (up to +3). | **Tidal Tiara** (water): Your water casts also lay 1 water step on the ring of tiles around the target.<br>**Frozen Tiara** (ice): Your ice locks (glazes) last 1 turn longer.<br>**Stormcaller's Tiara** (thunder): Your thunder deals 20% more damage.<br>**Lingering Tiara** (wind): Tiles copied by your gales last 1 turn longer.<br>**Abyssal Tiara** (dark): Your dark casts push the tile 1 extra step darker (still capped at -3).<br>**Radiant Tiara** (light): Your light tiles are 50% stronger: more healing and more exposure.<br>**Hallowed Tiara** (light): Light tiles you lay last 1 turn longer. |
| Crown | wizard | wil, con | **Royal Presence** (supportive): Allies within 2 hexes deal 10% more damage.<br>**Heavy Is the Head** (reactive): When an ally is knocked out, +2 willpower and +2 resistance for the rest of the battle (up to +6 each). | **Smouldering Crown** (fire): Fire tiles you lay last 1 turn longer before they start to cool.<br>**Brimming Crown** (water): Your water tiles are 50% stronger: wading costs more and thunder gets +50% of the water bonus when it detonates them.<br>**Frozen Crown** (ice): Your ice locks (glazes) last 1 turn longer.<br>**Shattering Crown** (ice): When thunder shatters a lock you made, the shatter multiplier is x2 instead of x1.5.<br>**Thundering Crown** (thunder): Your thunder effects trigger twice; the second resolves at 50%.<br>**Howling Crown** (wind): Your gales push everyone on the spread tiles 1 hex outward.<br>**Abyssal Crown** (dark): Your dark casts push the tile 1 extra step darker (still capped at -3).<br>**Collapsing Crown** (dark): Dark tiles you lay collapse 1 turn later: 2 damage per dark point to the occupant, and neighbours are pulled 1 hex in.<br>**Radiant Crown** (light): Your light tiles are 50% stronger: more healing and more exposure. |
| Dragoon Helm | heavy | str, def | **Leap Ready** (passive): +1 move.<br>**Dragoon's Descent** (passive): +10% damage for each level of elevation you stand above your target. | **Explosive Dragoon Helm** (fire): Fire tiles you lay erupt 1 turn later: 3 damage per fire point to everyone on the tile and its neighbours, then the tile goes neutral.<br>**Blazing Dragoon Helm** (fire): +10% strength per fire point on the tile you stand on (at least +1 per point).<br>**Shattering Dragoon Helm** (ice): When thunder shatters a lock you made, the shatter multiplier is x2 instead of x1.5.<br>**Thundering Dragoon Helm** (thunder): Your thunder effects trigger twice; the second resolves at 50%.<br>**Gloaming Dragoon Helm** (dark): Your dark tiles hide their occupant 50% better.<br>**Dawning Dragoon Helm** (light): Your light casts push the tile 1 extra step brighter (still capped at +3). |

### Chest

| Item | Weight | Stats | Abilities (learned after 2 battles) | Enchantments it can roll |
|---|---|---|---|---|
| Single Shoulder Guard | ranger | def, dex | **Shoulder Check** (passive): +5% glance chance against melee attacks.<br>**Brace** (reactive): When you take damage, +1 defense for the rest of the battle (up to +3). | **Geyser Single Shoulder Guard** (water): Water tiles you lay erupt 1 turn later: 2% max HP per water point, everyone on the tile is pushed 1 hex out, and the tile keeps its water.<br>**Frostbitten Single Shoulder Guard** (ice): Your basic attacks have a 50% chance to lock the target's tile.<br>**Arcing Single Shoulder Guard** (thunder): Your detonations splash 2 rings out instead of 1.<br>**Static Single Shoulder Guard** (thunder): When an adjacent enemy strikes you, thunder lands on its tile (detonating any charge there).<br>**Windbreak Single Shoulder Guard** (wind): Take 20% less wind damage.<br>**Nightforged Single Shoulder Guard** (dark): Take 20% less dark damage.<br>**Gleaming Single Shoulder Guard** (light): When you are struck, the attacker's tile gains 1 light step (exposing it). |
| Vest | ranger | dex, spd | **Nimble Strength** (passive): Add 25% of your strength to your dexterity.<br>**Second Wind** (reactive): The first time you fall below half HP, +2 speed for the rest of the battle. | **Emberstep Vest** (fire): Every tile you leave while moving gains 1 fire step.<br>**Wading Vest** (water): Water tiles never slow you.<br>**Riptide Vest** (water): +10% dexterity per water point on the tile you stand on (at least +1 per point).<br>**Geyser Vest** (water): Water tiles you lay erupt 1 turn later: 2% max HP per water point, everyone on the tile is pushed 1 hex out, and the tile keeps its water.<br>**Jolting Vest** (thunder): Your detonations knock whoever stands on the tile 1 hex away from you.<br>**Lingering Vest** (wind): Tiles copied by your gales last 1 turn longer.<br>**Shrouded Vest** (dark): +10% speed per dark point on the tile you stand on (at least +1 per point). |
| Chain Mail | heavy | def, con | **Woven Rings** (passive): Double your glancing damage reduction: glances against you deal 25% instead of 50%.<br>**Ring Guard** (supportive): Allies next to you get +5% glance chance. | **Fireproof Chain Mail** (fire): Take 20% less fire damage and half damage from burning tiles.<br>**Soaking Chain Mail** (water): When you are struck, the attacker's tile gains 1 water step (primed for thunder).<br>**Glacial Chain Mail** (ice): Your ice also locks the 6 tiles around the one you target.<br>**Rimed Chain Mail** (ice): +20% defense (at least +2) while you stand on a locked (glazed) tile.<br>**Grounded Chain Mail** (thunder): Take 20% less thunder damage and half damage from detonations you stand in.<br>**Hallowed Chain Mail** (light): Light tiles you lay last 1 turn longer. |
| Platemail | heavy | def, str, con | **Bastion** (passive): Double your glance chance.<br>**Guardian** (supportive): Allies next to you get +2 defense.<br>**Unbowed** (passive): You cannot be knocked back, pulled or shoved. | **Smouldering Platemail** (fire): Fire tiles you lay last 1 turn longer before they start to cool.<br>**Fireproof Platemail** (fire): Take 20% less fire damage and half damage from burning tiles.<br>**Frozen Platemail** (ice): Your ice locks (glazes) last 1 turn longer.<br>**Rimed Platemail** (ice): +20% defense (at least +2) while you stand on a locked (glazed) tile.<br>**Arcing Platemail** (thunder): Your detonations splash 2 rings out instead of 1.<br>**Nightforged Platemail** (dark): Take 20% less dark damage.<br>**Hallowed Platemail** (light): Light tiles you lay last 1 turn longer.<br>**Gleaming Platemail** (light): When you are struck, the attacker's tile gains 1 light step (exposing it). |
| Silken Robe | wizard | wil, res | **Ward** (reactive): When you take damage, +1 willpower and +1 resistance for the rest of the battle (up to +5 each).<br>**Insight** (passive): Add 25% of your willpower to your resistance.<br>**Mana Veil** (supportive): Allies next to you get +5% resist chance. | **Kindled Silken Robe** (fire): Your fire casts push the tile 1 extra step hotter (still capped at +3).<br>**Tidal Silken Robe** (water): Your water casts also lay 1 water step on the ring of tiles around the target.<br>**Brimming Silken Robe** (water): Your water tiles are 50% stronger: wading costs more and thunder gets +50% of the water bonus when it detonates them.<br>**Glacial Silken Robe** (ice): Your ice also locks the 6 tiles around the one you target.<br>**Stormcaller's Silken Robe** (thunder): Your thunder deals 20% more damage.<br>**Umbral Silken Robe** (dark): Dark tiles you lay last 1 turn longer.<br>**Radiant Silken Robe** (light): Your light tiles are 50% stronger: more healing and more exposure.<br>**Sunlit Silken Robe** (light): +10% willpower per light point on the tile you stand on (at least +1 per point). |
| Leather Cuirass | ranger | dex, def | **Supple** (passive): +5% avoid.<br>**Scout's Lead** (supportive): Allies within 2 hexes get +1 speed. | **Smouldering Leather Cuirass** (fire): Fire tiles you lay last 1 turn longer before they start to cool.<br>**Soaking Leather Cuirass** (water): When you are struck, the attacker's tile gains 1 water step (primed for thunder).<br>**Grounded Leather Cuirass** (thunder): Take 20% less thunder damage and half damage from detonations you stand in.<br>**Whistling Leather Cuirass** (wind): +1 extra wind affinity point every time you use wind.<br>**Windbreak Leather Cuirass** (wind): Take 20% less wind damage.<br>**Umbral Leather Cuirass** (dark): Dark tiles you lay last 1 turn longer.<br>**Shadowtrail Leather Cuirass** (dark): Every tile you leave while moving gains 1 dark step. |
| Brigandine | heavy | str, def | **Steel Under Cloth** (passive): Add 25% of your dexterity to your strength.<br>**Hardened** (passive): Take 10% less damage from weapon skills. | **Blazing Brigandine** (fire): +10% strength per fire point on the tile you stand on (at least +1 per point).<br>**Soaking Brigandine** (water): When you are struck, the attacker's tile gains 1 water step (primed for thunder).<br>**Frozen Brigandine** (ice): Your ice locks (glazes) last 1 turn longer.<br>**Jolting Brigandine** (thunder): Your detonations knock whoever stands on the tile 1 hex away from you.<br>**Nightforged Brigandine** (dark): Take 20% less dark damage.<br>**Gleaming Brigandine** (light): When you are struck, the attacker's tile gains 1 light step (exposing it). |
| Scarf | wizard | res, spd | **Flutter** (passive): +1 move.<br>**Keep Warm** (supportive): Allies next to you get +2 resistance. | **Kindled Scarf** (fire): Your fire casts push the tile 1 extra step hotter (still capped at +3).<br>**Tidal Scarf** (water): Your water casts also lay 1 water step on the ring of tiles around the target.<br>**Frozen Scarf** (ice): Your ice locks (glazes) last 1 turn longer.<br>**Frostbitten Scarf** (ice): Your basic attacks have a 50% chance to lock the target's tile.<br>**Gusting Scarf** (wind): Your gales copy the tile 2 rings out instead of 1.<br>**Windbreak Scarf** (wind): Take 20% less wind damage.<br>**Abyssal Scarf** (dark): Your dark casts push the tile 1 extra step darker (still capped at -3).<br>**Flaring Scarf** (light): Light tiles you lay flare 1 turn later: allies on the tile and its neighbours heal 2 per light point, then the tile goes neutral. |
| Bandolier | ranger | dex, spd | **Quick Draw** (passive): Once per battle, a weapon skill comes back 1 turn early.<br>**Ammo Belt** (passive): +1 range with bows and pistols. | **Explosive Bandolier** (fire): Fire tiles you lay erupt 1 turn later: 3 damage per fire point to everyone on the tile and its neighbours, then the tile goes neutral.<br>**Deepwater Bandolier** (water): Water tiles you lay last 1 turn longer.<br>**Geyser Bandolier** (water): Water tiles you lay erupt 1 turn later: 2% max HP per water point, everyone on the tile is pushed 1 hex out, and the tile keeps its water.<br>**Arcing Bandolier** (thunder): Your detonations splash 2 rings out instead of 1.<br>**Howling Bandolier** (wind): Your gales push everyone on the spread tiles 1 hex outward.<br>**Shrouded Bandolier** (dark): +10% speed per dark point on the tile you stand on (at least +1 per point). |
| Gladiator Chestpiece | heavy | str, con | **Crowd Pleaser** (reactive): When you knock out an enemy, +2 strength and +2 defense for the rest of the battle (up to +6 each).<br>**Arena Born** (passive): +5% critical chance. | **Explosive Gladiator Chestpiece** (fire): Fire tiles you lay erupt 1 turn later: 3 damage per fire point to everyone on the tile and its neighbours, then the tile goes neutral.<br>**Kindled Gladiator Chestpiece** (fire): Your fire casts push the tile 1 extra step hotter (still capped at +3).<br>**Blazing Gladiator Chestpiece** (fire): +10% strength per fire point on the tile you stand on (at least +1 per point).<br>**Shattering Gladiator Chestpiece** (ice): When thunder shatters a lock you made, the shatter multiplier is x2 instead of x1.5.<br>**Thundering Gladiator Chestpiece** (thunder): Your thunder effects trigger twice; the second resolves at 50%.<br>**Jolting Gladiator Chestpiece** (thunder): Your detonations knock whoever stands on the tile 1 hex away from you.<br>**Dawning Gladiator Chestpiece** (light): Your light casts push the tile 1 extra step brighter (still capped at +3).<br>**Gleaming Gladiator Chestpiece** (light): When you are struck, the attacker's tile gains 1 light step (exposing it). |

### Legs

| Item | Weight | Stats | Abilities (learned after 2 battles) | Enchantments it can roll |
|---|---|---|---|---|
| Chaps | ranger | dex, spd | **Light Footed** (reactive): When you take damage, +1 dexterity and +1 speed for the rest of the battle (up to +5 each).<br>**Sure Stride** (passive): Muddy ground costs normal movement. | **Explosive Chaps** (fire): Fire tiles you lay erupt 1 turn later: 3 damage per fire point to everyone on the tile and its neighbours, then the tile goes neutral.<br>**Emberstep Chaps** (fire): Every tile you leave while moving gains 1 fire step.<br>**Wading Chaps** (water): Water tiles never slow you.<br>**Grounded Chaps** (thunder): Take 20% less thunder damage and half damage from detonations you stand in.<br>**Gusting Chaps** (wind): Your gales copy the tile 2 rings out instead of 1.<br>**Shadowtrail Chaps** (dark): Every tile you leave while moving gains 1 dark step. |
| Platelegs | heavy | def, res | **Iron Wall** (reactive): When you take damage, +1 defense and +1 resistance for the rest of the battle (up to +5 each).<br>**Rooted** (passive): You cannot be knocked back, pulled or shoved. | **Explosive Platelegs** (fire): Fire tiles you lay erupt 1 turn later: 3 damage per fire point to everyone on the tile and its neighbours, then the tile goes neutral.<br>**Fireproof Platelegs** (fire): Take 20% less fire damage and half damage from burning tiles.<br>**Soaking Platelegs** (water): When you are struck, the attacker's tile gains 1 water step (primed for thunder).<br>**Glacial Platelegs** (ice): Your ice also locks the 6 tiles around the one you target.<br>**Static Platelegs** (thunder): When an adjacent enemy strikes you, thunder lands on its tile (detonating any charge there).<br>**Windbreak Platelegs** (wind): Take 20% less wind damage.<br>**Nightforged Platelegs** (dark): Take 20% less dark damage.<br>**Gleaming Platelegs** (light): When you are struck, the attacker's tile gains 1 light step (exposing it). |
| Leather Tassets | heavy | str, def | **Enrage** (reactive): When you take damage, +1 strength and +1 defense for the rest of the battle (up to +5 each).<br>**Bloodied** (reactive): The first time you fall below half HP, +3 strength for the rest of the battle. | **Fireproof Leather Tassets** (fire): Take 20% less fire damage and half damage from burning tiles.<br>**Blazing Leather Tassets** (fire): +10% strength per fire point on the tile you stand on (at least +1 per point).<br>**Deepwater Leather Tassets** (water): Water tiles you lay last 1 turn longer.<br>**Rimed Leather Tassets** (ice): +20% defense (at least +2) while you stand on a locked (glazed) tile.<br>**Grounded Leather Tassets** (thunder): Take 20% less thunder damage and half damage from detonations you stand in.<br>**Collapsing Leather Tassets** (dark): Dark tiles you lay collapse 1 turn later: 2 damage per dark point to the occupant, and neighbours are pulled 1 hex in.<br>**Sunlit Leather Tassets** (light): +10% willpower per light point on the tile you stand on (at least +1 per point). |
| Robe Bottoms | wizard | wil, res | **Ward** (reactive): When you take damage, +1 willpower and +1 resistance for the rest of the battle (up to +5 each).<br>**Insight** (passive): Add 25% of your willpower to your resistance.<br>**Drift** (passive): Water tiles never slow you. | **Kindled Robe Bottoms** (fire): Your fire casts push the tile 1 extra step hotter (still capped at +3).<br>**Tidal Robe Bottoms** (water): Your water casts also lay 1 water step on the ring of tiles around the target.<br>**Wading Robe Bottoms** (water): Water tiles never slow you.<br>**Stormcaller's Robe Bottoms** (thunder): Your thunder deals 20% more damage.<br>**Howling Robe Bottoms** (wind): Your gales push everyone on the spread tiles 1 hex outward.<br>**Umbral Robe Bottoms** (dark): Dark tiles you lay last 1 turn longer.<br>**Collapsing Robe Bottoms** (dark): Dark tiles you lay collapse 1 turn later: 2 damage per dark point to the occupant, and neighbours are pulled 1 hex in.<br>**Radiant Robe Bottoms** (light): Your light tiles are 50% stronger: more healing and more exposure.<br>**Flaring Robe Bottoms** (light): Light tiles you lay flare 1 turn later: allies on the tile and its neighbours heal 2 per light point, then the tile goes neutral. |
| Tights | ranger | spd, dex | **Acrobat** (passive): +5% avoid.<br>**Tumble** (reactive): When you avoid an attack, +1 speed for the rest of the battle (up to +3). | **Smouldering Tights** (fire): Fire tiles you lay last 1 turn longer before they start to cool.<br>**Emberstep Tights** (fire): Every tile you leave while moving gains 1 fire step.<br>**Wading Tights** (water): Water tiles never slow you.<br>**Riptide Tights** (water): +10% dexterity per water point on the tile you stand on (at least +1 per point).<br>**Frostbitten Tights** (ice): Your basic attacks have a 50% chance to lock the target's tile.<br>**Gusting Tights** (wind): Your gales copy the tile 2 rings out instead of 1.<br>**Whistling Tights** (wind): +1 extra wind affinity point every time you use wind.<br>**Shrouded Tights** (dark): +10% speed per dark point on the tile you stand on (at least +1 per point). |

### Main hand

| Weapon | Class | Stats | Enchantments it can roll |
|---|---|---|---|
| Sword | sword | str, spd | **Sword of Piercing Strikes**: Basic attack range is doubled.<br>**Riposting Sword**: Once per enemy turn, when an adjacent enemy attacks you, strike back for 50%.<br>**Guarding Sword**: After you attack, take 25% less damage until your next turn. |
| Scimitar | sword | str, dex | **Doubleshot Scimitar**: Every basic attack hits twice at 75% damage each.<br>**Flowing Scimitar**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Riposting Scimitar**: Once per enemy turn, when an adjacent enemy attacks you, strike back for 50%.<br>**Keen Scimitar**: +10% critical chance. |
| Flamberge | sword | str, con | **Flamberge of Cleaving**: Basic attacks and AoE skills reach 1 ring further. Allies in the added ring are spared.<br>**Riposting Flamberge**: Once per enemy turn, when an adjacent enemy attacks you, strike back for 50%.<br>**Serrated Flamberge**: Critical hits deal x2 instead of x1.5.<br>**Sundering Flamberge**: Attacks ignore 25% of the target's defense. |
| Axe | axe | str, con | **Axe of Cleaving**: Basic attacks and AoE skills reach 1 ring further. Allies in the added ring are spared.<br>**Axe of Impact**: Basic attacks knock the target 1 hex straight back.<br>**Sundering Axe**: Attacks ignore 25% of the target's defense. |
| Double Axe | axe | str, def | **Double Axe of Cleaving**: Basic attacks and AoE skills reach 1 ring further. Allies in the added ring are spared.<br>**Double Axe of Impact**: Basic attacks knock the target 1 hex straight back.<br>**Jousting Double Axe**: +10% damage for each hex moved this turn before attacking, up to +40%. |
| Hatchet | axe | str, spd | **Flowing Hatchet**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Quickdraw Hatchet**: Weapon skills recover 1 turn faster.<br>**Throwing Hatchet**: Basic attack can be thrown up to 2 extra hexes away for 75% damage. |
| Warhammer | axe | str, def | **Warhammer of Cleaving**: Basic attacks and AoE skills reach 1 ring further. Allies in the added ring are spared.<br>**Warhammer of Impact**: Basic attacks knock the target 1 hex straight back.<br>**Sundering Warhammer**: Attacks ignore 25% of the target's defense.<br>**Guarding Warhammer**: After you attack, take 25% less damage until your next turn. |
| Anchor | axe | str, con | **Anchor of Impact**: Basic attacks knock the target 1 hex straight back.<br>**Hooking Anchor**: Basic attacks drag the target 1 hex toward you.<br>**Jousting Anchor**: +10% damage for each hex moved this turn before attacking, up to +40%.<br>**Throwing Anchor**: Basic attack can be thrown up to 2 extra hexes away for 75% damage.<br>**Guarding Anchor**: After you attack, take 25% less damage until your next turn. |
| Lance | lance | str, def | **Lance of Piercing Strikes**: Basic attack range is doubled.<br>**Flowing Lance**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Jousting Lance**: +10% damage for each hex moved this turn before attacking, up to +40%.<br>**Lancing Lance**: Attacks pass through: the first unit behind the target in the same line takes 75%. |
| Javelin | lance | str, dex | **Javelin of Piercing Strikes**: Basic attack range is doubled.<br>**Flowing Javelin**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Jousting Javelin**: +10% damage for each hex moved this turn before attacking, up to +40%.<br>**Throwing Javelin**: Basic attack can be thrown up to 2 extra hexes away for 75% damage.<br>**Lancing Javelin**: Attacks pass through: the first unit behind the target in the same line takes 75%. |
| Halberd | lance | str, def | **Halberd of Cleaving**: Basic attacks and AoE skills reach 1 ring further. Allies in the added ring are spared.<br>**Halberd of Impact**: Basic attacks knock the target 1 hex straight back.<br>**Hooking Halberd**: Basic attacks drag the target 1 hex toward you.<br>**Riposting Halberd**: Once per enemy turn, when an adjacent enemy attacks you, strike back for 50%.<br>**Guarding Halberd**: After you attack, take 25% less damage until your next turn. |
| Glaive | lance | str, spd | **Glaive of Cleaving**: Basic attacks and AoE skills reach 1 ring further. Allies in the added ring are spared.<br>**Flowing Glaive**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Hooking Glaive**: Basic attacks drag the target 1 hex toward you.<br>**Conducting Glaive**: +25% damage against targets standing on charged tiles. |
| Dagger | daggers | dex, spd | **Doubleshot Dagger**: Every basic attack hits twice at 75% damage each.<br>**Flowing Dagger**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Keen Dagger**: +10% critical chance.<br>**Quickdraw Dagger**: Weapon skills recover 1 turn faster.<br>**Throwing Dagger**: Basic attack can be thrown up to 2 extra hexes away for 75% damage. |
| Jagged Dagger | daggers | dex, str | **Doubleshot Jagged Dagger**: Every basic attack hits twice at 75% damage each.<br>**Riposting Jagged Dagger**: Once per enemy turn, when an adjacent enemy attacks you, strike back for 50%.<br>**Keen Jagged Dagger**: +10% critical chance.<br>**Serrated Jagged Dagger**: Critical hits deal x2 instead of x1.5. |
| Shortbow | bow | dex, spd | **Spreadshot Shortbow**: Fires 3 shots along 3 different lines, 50% damage each.<br>**Flowing Shortbow**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Quickdraw Shortbow**: Weapon skills recover 1 turn faster. |
| Recurve Bow | bow | dex, str | **Doubleshot Recurve Bow**: Every basic attack hits twice at 75% damage each.<br>**Longshot Recurve Bow**: +2 range.<br>**Conducting Recurve Bow**: +25% damage against targets standing on charged tiles. |
| Compound Bow | bow | dex, def | **Doubleshot Compound Bow**: Every basic attack hits twice at 75% damage each.<br>**Keen Compound Bow**: +10% critical chance.<br>**Longshot Compound Bow**: +2 range.<br>**Lancing Compound Bow**: Attacks pass through: the first unit behind the target in the same line takes 75%. |
| Pistol | pistols | dex, spd | **Doubleshot Pistol**: Every basic attack hits twice at 75% damage each.<br>**Quickdraw Pistol**: Weapon skills recover 1 turn faster.<br>**Conducting Pistol**: +25% damage against targets standing on charged tiles. |
| Flintlock | pistols | dex, str | **Spreadshot Flintlock**: Fires 3 shots along 3 different lines, 50% damage each.<br>**Longshot Flintlock**: +2 range.<br>**Quickdraw Flintlock**: Weapon skills recover 1 turn faster. |
| M1911 | pistols | dex, def | **Doubleshot M1911**: Every basic attack hits twice at 75% damage each.<br>**Keen M1911**: +10% critical chance.<br>**Sundering M1911**: Attacks ignore 25% of the target's defense.<br>**Quickdraw M1911**: Weapon skills recover 1 turn faster.<br>**Lancing M1911**: Attacks pass through: the first unit behind the target in the same line takes 75%. |
| Staff | staff | wil, res | **Flowing Staff**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Staff of Impact**: Basic attacks knock the target 1 hex straight back.<br>**Guarding Staff**: After you attack, take 25% less damage until your next turn.<br>**Conducting Staff**: +25% damage against targets standing on charged tiles.<br>**Channelling Staff**: Spell AoEs reach 1 ring further (basic attack unchanged). |
| Hand Wraps | fists | str, spd | **Flowing Hand Wraps**: After attacking you may move up to 2 more hexes, even if you moved before attacking.<br>**Keen Hand Wraps**: +10% critical chance.<br>**Quickdraw Hand Wraps**: Weapon skills recover 1 turn faster.<br>**Pummeling Hand Wraps**: Flurry lands 4 strikes instead of 3.<br>**Welling Hand Wraps**: Palm Burst pours 3 steps of your element instead of 2. |
| Brass Knuckles | fists | str, dex | **Doubleshot Brass Knuckles**: Every basic attack hits twice at 75% damage each.<br>**Keen Brass Knuckles**: +10% critical chance.<br>**Serrated Brass Knuckles**: Critical hits deal x2 instead of x1.5.<br>**Sundering Brass Knuckles**: Attacks ignore 25% of the target's defense.<br>**Pummeling Brass Knuckles**: Flurry lands 4 strikes instead of 3.<br>**Brass Knuckles of the Rebound**: Uppercut knocks the target 2 hexes back (and slams if anything stops it on the way). |
| Gauntlets | fists | str, def | **Gauntlets of Impact**: Basic attacks knock the target 1 hex straight back.<br>**Sundering Gauntlets**: Attacks ignore 25% of the target's defense.<br>**Guarding Gauntlets**: After you attack, take 25% less damage until your next turn.<br>**Gauntlets of the Rebound**: Uppercut knocks the target 2 hexes back.<br>**Welling Gauntlets**: Palm Burst pours 3 steps of your element instead of 2. |
| Moon Staff | staff | wil, spd | **Longshot Moon Staff**: +2 range.<br>**Guarding Moon Staff**: After you attack, take 25% less damage until your next turn.<br>**Conducting Moon Staff**: +25% damage against targets standing on charged tiles.<br>**Channelling Moon Staff**: Spell AoEs reach 1 ring further (basic attack unchanged). |

### 2.1 Two weapons and imbues (D180-D183)

- **Second weapon.** Beside Main hand every unit has a **Second weapon** slot.
  The carried weapon gives no stats and no enchantment until drawn; it is
  slung on the model (swords and axes hilt-up over a shoulder, lances, staves
  and bows across the back, pistols and daggers at the hip).
- **Swap weapon** (combat menu, directly under Attack): free and unlimited
  (swap back and forth as you like, D195), spends neither the action nor the move. The class, range, damage, passive
  and skill bar follow the drawn weapon; each class keeps its own loadout
  (3, staff 4); cooldowns are per skill and carry over. The AI swaps when the
  other weapon's best option this turn scores 10% better (it weighs this once,
  at the start of its turn). On the board the swap is a ~0.5 s animation: the
  arm reaches back, the weapon in hand travels to its carry spot, the other
  travels from its carry spot into the hand; a small white tag names the class.
  Out of battle, the gear panel's Swap button does the same.
- **Enemies** carry a second weapon from fight 3 (D193): a random other
  class, at the same tier and expertise as the main one, so the AI swaps too.
- **Imbue.** A tier C+ weapon carries one of the seven elements. Its basic
  attacks carry that element (affinity damage if the wielder has it, Spark,
  conduction, braces) and paint it on the target's hex, hit or miss, like the
  staff's Channel; skills are unchanged and the attunement doesn't move.
  Name: "Fire Flamberge of Cleaving", "Keen Ice Dagger".

### Fists (D76)

A new weapon class, the daggers' counterpart: blunt and elemental, fast and
up close. Class row: martial (STR), Jab 8, range 1, speed +2, move +1,
levels STR. Anyone can wear fists of any tier (D180). The roster's
starting weapons are unchanged; fists come from loot and the shop (they are
ordinary main_hand rows), and a recruit brings a spare tier-E pair into the
inventory.

| Skill | Shape | Numbers |
|---|---|---|
| **Flurry** | adjacent enemy; the last strike lays the chosen element (1 step) on its hex | skill 12 × 45% per strike, 3 strikes (1.35 blows), each rolled; cd 2 per element |
| **Uppercut** | adjacent enemy, no element; knocks it 1 hex straight back (secondary: an avoid still pushes, a resist stops it) | skill 12; **+50% slam** if jagged ground, a rise too steep, or a unit stops the push. The map edge is open air and an immune target braced: no slam. cd 2 |
| **Palm Burst** | adjacent enemy; pours **2 steps** of the element into its hex (a melee Saturate, thunder bait) | skill 9; cd 2 per element |

The three new enchantments ride existing keys with a `skill=` param (§1):
Pummeling (`multi_hit`), Rebound (`knockback`), Welling (`cast_step_plus`).
Every fists item rolls 5–6 enchantments.

## 3. The elemental colour variants

The brief asks for 7 colour variants per armour piece ("Feathered Cap of
Fire", "of Water", ...). These are a naming and visual layer, not 7 rows of
data:

- **The colour follows the enchantment.** An armour piece shows the model
  variant for its enchantment's `element`. A Frozen Brigandine uses the
  `brigandine_ice` model (ice-blue cloth cover). Each `notes` cell in
  `equipment.csv` says which part of the model carries the colour.
- **Superseded by D54:** there is one model per item (`art/equipment/<item_id>.glb`), and the element variant is its accent tinted at runtime. The original note: model id was `{item_id}_{element}` (e.g. `feathered_cap_fire`). The
  **asset name** for the modelling lane is "{Item} of {Element}" (Feathered
  Cap of Fire), as the brief wrote it. The **in-game name** is the
  enchantment's `name_pattern` with `{item}` filled in ("Explosive Chaps").
- An unenchanted piece shows the plain grayscale model.
- Not every item can *roll* every element, but a shop scroll (§6) can put any
  element row onto any armour piece, so all 7 models per item can appear.
- Weapons have no element column. Below tier C they stay grayscale and take the
  wielder's element as an aura in combat, as the brief describes; an imbued
  weapon (D182) shows its imbue on its accent (edges, gems, a bow's fletching).

## 4. Tiers and stat rolls (from SCHEMA.md)

| Tier | Each stat line rolls | Drops after fight |
|---|---|---|
| E | +0 – +3 | 1–2 |
| D | +1 – +6 | 3–4 |
| C | +2 – +9 | 5–6 |
| B | +3 – +12 | 7–8 |
| A | +4 – +15 | 9–10 |

- Each entry in an item's `stat_lines` rolls independently inside the tier's
  range. Platemail has three lines; everything else has two.
- Every dropped piece also rolls one enchantment from the rows whose
  `applies_to` names it **and whose `tier` is at or below the item's** (D200).
  Rows at the item's own tier (D and up) weigh ×2; cursed rows weigh the same
  as the rest. Tiers unlock rows; they never scale an enchantment's numbers.
- **Anyone can equip any weapon (D180).** The old rule (expertise at the item's
  tier) is gone; expertise still sets hit chance and the class's skill picks.
- **C, B and A weapons roll their weapon enchantment plus an imbue (D182,
  D206):** an element and one element row of it (`imbue_enchant`), which works
  only while the weapon is drawn. E and D keep one; a scroll can add the imbue.
- **Hone** (downtime "Improve your equipment") is suggested as +1 to one stat
  line, never above the tier's top. The brief doesn't settle it.

## 5. Level-up bias (from the brief, with D15)

Each level, every stat gains 1. The stats named by the bias below gain 2
instead.

| Equipped | Stat that gains +2 |
|---|---|
| sword, axe, lance (martial) | str |
| daggers, bow, pistols (dexterous) | dex |
| staff (spell) | wil |
| 2 or more heavy armour pieces | def |
| 2 or more ranger armour pieces | spd |
| 2 or more wizard armour pieces | res |
| anything else | no armour bias; every stat +1 |

With three armour slots, at most one armour weight can reach 2 pieces, so a
unit gets at most two biased stats per level (one from the weapon, one from
armour). The bias stays invisible to the player, per the brief.

## 6. Shop and scrolls (D203)

- **Stock:** each visit offers 1 head, 1 chest, 1 legs piece and 2 weapons at
  your current tier. Trade 1 loose item for 1 of them; what you give joins the
  stock. There is no currency. The stock rerolls after every battle.
- **Imbuement scrolls (featured):** seven, one per element. Each holds one
  element row (`element` = that element) unlocked at the shop's tier, with the
  D200 weights; the cursed element rows can appear. They re-roll after every
  battle, from their own rng (run seed, fight, element).
  - A scroll costs **2 loose items**, which are gone. Pick the two, then the
    item it goes on: any item the squad owns, worn or loose (not one you pay
    with). It's used at once; the scroll is then spent until the re-roll.
  - **Armour:** the scroll overwrites its enchantment (the old one is lost).
    Any armour piece takes any element row, and the model recolours.
  - **A weapon (D206):** the scroll sets its **imbue** to the scroll's
    element **and** its row (the imbue's enchantment), replacing any old
    imbue, at any tier (an E/D weapon gains one). The weapon's own
    enchantment stays (D38).
- **Re-imbue is gone** (D202). Imbues (D182) are rolled with the weapon; only
  a scroll changes one.
- **Abilities:** a unit learns every ability on a piece after wearing it for 2
  battles, and keeps them after taking the piece off. A unit equips at most one
  reactive, one supportive and one passive at a time (my reading of "can only
  equip one type at a time").

## 7. Decisions I made

Overturn any of these freely.

1. **Params are `name=value;name=value`**, with `+` joining stat lists, so CSV
   list cells (`|`) and param cells never collide.
2. **25 keys.** Abilities reuse enchantment keys wherever possible, so the
   whole system is 25 implementations.
3. **Colour follows enchantment.** "Feathered Cap of Fire" is the fire-coloured
   model, and it's the one you see whenever the cap carries a fire enchantment.
4. **Armour weights:** the single shoulder guard is ranger (one pauldron, not
   a suit). The crown is wizard (it commands rather than protects). Leather
   tassets are heavy, because Enrage is a str/def ability. The scarf is wizard.
5. **The brief's "full helm" is the feathered full helm**, and "robes" covers
   both the silken robe and the robe bottoms. Both teach Ward and the new robe
   passive, Insight.
6. **Robe passive (blank in the brief): Insight.** Add 25% of willpower to
   resistance, matching the brigandine and vest pattern.
7. **Unflinching (blank in the brief):** you and adjacent allies can't be
   displaced. It's supportive, so it covers neighbours.
8. **Reactive stacking caps at +5** per stat. The brief says "for the rest of
   battle when taking damage" with no cap; uncapped, a tank hit 15 times gains
   +15 in two stats.
9. **Woven Rings (chainmail) caps the glance reduction at 75%.** Doubling the
   brief's 50% literally gives 100%, so every glance would deal 0.
10. **Thundering's second trigger is at 50%.** The brief says "trigger twice";
    a full second detonation would double thunder's damage outright.
11. **Doubleshot "longbow" goes on the recurve and compound bows**, since there
    is no longbow model.
12. **Flowing is a second move.** The base rules already allow act-then-move,
    so "can move after attacking" only adds something if you moved first. It
    is capped at 2 hexes.
13. **Cleaving keeps 100% damage on the added ring**, as written, but spares
    allies.
14. **Deadeye stays "supportive"** as the brief labels it, though it only helps
    the wearer.
15. **Weapons teach no abilities.** Weapon progress is expertise and skills;
    abilities come from armour, so `ability_id` is blank on weapons.
16. **Every stat +1 per level, biased stats +2** is my reading of "1–2 per
    level".

## 8. Flags: what depends on unsettled rules

ELEMENTS.md is being written in parallel. These rows lean on rules it has to
settle:

- **Tile ownership.** "Your fire tiles" (most armour keys) needs each tile's
  charge to remember the unit that last laid it. If tiles stay anonymous, these
  keys must instead read "tiles laid by anyone on your side".
- **Durations.** `tile_duration_plus` assumes V8's model: 3 turns, then decay
  one step inward, and an ice lock of 2 cycles. If ELEMENTS.md changes the
  clock, `turns=1` still reads, but the feel changes.
- **Ice's shatter multiplier** (Shattering, `pct=33` to turn ×1.5 into ×2) and
  **water's detonation bonus** (Brimming, Soaking) assume V8's thunder
  formula: 4 + 3 × charge, +2 per water point, ×1.5 if glazed.
- **Operator markers.** Frostbitten and Static land ice or thunder on empty
  tiles, which in V8 arms a marker rather than doing nothing. If markers are
  dropped, those enchantments fizzle on neutral ground.
- **Thunder triggering twice vs. the ground being spent.** Thundering assumes
  both resolutions happen before the tile is set to neutral.
- **Tile erupt** (Explosive, Geyser, Collapsing, Flaring) is new: a delayed
  timer on a tile. Explosive is the brief's own example, so this is wanted, but
  it needs a place in the tile tick.
- **Light healing** (Radiant, Flaring) follows D10: light heals.
- **Elevation** (Dragoon's Descent) assumes the maps' elevation affects
  combat. Nothing yet says it does.
- **Staff skills** aren't written yet; Channelling rides on whatever AoE they
  have.

### 8.1 Resolved in code (`src/core/effects.gd`, 2026-10-04)

ELEMENTS.md has since settled tile ownership (`source`), durations (2-cycle
steps, 2-cycle glaze), V8's thunder formula in % HP, and markers. All 25 keys
are implemented against those rules. Every flag above is settled; the
calls below are open to overturn.

**Flat damage → % max HP (D33, E2).** Rows keep their flat numbers in
`enchantments.csv`; `BWEffects.make()` converts at V8's own ratio, the one
ELEMENTS §10 used for fire and detonations (flat 3 per point → 4% per point),
so ×4/3, rounded to a whole percent. A row may set `dmg_pct_per_point` /
`heal_pct_per_point` directly to override.

| Enchantment | CSV param | In play |
|---|---|---|
| Explosive | `dmg_per_point=3` | 4% max HP per fire point |
| Collapsing | `dmg_per_point=2` | 3% per dark point |
| Geyser | `dmg_pct_per_point=2` (D196) | 2% per water point |
| Flaring | `heal_per_point=2` | 3% heal per light point (same as `LIGHT_HEAL_PCT`) |

Eruption damage uses the tile's element for resistance (§8.2 of ELEMENTS) and
damage_taken_mod `tile_pct` (Fireproof halves an Explosive blast).

**Interpretations.**

- *Sleeping:* an element-tagged enchantment does nothing until its wearer has
  rank ≥ 1 in that element; `damage_taken_mod` and `immune` always work.
- *tile_erupt:* the countdown is stamped on every hex the cast leaves carrying
  the element. It goes off at the start of the tile tick, `delay` ticks later,
  with the element's intensity *then* (gone = fizzles). It never chains: it
  lays nothing, fires no marker, and is spent once. Someone else's cast on the
  hex replaces the entry and disarms it. Damage hits everyone whose centre is
  within `radius` (tile effects hurt allies too); heals only the owner's side.
  **Collapsing** has `radius=1`, so its damage also reaches the neighbours,
  although its text says "the occupant"; the pull toward the centre only lands
  if the centre is free. **Geyser** (`radius=0`) pushes the occupant away from
  the owner.
- *effect_repeat* (Thundering): thunder only (no other rows use it). The echo
  is a second `detonate` event at 50%; damage is summed into one number per
  unit (E16) before the tile is spent.
- *element_area_plus:* water and ice add a ring around the whole cast shape
  (Tidal at 1 step, Glacial arms stasis on bare ground); thunder widens the
  detonation splash (Arcing: ring 2 also takes half); wind widens the gale
  copy (Gusting). A lay_on trigger is not a cast and gets no ring.
- *cast_step_plus:* every cast of the element (skills, Channel, riposte ring,
  pistol trail), never a lay_on trigger.
- *tile_potency_pct:* reads the tile's `source`. Water = wading cost (rounded
  up) and the detonation water bonus, not conduction on hits. Ice = the
  shatter multiplier of a glaze you made (each glaze now records
  `glaze_source`). Light = healing and exposure; dark = concealment; fire =
  standing and crossing burn.
- *stand_on_bonus:* anyone's charge counts; Rimed needs a glaze (a stasis
  marker is not a lock).
- *lay_on:* `move` = tiles left by a walk or a Charge (not leaps, not being
  pushed). `struck` = a landed basic attack or skill hit (ripostes and
  counters don't trigger it). `hit` = the basic attack landed on its main
  target. Triggers don't change the wearer's attuned element.
- *aoe_radius_plus:* the added ring is damage only, never painted (E10's
  lesson). Basic Cleaving rings the target; skill Cleaving/Channelling rings
  the skill's shape. Applies to the area skills: Arcing Shot, Surge,
  Tridentpierce, Cleave, Daggerleap.
- *multi_hit:* `same` rolls each strike; `fan` sends the side shots along the
  two neighbouring headings to the first foe in range and sight; `line` hits
  the first foe behind the target within weapon range. Each extra strike is
  its own `attack` event.
- *move_after_attack:* only adds anything if you moved before acting; an
  "attack" is a basic attack or a damaging skill.
- *knockback on=hit:* a secondary effect, so it lands on an avoid and only a
  resist stops it. A push stops at anything you couldn't stand on or climb.
- *counter_attack:* answers basic attacks and skills from within `range`
  (melee height rule applies), at `dmg_pct`% of the counterer's basic
  forecast, `per_turn` per attacker turn; counters are never countered.
- *attack_mod:* `hit_per_hex` counts the hexes *between* (distance − 1).
  Damage modifiers multiply in sequence after mitigation, one rounding.
- *guard:* after a basic attack or damaging skill, until your next turn.
- *trigger_stat:* `damaged` includes tile damage; `knockout` needs the KO
  credited to you (E14); caps are per stat.
- *element_damage_pct* `next_same` (Imbued): any action that carries an
  element primes it, so a run of same-element attacks keeps the +25% after the
  first.
- *aura_mod / glance_mod:* radius 0 (or `allies=0`) is the holder; radius ≥ 1
  with `allies=1` is allies within reach, not the holder. Own radius-0 bonuses
  also show on the sheet outside battle.
- *Abilities in battle:* `BWRun.prepare_for_battle(units)` fills
  `BWUnit.abilities`. A unit with learned abilities of a type but none of that
  type equipped auto-equips the first one it learned of that type, and the
  choice is saved.

## 9. Schema gaps (SCHEMA.md left untouched)

- **The enchantment param format** isn't in SCHEMA.md. Section 1 defines it;
  it's worth promoting.
- **"Every piece has one built-in enchantment"**: still true (re-imbue, which
  left pieces plain, is gone, D202).
- **Per-instance item data** has no file: tier, rolled stat values,
  enchantment id, and battles worn per unit (for learning). These CSVs are base
  types; inventory and saves need an instance format.
- **Ability equip limits** ("one type at a time") need a ruling: one of each
  type (my reading), or one ability in total.
- **The "Enchant your equipment" downtime action** is gone (D127); the shop's
  scrolls are the way to change an enchantment.
- **"Train in an ability"** raises its effectiveness. *Implemented* (kept
  more modest than the +50% first suggested): `BWRun.ability_ranks` holds the
  rank, and rank r multiplies an ability's magnitude params by
  `1 + 0.25 × (min(r, 3) − 1)`, so rank 2 = ×1.25 and rank 3 = ×1.5 (the cap).
  Integers round (Brace +1 stays +1 at rank 2, becomes +2 at rank 3).
  Multipliers scale only their excess (Bastion ×2 → ×2.5). Shape and gating
  params never scale: radius, range, `plus`, `move`, counts, caps,
  thresholds, chance, delay, once flags.
- **Move** is 4 for everyone (D17), and `weapons.csv` gives daggers +1. Leap
  Ready and Flutter stack on top of that.
