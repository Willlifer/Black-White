extends BWSkillDef
## Axe (D104; reworked D415: "Sunder should function like Ley Line. Like
## you're impacting the earth."). A splitting blow at an adjacent foe that
## ignores DEF_IGNORE% of its DEF and can't glance (that blow only). The
## ground then splits in a straight line from you THROUGH the target, LEN
## hexes in all (the target's hex + LEY_LEN more): every hex of it takes your
## element (painted like Ley Line), and every other foe standing on it is hit
## at LINE_PCT% power. Jagged rock and ice pillars stop the fissure.
## Earthsplitter (D416) is the other axe line: aimed anywhere, no paint, it
## heaves the foes on it back a hex; Sunder is the anchored blow that marks
## the earth.

const POWER := 13
const CD := 3
const DEF_IGNORE := 30
const LINE_PCT := 60
const LEN := BWSkills.LEY_LEN + 1        # 5: the target's hex + 4 beyond
const BELLOW_LEN := 10                   # D436: a Bellow doubles the fissure
const Bellow := preload("res://src/core/skill_defs/bellow.gd")


func _init() -> void:
	define({
		"key": "sunder", "name": "Sunder", "weapon": "axe", "clip": "",
		"desc": "A splitting blow at an adjacent enemy: ignores 30% of its DEF and can't glance. The ground splits on through it, 4 more tiles in a line: the line takes your element, and other enemies on it are hit at 60%. Rock stops the split",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
	}, 313)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	p.victims = b._foes_on(u, [target])
	if not p.victims.is_empty():
		p["sunder_main"] = (p.victims[0] as BWUnit).id
	p.hexes = fissure(b, u, target, BELLOW_LEN if Bellow.held(u) else LEN)
	if Bellow.held(u):
		p.notes.append("Bellow: the fissure doubles, up to %d tiles" % BELLOW_LEN)
	var hit: Array = []
	for o in b._foes_on(u, p.hexes):
		if not o in p.victims:
			p.victims.append(o)
			p.shares[o.id] = [LINE_PCT / 100.0, "Sunder fissure (%d%%)" % LINE_PCT, "Sunder"]
			hit.append(o.name)
	var line := "Fissure: %d tiles take %s" % [p.hexes.size(), element if element != "" else "the split"]
	if not hit.is_empty():
		line += "; %s hit at %d%%" % [", ".join(hit), LINE_PCT]
	p.notes.append(line)


## The fissure: from `u` through `target` (adjacent), LEN hexes, the target's
## hex first. Stops before jagged rock, an ice pillar or the map's edge.
static func fissure(b: BWBattle, u: BWUnit, target: Vector2i, length: int = LEN) -> Array:
	var out: Array = []
	for h in b.board.ray(u.pos, target, length):
		if out.is_empty() and h != target:
			break                               # a multi-hex foe off the heading: the target's hex only
		if not b.board.is_passable(h) or b.board.blocked(h):
			break
		out.append(h)
	if out.is_empty():
		out = [target]
	return out


## D436: a Bellow is spent by the blow.
func after_hits(b: BWBattle, u: BWUnit, _p: Dictionary, _results: Array) -> void:
	Bellow.spend(b, u, id)


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, v: BWUnit, p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	if v == null or v.id != str(p.get("sunder_main", "")):
		return                                  # the fissure's graze is a plain 60% hit
	mods.append({ "stage": "def_ignore", "value": DEF_IGNORE / 100.0, "label": "Sunder (%d%%)" % DEF_IGNORE })
	mods.append({ "stage": "glance_x", "value": 0.0, "label": "Sunder: can't glance" })
