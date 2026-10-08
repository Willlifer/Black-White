extends BWSkillDef
## Axe. D436 (replaces War Cry, retired): a roar that spends the action.
## Your next Cleave or Sunder this battle doubles in size: Cleave hits the six
## hexes around you plus the five ring-2 hexes in front (cleave.gd
## `bellowed`), Sunder's fissure runs BELLOW_LEN hexes (sunder.gd). It holds
## until one of them is used (u.fx `bellow`, cleared with the battle); a
## second Bellow while one is held isn't offered. The unit card and the board
## show it (BWKit2View: a burst of inked spikes at the feet, a card line).

const CD := 4
const FX := "bellow"


func _init() -> void:
	define({
		"key": "bellow", "name": "Bellow", "weapon": "axe", "clip": "war_cry",
		"desc": "Roar (uses your action): your next Cleave or Sunder this battle doubles in size. Cleave hits all 6 tiles around you and 5 more in front; Sunder's fissure runs 10 tiles",
		"targeting": "self", "needs_element": false, "range": 0, "cd": CD,
		"power": 0,
	}, 315)


## Not while a Bellow is still held.
func targets(b: BWBattle, u: BWUnit, element: String) -> Array[Vector2i]:
	if held(u):
		return []
	return super.targets(b, u, element)


func plan(_b: BWBattle, _u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.notes.append("Bellow: your next Cleave or Sunder this battle doubles in size")


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	u.fx[FX] = true
	b._emit({ "type": "bellow", "unit": u.id })
	return 0


static func held(u: BWUnit) -> bool:
	return u != null and bool(u.fx.get(FX, false))


## Cleave / Sunder resolved: the held Bellow is spent.
static func spend(b: BWBattle, u: BWUnit, by: String) -> void:
	if held(u):
		u.fx.erase(FX)
		b._emit({ "type": "bellow_spent", "unit": u.id, "skill": by })


## D112: roar when a Cleave or Sunder is in the kit and no foe is in reach
## yet (the doubled swing waits for the closing turn).
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	if held(u) or not b.attack_targets(u).is_empty():
		return {}
	var kit := u.fight_loadout(u.weapon_class)
	if not ("cleave" in kit or "sunder" in kit):
		return {}
	var reach := u.move_range() + b.weapon_range(u) + 1
	for f in b.foes_of(u):
		if b.gap(u, f) <= reach:
			return { "target": u.pos, "element": "", "score": 5.0 }
	return {}
