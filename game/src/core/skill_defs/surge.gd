extends BWSkillDef
## Staff spell (ELEMENTS §9). Burst the element over a hex and its ring.
## D87: the unit on the centre takes +SURGE_CENTRE_PCT%; Surge+ (D107)
## +PLUS_CENTRE_PCT%.

const PLUS_CENTRE_PCT := 50


func _init() -> void:
	define({
		"key": "surge", "name": "Surge", "weapon": "staff", "clip": "",
		"desc": "Burst your element over a hex and everything beside it; the centre takes +30%",
		"plus": "Surge+: the centre takes +50%",
		"targeting": "hex", "needs_element": true, "range": BWSkills.STAFF_RANGE, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.SURGE_DMG, "radius": 1, "min_range": 0, "los": true, "spell": true, "aoe": true,
	}, 190)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._on_board(b.board.area(target, int(data.get("radius", 1))))
	p.victims = b._foes_on(u, p.hexes)
	var c := b.unit_at(target)       # D87: the centre takes the brunt
	if c != null and c in p.victims:
		var pct := BWSkills.SURGE_CENTRE_PCT
		var label := "Surge centre"
		if upgraded(u):
			pct = PLUS_CENTRE_PCT
			label = "Surge+ centre"
		p.shares[c.id] = [1.0 + pct / 100.0, "%s: +%d%%" % [label, pct]]
