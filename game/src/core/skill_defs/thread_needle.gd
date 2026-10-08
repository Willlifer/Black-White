extends BWSkillDef
## Sword. D438 (replaces Heart Seeker, retired): strike an adjacent foe that
## stands on your element (the element you cast in), then thread the line:
## dash on through its hex, straight on along the hexes beyond it that hold
## that element, up to LEN of them, to the line's far end. The run stops
## before a hex without the element, a unit, rock or a climb too steep; with
## nothing beyond, it is just the strike. The ground is read before the strike
## paints. Riding your own line never burns you: a fire Thread takes no
## crossing damage (Claude, D438; Lunge and Charge still burn).

const POWER := 11
const CD := 2
const LEN := 3


func _init() -> void:
	define({
		"key": "thread_needle", "name": "Thread the Needle", "weapon": "sword", "clip": "thrust",
		"desc": "Strike an adjacent enemy standing on your element, then dash on through it along that element's line, up to 3 tiles, to its far end (a unit, rock or a tile without the element stops you)",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
	}, 301)


## Only a foe standing on the element.
func target_ok(b: BWBattle, _u: BWUnit, h: Vector2i, element: String) -> bool:
	var v := b.unit_at(h)
	return v != null and v.size <= 1 and b.tiles.carries(h, element)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	var run := thread(b, u, element, target)
	p["thread"] = run
	if run.is_empty():
		p.notes.append("No %s beyond it: just the strike" % element)
	else:
		p.notes.append("Then dash %d along your %s through %s to the line's end" % [run.size(), element,
			(p.victims[0] as BWUnit).name if not p.victims.is_empty() else "it"])


## The hexes beyond `target` (straight on from `u`) that carry `element`,
## free to stand on, up to LEN; stops at the first that isn't.
static func thread(b: BWBattle, u: BWUnit, element: String, target: Vector2i) -> Array:
	var out: Array = []
	if BWHex.distance(u.pos, target) != 1:
		return out
	var opts := { "jump": BWWeaponMove.jump(u) }
	var prev := target
	for h in b.board.ray(u.pos, target, LEN + 1):
		if h == target:
			continue
		if not b.tiles.carries(h, element) or b.unit_at(h) != null:
			break
		if b.board.step_cost(prev, h, opts) < 0 or not b.can_stand(u, h):
			break
		out.append(h)
		prev = h
	return out


## Strike, then dash: the run happens once the blow and its paint landed.
func after_paint(b: BWBattle, u: BWUnit, _el: String, target_hex: Vector2i, p: Dictionary,
		_results: Array, _stripped: int) -> void:
	var run: Array = p.get("thread", [])
	if run.is_empty():
		return
	var dest: Vector2i = run[-1]
	if not b.can_stand(u, dest) or b.unit_at(dest) != null:
		return
	var path: Array = [u.pos, target_hex] + run
	b.skill_relocate(u, { "dest": dest, "shove": {} }, path, "charge")
	b._lay_on_move(u, path)

