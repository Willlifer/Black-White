extends BWSkillDef
## Lance. Strike TRIDENT_LEN hexes forward; those and everything beside them
## are hit. D87: a foe right behind the first in line is pierced (+20%).


func _init() -> void:
	define({
		"key": "tridentpierce", "name": "Tridentpierce", "weapon": "lance", "clip": "",
		"desc": "Strike 2 tiles forward; those tiles and everything adjacent to them are hit. A foe standing right behind the first in line is pierced for +20%",
		"plus": "Tridentpierce+: the pierce carries on to a third foe in line",
		"targeting": "dir", "needs_element": true, "range": BWSkills.TRIDENT_LEN, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.TRIDENT_DMG, "aoe": true,
	}, 30)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var spine := b.board.ray(u.pos, target, BWSkills.TRIDENT_LEN)
	p.hexes = b._without(b._on_board(BWHex.fringe(spine, 1)), u.pos) if not spine.is_empty() else []
	p.victims = b._foes_on(u, p.hexes)
	if spine.size() >= 2:
		var a := b.unit_at(spine[0])
		var c := b.unit_at(spine[1])
		if a != null and c != null and a != c and a.team != u.team and c.team != u.team:
			p.shares[c.id] = [1.0 + BWSkills.TRIDENT_PIERCE_PCT / 100.0,
				"Pierce (in line behind %s): +%d%%" % [a.name, BWSkills.TRIDENT_PIERCE_PCT], "Pierce"]
			# Tridentpierce+ (D105): the pierce carries on to a third foe in line
			var line := b.board.ray(u.pos, target, BWSkills.TRIDENT_LEN + 1)
			if upgraded(u) and line.size() > BWSkills.TRIDENT_LEN:
				var d := b.unit_at(line[BWSkills.TRIDENT_LEN])
				if d != null and d != c and d != a and d.team != u.team and d in p.victims:
					p.shares[d.id] = [1.0 + BWSkills.TRIDENT_PIERCE_PCT / 100.0,
						"Pierce+ (in line behind %s): +%d%%" % [c.name, BWSkills.TRIDENT_PIERCE_PCT], "Pierce"]
