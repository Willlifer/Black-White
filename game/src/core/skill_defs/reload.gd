extends BWSkillDef
## Pistols (V8 flintlock, D9). Seat a round of an element: readies Quick
## Shot, and the next shot lays a trail. D87: a round of your own element
## hits +OWN_ROUND_PCT% (BWBattle.forecast_basic reads `loaded`). Reload+:
## two rounds are seated; when the first is fired (its trail's paint event
## on BWBattle.event, with `loaded` already spent) the second drops in, so
## two shots lay trails. A fresh Reload replaces the spare.


func _init() -> void:
	define({
		"key": "reload", "name": "Reload", "weapon": "pistols", "clip": "",
		"desc": "Seat a round of your element. Readies the quick shot, and the next shot lays a trail. A round of your own element hits +10%",
		"plus": "Reload+: seats two rounds, so two trailed shots",
		"targeting": "self", "needs_element": true, "range": 0, "cd": 0,
		"power": 0,
	}, 140)


func plan(_b: BWBattle, u: BWUnit, element: String, _target: Vector2i, p: Dictionary) -> void:
	if upgraded(u) and element != "":
		p.notes.append("Reload+: two %s rounds, two trailed shots" % element)


func ground(b: BWBattle, u: BWUnit, el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	u.loaded = el
	u.quick_shot_ready = true
	u.fx["fan"] = 0
	u.fx.erase("spare_round")
	if upgraded(u):
		u.fx["spare_round"] = el
		if not u.fx.get("reload_listen", false):
			u.fx["reload_listen"] = true
			b.event.connect(_reseat.bind(u))
	return 0


## Reload+: the round just fired (a pistol trail is a plain cast paint by the
## shooter in the round's element, with `loaded` already emptied).
func _reseat(e: Dictionary, u: BWUnit) -> void:
	if e.type != "paint" or e.has("kind") or str(e.get("unit", "")) != u.id or u.loaded != "":
		return
	var spare := str(u.fx.get("spare_round", ""))
	if spare != "" and spare == str(e.get("element", "")):
		u.fx.erase("spare_round")
		u.loaded = spare
