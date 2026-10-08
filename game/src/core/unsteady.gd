class_name BWUnsteady
extends RefCounted
## D397-D399 Unsteady footing (the author, 2026-10-07: "ice does not feel
## good. I would remove rink as a status, have ice apply 'unsteady footing',
## dropping dodge and glance chance for units on the tile."). Rules as built:
## design/ELEMENTS.md §14.1. Glaze is no longer slippery (the D261 slides are
## gone); it is bad footing instead. Pure rules over the battle, no nodes.
##
## UNSTEADY: a unit whose centre hex is GLAZED (glaze > 0, not a pillar) has
## AVOID_PCT less avoid and GLANCE_PCT less glance chance against every blow,
## both teams, for as long as it stands there. Stasis markers (ice armed on
## empty ground, glaze 0) don't count: there's no ice sheet yet. It stacks
## with Shatter (+15% damage on glaze), so a unit on glaze is easier to hit,
## glances less and takes more.
##   * the lingering status "unsteady" (Sure-Footed's rider) applies the same
##     numbers off the glaze, until the end of the unit's next turn;
##   * Ice Legs (the perk, effect key "skate") is never Unsteady;
##   * Sure-Footed (keystone id "skater", kept for saves) covers its holder
##     and allies within SURE_RADIUS; a foe that WALKS off the holder's glaze
##     stays Unsteady (the status) until the end of its next turn.

const AVOID_PCT := 10.0
const GLANCE_PCT := 15.0
const SURE := "skater"            # the keystone id (display name Sure-Footed)
const SURE_RADIUS := 2
const STATUS := "unsteady"
const AI_HAZARD := 4.0            # % max HP the AI reads standing Unsteady as (~ the extra damage it invites)


## Glazed ground a unit can stand on (a pillar is glazed but impassable).
static func on_glaze(tiles: BWTiles, h: Vector2i) -> bool:
	return tiles.is_glazed(h) and not tiles.is_pillar(h)


## Ice Legs: never Unsteady.
static func ice_legs(u: BWUnit) -> bool:
	return BWEffects.has(u, "skate")


## The Sure-Footed holder covering `u` standing at `at` (itself or an ally
## within SURE_RADIUS), else null.
static func sure_cover(b: BWBattle, u: BWUnit, at: Vector2i = BWBattle.NOWHERE) -> BWUnit:
	for o in b.units:
		if o.alive() and o.team == u.team and BWKeystones.has(o, SURE):
			if o == u or b.gap(u, o, at) <= SURE_RADIUS:
				return o
	return null


## Is `u` immune at `at` (Ice Legs, or a Sure-Footed cover)?
static func immune(b: BWBattle, u: BWUnit, at: Vector2i = BWBattle.NOWHERE) -> bool:
	return u != null and (ice_legs(u) or sure_cover(b, u, at) != null)


## Is `u` Unsteady now? On glaze or holding the status, and not immune.
## Stone objectives never are.
static func unsteady(b: BWBattle, u: BWUnit) -> bool:
	if u == null or not u.alive() or BWObelisk.is_objective(u):
		return false
	if not on_glaze(b.tiles, u.pos) and not u.statuses.has(STATUS):
		return false
	return not immune(b, u)


## Would `u` be Unsteady standing on `h` (the AI's hex scoring)?
static func unsteady_at(b: BWBattle, u: BWUnit, h: Vector2i) -> bool:
	if u == null or BWObelisk.is_objective(u) or not on_glaze(b.tiles, h):
		return false
	return not immune(b, u, h)


## BWBattle._mods: the two named lines ("Unsteady footing -10 avoid",
## "-15 glance"), or a note when an immunity spares a unit on glaze.
static func mods(b: BWBattle, dfn: BWUnit, out: Array) -> void:
	if dfn == null or BWObelisk.is_objective(dfn):
		return
	var glazed := on_glaze(b.tiles, dfn.pos)
	if not glazed and not dfn.statuses.has(STATUS):
		return
	if immune(b, dfn):
		if glazed:
			var why := "Ice Legs" if ice_legs(dfn) else "Sure-Footed (%s)" % sure_cover(b, dfn).name
			out.append({ "stage": "note", "value": 0.0, "label": "Unsteady footing: %s ignores it" % why })
		return
	var src := "" if glazed else " (stepped off the ice)"
	out.append({ "stage": "avoid", "value": -AVOID_PCT, "tag": "Unsteady",
		"label": "Unsteady footing −%d avoid%s" % [int(AVOID_PCT), src] })
	out.append({ "stage": "glance", "value": -GLANCE_PCT, "tag": "Unsteady",
		"label": "Unsteady footing −%d glance%s" % [int(GLANCE_PCT), src] })


## BWBattle.move, after a walk: Sure-Footed's rider. A foe of a holder that
## walked OFF the holder's glaze (started on it, ended off glaze) keeps
## Unsteady until the end of its next turn.
static func after_walk(b: BWBattle, u: BWUnit, path: Array) -> void:
	if path.size() < 2 or not u.alive() or on_glaze(b.tiles, u.pos):
		return
	var start: Vector2i = path[0]
	if not on_glaze(b.tiles, start):
		return
	var src := b._unit(str(b.tiles.at(start).get("glaze_source", "")))
	if src == null or src.team == u.team or not BWKeystones.has(src, SURE):
		return
	b._add_status(u, STATUS, src, 0)            # its "status" event floats UNSTEADY and logs the rule


## The AI's hex score: standing Unsteady invites hits (BWAI._best_hex).
static func ai_hazard(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	return AI_HAZARD if unsteady_at(b, u, h) else 0.0


## The tile card's line ([title, words]) for glazed ground.
static func card_line(b: BWBattle, h: Vector2i) -> Array:
	if not on_glaze(b.tiles, h):
		return []
	var words := "a unit standing here has −%d avoid and −%d glance chance (Shatter: hits on it +%d%%)" % [
		int(AVOID_PCT), int(GLANCE_PCT), int(BWTiles.SHATTER_HIT_PCT)]
	var u := b._centre_at(h)
	if u != null:
		if ice_legs(u):
			words += ". %s has Ice Legs: unaffected" % u.name
		elif sure_cover(b, u) != null:
			words += ". %s is Sure-Footed (%s): unaffected" % [u.name, sure_cover(b, u).name]
	return ["Unsteady", words]
