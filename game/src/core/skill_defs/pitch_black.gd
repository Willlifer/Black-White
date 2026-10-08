extends BWSkillDef
## D449 Pitch Black, Abyssal's free action (Keystones v3): once per turn,
## range 3, a dark 3 hex (anyone's). It is overcharged (dark 4 for the rest of
## your turn, dark 3 after) and explodes: 15% (dark) and +1 Rot to every foe
## within 1 (2 with Superconductor). The hex is not consumed. Weapon
## "keystone": in no class's pool; BWKeystones.skills lists it for a holder.
## Rules: BWKs3Dark.burst.


func _init() -> void:
	define({
		"key": "pitch_black", "name": "Pitch Black", "weapon": "keystone", "clip": "cast",
		"desc": "Free (Abyssal), once a turn, range 3: overcharge a dark 3 hex. It explodes: 15% and +1 Rot to every foe within 1. The hex stays (dark 4 until your turn ends)",
		"targeting": "hex", "needs_element": false, "range": 3, "cd": 0, "min_range": 0,
		"power": 0, "free_action": true, "keystone": true,
	}, 9040)


func targets(b: BWBattle, u: BWUnit, _element: String) -> Array[Vector2i]:
	return BWKs3Dark.targets(b, u, "pitch_black")


func target_ok(b: BWBattle, u: BWUnit, h: Vector2i, _element: String) -> bool:
	return h in BWKs3Dark.targets(b, u, "pitch_black")


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var r := BWKs3Dark.radius(u, "pitch_black")
	p.hexes = b.board.area(target, r)
	var n := BWKs3Dark.near(b, u, target, r, true).size()
	p.notes.append("Pitch Black: %d%% and +1 Rot to %d foe%s within %d; the hex stays (dark 4 this turn)" % [
		int(BWKeystones.param("abyssal", "pct", 15)), n, "" if n == 1 else "s", r])


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, _p: Dictionary) -> int:
	BWKs3Dark.burst(b, u, target_hex, "pitch_black")
	return 0


## The AI opens its turn with it when a foe is in a burst.
func ai_opener(b: BWBattle, u: BWUnit, _row: Dictionary) -> Dictionary:
	return BWKs3Dark.ai_pick(b, u, "pitch_black")
