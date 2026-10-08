extends BWSkillDef
## Sword. D439 (replaces Triumph, retired): once per battle, every hex on
## the map holding your element (the one you cast in, whoever laid it)
## pulses. A foe standing on one takes PULSE_PCT% of its max HP as ground
## damage of that element (resistance applies, like any tile damage); an
## ally standing on one, you included, is Swift (+1 move) on its next turn.
## Nothing is painted and nothing is consumed: the lines stay. Uses the action.

const PULSE_PCT := 10.0
const ONCE_CD := 999


func _init() -> void:
	define({
		"key": "tapestry", "name": "Tapestry", "weapon": "sword", "clip": "brace",
		"desc": "Once per battle: every tile holding your element pulses. Enemies on them take 10% of their max HP; allies on them (you too) get +1 move next turn",
		"targeting": "self", "needs_element": true, "range": 0, "cd": 0, "once_per_battle": true,
		"power": 0,
	}, 302)


func plan(b: BWBattle, u: BWUnit, element: String, _target: Vector2i, p: Dictionary) -> void:
	var hexes := pulse_hexes(b, element)
	p["pulse"] = hexes                    # never painted: p.hexes stays empty (no paint riders)
	var hit: Array = []
	var swift: Array = []
	for o in b.units:
		if not o.alive() or not o.pos in hexes:
			continue
		if o.team == u.team:
			swift.append(o.name)
		elif b.can_harm(u, o):
			hit.append("%s %d" % [o.name, b._tile_dmg(o, PULSE_PCT, element)])
	p.notes.append("Tapestry: %d tiles of %s pulse" % [hexes.size(), element])
	if not hit.is_empty():
		p.notes.append("Foes on them take %d%%: %s" % [int(PULSE_PCT), ", ".join(hit)])
	if not swift.is_empty():
		p.notes.append("Swift (+1 move next turn): %s" % ", ".join(swift))


static func pulse_hexes(b: BWBattle, element: String) -> Array:
	var out: Array = []
	if element == "":
		return out
	var keys: Array = b.tiles.entries.keys()
	keys.sort()
	for h in keys:
		if b.tiles.carries(h, element):
			out.append(h)
	return out


## The pulse: no paint. Foes take the ground damage, allies turn Swift.
func ground(b: BWBattle, u: BWUnit, el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	var hexes: Array = p.get("pulse", [])
	b._emit({ "type": "tapestry", "unit": u.id, "element": el, "hexes": hexes.duplicate() })
	for o in b.units.duplicate():
		if b.over or not o.alive() or not o.pos in hexes:
			continue
		if o.team == u.team:
			b._add_status(o, "swift", u)
		elif b.can_harm(u, o):
			b._tile_hurt(o, b._tile_dmg(o, PULSE_PCT, el), "tapestry", u.id)
	return 0


## The view's pulse reads the hexes off the skill event.
func decorate(e: Dictionary, p: Dictionary) -> void:
	e["pulse"] = (p.get("pulse", []) as Array).duplicate()


## Once per battle: every element of it goes dark.
func cooldown(u: BWUnit) -> int:
	for e in [""] + BWFormulas.ELEMENTS:
		u.cooldowns[BWSkills.cd_key(id, e)] = ONCE_CD
	return ONCE_CD


## D112: pulse when it lands real damage (two foes, or a KO), counting a
## little for each ally made Swift.
func ai_support(b: BWBattle, u: BWUnit, row: Dictionary) -> Dictionary:
	var best := {}
	for el in row.get("elements", []):
		var hexes := pulse_hexes(b, str(el))
		var score := 0.0
		var foes := 0
		for o in b.units:
			if not o.alive() or not o.pos in hexes:
				continue
			if o.team == u.team:
				score += 1.0
			elif b.can_harm(u, o):
				var d := float(b._tile_dmg(o, PULSE_PCT, str(el)))
				score += d + (1000.0 if d >= o.hp else 0.0)
				foes += 1
		if (foes >= 2 or score >= 1000.0) and (best.is_empty() or score > float(best.score)):
			best = { "target": u.pos, "element": el, "score": score }
	return best
