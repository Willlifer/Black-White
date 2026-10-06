extends BWSkillDef
## Daggers. Devour the dominant element under an adjacent foe (one you have
## learned): it takes CONSUME_DMG + CONSUME_PER_POINT per point eaten, the
## ring around you takes that element, and D87: you heal CONSUME_HEAL_PCT%
## max HP per point; Consume+ PLUS_HEAL_PCT%.

const PLUS_HEAL_PCT := 7


func _init() -> void:
	define({
		"key": "consume", "name": "Consume", "weapon": "daggers", "clip": "",
		"desc": "Devour the element under an adjacent enemy; it takes the damage, you heal 5% HP per point eaten, and you flourish",
		"plus": "Consume+: heals 7% per point",
		"targeting": "adjacent_unit", "needs_element": false, "range": 1, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.CONSUME_DMG,
	}, 70)


## Needs ground under the target in an element the unit has learned.
func target_ok(b: BWBattle, u: BWUnit, h: Vector2i, _element: String) -> bool:
	var dom := b.tiles.dominant(h)
	return not dom.is_empty() and str(dom.element) in b.learned_elements(u)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var dom := b.tiles.dominant(target)
	p.element = str(dom.get("element", ""))
	p["points"] = int(dom.get("points", 0))
	p.hexes = b._without(b._without(b._on_board(b.board.area(u.pos, 1)), u.pos), target)
	p.victims = b._foes_on(u, [target])
	if int(p.points) > 0:               # D87
		p.notes.append("Consume heals you %d%% HP (%d points eaten)" % [heal_pct(u) * int(p.points), int(p.points)])


func power_formula(b: BWBattle, _u: BWUnit, el: String, v: BWUnit, p: Dictionary) -> Dictionary:
	var pts := int(p.get("points", b.tiles.dominant(v.pos).get("points", 0)))
	return BWFormulas.consume_power(BWSkills.CONSUME_DMG, BWSkills.CONSUME_PER_POINT, pts, el)


func ground(b: BWBattle, u: BWUnit, el: String, target_hex: Vector2i, p: Dictionary) -> int:
	b.tiles.clear(target_hex)
	b._emit({ "type": "paint", "unit": u.id, "element": "", "hexes": [target_hex], "kind": "consume" })
	b.paint(p.hexes, el, u)
	return 0


func after_paint(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary,
		_results: Array, _stripped: int) -> void:
	if int(p.get("points", 0)) > 0:
		b._heal(u, heal_pct(u) * int(p.points), "consume")


func heal_pct(u: BWUnit) -> int:
	if upgraded(u):
		return PLUS_HEAL_PCT
	return BWSkills.CONSUME_HEAL_PCT
