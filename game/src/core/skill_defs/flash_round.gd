extends BWSkillDef
## Pistols. A flare-loaded shot at a foe within RANGE: it is Blinded (a
## secondary effect), and like any pistol shot it lays the seated round on
## its trail and spends the Quick Shot (BWBattle._fire_pistol).

const POWER := 8
const CD := 3
const RANGE := 5


func _init() -> void:
	define({
		"key": "flash_round", "name": "Flash Round", "weapon": "pistols", "clip": "",
		"desc": "A flare shot at an enemy up to 5 tiles away: it is Blinded, and a seated round lays its trail",
		"targeting": "unit", "needs_element": false, "range": RANGE, "cd": CD,
		"power": POWER,
	}, 363)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.victims = b._foes_on(u, [target])
	if u.loaded != "":
		p.hexes = b._on_board(BWHex.trail(u.pos, target))
		p.notes.append("Lays the seated %s round on its trail" % u.loaded)
	for v in p.victims:
		p.notes.append("%s is Blinded (%s)" % [v.name, BWSkills.STATUS.blinded[1]])


func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	if not results.is_empty() and not p.victims.is_empty():
		var v: BWUnit = p.victims[0]
		if v.alive() and results[0].result.secondary:
			b._add_status(v, "blinded", u)


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, _p: Dictionary) -> int:
	b._fire_pistol(u, target_hex)
	return 0
