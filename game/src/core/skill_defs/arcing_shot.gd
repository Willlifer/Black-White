extends BWSkillDef
## Bow. Lob an imbued shot: the target hex and its ring take the hit. D87:
## from ARCING_HIGH_GROUND+ levels above the target the blast is a radius wider.
## Arcing Shot+ (D106): PLUS_HIGH_GROUND level is enough.

const PLUS_HIGH_GROUND := 1


func _init() -> void:
	define({
		"key": "arcing_shot", "name": "Arcing Shot", "weapon": "bow", "clip": "shot_sky",
		"desc": "Lob an imbued shot; the target hex and everything beside it takes the hit. From 2+ levels above the target the blast is a radius wider",
		"plus": "Arcing Shot+: the wider blast needs only 1 level of height",
		"targeting": "hex", "needs_element": true, "range": 6, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.ARCING_DMG, "radius": BWSkills.ARCING_RADIUS, "aoe": true,
	}, 10)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var radius := int(data.get("radius", 1))
	var need := PLUS_HIGH_GROUND if upgraded(u) else BWSkills.ARCING_HIGH_GROUND
	if b.board.elevation(u.pos) - b.board.elevation(target) >= need:
		radius += 1                    # D87: plunging fire from high ground
		p.notes.append("High ground%s: blast radius %d" % [" (Arcing Shot+: 1 level)" if upgraded(u) else "", radius])
	p.hexes = b._on_board(b.board.area(target, radius))
	p.victims = b._foes_on(u, p.hexes)
