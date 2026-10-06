class_name BWTurnQueue
## Speed order, from V8 combat_scene.build_queue(): every living unit acts
## once per cycle, fastest first; ties go to the player side, then by id so
## the order is deterministic.


static func build(units: Array) -> Array:
	var q: Array = units.filter(func(u: BWUnit): return u.alive())
	q.sort_custom(func(a: BWUnit, b: BWUnit) -> bool:
		if a.speed() != b.speed():
			return a.speed() > b.speed()
		if a.team != b.team:
			return a.team == "player"
		return a.id < b.id)
	return q
