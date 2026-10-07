class_name BWLilFella
extends BWObjective
## D348: the LIL FELLA of Stop the Horde (BWHordeMode). A small neutral NPC
## the squad must keep alive: not player-controlled (it flees on its own turn,
## BWHordeMode._fella_turn), on the squad's side for damage. Built on
## BWObjective (team "neutral", allegiance "player", hittable ["enemy"]), so:
##   - the squad's blows never land on it (can_harm / foes_of read `hittable`),
##     its area skills pass over it (_foes_on), chain arcs skip it
##     (_chain_target, _conduct), and no status or displacement lands on it
##     from anyone (D141's stone rules, kept: simple and readable);
##   - the enemy's attacks hurt it (it is in foes_of(enemy));
##   - ground hurts it only when the ground's SOURCE is an enemy unit
##     (BWBattle._tile_hurt reads hurt_by_ground): the squad's fire, dark,
##     blasts, beams, pools and slams never do; unsourced (map-seeded) ground
##     doesn't either, and it never walks onto a hazard anyway.
## HP: HP_PCT of the highest max HP in the deployed squad at battle start.
## It moves MOVE hexes a turn and acts at the squad's median speed.

const HP_PCT := 0.5
const MOVE := 3
const TAG := "fella"
const NAME := "Lil Fella"


static func make_for(squad: Array, at: Vector2i) -> BWLilFella:
	var o := BWLilFella.new()
	o.kind = "fella"
	o.id = "lil_fella"
	o.name = NAME
	o.team = TEAM
	o.friendliness = "friendly"
	o.element = ""
	o.weapon_class = "fists"
	o.weapon_model = ""
	for s in BWUnit.STATS:
		o.stats[s] = 0
	o.stats["def"] = 4
	o.stats["res"] = 4
	o.stats["spd"] = median_speed(squad)
	o.pulse_kind = ""
	o.pulse_damage = 0
	o.dodge_vs = "none"
	o.hp_cap = hp_for(squad)
	o.allegiance = "player"
	o.hittable = ["enemy"]
	o.acts = true
	o.tag = TAG
	o.look_key = "fella"
	o.view_height = 1.3
	o.rule = "Keep it alive. Only the enemy can hurt it (blows, and ground the enemy laid). It flees on its own turn."
	o.codex = "A little one with a lantern, much too far from home."
	o.cosmetics = { "hair_style": "bob", "top": "hoodie", "bottom": "shorts", "clothing_shade": "dark", "voice_pitch": 1.5, "tagline": o.codex }
	o.equipment = { "head": { "base": "wizard_hat" } }
	o.at = at
	o.hp = o.hp_cap
	return o


## D348: half the highest max HP in the deployed squad (at least 1).
static func hp_for(squad: Array) -> int:
	var top := 0
	for u in squad:
		if u is BWUnit and not BWObelisk.is_objective(u):
			top = maxi(top, (u as BWUnit).max_hp())
	return maxi(1, int(round(top * HP_PCT)))


static func median_speed(squad: Array) -> int:
	var sp: Array = []
	for u in squad:
		if u is BWUnit and not BWObelisk.is_objective(u):
			sp.append((u as BWUnit).speed())
	if sp.is_empty():
		return 5
	sp.sort()
	return int(sp[sp.size() / 2])


static func is_fella(u: BWUnit) -> bool:
	return u is BWLilFella


func move_range() -> int:
	return MOVE


## Ground laid by `src` (a unit id; "" = the map's own) hurts it only when the
## layer is an enemy unit.
func hurt_by_ground(b: BWBattle, source: String) -> bool:
	var s := b._unit(source)
	return s != null and s.team == "enemy"
