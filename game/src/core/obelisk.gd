class_name BWObelisk
extends BWUnit
## D140-D145: a neutral objective on the "Obelisks" map (fight 4). A third
## side, team "neutral": it never moves or attacks, it pulses on its own turn
## in the speed queue, and the player wins by breaking one (BWBattle).
##
## Two kinds (author 2026-10-05, numbers tuned in D144):
##   lantern  the bright one, on the three-bridge island. Ranged attacks have a
##            flat 50% chance to miss it (bows, pistols, thrown daggers, staff
##            spells from beyond reach). Its pulse hits every unit for
##            PULSE.lantern and pushes everyone one hex away from it.
##   well     the dark one, on the causeway island. Melee attacks have a flat
##            50% chance to miss it. Its pulse hits every unit for PULSE.well
##            and pulls everyone one hex toward it.
## Both share ONE life (D378): HP_MAX is the shared pool, every stone's hp
## mirrors it (BWBattle._stones_sync) and a blow on either lowers it; at 0
## they crumble together. Both: no move, no statuses, no ground damage, can't be
## displaced, not a chain-lightning target.
##
## A map declares them under "objective" (BWBoard.objective):
##   "objective": { "mode": "obelisks", "obelisks": [ { "kind": "lantern", "at": [q, r] }, ... ] }
## and BWBattle.setup() places them, so every caller (the game, the sims,
## --combat) gets the mode from the map alone.

const HP_MAX := 280                   # D477: 280 (whole runs: 220 won 86-95%, 280 66%); D378: the SHARED pool, was 220 (was D155's 350 a stone; D144 320; the original 500)
const DODGE_PCT := 50.0               # flat: the hit chance is halved (D142)
const TEAM := "neutral"

## Per kind: display name, the attack type it shrugs off, its pulse (push =
## away, pull = toward), the pulse damage, and its sheet. `spd` places it in
## the speed queue (D140: mid-round at fight 4). `look` drives the view.
const KINDS := {
	"lantern": {
		"name": "The White Lantern", "dodge": "ranged", "pulse": "push", "spd": 9,
		"def": 6, "res": 6, "dex": 0, "look": "bright",
		"veil": "Glare",
		"codex": "A chalk-white pillar that hums. Arrows bend around its glare, and when it breathes out the world is shoved away.",
		"rule": "50%% of ranged attacks miss it (bows, thrown daggers, staff spells from range). Each turn: every unit takes %d and is pushed one hex away.",
	},
	"well": {
		"name": "The Black Well", "dodge": "melee", "pulse": "pull", "spd": 7,
		"def": 6, "res": 6, "dex": 0, "look": "dark",
		"veil": "Hollow",
		"codex": "A monolith of black glass with a hole for a heart. Blades sink into it like water, and when it breathes in the world slides toward it.",
		"rule": "50%% of melee attacks miss it (adjacent weapon attacks and melee skills). Each turn: every unit takes %d and is pulled one hex toward it.",
	},
}

## D144 tuned pulse damage (the author's starting numbers were 20 / 25).
const PULSE := { "lantern": 10, "well": 10 }   # author 2026-10-05: 10 each (D144 tuned 4 / 5; original 20 / 25)
## Slamming into rock or a unit when a pulse can't move you: % of max HP
## (Gust's rule, smaller: it happens every round).
const SLAM_PCT := 5.0

## Tuning only (tools/obelisk_sim.gd): replace HP_MAX / PULSE while set. The
## game never sets them.
static var hp_override := 0
static var pulse_override := {}

var kind := "lantern"
var pulse_kind := "push"
var pulse_damage := 20
var dodge_vs := "ranged"
var hp_cap := HP_MAX
var at := Vector2i(-1, -1)            # where the map puts it


static func create(p_kind: String, p_at: Vector2i) -> BWObelisk:
	var k: Dictionary = KINDS.get(p_kind, KINDS.lantern)
	var o := BWObelisk.new()
	o.kind = p_kind if KINDS.has(p_kind) else "lantern"
	o.id = "obelisk_" + o.kind
	o.name = str(k.name)
	o.team = TEAM
	o.friendliness = "unfriendly"
	o.element = ""
	o.weapon_class = ""
	o.weapon_model = ""
	for s in BWUnit.STATS:
		o.stats[s] = int(k.get(s, 0))
	o.pulse_kind = str(k.pulse)
	o.dodge_vs = str(k.dodge)
	o.pulse_damage = int(pulse_override.get(o.kind, PULSE[o.kind]))
	o.hp_cap = hp_override if hp_override > 0 else HP_MAX
	o.at = p_at
	o.cosmetics["tagline"] = str(k.codex)
	o.hp = o.hp_cap
	return o


## Its own HP, not the CON formula (BWUnit.max_hp is the squad's).
func max_hp() -> int:
	return hp_cap


func move_range() -> int:
	return 0


func speed() -> int:
	return stat("spd")


func begin_battle() -> void:
	super.begin_battle()
	pos = at


## Rules text for the hover card, the codex and the forecast.
func rule_text() -> String:
	return (str(KINDS[kind].rule) % pulse_damage) + " " + SHARED_RULE


## D378: said on every stone's card, the plate and the room card.
const SHARED_RULE := "The stones share one life: damage to either lowers it, and they fall together."


func codex_line() -> String:
	return str(KINDS[kind].codex)


func veil_name() -> String:
	return str(KINDS[kind].veil)


func look() -> String:
	return str(KINDS[kind].look)


## D327: who may strike it. A stone: the player only (the enemy defends it,
## D140). BWObjective overrides it with its `hittable` list.
func hittable_by(t: String) -> bool:
	return t == "player"


static func is_objective(u: BWUnit) -> bool:
	return u is BWObelisk


## D142: is a blow from `att` (standing at `from`) on `dfn` ranged or melee?
## Bows and pistols always shoot; daggers and staves are ranged beyond reach
## (thrown, cast) and melee adjacent; swords, axes, lances (reach 2 included),
## fists are melee.
static func attack_type(att: BWUnit, gap: int) -> String:
	match att.weapon_class:
		"bow", "pistols":
			return "ranged"
		"daggers", "staff":
			return "ranged" if gap > 1 else "melee"
	return "melee"
