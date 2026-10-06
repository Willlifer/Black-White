extends BWSkillDef
## Sword (D103). A cut for POWER x MULT that lays the element twice on the
## target's hex: an axis element +2 steps; thunder detonates (if there is
## charge to blow) and re-arms a fuse; ice glazes for GLAZE_CYCLES (a charged
## hex; bare ground takes a stasis marker); wind's gale copies last
## GALE_CYCLES.

const POWER := 10
const MULT := 1.5
const CD := 4
const GLAZE_CYCLES := 4
const GALE_CYCLES := 2


func _init() -> void:
	define({
		"key": "elemental_truth", "name": "Elemental Truth", "weapon": "sword", "clip": "",
		"desc": "A cut for x1.5 that applies the element twice to the target's hex: fire, water, light or dark +2 steps; thunder detonates then re-arms; ice glazes 4 cycles; wind's gale copies last 2 cycles",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": CD,
		"power": POWER,
	}, 305)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	p.victims = b._foes_on(u, [target])
	if element in BWTiles.AXIS:
		p.steps = 2
	p.notes.append(describe(b, element, target))


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		mods: Array, _notes: Array) -> void:
	mods.append({ "stage": "dmg", "value": MULT, "label": "Elemental Truth: x%.1f" % MULT })


## What the double application will do, in words (the hint and forecast).
func describe(b: BWBattle, element: String, hex: Vector2i) -> String:
	match element:
		"thunder":
			return "Thunder twice: detonates the charge, then re-arms a fuse" if b.tiles.charged(hex) \
				else "Thunder twice: arms a fuse (no charge to detonate)"
		"ice":
			return "Ice twice: glazed for %d cycles" % GLAZE_CYCLES if b.tiles.charged(hex) \
				else "Ice twice: a stasis marker (bare ground can't glaze)"
		"wind":
			return "Wind twice: the gale's copies last %d cycles" % GALE_CYCLES
	return "%s twice: +2 steps" % element.capitalize()


func ground(b: BWBattle, u: BWUnit, el: String, target_hex: Vector2i, p: Dictionary) -> int:
	match el:
		"thunder":
			b.paint(p.hexes, el, u)          # detonate (or arm) ...
			b.paint(p.hexes, el, u)          # ... then arm again
		"ice":
			b.paint(p.hexes, el, u)
			if b.tiles.is_glazed(target_hex):
				b.tiles.entries[target_hex].glaze = maxi(int(b.tiles.entries[target_hex].glaze), GLAZE_CYCLES)
		"wind":
			var r := b.paint(p.hexes, el, u)
			for g in r.get("gales", []):
				for c in g.copies:
					if b.tiles.entries.has(c):
						b.tiles.entries[c].timer = maxi(int(b.tiles.entries[c].timer), GALE_CYCLES)
		_:
			return super.ground(b, u, el, target_hex, p)
	return 0
