extends BWSkillDef
## RETIRED (D436 Bellow): never offered; the def stays for old saves, which map it
## (BWSkillRegistry.RENAMED, migrate_unit). Its helpers may still be shared.
## Axe (D104). A roar that spends the action: +STR_PCT% STR (battle_mods)
## for your next TURNS turns. The expiry listens to the battle's events
## (BWBattle.event): it ends when the last of those turns ends.

const CD := 4
const STR_PCT := 20
const TURNS := 2


func _init() -> void:
	define({
		"key": "war_cry", "name": "War Cry", "weapon": "axe", "clip": "war_cry",
		"desc": "Roar (uses your action): +20% STR for your next 2 turns",
		"targeting": "self", "needs_element": false, "range": 0, "cd": CD,
		"power": 0,
		"retired": true,
	}, 315)


func plan(_b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.notes.append("War Cry: +%d%% STR (+%d) for your next %d turns" % [STR_PCT, bonus(u), TURNS])


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	var old := int(u.fx.get("war_cry", 0))
	if old > 0:                                        # a fresh cry replaces the old one
		u.battle_mods["str"] = int(u.battle_mods.get("str", 0)) - old
	var amt := bonus(u)
	u.battle_mods["str"] = int(u.battle_mods.get("str", 0)) + amt
	u.fx["war_cry"] = amt
	u.fx["war_cry_left"] = TURNS + 1                   # this turn's end, then two more
	b._emit({ "type": "stat_up", "unit": u.id, "stats": ["str"], "amount": amt, "source": id, "name": "War Cry" })
	var cb := Callable(self, "_tick").bind(u)
	if not b.event.is_connected(cb):
		b.event.connect(cb)
	return 0


func _tick(e: Dictionary, u: BWUnit) -> void:
	if e.type != "turn_end" or str(e.get("unit", "")) != u.id or int(u.fx.get("war_cry", 0)) <= 0:
		return
	u.fx["war_cry_left"] = int(u.fx.get("war_cry_left", 1)) - 1
	if int(u.fx.war_cry_left) <= 0:
		u.battle_mods["str"] = int(u.battle_mods.get("str", 0)) - int(u.fx.war_cry)
		u.fx.erase("war_cry")


func bonus(u: BWUnit) -> int:
	return maxi(1, roundi((u.stat("str") - int(u.fx.get("war_cry", 0))) * STR_PCT / 100.0))


## D112: roar when nothing is in reach now but a foe will be next turn.
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	if int(u.fx.get("war_cry", 0)) > 0 or not b.attack_targets(u).is_empty():
		return {}
	var reach := u.move_range() + b.weapon_range(u) + 1
	for f in b.foes_of(u):
		if b.gap(u, f) <= reach:
			return { "target": u.pos, "element": "", "score": 5.0 }
	return {}
