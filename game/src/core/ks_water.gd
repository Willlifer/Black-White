class_name BWKsWater
extends RefCounted
## D295 water's keystones, after Keystones v3 (D443): Tidal Release and
## Riptide were REMOVED; Wellspring is an item enchantment ("Wellspring
## {item}", the keystone effect key; provisional, D443). Pure rules;
## BWKeystoneFx calls them.
##
## Wellspring     at the tick, you and your allies standing in YOUR water
##                heal WELL_PCT per level (4/8/12%). Not on top of light: a
##                hex whose light heal at the turn start is as big or bigger
##                gives nothing here, a smaller one leaves the difference (the
##                higher counts). Several holders: the best one counts.

const WELLSPRING := "wellspring"
const WELL_PCT := 4.0


static func has(u: BWUnit, id: String) -> bool:
	return u != null and BWKeystones.has(u, id)


# ---------------------------------------------------------------- Wellspring

## The heal `a` gets at the tick from Wellspring holders on its side (% max
## HP, after the light rule), and the holder.
static func well_pct(b: BWBattle, a: BWUnit) -> Array:
	var lvl := b.tiles.intensity(a.pos, "water")
	if lvl <= 0 or b.tiles.is_glazed(a.pos):
		return [0.0, null]
	var src := b._unit(str(b.tiles.at(a.pos).get("source", "")))
	if src == null or src.team != a.team or not has(src, WELLSPRING) or not src.alive():
		return [0.0, null]
	var pct := WELL_PCT * lvl
	var st := b.tiles.standing(a.pos)
	var lsrc := b._unit(str(st.light_src))
	var light := float(st.heal) if lsrc == null or lsrc.team == a.team else 0.0   # D496
	return [maxf(0.0, pct - light), src]


static func tick(b: BWBattle) -> void:
	for a in b.units:
		if b.over:
			return
		if not a.alive() or BWObelisk.is_objective(a) or a.hp >= a.max_hp():
			continue
		var w := well_pct(b, a)
		if float(w[0]) > 0.0:
			b._emit({ "type": "wellspring", "unit": a.id, "hex": a.pos, "by": (w[1] as BWUnit).id, "pct": w[0] })
			b._heal(a, float(w[0]), "wellspring")


## The tile card's lines.
static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var u := b._centre_at(h)
	if u != null:
		var w := well_pct(b, u)
		if float(w[0]) > 0.0:
			out.append("Wellspring (%s): %s heals %d%% at the tick" % [(w[1] as BWUnit).name, u.name, int(w[0])])
	return out
