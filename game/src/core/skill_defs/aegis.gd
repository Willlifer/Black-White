extends BWSkillDef
## RETIRED (D442: removed): never offered; the def stays for old saves, which map it
## (BWSkillRegistry.RENAMED, migrate_unit). Its helpers may still be shared.
## Staff spell (D107). Ward one ally within RANGE (not yourself): it takes
## GUARD_PCT% less damage until the end of its next turn. The ward is the FX
## `guard` (Phalanx.guard); the battle drops guards when the holder's turn
## starts, so Aegis puts it back up at that turn's start and takes it down at
## that turn's end (listening to BWBattle.event).

const Phalanx := preload("res://src/core/skill_defs/phalanx.gd")

const CD := 4
const RANGE := 4
const GUARD_PCT := 20


func _init() -> void:
	define({
		"key": "aegis", "name": "Aegis", "weapon": "staff", "clip": "",
		"desc": "Ward an ally up to 4 tiles away: it takes 20% less damage until the end of its next turn",
		"targeting": "hex", "needs_element": false, "range": RANGE, "cd": CD,
		"power": 0, "min_range": 1, "los": true, "spell": true,
		"retired": true,
	}, 344)


func target_ok(b: BWBattle, u: BWUnit, h: Vector2i, _element: String) -> bool:
	var a := b._centre_at(h)
	return a != null and a != u and a.team == u.team


func plan(b: BWBattle, _u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var a := b._centre_at(target)
	if a != null:
		p.notes.append("Aegis: %s takes -%d%% damage until its next turn ends" % [a.name, GUARD_PCT])


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, _p: Dictionary) -> int:
	var a := b._centre_at(target_hex)
	if a == null:
		return 0
	Phalanx.guard(b, a, GUARD_PCT, "Aegis")
	a.fx["aegis"] = 1                       # its next turn still to come
	var cb := Callable(self, "_hold").bind(a)
	if not b.event.is_connected(cb):
		b.event.connect(cb)
	return 0


## Through the ward's own next turn: up again at its start, down at its end.
func _hold(e: Dictionary, a: BWUnit) -> void:
	if str(e.get("unit", "")) != a.id or not a.fx.has("aegis"):
		return
	if e.type == "turn":
		a.fx["guard"] = maxf(float(a.fx.get("guard", 0)), float(GUARD_PCT))
		a.fx["guard_name"] = "Aegis: -%d%%" % GUARD_PCT
	elif e.type == "turn_end":
		a.fx.erase("aegis")
		if str(a.fx.get("guard_name", "")).begins_with("Aegis"):
			a.fx.erase("guard")


## D112: ward the most threatened ally under 60% HP.
func ai_support(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	var best := {}
	for h in b.skill_targets(u, id, ""):
		var a := b._centre_at(h)
		if a == null or a.fx.has("aegis"):
			continue
		var frac := float(a.hp) / maxf(a.max_hp(), 1.0)
		var threat := BWAI.threat(b, a, a.pos)
		if frac >= 0.6 or threat == 0:
			continue
		var score := 4.0 + 3.0 * threat + 10.0 * (0.6 - frac)
		if best.is_empty() or score > best.score:
			best = { "target": h, "element": "", "score": score }
	return best
