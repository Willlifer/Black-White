extends BWSkillDef
## D294 Glacier Wall's Break Pillar: the menu row a Glacier Wall holder gets for
## "target your own pillar with a basic" (design/ELEMENTS-v3.md §2; the
## pillar has no HP, so the basic is this row). Your own pillar within your
## weapon's reach: it shatters, 12% (ice) to all six neighbours, both teams,
## and a push of 1 away (onto glaze they just stop, D400). Spends the action. Any of your
## skills whose shape covers your pillar shatters it too (BWKsIce.after_skill).


func _init() -> void:
	define({
		"key": "glacier_shatter", "name": "Break Pillar", "weapon": "keystone", "clip": "strike",
		"desc": "Break one of your own ice pillars in reach: 12% to all six hexes around it (both teams) and a push of 1 away",
		"targeting": "hex", "needs_element": false, "range": 1, "cd": 0,
		"power": 0, "keystone": true,
	}, 9030)


func targets(b: BWBattle, u: BWUnit, _element: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var reach := maxi(1, b.weapon_range(u))
	for h in BWKsIce.own_pillars(b, u):
		if BWHex.distance(u.pos, h) <= reach:
			out.append(h)
	return out


func plan(b: BWBattle, _u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	var ring: Array = []
	for n in BWHex.neighbors(target):
		if b.board.exists(n):
			ring.append(n)
	p["shatter_ring"] = ring
	p.notes.append("Shatter: %d%% to everyone on the six hexes around, then a push of 1 away" % int(BWKsIce.SHATTER_PCT))


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, _p: Dictionary) -> int:
	BWKsIce.shatter(b, u, target_hex)
	return 0


func ai_support(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	return BWKsIce.ai_shatter(b, u, row)
