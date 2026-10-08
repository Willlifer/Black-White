extends RefCounted
## D315-D318, D403-D404: auto-equip (BWAutoEquip). Priority, element matching, set
## completion, stealing only from lower priority, cursed pieces, the
## per-unit no-steal Optimize, determinism, apply and undo.


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(x): return str(x.id))


## A run whose squad wears only a plain tier-E weapon of its class and an
## empty inventory, so each test places exactly the pieces it reads.
func _bare(seed_v: int = 3) -> BWRun:
	var r := BWRun.start(_ids(), seed_v)
	r.inventory.clear()
	for u in r.squad:
		u.equipment = { "main_hand": r.make_item(_base_of(u.weapon_class), "E", "") }
		u.sync_weapon()
		u.refresh_effects()
	return r


func _base_of(wc: String) -> String:
	for row in BWData.table("equipment"):
		if str(row.weight) == wc:
			return str(row.id)
	return "sword"


func _ench(el: String) -> String:
	for row in BWData.table("enchantments"):
		if str(row.element) == el and not BWEffects.cursed(row) and str(row.id) != BWEffects.WARDED:
			return str(row.id)
	return ""


func _cursed() -> String:
	for row in BWData.table("enchantments"):
		if BWEffects.cursed(row):
			return str(row.id)
	return ""


func _armour(r: BWRun, base: String, tier: String, el: String) -> Dictionary:
	return r.make_item(base, tier, _ench(el) if el != "" else "")


func _used(r: BWRun, u: BWUnit, fights: int, dmg: int = 0) -> void:
	r.stats.units[u.id] = { "fights": fights, "kos": 0, "damage": dmg, "taken": 0, "mvp": 0 }


# ---------------------------------------------------------------- D315 priority

func test_priority_order(t) -> void:
	var r := _bare()
	var s: Array = r.squad
	_used(r, s[3], 5, 100)
	_used(r, s[1], 5, 300)
	_used(r, s[4], 2, 999)
	s[5].level = 9
	var ord := BWAutoEquip.priority(r).map(func(u): return u.id)
	t.eq(ord[0], s[1].id, "most fights, then more damage first")
	t.eq(ord[1], s[3].id, "same fights, less damage second")
	t.eq(ord[2], s[4].id, "fewer fights after")
	t.eq(ord[3], s[5].id, "unused: higher level first")
	t.eq(ord.slice(4), [s[0].id, s[2].id], "then squad order")


func test_used_element(t) -> void:
	var r := _bare()
	var u: BWUnit = r.squad[0]
	t.eq(BWAutoEquip.primary(u), u.element, "fresh: the native element")
	var other := "water" if u.element != "water" else "fire"
	u.affinity[other] = int(u.affinity.get(u.element, 0)) + 50
	t.eq(BWAutoEquip.primary(u), u.element, "D403: a higher affinity doesn't displace the focus (native)")
	t.eq(BWAutoEquip.used_element(u), other, "the most-used element (the featured scroll's) is still the highest affinity")
	u.focus_element = other
	t.eq(BWAutoEquip.primary(u), other, "the chosen focus is the primary")


## D403: focus, then the other learned elements by rank, points, data order.
func test_element_priority_list(t) -> void:
	var r := _bare()
	var u: BWUnit = r.squad[0]
	var rest: Array = BWFormulas.ELEMENTS.filter(func(e): return e != u.element)
	var a: String = rest[0]
	var b: String = rest[1]
	var c: String = rest[2]
	var d: String = rest[3]
	u.affinity = { u.element: 10, a: 12, b: 35, c: 12, d: 0 }
	u.focus_element = a
	t.eq(BWAutoEquip.elements(u), [a, b, c, u.element], "focus, then rank 3, then rank 1 by points (12 over 10)")
	u.affinity[c] = 10
	var tie := [u.element, c] if BWFormulas.ELEMENTS.find(u.element) < BWFormulas.ELEMENTS.find(c) else [c, u.element]
	t.eq(BWAutoEquip.elements(u), [a, b] + tie, "a points tie goes to data order")
	t.ok(not d in BWAutoEquip.elements(u), "an unlearned element isn't listed")
	u.focus_element = ""
	t.eq(BWAutoEquip.elements(u)[0], u.element, "no focus chosen: the native element leads")


# ---------------------------------------------------------------- D317 scoring

func test_element_match_beats_tier(t) -> void:
	var r := _bare()
	var u: BWUnit = r.squad[0]
	var el := BWAutoEquip.primary(u)
	var other := "dark" if el != "dark" else "light"
	var m_it := _armour(r, "vest", "E", el)
	var high := _armour(r, "chain_mail", "A", other)
	r.inventory = [high, m_it]
	var plan := BWAutoEquip.plan_unit(r, u)
	t.eq(plan.loadouts[u.id].get("chest", {}).get("uid", ""), m_it.uid, "the used element's piece over a higher tier")
	var plain_a := _armour(r, "platemail", "A", "")
	var plain_e := _armour(r, "brigandine", "E", "")
	r.inventory = [plain_e, plain_a]
	plan = BWAutoEquip.plan_unit(r, u)
	t.eq(plan.loadouts[u.id].chest.uid, plain_a.uid, "no element match: the higher tier")


func test_weapon_class_match(t) -> void:
	var r := _bare()
	var u: BWUnit = r.squad[0]
	var wc := u.weapon_class
	var other := "staff" if wc != "staff" else "sword"
	var off := r.make_item(_base_of(other), "A", "")
	var on := r.make_item(_base_of(wc), "D", "")
	r.inventory = [off, on]
	var lo: Dictionary = BWAutoEquip.plan_unit(r, u).loadouts[u.id]
	t.eq(lo.main_hand.uid, on.uid, "the main hand keeps the class")
	t.eq(lo.get("second", {}).get("uid", ""), off.uid, "the other class goes in the second slot")


func test_second_prefers_expertise(t) -> void:
	var r := _bare()
	var u: BWUnit = r.squad[0]
	var picks := BWRun.weapon_classes().filter(func(c): return c != u.weapon_class)
	var a: String = picks[0]
	var b: String = picks[1]
	u.expertise[b] = 2 * BWUnit.POINTS_PER_RANK
	var wa := r.make_item(_base_of(a), "B", "")
	var wb := r.make_item(_base_of(b), "E", "")
	r.inventory = [wa, wb]
	var lo: Dictionary = BWAutoEquip.plan_unit(r, u).loadouts[u.id]
	t.eq(lo.second.uid, wb.uid, "the second slot: a class with expertise over a higher tier")


func test_set_completion(t) -> void:
	var r := _bare()
	var u: BWUnit = r.squad[0]
	var el := BWAutoEquip.primary(u)
	# another learned element with a head piece worn: a second piece makes its 2-set
	var other := "ice" if el != "ice" else "wind"
	u.affinity[other] = 1
	u.equipment["head"] = _armour(r, "wizard_hat", "E", other)
	var two := _armour(r, "vest", "E", other)
	var plain := _armour(r, "leather_cuirass", "C", "")
	r.inventory = [plain, two]
	var lo: Dictionary = BWAutoEquip.plan_unit(r, u).loadouts[u.id]
	t.eq(lo.chest.uid, two.uid, "completing a 2-piece set beats a plain higher tier")
	t.eq(lo.head.uid, u.equipment.head.uid, "the head stays")
	# unlearned: the set sleeps, the tier wins
	u.affinity[other] = 0
	lo = BWAutoEquip.plan_unit(r, u).loadouts[u.id]
	t.eq(lo.chest.uid, plain.uid, "an unlearned set counts for nothing")


# ---------------------------------------------------------------- D318 stealing

func test_steals_only_downward(t) -> void:
	var r := _bare()
	var hi: BWUnit = r.squad[0]
	var lo_u: BWUnit = r.squad[1]
	var mid: BWUnit = r.squad[2]
	_used(r, hi, 6)
	_used(r, mid, 4)
	_used(r, lo_u, 1)
	var good := _armour(r, "chain_mail", "A", "")
	var mid_good := _armour(r, "platemail", "B", "")
	lo_u.equipment["chest"] = good          # the lowest wears the best chest
	hi.equipment["chest"] = mid_good        # the top wears the second best
	var plan := BWAutoEquip.plan_all(r)
	t.eq(plan.loadouts[hi.id].chest.uid, good.uid, "the top unit takes the best chest from a lower one")
	t.eq(plan.loadouts[mid.id].get("chest", {}).get("uid", ""), mid_good.uid, "what it let go goes to the next unit")
	t.ok(plan.loadouts[lo_u.id].get("chest", {}).is_empty(), "the lowest is left without")
	t.ok(plan.changes.any(func(c): return c.unit == hi.id and str(c.from) == lo_u.id), "the change names who it came from")
	# a low unit never takes from a higher one
	var r2 := _bare()
	_used(r2, r2.squad[0], 6)
	var top_chest := _armour(r2, "chain_mail", "A", "")
	r2.squad[0].equipment["chest"] = top_chest
	var p2 := BWAutoEquip.plan_all(r2)
	t.eq(p2.loadouts[r2.squad[0].id].chest.uid, top_chest.uid, "the top keeps its piece")
	for c in p2.changes:
		t.ok(c.from != r2.squad[0].id, "nobody takes from the top unit (%s)" % c.unit)


func test_nobody_disarmed(t) -> void:
	var r := _bare()
	_used(r, r.squad[0], 6)
	# a juicy weapon of another class on a low unit: not a carried weapon for the top
	var plan := BWAutoEquip.plan_all(r)
	for u in r.squad:
		t.ok(not plan.loadouts[u.id].get("main_hand", {}).is_empty(), "%s keeps a weapon in hand" % u.name)
	var seen := {}
	for id in plan.loadouts:
		for slot in plan.loadouts[id]:
			var uid := str(plan.loadouts[id][slot].uid)
			t.ok(not seen.has(uid), "piece %s worn once" % uid)
			seen[uid] = true


# ---------------------------------------------------------------- cursed

func test_never_auto_equips_cursed(t) -> void:
	var r := _bare()
	var u: BWUnit = r.squad[0]
	var cur := _cursed()
	t.ok(cur != "", "a cursed row exists")
	var bad := r.make_item("platemail", "A", cur)
	var plain := r.make_item("vest", "E", "")
	r.inventory = [bad, plain]
	var lo: Dictionary = BWAutoEquip.plan_unit(r, u).loadouts[u.id]
	t.eq(lo.chest.uid, plain.uid, "a loose cursed piece is never handed out")
	var all := BWAutoEquip.plan_all(r)
	for id in all.loadouts:
		t.ok(all.loadouts[id].get("chest", {}).get("uid", "") != bad.uid, "nor by Optimize all (%s)" % id)
	# worn already: it may stay
	r.inventory = [plain]
	u.equipment["chest"] = bad
	lo = BWAutoEquip.plan_unit(r, u).loadouts[u.id]
	t.eq(lo.chest.uid, bad.uid, "a cursed piece already worn stays (opted in)")
	# and it is never stolen by someone else
	_used(r, r.squad[1], 9)
	var p := BWAutoEquip.plan_all(r)
	t.eq(p.loadouts[u.id].chest.uid, bad.uid, "the wearer keeps it under Optimize all")


# ---------------------------------------------------------------- per unit

func test_unit_never_steals(t) -> void:
	var r := _bare()
	var u: BWUnit = r.squad[0]
	var v: BWUnit = r.squad[1]
	var good := _armour(r, "chain_mail", "A", "")
	v.equipment["chest"] = good
	var loose := _armour(r, "vest", "E", "")
	r.inventory = [loose]
	var plan := BWAutoEquip.plan_unit(r, u)
	t.eq(plan.loadouts[u.id].chest.uid, loose.uid, "Optimize fills from the inventory only")
	t.eq(plan.loadouts[v.id].chest.uid, good.uid, "the other unit is untouched")
	for c in plan.changes:
		t.eq(c.unit, u.id, "every change is on the unit")
		t.ok(c.from == "" or c.from == u.id, "nothing from another unit")


# ---------------------------------------------------------------- determinism, apply, undo

func _setup_mixed(seed_v: int) -> BWRun:
	var r := BWRun.start(_ids(), seed_v)
	r.fight = 6
	for i in 14:
		r.inventory.append(r.random_item(["E", "D", "C", "B"][i % 4]))
	_used(r, r.squad[2], 4, 200)
	_used(r, r.squad[4], 3, 50)
	return r


func _sig(plan: Dictionary) -> Array:
	var out: Array = []
	for id in plan.loadouts.keys():
		for slot in BWRun.GEAR_SLOTS:
			out.append("%s:%s:%s" % [id, slot, str(plan.loadouts[id].get(slot, {}).get("uid", ""))])
	out.sort()
	return out


func test_deterministic(t) -> void:
	var a := BWAutoEquip.plan_all(_setup_mixed(11))
	var b := BWAutoEquip.plan_all(_setup_mixed(11))
	t.eq(_sig(a), _sig(b), "same inputs, same plan")
	t.ok(not BWAutoEquip.empty(a), "the mixed run changes something")
	# applying the plan and planning again changes nothing
	var r := _setup_mixed(11)
	BWAutoEquip.apply(r, BWAutoEquip.plan_all(r))
	t.ok(BWAutoEquip.empty(BWAutoEquip.plan_all(r)), "a second Optimize all is a no-op")


func test_apply_and_undo(t) -> void:
	var r := _setup_mixed(12)
	r.trash.append(r.inventory.pop_back())
	var trashed: Dictionary = r.trash[0]
	var before_inv := r.inventory.map(func(it): return str(it.uid))
	var before_eq := {}
	var count := r.inventory.size()
	for u in r.squad:
		before_eq[u.id] = BWRun.GEAR_SLOTS.map(func(s): return str(u.equipment.get(s, {}).get("uid", "")))
		count += u.equipment.size()
	var plan := BWAutoEquip.plan_all(r)
	var snap := BWAutoEquip.apply(r, plan)
	t.ok(not snap.is_empty(), "applied")
	var after := r.inventory.size()
	for u in r.squad:
		after += u.equipment.size()
		t.ok(not u.equipment.get("main_hand", {}).is_empty(), "%s holds a weapon" % u.name)
		t.eq(u.weapon_class, str(u.equipment.main_hand.weight), "%s's class follows the hand" % u.name)
	t.eq(after, count, "no piece lost or doubled")
	t.ok(trashed in r.trash and not trashed in r.inventory, "the discard pile is untouched")
	t.ok(BWAutoEquip.undo(r, snap), "undo")
	t.eq(r.inventory.map(func(it): return str(it.uid)), before_inv, "the inventory as it was, in order")
	for u in r.squad:
		t.eq(BWRun.GEAR_SLOTS.map(func(s): return str(u.equipment.get(s, {}).get("uid", ""))), before_eq[u.id], "%s as it was" % u.name)
	# undo is refused once the owned pieces change
	var snap2 := BWAutoEquip.apply(r, BWAutoEquip.plan_all(r))
	r.trash_item(r.inventory[0])
	t.ok(not BWAutoEquip.undo(r, snap2), "undo refused after a discard")


# ---------------------------------------------------------------- D403 primary then secondary

## A unit with a focus `pri` and a learned `sec` (2nd); returns [u, pri, sec].
## pri is the focus (rank 2), sec has more affinity (rank 3) so it is 2nd,
## the native element (rank 1) is 3rd.
func _two_elements(r: BWRun) -> Array:
	var u: BWUnit = r.squad[0]
	var free: Array = BWFormulas.ELEMENTS.filter(func(e): return e != u.element)
	var pri: String = free[0]
	var sec: String = free[1]
	u.affinity = { u.element: 10, pri: 20, sec: 30 }
	u.focus_element = pri
	return [u, pri, sec]


func test_primary_then_secondary(t) -> void:
	var r := _bare()
	var x := _two_elements(r)
	var u: BWUnit = x[0]
	var pri: String = x[1]
	var sec: String = x[2]
	t.eq(BWAutoEquip.elements(u).slice(0, 2), [pri, sec], "focus first though the 2nd has more affinity")
	var p_head := _armour(r, "wizard_hat", "E", pri)
	var s_head := _armour(r, "wizard_hat", "A", sec)
	var s_chest := _armour(r, "chain_mail", "A", sec)
	var plain_legs := _armour(r, "platelegs", "A", "")
	var s_legs := _armour(r, "chaps", "E", sec)
	r.inventory = [s_head, s_chest, plain_legs, p_head, s_legs]
	var plan := BWAutoEquip.plan_unit(r, u)
	var lo: Dictionary = plan.loadouts[u.id]
	t.eq(lo.head.uid, p_head.uid, "the primary's piece over a higher-tier secondary")
	t.eq(lo.chest.uid, s_chest.uid, "a slot the primary can't fill: the secondary")
	t.eq(lo.legs.uid, s_legs.uid, "the secondary set's 2nd piece over a plain higher tier")
	var reasons := {}
	for c in plan.changes:
		reasons[c.slot] = str(c.get("reason", ""))
	t.eq(reasons.get("head", ""), "%s (focus)" % pri.capitalize(), "reason: the focus")
	t.eq(reasons.get("chest", ""), "%s set 2/3 (2nd)" % sec.capitalize(), "reason: a secondary set")


func test_primary_set_first(t) -> void:
	var r := _bare()
	var x := _two_elements(r)
	var u: BWUnit = x[0]
	var pri: String = x[1]
	var sec: String = x[2]
	# the secondary could make a 3-piece set at tier A; the primary has head
	# and legs at tier E: the primary set takes them, the secondary the chest
	var pieces := {
		"s_head": _armour(r, "wizard_hat", "A", sec), "s_chest": _armour(r, "chain_mail", "A", sec),
		"s_legs": _armour(r, "platelegs", "A", sec),
		"p_head": _armour(r, "wizard_hat", "E", pri), "p_legs": _armour(r, "chaps", "E", pri) }
	r.inventory = pieces.values()
	var plan := BWAutoEquip.plan_unit(r, u)
	var lo: Dictionary = plan.loadouts[u.id]
	t.eq(lo.head.uid, pieces.p_head.uid, "primary head")
	t.eq(lo.legs.uid, pieces.p_legs.uid, "primary legs: the primary set before a secondary 3-piece")
	t.eq(lo.chest.uid, pieces.s_chest.uid, "the secondary fills the chest")
	for c in plan.changes:
		if c.slot in ["head", "legs"]:
			t.eq(str(c.reason), "%s set 2/3" % pri.capitalize(), "reason on %s" % c.slot)
	# with a primary chest too: a 3/3 reason
	var p_chest := _armour(r, "vest", "E", pri)
	r.inventory.append(p_chest)
	plan = BWAutoEquip.plan_unit(r, u)
	t.eq(plan.loadouts[u.id].chest.uid, p_chest.uid, "the primary completes its 3-piece")
	t.ok(plan.changes.all(func(c): return str(c.reason) == "%s set 3/3" % pri.capitalize()), "every change reads %s set 3/3" % pri.capitalize())
	var bb := BWGearPanel.preview_bbcode(r, plan)
	t.ok(bb.contains("%s set 3/3" % pri.capitalize()), "the preview shows the reason")


# ---------------------------------------------------------------- D404 unequip all

func _dressed() -> BWRun:
	var r := _bare()
	var classes := BWRun.weapon_classes()
	for i in r.squad.size():
		var u: BWUnit = r.squad[i]
		u.equipment["chest"] = _armour(r, "vest", "D", "")
		u.equipment["legs"] = _armour(r, "chaps", "E", "")
		var oc: String = classes.filter(func(c): return c != u.weapon_class)[0]
		u.equipment[BWUnit.SECOND] = r.make_item(_base_of(oc), "E", "")
	r.squad[1].equipment["head"] = r.make_item("wizard_hat", "C", _cursed())
	r.inventory = [_armour(r, "platemail", "B", "")]
	return r


func test_unequip_all_keeps_main_hand(t) -> void:
	var r := _dressed()
	var cursed_head: Dictionary = r.squad[1].equipment.head
	var hands := r.squad.map(func(u): return str(u.equipment.main_hand.uid))
	var total := r.inventory.size()
	for u in r.squad:
		total += u.equipment.size()
	var plan := BWAutoEquip.plan_unequip(r)
	t.eq(plan.freed.size(), 3 * r.squad.size() + 1, "chest, legs, second each, plus the cursed head")
	var snap := BWAutoEquip.apply(r, plan)
	t.ok(not snap.is_empty(), "applied")
	for i in r.squad.size():
		var u: BWUnit = r.squad[i]
		t.eq(u.equipment.keys().filter(func(k): return k in BWRun.GEAR_SLOTS), ["main_hand"], "%s wears only its main hand" % u.name)
		t.eq(str(u.equipment.main_hand.uid), hands[i], "%s keeps the same weapon" % u.name)
		t.eq(u.weapon_class, str(u.equipment.main_hand.weight), "%s's class unchanged" % u.name)
	t.ok(cursed_head in r.inventory, "the cursed piece comes off too")
	var after := r.inventory.size()
	for u in r.squad:
		after += u.equipment.size()
	t.eq(after, total, "no piece lost or doubled")
	t.ok(BWAutoEquip.empty(BWAutoEquip.plan_unequip(r)), "a second Unequip all is a no-op")
	var line := BWGearPanel.unequip_line(r, plan)
	t.ok(line.contains("Main-hand weapons stay") and line.contains("(1 cursed)"), "the confirm line: %s" % line)
	t.ok(BWAutoEquip.undo(r, snap), "undo")
	t.eq(r.squad[1].equipment.get("head", {}).get("uid", ""), cursed_head.uid, "undo: the cursed head is back on")
	for u in r.squad:
		t.ok(u.equipment.has("chest") and u.equipment.has(BWUnit.SECOND), "undo: %s dressed again" % u.name)
	t.eq(r.inventory.size(), 1, "undo: the inventory as it was")


func test_unequip_unit_only(t) -> void:
	var r := _dressed()
	var u: BWUnit = r.squad[2]
	var plan := BWAutoEquip.plan_unequip(r, [u])
	for c in plan.changes:
		t.eq(c.unit, u.id, "every change is on the unit")
	t.eq(plan.freed.size(), 3, "its chest, legs and second weapon")
	var snap := BWAutoEquip.apply(r, plan)
	t.ok(u.equipment.has("main_hand") and not u.equipment.has("chest"), "the unit keeps its main hand only")
	t.ok(r.squad[3].equipment.has("chest"), "another unit is untouched")
	t.ok(BWAutoEquip.undo(r, snap) and u.equipment.has("chest"), "undo puts it back")
