extends RefCounted
## D233-D237, the author's first playtest notes: the first perk is drawn at
## random (no picker), the discard pile, inventory sorting, free scrolls (in
## test_enchant_v2), and no cutscene for ground actions that hurt nobody.


func _ids() -> Array:
	return BWData.table("roster").slice(0, 6).map(func(x): return str(x.id))


# ---------------------------------------------------------------- D233

func test_first_perk_is_drawn(t) -> void:
	var r := BWRun.start(_ids(), 7)
	t.eq(r.pending_picks(), [], "nothing owed at run start: no picker")
	for u in r.squad:
		var own := BWPicks.owned(u, u.element)
		t.eq(own.size(), 1, "%s has one %s perk" % [u.name, u.element])
		t.eq(u.perks.size(), 1, "%s: and only that one" % u.name)
		t.eq(BWRun.first_perk(u), str(own[0]), "first_perk reads it back")
	var r2 := BWRun.start(_ids(), 7)
	t.eq(r2.squad.map(func(u): return u.perks), r.squad.map(func(u): return u.perks), "same seed, same perks")
	t.eq(r2.inventory.map(func(it): return str(it.base)), r.inventory.map(func(it): return str(it.base)), "the run's own rolls don't move")
	# across seeds the draw covers the element, not just the first two cards
	var seen := {}
	for s in 40:
		var rs := BWRun.start(_ids().slice(0, 1), 100 + s)
		seen[str(rs.squad[0].perks[0])] = true
	t.ok(seen.size() >= 4, "40 seeds draw at least 4 different perks (%d)" % seen.size())
	# the save keeps it; a second call never adds another
	var r3 := BWRun.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.eq(r3.squad.map(func(u): return u.perks), r.squad.map(func(u): return u.perks), "saved and loaded")
	t.eq(r.auto_first_perk(r.squad[0]), "", "only the first perk is drawn")


func test_later_picks_keep_two_cards(t) -> void:
	var r := BWRun.start(_ids(), 3)
	var u: BWUnit = r.squad[0]
	u.affinity[u.element] = 2 * BWUnit.POINTS_PER_RANK
	var req := { "kind": "perk", "element": u.element }
	t.eq(BWPicks.pending(u), [req], "rank 2 owes a pick")
	t.eq(BWPicks.options(u, req).size(), 2, "with two cards")


# ---------------------------------------------------------------- D234

func test_trash_pile(t) -> void:
	var r := BWRun.start(_ids(), 5)
	var it: Dictionary = r.inventory[0]
	var n := r.inventory.size()
	t.ok(r.trash_item(it), "a loose item goes on the pile")
	t.ok(not it in r.inventory and it in r.trash, "out of the inventory")
	t.eq(r.inventory.size(), n - 1, "one fewer loose")
	t.ok(not r.trade(it, r.shop[0]), "the shop can't take a discarded item")
	t.ok(not r.trash_item(r.squad[0].equipment.main_hand), "only loose items")
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	var r2 := BWRun.from_dict(d)
	t.eq(r2.trash.size(), 1, "the pile is saved")
	t.ok(r.untrash_item(it), "and recoverable")
	t.ok(it in r.inventory and r.trash.is_empty(), "back in the inventory")
	r.trash_item(it)
	r.trash_item(r.inventory[0])
	t.eq(r.empty_trash(), 2, "the battle starts: two thrown away")
	t.ok(r.trash.is_empty() and not it in r.inventory, "gone for good")
	d.erase("trash")
	t.eq(BWRun.from_dict(d).trash, [], "an older save has no pile")


# ---------------------------------------------------------------- D235

func test_inventory_sort(t) -> void:
	var r := BWRun.start(_ids(), 5)
	var plain := r.make_item("vest", "A", "")
	var fire := r.make_item("chaps", "E", "")
	fire["imbue"] = "fire"                        # item_element reads the imbue first
	var ice := r.make_item("crown", "C", "")
	ice["imbue"] = "ice"
	var water := r.make_item("sword", "B", "")
	water["imbue"] = "water"
	var items := [plain, ice, water, fire]
	var by_el := BWInvSort.sorted(items, "element")
	t.eq(by_el.map(func(x): return BWRun.item_element(x)), ["fire", "water", "ice", ""], "element order, plain last")
	var by_slot := BWInvSort.sorted(items, "slot")
	t.eq(by_slot.map(func(x): return str(x.slot)), ["head", "chest", "legs", "main_hand"], "head, chest, legs, weapons")
	var by_tier := BWInvSort.sorted(items, "tier")
	t.eq(by_tier.map(func(x): return str(x.tier)), ["A", "B", "C", "E"], "best tier first")
	var newest := BWInvSort.sorted(items, "newest")
	t.eq(newest[0], water, "the latest item first")
	t.eq(items[0], plain, "the source array is untouched")
	var was := BWInvSort.mode
	BWInvSort.set_mode("tier")
	t.eq(BWInvSort.sorted(items)[0], plain, "the session's mode is the default")
	BWInvSort.set_mode("nonsense")
	t.eq(BWInvSort.mode, "tier", "unknown modes are ignored")
	BWInvSort.set_mode(was)


# ---------------------------------------------------------------- D237

func _row(targeting: String, cd: int = 2, power: int = 10, once: bool = false) -> Dictionary:
	return { "key": "g", "targeting": targeting, "cd": cd, "power": power, "once_per_battle": once }


func _sk(row: Dictionary, results: Array = []) -> Dictionary:
	return { "type": "skill", "skill": "g", "results": results, "ko": false }


func _hit(dmg: int = 10, hit: bool = true, crit: bool = false) -> Dictionary:
	return { "target": "x", "result": { "hit": hit, "crit": crit, "damage": dmg }, "ko": false }


func test_ground_actions_play_in_place(t) -> void:
	var M := BWCutsceneTier.MINIMAL
	var S := BWCutsceneTier.SHORT
	var F := BWCutsceneTier.FULL
	var hex := _row("hex")
	var big := _row("hex", 4, 20, true)           # a once-per-battle area (Tempest-like)
	var unit := _row("unit")
	var tc := BWCutsceneTier.tier_for(_sk(hex), "default", hex)
	t.eq(int(tc.tier), M, "a paint on empty ground: in place")
	t.ok(bool(tc.ground) and not bool(tc.callout), "flagged ground, no callout")
	t.eq(int(BWCutsceneTier.tier_for(_sk(big), "default", big).tier), M, "even a once-per-battle area that hits nobody")
	t.eq(int(BWCutsceneTier.tier_for(_sk(_row("dir")), "default", _row("dir")).tier), M, "a direction at nobody (Ley Line)")
	t.eq(int(BWCutsceneTier.tier_for(_sk(hex, [_hit(0, false)]), "default", hex).tier), M, "a miss hurts nobody")
	# damage brings the tier rules back
	t.eq(int(BWCutsceneTier.tier_for(_sk(hex, [_hit()]), "default", hex).tier), S, "a direct hit: short as before")
	t.eq(int(BWCutsceneTier.tier_for(_sk(big, [_hit()]), "default", big).tier), F, "a once-per-battle hit: full as before")
	t.eq(int(BWCutsceneTier.tier_for(_sk(hex, [_hit(10, true, true)]), "default", hex).tier), F, "a crit: full")
	var det := [{ "type": "paint" }, { "type": "detonate", "hex": Vector2i(1, 1) },
		{ "type": "tile_damage", "unit": "x", "amount": 12, "cause": "detonation" }, { "type": "growth" }]
	t.eq(int(BWCutsceneTier.tier_for(_sk(hex), "default", hex, det).tier), S, "a detonation that hurts: the tier applies")
	var arc := [{ "type": "chain", "from": "a", "to": "b", "amount": 6 }, { "type": "growth" }]
	t.eq(int(BWCutsceneTier.tier_for(_sk(hex), "default", hex, arc).tier), S, "a chain arc that hurts: the tier applies")
	var later := [{ "type": "growth" }, { "type": "tile_damage", "unit": "x", "amount": 9, "cause": "detonation" }]
	t.eq(int(BWCutsceneTier.tier_for(_sk(hex), "default", hex, later).tier), M, "damage after the action's end doesn't count")
	var pulse := [{ "type": "tile_damage", "unit": "x", "amount": 9, "cause": "pulse" }]
	t.eq(int(BWCutsceneTier.tier_for(_sk(hex), "default", hex, pulse).tier), M, "an obelisk pulse isn't the action's")
	# aimed at a unit: unchanged
	t.eq(int(BWCutsceneTier.tier_for(_sk(unit, [_hit()]), "default", unit).tier), S, "a unit-targeted skill keeps its tier")
	t.ok(not bool(BWCutsceneTier.tier_for(_sk(unit), "default", unit).ground), "and is never ground")
	# the blast's slow beat
	t.ok(BWCutsceneTier.blast_hurts(det.slice(2)), "the blast hurts: slow beat")
	t.ok(not BWCutsceneTier.blast_hurts([{ "type": "growth" }]), "a blast on nobody: no beat")
	# the real rows: Saturate, Ley Line, Transfer, Inversion are ground skills
	for k in ["saturate", "ley_line", "transfer", "inversion", "surge", "tempest"]:
		if BWSkills.has_skill(k):
			var e := { "type": "skill", "skill": k, "results": [], "ko": false }
			t.eq(int(BWCutsceneTier.tier_for(e).tier), M, "%s on nobody plays in place" % k)
