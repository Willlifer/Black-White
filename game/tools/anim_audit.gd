extends SceneTree
## D219-D222 animation fit sweep: every weapon skill is used on a flat
## board (headless), and the probe prints what the battle emits (moves,
## the skill event and how many it hits, follow-up strikes, statuses) and
## which clip the combat screen plays for it (BWClipRoute: the same routing
## the cutscene uses).
##   godot --headless --path . --script res://tools/anim_audit.gd
## design/art/ANIMATION-AUDIT.md was written from this output.

const SET_OF := { "sword": "one", "axe": "one", "lance": "polearm", "daggers": "pair", "fists": "fists",
	"pistols": "pistol", "bow": "bow", "staff": "staff" }
const C := Vector2i(5, 5)


func _initialize() -> void:
	_run.call_deferred()


func _board(n: int = 11) -> BWBoard:
	var cells: Array = []
	for r in n:
		for c in n:
			cells.append({ "q": c, "r": r, "terrain": "neutral", "elevation": 0 })
	return BWBoard.from_dict({ "name": "flat", "cols": n, "rows": n, "cells": cells,
		"spawns": { "player": [[0, 0], [0, 1], [0, 2]], "enemy": [[10, 0], [10, 1], [10, 2]] } })


func _u(id: String, wc: String, el: String, con := 4) -> BWUnit:
	return BWUnit.from_roster({ "id": id, "name": id, "weapon_class": wc, "element": el,
		"con": con, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4 })


## The parent skill that grants `key` as a follow-up ("" = none).
func _parent(key: String) -> String:
	for k in BWSkillRegistry.keys():
		if key in (BWSkillRegistry.row(k).get("follow_up", []) as Array):
			return k
	return ""


func _setup(key: String, layout: Array) -> Dictionary:
	var d := BWSkillRegistry.get_def(key)
	var wc := str(d.data.get("weapon", ""))
	var me := _u("me", wc, "fire")
	var parent := _parent(key)
	for k in [key, parent]:
		if k != "" and not k in me.known_skills:
			me.known_skills.append(k)
	me.skill_loadout[wc] = [parent if parent != "" else key]
	me.quick_shot_ready = true
	var foes: Array = []
	for i in layout.size():
		foes.append(_u("f%d" % i, "axe", "water", 300))
	var mate := _u("m", "sword", "ice")
	var b := BWBattle.new(_board(), 7)
	b.setup([me, mate], foes)
	me.pos = C
	mate.pos = BWHex.neighbors(C)[3]
	for i in foes.size():
		foes[i].pos = layout[i]
		foes[i].facing = BWHex.direction_index(C, foes[i].pos)    # facing away: Assassinate's backstab
	b.queue = [me]
	b.turn_index = 0
	b._begin_turn()
	# ground to work with (Consume, Siphon, Inversion, Transfer)
	var ground: Array = []
	for f in foes:
		ground.append(f.pos)
	ground.append(BWHex.neighbors(C)[2])
	b.paint(ground, "fire", me, 2)
	if parent != "":
		var el0 := "fire" if bool(BWSkillRegistry.row(parent).get("needs_element", false)) else ""
		for h in b.skill_targets(me, parent, el0):
			var choice := _choice(b, parent, me, el0, h)
			if not b.use_skill(me, parent, el0, h, choice).is_empty():
				break
	return { "b": b, "me": me, "foes": foes }


func _choice(b: BWBattle, key: String, me: BWUnit, el: String, h: Vector2i) -> Vector2i:
	var d := BWSkillRegistry.get_def(key)
	if d.has_method("second_targets"):
		var st: Array = d.second_targets(b, me, el, h)
		if not st.is_empty():
			return st[0]
	return BWBattle.NOWHERE


## Every legal use of `key` in `layout`, each on a fresh board.
func _uses(key: String, layout: Array) -> Array:
	var d := BWSkillRegistry.get_def(key)
	var el := "fire" if bool(d.data.get("needs_element", false)) else ""
	var probe := _setup(key, layout)
	var out: Array = []
	var tg: Array = Array(probe.b.skill_targets(probe.me, key, el))
	for h in tg:
		var s := _setup(key, layout)
		var b: BWBattle = s.b
		var me: BWUnit = s.me
		var before := {}
		for u in b.units:
			before[u.id] = u.pos
		var start := b.history.size()
		var e := b.use_skill(me, key, el, h, _choice(b, key, me, el, h))
		if e.is_empty():
			continue
		var res: Array = e.results
		var dist := BWHex.distance(me.pos, before[str(res[0].target)]) if not res.is_empty() else -1
		out.append({ "b": b, "me": me, "e": e, "start": start, "dist": dist, "n": res.size() })
	return out


func _run() -> void:
	var nb := BWHex.neighbors(C)
	var ray := Array(BWHex.ray(C, nb[0], 4))
	var layouts := [[ray[0]], [ray[0], ray[1]], [ray[1]], [ray[2]], [ray[0], nb[1], nb[5]]]
	var keys := BWSkillRegistry.keys()
	keys.sort()
	for key in keys:
		var d := BWSkillRegistry.get_def(key)
		var wc := str(d.data.get("weapon", ""))
		var best := {}
		for lay in layouts:
			for u in _uses(key, lay):
				# prefer a use that lands blows; then the longest reach; then more victims
				var score := (1000 if int(u.n) > 0 else 0) + int(u.dist) * 10 + int(u.n)
				if best.is_empty() or score > int(best.score):
					best = u
					best["score"] = score
		if best.is_empty():
			print("%-20s %-8s NO TARGET" % [key, wc])
			continue
		var b: BWBattle = best.b
		var e: Dictionary = best.e
		var evs: PackedStringArray = []
		for ev in b.history.slice(int(best.start)):
			match str(ev.type):
				"move": evs.append("move(%s%s)" % [str(ev.get("kind", "walk")), "" if str(ev.unit) == "me" else ":" + str(ev.unit)])
				"skill": evs.append("SKILL[%d]" % (ev.results as Array).size())
				"attack": evs.append("attack(%s %d/%d)" % [str(ev.get("skill", "")), int(ev.get("strike", 0)) + 1, int(ev.get("strikes", 1))])
				"status": evs.append("status(%s)" % str(ev.get("status", "")))
				"growth", "turn", "cycle", "paint", "tiles_tick", "follow_up", "stat_up", "guard", "detonate", "erupt": pass
				_: evs.append(str(ev.type))
		var st := str(SET_OF.get(wc, "one"))
		var r := BWClipRoute.skill(key, st, wc, int(best.dist), str(e.element), int(best.n) > 0)
		print("%-20s %-8s %-8s dist=%2d hits=%d el=%-5s def=%-12s %-8s pose=%-14s clip=%-20s | %s" % [key, wc, st, int(best.dist), int(best.n),
			str(e.element), BWSkillRegistry.clip(key), str(r.mode), str(r.pose), str(r.clip) + (" +" + str(r.then) if r.has("then") else ""),
			" ".join(evs)])
	quit(0)
