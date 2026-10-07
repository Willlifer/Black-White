class_name BWRosterGen
extends RefCounted
## D150–D152: the roster's randomized facets. data/roster.csv holds the
## identities only (the 20 core seats and, D379, the rolling pool) (name, gender, seat, element lock, friendliness, hair,
## voice); every new game rolls the rest from a seed:
##
##   BWRosterGen.roll(identities, seed) -> Array of full roster rows
##
## Pure: the same identities and seed give the same rows, nothing global is
## touched. A rolled row has every column BWUnit.from_roster reads:
## weapon_class, weapon_model, element, the seven stats, top, bottom,
## clothing_shade (plus the identity columns, unchanged).
##
##   weapon   a class from a deck (each of the 7 classes twice, 6 more at
##            random), then a model of that class (the class's models in a
##            shuffled cycle, so a class held 3 times shows 3 models)
##   element  the lock if the identity has one (Aureli light, Rem ice);
##            the rest from a deck (each element twice, 4 at random)
##   stats    the class's PROFILES row, then one point moved between two
##            stats and, a third of the time, one stat ±1 (each stat stays
##            within ±1 of the profile, the total within ±1, all 1–6)
##   clothes  a top and a bottom weighted by gender (POOLS: f / m / a for
##            ambiguous), then a coverage pass so all 7 tops and all 7
##            bottoms appear among the 20; shade from a 7 dark / 7 mid /
##            6 light deck
## The seed itself is shown nowhere; the run stores it (BWRun.roster_seed).

## The seed the self-test, tools and sims roll with (BWData's default roster).
const DEFAULT_SEED := 1
## The 7 classes a roster character can start with (fists never, D76).
const CLASSES := ["sword", "axe", "lance", "daggers", "bow", "pistols", "staff"]
const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "dark", "light"]
const STATS := ["con", "str", "dex", "wil", "def", "res", "spd"]
const STAT_MIN := 1
const STAT_MAX := 6

## D151: each class's stat profile, con/str/dex/wil/def/res/spd (design/ROSTER.md).
const PROFILES := {
	"sword":   [4, 5, 4, 2, 4, 3, 4],   # 26  balanced duelist, STR lean
	"axe":     [6, 6, 2, 1, 5, 3, 2],   # 25  STR/CON/DEF, slow
	"lance":   [5, 5, 3, 2, 5, 3, 3],   # 26  CON/STR/DEF
	"daggers": [3, 2, 6, 2, 2, 3, 6],   # 24  DEX/SPD, fragile
	"bow":     [3, 3, 6, 2, 3, 3, 5],   # 25  DEX/SPD
	"pistols": [3, 4, 6, 1, 3, 3, 4],   # 24  DEX/STR
	"staff":   [3, 1, 3, 6, 2, 6, 4],   # 25  WIL/RES
}
## Chance of the ±1 drift on top of the point moved (the total moves by 1).
const DRIFT_CHANCE := 0.34

## D152: gender-leaning clothing weights. f / m lean their usual way with a
## low weight on the other side's pieces (the occasional outlier); `a`
## (ambiguous) leans to the neutral pieces.
const POOLS := {
	"f": {
		"top": { "crop_top": 3.0, "crop_hoodie": 3.0, "tank_top": 2.0, "sweater_scarf": 2.0, "sweater": 2.0, "hoodie": 1.0, "tshirt": 1.0 },
		"bottom": { "tight_pants": 3.0, "tight_shorts": 3.0, "short_shorts": 3.0, "ripped_tight_pants": 2.0, "sweatpants": 1.5, "shorts": 0.6, "baggy_sweatpants": 0.6 },
	},
	"m": {
		"top": { "tshirt": 3.0, "hoodie": 3.0, "tank_top": 3.0, "sweater": 2.0, "sweater_scarf": 1.0, "crop_top": 0.25, "crop_hoodie": 0.25 },
		"bottom": { "baggy_sweatpants": 3.0, "shorts": 3.0, "sweatpants": 3.0, "ripped_tight_pants": 1.5, "tight_pants": 1.0, "short_shorts": 0.25, "tight_shorts": 0.25 },
	},
	"a": {
		"top": { "hoodie": 3.0, "sweater": 3.0, "tshirt": 2.0, "sweater_scarf": 2.0, "tank_top": 1.0, "crop_hoodie": 1.0, "crop_top": 0.4 },
		"bottom": { "sweatpants": 3.0, "tight_pants": 2.0, "baggy_sweatpants": 2.0, "ripped_tight_pants": 2.0, "shorts": 1.0, "short_shorts": 0.4, "tight_shorts": 0.4 },
	},
}
const TOPS := ["tank_top", "crop_top", "hoodie", "crop_hoodie", "tshirt", "sweater", "sweater_scarf"]
const BOTTOMS := ["baggy_sweatpants", "sweatpants", "tight_pants", "ripped_tight_pants", "tight_shorts", "shorts", "short_shorts"]
const SHADE_DECK := { "dark": 7, "mid": 7, "light": 6 }

## A new game's seed when none is forced: -1 = random. `--seed N` and the
## probes set it (boot.gd), so the roster screen opens on a known roll.
static var fixed_seed := -1


## D379: the rolling pool. With `pool` given (BWData.pool_identities(): the
## game's start and every Randomize), POOL_MIN..POOL_MAX of the back row's
## seats (11-20) are handed to pool identities first, seeded on their own
## stream so the kits per seat roll as before. The front row is always the
## core ten; a locked core character (Rem) keeps the seat. The incoming
## identity takes the seat's number.
const BACK_ROW_FROM := 11
const POOL_MIN := 3
const POOL_MAX := 5


## The 20 rows for `seed`. `identities`: roster.csv's core rows
## (BWData.identities()); `pool`: the pool rows to rotate in (D379; empty =
## the core twenty, as tests, tools and sims roll).
static func roll(identities: Array, p_seed: int, pool: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bw-roster:%d" % p_seed)
	var ids: Array = seated(identities, p_seed, pool)
	var n := ids.size()
	var classes := _deck(CLASSES, 2, n, rng)
	var free := ids.filter(func(r): return str(r.get("element_lock", "")) == "").size()
	var elements := _deck(ELEMENTS, 2, free, rng)
	var shades: Array = []
	for s in SHADE_DECK:
		for k in SHADE_DECK[s]:
			shades.append(s)
	while shades.size() < n:
		shades.append(SHADE_DECK.keys()[rng.randi() % SHADE_DECK.size()])
	_shuffle(shades, rng)
	var model_cycle := {}
	var out: Array = []
	for i in n:
		var row: Dictionary = Dictionary(ids[i]).duplicate()
		var wc: String = classes[i]
		row["weapon_class"] = wc
		row["weapon_model"] = _next_model(wc, model_cycle, rng)
		var lock := str(row.get("element_lock", ""))
		row["element"] = lock if lock != "" else str(elements.pop_back())
		var st := stats_for(wc, rng)
		for k in STATS.size():
			row[STATS[k]] = st[k]
		var g := _gender(row)
		row["top"] = _weighted(POOLS[g].top, rng)
		row["bottom"] = _weighted(POOLS[g].bottom, rng)
		row["clothing_shade"] = shades[i % shades.size()]
		out.append(row)
	_cover(out, "top", TOPS, rng)
	_cover(out, "bottom", BOTTOMS, rng)
	return out


## D379: the twenty identities for `seed`, in seat order: the core rows with
## POOL_MIN..POOL_MAX unlocked back-row seats given to pool rows (none when
## `pool` is empty). Pure.
static func seated(identities: Array, p_seed: int, pool: Array = []) -> Array:
	var ids: Array = identities.duplicate()
	ids.sort_custom(func(a, b): return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	if pool.is_empty():
		return ids
	var prng := RandomNumberGenerator.new()
	prng.seed = hash("bw-pool:%d" % p_seed)
	var open: Array = []
	for i in ids.size():
		if int(ids[i].get("seat", 0)) >= BACK_ROW_FROM and str(ids[i].get("element_lock", "")) == "":
			open.append(i)
	var incoming: Array = pool.duplicate()
	incoming.sort_custom(func(a, b): return str(a.id) < str(b.id))
	_shuffle(open, prng)
	_shuffle(incoming, prng)
	var k := mini(POOL_MIN + prng.randi() % (POOL_MAX - POOL_MIN + 1), mini(open.size(), incoming.size()))
	for j in k:
		var i: int = open[j]
		var row: Dictionary = Dictionary(incoming[j]).duplicate()
		row["seat"] = int(ids[i].seat)
		ids[i] = row
	return ids


## D379: rolled rows for every identity of `all` not seated in `rows` (the
## swapped-out core and the unseated pool): the enemy side's reserve
## (BWRun.reserve_rows). Each rolls on its own seeded stream: a class at
## random, the lock or a random element, the class profile, gendered clothes.
static func reserve(all: Array, rows: Array, p_seed: int) -> Array:
	var seated_ids := {}
	for r in rows:
		seated_ids[str(r.id)] = true
	var out: Array = []
	for idr in all:
		if seated_ids.has(str(idr.id)):
			continue
		out.append(roll_one(idr, hash("bw-reserve:%d:%s" % [p_seed, str(idr.id)])))
	return out


## D379: one identity's kit on its own stream (the reserve, and a duplicate
## enemy's different roll when the side runs short).
static func roll_one(identity: Dictionary, stream: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream
	var row: Dictionary = identity.duplicate()
	var wc: String = CLASSES[rng.randi() % CLASSES.size()]
	row["weapon_class"] = wc
	row["weapon_model"] = _next_model(wc, {}, rng)
	var lock := str(row.get("element_lock", ""))
	row["element"] = lock if lock != "" else ELEMENTS[rng.randi() % ELEMENTS.size()]
	var st := stats_for(wc, rng)
	for k in STATS.size():
		row[STATS[k]] = st[k]
	var g := _gender(row)
	row["top"] = _weighted(POOLS[g].top, rng)
	row["bottom"] = _weighted(POOLS[g].bottom, rng)
	row["clothing_shade"] = SHADE_DECK.keys()[rng.randi() % SHADE_DECK.size()]
	return row


## The class's profile with the seeded variance (see the header).
static func stats_for(wc: String, rng: RandomNumberGenerator) -> Array:
	var st: Array = (PROFILES.get(wc, [4, 4, 4, 4, 4, 4, 4]) as Array).duplicate()
	var touched := {}
	# one point moved: from a stat above the floor to a different one below the cap
	for tries in 12:
		var a := rng.randi() % STATS.size()
		var b := rng.randi() % STATS.size()
		if a != b and st[a] > STAT_MIN and st[b] < STAT_MAX:
			st[a] -= 1
			st[b] += 1
			touched[a] = true
			touched[b] = true
			break
	if rng.randf() < DRIFT_CHANCE:
		for tries in 12:
			var c := rng.randi() % STATS.size()
			var d := 1 if rng.randf() < 0.5 else -1
			if not touched.has(c) and st[c] + d >= STAT_MIN and st[c] + d <= STAT_MAX:
				st[c] += d
				break
	return st


## A fresh seed after `prev` (the Randomize button): random, unless a seed
## was forced, then a fixed step so a probe's re-roll is reproducible too.
static func next_seed(prev: int) -> int:
	if fixed_seed < 0:
		return randi() & 0x7fffffff
	return absi(hash("bw-next:%d" % prev)) & 0x7fffffff


## The seed a new roster screen opens with.
static func first_seed() -> int:
	return fixed_seed if fixed_seed >= 0 else (randi() & 0x7fffffff)


static func row_by_id(rows: Array, id: String) -> Dictionary:
	for r in rows:
		if str(r.id) == id:
			return r
	return {}


# ---------------------------------------------------------------- internals

static func _gender(row: Dictionary) -> String:
	var g := str(row.get("gender", "a"))
	return g if POOLS.has(g) else "a"


## Each of `items` `each` times, topped up at random to `n`, shuffled.
static func _deck(items: Array, each: int, n: int, rng: RandomNumberGenerator) -> Array:
	var d: Array = []
	for k in each:
		d.append_array(items)
	_shuffle(d, rng)
	d.resize(mini(d.size(), n))
	while d.size() < n:
		d.append(items[rng.randi() % items.size()])
	_shuffle(d, rng)
	return d


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


## The class's models in a shuffled cycle (equipment.csv main_hand rows).
static func _next_model(wc: String, cycle: Dictionary, rng: RandomNumberGenerator) -> String:
	if not cycle.has(wc) or (cycle[wc] as Array).is_empty():
		var models: Array = []
		for r in BWData.table("equipment"):
			if str(r.slot) == "main_hand" and str(r.weight) == wc:
				models.append(str(r.id))
		if models.is_empty():
			return wc
		_shuffle(models, rng)
		cycle[wc] = models
	return str((cycle[wc] as Array).pop_back())


static func _weighted(w: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys: Array = w.keys()
	keys.sort()                          # fixed order: stable per seed
	var total := 0.0
	for k in keys:
		total += float(w[k])
	var x := rng.randf() * total
	for k in keys:
		x -= float(w[k])
		if x <= 0.0:
			return str(k)
	return str(keys.back())


## Every item of `all` worn at least once in `slot`: a missing one goes to the
## character whose pool favours it most among those wearing a duplicate.
static func _cover(rows: Array, slot: String, all: Array, rng: RandomNumberGenerator) -> void:
	for item in all:
		var counts := {}
		for r in rows:
			counts[r[slot]] = int(counts.get(r[slot], 0)) + 1
		if counts.has(item):
			continue
		var best := -1
		var best_w := -1.0
		for i in rows.size():
			if int(counts[rows[i][slot]]) < 2:
				continue
			var wt := float(POOLS[_gender(rows[i])][slot].get(item, 0.0)) + rng.randf() * 0.5
			if wt > best_w:
				best_w = wt
				best = i
		if best >= 0:
			rows[best][slot] = item
