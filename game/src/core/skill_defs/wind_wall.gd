extends BWSkillDef
## D273 Wind Wall, wind's keystone ACTION (design/ELEMENTS-v3.md §1 and the
## author's ruling: blocks movement and skills both ways, basic attacks pierce
## it). Weapon "keystone": it joins no class's pool; BWBattle.skills_for adds
## it for a unit that holds it (BWWind.has_wind_wall: the wind_wall keystone,
## BWKeystones; D293 replaced the D273 flag).
##
## Click the first hex (empty, within 3), then the second (the line's
## heading): a line of 3 empty hexes stands for 2 ticks. One wall per unit (a
## new one takes the old down). Cooldown 3. The walls are BWBattle.wind; the
## board's blocker reads them (moves, pushes, slides, charges), skill targets
## are filtered (BWWind.filter_targets), sight is untouched (basics pierce).

const NOWHERE := Vector2i(-9999, -9999)


func _init() -> void:
	define({
		"key": "wind_wall", "name": "Wind Wall", "weapon": "keystone", "clip": "",
		"desc": "Raise a line of 3 wind-wall hexes (empty hexes, the first within 3) for 2 ticks: it blocks movement and skills both ways; basic attacks pierce it. One wall at a time",
		"targeting": "hex", "needs_element": false, "range": BWWind.WALL_RANGE, "cd": 3, "second_pick": "hex",
		"power": 0, "min_range": 1, "keystone": true,
	}, 9000)


func target_ok(b: BWBattle, _u: BWUnit, h: Vector2i, _element: String) -> bool:
	return not BWWind.wall_dirs(b, h).is_empty()


## D109: the second hex of every legal line from the first.
func second_targets(b: BWBattle, _u: BWUnit, _element: String, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in BWWind.wall_dirs(b, target):
		out.append(BWHex.neighbors(target)[d])
	return out


## The heading: the player's second pick, else the one most across the
## caster's line of sight (a screen in front of it).
func heading(b: BWBattle, u: BWUnit, target: Vector2i, choice: Vector2i) -> int:
	var dirs := BWWind.wall_dirs(b, target)
	if dirs.is_empty():
		return -1
	if choice != NOWHERE:
		var d := BWHex.direction_index(target, choice)
		return d if d in dirs else -1
	var d0 := BWHex.direction_index(u.pos, target)
	for d in [(d0 + 2) % 6, (d0 + 4) % 6, (d0 + 1) % 6, (d0 + 5) % 6, d0, (d0 + 3) % 6]:
		if d in dirs:
			return d
	return dirs[0]


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var d := heading(b, u, target, p.get("choice", NOWHERE))
	if d < 0:
		return
	p["wall"] = BWWind.wall_line(b, target, d)
	p.hexes = (p.wall as Array).duplicate()          # the shape the aim shows (ground() paints nothing)
	p.notes.append("Wind Wall: 3 hexes for %d ticks; blocks moves and skills both ways, basic attacks pierce it" % BWWind.WALL_TICKS)


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	var w: Array = p.get("wall", [])
	if w.size() == BWWind.WALL_LEN:
		BWWind.raise_wall(b, u, w)
	return 0


## D293: the AI raises a wall against a ranged threat (BWKsWind.ai_wall).
func ai_support(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	return BWKsWind.ai_wall(b, u, row)
