extends BWSkillDef
## Axe. Sweep CLEAVE_ARC hexes beside you (V8 _cleave_arc). D433: if any
## hex of that arc already holds your element, the swing widens to all six
## hexes around you (was: carried a ring further). D436 Bellow: the next
## Cleave (or Sunder) after a Bellow doubles: the six around you plus the five
## ring-2 hexes in front (11). D87: +10% to everyone per foe caught beyond
## the first; Cleave+ (D104) +PLUS_PER_FOE_PCT%.

const PLUS_PER_FOE_PCT := 15
const Bellow := preload("res://src/core/skill_defs/bellow.gd")


func _init() -> void:
	define({
		"key": "cleave", "name": "Cleave", "weapon": "axe", "clip": "cut",
		"desc": "Sweep 3 tiles beside you. If any of them already holds your element, the swing widens to all 6 tiles around you. +10% to everyone per foe caught beyond the first",
		"plus": "Cleave+: +15% per extra foe (from +10%)",
		"targeting": "dir", "needs_element": true, "range": 1, "cd": BWSkills.DEFAULT_CD,
		"power": BWSkills.CLEAVE_DMG, "aoe": true,
	}, 50)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	var arc := arc_from(b, u.pos, target)
	p.hexes = arc
	if Bellow.held(u):                 # D436: doubled
		p.hexes = bellowed(b, u.pos, target)
		p.notes.append("Bellow: the swing doubles, %d tiles (the 6 around you and 5 beyond in front)" % (p.hexes as Array).size())
	else:
		for h in arc:                  # read before anything is laid
			if b.tiles.carries(h, element):
				p.hexes = b._on_board(BWHex.neighbors(u.pos))
				p.notes.append("Your %s is in the arc: the swing widens to all 6 tiles around you" % element)
				break
	p.victims = b._foes_on(u, p.hexes)


## D436: a Bellow is spent by the swing.
func after_hits(b: BWBattle, u: BWUnit, _p: Dictionary, _results: Array) -> void:
	Bellow.spend(b, u, id)


## D436: the six around `from` and the five ring-2 hexes centred on the
## heading (those within 2 of the hex 2 straight ahead).
static func bellowed(b: BWBattle, from: Vector2i, toward: Vector2i) -> Array:
	var out: Array = b._on_board(BWHex.neighbors(from))
	var di := BWHex.direction_index(from, toward)
	if di < 0:
		return out
	var ahead := BWHex.neighbors(BWHex.neighbors(from)[di])[di]
	for h in BWHex.ring(from, 2):
		if BWHex.distance(h, ahead) <= 2 and b.board.exists(h):
			out.append(h)
	return out


func forecast_mods(_b: BWBattle, u: BWUnit, _el: String, _v: BWUnit, p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	var n: int = (p.get("victims", []) as Array).size()
	var per := BWSkills.CLEAVE_PER_FOE_PCT
	if upgraded(u):
		per = PLUS_PER_FOE_PCT
	if n > 1:
		mods.append({ "stage": "dmg", "value": 1.0 + per * (n - 1) / 100.0,
			"label": "%s: %d foes caught (+%d%%)" % ["Cleave+" if upgraded(u) else "Cleave", n, per * (n - 1)], "tag": "Cleave" })


## V8 _cleave_arc: CLEAVE_ARC contiguous neighbours centred on the heading.
static func arc_from(b: BWBattle, from: Vector2i, toward: Vector2i) -> Array:
	var di := BWHex.direction_index(from, toward)
	if di < 0:
		return []
	var nbrs := BWHex.neighbors(from)
	var half := BWSkills.CLEAVE_ARC / 2
	var out: Array = []
	for off in range(-half, half + 1):
		var h: Vector2i = nbrs[(di + off + 6) % 6]
		if b.board.exists(h):
			out.append(h)
	return out
