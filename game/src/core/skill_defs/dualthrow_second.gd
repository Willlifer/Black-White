extends BWSkillDef
## Daggers, follow-up only (Dualthrow's other blade). Same trail rule; D87:
## it bounces on to the nearest other foe within BOUNCE_RANGE of its target,
## at BOUNCE_PCT%. Dualthrow+ (the Dualthrow improve): it bounces twice, the
## second time on from the first bounce's foe at PLUS_SECOND_PCT%.

const PLUS_SECOND_PCT := 50


func _init() -> void:
	define({
		"key": "dualthrow_second", "name": "Second Dagger", "weapon": "daggers", "clip": "throw_l",
		"desc": "The other blade, same reach. It bounces on to the nearest foe within 2 hexes for 75%",
		"targeting": "unit", "needs_element": true, "range": BWSkills.DUALTHROW_RANGE, "cd": 0,
		"power": BWSkills.DUALTHROW_DMG, "follow_up_only": true,
	}, 100)


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._on_board(BWHex.trail(u.pos, target))
	p.victims = b._foes_on(u, p.hexes)
	var hit := b.unit_at(target)
	if hit == null or hit.team == u.team:
		return
	var best := bounce_from(b, u, hit, p.victims)
	if best != null:
		p.victims.append(best)
		p.shares[best.id] = [BWSkills.BOUNCE_PCT / 100.0, "Bounce (off %s): %d%%" % [hit.name, BWSkills.BOUNCE_PCT], "Bounce"]
		p["bounce"] = best.id
		if u.skill_upgraded("dualthrow"):
			var more := bounce_from(b, u, best, p.victims)
			if more != null:
				p.victims.append(more)
				p.shares[more.id] = [PLUS_SECOND_PCT / 100.0,
					"Second bounce (Dualthrow+, off %s): %d%%" % [best.name, PLUS_SECOND_PCT], "Bounce"]


## The nearest other foe within BOUNCE_RANGE of `from`, not already struck.
func bounce_from(b: BWBattle, u: BWUnit, from: BWUnit, struck: Array) -> BWUnit:
	var best: BWUnit = null
	for o in b.foes_of(u):
		if o in struck or b.gap(from, o) > BWSkills.BOUNCE_RANGE:
			continue
		if best == null or b.gap(from, o) < b.gap(from, best):
			best = o
	return best
