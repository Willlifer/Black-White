class_name BWKs3Fire
extends RefCounted
## D447-D448 fire's keystones (Keystones v3, design/ELEMENTS.md).
##
## Lava Walker   your fire climbs to fire 4 and 5 (BWTiles.LAVA_MAX; the paint
##               option fire_max, the entry flag `lava`). NOTHING reacts with
##               your fire: any other element, and anyone else's fire, fizzles
##               on it (BWTiles._lava_filter; thunder's fuses and the Powder
##               Keg duo included: "lava 5 reigns supreme"). Fresh fire erupts
##               only at your cap (fire 5), and an eruption's ring never cools
##               lava. Your fire burns harder: 5% a step standing, 3% a step
##               crossing (not 4% / 2%), so fire 5 burns 25% at a turn start.
##               You and allies next to you never take fire walking or
##               standing damage (any fire).
## Island Maker  your fire's Overheats (and a fire tile_erupt you own) reach 1
##               ring further: the ring is radius 2 (3 with Superconductor).
##               You take 75% less from the reactions you set off, your own
##               fire on the ground included (BWKs3.filter_hurt).

const WALKER := "lava_walker"
const ISLAND := "island_maker"


static func ks(u: BWUnit, id: String) -> bool:
	return BWKs3.ks(u, id)


## Lava Walker's aura: `u` or an ally next to it holds Lava Walker.
static func fire_immune(b: BWBattle, u: BWUnit) -> bool:
	if ks(u, WALKER):
		return true
	for o in b.units:
		if o != u and o.alive() and o.team == u.team and ks(o, WALKER) and b.gap(o, u) <= int(BWKeystones.param(WALKER, "aura", 1)):
			return true
	return false


## BWBattle._erupt: Island Maker's fire eruption reaches 1 further.
static func erupt_radius(owner: BWUnit, element: String, radius: int) -> int:
	if element == "fire" and ks(owner, ISLAND):
		return radius + 1
	return radius


## BWAI: a Lava Walker on fire stands happily (no burn); its allies like its side.
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	if b.tiles.intensity(h, "fire") <= 0:
		return 0.0
	if ks(u, WALKER):
		return 2.0                     # its own fire can't hurt it: a safe hex
	return 0.0


## BWAI._best_skill: Lava Walker values raising its fire past 3 under foes.
static func ai_skill(b: BWBattle, u: BWUnit, pv: Dictionary) -> float:
	if str(pv.get("element", "")) != "fire" or not ks(u, WALKER):
		return 0.0
	var s := 0.0
	for h in pv.get("hexes", []):
		var o := b.unit_at(h)
		if o != null and o.team != u.team and b.tiles.intensity(h, "fire") >= 3 \
				and b.tiles.intensity(h, "fire") < BWTiles.LAVA_MAX:
			s += o.pct_base_hp() * float(BWTiles.LAVA_STAND_PCT) / 100.0
	return s


## The tile card's lines.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	if b.tiles.is_lava(h):
		var src := b._unit(str(b.tiles.at(h).get("source", "")))
		out.append("Lava (%s, Lava Walker): fire %d. Nothing reacts with it: every other element fizzles here. Burns %d%% a step standing, %d%% crossing" % [
			src.name if src else "?", b.tiles.intensity(h, "fire"), BWTiles.LAVA_STAND_PCT, BWTiles.LAVA_CROSS_PCT])
	var u := b._centre_at(h)
	if u != null and u.alive():
		if ks(u, WALKER):
			out.append("%s (Lava Walker): it and allies next to it never burn on fire" % u.name)
		if ks(u, ISLAND):
			out.append("%s (Island Maker): its Overheats reach radius 2; it takes 75%% less from its own reactions" % u.name)
	return out
