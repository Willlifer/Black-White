extends BWSkillDef
## D295 Tidal Release, water's keystone ACTION (design/ELEMENTS-v3.md §4):
## cooldown 4. Click a pool hex within 3, then the heading (the second pick,
## D109). The pool drains; a wave runs along the line (length = the pool's
## size, max 6) pushing every unit on it 3 along it (slams; onto glaze it just stops);
## the line gets water 2. Rules: BWKsWater.

const NOWHERE := Vector2i(-9999, -9999)


func _init() -> void:
	define({
		"key": "tidal_release", "name": "Tidal Release", "weapon": "keystone", "clip": "cast",
		"desc": "Cooldown 4. Pick a pool hex within 3 and a heading: the pool drains and a wave (the pool's size, max 6) runs along the line, pushing everyone on it 3 (slams; onto glaze it just stops); the line gets water 2",
		"targeting": "hex", "needs_element": false, "range": BWKsWater.TIDAL_RANGE, "cd": 4, "second_pick": "hex",
		"power": 0, "min_range": 0, "keystone": true,
	}, 9020)


func target_ok(b: BWBattle, _u: BWUnit, h: Vector2i, _element: String) -> bool:
	return BWKsWater.tidal_ok(b, h)


## D109: the six headings, as the neighbour hexes on the map.
func second_targets(b: BWBattle, _u: BWUnit, _element: String, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in 6:
		var n: Vector2i = BWHex.neighbors(target)[d]
		if b.board.exists(n):
			out.append(n)
	return out


## The heading: the player's pick, else the AI's best (or away from the caster).
func heading(b: BWBattle, u: BWUnit, target: Vector2i, choice: Vector2i) -> int:
	if choice != NOWHERE:
		return BWHex.direction_index(target, choice)
	var best := BWKsWater.ai_tidal(b, u, { "key": id })
	if not best.is_empty() and best.target == target:
		return BWHex.direction_index(target, best.choice)
	var d := BWBattle.pulse_heading(u.pos, target, true) if u.pos != target else u.facing
	return maxi(d, 0)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var d := heading(b, u, target, p.get("choice", NOWHERE))
	var line := BWKsWater.wave_line(b, target, d)
	if line.is_empty():
		return
	p.hexes = line.duplicate()
	p["wave"] = { "dir": d, "line": line }
	p.notes.append("Tidal Release: the pool (%d) drains; a %d-hex wave pushes everyone on it %d; the line gets water %d" % [
		BWPools.pool(b.tiles, target).size(), line.size(), BWKsWater.WAVE_PUSH, BWKsWater.WAVE_WATER])


func ground(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, p: Dictionary) -> int:
	var w: Dictionary = p.get("wave", {})
	if not w.is_empty():
		BWKsWater.release(b, u, target_hex, int(w.dir))
	return 0


func ai_support(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	return BWKsWater.ai_tidal(b, u, row)
