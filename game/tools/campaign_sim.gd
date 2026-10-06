extends SceneTree
## Whole-run balance sim: the AI plays YOUR side through a full run (gear,
## downtime, picks) against the real enemies_for() squads, then the Giant.
##   godot --headless --path . --script res://tools/campaign_sim.gd
## Env: RUNS (per policy, default 12). Policies are downtime habits (D127,
## one choice per unit per day), by squad slot:
##   specialize  everyone Specializes
##   branch      everyone Branches out
##   wander      everyone Wanders
##   mixed       slots 1-4 Specialize, 5 Branches out, 6 Wanders (recruits Specialize)
## Found weapons are equipped only in the unit's own class or one it has
## expertise in; rogues (Wander's jackpot) still deploy, and play themselves.
## Prints win rate and rounds per fight, survivors, and the Giant's HP left.

const POLICIES := {
	"specialize": ["specialize"],
	"branch": ["branch_out"],
	"wander": ["wander"],
	"mixed": ["specialize", "specialize", "specialize", "specialize", "branch_out", "wander"],
}


## The policy's choice for squad slot i (a list shorter than the squad repeats
## its first entry: one-word policies, recruits under "mixed").
static func choice_for(pol: String, i: int) -> String:
	var l: Array = POLICIES[pol]
	return str(l[i] if i < l.size() else l[0])


func _init() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 12
	var ids: Array = BWData.table("roster").map(func(r): return str(r.id))
	for pol in POLICIES:
		var wins := []          # per fight: wins
		var rounds := []
		var played := []        # D145: per fight, map -> times (the order is shuffled per run)
		var alive := []
		for f in BWRun.BOSS_FIGHT:
			wins.append(0); rounds.append([]); alive.append(0); played.append({})
		var boss_left: Array = []
		var rogues := 0
		for s in runs:
			var rng := RandomNumberGenerator.new()
			rng.seed = 9000 + s
			var pick := ids.duplicate()
			for i in range(pick.size() - 1, 0, -1):
				var j := rng.randi() % (i + 1)
				var t = pick[i]; pick[i] = pick[j]; pick[j] = t
			var run := BWRun.start(pick.slice(0, BWRun.SQUAD), 9000 + s)
			for u in run.squad:
				BWPicks.auto_resolve(u)
			while not run.is_over() and run.fight <= BWRun.BOSS_FIGHT:
				var n := run.fight
				var deployed := _deploy(run)
				_gear(run, deployed)
				var enemies := run.enemies_for(n)
				run.prepare_for_battle(deployed)
				var mname := run.map_for(n)
				played[n - 1][mname] = int(played[n - 1].get(mname, 0)) + 1
				var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % mname), run.seed_value * 31 + n)
				b.setup(deployed, enemies, [])
				var guard := 0
				while not b.over and guard < 1500:
					BWAI.take_turn(b)
					guard += 1
				var won := b.winner == "player"
				if won:
					wins[n - 1] += 1
				rounds[n - 1].append(b.cycle)
				alive[n - 1] += deployed.filter(func(u): return u.alive()).size()
				if n == BWRun.BOSS_FIGHT:
					boss_left.append(enemies[0].hp)
				var defeated := enemies.filter(func(e): return not e.alive())
				run.after_fight(won, deployed, defeated, enemies, b.history)
				for u in run.squad:
					u.hp = u.max_hp()
					BWPicks.auto_resolve(u)
				if n >= BWRun.BOSS_FIGHT:
					break
				var plan: Array = []
				for i in run.squad.size():
					plan.append([run.squad[i].id, choice_for(pol, i)])
				run.progress_day(plan)
				for u in run.squad:
					BWPicks.auto_resolve(u)
			rogues += run.squad.filter(func(u): return u.rogue).size()
		var out: PackedStringArray = ["POLICY %s (%d runs)" % [pol, runs]]
		out.append("  rogues at the end: %d" % rogues)
		for f in BWRun.BOSS_FIGHT:
			var r: Array = rounds[f]
			r.sort()
			out.append("  fight %2d %-9s  win %3d%%  rounds med %2d  survivors %.1f/3" % [f + 1,
				"(Giant)" if f + 1 == BWRun.BOSS_FIGHT else "(%s)" % _maps_label(played[f]),
				100 * wins[f] / maxi(r.size(), 1), r[r.size() / 2] if r.size() > 0 else 0,
				float(alive[f]) / maxf(r.size(), 1)])
		boss_left.sort()
		out.append("  Giant HP left (of 500): %s" % str(boss_left))
		print("\n".join(out))
	quit()


## The three highest-level units (ties: most HP), as a player would.
func _deploy(run: BWRun) -> Array:
	var s := run.squad.duplicate()
	s.sort_custom(func(a, b): return a.level > b.level or (a.level == b.level and a.max_hp() > b.max_hp()))
	return s.slice(0, BWRun.DEPLOY)


## Put the best legal loose piece (by stat total) into each empty or weaker slot.
func _gear(run: BWRun, units: Array) -> void:
	for u in units:
		for slot in BWRun.SLOTS:
			var cur: Dictionary = u.equipment.get(slot, {})
			var best: Dictionary = {}
			var best_v := _value(cur)
			for it in run.inventory:
				if _slot_of(it) != slot:
					continue
				if not run.can_equip(u, it):
					continue
				if slot == "main_hand" and str(it.weight) != u.weapon_class and u.expertise_rank(str(it.weight)) < 1:
					continue                   # another class only with expertise in it (D131)
				if _value(it) > best_v:
					best = it
					best_v = _value(it)
			if not best.is_empty():
				run.equip(u, best)


func _slot_of(it: Dictionary) -> String:
	var row := BWData.row("equipment", it.base)
	return str(row.slot) if not row.is_empty() else "main_hand"


func _value(it: Dictionary) -> int:
	var v := 0
	for k in it.get("stats", {}):
		v += int(it.stats[k])
	return v - (0 if not it.is_empty() else 1)


## D145: the maps a fight slot was played on across the runs, most often first.
static func _maps_label(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b] or (counts[a] == counts[b] and str(a) < str(b)))
	if keys.size() == 1:
		return str(keys[0])
	return ", ".join(keys.map(func(k): return "%s %d" % [k, counts[k]]))
