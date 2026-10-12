class_name BWDuo
extends RefCounted
## D455-D463 DUO PERKS (Hades style; design/ELEMENTS.md "Keystones v3",
## "Duo perks"). A duo perk is a perks.csv row with a `duo` column (the second
## element; `element` is the first) and effect_key "duo" (params id=<duo id>).
## D560 (author: "available once you hit 4 in 2 elements"): a duo is its OWN
## pick (kind "duo"), no longer a card on a perk pick, and it fills no perk
## slot. It is owed once the unit has learned MIN_TREE picks of BOTH elements'
## trees (ordinary perks + that element's keystone), one per pair that has a
## duo row. The rules live in the hooks that ask has(u, id) (tiles, battle,
## wind, pools; each marked "D45x duo").
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
##   scalding       (fire+water)   your fire / water dousing each other blows as a fuse (5%) (D566)
##   frostfire      (fire+ice)     your fire on your glaze: the glaze holds, the fire under it (D567)
##   charged_ice    (ice+thunder)  your glaze is your fuse: any element but ice sets it off, x1.5 (D568)
##   sunbolt        (thunder+light) your side heals 5% in your blasts instead of taking them (D569)

## D560: picks a unit must hold in each element's tree (perks + keystone).
## Was 3 (D498), 1 perk each before that.
const MIN_TREE := 4
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


## D498: how much of `el`'s tree `u` has learned: ordinary perks + keystones.
static func tree(u: BWUnit, el: String) -> int:
	return base_perks(u, el) + BWPicks.keystones_owned(u, el).size()


## The pair's key, element order independent ("fire|wind").
static func pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


## Has `u` learned enough of both of a row's elements for its duo?
static func is_ready(u: BWUnit, r: Dictionary) -> bool:
	var a := str(r.element)
	var b := str(r.duo)
	return u.affinity_rank(a) >= 1 and u.affinity_rank(b) >= 1 and tree(u, a) >= MIN_TREE and tree(u, b) >= MIN_TREE


## D560: the duo picks `u` owes: [{ kind "duo", element, duo }], one per pair
## that is ready and of which it holds no duo yet (CSV order).
static func owed(u: BWUnit) -> Array:
	var out: Array = []
	var seen := {}
	for r in rows():
		var k := pair_key(str(r.element), str(r.duo))
		if seen.has(k):
			continue
		seen[k] = true
		if not is_ready(u, r) or held_in_pair(u, str(r.element), str(r.duo)) != "":
			continue
		out.append({ "kind": "duo", "element": str(r.element), "duo": str(r.duo) })
	return out


## The duo `u` holds for the pair (either order), or "".
static func held_in_pair(u: BWUnit, a: String, b: String) -> String:
	var k := pair_key(a, b)
	for r in rows():
		if str(r.id) in u.perks and pair_key(str(r.element), str(r.duo)) == k:
			return str(r.id)
	return ""


## D560: a duo request's cards: the pair's rows, owned ones flagged.
static func options(u: BWUnit, req: Dictionary) -> Array:
	var k := pair_key(str(req.get("element", "")), str(req.get("duo", "")))
	var out: Array = []
	for r in rows():
		if pair_key(str(r.element), str(r.duo)) == k:
			out.append({ "id": str(r.id), "name": str(r.name), "text": str(r.effect_text), "element": str(r.element),
				"owned": str(r.id) in u.perks, "kind": "duo", "duo": str(r.duo) })
	return out


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
