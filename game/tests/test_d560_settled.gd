extends RefCounted
## D560-D563 (author, 2026-10-11): duo perks are their own pick at 4 tree
## picks in each element (test_keystones_v3.test_duo_offers); a settled unit
## (3 elements) trains "Specialize in X element, Y weapon" on both day tiles;
## learned abilities fill empty slots; an undressed squad is dressed before
## fight 1.


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(x): return str(x.id))


func _settle(r: BWRun, u: BWUnit) -> Array:
	var others: Array = BWFormulas.ELEMENTS.filter(func(e): return e != u.element)
	u.affinity[str(others[0])] = 10
	u.affinity[str(others[1])] = 10
	var wc: String = BWRun.weapon_classes().filter(func(c): return c != u.weapon_class)[0]
	u.expertise[wc] = 10
	return [others[0], others[1], wc]


func test_unsettled_keeps_branch_out(t) -> void:
	var r := BWRun.start(_ids(), 3)
	var u: BWUnit = r.squad[0]
	t.ok(not r.settled(u), "one element: not settled")
	t.ok(r.specialize_preview(u).is_empty(), "no pairings")
	t.eq(r.day_cards(u, "branch_out"), r.branch_preview(u), "Branch out shows its cards")
	t.eq(r.day_cards(u, "specialize"), [], "Specialize is the plain tile")
	t.eq(r.choice_name(u, "branch_out"), "Branch out", "named Branch out")


func test_settled_pairings(t) -> void:
	var r := BWRun.start(_ids(), 3)
	var u: BWUnit = r.squad[0]
	var got := _settle(r, u)
	t.ok(r.settled(u), "three elements: settled")
	var sc := r.specialize_preview(u)
	t.eq(sc.size(), 2, "two pairings")
	t.eq(sc[0], { "element": u.focus(), "weapon": u.weapon_class }, "the first: focus and the class in hand")
	t.ok(str(sc[1].element) != u.focus(), "the second: another element first")
	t.ok(str(sc[1].element) in u.attuned_elements(), "an element it has")
	t.ok(str(sc[1].weapon) in [u.weapon_class, got[2]], "a class it has expertise in")
	t.eq(r.specialize_preview(u), sc, "stable all day")
	t.eq(r.day_cards(u, "specialize"), [sc[0]], "the Specialize tile: the first")
	t.eq(r.day_cards(u, "branch_out"), [sc[1]], "the Branch out tile: the second")
	t.eq(r.choice_name(u, "branch_out"), "Specialize", "and it's named Specialize")


func test_settled_branch_out_trains_the_pairing(t) -> void:
	var r := BWRun.start(_ids(), 3)
	var u: BWUnit = r.squad[0]
	_settle(r, u)
	var sc := r.specialize_preview(u)
	var el := str(sc[1].element)
	var wc := str(sc[1].weapon)
	var a0 := int(u.affinity.get(el, 0))
	var x0 := int(u.expertise.get(wc, 0))
	var n0 := u.attuned_elements().size()
	var rep := r.downtime(u, "branch_out")
	t.eq(str(rep.choice), "specialize", "reported as a Specialize")
	t.ok(not rep.get("pending", false), "no Branch out cards to take")
	t.eq(int(u.affinity.get(el, 0)), a0 + BWRun.SPECIALIZE_POINTS, "+half a rank in %s" % el)
	t.eq(int(u.expertise.get(wc, 0)), x0 + BWRun.SPECIALIZE_POINTS, "+half a rank in %s" % wc)
	t.eq(u.attuned_elements().size(), n0, "no new element")


func test_settled_specialize_trains_the_first(t) -> void:
	var r := BWRun.start(_ids(), 3)
	var u: BWUnit = r.squad[0]
	_settle(r, u)
	var sc := r.specialize_preview(u)
	var a0 := int(u.affinity.get(str(sc[0].element), 0))
	r.downtime(u, "specialize")
	t.eq(int(u.affinity.get(str(sc[0].element), 0)), a0 + BWRun.SPECIALIZE_POINTS, "the focus trains")


func test_abilities_fill_empty_slots(t) -> void:
	var r := BWRun.start(_ids(), 3)
	var u: BWUnit = r.squad[0]
	var ab := ""
	for row in BWData.table("abilities"):
		ab = str(row.id)
		break
	var type := BWRun.ability_type(ab)
	r.learned[u.id] = [ab]
	r.equipped_ability[u.id] = {}
	var auto := r.fill_abilities(u)
	t.eq(str(r.equipped_ability[u.id].get(type, "")), ab, "an empty %s slot takes it" % type)
	t.eq(auto.size(), 1, "reported")
	t.eq(r.fill_abilities(u), [], "a filled slot stays")
	r.learned[u.id] = []
	r.fill_abilities(u)
	t.ok(not r.equipped_ability[u.id].has(type), "a stale entry is dropped")


func test_first_fight_auto_dress(t) -> void:
	var r := BWRun.start(_ids(), 3)
	var n := r.inventory.size()
	t.ok(r.auto_dress_first(), "an undressed squad is dressed before fight 1")
	t.ok(r.inventory.size() < n, "the starting kit was handed out")
	t.ok(not r.auto_dress_first(), "once anyone wears something, it leaves it alone")
	var r2 := BWRun.start(_ids(), 3)
	r2.fight = 2
	t.ok(not r2.auto_dress_first(), "only before the first fight")
