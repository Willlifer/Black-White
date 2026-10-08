class_name BWKeystoneFx
extends RefCounted
## D293-D297 the battle's hooks for the wind, ice, water and dark keystones
## of C3 (rules in ks_wind.gd, ks_ice.gd, ks_water.gd and ks_dark.gd). Since
## Keystones v3 (D443) these serve the ones that became item enchantments
## (Wellspring, Event Horizon, Doom, Contagion, Eye of the Vortex,
## Sure-Footed) and the dormant Frozen status; Riptide, Jetstream, Flash
## Freeze, Glacier Wall, Tidal Release and Wind Wall were removed. The v3
## keystones' hooks are BWKs3. Each is a no-op when nobody holds the
## keystone, so a battle without them plays exactly as before.


## BWBattle._begin_turn, after the ground: Frozen. True = the turn is skipped.
static func turn_start(b: BWBattle, u: BWUnit) -> bool:
	if b.over or not u.alive():
		return false
	return BWKsIce.turn_start(b, u)


## The tick (BWWind.tick, after Event Horizon): Wellspring heals, then served
## Frozen units thaw.
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


## BWBattle.paint, before BWTiles.apply (D443: Jetstream's options are gone).
static func paint_opts(_by: BWUnit, _o: Dictionary) -> void:
	pass


## BWBattle.paint, after the tiles changed (D443: Glacier Wall is gone).
static func after_paint(_b: BWBattle, _by: BWUnit, _r: Dictionary) -> void:
	pass


## BWBattle.use_skill, after the ground (D443: Glacier Wall is gone).
static func after_skill(_b: BWBattle, _u: BWUnit, _p: Dictionary) -> void:
	pass


## BWAI._best_hex: Event Horizon wariness, plus the v3 keystones' (BWKs3).
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	return BWKsDark.ai_hex(b, u, h) + BWKs3.ai_hex(b, u, h)


## The tile card's keystone lines (BWBattle.ground_report "keystones").
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	return BWKsIce.card_lines(b, h) + BWKsWater.card_lines(b, h) + BWKsDark.card_lines(b, h) + BWKs3.card_lines(b, h)
