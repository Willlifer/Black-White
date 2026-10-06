class_name BWSkills
## The weapon skills' tuning sheet and shared vocabulary: every number, the
## short statuses and the reactions. The skills themselves (data row + rules)
## are one file each in res://src/core/skill_defs/, loaded by
## BWSkillRegistry (D89); the functions below are the old lookups, kept as
## thin facades over the registry. Shapes: design/ELEMENTS.md §7.2, staff §9.
##
## Targeting (what a click means):
##   "unit"          an enemy within range (line of sight beyond 1 hex)
##   "hex"           any hex within range (min_range..range; `los` if set)
##   "leap"          a free hex within range, OR a free hex carrying the
##                   chosen element at any distance (§7.4)
##   "dir"           one of the six adjacent hexes; only the heading is used
##   "adjacent_unit" an enemy standing next to you
##   "self"          your own hex
##
## Power feeds the brief's skill formula (power + ½STR + ½DEX), or the spell
## formula (power + WIL) for the staff. Powers are V8's, untuned; D87 gave
## every skill one rider (the constants below DEFAULT_CD, design/SKILLS.md).
## `free_action` (Riposte): usable before or after acting; spends nothing.

## V8 MeleeSkills constants, unchanged.
const ARCING_DMG := 10
const ENERGIZED_DMG := 12
const TRIDENT_DMG := 10
const CLEAVE_DMG := 13
const CONSUME_DMG := 14
const CONSUME_PER_POINT := 2       # ELEMENTS §7.2: + 2 per intensity point eaten
const LEAP_DMG := 8
const DUALTHROW_DMG := 9
const STRIKE_DMG := 11
const RIPOSTE_DMG := 10

const ARCING_RADIUS := 1
const TRIDENT_LEN := 2
const CLEAVE_ARC := 3
const LEAP_RANGE := 3
const LEAP_RADIUS := 1
const CHARGE_LEN := 3
const VAULT_LEN := 2
const DUALTHROW_RANGE := 4

## Fists (D76, new; not from V8). Flurry is FLURRY_HITS strikes at
## FLURRY_PCT% of its power each (1.35x one blow, three rolls); Uppercut's
## slam is +UPPERCUT_SLAM_PCT% when the hex behind stops the knockback.
const FLURRY_DMG := 12
const FLURRY_HITS := 3
const FLURRY_PCT := 45
const UPPERCUT_DMG := 12
const UPPERCUT_PUSH := 1
const UPPERCUT_SLAM_PCT := 50
const PALM_DMG := 9

## Staff (ELEMENTS §9).
const SURGE_DMG := 9
const SATURATE_DMG := 13
const STAFF_RANGE := 4
const LEY_LEN := 4

const DEFAULT_CD := 2              # ELEMENTS §10 SKILL_CD

## D87 skills pass (design/SKILLS.md): one hook per skill. Damage stays in
## the V8 bands above; these are the riders.
const RIPOSTE_CD := 3              # free to set; a landed answer refunds 1
const CLEAVE_PER_FOE_PCT := 10     # +10% to every foe per foe beyond the first
const CHARGE_SLAM_PCT := 8         # % max HP to the caught foe and what it hits
const TRIDENT_PIERCE_PCT := 20     # the foe in line behind the first takes +20%
const VAULT_MOMENTUM_PCT := 25     # the follow-up after landing
const BACKSTAB_PCT := 50           # Daggerleap landing behind a foe
const BOUNCE_RANGE := 2            # Second Dagger bounces to a foe within 2
const BOUNCE_PCT := 75
const CONSUME_HEAL_PCT := 5        # per point eaten
const ARCING_HIGH_GROUND := 2      # levels above the target hex for +1 radius
const PIERCE_PCT := 60             # Energized Shot, the next foe in line
const PIERCE_REACH := 3            # ... within 3 hexes beyond the target
const FAN_SHOTS := 2               # Quick Shots per reload when unmoved
const OWN_ROUND_PCT := 10          # Reload in your own element
const SURGE_CENTRE_PCT := 30
const LEY_SWIFT := 1               # move for allies on the line, next turn
const SIPHON_HEAL_PCT := 4         # per step stripped
const FLURRY_FINISH_CRIT := 15     # crit points on the last strike
const STEAM_PCT := 8               # fire + water: % max HP to the ring
const BLIND_RANGE := 2             # D94: Blinded can only target units within 2 hexes
const PINNED_MOVE := 2             # D94: Pinned, -2 move
const STEADIED_TURNS := 2          # D94: after Staggered ends, immune to it for 2 turns
const SCORCH_PCT := 10             # Saturate fire 3: attacks on it +10%
const DRENCH_THUNDER_PCT := 20     # Saturate water 3: thunder hits +20%, move -1
const SHROUD_DRAIN_PCT := 4        # Saturate dark 3: drain at its turn start

## Saturate pushing an axis to 3 marks the unit on the hex (D87).
const SATURATE_STATUS := { "fire": "scorched", "water": "drenched", "light": "blinded", "dark": "shrouded" }
## Striketwice's second cut in the opposite element (D87), keyed by the pair
## in either order.
const REACTIONS := {
	"fire|water": "steam", "water|fire": "steam",
	"light|dark": "eclipse", "dark|light": "eclipse",
	"thunder|wind": "storm", "wind|thunder": "storm",
}
## Status names and one-line rules (unit card, forecast, codex). D94: every
## short status lasts until the end of the holder's next turn, and none of
## them lowers hit any more (the author's call: no "reduce hit" effects).
const STATUS := {
	"staggered": ["Staggered", "can't use skills on its next turn (basic attack only)"],
	"blinded": ["Blinded", "can't crit; can only target units within 2 hexes"],
	"pinned": ["Pinned", "-2 move"],
	"drenched": ["Drenched", "-1 move; thunder hits on it +20%"],
	"scorched": ["Scorched", "attacks on it +10%"],
	"shrouded": ["Shrouded", "4% dark drain at its turn start"],
	"swift": ["Swift", "+1 move"],
	"frost_ward": ["Frost Ward", "negates the next elemental effect on it, then breaks"],
	"steadied": ["Steadied", "immune to stagger for its next 2 turns"],
	"ward_cd": ["Frost Ward recharging", "no ward at its next turn (a ward every 2nd turn)"],
}
## D93: statuses that count as an elemental effect (Frost Ward / Nightborn
## negate them). Staggered counts only when an element lays it (Static Field).
const ELEMENTAL_STATUS := ["scorched", "drenched", "shrouded", "blinded"]


## The skill's data row ({} if unknown). See BWSkillDef for the fields.
static func get_skill(key: String) -> Dictionary:
	return BWSkillRegistry.row(key)


static func has_skill(key: String) -> bool:
	return BWSkillRegistry.has(key)


## Every skill of one weapon class, menu order.
static func for_weapon(weapon_class: String) -> Array:
	return BWSkillRegistry.for_class(weapon_class).map(func(d): return d.data)


## The class's starting kit (weapons.csv `skills`, else the whole pool),
## with the follow-up halves after the skills that grant them. A unit's own
## kit (its loadout) is BWSkillRegistry.kit_for(u).
static func kit(weapon_class: String) -> Array:
	return BWSkillRegistry.expand(BWSkillRegistry.starter(weapon_class)).map(func(k): return get_skill(k))


## Cooldowns are per skill AND element (ELEMENTS §7.1, V8 melee_cd_key).
static func cd_key(key: String, element: String) -> String:
	return key if element == "" else "%s_%s" % [key, element]


## Does this skill deal damage on its own (no follow-up needed)?
static func is_damaging(key: String) -> bool:
	return int(get_skill(key).get("power", 0)) > 0 or get_skill(key).get("basic", false)
