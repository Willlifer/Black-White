class_name BWAutoEquip
extends RefCounted
## Auto-equip (D315-D318): "Optimize all" hands the squad's gear out by who
## is used most; "Optimize" fills one unit from the loose inventory. Pure: no
## nodes. A plan is computed first (the preview), then applied; apply returns
## a snapshot that `undo` restores (one step).
##
## Priority (D315): fights deployed this run (BWRun.stats.units[id].fights),
## then damage dealt there, then level, then squad order.
##
## A unit's profile (D316):
##   element  its highest affinity (points come from using an element in
##            battle, +1 an attack and +3 a KO, and from training it); ties go
##            to the focus, then the native element. The run's stats keep no
##            per-element damage, and affinity is the one per-unit "what it
##            uses" count the rules already keep.
##   weapon   the class of its drawn main weapon (u.weapon_class).
##   second   the class it has the most expertise in other than `weapon`.
##
## Scoring an item for a slot (D317), highest wins, lexicographic:
##   main hand  its class is the unit's weapon (a sword user keeps a sword:
##              expertise sets hit chance and the skill bar)
##   second     a different class than the drawn weapon, the unit's
##              expertise in it, then the rest
##   element    the item's element (armour colour, a weapon's imbue) is the
##              unit's element
##   set        it brings a learned element to 2 or 3 pieces (head, chest,
##              legs and the drawn weapon count; BWSets)
##   tier, then the stat total, then the piece the unit already wears there,
##   then the lower uid (determinism).
## Cursed pieces (an enchantment or imbue row marked cursed) are only ever
## kept by the unit already wearing them: never handed to anyone else.
##
## Optimize all (D318): units in priority order; each takes from the loose
## inventory, from what higher units let go, and from units below it
## (stealing), never from a unit above it (those are settled). A second
## weapon is never another unit's drawn weapon, and is skipped when taking
## it would leave a later unit with no weapon. Whatever nobody takes goes to
## the inventory; the discard pile is never touched (it isn't the inventory).

const SET_SLOTS := ["main_hand", "chest", "legs", "head"]
const PASSES := 2

const W_CLASS := 1.0e7
const W_SECOND_EXP := 1.0e6
const W_ELEMENT := 1.0e5
const W_SET := 3.0e4
const W_TIER := 1.0e3
const W_STAT := 10.0
const W_KEEP := 2.0 * W_STAT + 1.0     # a piece must beat what's worn there by 3+ stat points to move


# ---------------------------------------------------------------- priority and profile

## Squad units, most used first.
static func priority(run: BWRun) -> Array:
	var order: Array = []
	for i in run.squad.size():
		var u: BWUnit = run.squad[i]
		var s: Dictionary = run.stats.get("units", {}).get(u.id, {})
		order.append([u, int(s.get("fights", 0)), int(s.get("damage", 0)), int(u.level), i])
	order.sort_custom(func(a, b):
		for k in [1, 2, 3]:
			if a[k] != b[k]:
				return a[k] > b[k]
		return a[4] < b[4])
	return order.map(func(x): return x[0])


## The element `u` uses most: highest affinity; ties go to the focus, then the native element.
static func used_element(u: BWUnit) -> String:
	var best := u.focus()
	var bp := int(u.affinity.get(best, 0))
	var cand: Array = [u.focus(), u.element] + BWFormulas.ELEMENTS
	for el in cand:
		if el == "":
			continue
		var p := int(u.affinity.get(el, 0))
		if p > bp:
			best = el
			bp = p
	return best


static func profile(u: BWUnit) -> Dictionary:
	var wc := u.weapon_class
	var sec := ""
	var sp := 0
	for c in BWRun.weapon_classes():
		if c == wc:
			continue
		var p := int(u.expertise.get(c, 0))
		if p > sp:
			sec = c
			sp = p
	return { "element": used_element(u), "weapon": wc, "second": sec }


# ---------------------------------------------------------------- scoring

static func cursed(it: Dictionary) -> bool:
	return BWEffects.cursed(str(it.get("enchant", ""))) or BWEffects.cursed(str(it.get("imbue_enchant", "")))


static func stat_total(it: Dictionary) -> int:
	var n := 0
	for k in it.get("stats", {}):
		n += int(it.stats[k])
	return n


## The score of `it` in `slot` for `u` (profile `pf`), with `counts` the set
## pieces its other set slots already hold (element -> n).
static func score(u: BWUnit, pf: Dictionary, it: Dictionary, slot: String, counts: Dictionary) -> float:
	var s := 0.0
	var el := BWSets.item_set_element(it)
	if slot == "main_hand":
		if str(it.get("weight", "")) == str(pf.weapon):
			s += W_CLASS
	elif slot == BWUnit.SECOND:
		var wc := str(it.get("weight", ""))
		if wc != str(pf.weapon):
			s += W_CLASS
			s += W_SECOND_EXP * mini(int(u.expertise.get(wc, 0)) / BWUnit.POINTS_PER_RANK, 5) / 5.0
			if wc == str(pf.second):
				s += W_SECOND_EXP * 0.5
	if el != "" and el == str(pf.element):
		s += W_ELEMENT
	if slot in SET_SLOTS and el != "" and int(u.affinity.get(el, 0)) > 0:
		var n := int(counts.get(el, 0)) + 1
		if n == 2 or n == 3:
			s += W_SET
	s += W_TIER * BWRun.TIERS.find(str(it.get("tier", "E")))
	s += W_STAT * stat_total(it)
	if u.equipment.get(slot, {}) == it:
		s += W_KEEP
	return s


## May `u` be handed `it`? A cursed piece only stays where it is.
static func allowed(u: BWUnit, it: Dictionary) -> bool:
	if not cursed(it):
		return true
	for slot in BWRun.GEAR_SLOTS:
		if u.equipment.get(slot, {}) == it:
			return true
	return false


static func _kind(slot: String) -> String:
	return "main_hand" if slot == BWUnit.SECOND else slot


## The best of `cands` for `slot`, {} if none. Ties: the lower uid.
static func _best(u: BWUnit, pf: Dictionary, cands: Array, slot: String, counts: Dictionary) -> Dictionary:
	var best := {}
	var bs := -1.0
	for it in cands:
		var sc := score(u, pf, it, slot, counts)
		if sc > bs or (sc == bs and str(it.uid) < str(best.get("uid", ""))):
			best = it
			bs = sc
	return best


## Set pieces of `chosen` (slot -> item), leaving out `skip`.
static func _counts(chosen: Dictionary, skip: String) -> Dictionary:
	var c := {}
	for slot in SET_SLOTS:
		if slot == skip or chosen.get(slot, {}).is_empty():
			continue
		var el := BWSets.item_set_element(chosen[slot])
		if el != "":
			c[el] = int(c.get(el, 0)) + 1
	return c


## One unit's loadout from `pool` (Array of items it may take). `spare`
## (item) -> bool: may this weapon go in the second slot.
static func _fill(u: BWUnit, pool: Array, spare: Callable) -> Dictionary:
	var pf := profile(u)
	var chosen := {}
	for slot in SET_SLOTS:
		var cur: Dictionary = u.equipment.get(slot, {})
		if not cur.is_empty() and cur in pool:
			chosen[slot] = cur
	for p in PASSES:
		for slot in SET_SLOTS:
			var taken := []
			for s2 in chosen:
				if s2 != slot:
					taken.append(chosen[s2])
			var cands := pool.filter(func(it): return str(it.get("slot", "")) == slot and not it in taken and allowed(u, it))
			var b := _best(u, pf, cands, slot, _counts(chosen, slot))
			if b.is_empty():
				chosen.erase(slot)
			else:
				chosen[slot] = b
	var used: Array = chosen.values()
	var cands2 := pool.filter(func(it): return str(it.get("slot", "")) == "main_hand" and not it in used and allowed(u, it) and spare.call(it))
	var b2 := _best(u, pf, cands2, BWUnit.SECOND, {})
	if not b2.is_empty():
		chosen[BWUnit.SECOND] = b2
	return chosen


# ---------------------------------------------------------------- plans

## Optimize all: { loadouts: { unit id: { slot: item } }, changes: [...] }.
static func plan_all(run: BWRun) -> Dictionary:
	var order := priority(run)
	var avail: Array = run.inventory.duplicate()
	var holder := {}                      # item uid -> the unit wearing it now
	for u in run.squad:
		for slot in BWRun.GEAR_SLOTS:
			var it: Dictionary = u.equipment.get(slot, {})
			if not it.is_empty():
				avail.append(it)
				holder[str(it.uid)] = u
	var loadouts := {}
	for i in order.size():
		var u: BWUnit = order[i]
		var later: Array = order.slice(i + 1)
		var spare := func(it: Dictionary) -> bool:
			var h = holder.get(str(it.uid))
			if h != null and h != u and h in later and h.equipment.get("main_hand", {}) == it:
				return false                  # never disarm a unit for a carried weapon
			# leave a weapon for every later unit
			var left := 0
			for w in avail:
				if w != it and str(w.get("slot", "")) == "main_hand" and not cursed(w) and not w in loadouts.get(u.id, {}).values():
					left += 1
			for v in later:
				var own: Dictionary = v.equipment.get("main_hand", {})
				if cursed(own) and own in avail:
					left += 1
			return left >= later.size()
		# everything still unclaimed: loose, let go by a unit above, or worn by
		# this unit or one below it (a unit above has already kept its pieces)
		var pool: Array = avail.duplicate()
		var lo := _fill_main_first(u, pool, spare, loadouts)
		if lo.get("main_hand", {}).is_empty():
			# no allowed weapon left: keep its own, or the best leftover of any kind
			var own: Dictionary = u.equipment.get("main_hand", {})
			if own in avail:
				lo["main_hand"] = own
			else:
				var ws := avail.filter(func(it): return str(it.get("slot", "")) == "main_hand" and not it in lo.values())
				if not ws.is_empty():
					lo["main_hand"] = _best(u, profile(u), ws, "main_hand", {})
		loadouts[u.id] = lo
		for it in lo.values():
			avail.erase(it)
	return _with_changes(run, loadouts)


## _fill, writing the result into `into[u.id]` before the second slot is
## decided (the reserve count reads it).
static func _fill_main_first(u: BWUnit, pool: Array, spare: Callable, into: Dictionary) -> Dictionary:
	var lo := _fill(u, pool, func(_it): return false)
	into[u.id] = lo
	var pf := profile(u)
	var used: Array = lo.values()
	var cands := pool.filter(func(it): return str(it.get("slot", "")) == "main_hand" and not it in used and allowed(u, it) and spare.call(it))
	var b := _best(u, pf, cands, BWUnit.SECOND, {})
	if not b.is_empty():
		lo[BWUnit.SECOND] = b
	return lo


## Optimize one unit: its own pieces and the loose inventory, nobody else's.
static func plan_unit(run: BWRun, u: BWUnit) -> Dictionary:
	var pool: Array = run.inventory.duplicate()
	for slot in BWRun.GEAR_SLOTS:
		var it: Dictionary = u.equipment.get(slot, {})
		if not it.is_empty():
			pool.append(it)
	var lo := _fill(u, pool, func(_it): return true)
	if lo.get("main_hand", {}).is_empty():
		lo["main_hand"] = u.equipment.get("main_hand", {})
	var loadouts := {}
	for v in run.squad:
		loadouts[v.id] = v.equipment.duplicate() if v != u else lo
	return _with_changes(run, loadouts)


## Adds `changes`: one row per piece a unit gains, in squad order then slot
## order: { unit, slot, item, from (unit id, "" = the inventory), out (what
## left that slot, {} = nothing) }; and `freed`: pieces going to the inventory.
static func _with_changes(run: BWRun, loadouts: Dictionary) -> Dictionary:
	var where := {}                       # item uid -> [unit id, slot] now
	for u in run.squad:
		for slot in BWRun.GEAR_SLOTS:
			var it: Dictionary = u.equipment.get(slot, {})
			if not it.is_empty():
				where[str(it.uid)] = [u.id, slot]
	var changes: Array = []
	var kept := {}
	for u in run.squad:
		var lo: Dictionary = loadouts.get(u.id, u.equipment)
		for slot in BWRun.GEAR_SLOTS:
			var it: Dictionary = lo.get(slot, {})
			if not it.is_empty():
				kept[str(it.uid)] = true
			var was: Dictionary = u.equipment.get(slot, {})
			if it == was:
				continue
			if it.is_empty():
				changes.append({ "unit": u.id, "slot": slot, "item": {}, "from": "", "out": was })
				continue
			var w: Array = where.get(str(it.uid), ["", ""])
			changes.append({ "unit": u.id, "slot": slot, "item": it, "from": str(w[0]), "from_slot": str(w[1]), "out": was })
	var freed: Array = []
	for u in run.squad:
		for slot in BWRun.GEAR_SLOTS:
			var it: Dictionary = u.equipment.get(slot, {})
			if not it.is_empty() and not kept.has(str(it.uid)):
				freed.append(it)
	return { "loadouts": loadouts, "changes": changes, "freed": freed }


static func empty(plan: Dictionary) -> bool:
	return plan.get("changes", []).is_empty()


# ---------------------------------------------------------------- apply and undo

## Everything needed to put the gear back: per unit its equipment (the same
## item dictionaries), and the inventory's order.
static func snapshot(run: BWRun) -> Dictionary:
	var eq := {}
	for u in run.squad:
		eq[u.id] = u.equipment.duplicate()
	return { "equipment": eq, "inventory": run.inventory.duplicate(), "uids": _uids(run) }


static func _uids(run: BWRun) -> Array:
	var out: Array = []
	for it in run.inventory:
		out.append(str(it.uid))
	for u in run.squad:
		for slot in BWRun.GEAR_SLOTS:
			var it: Dictionary = u.equipment.get(slot, {})
			if not it.is_empty():
				out.append(str(it.uid))
	out.sort()
	return out


## Apply a plan. Returns the snapshot for `undo` ({} if nothing changed).
## The inventory keeps its order; pieces let go are added at the end.
static func apply(run: BWRun, plan: Dictionary) -> Dictionary:
	if empty(plan):
		return {}
	var snap := snapshot(run)
	var lo: Dictionary = plan.loadouts
	var worn := {}
	for id in lo:
		for slot in lo[id]:
			if not lo[id][slot].is_empty():
				worn[str(lo[id][slot].uid)] = true
	var inv: Array = run.inventory.filter(func(it): return not worn.has(str(it.uid)))
	for u in run.squad:
		for slot in BWRun.GEAR_SLOTS:
			var it: Dictionary = u.equipment.get(slot, {})
			if not it.is_empty() and not worn.has(str(it.uid)) and not it in inv:
				inv.append(it)
	for u in run.squad:
		if not lo.has(u.id):
			continue
		var eq := {}
		for slot in BWRun.GEAR_SLOTS:
			var it: Dictionary = lo[u.id].get(slot, {})
			if not it.is_empty():
				eq[slot] = it
		for k in u.equipment:
			if not k in BWRun.GEAR_SLOTS:
				eq[k] = u.equipment[k]
		u.equipment = eq
		u.sync_weapon()
		u.refresh_effects()
	run.inventory = inv
	return snap


## Put the gear back as `snap` had it. Refused (false) if the pieces the run
## owns changed since (a shop trade, a discard, new loot).
static func undo(run: BWRun, snap: Dictionary) -> bool:
	if snap.is_empty() or snap.get("uids", []) != _uids(run):
		return false
	for u in run.squad:
		if snap.equipment.has(u.id):
			u.equipment = snap.equipment[u.id].duplicate()
			u.sync_weapon()
			u.refresh_effects()
	run.inventory = snap.inventory.duplicate()
	return true
