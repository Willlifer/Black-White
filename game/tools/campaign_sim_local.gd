extends SceneTree
## Whole-run balance sim: the AI plays YOUR side through a full run (gear,
## downtime, picks) against the real enemies_for() squads, then the Giant.
##   godot --headless --path . --script res://tools/campaign_sim_local.gd
## Local copy of tools/campaign_sim.gd for the D133 enemy-curve tuning; it adds
## env POLICY (one policy only), CURVE (a JSON ENEMY_CURVE to try) and SEED0
## (first run seed, default 9000, to split RUNS across processes). Prints a
## RAW line per fight (wins, rounds list) for merging.
## Env: RUNS (per policy, default 12). Policies are downtime habits (D127,
## one choice per unit per day), by squad slot:
##   specialize  everyone Specializes
##   branch      everyone Branches out
##   wander      everyone Wanders
##   mixed       slots 1-4 Specialize, 5 Branches out, 6 Wanders (recruits Specialize)
## D175: a day offers each unit two of the three, so a policy is a preference:
## its choice when offered, else the first offered of FALLBACK's order.
## Branch out takes its first card (D176). Found weapons are equipped only in
## the unit's own class or one it has expertise in.
## Prints win rate and rounds per fight, survivors, and the Giant's HP left.

const POLICIES := {
	"specialize": ["specialize"],
	"branch": ["branch_out"],
	"wander": ["wander"],
	"mixed": ["specialize", "specialize", "specialize", "specialize", "branch_out", "wander"],
}


## When the policy's choice isn't offered today (D175), the first offered of these.
const FALLBACK := ["specialize", "wander", "branch_out"]


## The policy's choice for squad slot i (a list shorter than the squad repeats
## its first entry: one-word policies, recruits under "mixed"), among the
## day's `offered` choices (BWRun.day_choices; empty = any).
static func choice_for(pol: String, i: int, offered: Array = []) -> String:
	var l: Array = POLICIES[pol]
	var want := str(l[i] if i < l.size() else l[0])
	if offered.is_empty() or want in offered:
		return want
	for c in FALLBACK:
		if c in offered:
			return c
	return str(offered[0])


func _init() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 12
	if OS.get_environment("CURVE") != "":         # a JSON ENEMY_CURVE to try (D133 tuning)
		BWRun.curve_override = JSON.parse_string(OS.get_environment("CURVE"))
	var only := OS.get_environment("POLICY")
	var seed0 := int(OS.get_environment("SEED0")) if OS.get_environment("SEED0") != "" else 9000   # split runs across processes
	var ids: Array = BWData.table("roster").map(func(r): return str(r.id))
	for pol in POLICIES:
		if only != "" and pol != only:
			continue
		var wins := []          # per fight: wins
		var rounds := []
		var alive := []
		for f in BWRun.BOSS_FIGHT:
			wins.append(0); rounds.append([]); alive.append(0)
		var boss_left: Array = []
		for s in runs:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed0 + s
			var pick := ids.duplicate()
			for i in range(pick.size() - 1, 0, -1):
				var j := rng.randi() % (i + 1)
				var t = pick[i]; pick[i] = pick[j]; pick[j] = t
			var run := BWRun.start(pick.slice(0, BWRun.SQUAD), seed0 + s)
			for u in run.squad:
				BWPicks.auto_resolve(u)
			while not run.is_over() and run.fight <= BWRun.BOSS_FIGHT:
				var n := run.fight
				var deployed := _deploy(run)
				_gear(run, deployed)
				var enemies := run.enemies_for(n)
				run.prepare_for_battle(deployed)
				var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % run.map_for(n)), run.seed_value * 31 + n)
				b.setup(deployed, enemies, [])
				var guard := 0
				while not b.over and guard < 1500:
					BWAI.take_turn(b)
					guard += 1
				var won := b.winner == "player"
				if won:
					wins[n - 1] += 1
				rounds[n - 1].append(b.cycle)
				if OS.get_environment("LVL") != "":   # tuning: levels, HP and stat totals per side
					print("LVL %d me L%.1f hp%.0f st%.0f  foe L%.1f hp%.0f st%.0f" % [n, _avg(deployed, "level"), _avg(deployed, "hp"), _avg(deployed, "st"), _avg(enemies, "level"), _avg(enemies, "hp"), _avg(enemies, "st")])
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
					plan.append([run.squad[i].id, choice_for(pol, i, run.day_choices(run.squad[i]))])
				run.progress_day(plan)
				for u in run.squad:
					BWPicks.auto_resolve(u)
		var out: PackedStringArray = ["POLICY %s (%d runs)" % [pol, runs]]
		for f in BWRun.BOSS_FIGHT:
			var r: Array = rounds[f]
			r.sort()
			out.append("  fight %2d %-9s  win %3d%%  rounds med %2d  survivors %.1f/3" % [f + 1,
				"(Giant)" if f + 1 == BWRun.BOSS_FIGHT else "(%s)" % BWRun.new().map_for(f + 1),
				100 * wins[f] / maxi(r.size(), 1), r[r.size() / 2] if r.size() > 0 else 0,
				float(alive[f]) / maxf(r.size(), 1)])
		for f in BWRun.BOSS_FIGHT:
			print("RAW %s %d %d %s" % [pol, f + 1, wins[f], JSON.stringify(rounds[f])])
		boss_left.sort()
		out.append("  Giant HP left (of 500): %s" % str(boss_left))
		print("\n".join(out))
	quit()


func _avg(us: Array, k: String) -> float:
	var t := 0.0
	for u in us:
		if k == "level":
			t += u.level
		elif k == "hp":
			t += u.max_hp()
		else:
			for st in BWUnit.STATS:
				t += u.stat(st)
	return t / maxf(us.size(), 1)


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
