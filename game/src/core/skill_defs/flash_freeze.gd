extends BWSkillDef
## D294 Flash Freeze, ice's keystone ACTION (design/ELEMENTS-v3.md §2): once
## a battle, range 3, on a foe: it is Frozen (BWKsIce): it skips its next
## turn (a boss doesn't), can't be displaced, counts as glazed for Shatter,
## and its next hit taken is x2, which thaws it. Weapon "keystone": in no
## class's pool; BWWind.keystone_actions adds it for a holder (BWKeystones)
## until it is spent.


func _init() -> void:
	define({
		"key": "flash_freeze", "name": "Flash Freeze", "weapon": "keystone", "clip": "cast",
		"desc": "Once a battle, range 3: Freeze a foe. It skips its next turn (a boss doesn't), can't be displaced, counts as glazed (Shatter), and its next hit taken is x2, which thaws it",
		"targeting": "unit", "needs_element": false, "range": BWKsIce.FREEZE_RANGE, "cd": 0,
		"power": 0, "keystone": true, "once_per_battle": true,
	}, 9010)


func target_ok(b: BWBattle, _u: BWUnit, h: Vector2i, _element: String) -> bool:
	var v := b.unit_at(h)
	return v != null and not BWKsIce.frozen(v) and not BWObelisk.is_objective(v)


func plan(b: BWBattle, _u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var v := b.unit_at(target)
	if v == null:
		return
	p.hexes = [v.pos]
	p["freeze"] = v.id
	p.notes.append("Flash Freeze: %s %s; its next hit taken is x2 (that thaws it)" % [
		v.name, "can't skip (a boss) but is encased" if BWKsIce.is_boss(v) else "skips its next turn"])


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	u.fx["flash_freeze_used"] = true
	var v := b._unit(str(p.get("freeze", "")))
	if v != null:
		BWKsIce.freeze(b, v, u)
	return 0


func ai_support(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	return BWKsIce.ai_freeze(b, u, row)
