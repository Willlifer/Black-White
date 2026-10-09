extends RefCounted
## D510-D520: the alternate clips (BWClipRoute.pick, BWAnimAlt), the
## dagger backstab's route, and the spear set's shield arm.

const N := 9
const C := Vector2i(4, 4)


func _has(set_id: String, cls: String = "") -> Callable:
	var acts := BWAnimClips.actions_for(set_id, cls)
	var lib := BWAnimClips.load_set(set_id)
	return func(p: String) -> bool: return acts.has(p) and lib.has_animation(StringName(str(acts[p].clip)))


func _counts(set_id: String, cls: String, base: String, n: int, ctx: Dictionary = {}) -> Dictionary:
	var out := {}
	var has := _has(set_id, "axe" if cls == "axe" else "")
	for i in n:
		var c := ctx.duplicate()
		c["salt"] = "u%d|t|%d|true|false|%d|0" % [i % 7, i, 30 - i % 30]
		var p := BWClipRoute.pick(set_id, cls, base, has, c)
		out[p] = int(out.get(p, 0)) + 1
	return out


func test_pick_is_deterministic(t) -> void:
	var has := _has("heavy", "axe")
	var ok := true
	for i in 200:
		var ctx := { "salt": "blow%d" % i, "melee": true }
		if BWClipRoute.pick("heavy", "axe", "", has, ctx) != BWClipRoute.pick("heavy", "axe", "", has, ctx.duplicate()):
			ok = false
	t.ok(ok, "the same blow always picks the same clip")
	var r := { "target": "b", "result": { "damage": 7, "hit": true, "crit": false }, "target_hp": 12 }
	t.eq(BWClipRoute.salt_of("a", r), BWClipRoute.salt_of("a", r.duplicate(true)), "a blow's salt is its content")
	t.ok(BWClipRoute.salt_of("a", r) != BWClipRoute.salt_of("a", { "target": "b", "result": { "damage": 8, "hit": true }, "target_hp": 11 }),
		"another blow, another salt")
	# the battle's RNG is never touched (view only)
	var rng_state := BWBattle.new(BWBoard.from_dict({ "name": "x", "cols": 2, "rows": 1, "cells": [{ "q": 0, "r": 0 }, { "q": 1, "r": 0 }],
		"spawns": { "player": [[0, 0]], "enemy": [[1, 0]] } }), 3).rng.state
	BWClipRoute.pick("pair", "daggers", "", _has("pair"), { "salt": "x" })
	t.eq(BWBattle.new(BWBoard.from_dict({ "name": "x", "cols": 2, "rows": 1, "cells": [{ "q": 0, "r": 0 }, { "q": 1, "r": 0 }],
		"spawns": { "player": [[0, 0]], "enemy": [[1, 0]] } }), 3).rng.state, rng_state, "a seeded battle rolls the same after a pick")


func test_weights(t) -> void:
	var n := 3000
	# the axes: chop 1, sweep 1, smash 0.75, flip 0.25 (of 3)
	var ax := _counts("heavy", "axe", "", n)
	t.near(float(ax.get("", 0)) / n, 1.0 / 3.0, 0.05, "heavy axe: the chop a third of the time (%s)" % str(ax))
	t.near(float(ax.get("sweep_under", 0)) / n, 1.0 / 3.0, 0.05, "the underhand sweep a third")
	t.near(float(ax.get("smash", 0)) / n, 0.25, 0.05, "the smash a quarter")
	t.near(float(ax.get("smash_flip", 0)) / n, 1.0 / 12.0, 0.03, "the flip a quarter of the smashes")
	var sw := _counts("heavy", "sword", "", n)
	t.near(float(sw.get("smash_flip", 0)) / maxf(float(sw.get("smash", 0) + sw.get("smash_flip", 0)), 1.0), 0.25, 0.06,
		"flamberge: the flip ~25%% vs ~75%% plain (%s)" % str(sw))
	var ln := _counts("spear", "lance", "", n)
	t.near(float(ln.get("lunge", 0)) / n, 0.5, 0.05, "every lance stab lunges ~half the time (%s)" % str(ln))
	var bw := _counts("bow", "bow", "", n, { "melee": false })
	t.near(float(bw.get("shot_jump", 0)) / n, 0.5, 0.05, "bow: the jump shot ~half (%s)" % str(bw))
	var dg := _counts("pair", "daggers", "", n)
	t.near(float(dg.get("flourish", 0)) / n, 0.5, 0.05, "daggers: the flourish ~half (%s)" % str(dg))
	var th := _counts("one", "sword", "thrust", n)
	t.near(float(th.get("thrust", 0)) / n, 1.0 / 3.0, 0.05, "a sword's thrust skill: the thrust, the 2h thrust, the lunge, a third each (%s)" % str(th))
	t.ok(th.has("thrust_2h") and th.has("lunge"), "both thrust alternates play")
	# the weights are data: every pose in the table exists where it is routed
	var bad: PackedStringArray = []
	for k in BWClipRoute.ALTERNATES:
		var parts := str(k).split("|")
		var has := _has(parts[0], "axe" if parts[1] == "axe" else "")
		for p in BWClipRoute.ALTERNATES[k]:
			if str(p) != "" and str(p) != parts[2] and not bool(has.call(str(p))):
				bad.append("%s: %s" % [k, p])
	t.ok(bad.is_empty(), "every alternate in the table is a clip of its set (%s)" % ", ".join(bad))


func test_crit_flips_and_fit_rules(t) -> void:
	var ok := true
	for i in 100:
		for k in [["heavy", "axe"], ["heavy", "sword"], ["one", "axe"], ["polearm", "lance"]]:
			if BWClipRoute.pick(k[0], k[1], "", _has(k[0], "axe" if k[1] == "axe" else ""), { "salt": "c%d" % i, "crit": true }) != "smash_flip":
				ok = false
	t.ok(ok, "a crit always plays the flip smash where the smash is offered")
	t.ok(BWClipRoute.pick("pair", "daggers", "", _has("pair"), { "salt": "c", "crit": true }) != "smash_flip", "daggers never flip-smash")
	var far := _counts("heavy", "axe", "", 400, { "melee": false })
	t.ok(not far.has("smash") and not far.has("smash_flip") and not far.has("sweep_under"), "no smash or sweep at range (%s)" % str(far))
	t.eq(BWClipRoute.pick("heavy", "axe", "", _has("heavy", "axe"), { "salt": "m", "single": false }), "", "a multi-target blow keeps its clip")
	t.eq(BWClipRoute.pick("heavy", "axe", "cut", _has("heavy", "axe"), { "salt": "m" }), "cut", "a skill clip with no table keeps its clip")
	t.eq(BWClipRoute.pick("staff", "staff", "tempest", _has("staff"), { "salt": "m" }), "tempest", "Tempest keeps its floating cast")
	t.eq(BWClipRoute.pick("pistol", "pistols", "", _has("pistol"), { "salt": "m" }), "", "a style without alternates plays its strike")


func test_backstab_route(t) -> void:
	var has := _has("pair")
	t.eq(BWClipRoute.pick("pair", "daggers", "", has, { "salt": "b", "behind": true }), "backstab", "a dagger attack from behind backstabs")
	t.eq(BWClipRoute.pick("pair", "daggers", "", has, { "salt": "b", "behind": true, "crit": true }), "backstab", "even a crit")
	t.eq(BWClipRoute.pick("pair", "daggers", "", has, { "salt": "b", "skill_name": "assassinate" }), "backstab", "Assassinate backstabs (from behind by its rule; its event carries no tag)")
	t.ok(BWClipRoute.pick("pair", "daggers", "", has, { "salt": "b", "behind": true, "skill_name": "hamstring" }) != "backstab", "other skills don't")
	t.ok(BWClipRoute.pick("pair", "daggers", "", has, { "salt": "b", "behind": false }) != "backstab", "not from the front")
	t.ok(BWClipRoute.pick("pair", "daggers", "", has, { "salt": "b", "behind": true, "melee": false }) != "backstab", "not a thrown blade")
	t.ok(BWClipRoute.pick("one", "sword", "", _has("one"), { "salt": "b", "behind": true }) != "backstab", "daggers only")
	# the rules tag the blow (view only): an attack at a foe's back carries "behind"
	var b := _fight()
	var a: BWUnit = b.units[0]
	var v: BWUnit = b.units[1]
	v.facing = BWHex.direction_index(v.pos, a.pos)
	v.facing = (v.facing + 3) % 6                                  # its back to the attacker
	b.queue = [a]
	b.turn_index = 0
	b._begin_turn()
	b.history.clear()
	b.attack(a, v)
	var ev: Array = b.history.filter(func(e): return e.type == "attack")
	t.ok(not ev.is_empty() and bool(ev[0].get("behind", false)), "an attack from behind is tagged behind")
	var b2 := _fight()
	var a2: BWUnit = b2.units[0]
	var v2: BWUnit = b2.units[1]
	v2.facing = BWHex.direction_index(v2.pos, a2.pos)                # facing the attacker
	b2.queue = [a2]
	b2.turn_index = 0
	b2._begin_turn()
	b2.history.clear()
	b2.attack(a2, v2)
	var ev2: Array = b2.history.filter(func(e): return e.type == "attack")
	t.ok(not ev2.is_empty() and not ev2[0].has("behind"), "an attack from the front isn't")
	# the choreography: the slither ends behind the target and comes home
	var home := Vector3(0, 0, 0)
	var d := Vector3(0, 0, 1.73)
	var to := BWBackstab.stab_point(home, d)
	t.near(to.distance_to(d), BWBackstab.REACH, 0.001, "the stab is made at the target's back")
	t.near(BWBackstab.path(home, to, 0.0, 1.0).distance_to(home), 0.0, 0.001, "the slither leaves from home")
	t.near(BWBackstab.path(home, to, 1.0, -1.0).distance_to(to), 0.0, 0.001, "and arrives behind")
	t.ok(absf(BWBackstab.path(home, to, 0.25, 1.0).x) > 0.1, "on an S, not a straight line")


func _fight() -> BWBattle:
	var cells: Array = []
	for r in N:
		for c in N:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	var board := BWBoard.from_dict({ "name": "bs", "cols": N, "rows": N, "cells": cells,
		"spawns": { "player": [[0, 0]], "enemy": [[8, 8]] } })
	var b := BWBattle.new(board, 5)
	var a := BWUnit.from_roster({ "id": "rem", "name": "Rem", "weapon_class": "daggers", "element": "wind",
		"con": 4, "str": 4, "dex": 40, "wil": 4, "def": 4, "res": 4, "spd": 4 })
	var v := BWUnit.from_roster({ "id": "foe", "name": "Foe", "weapon_class": "axe", "element": "water",
		"con": 40, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })
	b.setup([a], [v])
	a.pos = C
	v.pos = BWHex.neighbors(C)[0]
	for u in [a, v]:
		u.statuses = {}
	b.refresh_effects()
	return b


func test_alternate_clips(t) -> void:
	var mk := func(st: String, n: String) -> Dictionary:
		return (BWAnimClips.load_set(st).get_animation(n).get_meta("bw") as Dictionary)
	for st in ["one", "heavy", "polearm"]:
		var m: Dictionary = mk.call(st, "strike_smash")
		t.ok(is_equal_approx(float(m.markers.hit), float(m.markers.land)) and float(m.markers.launch) < float(m.markers.land),
			"%s smash: the blow lands with her" % st)
		var f: Dictionary = mk.call(st, "strike_smash_flip")
		var ys: Array = f.get("flip_pitch", [])
		var mono := true
		for i in range(1, ys.size()):
			if float(ys[i]) < float(ys[i - 1]) - 1e-6:
				mono = false
		t.ok(ys.size() > 10 and is_zero_approx(float(ys[0])) and is_equal_approx(float(ys.back()), TAU) and mono,
			"%s flip: one forward somersault, 0 -> TAU" % st)
		var land_i := int(round(float(f.markers.land) * BWAnimClips.BAKE_HZ))
		t.near(float(ys[mini(land_i, ys.size() - 1)]), TAU, 0.01, "%s flip: over by the landing" % st)
	for st in ["one", "heavy"]:
		var tm: Dictionary = mk.call(st, "strike_throw_under")
		t.ok(float(tm.markers.release) < float(tm.markers.draw) and (tm.get("toss", []) as Array).size() == 2,
			"%s underhand throw: the hand is empty from the release to the draw" % st)
		t.ok(BWAnimClips.actions_for(st, "axe").has("throw_under") and BWAnimClips.actions_for(st, "axe").has("sweep_under"),
			"%s axes answer throw_under (Axe Throw) and sweep_under (Earthsplitter)" % st)
	t.eq(BWSkillRegistry.clip("earthsplitter"), "sweep_under", "Earthsplitter plays the underhand sweep")
	t.eq(BWSkillRegistry.clip("tempest"), "tempest", "Tempest plays the floating cast")
	var tp: Dictionary = mk.call("staff", "cast_tempest")
	t.ok((tp.get("spin_yaw", []) as Array).size() > 10 and float(tp.markers.release) > float(tp.markers.coil), "Tempest turns once and looses at the top")
	t.eq(str(BWAnimClips.actions_for("staff").tempest.after.channel), "coil", "and follows the channel from its coil")
	# the jump shot leaves the floor before the release and lands after it
	var jl := BWAnimClips.load_set("bow").get_animation("shot_jump")
	var jm: Dictionary = jl.get_meta("bw")
	var tr := -1
	for i in jl.get_track_count():
		if str(jl.track_get_path(i).get_concatenated_subnames()) == "contact_l":
			tr = i
	t.ok(tr >= 0 and float(jl.value_track_interpolate(tr, float(jm.markers.release))) < 0.1, "the arrow leaves in the air")
	t.ok(float(jm.markers.launch) < float(jm.markers.release) and float(jm.markers.release) < float(jm.markers.land), "launch < release < land")
	var bm: Dictionary = mk.call("pair", "strike_backstab")
	t.ok(float(bm.markers.land) < float(bm.markers.hit) and float(bm.markers.hit) < float(bm.markers.slide_back)
		and not bm.markers.has("hop_start"), "backstab: arrives, stabs, slithers home (no straight hop)")
	t.ok(BWClipRoute.SETUP_BY_SKILL.get("self_detonate", "") == "flourish"
		and BWClipRoute.setup_pose_for("self_detonate", "cast", _has("pair"), false) == "flourish"
		and BWClipRoute.setup_pose_for("self_detonate", "cast", _has("one"), false) == "cast", "Self-detonate: daggers flourish, the rest cast")


## D520: the lance, javelin and trident fight one-handed behind a shield;
## the halberd and glaive stay two-handed.
func test_shield_spears(t) -> void:
	for id in ["lance", "javelin"]:
		t.eq(BWAnimClips.set_for(BWWeaponView.meta_for(id)), "spear", "%s: the spear set (one hand + shield)" % id)
	for id in ["halberd", "glaive"]:
		t.eq(BWAnimClips.set_for(BWWeaponView.meta_for(id)), "polearm", "%s: two-handed" % id)
	var lib := BWAnimClips.load_set("spear")
	var bad: PackedStringArray = []
	for n in ["idle", "walk", "run", "strike", "stricken", "stricken_flinch"]:
		var a := lib.get_animation(n)
		for i in a.get_track_count():
			var ch := str(a.track_get_path(i).get_concatenated_subnames())
			if ch == "hand_l_grip" and float(a.value_track_interpolate(i, a.length * 0.5)) > 0.01:
				bad.append(n)
	t.ok(bad.is_empty(), "the shield hand never takes the spear (%s)" % ", ".join(bad))
	var blk := lib.get_animation("block")
	var lp := -1
	for i in blk.get_track_count():
		if str(blk.track_get_path(i).get_concatenated_subnames()) == "hand_l_pos":
			lp = i
	var up: Vector3 = blk.value_track_interpolate(lp, float((blk.get_meta("bw").markers as Dictionary).impact))
	t.ok(up.y > (BWAnimClips.SHIELD_GUARD.hand_l_pos as Vector3).y + 0.1, "the block raises the shield")
	var lg := lib.get_animation("strike_lunge")
	var ll := -1
	for i in lg.get_track_count():
		if str(lg.track_get_path(i).get_concatenated_subnames()) == "hand_l_pos":
			ll = i
	var back: Vector3 = lg.value_track_interpolate(ll, float((lg.get_meta("bw").markers as Dictionary).hit))
	t.ok(back.z < -0.3, "the lunge flings the shield arm back (the author's call)")
