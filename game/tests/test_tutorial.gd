extends RefCounted
## D223-D226: the tutorial's scripted fight, played on the rules alone with
## the live tutorial's own actions, staging and turn passing
## (BWTutorialScript.dry_run). Every lesson must show what its prompt says.


func test_tutorial_script_plays_every_lesson(t) -> void:
	var r := BWTutorialScript.dry_run()
	var b: BWBattle = r.battle
	var h: Array = b.history
	var has := func(pred: Callable) -> bool: return h.any(pred)
	t.ok(has.call(func(e): return e.type == "undo_move"), "1: the move is undone")
	var first: Array = h.filter(func(e): return e.type == "attack")
	t.ok(not first.is_empty() and first[0].unit == "della" and first[0].result.hit, "2: Della's first blow lands")
	t.ok(has.call(func(e): return e.type == "paint" and e.element == "fire" and BWTutorialScript.F_HEX in e.hexes), "4: fire on the marked hex")
	t.ok(has.call(func(e): return e.type == "detonate" and e.hex == BWTutorialScript.C0), "5: the fuse detonates")
	t.ok(has.call(func(e): return e.type == "tile_damage" and e.unit == "della" and e.cause == "detonation"), "5: Della is in the splash (the red tag)")
	t.ok(has.call(func(e): return e.type == "attack" and "Shatter" in e.get("tags", [])), "5: Shatter on the glazed tile")
	t.ok(has.call(func(e): return e.type == "skill" and e.skill == "bolt" and e.results.any(func(x): return "Spark" in x.get("tags", []))), "5: Spark")
	t.ok(has.call(func(e): return e.type == "chain" and e.from == "rui"), "5: the arc from conductive Rui")
	t.ok(has.call(func(e): return e.type == "swap" and e.weapon_class == "bow"), "6: the swap draws the bow (D419: pistols benched)")
	t.ok(has.call(func(e): return e.type == "status" and e.status == "pinned" and e.unit == "burt"), "7: Burt Pinned")
	t.ok(has.call(func(e): return e.type == "status" and e.status == "pinned" and e.unit == "rui"), "7: Rui Pinned")
	t.ok(has.call(func(e): return e.type == "attack" and "Rear" in e.get("tags", [])), "8: a rear attack")
	t.ok(b.over and b.winner == "player", "9: the Surge wins it")
	# D468: the squad shows the rules as they are now: 3 elements at most (D417)
	for u in r.run.squad:
		t.ok(u.attuned_elements().size() <= BWUnit.MAX_ELEMENTS, "%s holds %d elements, the cap is %d" % [u.id, u.attuned_elements().size(), BWUnit.MAX_ELEMENTS])
	# D468: the board-painting core and the new rules are named on the way
	var said := " ".join(BWTutorialScript.steps().map(func(s): return str(s.text)))
	for w in ["paint", "cash it in", "ignites", "Unsteady", "Shatter", "keystone", "title"]:
		t.ok(said.contains(w), "a step says \"%s\"" % w)
	t.ok(not has.call(func(e): return e.type == "tile_damage" and e.unit == "della" and e.cause == "fire_cross"), "8: the way behind Burt doesn't cross fire")


## The run is the tutorial's own: the summary levels every unit once and
## the two picks have two cards each.
func test_tutorial_after_the_fight(t) -> void:
	var r := BWTutorialScript.dry_run()
	var run: BWRun = r.run
	var b: BWBattle = r.battle
	var enemies: Array = b.units.filter(func(x): return x.team == "enemy")
	var rep := run.after_fight(true, run.squad, enemies, enemies, b.history)
	t.eq(rep.levels.size(), 3, "a level for each of the three")
	t.ok(run.squad.all(func(u): return u.level == 2), "one level per fight")
	var della := run.unit("della")
	t.eq(BWPicks.options(della, { "kind": "perk", "element": "fire" }).size(), 2, "the perk pick shows two cards")
	della.bonus_skills["sword"] = 1
	t.eq(BWPicks.options(della, { "kind": "skill", "weapon": "sword" }).size(), 2, "the skill pick shows two cards")


## Every step is short (two sentences at most) and names a lesson in order.
func test_tutorial_prompts(t) -> void:
	var last := 0
	for s in BWTutorialScript.steps():
		var text := str(s.text)
		var sentences := text.split(". ", false).size()
		t.ok(sentences <= 2 and text.length() <= 150, "%s: short (%d sentences, %d chars)" % [s.id, sentences, text.length()])
		t.ok(int(s.lesson) >= last, "%s: lessons in order" % s.id)
		last = int(s.lesson)
	t.eq(last, BWTutorialScript.LESSONS.size() - 1, "the closing card is the last lesson")
