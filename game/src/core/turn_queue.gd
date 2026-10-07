class_name BWTurnQueue
## Speed order, from V8 combat_scene.build_queue(): every living unit acts
## once per cycle, fastest first; ties go to the player side, then by id so
## the order is deterministic.
## D347 GROUP TURNS: units sharing a non-empty `group_turn` key are pulled
## together into one contiguous block at the slot of the group's fastest
## member (its order inside the block is settled when the block begins,
## BWBattle._group_open). Units without a key are untouched.


static func build(units: Array) -> Array:
	var q: Array = units.filter(func(u: BWUnit): return u.alive() and BWObjectives.in_queue(u))   # D327: objects wait
	q.sort_custom(func(a: BWUnit, b: BWUnit) -> bool:
		if a.speed() != b.speed():
			return a.speed() > b.speed()
		if a.team != b.team:
			return a.team == "player"
		return a.id < b.id)
	return group(q)


## D347: gather each group's members at its first member's slot.
static func group(q: Array) -> Array:
	if not q.any(func(u): return u.group_turn != ""):
		return q
	var members := {}
	for u in q:
		if u.group_turn != "":
			if not members.has(u.group_turn):
				members[u.group_turn] = []
			members[u.group_turn].append(u)
	var out: Array = []
	var placed := {}
	for u in q:
		if u.group_turn == "":
			out.append(u)
		elif not placed.has(u.group_turn):
			placed[u.group_turn] = true
			out.append_array(members[u.group_turn])
	return out


## D347: the queue as the turn order shows it: a unit, or a group block as
## { "group": key, "units": [...] } (living members only). One entry per slot.
static func slots(q: Array) -> Array:
	var out: Array = []
	for u in q:
		if u.group_turn != "" and not out.is_empty() and out[-1] is Dictionary and out[-1].group == u.group_turn:
			out[-1].units.append(u)
		elif u.group_turn != "":
			out.append({ "group": u.group_turn, "units": [u] })
		else:
			out.append(u)
	return out
