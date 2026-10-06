extends BWSkillDef
## Sword (D103). Dash straight up to LEN hexes and strike the first unit in
## the way. A foe takes the hit (and its hex the element); an ally, rock or a
## climb just stops you. Running, so fire on the way burns (like Charge).

const POWER := 11
const CD := 2
const LEN := 3


func _init() -> void:
	define({
		"key": "lunge", "name": "Lunge", "weapon": "sword", "clip": "thrust",
		"desc": "Dash up to 3 tiles in a straight line and strike the first enemy in the way. An ally or rock just stops you",
		"targeting": "dir", "needs_element": true, "range": LEN, "cd": CD,
		"power": POWER,
	}, 304)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var prev := u.pos
	for h in b.board.ray(u.pos, target, LEN):
		var o := b.unit_at(h)
		if o != null and o != u:
			if o.team != u.team:
				p.victims = [o]
				p.hexes = [h]
			break
		if b.board.step_cost(prev, h) < 0 or not b.can_stand(u, h):
			break
		p.walk.append(h)
		prev = h
	p.dest = p.walk[-1] if not p.walk.is_empty() else u.pos
	if p.victims.is_empty():
		p.walk = []                       # nothing to lunge at: not a legal heading
		p.dest = u.pos
	elif not p.walk.is_empty():
		p.notes.append("Dash %d to strike %s" % [p.walk.size(), p.victims[0].name])


func relocate(b: BWBattle, u: BWUnit, p: Dictionary, target_hex: Vector2i) -> void:
	if p.walk.is_empty():
		super.relocate(b, u, p, target_hex)
		return
	var path: Array = [u.pos] + (p.walk as Array)
	b.skill_relocate(u, p, path, "charge")
	for h in p.walk:
		var pct := b.tiles.crossing_pct(h)
		if pct > 0 and u.alive():
			b._tile_hurt(u, b._tile_dmg(u, pct, "fire"), "fire_cross", str(b.tiles.at(h).get("source", "")))
	b._lay_on_move(u, path)
	if not p.victims.is_empty():
		b._face(u, p.victims[0].pos)
