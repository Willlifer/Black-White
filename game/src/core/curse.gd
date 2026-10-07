class_name BWCurse
extends RefCounted
## D275-D276 Dark: curse and gravity (design/ELEMENTS-v3.md, the author's
## rulings of 2026-10-07, "Dark"). Dark keeps its rules (concealment, the
## dark 3 drain, Shrouded, its perks) and gains two base facets. Pure rules;
## the battle calls the hooks marked "D275" in battle.gd.
##
## Rot (curse): a foe ending its turn on YOUR dark (any level, laid by a unit
## of the other side) gains 1 Rot, up to ROT_MAX, for the rest of the battle.
## Each Rot is +ROT_PCT% damage taken from every source (blows, through
## BWBattle._mods; ground, blasts and slams, through _tile_dmg). A light heal
## on the unit removes 1. Stored as fx["rot"] (per battle, cloned).
##
## Gravity (void): YOUR dark 3 pulls on your foes; it never changes a tile.
##   * a foe's voluntary step OUT of it costs +1 move (BWBattle._reach_fx);
##   * a displacement of a foe within GRAVITY_REACH of it goes 1 further when
##     it heads toward it, 1 shorter when it heads away (BWBattle._displace,
##     BWWind.push), inside the wind caps.
##
## Lane C keystones hook in here: Contagion (on_ko), Doom (add_rot reaching
## ROT_MAX), Event Horizon (tick, and gravity_reach).

const ROT_MAX := 3
const ROT_PCT := 5
const GRAVITY_REACH := 1        # a foe on or beside your dark 3 feels it
const GRAVITY_LEVEL := 3


# ---------------------------------------------------------------- Rot

static func rot(u: BWUnit) -> int:
	return int(u.fx.get("rot", 0)) if u != null else 0


## Add `n` Rot (negative removes) to `v`, capped 0..ROT_MAX; emits `rot`
## { unit, stacks, delta, by }. Returns the new count.
## Lane C: Doom fires when this reaches ROT_MAX.
static func add_rot(b: BWBattle, v: BWUnit, n: int, by: String = "", why: String = "") -> int:
	if v == null or not v.alive() or BWObelisk.is_objective(v):
		return rot(v)
	var before := rot(v)
	var now := clampi(before + n, 0, ROT_MAX)
	if now == before:
		return now
	v.fx["rot"] = now
	b._emit({ "type": "rot", "unit": v.id, "stacks": now, "delta": now - before, "by": by, "why": why })
	if now >= ROT_MAX:
		BWKsDark.on_rot_max(b, v)                 # D296 Doom
	return now


## Damage taken multiplier from Rot.
static func taken_mult(u: BWUnit) -> float:
	return 1.0 + ROT_PCT / 100.0 * rot(u)


## The forecast line (a named dmg stage, so the hover shows it).
static func rot_mods(dfn: BWUnit, mods: Array) -> void:
	var r := rot(dfn)
	if r > 0:
		mods.append({ "stage": "dmg", "value": taken_mult(dfn),
			"label": "Rot %d: +%d%% taken" % [r, ROT_PCT * r], "tag": "Rot" })


## The dark under `h` was laid by a foe of `u`: the foe (else null).
static func dark_owner(b: BWBattle, h: Vector2i, u: BWUnit) -> BWUnit:
	if b.tiles.intensity(h, "dark") <= 0:
		return null
	var src := b._unit(str(b.tiles.at(h).get("source", "")))
	if src == null or src.team == u.team or BWObelisk.is_objective(src):
		return null
	return src


## `u` ends its turn: on a foe's dark, +1 Rot.
static func turn_end(b: BWBattle, u: BWUnit) -> void:
	if b.over or not u.alive() or BWObelisk.is_objective(u):
		return
	BWKsDark.turn_end(b, u)                       # D296 Doom: the burst at the end of its next turn
	if b.over or not u.alive():
		return
	var o := dark_owner(b, u.pos, u)
	if o != null:
		add_rot(b, u, 1, o.id, "dark")


## A light heal landed on `u`: it cleans 1 Rot.
static func on_heal(b: BWBattle, u: BWUnit, cause: String) -> void:
	if cause == "light" and rot(u) > 0:
		add_rot(b, u, -1, "", "light")


## D296 Contagion: a foe with Rot was knocked out (BWKsDark).
static func on_ko(b: BWBattle, victim: BWUnit, _by: BWUnit) -> void:
	BWKsDark.on_ko(b, victim, rot(victim))


## D296 Event Horizon: the tick's dark 3 pull, after the vortex fields
## (a field move under the wind caps; BWKsDark).
static func tick(b: BWBattle) -> void:
	BWKsDark.tick(b)


# ---------------------------------------------------------------- gravity

## Dark 3 hexes laid by a foe of `u`: hex -> true. Lane C (Event Horizon)
## widens the reach, not this set.
static func gravity_hexes(b: BWBattle, u: BWUnit) -> Dictionary:
	var out := {}
	for h in b.tiles.entries:
		if b.tiles.intensity(h, "dark") >= GRAVITY_LEVEL and dark_owner(b, h, u) != null:
			out[h] = true
	return out


static func gravity_reach(b: BWBattle, v: BWUnit) -> int:
	return BWKsDark.gravity_reach(b, v, GRAVITY_REACH)     # D296 Event Horizon: 2


## A displacement of `v` heading `dir` for `n` hexes, under gravity: +1
## toward a foe's dark 3 within reach, -1 away from it (0 = it holds).
static func gravity_step(b: BWBattle, v: BWUnit, dir: int, n: int) -> int:
	if n <= 0 or dir < 0 or v == null:
		return n
	var g := gravity_hexes(b, v)
	if g.is_empty():
		return n
	var reach := gravity_reach(b, v)
	var d0 := _nearest(v.pos, g)
	if d0 > reach:
		return n
	var nxt: Vector2i = BWHex.neighbors(v.pos)[dir]
	var d1 := _nearest(nxt, g)
	if d1 < d0:
		return n + 1
	if d1 > d0:
		return maxi(0, n - 1)
	return n


static func _nearest(h: Vector2i, g: Dictionary) -> int:
	var best := 1 << 20
	for x in g:
		best = mini(best, BWHex.distance(h, x))
	return best


## BWBattle._move_rules: the walk search learns the foe's dark 3 hexes.
static func move_rules(b: BWBattle, u: BWUnit, r: Dictionary) -> void:
	var g := gravity_hexes(b, u)
	if not g.is_empty():
		r["gravity"] = g


## BWBattle._reach_fx: +1 for a step out of gravity.
static func step_extra(rules: Dictionary, h: Vector2i, n: Vector2i) -> int:
	if not rules.has("gravity"):
		return 0
	var g: Dictionary = rules.gravity
	return 1 if g.has(h) and not g.has(n) else 0


## The tile card's lines for `h`.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	if b.tiles.intensity(h, "dark") >= GRAVITY_LEVEL:
		var src := b._unit(str(b.tiles.at(h).get("source", "")))
		if src != null:
			out.append("Gravity (%s's dark 3): %s's foes pay +1 move to step out; pushes toward it go 1 further, away 1 shorter" % [src.name, src.name])
	var u := b._centre_at(h)
	if u != null and rot(u) > 0:
		out.append("%s: Rot %d, takes +%d%% damage (a light heal cleans 1)" % [u.name, rot(u), ROT_PCT * rot(u)])
	elif u != null and dark_owner(b, h, u) != null:
		out.append("%s gains 1 Rot if it ends its turn here" % u.name)
	return out
