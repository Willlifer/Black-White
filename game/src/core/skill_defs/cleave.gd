extends BWSkillDef
## Axe. Sweep CLEAVE_ARC hexes beside you (V8 _cleave_arc); if the element
## is already on that ground the swing carries a ring further. D87: +10% to
## everyone per foe caught beyond the first; Cleave+ (D104) +PLUS_PER_FOE_PCT%.

const PLUS_PER_FOE_PCT := 15


func _init() -> void:
	define({
		"key": "cleave", "name": "Cleave", "weapon": "axe", "clip": "cut",
		"desc": "Sweep 3 tiles beside you. If the element is already on the ground there, the swing carries further. +10% to everyone per foe caught beyond the first",
		"plus": "Cleave+: +15% per extra foe (from +10%)",
		"targeting": "dir", "needs_element": true, "range": 1, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.CLEAVE_DMG, "aoe": true,
	}, 50)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	var arc := arc_from(b, u.pos, target)
	p.hexes = arc
	for h in arc:                      # read before anything is laid
		if b.tiles.carries(h, element):
			p.hexes = b._without(b._on_board(BWHex.fringe(arc, 1)), u.pos)
			break
	p.victims = b._foes_on(u, p.hexes)


func forecast_mods(_b: BWBattle, u: BWUnit, _el: String, _v: BWUnit, p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	var n: int = (p.get("victims", []) as Array).size()
	var per := BWSkills.CLEAVE_PER_FOE_PCT
	if upgraded(u):
		per = PLUS_PER_FOE_PCT
	if n > 1:
		mods.append({ "stage": "dmg", "value": 1.0 + per * (n - 1) / 100.0,
			"label": "%s: %d foes caught (+%d%%)" % ["Cleave+" if upgraded(u) else "Cleave", n, per * (n - 1)], "tag": "Cleave" })


## V8 _cleave_arc: CLEAVE_ARC contiguous neighbours centred on the heading.
static func arc_from(b: BWBattle, from: Vector2i, toward: Vector2i) -> Array:
	var di := BWHex.direction_index(from, toward)
	if di < 0:
		return []
	var nbrs := BWHex.neighbors(from)
	var half := BWSkills.CLEAVE_ARC / 2
	var out: Array = []
	for off in range(-half, half + 1):
		var h: Vector2i = nbrs[(di + off + 6) % 6]
		if b.board.exists(h):
			out.append(h)
	return out
