class_name BWProgression
## XP, levels, affinity and expertise growth (brief + D14, D15, D27).

const XP_PER_LEVEL := 100
const ATTACK := { "xp": 10, "affinity": 1, "expertise": 1 }
const KNOCKOUT := { "xp": 30, "affinity": 3, "expertise": 3 }
const ARMOR_BIAS := { "heavy": "def", "ranger": "spd", "wizard": "res" }


## Award one attack or knockout. Returns a list of event dicts for the UI
## ({type: "xp"|"level"|"affinity_rank"|"expertise_rank", ...}).
static func award(u: BWUnit, ko: bool, element: String) -> Array:
	var g: Dictionary = KNOCKOUT if ko else ATTACK
	var events: Array = []
	if element != "":
		var before := u.affinity_rank(element)
		u.affinity[element] = int(u.affinity.get(element, 0)) + g.affinity
		if u.affinity_rank(element) > before:
			events.append({ "type": "affinity_rank", "element": element, "rank": u.affinity_rank(element) })
	var wc := u.weapon_class
	var before_e := u.expertise_rank(wc)
	u.expertise[wc] = int(u.expertise.get(wc, 0)) + g.expertise
	if u.expertise_rank(wc) > before_e:
		events.append({ "type": "expertise_rank", "weapon": wc, "rank": u.expertise_letter(wc) })
	events.append_array(add_xp(u, g.xp))
	return events


static func add_xp(u: BWUnit, amount: int) -> Array:
	var events: Array = [{ "type": "xp", "amount": amount }]
	u.xp += amount
	while u.xp >= XP_PER_LEVEL:
		u.xp -= XP_PER_LEVEL
		u.level += 1
		var gains := level_gains(u)
		for s in gains:
			u.stats[s] = mini(int(u.stats[s]) + gains[s], BWUnit.STAT_CAP)
		events.append({ "type": "level", "level": u.level, "gains": gains })
	return events


## Brief: every stat +1 per level, +2 where the gear says so (D27).
## Weapon: its `levels` stat. Armour: two or more pieces of one weight class.
static func level_gains(u: BWUnit) -> Dictionary:
	var gains := {}
	for s in BWUnit.STATS:
		gains[s] = 1
	var wl := str(u.weapon().get("levels", ""))
	if wl in gains:
		gains[wl] = 2
	var counts := {}
	for slot in ["head", "chest", "legs"]:
		var item: Dictionary = u.equipment.get(slot, {})
		var w := str(item.get("weight", ""))
		if ARMOR_BIAS.has(w):
			counts[w] = int(counts.get(w, 0)) + 1
	for w in counts:
		if counts[w] >= 2:
			gains[ARMOR_BIAS[w]] = 2
	return gains
