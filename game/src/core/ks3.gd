class_name BWKs3
extends RefCounted
## Keystones v3 (D443-D465, design/ELEMENTS.md "Keystones v3"): the battle's
## hooks. BWBattle (and BWTiles / BWOverheat / BWPools through the paint
## options) call these at the lines marked "D44x" / "D45x"; each is a no-op
## when nobody holds the keystone, so a battle without them plays as before.
## The rules live per element:
##   BWKs3Fire     Lava Walker, Island Maker
##   BWKs3Dark     Abyssal (Pitch Black), Hopekiller
##   BWKs3Light    Judicator, Sunburst (Solar Flare)
##   BWKs3Water    Leviathan (Drowned; Leviathos is a TODO), Being of Rain
##   BWKs3Thunder  Superconductor (+ Self-detonate, BWThunderKeys), Overflow
##   BWKs3Wind     El Niño, La Niña
##   BWKs3Ice      Shatterer, Sculptor
## Duo perks (D455-D463) are BWDuo; their rules ride the same hooks.

## Damage causes that are REACTIONS (an element meeting another, or a keystone
## burst): Superconductor's own-hex immunity and Island Maker's 75% read them.
const REACTIONS := ["detonation", "erupt", "shock", "overheat", "overfreeze", "pitch_black", "solar_flare", "shatter"]
## Fire on the ground: Island Maker counts it ("your own fire included"), Lava
## Walker's aura stops it.
const FIRE_GROUND := ["fire", "fire_cross"]


## Keystone check (held, worn as an enchantment, or the dev flag).
static func ks(u: BWUnit, id: String) -> bool:
	return u != null and BWKeystones.has(u, id)


## Does anyone in the battle hold `id` (a cheap guard for the hooks)?
static func any_holder(b: BWBattle, id: String) -> bool:
	for u in b.units:
		if u.alive() and not u.keystones.is_empty() and id in u.keystones:
			return true
	return false


# ---------------------------------------------------------------- paint options

## BWBattle.paint (via BWOverheat.paint_opts): `by`'s options for BWTiles.apply.
static func paint_opts(by: BWUnit, element: String, o: Dictionary) -> void:
	if by == null:
		return
	var sc := ks(by, "superconductor")
	match element:
		"fire":
			if ks(by, "lava_walker"):
				o["fire_max"] = BWTiles.LAVA_MAX            # D447: your fire climbs to 5
				o["lava"] = true
			var r := 2 if sc else 1                         # D452: reactions radius 2
			if ks(by, "island_maker"):
				r += 1                                      # D448: overheat / eruption +1
			if r > 1:
				o["overheat_radius"] = r
		"ice":
			if ks(by, "sculptor"):
				o["sculpt"] = true                          # D459: ice on ice raises a pillar
				o["pillar_cap"] = int(BWKeystones.param("sculptor", "pillar_max", 6))
			if BWDuo.has(by, "flash_flood"):
				o["flash_flood"] = true                     # D458: the whole pool glazes
			if sc:
				o["pool_reach"] = maxi(int(o.get("pool_reach", 1)), 2)
		"thunder":
			if BWDuo.has(by, "storm_drain"):
				o["pool_reach"] = BWPools.POOL_MAX          # D457: the whole connected pool
			elif sc:
				o["pool_reach"] = maxi(int(o.get("pool_reach", 1)), 2)
		"light", "dark":
			if BWDuo.has(by, "eclipse"):
				o["eclipse"] = true                         # D461 Eclipse
	if sc:
		o["overfreeze_radius"] = 2                          # D452: an Overfreeze burst reaches 2
	# a gale fires whatever element lands on it: the painter's gale riders ride every paint
	if ks(by, "el_nino"):
		o["gale_radius"] = int(o.get("gale_radius", 1)) + 1   # D454 El Niño: gales spread 1 further
	if BWDuo.has(by, "wildfire_gale"):
		o["fire_gale_plus"] = 1                         # D456 Wildfire Gale: fire it carries, 1 further


# ---------------------------------------------------------------- around BWTiles.apply

## Before BWTiles.apply: what the hooks after it need from the old board.
static func before_paint(b: BWBattle) -> Dictionary:
	return { "pillars": b.tiles.pillars.duplicate(true) }


## Right after BWTiles.apply, before any damage: the fizzles, Superconductor's
## own-hex immunity for this action.
static func after_apply(b: BWBattle, by: BWUnit, element: String, r: Dictionary) -> void:
	var fz: Array = r.get("fizzled", [])
	if not fz.is_empty():
		b._emit({ "type": "fizzle", "hexes": fz.duplicate(), "element": element, "unit": by.id if by else "" })
	BWKs3Thunder.mark_own_hex(b, by, r)


## The radius of detonation `d` (base `radius`): Superconductor 2 (the blast's
## credited unit or the painter), Powder Keg +1 on your fire.
static func det_radius(b: BWBattle, by: BWUnit, d: Dictionary, radius: int) -> int:
	var src := b._unit(str(d.get("source", "")))
	if ks(by, "superconductor") or ks(src, "superconductor"):
		radius = maxi(radius, int(BWKeystones.param("superconductor", "radius", 2)))
	var mix: Dictionary = d.get("mix", {})
	if int(mix.get("fire", 0)) > 0 and (BWDuo.has(by, "powder_keg") or BWDuo.has(src, "powder_keg")):
		radius += 1                                        # D457b Powder Keg: a fuse on your fire blows wider
	return radius


## A detonation's % multiplier: a Sculptor's pillar shatters for double.
static func det_mult(pre: Dictionary, d: Dictionary) -> float:
	var pl: Dictionary = pre.get("pillars", {})
	var rec: Dictionary = pl.get(d.hex, {})
	if bool(rec.get("sculpt", false)):
		return float(BWKeystones.param("sculptor", "shatter_mult", 2))
	return 1.0


## After all of a paint's damage: Overflow heals its painter.
static func after_paint(b: BWBattle, by: BWUnit, _element: String, r: Dictionary) -> void:
	if by == null or b.over or not by.alive():
		return
	var n: int = (r.get("detonations", []) as Array).size() + (r.get("overheat", []) as Array).size() \
		+ (r.get("overfreeze", []) as Array).size()
	var pools: Dictionary = r.get("pools", {})
	if not (pools.get("shock", []) as Array).is_empty():
		n += 1
	if n > 0:
		BWKs3Thunder.overflow(b, by, n)


# ---------------------------------------------------------------- hurts and heals

## BWOverheat.filter_hurt, first: Lava Walker's aura (no fire ground damage),
## Superconductor's own-hex immunity, Island Maker's 75% less from your own
## reactions.
static func filter_hurt(b: BWBattle, u: BWUnit, amount: int, cause: String, source: String) -> int:
	if amount <= 0:
		return amount
	if cause in FIRE_GROUND and BWKs3Fire.fire_immune(b, u):
		b._emit({ "type": "immune", "unit": u.id, "class": "fire (Lava Walker)" })
		return 0
	if cause in REACTIONS and BWKs3Thunder.shielded(b, u):
		b._emit({ "type": "immune", "unit": u.id, "class": "its own reaction (Superconductor)" })
		return 0
	if source == u.id and (cause in REACTIONS or cause in FIRE_GROUND) and ks(u, "island_maker"):
		return maxi(0, roundi(amount * BWKeystones.param("island_maker", "own_taken_pct", 25) / 100.0))
	return amount


## BWBattle._heal: Hopekiller turns a heal into damage. True = handled (the
## heal must not land).
static func heal_hook(b: BWBattle, u: BWUnit, pct: float, cause: String) -> bool:
	return BWKs3Dark.heal_to_harm(b, u, pct, cause)


## BWBattle._begin_turn, right after tiles.standing: Judicator and Solar Wind
## re-cut what the ground does to `u` this turn start (mutates `st`).
static func standing(b: BWBattle, u: BWUnit, st: Dictionary) -> void:
	BWKs3Light.standing(b, u, st)


# ---------------------------------------------------------------- turns

## BWBattle._begin_turn (after the ground): La Niña, the Leviathan's form.
static func turn_start(b: BWBattle, u: BWUnit) -> void:
	if b.over or not u.alive():
		return
	BWKs3Wind.la_nina(b, u)
	if b.over or not u.alive():
		return
	BWKs3Water.turn_start(b, u)


## BWBattle.end_turn: Pitch Black / Solar Flare's overcharge reverts.
static func turn_end(b: BWBattle, u: BWUnit) -> void:
	BWKs3Dark.revert_overcharge(b, u)
	BWKs3Water.turn_end(b, u)


## BWBattle._ko: a foe KO'd on Hopekiller's dark leaves dark 3.
static func on_ko(b: BWBattle, victim: BWUnit) -> void:
	BWKs3Dark.on_ko(b, victim)


# ---------------------------------------------------------------- moving

## BWBattle._move_rules: Being of Rain's free water.
static func move_rules(_b: BWBattle, u: BWUnit, r: Dictionary) -> void:
	if ks(u, "being_of_rain"):
		r["cost_on"] = ["water", 0]


## BWBattle.move, after the walk: Being of Rain's rain, the Leviathan's offer.
static func after_walk(b: BWBattle, u: BWUnit, path: Array) -> void:
	BWKs3Water.after_walk(b, u, path)


## BWBattle._lay_on_move: Being of Rain never paints as it walks.
static func paints_walking(u: BWUnit) -> bool:
	return not ks(u, "being_of_rain")


# ---------------------------------------------------------------- blows

## BWBattle._mods: Shatterer's bonus, Permafrost's Shatter.
static func blow_mods(b: BWBattle, att: BWUnit, dfn: BWUnit, mods: Array) -> void:
	BWKs3Ice.blow_mods(b, att, dfn, mods)


## BWBattle._after_blow: Shatterer's shatter.
static func after_blow(b: BWBattle, att: BWUnit, v: BWUnit, res: Dictionary) -> void:
	BWKs3Ice.after_blow(b, att, v, res)


## BWBattle._plan: El Niño widens a wind area.
static func plan(b: BWBattle, u: BWUnit, d: BWSkillDef, p: Dictionary) -> void:
	BWKs3Wind.widen(b, u, d, p)


# ---------------------------------------------------------------- AI

## BWAI._best_hex: where a holder likes to stand (HP-scale points).
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	return BWKs3Wind.ai_hex(b, u, h) + BWKs3Dark.ai_hex(b, u, h) + BWKs3Light.ai_hex(b, u, h) \
		+ BWKs3Fire.ai_hex(b, u, h)


## BWAI._best_skill: the keystone part of an action's worth (HP points).
static func ai_skill(b: BWBattle, u: BWUnit, pv: Dictionary) -> float:
	return BWKs3Fire.ai_skill(b, u, pv) + BWKs3Ice.ai_skill(b, u, pv)


# ---------------------------------------------------------------- readability

## The tile card's keystone lines for `h` (BWBattle.ground_report).
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	return BWKs3Fire.card_lines(b, h) + BWKs3Dark.card_lines(b, h) + BWKs3Light.card_lines(b, h) \
		+ BWKs3Water.card_lines(b, h) + BWKs3Thunder.card_lines(b, h) + BWKs3Ice.card_lines(b, h)
