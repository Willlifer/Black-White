extends RefCounted
## D219-D222: the animation fit sweep's routes (BWClipRoute,
## design/art/ANIMATION-AUDIT.md) and the encounters' motion setup.

const SETS_OF := { "sword": ["one", "heavy"], "axe": ["one", "heavy"], "lance": ["polearm", "spear"], "daggers": ["pair"],
	"fists": ["fists"], "pistols": ["pistol"], "bow": ["bow"], "staff": ["staff"] }


## Every def that names a clip gets a real clip in every style of its class
## (the audit's fixes can't silently fall back to the plain strike).
func test_every_named_clip_resolves(t) -> void:
	var bad: PackedStringArray = []
	for key in BWSkillRegistry.keys():
		var row := BWSkillRegistry.row(key)
		var clip := str(row.get("clip", ""))
		if clip == "":
			continue
		for st in SETS_OF.get(str(row.weapon), []):
			var cls := "axe" if str(row.weapon) == "axe" else ""
			var acts := BWAnimClips.actions_for(st, cls)
			if not acts.has(clip) or not BWAnimClips.load_set(st).has_animation(StringName(str(acts[clip].clip))):
				bad.append("%s/%s: %s" % [key, st, clip])
	t.ok(bad.is_empty(), "every def's clip plays in each style of its class (%s)" % ", ".join(bad))


func test_route_rules(t) -> void:
	var being := BWUnit.from_roster({ "id": "b", "name": "b", "weapon_class": "sword", "element": "fire" })
	being.encounter = "being"
	t.ok(BWClipRoute.casts(being, false), "a Being casts its attacks")
	t.ok(not BWClipRoute.casts(null, false, "thrust"), "a weapon skill strikes, even at range")
	t.ok(BWClipRoute.casts(null, true), "a staff casts")
	var has := func(p: String) -> bool: return p in ["brace", "channel"]
	t.eq(BWClipRoute.setup_pose("brace", has, false), "brace", "a setup plays its def's pose")
	t.eq(BWClipRoute.setup_pose("", has, false), "", "a weapon with no setup pose plays nothing (no free-hand channel)")
	t.eq(BWClipRoute.setup_pose("", has, true), "channel", "a staff channels")
	t.eq(BWClipRoute.multi_hits("hundred"), 6, "Hundred Fists shows six blows")
	var m: Dictionary = BWAnimClips.load_set("fists").get_animation("strike_hundred").get_meta("bw").markers
	t.ok(m.has("hit6") and float(m.hit6) > float(m.hit5) and float(m.hit2) > float(m.hit), "hundred: hit .. hit6 in order")
	t.ok((BWAnimClips.load_set("fists").get_animation("strike_grapple").get_meta("bw").markers as Dictionary).has("throw"), "grapple: throw marker")


func test_encounter_motion(t) -> void:
	var c := BWUnit.from_roster({ "id": "colossus", "name": "c", "weapon_class": "lance", "weapon_model": "lance" })
	c.encounter = "colossus"
	var ch := BWCharacter.create(c)
	t.eq(str(ch.animator.actions.walk.clip), "walk_colossus", "the Colossus walks heavy")
	t.eq(str(ch.animator.actions.strike.clip), "strike_colossus", "and thrusts its own way")
	t.eq(str(ch.animator.plan_move(3.0 * BWAnimClips.HEX_STEP, 3).gait), "walk", "it never runs")
	ch.free()
	var g := BWUnit.from_roster({ "id": "grunt3", "name": "g", "weapon_class": "sword", "weapon_model": "sword" })
	g.encounter = "grunt"
	var gc := BWCharacter.create(g)
	t.eq(str(gc.animator.actions.strike.clip), "strike_jab", "a grunt jabs")
	var paces := {}
	for i in 10:
		var gi := BWUnit.from_roster({ "id": "grunt%d" % i, "name": "g", "weapon_class": "sword", "weapon_model": "sword" })
		gi.encounter = "grunt"
		var gx := BWCharacter.create(gi)
		paces["%.2f" % float(gx.animator.plan_move(2.0 * BWAnimClips.HEX_STEP, 2).dur)] = true
		gx.free()
	t.ok(paces.size() >= 5, "ten grunts don't share one pace (%d distinct)" % paces.size())
	gc.free()
	var b := BWUnit.from_roster({ "id": "being1", "name": "b", "weapon_class": "sword", "weapon_model": "sword", "element": "water" })
	b.encounter = "being"
	var bc := BWCharacter.create(b)
	bc.animator.update(1.0 / 60.0)
	bc.animator.update(0.5)
	var p: Dictionary = bc.animator.last_pose
	t.ok(float(p.contact_l) < 0.1 and float(p.contact_r) < 0.1, "a Being's feet don't touch the floor")
	t.eq(str(bc.animator.plan_move(BWAnimClips.HEX_STEP, 1).gait), "glide", "a Being glides")
	bc.free()
