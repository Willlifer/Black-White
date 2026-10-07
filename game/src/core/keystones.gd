class_name BWKeystones
## Element Overhaul keystones (design/ELEMENTS-v3.md §9, D277-D284).
##
## A keystone is a rule-breaker earned at affinity rank 3 (pick 1 of 2 from
## the element's 3) and rank 6 (the second, from the 2 left). A unit holds at
## most MAX_PER_UNIT across all elements. Rows live in data/keystones.csv:
## id, element, name, text, kind (passive | action), params (k=v;k=v).
##
## The shared contract: effect code anywhere asks `BWKeystones.has(u, id)`.
## This file owns only the bookkeeping (who holds what, the offers, the
## menu hook for action keystones); the effects live with their element.

const TABLE := "keystones"
const MAX_PER_UNIT := 2
## Affinity ranks that grant a keystone pick (D277).
const RANKS := [3, 6]

const ELEMENT_IDS := {
	"wind": ["eye_of_vortex", "wind_wall", "jetstream"],
	"ice": ["skater", "flash_freeze", "glacier_wall"],
	"light": ["prism", "overflow", "magnify"],
	"water": ["tidal_release", "riptide", "wellspring"],
	"fire": ["conflagration", "trailblazer", "phoenix_heart"],
	"dark": ["contagion", "doom", "event_horizon"],
	"thunder": ["static_blades", "blast_rider", "daisy_chain"],
}


## Does unit `u` hold keystone `id`? Null-safe (false for a null unit).
static func has(u, id: String) -> bool:
	if u == null:
		return false
	return id in of(u)


## The keystone ids `u` holds, in the order taken.
static func of(u) -> Array:
	if u == null or not ("keystones" in u):
		return []
	return u.keystones


## Give `u` keystone `id` (no-op when held, unknown, or the unit is at the cap).
## Returns true when it was added.
static func grant(u, id: String) -> bool:
	if u == null or row(id).is_empty() or has(u, id):
		return false
	if u.keystones.size() >= cap(u):
		return false                          # D302: the cap (2, or an enemy's stage cap) binds every grant
	u.keystones.append(id)
	return true


## The csv row for `id` ({} if unknown).
static func row(id: String) -> Dictionary:
	return BWData.row(TABLE, id)


static func name_of(id: String) -> String:
	return str(row(id).get("name", id))


static func element_of(id: String) -> String:
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


## The action keystones `u` holds (each gets its own menu row). The battle
## UI lists these; the effect lanes resolve them.
static func actions(u) -> Array:
	return of(u).filter(func(id): return is_action(str(id)))


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


# ---------------------------------------------------------------- enemies (D279)

## The Twins' keystones by role (D279): Noon carries Prism (its beam bends at
## a third light-standing unit, and heals the twins on it); Dusk carries Event
## Horizon (its dark 3 pulls you in and can't be healed on): Shadow Clone, the
## draft's second, was removed with dark's stealth (author, 2026-10-07).
const TWINS := { "noon": "prism", "dusk": "event_horizon" }


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


## One line naming a unit's keystones ("Keystone: Prism"), "" when none.
static func line(u) -> String:
	var ids := of(u)
	if ids.is_empty():
		return ""
	return ("Keystones: " if ids.size() > 1 else "Keystone: ") + ", ".join(ids.map(func(id): return name_of(str(id))))


## D302: trim a unit to the cap (a save or a tool that appended past it):
## keeps the first ones taken. Returns how many were dropped.
static func enforce_cap(u) -> int:
	if u == null or not ("keystones" in u):
		return 0
	var n := 0
	while u.keystones.size() > MAX_PER_UNIT:
		u.keystones.pop_back()
		n += 1
	return n
