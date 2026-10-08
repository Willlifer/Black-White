class_name BWProgression
## Levels, affinity and expertise growth (brief + D14, D15, D27; D179).
##
## D179 (author: "standardize levels. All units gain a level upon clearing a
## map. Exp no longer matters."): there is no XP. Every squad unit, deployed
## or benched, gains one level after every fight, won or lost (BWRun.after_fight;
## D194 LEVEL_ON_LOSS; false would level on wins only). Attacks and knockouts still grow
## affinity and expertise.

const ATTACK := { "affinity": 1, "expertise": 1 }
const KNOCKOUT := { "affinity": 3, "expertise": 3 }
const ARMOR_BIAS := { "heavy": "def", "ranger": "spd", "wizard": "res" }
## D179: false = only a won fight levels the squad; true = every fight does.
## D194 (author): true, a lost fight levels the squad too.
const LEVEL_ON_LOSS := true


## Award one attack or knockout: affinity and expertise. Returns a list of
## event dicts for the UI ({type: "affinity_rank"|"expertise_rank", ...}).
static func award(u: BWUnit, ko: bool, element: String) -> Array:
	var g: Dictionary = KNOCKOUT if ko else ATTACK
	var events: Array = []
	if element != "":
		var before := u.affinity_rank(element)
		u.add_affinity(element, int(g.affinity))      # D417: no 4th element
		if u.affinity_rank(element) > before:
			events.append({ "type": "affinity_rank", "element": element, "rank": u.affinity_rank(element) })
	var wc := u.weapon_class
	var before_e := u.expertise_rank(wc)
	u.expertise[wc] = int(u.expertise.get(wc, 0)) + g.expertise
	if u.expertise_rank(wc) > before_e:
		events.append({ "type": "expertise_rank", "weapon": wc, "rank": u.expertise_letter(wc) })
	return events


## D179: `n` levels, each with its stat gains (level_gains). Returns one
## { type: "level", level, gains } event per level.
static func level_up(u: BWUnit, n: int = 1) -> Array:
	var events: Array = []
	for i in maxi(n, 0):
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
