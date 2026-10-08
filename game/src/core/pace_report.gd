class_name BWPaceReport
## Fight pace measured from whole simulated fights rather than single hits:
## rounds per fight, and where the damage actually came from (basic
## attacks, skills, ground: fire/dark tiles and detonations, counters).
## `godot --headless --path game -- --pace`. The AI plays both sides; it
## uses damaging skills but never sets up ground combos on purpose, so this
## is an upper bound on fight length for a player who does.


const SUPPORT := ["bellow", "phalanx", "covering_fire", "tumble", "transfer", "inversion", "kindle", "tapestry", "overload"]   # D435-D442


## D112 `--pace --support`: every unit swaps the tail of its starter kit for
## its class's support skills, so their share can be read.
const SUPPORT_KIT := { "axe": ["bellow"], "lance": ["phalanx"], "pistols": ["covering_fire"],
	"daggers": ["tumble"], "staff": ["transfer", "inversion"] }


static func _support_kit(u: BWUnit) -> void:
	var add: Array = SUPPORT_KIT.get(u.weapon_class, [])
	if add.is_empty():
		return
	var kit: Array = BWSkillRegistry.starter(u.weapon_class)
	kit = kit.slice(0, maxi(0, BWUnit.loadout_cap(u.weapon_class) - add.size())) + add
	for k in add:
		if not k in u.known_skills:
			u.known_skills.append(k)
	u.skill_loadout[u.weapon_class] = kit


static func render(fights: int = 40, support_kits: bool = false) -> String:
	var roster := BWData.table("roster")
	var maps := ["arena", "paintball", "bridge", "ravine", "tinderbox"]
	var dmg := { "basic": 0, "skill": 0, "ground": 0, "detonation": 0, "counter": 0, "riposte": 0, "chain": 0 }
	var rounds: Array = []
	var actions := { "attack": 0, "skill": 0 }
	var support := {}                          # D112: support skill uses by key
	for k in SUPPORT:
		support[k] = 0
	var offered := 0                           # fights with a support skill on the field
	for i in fights:
		var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % maps[i % maps.size()]), 500 + i)
		var p: Array = []
		var e: Array = []
		for k in 3:
			p.append(BWUnit.from_roster(roster[(i * 3 + k) % roster.size()]))
			e.append(BWUnit.from_roster(roster[(i * 3 + k + 10) % roster.size()]))
		if support_kits:
			for u in p + e:
				_support_kit(u)
		b.setup(p, e)
		if b.units.any(func(u): return BWSkillRegistry.expand(u.fight_loadout(u.weapon_class)).any(func(k): return k in SUPPORT)):
			offered += 1
		var guard := 0
		while not b.over and guard < 900:
			BWAI.take_turn(b)
			guard += 1
		rounds.append(b.cycle)
		for ev in b.history:
			match ev.type:
				"attack":
					dmg.basic += int(ev.result.damage)
					actions.attack += 1
				"skill":
					actions.skill += 1
					if support.has(str(ev.skill)):
						support[ev.skill] += 1
					for r in ev.results:
						dmg.skill += int(r.result.damage)
				"counter":
					dmg.counter += int(ev.result.damage)
				"riposte":
					for r in ev.results:
						dmg.riposte += int(r.result.damage)
				"chain":
					dmg.chain += int(ev.amount)
				"tile_damage":
					if ev.cause == "detonation":
						dmg.detonation += int(ev.amount)
					else:
						dmg.ground += int(ev.amount)
	rounds.sort()
	var total := 0
	for k in dmg:
		total += dmg[k]
	var out: PackedStringArray = []
	out.append("FIGHT PACE — %d AI-vs-AI fights, level-1 roster squads, all five maps%s" % [fights,
		" (support kits)" if support_kits else ""])
	out.append("rounds per fight: median %d, fastest %d, slowest %d" % [rounds[rounds.size() / 2], rounds[0], rounds[-1]])
	out.append("actions: %d basic attacks, %d skills (%.0f%% skills)" % [actions.attack, actions.skill,
		100.0 * actions.skill / maxf(actions.attack + actions.skill, 1)])
	var sup_total := 0
	for k in support:
		sup_total += support[k]
	out.append("support skills (D112): %d uses, %.1f%% of all actions; %d of %d fights field one" % [sup_total,
		100.0 * sup_total / maxf(actions.attack + actions.skill, 1), offered, fights])
	out.append("  " + "  ".join(support.keys().map(func(k): return "%s %d" % [k, support[k]])))
	out.append("damage by source:")
	for k in dmg:
		out.append("  %-11s %6d  (%4.1f%%)" % [k, dmg[k], 100.0 * dmg[k] / maxf(total, 1)])
	return "\n".join(out)
