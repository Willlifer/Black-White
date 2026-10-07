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
## D175: a day offers each unit two of the three, so a policy is a preference:
## its choice when offered, else the first offered of FALLBACK's order.
## Branch out takes its first card (D176). Found weapons are equipped only in
## the unit's own class or one it has expertise in; the best weapon of another
## class it has expertise in is carried as the second weapon (D180, D193).
## Prints win rate and rounds per fight, survivors, and the Giant's HP left.
## D188 room policy, env ROOMS (default standard; "all" runs each in turn):
##   standard  always the Standard room
##   hard      always the Hard room (when there is a choice)
##   mixed     Hard when the squad is healthy: the last fight won with all
##             three deployed standing; else Standard
## SHADOW=1: under "standard", every choice fight is also played in its Hard
## room on a copy of the run (same squad, same day), printed "hard (paired)".
## HARD="stages,levels,mult,armor" overrides the BWRooms Hard knobs (tuning).
## CURVE="m1,...,m10" overrides ENEMY_CURVE's multipliers, ELVL the enemy
## levels per stage (BWRooms.LEVELS_PER_STAGE) (tuning).
## ENC=1 (D212): every choice fight (3-10) is also played as each special
## encounter (BWEncounters: horde, colossus, blank, being) on a copy of the
## run, the Hard room's map; printed per fight and as a fights 3-10 total.
## ENC_TUNE="horde_mult,horde_hp,colossus_mult,colossus_hp,blank_mult,being_mult[,blank_hp,being_hp]" (tuning).
## WEATHER=1 (D254): every choice fight from fight 5 is also played on a copy
## of the run in its Standard room, once with no weather and once in each
## weather (BWWeather.KINDS), paired: same squad, same day, same map; printed
## per kind as fights 5-10 win rate vs the paired clear-sky rate (a swing over
## 15 points is flagged). The run's own fights play their room's weather.
## Env POLICY limits the downtime habits to one (e.g. POLICY=mixed).
## Per fight it also prints the win rate in each kind of room played.
## D308: per keystone the squad's AI took (BWPicks.auto_resolve), the win rate
## of the fights (1-10, rooms as played) a deployed unit holding it fought
## (informational: spotting an overpowered keystone; late fights hold more).
## MAP=<name> (D319, tools only) plays every fight on that map at its deploy
## count, e.g. MAP=commons for 6v6 (the enemies drawn six to a room).
## TRACE_SIM=1 prints each fight's turns, cycles and time; TRACE_FIGHT="run:fight"
## prints the acting unit before every turn of that one fight (D308: finding a hang).

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
	var ids: Array = BWData.table("roster").map(func(r): return str(r.id))
	var room_pols: Array = ["standard", "hard", "mixed"] if OS.get_environment("ROOMS") == "all" else [OS.get_environment("ROOMS") if OS.get_environment("ROOMS") != "" else "standard"]
	var only := OS.get_environment("POLICY")
	if OS.get_environment("HARD") != "":                   # D188 tuning: "stages,levels,mult,armor"
		var k := OS.get_environment("HARD").split(",")
		BWRooms.HARD_STAGES = int(k[0]); BWRooms.HARD_LEVELS = int(k[1])
		BWRooms.HARD_MULT = float(k[2]); BWRooms.HARD_ARMOR = int(k[3])
	if OS.get_environment("CURVE") != "":                  # tuning: the ten base-stat multipliers
		var m := OS.get_environment("CURVE").split(",")
		BWRun.curve_override = []
		for i in BWRun.ENEMY_CURVE.size():
			var row: Array = BWRun.ENEMY_CURVE[i].duplicate()
			row[1] = float(m[i])
			BWRun.curve_override.append(row)
	if OS.get_environment("ENC_TUNE") != "":               # D212 tuning
		var e := OS.get_environment("ENC_TUNE").split(",")
		BWEncounters.HORDE_MULT = float(e[0]); BWEncounters.HORDE_HP = float(e[1])
		BWEncounters.COLOSSUS_MULT = float(e[2]); BWEncounters.COLOSSUS_HP = float(e[3])
		BWEncounters.BLANK_MULT = float(e[4]); BWEncounters.BEING_MULT = float(e[5])
		if e.size() >= 8:
			BWEncounters.BLANK_HP = float(e[6]); BWEncounters.BEING_HP = float(e[7])
	if OS.get_environment("TWINS") != "":                  # D259 tuning: "hp,mult" for the Twins (fight 7)
		var tw := OS.get_environment("TWINS").split(",")
		BWTwins.TWINS_HP = float(tw[0])
		if tw.size() > 1:
			BWTwins.TWINS_MULT = float(tw[1])
	if OS.get_environment("ELVL") != "":                   # tuning: enemy levels per stage
		BWRooms.LEVELS_PER_STAGE = float(OS.get_environment("ELVL"))
	print("Curve: %s, levels per stage %.2f" % [str((BWRun.curve_override if not BWRun.curve_override.is_empty() else BWRun.ENEMY_CURVE).map(func(r): return r[1])), BWRooms.LEVELS_PER_STAGE])
	print("Hard: stages +%d, levels +%d, mult x%.2f, armour +%d" % [BWRooms.HARD_STAGES, BWRooms.HARD_LEVELS, BWRooms.HARD_MULT, BWRooms.HARD_ARMOR])
	for combo in _combos(room_pols, only):
		_sim(combo[0], combo[1], runs, ids)
	quit()


func _combos(room_pols: Array, only: String) -> Array:
	var out: Array = []
	for rp in room_pols:
		for pol in POLICIES:
			if only == "" or only == pol:
				out.append([pol, rp])
	return out


func _sim(pol: String, room_pol: String, runs: int, ids: Array) -> void:
	var shadow := OS.get_environment("SHADOW") == "1"
	if true:
		var wins := []          # per fight: wins
		var rounds := []
		var played := []        # D145: per fight, map -> times (the order is shuffled per run)
		var alive := []
		for f in BWRun.BOSS_FIGHT:
			wins.append(0); rounds.append([]); alive.append(0); played.append({})
		var boss_left: Array = []
		var by_room := {}       # D188: "n|kind" -> [wins, played]
		var ks_fights := {}     # D308: keystone -> [wins, fights a deployed holder fought]
		for s in runs:
			var rng := RandomNumberGenerator.new()
			rng.seed = 9000 + s
			var pick := ids.duplicate()
			for i in range(pick.size() - 1, 0, -1):
				var j := rng.randi() % (i + 1)
				var t = pick[i]; pick[i] = pick[j]; pick[j] = t
			var run := BWRun.start(pick.slice(0, BWRun.SQUAD), 9000 + s)
			run.force_map = OS.get_environment("MAP")         # D319: MAP=commons plays every fight there (6v6)
			for u in run.squad:
				BWPicks.auto_resolve(u)
			var healthy := true
			while not run.is_over() and run.fight <= BWRun.BOSS_FIGHT:
				var n := run.fight
				var kind := "standard"
				if BWRooms.has_choice(n):                      # D188: the room policy
					BWRooms.offer(run)
					var hard := room_pol == "hard" or (room_pol == "mixed" and healthy)
					BWRooms.choose(run, 1 if hard else 0)
					kind = "hard" if hard else "standard"
					if shadow and not hard:
						# D188 SHADOW=1: the same squad, same day, also tries the Hard
						# room on a copy of the run (off the record): a paired rate.
						var sr := BWRun.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
						var hr: Dictionary = sr.room_offer.rooms[1]
						if hr.has("encounter"):                # D212: the paired rate is a normal Hard room
							sr.room_offer.rooms[1] = { "kind": BWRooms.HARD, "map": hr.map, "fight": n,
								"enemies": BWRooms._draw_ids(sr, n, sr.room_offer.rooms[0].enemies, true) }
						BWRooms.choose(sr, 1)
						var sk := "%d|shadow" % n
						var swp: Array = by_room.get(sk, [0, 0])
						by_room[sk] = [swp[0] + (1 if _fight(sr, n) else 0), swp[1] + 1]
					if OS.get_environment("ENC") == "1":
						# D212: the same squad, same day, against each special encounter
						for ek in BWEncounters.KINDS:
							var er := BWRun.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
							BWRooms.offer(er)
							er.room_offer.rooms[1] = BWEncounters.room(n, ek, str(er.room_offer.rooms[1].map))
							BWRooms.choose(er, 1)
							var ekk := "%d|enc:%s" % [n, ek]
							var ewp: Array = by_room.get(ekk, [0, 0])
							by_room[ekk] = [ewp[0] + (1 if _fight(er, n) else 0), ewp[1] + 1]
				if OS.get_environment("WEATHER") == "1" and n >= BWWeather.FROM_FIGHT and BWRooms.has_choice(n):
					# D254: paired, the Standard room on a copy: clear sky, then each weather
					for wk in [""] + BWWeather.KINDS:
						var wr := BWRun.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
						BWRooms.offer(wr)
						BWRooms.choose(wr, 0)
						var wkk := "%d|w:%s" % [n, wk if wk != "" else "clear"]
						var wwp: Array = by_room.get(wkk, [0, 0])
						by_room[wkk] = [wwp[0] + (1 if _fight(wr, n, wk) else 0), wwp[1] + 1]
				var deployed := _deploy(run)
				_gear(run, deployed)
				var enemies := run.enemies_for(n)
				run.prepare_for_battle(deployed)
				var mname := run.map_for(n)
				played[n - 1][mname] = int(played[n - 1].get(mname, 0)) + 1
				var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % mname), run.seed_value * 31 + n)
				b.set_weather(BWWeather.for_fight(run, n))          # D249: the room's weather
				b.setup(deployed, enemies, [])
				var guard := 0
				var t0 := Time.get_ticks_msec()
				var tf := OS.get_environment("TRACE_FIGHT") == "%d:%d" % [s, n]
				var worst_us := 0
				while not b.over and guard < 1500:
					if tf:
						var cu := b.current()
						print("  turn %d %s %s pos %s ks %s" % [guard, cu.id if cu else "-", cu.team if cu else "", str(cu.pos) if cu else "", str(cu.keystones) if cu else ""])
					var tt := Time.get_ticks_usec()
					BWAI.take_turn(b)
					worst_us = maxi(worst_us, Time.get_ticks_usec() - tt)
					guard += 1
				if OS.get_environment("TRACE_SIM") == "1":       # timing: which fight runs long (D323: the worst AI turn)
					print("run %d fight %d %s %dv%d turns %d cycles %d %d ms (worst turn %.0f ms) %s" % [s, n, mname, deployed.size(), enemies.size(),
						guard, b.cycle, Time.get_ticks_msec() - t0, worst_us / 1000.0, b.winner])
				var won := b.winner == "player"
				if won:
					wins[n - 1] += 1
				rounds[n - 1].append(b.cycle)
				alive[n - 1] += deployed.filter(func(u): return u.alive()).size()
				healthy = won and deployed.all(func(u): return u.alive())
				if n < BWRun.BOSS_FIGHT:
					var seen := {}
					for u in deployed:
						for kid in u.keystones:
							seen[str(kid)] = true
					for kid in seen:
						var kp: Array = ks_fights.get(kid, [0, 0])
						ks_fights[kid] = [kp[0] + (1 if won else 0), kp[1] + 1]
				var rk := "%d|%s" % [n, kind]
				var wp: Array = by_room.get(rk, [0, 0])
				by_room[rk] = [wp[0] + (1 if won else 0), wp[1] + 1]
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
		var out: PackedStringArray = ["POLICY %s, ROOMS %s (%d runs)" % [pol, room_pol, runs]]
		for f in BWRun.BOSS_FIGHT:
			var r: Array = rounds[f]
			r.sort()
			out.append("  fight %2d %-9s  win %3d%%  rounds med %2d  survivors %.1f%s" % [f + 1,
				"(Giant)" if f + 1 == BWRun.BOSS_FIGHT else "(Twins)" if f + 1 == BWRun.TWINS_FIGHT else "(%s)" % _maps_label(played[f]),
				100 * wins[f] / maxi(r.size(), 1), r[r.size() / 2] if r.size() > 0 else 0,
				float(alive[f]) / maxf(r.size(), 1), _room_rates(by_room, f + 1)])
		if OS.get_environment("ENC") == "1":
			for ek in ["shadow"] + BWEncounters.KINDS.map(func(k): return "enc:" + k):
				var row: PackedStringArray = []
				var tw := 0
				var tp := 0
				for f in range(3, BWRun.FIGHTS + 1):
					var wp: Array = by_room.get("%d|%s" % [f, ek], [0, 0])
					if wp[1] > 0:
						row.append("%d:%3d%%" % [f, 100 * wp[0] / wp[1]])
						tw += wp[0]
						tp += wp[1]
				out.append("  %-14s fights 3-10 %3d%% (%d)   %s" % ["hard (paired)" if ek == "shadow" else ek.substr(4), 100 * tw / maxi(tp, 1), tp, "  ".join(row)])
		if OS.get_environment("WEATHER") == "1":
			var clear: Array = [0, 0]
			for f in range(BWWeather.FROM_FIGHT, BWRun.FIGHTS + 1):
				var cp: Array = by_room.get("%d|w:clear" % f, [0, 0])
				clear = [clear[0] + cp[0], clear[1] + cp[1]]
			var cr: float = 100.0 * clear[0] / maxf(clear[1], 1)
			out.append("  weather (paired, Standard room) clear sky fights 5-10 %3d%% (%d)" % [roundi(cr), clear[1]])
			for wk in BWWeather.KINDS:
				var row: PackedStringArray = []
				var tw := 0
				var tp := 0
				for f in range(BWWeather.FROM_FIGHT, BWRun.FIGHTS + 1):
					var wp: Array = by_room.get("%d|w:%s" % [f, wk], [0, 0])
					var cp: Array = by_room.get("%d|w:clear" % f, [0, 0])
					if wp[1] > 0:
						row.append("%d:%3d%%/%3d%%" % [f, 100 * wp[0] / wp[1], 100 * cp[0] / maxi(cp[1], 1)])
						tw += wp[0]
						tp += wp[1]
				var wr: float = 100.0 * tw / maxf(tp, 1)
				out.append("  %-9s fights 5-10 %3d%% (%d)  swing %+d%s   %s" % [wk, roundi(wr), tp, roundi(wr - cr),
					"  <-- FLAG (>15)" if absf(wr - cr) > 15.0 else "", "  ".join(row)])
		boss_left.sort()
		out.append("  Giant HP left (of 500): %s" % str(boss_left))
		var kids: Array = ks_fights.keys()
		kids.sort_custom(func(a, c): return int(ks_fights[a][1]) > int(ks_fights[c][1]))
		var krow: PackedStringArray = []
		for kid in kids:
			var kp: Array = ks_fights[kid]
			krow.append("%s %d%% (%d)" % [BWKeystones.name_of(str(kid)), 100 * int(kp[0]) / maxi(int(kp[1]), 1), int(kp[1])])
		out.append("  keystones (squad, fights 1-10 with a deployed holder): " + (", ".join(krow) if not krow.is_empty() else "none"))
		print("\n".join(out))
	quit()


## One fight on run `r` as the sim plays it (deploy, gear, AI both sides): won?
func _fight(r: BWRun, n: int, weather: String = "?") -> bool:
	var deployed := _deploy(r)
	_gear(r, deployed)
	var enemies := r.enemies_for(n)
	r.prepare_for_battle(deployed)
	var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % r.map_for(n)), r.seed_value * 31 + n)
	b.set_weather(BWWeather.for_fight(r, n) if weather == "?" else weather)   # D254
	b.setup(deployed, enemies, [])
	var guard := 0
	while not b.over and guard < 1500:
		BWAI.take_turn(b)
		guard += 1
	return b.winner == "player"


## " · std 80% (10) · hard 50% (2)": the win rate per room kind played at fight n.
static func _room_rates(by_room: Dictionary, n: int) -> String:
	var parts: PackedStringArray = []
	for kind in ["standard", "hard", "shadow"] + BWEncounters.KINDS.map(func(k): return "enc:" + k):
		var wp: Array = by_room.get("%d|%s" % [n, kind], [0, 0])
		if wp[1] > 0:
			parts.append("%s %3d%% (%d)" % [{ "standard": "std", "hard": "hard", "shadow": "hard (paired)" }.get(kind, kind.substr(4)), 100 * wp[0] / wp[1], wp[1]])
	return "   " + " · ".join(parts)


## The three highest-level units (ties: most HP), as a player would.
func _deploy(run: BWRun) -> Array:
	var s := run.squad.duplicate()
	s.sort_custom(func(a, b): return a.level > b.level or (a.level == b.level and a.max_hp() > b.max_hp()))
	return s.slice(0, run.deploy_for(run.fight))         # D319: the map's count (6 on a big map)


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
		# D180/D193: carry the best weapon of another class the unit has expertise in
		var cur2: Dictionary = u.equipment.get(BWUnit.SECOND, {})
		var best2: Dictionary = {}
		var best2_v := _value(cur2)
		for it in run.inventory:
			if _slot_of(it) != "main_hand" or str(it.weight) == u.weapon_class or u.expertise_rank(str(it.weight)) < 1:
				continue
			if _value(it) > best2_v:
				best2 = it
				best2_v = _value(it)
		if not best2.is_empty():
			run.equip(u, best2, BWUnit.SECOND)


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
