class_name BWKeystones
## Keystones v3 (D443-D465, design/ELEMENTS.md "Keystones v3"; the C1 ladder
## D277-D284 it replaced is history).
##
## FOURTEEN keystones, TWO per element (data/keystones.csv: id, element, name,
## title, text, kind (passive | action), params). A unit holds at most
## MAX_PER_UNIT (2), at most ONE per element (any 2 of its <= 3 elements).
## The ladder (D444): affinity rank 3 in an element owes that element's
## keystone (1 of its 2); rank 6 in any element opens the second slot, taken
## from another element the unit has learned (2 cards drawn from those).
## Taking one gives the unit a TITLE ("Will, the Lava Walker", D445).
##
## The 21 keystones of C1-C3 left the pool (D443): eleven became item
## enchantments (LEGACY: enchantments.csv rows with effect_key "keystone",
## params id=<old id>, so their effect code still asks has(u, "<old id>")),
## ten were removed (REMOVED). Saves migrate (migrate(): D446).
##
## The shared contract: effect code anywhere asks `BWKeystones.has(u, id)`.
## It is true for a held keystone, a worn enchantment granting the old one
## (awake: its element learned), or the dev / review flag fx["ks:<id>"].

const TABLE := "keystones"
const MAX_PER_UNIT := 2
## Affinity ranks that open keystone picks (D277, re-read by D444): rank 3
## owes the element's own keystone, rank 6 the second slot (another element).
const RANKS := [3, 6]
const ANY := "*"                  # D444: the rank-6 request's element: any other learned element

const ELEMENT_IDS := {
	"fire": ["lava_walker", "island_maker"],
	"dark": ["abyssal", "hopekiller"],
	"light": ["judicator", "sunburst"],
	"water": ["leviathan", "being_of_rain"],
	"thunder": ["superconductor", "thunder_overflow"],
	"wind": ["el_nino", "la_nina"],
	"ice": ["shatterer", "sculptor"],
}

## D443: the C1-C3 keystones that became item enchantments: old id -> the
## enchantments.csv row granting it (and the name its effect code shows).
const LEGACY := {
	"conflagration": { "name": "Conflagration", "enchant": "conflagration", "element": "fire" },
	"phoenix_heart": { "name": "Phoenix Heart", "enchant": "phoenix_heart", "element": "fire" },
	"doom": { "name": "Doom", "enchant": "doom", "element": "dark" },
	"contagion": { "name": "Contagion", "enchant": "contagion", "element": "dark" },
	"event_horizon": { "name": "Event Horizon", "enchant": "event_horizon", "element": "dark" },
	"daisy_chain": { "name": "Daisy Chain", "enchant": "daisy_chain", "element": "thunder" },
	"eye_of_vortex": { "name": "Eye of the Vortex", "enchant": "eye_of_vortex", "element": "wind" },
	"skater": { "name": "Sure-Footed", "enchant": "sure_footed", "element": "ice" },
	"overflow": { "name": "Ward of Light", "enchant": "ward_of_light", "element": "light" },
	"wellspring": { "name": "Wellspring", "enchant": "wellspring", "element": "water" },
	"magnify": { "name": "Magnify", "enchant": "magnify", "element": "light" },
}
## D443: removed outright (a save's slot is refunded).
const REMOVED := ["trailblazer", "prism", "tidal_release", "riptide", "blast_rider", "static_blades",
	"wind_wall", "jetstream", "flash_freeze", "glacier_wall"]
## Keystone -> the skill def its menu row is (D447-D449: the free actions).
const SKILLS := { "abyssal": "pitch_black", "sunburst": "solar_flare", "superconductor": "self_detonate" }


## Does unit `u` hold keystone `id` (or wear an enchantment granting the old
## one, or carry the dev flag)? Null-safe.
static func has(u, id: String) -> bool:
	if u == null:
		return false
	if id in of(u):
		return true
	if "fx" in u and bool(u.fx.get("ks:" + id, false)):
		return true
	if "effects" in u:
		for e in u.effects:
			if str(e.key) == "keystone" and str(e.params.get("id", "")) == id and BWEffects.awake(u, e):
				return true
	return false


## The keystone ids `u` holds, in the order taken (enchantments not included).
static func of(u) -> Array:
	if u == null or not ("keystones" in u):
		return []
	return u.keystones


## Give `u` keystone `id`: no-op when held, unknown (or a legacy / removed id),
## at the cap, or when `u` already holds one of that element (D444).
## Returns true when it was added.
static func grant(u, id: String) -> bool:
	if u == null or row(id).is_empty() or id in of(u):
		return false
	if u.keystones.size() >= cap(u):
		return false                          # D302: the cap (2, or an enemy's stage cap) binds every grant
	var el := element_of(id)
	if u.keystones.any(func(k): return element_of(str(k)) == el):
		return false                          # D444: one per element
	u.keystones.append(id)
	return true


## The csv row for `id` ({} if unknown).
static func row(id: String) -> Dictionary:
	return BWData.row(TABLE, id)


static func name_of(id: String) -> String:
	if LEGACY.has(id):
		return str(LEGACY[id].name)
	return str(row(id).get("name", id))


static func element_of(id: String) -> String:
	if LEGACY.has(id):
		return str(LEGACY[id].element)
	return str(row(id).get("element", ""))


## The params cell parsed: { key: number|string }.
static func params(id: String) -> Dictionary:
	var out := {}
	for part in str(row(id).get("params", "")).split(";", false):
		var kv := part.split("=")
		if kv.size() == 2:
			var v := kv[1].strip_edges()
			out[kv[0].strip_edges()] = v.to_float() if v.is_valid_float() else v
	return out


static func param(id: String, key: String, fallback: float = 0.0) -> float:
	return float(params(id).get(key, fallback))


static func is_action(id: String) -> bool:
	return str(row(id).get("kind", "")) == "action"


## The action keystones `u` holds.
static func actions(u) -> Array:
	return of(u).filter(func(id): return is_action(str(id)))


## The skill defs `u`'s keystones put on its menu (D447-D449: Pitch Black,
## Solar Flare, Self-detonate), registered ones only.
static func skills(u) -> Array:
	var out: Array = []
	for id in of(u):
		var k := str(SKILLS.get(str(id), ""))
		if k != "" and BWSkillRegistry.has(k) and not k in out:
			out.append(k)
	return out


## All keystone ids of an element, in csv order.
static func of_element(el: String) -> Array:
	return (ELEMENT_IDS.get(el, []) as Array).duplicate()


static func all_ids() -> Array:
	var out: Array = []
	for r in BWData.table(TABLE):
		out.append(str(r.id))
	return out


## The most keystones `u` may hold: MAX_PER_UNIT, or an enemy's stage cap (D279).
static func cap(u) -> int:
	var c := int(u.keystone_cap) if "keystone_cap" in u else -1
	return MAX_PER_UNIT if c < 0 else mini(c, MAX_PER_UNIT)


# ---------------------------------------------------------------- titles (D445)

## The title a keystone gives ("the Lava Walker", "El Niño").
static func title_of(id: String) -> String:
	return str(row(id).get("title", ""))


## `u`'s title: its most recent keystone's (D445: the newest names you), or "".
static func title(u) -> String:
	var ids := of(u)
	for i in range(ids.size() - 1, -1, -1):
		var t := title_of(str(ids[i]))
		if t != "":
			return t
	return ""


## "Will, the Lava Walker" (or just "Will" with no keystone).
static func titled(u) -> String:
	if u == null:
		return ""
	var t := title(u)
	return str(u.name) if t == "" else "%s, %s" % [u.name, t]


## Every title `u` holds, oldest first ("the Lava Walker · La Niña"), for hovers.
static func titles_line(u) -> String:
	var out: Array = []
	for id in of(u):
		var t := title_of(str(id))
		if t != "":
			out.append(t)
	return " · ".join(out)


# ---------------------------------------------------------------- enemies (D279)

## The Twins' keystones by role (D279; D454 re-cut for v3): Noon carries
## Judicator (its light heals the twins double and burns you), Dusk carries
## Hopekiller (on its dark you can't be healed or buffed).
const TWINS := { "noon": "judicator", "dusk": "hopekiller" }


## How many of fight n's enemies carry a keystone (ELEMENTS-v3 §9):
## fights 1-3 none, 4-6 one per squad, 7 the Twins (TWINS), 8-10 every
## enemy, the Giant one. A special encounter's squad (the Horde, the
## Colossus...) carries one from fight 4 (D279: ten keystoned grunts is noise).
static func enemy_count(n: int, squad: int, encounter: bool = false) -> int:
	if n <= 3:
		return 0
	if n >= BWRun.BOSS_FIGHT:
		return 1
	if n <= 6 or encounter:
		return mini(1, squad)
	return squad


## Give fight n's enemies their keystones, replacing whatever their ranks
## auto-picked: the first units in squad order with an element, each taking
## the FIRST card of its own seeded offer (D174, as the AI picks). Sets each
## unit's keystone_cap so nothing is owed later. Returns the ids granted.
static func arm_enemies(units: Array, n: int, room: Dictionary = {}) -> Array:
	var made: Array = []
	var enc := str(room.get("encounter", "")) != "" 		or units.any(func(o): return not str(o.encounter) in ["", "twin"])
	var left := enemy_count(n, units.size(), enc)
	for u in units:
		u.keystones.clear()
		u.keystone_cap = -1                   # re-armed from scratch: the stage sets it below
		var ks := ""
		if str(u.encounter) == "twin":
			ks = str(TWINS.get(BWTwins.role(u), ""))
		elif left > 0 and str(u.element) != "":
			var opts := BWPicks.options(u, { "kind": "keystone", "element": str(u.element) })
			ks = str(opts[0].id) if not opts.is_empty() else ""
		if ks != "" and grant(u, ks):
			left -= 1
			made.append(ks)
		u.keystone_cap = u.keystones.size()
		u.refresh_effects()
	return made


## One line naming a unit's keystones ("Keystone: Lava Walker"), "" when none.
static func line(u) -> String:
	var ids := of(u)
	if ids.is_empty():
		return ""
	return ("Keystones: " if ids.size() > 1 else "Keystone: ") + ", ".join(ids.map(func(id): return name_of(str(id))))


## D302 / D444: trim a unit to the rules (a save or a tool that appended past
## them): unknown ids out, one per element, at most MAX_PER_UNIT, keeping the
## first ones taken. Returns how many were dropped.
static func enforce_cap(u) -> int:
	if u == null or not ("keystones" in u):
		return 0
	var keep: Array = []
	var els := {}
	for id in u.keystones:
		var el := element_of(str(id))
		if row(str(id)).is_empty() or els.has(el) or keep.size() >= MAX_PER_UNIT:
			continue
		els[el] = true
		keep.append(str(id))
	var n: int = u.keystones.size() - keep.size()
	u.keystones = keep
	return n


# ---------------------------------------------------------------- saves (D446)

## D446: take the C1-C3 keystones off a unit. Removed ones are refunded (the
## slot reopens: the pick flow asks again). Converted ones are refunded the
## same way AND come back as an item (the caller, BWRun, makes it: a matching
## enchanted piece in the inventory). Returns { converted: [old ids],
## refunded: [old ids] } (converted ones are in both).
static func migrate(u) -> Dictionary:
	var out := { "converted": [], "refunded": [] }
	if u == null or not ("keystones" in u):
		return out
	var keep: Array = []
	for id in u.keystones:
		var k := str(id)
		if not row(k).is_empty():
			keep.append(k)
			continue
		out.refunded.append(k)
		if LEGACY.has(k):
			out.converted.append(k)
	u.keystones = keep
	enforce_cap(u)
	return out


## The enchantment id that carries a converted keystone now ("" for none).
static func enchant_of(old_id: String) -> String:
	return str(LEGACY.get(old_id, {}).get("enchant", ""))
