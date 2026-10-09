class_name BWDuo
extends RefCounted
## D455-D463 DUO PERKS (Hades style; design/ELEMENTS.md "Keystones v3",
## "Duo perks"). A duo perk is a perks.csv row with a `duo` column (the second
## element; `element` is the first, the slot it fills) and effect_key "duo"
## (params id=<duo id>). It is OFFERED only on a perk pick of its first element,
## only to a unit holding at least one ordinary perk in each of its two
## elements (so both are among the unit's <= 3), at a modest RATE: when one is
## eligible, RATE% of those picks show it as the second card. Taking it fills
## that element's perk slot like any perk. The rules live in the hooks that
## ask has(u, id) (tiles, battle, wind, pools; each marked "D45x duo").
##
##   wildfire_gale  (fire+wind)    fire your gales carry spreads 1 ring further, full steps
##   powder_keg     (fire+thunder) a fuse set off on your fire blows +1 radius (on lava too: D494, it blows as fire 1, a step burns off)
##   storm_drain    (water+thunder) your electrified water: the whole connected pool
##   flash_flood    (water+ice)    your ice on your water glazes the whole pool at once
##   permafrost     (ice+dark)     your dark 3 counts as glazed (Unsteady, Shatter)
##   solar_wind     (light+fire)   on your light: allies heal for its fire steps too (no burn),
##                                 foes burn for its light steps too (no heal)
##   eclipse        (light+dark)   your light and dark on one hex both stay (the hex holds both)
##   blizzard       (wind+ice)     your wind pushes glaze the landing hex

const RATE := 35
const TABLE := "perks"


## Every duo row, CSV order.
static func rows() -> Array:
	return BWData.table(TABLE).filter(func(r): return str(r.get("duo", "")) != "")


## Does `u` hold duo `id` (its perk, awake; or the dev flag fx["duo:<id>"])?
static func has(u: BWUnit, id: String) -> bool:
	if u == null:
		return false
	if bool(u.fx.get("duo:" + id, false)):
		return true
	for e in BWEffects.list(u, "duo"):
		if str(e.params.get("id", "")) == id:
			return true
	return false


## Ordinary (non-duo) perks `u` holds in `el`.
static func base_perks(u: BWUnit, el: String) -> int:
	var n := 0
	for id in u.perks:
		var r := BWData.row(TABLE, str(id))
		if str(r.get("element", "")) == el and str(r.get("duo", "")) == "":
			n += 1
	return n


## The duo rows `u` could be offered on a perk pick of `el`.
static func eligible(u: BWUnit, el: String) -> Array:
	var out: Array = []
	for r in rows():
		if str(r.element) != el or str(r.id) in u.perks:
			continue
		var e2 := str(r.duo)
		if u.affinity_rank(e2) < 1 or base_perks(u, el) < 1 or base_perks(u, e2) < 1:
			continue
		out.append(r)
	return out


## The duo card a perk request shows ({} for none): deterministic from the
## request's salt (BWPicks._offer_salt), RATE% of the eligible picks.
static func offer(u: BWUnit, req: Dictionary, salt: String) -> Dictionary:
	if str(req.get("kind", "")) != "perk":
		return {}
	var el := str(req.get("element", ""))
	var cands := eligible(u, el)
	if cands.is_empty():
		return {}
	if absi(hash(salt + "|duo")) % 100 >= RATE:
		return {}
	var r: Dictionary = cands[absi(hash(salt + "|duo-pick")) % cands.size()]
	return { "id": str(r.id), "name": str(r.name), "text": str(r.effect_text), "element": el,
		"owned": false, "kind": "perk", "duo": str(r.duo) }


## "Fire + Wind" for a card's kind line.
static func pair_label(r: Dictionary) -> String:
	return "%s + %s" % [str(r.get("element", "")).capitalize(), str(r.get("duo", "")).capitalize()]


## Does tile `hex` count as glazed for `u`'s footing and Shatter? Permafrost:
## a foe of the dark's layer, on its dark 3.
static func permafrost(b: BWBattle, u: BWUnit, hex: Vector2i) -> bool:
	if b.tiles.intensity(hex, "dark") < 3:
		return false
	var src := b._unit(str(b.tiles.at(hex).get("source", "")))
	return src != null and u != null and src.team != u.team and has(src, "permafrost")
