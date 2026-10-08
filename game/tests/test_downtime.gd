extends RefCounted
## D127-D132: the three-choice downtime (Specialize, Branch out, Wander), the
## picks they grant, Branch out's two options, Wander's odds and outcomes
## (status immunity, the next-battle brace and buff, one recruit a day, the
## jackpot's reroll), the focus element, weapon-class switching, save v4.
## D175-D177: two of the three choices a day, Branch out's cards shown before
## committing, the jackpot rerolls (no rogue).

const C := Vector2i(4, 4)
const E := Vector2i(5, 4)


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))


## A fresh run with every start pick made, its rng at `seed_value`.
func _run(seed_value: int = 1) -> BWRun:
	var r := BWRun.start(_ids(), 1234)
	for u in r.squad:
		BWPicks.auto_resolve(u)
	r.rng.seed = seed_value
	return r


## D179: no XP; the day's permanent stat points show in the base-stat total.
func _stat_total(u: BWUnit) -> int:
	var n := 0
	for k in BWUnit.STATS:
		n += int(u.stats[k])
	return n


func _board(n: int = 11) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String, el: String, extra: Dictionary = {}) -> BWUnit:
	var row := { "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 }
	row.merge(extra, true)
	return BWUnit.from_roster(row)


func _fight(me: BWUnit, foes: Array, at: Array, seed_value: int = 7) -> BWBattle:
	var b := BWBattle.new(_board(), seed_value)
	b.setup([me], foes)
	me.pos = C
	for i in foes.size():
		foes[i].pos = at[i]
	b.queue = [me]
	b.turn_index = 0
	b._begin_turn()
	return b


func _events(b: BWBattle, type: String) -> Array:
	return b.history.filter(func(e): return e.type == type)


# ------------------------------------------------------------------ the choices

func test_three_choices_and_names(t) -> void:
	t.eq(BWRun.DOWNTIME_CHOICES, ["specialize", "branch_out", "wander"], "three choices (D127)")
	t.eq(BWRun.DOWNTIME_CHOICES.map(func(c): return BWRun.CHOICE_NAMES[c]), ["Specialize", "Branch out", "Wander"], "names")
	var r := _run()
	var day := r.day
	var reps := r.progress_day(r.squad.map(func(u): return [u.id, "wander"]))
	t.eq(reps.size(), 6, "one report per unit")
	t.eq(r.day, day + 1, "the day advances")
	t.ok(reps.all(func(x): return x.ok and str(x.headline).begins_with("I wandered")), "first person")
	t.ok(not r.downtime(r.squad[0], "rest").ok, "the old actions are gone")


## D175: each unit is offered two of the three, per day, from the run seed:
## stable all day (and across a reload), fresh the next day.
func test_day_choices(t) -> void:
	t.eq(BWRun.DOWNTIME_OFFER, 2, "two of the three (D175)")
	var r := _run()
	var combos := {}
	var differs := false
	for d in 12:
		r.day = 1 + d
		for u in r.squad:
			var c := r.day_choices(u)
			t.eq(c.size(), 2, "day %d %s: two choices" % [r.day, u.id])
			t.ok(c.all(func(x): return x in BWRun.DOWNTIME_CHOICES), "real choices")
			t.ok(c[0] != c[1], "two different")
			t.eq(c, BWRun.DOWNTIME_CHOICES.filter(func(x): return x in c), "in the usual order")
			t.eq(r.day_choices(u), c, "stable for the day")
			combos[str(c)] = true
			if r.day > 1:
				r.day -= 1
				differs = differs or r.day_choices(u) != c
				r.day += 1
	t.eq(combos.size(), 3, "every pair turns up: %s" % [combos.keys()])
	t.ok(differs, "a new day can offer a different pair")
	var r2 := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.ok(r.squad.all(func(u): return r2.day_choices(r2.unit(u.id)) == r.day_choices(u)), "a reload offers the same")


func test_specialize_both_branches(t) -> void:
	var seen := { "skill": 0, "weapon": 0, "perk": 0, "armour": 0 }
	for s in 40:
		var r := _run(100 + s)
		var u: BWUnit = r.squad[0]
		var el := u.element
		var wc := u.weapon_class
		var aff := int(u.affinity.get(el, 0))
		var exp_ := int(u.expertise.get(wc, 0))
		var rank := u.affinity_rank(el)
		var xp := _stat_total(u)
		var inv := r.inventory.size()
		var rep := r.downtime(u, "specialize")
		t.eq(int(u.affinity[el]) - aff, 5, "seed %d: +half a level in the element" % s)
		t.eq(int(u.expertise[wc]) - exp_, 5, "seed %d: +half a level in the weapon" % s)
		t.eq(_stat_total(u) - xp, 0, "seed %d: no stat points (and no XP, D179)" % s)
		t.eq(u.affinity_rank(el), rank, "seed %d: the perk point doesn't move the rank (5 points from 10)" % s)
		var weapons: Array = rep.items.filter(func(it): return it.slot == "main_hand")
		var armour: Array = rep.items.filter(func(it): return it.slot != "main_hand")
		if int(u.bonus_skills.get(wc, 0)) == 1:
			seen.skill += 1
			t.ok(weapons.is_empty(), "seed %d: a skill point, no weapon" % s)
			t.eq(BWPicks.skill_picks_owed(u, wc), 1, "seed %d: the free skill pick is owed" % s)
		else:
			seen.weapon += 1
			t.eq(weapons.size(), 1, "seed %d: no skill point: a weapon" % s)
			t.ok(weapons[0].weight == wc and weapons[0].tier == r.tier_for(r.fight), "seed %d: same class, this fight's tier" % s)
		if int(u.bonus_perks.get(el, 0)) == 1:
			seen.perk += 1
			t.ok(armour.is_empty(), "seed %d: a perk point, no armour" % s)
			t.ok(BWPicks.pending(u).any(func(q): return q.kind == "perk" and q.element == el), "seed %d: the free perk is owed" % s)
		else:
			seen.armour += 1
			t.eq(armour.size(), 1, "seed %d: no perk point: armour" % s)
			t.eq(BWRun.item_element(armour[0]), el, "seed %d: attuned to the unit's element" % s)
		t.eq(r.inventory.size() - inv, rep.items.size(), "seed %d: finds go to the inventory" % s)
		t.ok(str(rep.headline).begins_with("I specialized and gained") and str(rep.headline).ends_with("feeling confident."), rep.headline)
		# the picks go through the normal flow and leave nothing owed
		BWPicks.auto_resolve(u)
		t.eq(BWPicks.pending(u), [], "seed %d: picks resolved" % s)
	for k in seen:
		t.ok(seen[k] > 0, "40 seeds reach the %s branch (%d)" % [k, seen[k]])


func test_specialize_impossible_counts_as_a_fail(t) -> void:
	for s in 12:
		var r := _run(300 + s)
		var u: BWUnit = r.squad[0]
		for p in BWPicks.perks_of(u.element):
			if not str(p.id) in u.perks:
				u.perks.append(str(p.id))                   # owns all five (rank 1 + a stack of free picks)
		u.bonus_perks[u.element] = 4
		for k in BWSkillRegistry.pool(u.weapon_class):
			if not k in u.known_skills:
				u.known_skills.append(k)
			u.skill_ranks[k] = 2                            # nothing left to learn or improve
		var rep := r.downtime(u, "specialize")
		t.eq(int(u.bonus_perks[u.element]), 4, "seed %d: no perk point when all five are owned" % s)
		t.eq(int(u.bonus_skills.get(u.weapon_class, 0)), 0, "seed %d: no skill point with nothing to pick" % s)
		t.eq(rep.items.size(), 2, "seed %d: so it finds a weapon and armour instead" % s)


func test_branch_out(t) -> void:
	for s in 20:
		var r := _run(500 + s)
		r.day = 1 + s                                  # D176: the cards are rolled per day
		var u: BWUnit = r.squad[1]
		var own := u.weapon_class
		var aff := u.affinity.duplicate()
		var exp_ := u.expertise.duplicate()
		var xp := _stat_total(u)
		var rep := r.downtime(u, "branch_out", false)
		t.ok(rep.pending and rep.options.size() == 2, "seed %d: two options wait for the player" % s)
		t.eq(u.affinity, aff, "seed %d: nothing applied before the pick (affinity)" % s)
		t.eq(u.expertise, exp_, "seed %d: (expertise)" % s)
		t.eq(_stat_total(u), xp, "seed %d: (stats)" % s)
		var o0: Dictionary = rep.options[0]
		var o1: Dictionary = rep.options[1]
		t.ok(o0.element != o1.element and o0.weapon != o1.weapon, "seed %d: two different pairings %s / %s" % [s, o0, o1])
		for o in rep.options:
			t.eq(u.affinity_rank(o.element), 0, "seed %d: %s is at 0" % [s, o.element])
			t.ok(o.weapon != own and u.expertise_rank(o.weapon) == 0, "seed %d: %s is another class at E" % [s, o.weapon])
		var pick := s % 2
		var o: Dictionary = rep.options[pick]
		var other: Dictionary = rep.options[1 - pick]
		t.ok(r.branch_pick(u, rep, pick), "seed %d: take option %d" % [s, pick + 1])
		t.ok(not r.branch_pick(u, rep, 1 - pick), "seed %d: only once" % s)
		var el := str(o.element)
		var wc := str(o.weapon)
		t.eq(u.affinity_rank(el), 1, "seed %d: a full level in %s" % [s, el])
		t.eq(u.expertise_letter(wc), "D", "seed %d: %s to D" % [s, wc])
		t.eq(u.affinity_rank(str(other.element)), 0, "seed %d: the other option's element untouched" % s)
		t.eq(u.expertise_rank(str(other.weapon)), 0, "seed %d: the other option's class untouched" % s)
		var w: Array = rep.items.filter(func(it): return it.slot == "main_hand")
		var a: Array = rep.items.filter(func(it): return it.slot != "main_hand")
		t.ok(w.size() == 1 and w[0].weight == wc and w[0].tier == r.tier_for(r.fight), "seed %d: a %s of this fight's tier" % [s, wc])
		t.ok(a.size() == 1 and BWRun.item_element(a[0]) == el, "seed %d: armour attuned to %s" % [s, el])
		t.eq(_stat_total(u) - xp, 0, "seed %d: no stat points (and no XP, D179)" % s)
		t.ok(str(rep.headline).contains(el) and str(rep.headline).contains(BWRun.class_name_of(wc)), rep.headline)
		var kinds := BWPicks.pending(u).map(func(q): return "%s:%s" % [q.kind, q.get("element", q.get("weapon", ""))])
		t.ok(("perk:" + el) in kinds and ("skill:" + wc) in kinds, "seed %d: the new element's first perk and a %s skill pick owed: %s" % [s, wc, kinds])
		t.eq(u.weapon_class, own, "seed %d: still holding its own weapon" % s)
		if s == 0:
			t.ok(r.equip(u, w[0]), "the found tier-E weapon can be equipped at D")
			t.eq(u.weapon_class, wc, "and the unit now fights with the %s (D131)" % wc)
	# the AI / sim way: the first option, at once
	var r2 := _run(42)
	var u2: BWUnit = r2.squad[2]
	var rep2 := r2.downtime(u2, "branch_out")
	t.ok(not rep2.pending and int(rep2.picked) == 0, "auto takes the first option")
	t.eq(u2.affinity_rank(str(rep2.options[0].element)), 1, "and applies it")
	# one valid option: one card. D417: a unit holding 3 elements is offered no
	# new element, so with one class left it is one class-only card.
	var r3 := _run(9)
	var u3: BWUnit = r3.squad[0]
	var left: Array = BWFormulas.ELEMENTS.filter(func(e): return u3.affinity_rank(e) == 0)
	for e in left.slice(0, BWUnit.MAX_ELEMENTS - u3.attuned_elements().size()):
		u3.affinity[e] = 10
	var cls: Array = BWRun.weapon_classes().filter(func(c): return c != u3.weapon_class and u3.expertise_rank(c) == 0)
	for c in cls.slice(1):
		u3.expertise[c] = 10
	var rep3 := r3.downtime(u3, "branch_out", false)
	t.eq(rep3.options, [{ "element": "", "weapon": cls[0] }], "at 3 elements, one class left: one class-only card")
	# nothing left: every element ranked, every class at D
	for e in BWFormulas.ELEMENTS:
		u3.affinity[e] = maxi(int(u3.affinity.get(e, 0)), 10)
	for c in BWRun.weapon_classes():
		u3.expertise[c] = maxi(int(u3.expertise.get(c, 0)), 10)
	var xp3 := _stat_total(u3)
	r3.day += 1                                      # a new day: new cards
	var rep4 := r3.downtime(u3, "branch_out", false)
	t.ok(rep4.options.is_empty() and not rep4.get("pending", false), "nothing new to try: no options")
	t.ok(str(rep4.headline).contains("nothing new") and _stat_total(u3) - xp3 == 1, "+1 to a stat: " + rep4.headline)


## D176: the cards are rolled when the day starts and shown in the hall;
## Branch out gives exactly those, and the card taken in the hall (the plan's
## third entry) is applied at once. Another choice leaves them unused.
func test_branch_preview(t) -> void:
	for s in 12:
		var r := _run(800 + s)
		r.day = 1 + s
		var u: BWUnit = r.squad[s % 6]
		var cards := r.branch_preview(u)
		t.ok(cards.size() == 2, "seed %d: two cards before committing" % s)
		t.eq(r.branch_preview(u), cards, "seed %d: the same cards each time it's asked" % s)
		var rngs := r.rng.state
		var re := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
		t.eq(re.branch_preview(re.unit(u.id)), cards, "seed %d: a reload shows the same" % s)
		t.eq(r.rng.state, rngs, "seed %d: the preview leaves the run's rng alone" % s)
		var pick := s % 2
		var reps := r.progress_day([[u.id, "branch_out", pick]], false)
		var rep: Dictionary = reps[0]
		t.eq(rep.options, cards, "seed %d: Branch out gives the previewed cards" % s)
		t.ok(not rep.get("pending", false) and int(rep.picked) == pick, "seed %d: the hall's card %d, applied at once" % [s, pick + 1])
		t.eq(u.affinity_rank(str(cards[pick].element)), 1, "seed %d: its element" % s)
		t.eq(u.expertise_letter(str(cards[pick].weapon)), "D", "seed %d: its class" % s)
		t.eq(u.affinity_rank(str(cards[1 - pick].element)), 0, "seed %d: the other card unused" % s)
	# another choice discards them: nothing of the cards is applied
	var r2 := _run(3)
	var w: BWUnit = r2.squad[0]
	var c2 := r2.branch_preview(w)
	r2.progress_day([[w.id, "specialize"]])
	t.ok(c2.all(func(c): return w.affinity_rank(str(c.element)) == 0), "Specialize instead: the cards' elements untouched")


# ------------------------------------------------------------------ wander

func test_wander_constants(t) -> void:
	t.near(BWRun.WANDER_ROLL, 0.20, 0.0001, "each of the nine at 20%")
	t.eq(BWRun.WANDER_EFFECTS.size(), 9, "nine effects")
	t.near(BWRun.WANDER_JACKPOT_EXTRA_ROLL, 0.05, 0.0001, "the jackpot's extra roll (author: 0.05)")
	t.near(pow(1.0 - BWRun.WANDER_ROLL, 9) * BWRun.WANDER_JACKPOT_EXTRA_ROLL, 0.0067, 0.0001, "≈0.67% a wander")
	t.eq(BWRun.WANDER_STAT_POINT, 1, "the stat effect and the consolation: +1, for good (D179)")
	t.ok(not "xp" in BWRun.WANDER_EFFECTS and "stat" in BWRun.WANDER_EFFECTS, "no XP effect")
	t.near(BWRun.WANDER_JACKPOT_ROLL, 0.30, 0.0001, "the jackpot rerolls the nine at 30% (D177)")


## 10k seeded wanders on fresh units, each with past enemies to meet: every
## effect lands ~20%; nothing at all 0.8^9 ≈ 13.4% of the time; 5% of that is
## the jackpot (≈0.67%).
func test_wander_probabilities(t) -> void:
	var r := _run()
	var e := r.enemies_for(1).map(func(x): return x.to_dict())
	var six := r.squad.duplicate()
	r.rng.seed = 77
	var n := 10000
	var hits := {}
	var none := 0
	var jack := 0
	var row := BWData.row("roster", _ids()[0])
	for i in n:
		r.squad = six.duplicate()
		r.last_enemies = e.duplicate(true)
		r.recruited_today = false
		var u := BWUnit.from_roster(row)
		var rep := r.downtime(u, "wander")
		for k in rep.successes:
			hits[k] = int(hits.get(k, 0)) + 1
		if rep.successes.is_empty() or rep.jackpot:
			none += 1                                  # the first nine all missed
		if rep.jackpot:
			jack += 1
	for k in BWRun.WANDER_EFFECTS:
		t.near(float(hits.get(k, 0)) / n, 0.20, 0.015, "%s ≈ 20%%" % k)
	t.near(float(none) / n, pow(0.8, 9), 0.015, "nothing landed ≈ 0.8^9 = 13.4%%")
	t.near(float(jack) / n, pow(0.8, 9) * 0.05, 0.003, "jackpot ≈ 0.67%% (%d of %d)" % [jack, n])


func test_one_recruit_a_day(t) -> void:
	var days_with_two := 0
	var recruits := 0
	for s in 120:
		var r := _run(4000 + s)
		var e := r.enemies_for(1)
		r.last_enemies = e.map(func(x): return x.to_dict())
		var before := r.squad.size()
		var reps := r.progress_day(r.squad.map(func(u): return [u.id, "wander"]))
		var n := reps.filter(func(x): return "recruit" in x.successes).size()
		t.eq(r.squad.size() - before, n, "seed %d: squad grows by the recruits" % s)
		t.ok(n <= 1, "seed %d: at most one recruit a day, squad-wide (%d)" % [s, n])
		recruits += n
	t.ok(recruits > 40, "six wanderers recruit on most days (%d of 120)" % recruits)
	# the flag resets with the next day
	var r2 := _run(5)
	r2.recruited_today = true
	r2.last_enemies = r2.enemies_for(1).map(func(x): return x.to_dict())
	r2.progress_day([])
	t.ok(not r2.recruited_today, "a new day: recruiting is open again")


## Every outcome checked against its report, over seeded wanders: the extra
## stat point, finds, immunities, the buff, a recruit; the consolation; a card with
## two or more successes.
func test_wander_outcomes(t) -> void:
	var multi := 0
	var consolation := 0
	var found_jackpot := false
	for s in 400:
		var r := _run(1000 + s)
		var e := r.enemies_for(1)
		r.last_enemies = e.map(func(x): return x.to_dict())
		var u: BWUnit = r.squad[0]
		var xp := _stat_total(u)
		var sq := r.squad.size()
		var rep := r.downtime(u, "wander")
		var succ: Array = rep.successes
		if rep.jackpot:
			found_jackpot = true
			continue
		var want := (1 if "stat" in succ else 0) + (1 if succ.is_empty() else 0)
		var gained := _stat_total(u) - xp
		t.eq(gained, want, "seed %d: stat points %s" % [s, succ])
		t.eq(r.squad.size() - sq, 1 if "recruit" in succ else 0, "seed %d: recruit" % s)
		t.eq(u.next_immune.size(), 1 if "status_immunity" in succ else 0, "seed %d: status immunity for the next fight" % s)
		t.eq(u.next_brace.size(), 1 if "element_brace" in succ else 0, "seed %d: braced for the next fight" % s)
		t.eq(u.fight_buff.size(), 1 if "stat_buff" in succ else 0, "seed %d: buff" % s)
		if "stat_buff" in succ:
			t.eq(int(u.fight_buff.values()[0]), 10, "seed %d: +10" % s)
		var tiers := [r.tier_for(r.fight), BWRun.TIERS[mini(BWRun.tier_index(r.fight) + 1, 4)]]
		var w: Array = rep.items.filter(func(it): return it.slot == "main_hand")
		var a: Array = rep.items.filter(func(it): return it.slot != "main_hand")
		t.eq(w.size(), 1 if "find_weapon" in succ else 0, "seed %d: weapon find" % s)
		t.eq(a.size(), 1 if "find_armour" in succ else 0, "seed %d: armour find" % s)
		t.ok(rep.items.all(func(it): return it.tier in tiers), "seed %d: finds at this tier or one up" % s)
		t.eq(rep.lines.size(), succ.size(), "seed %d: one line per success" % s)
		if succ.size() >= 2:
			multi += 1
		if succ.is_empty():
			consolation += 1
			t.ok(str(rep.headline).contains("Nothing happened") and str(rep.headline).contains("(+1 "), rep.headline)
	t.ok(multi > 0, "some wanders land two or more (%d)" % multi)
	t.ok(consolation > 0, "some land nothing (%d)" % consolation)
	t.ok(true, "a jackpot in these seeds: %s" % found_jackpot)


## D177: the jackpot rerolls the nine at 30% each (no +5000 XP, no rogue);
## a reroll that misses everything too gives the consolation (+1 to a stat).
func test_wander_jackpot(t) -> void:
	var r := _run()
	var e := r.enemies_for(1).map(func(x): return x.to_dict())
	var six := r.squad.duplicate()
	var row := BWData.row("roster", _ids()[0])
	var jack := 0
	var hits := 0
	var empty := 0
	var recruits := 0
	for s in 30000:
		r.rng.seed = s
		r.squad = six.duplicate()
		r.last_enemies = e.duplicate(true)
		r.recruited_today = false
		var u := BWUnit.from_roster(row)
		var xp := _stat_total(u)
		var rep := r.downtime(u, "wander")
		if not rep.jackpot:
			continue
		jack += 1
		t.ok(str(rep.headline).begins_with("I wandered and ran into a being of unlimited benevolence"), rep.headline)
		t.ok(not "rogue" in u.to_dict(), "seed %d: no rogue" % s)
		t.eq(u.level, 1, "seed %d: no levels from wandering" % s)
		var succ: Array = rep.successes
		hits += succ.size()
		if "recruit" in succ:
			recruits += 1
		var want := (1 if "stat" in succ else 0) + (1 if succ.is_empty() else 0)
		t.eq(_stat_total(u) - xp, want, "seed %d: stat points for %s" % [s, succ])
		t.eq(rep.lines.size(), succ.size(), "seed %d: a line per rerolled gain" % s)
		if succ.is_empty():
			empty += 1
			t.ok(str(rep.headline).contains("(+1 "), "seed %d: the reroll missed too: +1 to a stat" % s)
	t.ok(jack >= 120, "jackpots in 30000 wanders: %d (about 0.67 percent)" % jack)
	t.near(float(hits) / maxf(jack * 9, 1), 0.30, 0.05, "rerolled effects land about 30 percent (%d of %d)" % [hits, jack * 9])
	t.ok(recruits > 0, "the reroll can recruit (%d)" % recruits)
	t.ok(true, "rerolls that missed everything: %d" % empty)
	# the reroll still honours one recruit a day
	var r2 := _run()
	r2.last_enemies = e.duplicate(true)
	r2.recruited_today = true
	var before := r2.squad.size()
	for s in 20000:
		r2.rng.seed = s
		var rep2 := r2.downtime(BWUnit.from_roster(row), "wander")
		if rep2.jackpot:
			t.ok(not "recruit" in rep2.successes, "seed %d: no second recruit today" % s)
	t.eq(r2.squad.size(), before, "nobody joined after today's recruit")


# ------------------------------------------------------------------ battle: immunity, buff

func test_element_brace(t) -> void:
	# set before the battle, it lasts that battle only
	var me := _u("me", "staff", "fire", { "dex": 200 })
	var foe := _u("f", "axe", "water", { "con": 50 })
	foe.next_brace = ["fire"]
	var b := _fight(me, [foe], [Vector2i(6, 4)])
	t.eq(foe.braced, ["fire"], "braced this battle")
	t.ok(foe.next_brace.is_empty(), "spent at the battle's start")
	var plain := _u("p", "axe", "water", { "con": 50 })
	var b0 := _fight(_u("me", "staff", "fire", { "dex": 200 }), [plain], [Vector2i(6, 4)])
	var full := float(b0.forecast_basic(b0.units[0], plain).damage.value)
	var fc := b.forecast_basic(me, foe)
	t.near(float(fc.damage.value), maxf(1.0, roundf(full * 0.25)), 1.0, "a fire blow: -75%% (%s vs %s)" % [fc.damage.value, full])
	t.ok(fc.mods.any(func(m): return str(m.label).begins_with("Braced against fire")), "named in the forecast")
	t.ok(float(b.forecast_basic(me, foe).damage.value) < full, "less than an unbraced unit takes")
	# statuses of the element don't apply; others do
	b.add_status(foe, "scorched", me)
	t.ok(not foe.statuses.has("scorched"), "no Scorched while braced against fire")
	t.ok(_events(b, "status_resisted").any(func(e): return e.unit == "f" and e.reason == "Braced"), "resisted: Braced")
	b.add_status(foe, "drenched", me)
	t.ok(foe.statuses.has("drenched"), "water still drenches it")
	# its ground
	var g_full := b._tile_dmg(plain, 40.0, "fire")
	var g := b._tile_dmg(foe, 40.0, "fire")
	t.ok(g < g_full and g > 0, "fire ground: a quarter (%d vs %d)" % [g, g_full])
	t.eq(b._tile_dmg(foe, 40.0, "dark"), b._tile_dmg(plain, 40.0, "dark"), "dark ground in full")
	# detonations and chain arcs (thunder)
	var me2 := _u("me", "staff", "thunder")
	var brc := _u("brc", "axe", "water", { "con": 300 })
	var plain2 := _u("plain", "axe", "water", { "con": 300 })
	brc.next_brace = ["thunder"]
	var X := Vector2i(7, 4)
	var b2 := _fight(me2, [brc, plain2], [Vector2i(8, 4), Vector2i(6, 4)])
	b2.tiles.apply([X], "fire", "x")
	b2.paint([X], "thunder", me2)
	var td_b: Array = _events(b2, "tile_damage").filter(func(e): return e.unit == "brc")
	var td_p: Array = _events(b2, "tile_damage").filter(func(e): return e.unit == "plain")
	t.ok(td_b.size() == 1 and td_p.size() == 1 and int(td_b[0].amount) < int(td_p[0].amount),
		"detonation splash: the braced neighbour takes less (%s vs %s)" % [td_b.map(func(e): return e.amount), td_p.map(func(e): return e.amount)])
	var arcs := []
	for braced in [false, true]:
		var me3 := _u("me", "sword", "fire", { "dex": 200, "str": 40 })
		var tgt := _u("t", "axe", "water", { "con": 300 })
		var mate := _u("m", "axe", "water", { "con": 300 })
		if braced:
			mate.next_brace = ["thunder"]
		var b3 := _fight(me3, [tgt, mate], [E, Vector2i(8, 4)], 5)
		b3.tiles.apply([E], "thunder", "x")
		b3.attack(me3, tgt)
		var ch := _events(b3, "chain")
		arcs.append(int(ch[0].amount) if not ch.is_empty() else -1)
	t.ok(arcs[0] > 0 and arcs[1] > 0 and arcs[1] < arcs[0], "a chain arc onto the braced: less (%s)" % [arcs])
	# the battle after: gone
	var b4 := _fight(me, [foe], [Vector2i(6, 4)])
	t.ok(foe.braced.is_empty() and not foe.braced_against("fire"), "the next battle: no brace")
	t.ok(not b4.forecast_basic(me, foe).mods.any(func(m): return str(m.label).begins_with("Braced")), "full damage again")


func test_status_immunity(t) -> void:
	var me := _u("me", "sword", "fire")
	var foe := _u("f", "axe", "water")
	foe.next_immune = ["pinned"]
	var b := _fight(me, [foe], [E])
	t.ok(foe.next_immune.is_empty() and foe.immune_statuses == ["pinned"], "moved into this battle at its start")
	b.add_status(foe, "pinned", me)
	t.ok(not foe.statuses.has("pinned"), "immune to Pinned")
	t.ok(_events(b, "status_resisted").any(func(e): return e.status == "pinned" and e.reason == "Immune"), "shown as resisted")
	b.add_status(foe, "staggered", me)
	t.ok(foe.statuses.has("staggered"), "other statuses still land")
	var b2 := _fight(me, [foe], [E])
	b2.add_status(foe, "pinned", me)
	t.ok(foe.statuses.has("pinned"), "the battle after: Pinned lands again")
	t.eq(BWRun.IMMUNE_STATUSES, ["staggered", "blinded", "pinned", "drenched", "scorched", "shrouded"], "the six Wander can grant")


func test_next_battle_buff_expires(t) -> void:
	var u := _u("u", "sword", "fire")
	var base := u.stat("str")
	u.fight_buff = { "str": 10 }
	var b := BWBattle.new(_board(), 1)
	b.setup([u], [_u("f", "axe", "water")])
	t.eq(u.stat("str"), base + 10, "+10 STR in the next battle")
	t.ok(u.fight_buff.is_empty(), "spent at its start")
	var b2 := BWBattle.new(_board(), 2)
	b2.setup([u], [_u("f2", "axe", "water")])
	t.eq(u.stat("str"), base, "gone the battle after")


## D177: no rogue. BWAI plays enemies (and everyone under autoplay), never
## a player unit; a save that still carries the old flag loads without it.
func test_no_rogue(t) -> void:
	var me := _u("me", "sword", "fire", { "con": 60 })
	var foe := _u("f", "axe", "water", { "con": 20 })
	foe.team = "enemy"
	t.ok(BWAI.controls(foe) and not BWAI.controls(me), "BWAI plays the enemy, not you")
	t.ok(BWAI.controls(me, true), "autoplay plays everyone")
	var r := _run()
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	t.ok(not d.squad[0].has("rogue"), "saves no longer write it")
	d.squad[0]["rogue"] = true                       # a save from before D177
	var v: BWUnit = BWRun.from_dict(d).squad[0]
	t.ok(not BWAI.controls(v) and not "rogue" in v.to_dict(), "an old rogue loads as an ordinary unit")


# ------------------------------------------------------------------ weapon class, picks, save

func test_weapon_class_switching(t) -> void:
	var r := _run()
	var u: BWUnit = r.squad[0]
	var own := u.weapon_class
	var other: String = BWRun.weapon_classes().filter(func(c): return c != own and c != "fists")[0]
	var model: String = BWData.table("equipment").filter(func(x): return x.slot == "main_hand" and x.weight == other)[0].id
	var w := r.make_item(model, "E")
	r.inventory.append(w)
	t.ok(r.equip(u, w), "a tier-E %s needs only E" % other)
	t.eq(u.weapon_class, other, "the class follows the main hand")
	t.eq(u.loadout(other), BWSkillRegistry.starter(other), "its skills are the %s's" % other)
	var b := BWBattle.new(_board(), 3)
	b.setup([u], [_u("f", "axe", "water")])
	var keys: Array = b.skills_for(u).map(func(s): return str(s.key))
	t.ok(BWSkillRegistry.starter(other).all(func(k): return k in keys), "the battle offers the %s kit: %s" % [other, keys])
	var e_old := int(u.expertise.get(own, 0))
	var e_new := int(u.expertise.get(other, 0))
	BWProgression.award(u, false, "")
	t.ok(int(u.expertise.get(other, 0)) == e_new + 1 and int(u.expertise.get(own, 0)) == e_old, "expertise grows in the class held")
	var d := r.to_dict()
	d.squad[0].weapon_class = own                     # a stale field: the main hand wins
	var r2 := BWRun.from_dict(JSON.parse_string(JSON.stringify(d)))
	t.eq(r2.squad[0].weapon_class, other, "a load re-reads the class from the main hand")
	var big := r.make_item(model, "C")
	r.inventory.append(big)
	t.ok(r.equip(u, big), "D180: a C %s needs no expertise any more" % other)


func test_save_v4(t) -> void:
	var r := _run()
	var u: BWUnit = r.squad[0]
	u.next_immune = ["pinned"]
	u.next_brace = ["fire"]
	u.fight_buff = { "dex": 10 }
	u.focus_element = "ice"
	u.bonus_perks = { u.element: 1 }
	u.bonus_skills = { u.weapon_class: 1 }
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	t.eq(int(d.version), BWRun.SAVE_VERSION, "save version current (4 added these, D132)")
	var v: BWUnit = BWRun.from_dict(d).squad[0]
	t.ok(v.next_immune == ["pinned"] and v.next_brace == ["fire"], "immunity and brace survive")
	t.eq(v.focus_element, "ice", "the focus element survives")
	t.eq(v.fight_buff, { "dex": 10 }, "the buff survives (ints)")
	t.eq(v.bonus_perks, { u.element: 1 }, "free perk picks survive")
	t.eq(v.bonus_skills, { u.weapon_class: 1 }, "free skill picks survive")
	# a v3 save: defaults
	var old: Dictionary = JSON.parse_string(JSON.stringify(_run().to_dict()))
	old.version = 3
	for ud in old.squad:
		for k in ["rogue", "next_immune", "next_brace", "fight_buff", "bonus_perks", "bonus_skills", "focus_element"]:
			ud.erase(k)
	var m := BWRun.from_dict(old)
	t.ok(m.squad.all(func(x): return x.next_immune.is_empty() and x.next_brace.is_empty() and x.focus_element == "" \
		and x.fight_buff.is_empty() and x.bonus_perks.is_empty() and x.bonus_skills.is_empty()), "a v3 save loads with defaults")
	t.eq(m.pending_picks(), [], "and owes nothing")


func test_focus_element(t) -> void:
	var r := _run(3)
	var u: BWUnit = r.squad[0]
	t.eq(u.focus(), u.element, "the focus defaults to the native element")
	t.eq(u.focus_options(), [u.element], "only elements with affinity are offered")
	var other: String = BWFormulas.ELEMENTS.filter(func(e): return e != u.element)[0]
	u.focus_element = other
	t.eq(u.focus(), u.element, "a focus with no affinity falls back to native")
	u.affinity[other] = 10
	t.ok(other in u.focus_options(), "%s offered once it has affinity" % other)
	t.eq(u.focus(), other, "now %s is the focus" % other)
	var native := int(u.affinity[u.element])
	for s in 30:
		r.rng.seed = 700 + s
		var before := int(u.affinity[other])
		var rep := r.downtime(u, "specialize")
		t.eq(int(u.affinity[other]) - before, 5, "seed %d: Specialize trains the focus" % s)
		var a: Array = rep.items.filter(func(it): return it.slot != "main_hand")
		t.ok(a.all(func(it): return BWRun.item_element(it) == other), "seed %d: armour attuned to the focus" % s)
		BWPicks.auto_resolve(u)
	t.eq(int(u.affinity[u.element]), native, "the native element untouched")


## D417 (author: "Reduce max elements attuned to 3"): no 4th element from any
## source: battle awards, Branch out's cards, Wander's element; a save holding
## more keeps the top 3 and moves half of the rest's points to the focus.
func test_element_cap(t) -> void:
	t.eq(BWUnit.MAX_ELEMENTS, 3, "the cap is 3")
	var r := _run(77)
	var u: BWUnit = r.squad[0]
	var others: Array = BWFormulas.ELEMENTS.filter(func(e): return e != u.element)
	u.affinity[others[0]] = 10
	u.affinity[others[1]] = 4                      # rank 0, but attuned: it counts
	t.eq(u.attuned_elements().size(), 3, "native + two others = 3")
	t.ok(not u.can_attune(others[2]) and u.can_attune(others[1]), "a 4th can't attune; an owned one can")
	BWProgression.award(u, true, str(others[2]))
	t.eq(int(u.affinity.get(others[2], 0)), 0, "a knockout with a 4th element grows nothing in it")
	BWProgression.award(u, true, str(others[1]))
	t.eq(int(u.affinity[others[1]]), 7, "an owned element still grows")
	# Branch out: class-only cards at the cap
	r.day = 3
	for o in r.branch_options(u):
		t.ok(str(o.element) == "" or str(o.element) in u.attuned_elements(), "no 4th element on a Branch out card: %s" % o)
	# Wander's element: owned elements only
	for s in 30:
		var r2 := _run(900 + s)
		var w: BWUnit = r2.squad[1]
		var oth: Array = BWFormulas.ELEMENTS.filter(func(e): return e != w.element)
		w.affinity[oth[0]] = 10
		w.affinity[oth[1]] = 10
		var rep := { "lines": [], "items": [], "successes": [] }
		if r2._wander_effect(w, "element", rep):
			t.ok(w.attuned_elements().size() == 3, "seed %d: Wander teaches an owned element (%s)" % [s, w.affinity])
	# save migration: 5 elements -> the top 3, half the rest to the focus
	var m := _run(5)
	var v: BWUnit = m.squad[0]
	var oo: Array = BWFormulas.ELEMENTS.filter(func(e): return e != v.element)
	v.affinity = { v.element: 12, oo[0]: 40, oo[1]: 25, oo[2]: 9, oo[3]: 6 }
	v.focus_element = str(oo[0])
	var d: Dictionary = JSON.parse_string(JSON.stringify(m.to_dict()))
	var back: BWUnit = BWRun.from_dict(d).squad[0]
	t.eq(back.attuned_elements().size(), 3, "a loaded save holds 3 elements: %s" % back.affinity)
	t.ok(back.affinity.has(back.element) and back.affinity.has(oo[0]) and back.affinity.has(oo[1]), "native and the two highest kept")
	t.eq(int(back.affinity[oo[0]]), 40 + 4 + 3, "half of the dropped 9 and 6 (4 + 3) went to the focus")
	t.ok(not back.affinity.has(oo[2]) and not back.affinity.has(oo[3]), "the rest dropped")
	# the native element is kept even when it's 4th by points
	var n := BWUnit.from_roster({ "id": "x", "element": "fire", "weapon_class": "sword" })
	n.affinity = { "fire": 5, "ice": 30, "dark": 20, "light": 10 }
	var res := n.enforce_element_cap()
	t.eq(res.dropped, ["light"], "the native stays, the lowest other drops")
	t.eq(int(n.affinity.fire), 10, "and half of light's 10 goes to the native (no focus)")
	# enemies and the roster roll hold one element
	for e in r.enemies_for(3):
		t.ok(e.attuned_elements().size() <= 3, "enemy within the cap")
