extends BWSkillDef
## D306 Self-detonate, Blast Rider's free action. A holder standing on a charge
## that thunder detonates (anything charged but unglazed water) or on its own
## fuse blows its own hex under the Blast Rider rules (D291): it takes nothing,
## the ring takes the normal half, it is launched (move 2 after the action),
## once per turn, and the hex can't be re-armed until its next turn. Any
## weapon can use it; it is what makes the dagger bomber work: Daggerleap into
## the pack onto a fuse or fire, self-detonate, launch out. Weapon "keystone":
## in no class's pool; BWWind.keystone_actions lists it for every holder.


func _init() -> void:
	define({
		"key": "self_detonate", "name": "Self-detonate", "weapon": "keystone", "clip": "cast",
		"desc": "Free (Blast Rider): blow the charge or your fuse under you. You take nothing, the ring takes the normal half, and you launch: move 2. Once per turn",
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
	p.notes.append("Self-detonate: your hex blows (you take nothing, the ring the normal half); then move %d" % BWThunderKeys.LAUNCH)


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	BWThunderKeys.self_detonate(b, u)
	return 0


## The AI blows it when the simulated blast nets damage (BWAI._guard_up runs
## free actions last, then walks the launch to the safest hex).
func ai_free_wanted(b: BWBattle, u: BWUnit) -> bool:
	return BWThunderKeys.ai_self_det(b, u)
