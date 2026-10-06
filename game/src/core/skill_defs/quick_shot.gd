extends BWSkillDef
## Pistols. A basic shot that spends no action, once per Reload. D87 fan the
## hammer: twice per reload if the shooter hasn't moved (the second is plain
## lead; moving spends it). Quick Shot+: PLUS_SHOTS times if unmoved.

const PLUS_SHOTS := 3


func _init() -> void:
	define({
		"key": "quick_shot", "name": "Quick Shot", "weapon": "pistols", "clip": "",
		"desc": "Fire without spending your action; once per reload, or twice if you haven't moved (fan the hammer)",
		"plus": "Quick Shot+: fan three times if you haven't moved",
		"targeting": "unit", "needs_element": false, "range": 5, "cd": 0,
		"power": 0, "basic": true, "free": true,
	}, 150)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.victims = b._foes_on(u, [target])
	if u.loaded != "":
		p.hexes = b._on_board(BWHex.trail(u.pos, target))


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, _p: Dictionary) -> int:
	b._fire_pistol(u, target_hex)
	if not u.moved and int(u.fx.get("fan", 0)) < shots(u) - 1:
		u.fx["fan"] = int(u.fx.get("fan", 0)) + 1
		u.quick_shot_ready = true
		b._emit({ "type": "fan", "unit": u.id })
	return 0


## Shots per reload while unmoved (fan the hammer).
func shots(u: BWUnit) -> int:
	if upgraded(u):
		return PLUS_SHOTS
	return BWSkills.FAN_SHOTS
