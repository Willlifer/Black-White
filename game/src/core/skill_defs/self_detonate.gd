extends BWSkillDef
## D306 Self-detonate, kept PROVISIONALLY by Keystones v3 (D452): now
## Superconductor's free action (Blast Rider is gone). A holder standing on a
## charge that thunder detonates (anything charged but unglazed water) or on
## its own fuse blows its own hex, once per turn. The blast is on its own hex,
## so Superconductor's rule makes it immune to everything that action sets
## off, and the ring reaches 2. No launch any more. Weapon "keystone": in no
## class's pool; BWKeystones.skills lists it for every holder.


func _init() -> void:
	define({
		"key": "self_detonate", "name": "Self-detonate", "weapon": "keystone", "clip": "cast",
		"desc": "Free (Superconductor): blow the charge or your fuse under you. It's on your own hex, so nothing from it hurts you, and it reaches radius 2. Once per turn",
		"targeting": "self", "needs_element": false, "range": 0, "cd": 0,
		"power": 0, "free_action": true, "keystone": true,
	}, 9030)


func targets(b: BWBattle, u: BWUnit, _element: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if BWThunderKeys.self_det_ready(b, u):
		out.append(u.pos)                     # "self" targeting skips target_ok: gate it here
	return out


func target_ok(b: BWBattle, u: BWUnit, _h: Vector2i, _element: String) -> bool:
	return BWThunderKeys.self_det_ready(b, u)


func plan(_b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.hexes = [u.pos]
	p.notes.append("Self-detonate: your hex blows, radius 2 (Superconductor: you take nothing from it)")


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	BWThunderKeys.self_detonate(b, u)
	return 0


## The AI blows it when the simulated blast nets damage (BWAI._guard_up runs
## free actions last).
func ai_free_wanted(b: BWBattle, u: BWUnit) -> bool:
	return BWThunderKeys.ai_self_det(b, u)
