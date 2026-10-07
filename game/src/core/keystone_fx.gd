class_name BWKeystoneFx
extends RefCounted
## D293-D297 the battle's hooks for the wind, ice, water and dark keystones
## (Lane C3; the rules live in ks_wind.gd, ks_ice.gd, ks_water.gd and
## ks_dark.gd, who holds what in BWKeystones). BWBattle calls these at the
## lines marked "D293"-"D297"; each is a no-op when nobody holds the
## keystone, so a battle without keystones plays exactly as before.


## BWBattle._begin_turn, after the ground: Riptide (the holder's own turn
## start), then Frozen. True = the turn is skipped (Frozen).
static func turn_start(b: BWBattle, u: BWUnit) -> bool:
	BWKsWater.riptide(b, u)
	if b.over or not u.alive():
		return false
	return BWKsIce.turn_start(b, u)


## The tick (BWWind.tick, after the vortex fields and Event Horizon):
## Wellspring heals, then served Frozen units thaw.
static func tick(b: BWBattle) -> void:
	BWKsWater.tick(b)
	if not b.over:
		BWKsIce.tick(b)


## BWBattle._mods: Frozen (x2, Shatter).
static func blow_mods(b: BWBattle, att: BWUnit, dfn: BWUnit, mods: Array) -> void:
	BWKsIce.blow_mods(b, att, dfn, mods)


## BWBattle._after_blow: a landed hit thaws Frozen.
static func after_blow(b: BWBattle, _att: BWUnit, v: BWUnit, res: Dictionary) -> void:
	BWKsIce.after_blow(b, v, res)


## BWBattle._immune("displace"): Frozen holds.
static func holds(u: BWUnit) -> bool:
	return BWKsIce.frozen(u)


## BWBattle._heal: Event Horizon (a foe on the holder's dark 3).
static func heal_blocked(b: BWBattle, u: BWUnit) -> bool:
	return BWKsDark.heal_blocked(b, u)


## BWBattle.paint, before BWTiles.apply: Jetstream's opts.
static func paint_opts(by: BWUnit, o: Dictionary) -> void:
	BWKsWind.paint_opts(by, o)


## BWBattle.paint, after the tiles changed: Glacier pillars.
static func after_paint(b: BWBattle, by: BWUnit, r: Dictionary) -> void:
	BWKsIce.after_paint(b, by, r)


## BWBattle.use_skill, after the ground: a Glacier holder's shape shatters
## its own pillars.
static func after_skill(b: BWBattle, u: BWUnit, p: Dictionary) -> void:
	BWKsIce.after_skill(b, u, p)


## BWAI._best_hex: cheap positioning for Riptide and Event Horizon.
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	return BWKsWater.ai_hex(b, u, h) + BWKsDark.ai_hex(b, u, h)


## The tile card's keystone lines (BWBattle.ground_report "keystones").
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	return BWKsIce.card_lines(b, h) + BWKsWater.card_lines(b, h) + BWKsDark.card_lines(b, h)
