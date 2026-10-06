extends BWSkillDef
## Bow. A straight shot that lays the element on its trail and hits only its
## target (D44); D87: it punches through to the next foe in line within
## PIERCE_REACH, at PIERCE_PCT%. Energized Shot+ (D106): PLUS_PCT%, reaching
## PLUS_REACH.

const PLUS_PCT := 80
const PLUS_REACH := 5


func _init() -> void:
	define({
		"key": "energized_shot", "name": "Energized Shot", "weapon": "bow", "clip": "",
		"desc": "A hard straight shot that leaves the element on every tile between you and the target, and punches through to the next foe in line (within 3) at 60%",
		"plus": "Energized Shot+: the pierce deals 80% and reaches 5",
		"targeting": "unit", "needs_element": true, "range": 6, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.ENERGIZED_DMG,
	}, 20)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._on_board(BWHex.trail(u.pos, target))
	p.victims = b._foes_on(u, [target])                  # target only
	if p.victims.is_empty():
		return
	var first: BWUnit = p.victims[0]
	var pct := PLUS_PCT if upgraded(u) else BWSkills.PIERCE_PCT
	for h in b._line_beyond(u.pos, target, PLUS_REACH if upgraded(u) else BWSkills.PIERCE_REACH):
		if not b.board.exists(h) or b.board.terrain(h) == BWBoard.JAGGED:
			break
		var o := b.unit_at(h)
		if o != null and o != first and o.team != u.team:
			p.victims.append(o)
			p.shares[o.id] = [pct / 100.0, "Pierced through %s: %d%%%s" % [first.name, pct, " (Energized Shot+)" if upgraded(u) else ""], "Pierced"]
			p["pierce_to"] = o.id
			break
