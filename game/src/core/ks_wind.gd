class_name BWKsWind
extends RefCounted
## D293 wind's keystones (design/ELEMENTS-v3.md §1 "Keystones", ELEMENTS.md
## §16.1). Pure rules on top of BWWind (src/core/wind_modes.gd), which calls
## the hooks here. Who holds what is BWKeystones (Lane C1).
##
## Eye of the Vortex  (D408, reworked: the Vortex fields are gone, D406, and a
##                    gale only spreads) your wind skills' DRAW IN reaches
##                    foes within 2 of the area (not 1) and pulls each up to 2
##                    hexes toward its centre, one hex at a time, stopping at
##                    the first blocked hex: no slam on an inward pull. Still
##                    a direct wind move (once per action, 2 hexes a cycle).
## (D443: Eye of the Vortex is an item enchantment now, "{item} of the Vortex";
## Wind Wall and Jetstream were removed with Keystones v3.)
## Glaze carry (D293, the D272 TODO; D398 dropped the "rink" name): a glazed
## hex never fires a gale (wind on glaze does nothing, ELEMENTS-v3 §2), so
## glaze can't be the origin. A gale that fires NEXT TO glaze (a glazed,
## standable hex beside the origin) carries it instead: its WATER copies glaze
## for GLAZE_CARRY cycle (a fire or light copy stays unglazed; Unsteady ground,
## never a pillar: pillars need a fresh ice cast).

const EYE := "eye_of_vortex"
const EYE_RADIUS := 2
const EYE_PULL := 2
const GLAZE_CARRY := 1


static func eye(u: BWUnit) -> bool:
	return u != null and BWKeystones.has(u, EYE)


## Glaze carry (BWWind.carry): a gale that fired beside glaze glazes its water copies.
static func carry_glaze(b: BWBattle, origin: Vector2i, copies: Array) -> void:
	var near := false
	var src := ""
	for n in b.board.neighbors(origin):
		if BWUnsteady.on_glaze(b.tiles, n) and not n in copies:
			near = true
			src = str(b.tiles.at(n).get("glaze_source", ""))
			break
	if not near:
		return
	for c in copies:
		var e: Dictionary = b.tiles.entries.get(c, {})
		if e.is_empty() or b.tiles.pillars.has(c) or str(e.get("marker", "")) != "" or int(e.h) >= 0:
			continue
		if int(e.glaze) <= 0:
			e.glaze = GLAZE_CARRY
			e["glaze_source"] = src
			e["glaze_carry"] = true


# ---------------------------------------------------------------- Eye of the Vortex (D408)

## Draw in for an Eye holder (BWWind.pre_mode): each candidate (foes within
## EYE_RADIUS of the area) is pulled up to EYE_PULL hexes toward `centre`,
## closest first (ties in setup order). `dry`: positions only (the preview
## restores them). Returns { moves, becalm } like BWWind.apply_mode.
static func eye_draw(b: BWBattle, by: BWUnit, cand: Array, centre: Vector2i, reserved: Array = [], dry: bool = false) -> Dictionary:
	var out := { "moves": [], "becalm": [] }
	var rows: Array = []
	for v in cand:
		if v == null or not v.alive() or BWObelisk.is_objective(v) or maxi(v.size, 1) > 1 or v.pos == centre:
			continue
		rows.append([BWHex.distance(centre, v.pos), b.units.find(v), v])
	rows.sort_custom(func(a, c) -> bool: return a[0] < c[0] if a[0] != c[0] else a[1] < c[1])
	for r in rows:
		if b.over:
			break
		var path := pull_in(b, r[2], centre, EYE_PULL, by, reserved, dry)
		if path.size() > 1:
			out.moves.append({ "unit": (r[2] as BWUnit).id, "path": path, "kind": "pull" })
	return out


## Step `v` toward `centre` one hex at a time, up to `n`, stopping before the
## first blocked or reserved hex (no slam). A direct wind move (once per
## action, the cycle budget). Returns the path walked ([start] = no move).
static func pull_in(b: BWBattle, v: BWUnit, centre: Vector2i, n: int, by: BWUnit, reserved: Array = [], dry: bool = false) -> Array:
	if not BWWind.direct_ready(b, v, dry):
		return [v.pos]
	if b._immune(v, "displace"):
		if not dry:
			b._emit({ "type": "displace_resisted", "unit": v.id, "kind": "pull" })
		return [v.pos]
	if not dry and b._negate(v, "displacement"):
		return [v.pos]
	var m := mini(n, BWWind.budget(b, v))
	var path: Array = [v.pos]
	var cur := v.pos
	for i in m:
		var d := BWBattle.pulse_heading(centre, cur, false)
		if d < 0:
			break
		var nxt: Vector2i = BWHex.neighbors(cur)[d]
		if nxt in reserved or b.board.step_cost(cur, nxt) < 0 or not b.can_stand(v, nxt):
			break
		cur = nxt
		path.append(cur)
	if not dry:
		BWWind._spend(b, v, false, path.size() - 1)
	if path.size() < 2:
		return path
	v.pos = cur
	if not dry:
		b._emit({ "type": "move", "unit": v.id, "path": path, "kind": "pull", "wind": true, "eye": true })
	return path
