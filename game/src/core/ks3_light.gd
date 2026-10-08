class_name BWKs3Light
extends RefCounted
## D450b-D451 light's keystones (Keystones v3, design/ELEMENTS.md).
##
## Judicator  your light heals twice as much (the turn-start heal of a unit
##            standing on it, your side), and a FOE starting its turn on your
##            light takes that same amount as light damage instead of healing
##            (cause "judicator"). Read at the turn start (standing()).
## Sunburst   Abyssal's twin for light 3 (skill def solar_flare, a free action
##            once per turn, range 3): the hex is overcharged to light 4 for
##            your turn and explodes as a SOLAR FLARE, PCT% (light) to every
##            foe within 1 (2 with Superconductor), and allies within 1 heal
##            HEAL_PCT. Rules shared with Pitch Black: BWKs3Dark.burst.
## Solar Wind (duo, D460) rides the same turn-start read: on your light, allies
## also heal for the hex's fire steps (and don't burn), foes also burn for its
## light steps (and don't heal).

const JUDICATOR := "judicator"
const SUNBURST := "sunburst"


static func ks(u: BWUnit, id: String) -> bool:
	return BWKs3.ks(u, id)


## BWBattle._begin_turn, right after tiles.standing: re-cut `st` for `u`.
## Adds st.judged (% light damage to take, Judicator) when it applies.
static func standing(b: BWBattle, u: BWUnit, st: Dictionary) -> void:
	var light := b.tiles.intensity(u.pos, "light")
	if light <= 0:
		return
	var src := b._unit(str(st.get("source", "")))
	if src == null:
		return
	var ally := src.team == u.team
	if BWDuo.has(src, "solar_wind"):
		var fire := b.tiles.intensity(u.pos, "fire")
		if ally:
			st.heal = float(st.heal) + BWTiles.LIGHT_HEAL_PCT * fire
			st.fire = 0.0
		else:
			st.fire = float(st.fire) + BWTiles.FIRE_STAND_PCT * light
			st.heal = 0.0
		st["solar_wind"] = src.id
	if ks(src, JUDICATOR):
		var amt := float(st.heal) * BWKeystones.param(JUDICATOR, "mult", 2)
		if ally:
			st.heal = amt
		elif amt > 0.0:
			st["judged"] = amt
			st.heal = 0.0
		st["judicator"] = src.id


## BWAI: a foe of a Judicator steps off its light (a little more when hurt).
static func ai_hex(b: BWBattle, u: BWUnit, h: Vector2i) -> float:
	if b.tiles.intensity(h, "light") <= 0:
		return 0.0
	var src := b._unit(str(b.tiles.at(h).get("source", "")))
	if src == null or not ks(src, JUDICATOR):
		return 0.0
	var amt := BWTiles.LIGHT_HEAL_PCT * b.tiles.intensity(h, "light") * 2.0 * u.pct_base_hp() / 100.0
	return amt * (0.5 if src.team == u.team else -1.0)


static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var lt := b.tiles.intensity(h, "light")
	if lt <= 0:
		return out
	var src := b._unit(str(b.tiles.at(h).get("source", "")))
	if src != null and ks(src, JUDICATOR):
		out.append("Judicator (%s): its side heals %d%% here at a turn start; its foes burn %d%% instead" % [
			src.name, BWTiles.LIGHT_HEAL_PCT * lt * 2, BWTiles.LIGHT_HEAL_PCT * lt * 2])
	if src != null and BWDuo.has(src, "solar_wind"):
		out.append("Solar Wind (%s): its side also heals for the fire here and doesn't burn; its foes also burn for the light" % src.name)
	return out
