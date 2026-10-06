extends BWSkillDef
## Staff spell (ELEMENTS §9). Pour `steps` of the element into one hex.
## D87: pushing an axis from below 3 to 3 marks the foe there for a turn
## (BWSkills.SATURATE_STATUS: Scorched, Drenched, Blinded, Shrouded); a
## secondary effect, so a resist stops it. Saturate+ (D107): the mark also
## lands when the pour ends at 2 (from below 2): threshold() below.


func _init() -> void:
	define({
		"key": "saturate", "name": "Saturate", "weapon": "staff", "clip": "",
		"desc": "Pour two steps of your element into a single hex. Push it to 3 and the foe there is Scorched, Drenched, Blinded or Shrouded for a turn",
		"plus": "Saturate+: the status also lands when the pour ends at 2",
		"targeting": "hex", "needs_element": true, "range": BWSkills.STAFF_RANGE, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.SATURATE_DMG, "steps": 2, "min_range": 0, "los": true, "spell": true,
	}, 200)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, p.hexes)
	p["sat_before"] = b.tiles.intensity(target, element)
	var st: String = BWSkills.SATURATE_STATUS.get(element, "")
	var need := threshold(u)
	if st == "" or p.victims.is_empty() or int(p.sat_before) >= need:
		return
	var after: Dictionary = b.tiles._route(b.tiles.at(target), element, true, p.steps, u.id)
	var ent: Dictionary = after.get("entry", {})
	var axis := int(ent.get("h", 0)) if element in ["fire", "water"] else int(ent.get("v", 0))
	if absi(axis) >= need and signi(axis) == (1 if element in ["fire", "light"] else -1):
		p.notes.append("%s to %d: %s is %s for a turn (%s)" % [element.capitalize(), need, p.victims[0].name,
			BWSkills.STATUS[st][0], BWSkills.STATUS[st][1]])


func after_paint(b: BWBattle, u: BWUnit, el: String, target_hex: Vector2i, p: Dictionary,
		results: Array, _stripped: int) -> void:
	var st: String = BWSkills.SATURATE_STATUS.get(el, "")
	var need := threshold(u)
	if st == "" or int(p.get("sat_before", 3)) >= need or b.tiles.intensity(target_hex, el) < need:
		return
	var first_res: Dictionary = results[0].result if not results.is_empty() else {}
	var v := b.unit_at(target_hex)
	if v != null and v.team != u.team and not first_res.is_empty() and first_res.secondary:
		b._add_status(v, st, u)


## The intensity the pour must reach (from below it) to mark: 3, or 2 with
## Saturate+.
func threshold(u: BWUnit) -> int:
	if upgraded(u):
		return 2
	return 3
