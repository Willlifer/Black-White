extends BWSkillDef
## Staff spell (ELEMENTS §9). Draw the element in a straight line up to
## LEY_LEN (jagged ground stops it), then a basic follow-up. D87: allies
## standing on the line are Swift (+LEY_SWIFT move) next turn. Ley Line+
## (D107): PLUS_LEN long.

const PLUS_LEN := 6


func _init() -> void:
	define({
		"key": "ley_line", "name": "Ley Line", "weapon": "staff", "clip": "",
		"desc": "Draw your element in a straight line, then act again. Allies on the line get +1 move next turn",
		"plus": "Ley Line+: length 6",
		"targeting": "dir", "needs_element": true, "range": BWSkills.LEY_LEN, "cd": BWSkills.DEFAULT_CD,
		"power": 0, "follow_up": ["basic"], "spell": true,
	}, 210)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var length := BWSkills.LEY_LEN
	if upgraded(u):
		length = PLUS_LEN
	for h in b.board.ray(u.pos, target, length):
		if b.board.terrain(h) == BWBoard.JAGGED:
			break
		p.hexes.append(h)
	var swift: Array = b.side(u.team).filter(func(a): return a != u and a.pos in p.hexes).map(func(a): return a.name)
	if not swift.is_empty():            # D87
		p.notes.append("Swift: %s +%d move next turn" % [", ".join(swift), BWSkills.LEY_SWIFT])


func after_paint(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary,
		_results: Array, _stripped: int) -> void:
	for a in b.side(u.team):
		if a != u and a.pos in p.hexes:
			b._add_status(a, "swift", u)
