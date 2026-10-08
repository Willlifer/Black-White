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
## Prints win rate and rounds per fight, survivors, and the Giant's HP left,
## win rate, mean rounds and player deaths. GIANT_HP=n sets its pool (D485;
## 500 = before D485: the same seeds give a paired before/after).
## D188 room policy, env ROOMS (default standard; "all" runs each in turn):
##   standard  always the Standard room
##   hard      always the Hard room (when there is a choice)
##   mixed     Hard when the squad is healthy: the last fight won with all
##             three deployed standing; else Standard
## SHADOW=1: under "standard", every choice fight is also played in its Hard
## room on a copy of the run (same squad, same day), printed "hard (paired)".
## HARD="stages,levels,mult,armor" overrides the BWRooms Hard knobs (tuning).
## THREE="s1,...,s10" (D385) overrides the 3v3 scales (ENEMY_CURVE column 5).
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
## CASTLE="d_gate,d_mult,d_hp,s_gate,s_mult,s_hp" (D341) overrides the castle modes' knobs.
## SNAPSHOT=<dir> (D341) saves the run and the deployed six before fights 8 and 10
## (the squads tools/castle_sim.gd CAMPAIGN=<dir> replays against each castle mode).
## SIX=1 (D333): at fights 8 and 10 the same squad, same day, also plays each
## 6v6 mode with a shipped map on a copy of the run (paired, off the record);
## printed per mode. STOP_AT=n ends each run after fight n (tuning the early
## fights fast). SPLIT="mult,wind_hp" and HORDE="grunt_mult,grunt_hp,elite_mult[,fella_pct]"
## override the Split Front and Horde knobs (D334, D351).
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
	if OS.get_environment("CASTLE") != "":                 # D341 tuning: "d_gate,d_mult,d_hp,s_gate,s_mult,s_hp"
		var c := OS.get_environment("CASTLE").split(",")
		BWCastleDefend.GATE_HP = float(c[0]); BWCastleDefend.ENEMY_MULT = float(c[1]); BWCastleDefend.ENEMY_HP = float(c[2])
		BWCastleStorm.GATE_HP = float(c[3]); BWCastleStorm.ENEMY_MULT = float(c[4]); BWCastleStorm.ENEMY_HP = float(c[5])
	if OS.get_environment("SPLIT") != "":                  # D334 tuning: "mult,wind_hp"
		var sp := OS.get_environment("SPLIT").split(",")
		BWSplitFront.ENEMY_MULT = float(sp[0])
		if sp.size() > 1:
			BWSplitFront.WIND_HP = int(sp[1])
	if OS.get_environment("HORDE") != "":                  # D334/D351 tuning: "grunt_mult,grunt_hp,elite_mult[,fella_pct]"
		var hp := OS.get_environment("HORDE").split(",")
		BWHordeMode.GRUNT_MULT = float(hp[0]); BWHordeMode.GRUNT_HP = float(hp[1])
		BWHordeMode.ELITE_MULT = float(hp[2])
		if hp.size() > 3:
			BWHordeMode.FELLA_PCT = float(hp[3])
	if OS.get_environment("CURVE") != "":                  # tuning: the ten base-stat multipliers
		var m := OS.get_environment("CURVE").split(",")
		BWRun.curve_override = []
		for i in BWRun.ENEMY_CURVE.size():
			var row: Array = BWRun.ENEMY_CURVE[i].duplicate()
			row[1] = float(m[i])
			BWRun.curve_override.append(row)
	if OS.get_environment("THREE") != "":                  # D385 tuning: the ten 3v3 scales (column 5)
		var th := OS.get_environment("THREE").split(",")
		if BWRun.curve_override.is_empty():
			for i in BWRun.ENEMY_CURVE.size():
				BWRun.curve_override.append(BWRun.ENEMY_CURVE[i].duplicate())
		for i in BWRun.curve_override.size():
			BWRun.curve_override[i][4] = float(th[i])
	if OS.get_environment("ENC_TUNE") != "":               # D212 tuning
		var e := OS.get_environment("ENC_TUNE").split(",")
		BWEncounters.HORDE_MULT = float(e[0]); BWEncounters.HORDE_HP = float(e[1])
		BWEncounters.COLOSSUS_MULT = float(e[2]); BWEncounters.COLOSSUS_HP = float(e[3])
		BWEncounters.BLANK_MULT = float(e[4]); BWEncounters.BEING_MULT = float(e[5])
		if e.size() >= 8:
			BWEncounters.BLANK_HP = float(e[6]); BWEncounters.BEING_HP = float(e[7])
	if OS.get_environment("GIANT_HP") != "":               # D485 tuning: the Giant's pool (500 = before D485)
		BWRun.giant_hp = int(OS.get_environment("GIANT_HP"))
	if OS.get_environment("TWINS") != "":                  # D259 tuning: "hp,mult" for the Twins (fight 7)
		var tw := OS.get_environment("TWINS").split(",")
		BWTwins.TWINS_HP = float(tw[0])
		if tw.size() > 1:
			BWTwins.TWINS_MULT = float(tw[1])
		if tw.size() > 2:                                  # D477: "hp,mult,heal"
			BWTwins.HEAL_PCT = float(tw[2])
	if OS.get_environment("OB_HP") != "":                  # D477 tuning: the Obelisks' shared pool
		BWObelisk.hp_override = int(OS.get_environment("OB_HP"))
	if OS.get_environment("ELVL") != "":                   # tuning: enemy levels per stage
		BWRooms.LEVELS_PER_STAGE = float(OS.get_environment("ELVL"))
	print("Curve: %s, 3v3 scale %s, levels per stage %.2f" % [str((BWRun.curve_override if not BWRun.curve_override.is_empty() else BWRun.ENEMY_CURVE).map(func(r): return r[1])),
		str((BWRun.curve_override if not BWRun.curve_override.is_empty() else BWRun.ENEMY_CURVE).map(func(r): return r[4] if r.size() > 4 else 1.0)), BWRooms.LEVELS_PER_STAGE])
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
		var giant := { "fights": 0, "won": 0, "rounds": 0, "deaths": 0, "deployed": 0, "worst": 0 }   # D485
		var by_room := {}       # D188: "n|kind" -> [wins, played]
		var ks_fights := {}     # D308: keystone -> [wins, fights a deployed holder fought]
		led = { "recs": [], "heal": {}, "dmg": { "player": 0, "enemy": 0 }, "kind": {}, "stall": 0, "long": 0 }   # D473
		for s in runs:
			var rng := RandomNumberGenerator.new()
			var base := int(OS.get_environment("SEED0")) if OS.get_environment("SEED0") != "" else 9000   # D353: shards
			rng.seed = base + s
			var pick := ids.duplicate()
			for i in range(pick.size() - 1, 0, -1):
				var j := rng.randi() % (i + 1)
				var t = pick[i]; pick[i] = pick[j]; pick[j] = t
			pick_rng.seed = (base + s) * 7 + 1               # D473 PICKS=random
			var run := BWRun.start(pick.slice(0, BWRun.SQUAD), base + s)
			run.force_map = OS.get_environment("MAP")         # D319: MAP=commons plays every fight there (6v6)
			for u in run.squad:
				_resolve(u)
			var healthy := true
			var hurt := false                           # D353: lost, or under half the deployed standing
			var alt := { "six": 0, "mix": 0 }          # D353: the sim's alternation over 6v6 cards
			while not run.is_over() and run.fight <= BWRun.BOSS_FIGHT:
				var n := run.fight
				var kind := "standard"
				if BWRooms.has_choice(n):                      # D188: the room policy
					var offered := BWRooms.offer(run)
					var hard := room_pol == "hard" or (room_pol == "mixed" and healthy)
					var ci := _pick_card(offered, hard, not hurt, s, alt)   # D353: boss, 6v6 and mixed offers
					BWRooms.choose(run, ci)
					kind = _card_key(offered[ci])
					hard = str(offered[ci].kind) == BWRooms.HARD
					var std_hard: bool = offered.size() == 2 and str(offered[1].kind) == BWRooms.HARD
					if shadow and not hard and std_hard:
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
					if OS.get_environment("ENC") == "1" and std_hard:
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
				if OS.get_environment("SIX") == "1" and n in BWRun.SIX_FIGHTS:
					# D333: the same squad, same day, against each 6v6 mode (paired, off the record)
					for md in BWRun.SIX_MODES:
						if BWRun.mode_map(md) == BWRun.MODE_PLACEHOLDER:
							continue
						var xr := BWRun.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())))
						xr.mode_override = { n: md }
						var mk := "%d|six:%s" % [n, md]
						var mp: Array = by_room.get(mk, [0, 0])
						by_room[mk] = [mp[0] + (1 if _fight(xr, n) else 0), mp[1] + 1]
				var deployed := _deploy(run)
				_gear(run, deployed)
				if OS.get_environment("SNAPSHOT") != "" and n in BWRun.SIX_FIGHTS:   # D341: squads for tools/castle_sim.gd CAMPAIGN=dir
					var sf := FileAccess.open("%s/%s_r%d_f%d.json" % [OS.get_environment("SNAPSHOT"), pol, base + s, n], FileAccess.WRITE)
					sf.store_string(JSON.stringify({ "run": run.to_dict(), "deployed": deployed.map(func(u): return u.id), "fight": n }))
					sf.close()
				var enemies := run.enemies_for(n)
				run.prepare_for_battle(deployed)
				var mname := run.map_for(n)
				played[n - 1][mname] = int(played[n - 1].get(mname, 0)) + 1
				var b := BWBattle.new(BWBoard.load_file("res://maps/%s.json" % mname), run.seed_value * 31 + n)
				b.set_weather(BWWeather.for_fight(run, n))          # D249: the room's weather
				BWObjectives.configure(b, BWRooms.battle_opts(run, n))   # D354: the card's divider
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
				_ledger(b, deployed, won, n, kind, guard >= 1500)   # D473
				if won:
					wins[n - 1] += 1
				rounds[n - 1].append(b.cycle)
				alive[n - 1] += deployed.filter(func(u): return u.alive()).size()
				healthy = won and deployed.all(func(u): return u.alive())
				hurt = not won or deployed.filter(func(u): return u.alive()).size() * 2 < deployed.size()
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
					giant.fights += 1
					giant.won += 1 if won else 0
					giant.rounds += b.cycle
					giant.worst = maxi(int(giant.worst), b.cycle)
					giant.deployed += deployed.size()
					giant.deaths += deployed.filter(func(u): return not u.alive()).size()
				var defeated := enemies.filter(func(e): return not e.alive())
				run.after_fight(won, deployed, defeated, enemies, b.history)
				for u in run.squad:
					u.hp = u.max_hp()
					_resolve(u)
				if n >= BWRun.BOSS_FIGHT or (OS.get_environment("STOP_AT") != "" and n >= int(OS.get_environment("STOP_AT"))):
					break
				var plan: Array = []
				for i in run.squad.size():
					plan.append([run.squad[i].id, choice_for(pol, i, run.day_choices(run.squad[i]))])
				run.progress_day(plan)
				for u in run.squad:
					_resolve(u)
		var out: PackedStringArray = ["POLICY %s, ROOMS %s (%d runs)" % [pol, room_pol, runs]]
		for f in BWRun.BOSS_FIGHT:
			var r: Array = rounds[f]
			r.sort()
			out.append("  fight %2d %-9s  win %3d%%  rounds med %2d  survivors %.1f%s" % [f + 1,
				"(Giant)" if f + 1 == BWRun.BOSS_FIGHT else "(%s)" % _maps_label(played[f]),
				100 * wins[f] / maxi(r.size(), 1), r[r.size() / 2] if r.size() > 0 else 0,
				float(alive[f]) / maxf(r.size(), 1), _room_rates(by_room, f + 1)])
		out.append("  by card (fights 1-10, as played): " + _card_rates(by_room))   # D353
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
		if OS.get_environment("SIX") == "1":
			for md in BWRun.SIX_MODES:
				var row: PackedStringArray = []
				var tw := 0
				var tp := 0
				for f in BWRun.SIX_FIGHTS:
					var wp: Array = by_room.get("%d|six:%s" % [f, md], [0, 0])
					if wp[1] > 0:
						row.append("%d:%3d%% (%d)" % [f, 100 * wp[0] / wp[1], wp[1]])
						tw += wp[0]
						tp += wp[1]
				if tp > 0:
					out.append("  six %-8s (paired) %3d%% (%d)   %s" % [md, 100 * tw / tp, tp, "  ".join(row)])
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
		out.append("  Giant HP left (of %d): %s" % [BWRun.giant_hp, str(boss_left)])
		var gf := maxf(float(giant.fights), 1.0)
		out.append("  Giant (D485, %d HP): win %d%% (%d)  mean rounds %.1f (max %d)  player deaths %.2f of %.1f deployed" % [BWRun.giant_hp,
			roundi(100.0 * giant.won / gf), giant.fights, giant.rounds / gf, giant.worst, giant.deaths / gf, giant.deployed / gf])
		var kids: Array = ks_fights.keys()
		kids.sort_custom(func(a, c): return int(ks_fights[a][1]) > int(ks_fights[c][1]))
		var krow: PackedStringArray = []
		for kid in kids:
			var kp: Array = ks_fights[kid]
			krow.append("%s %d%% (%d)" % [BWKeystones.name_of(str(kid)), 100 * int(kp[0]) / maxi(int(kp[1]), 1), int(kp[1])])
		out.append("  keystones (squad, fights 1-10 with a deployed holder): " + (", ".join(krow) if not krow.is_empty() else "none"))
		out.append_array(_ledger_report())                   # D473
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
	BWObjectives.configure(b, BWRooms.battle_opts(r, n))   # D354
	b.setup(deployed, enemies, [])
	var guard := 0
	while not b.over and guard < 1500:
		BWAI.take_turn(b)
		guard += 1
	return b.winner == "player"


## D353 the sim's card policy: Standard / Hard offers keep the ROOMS policy
## (`hard`); a boss offer alternates by run (env BOSS=obelisks|twins pins it);
## two 6v6 cards alternate within the run (offset by run); a 3v3 card against a
## 6v6 card: the 3v3 when hurt (the last fight lost or a unit down), else
## alternate (offset by run).
func _pick_card(offered: Array, hard: bool, healthy: bool, s: int, alt: Dictionary) -> int:
	var kinds: Array = offered.map(func(c): return str(c.kind))
	if kinds == [BWRooms.STANDARD, BWRooms.HARD]:
		return 1 if hard else 0
	if BWRooms.BOSS in kinds:
		var pin := OS.get_environment("BOSS")
		if pin != "":
			return maxi(0, offered.map(func(c): return str(c.get("boss", ""))).find(pin))
		return s % 2
	var six: Array = []
	for i in offered.size():
		if kinds[i] == BWRooms.SIX:
			six.append(i)
	if six.size() == offered.size():
		alt.six = int(alt.six) + 1
		return (s + int(alt.six)) % offered.size()
	if not healthy:
		return kinds.find(BWRooms.STANDARD)
	alt.mix = int(alt.mix) + 1
	return int(six[0]) if (s + int(alt.mix)) % 2 == 1 else kinds.find(BWRooms.STANDARD)


## D353 card keys: standard / hard, the boss (obelisks / twins), or a 6v6
## card's mode (a Split Front card its map: splitfront / fords).
const CARD_KEYS := ["obelisks", "twins", "splitfront", "fords", "defend", "storm", "horde"]


static func _card_key(c: Dictionary) -> String:
	match str(c.kind):
		BWRooms.BOSS:
			return str(c.boss)
		BWRooms.SIX:
			return str(c.map) if str(c.mode) == "splitfront" else str(c.mode)
	return str(c.kind)


## Win rate per card key over every fight it was played at.
static func _card_rates(by_room: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in ["standard", "hard"] + CARD_KEYS:
		var w := 0
		var p := 0
		for f in range(1, BWRun.FIGHTS + 1):
			var wp: Array = by_room.get("%d|%s" % [f, key], [0, 0])
			w += int(wp[0])
			p += int(wp[1])
		if p > 0:
			parts.append("%s %d%% (%d)" % [key, 100 * w / p, p])
	return " · ".join(parts)


## " · std 80% (10) · hard 50% (2)": the win rate per room kind played at fight n.
static func _room_rates(by_room: Dictionary, n: int) -> String:
	var parts: PackedStringArray = []
	for kind in ["standard", "hard", "shadow"] + CARD_KEYS + BWEncounters.KINDS.map(func(k): return "enc:" + k):
		var wp: Array = by_room.get("%d|%s" % [n, kind], [0, 0])
		if wp[1] > 0:
			parts.append("%s %3d%% (%d)" % [{ "standard": "std", "hard": "hard", "shadow": "hard (paired)" }.get(kind, kind.substr(4) if kind.begins_with("enc:") else kind), 100 * wp[0] / wp[1], wp[1]])
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


# ---------------------------------------------------------------- D473 ledger

## D473 PICKS=random: every pick (perk, keystone, duo, skill) takes a random
## unowned card (seeded per run) instead of BWPicks.auto_choice's first card,
## so every keystone and duo perk gets measured (the first card is always the
## element's first keystone, and a duo perk is never the first card).
var pick_rng := RandomNumberGenerator.new()


func _resolve(u: BWUnit) -> void:
	if OS.get_environment("PICKS") != "random":
		BWPicks.auto_resolve(u)
		return
	for guard in 64:
		BWPicks.settle(u)
		var p := BWPicks.pending(u)
		if p.is_empty():
			break
		var req: Dictionary = p[0]
		var choice := ""
		if req.has("ai"):
			choice = str(req.ai)
		else:
			var opts: Array = BWPicks.options(u, req).filter(func(o): return not o.owned)
			if not opts.is_empty():
				choice = str(opts[pick_rng.randi() % opts.size()].id)
		if BWPicks.apply(u, req, choice).is_empty():
			break


## D473 the balance ledger: per fight (1-11, as played) the card, the result,
## the rounds, and what the deployed side brought (focus elements, weapon
## classes, keystones, duo perks); the healing by source against the HP lost
## (both sides, BWBattleStats' "taken"), shields soaked, Hopekiller's turned
## heals, and stalls (the 1500-turn guard) and long fights (20+ rounds).
## LEDGER_OUT=<file> also writes the raw records as JSON (merging shards).
var led := {}


func _ledger(b: BWBattle, deployed: Array, won: bool, n: int, kind: String, stalled: bool) -> void:
	var keys := {}
	for u in deployed:
		keys["el:" + u.focus()] = true
		keys["wc:" + u.weapon_class] = true
		for kid in u.keystones:
			keys["ks:" + str(kid)] = true
		for pid in u.perks:
			var row := BWData.row("perks", str(pid))
			if not row.is_empty() and str(row.get("duo", "")) != "":
				keys["duo:" + str(pid)] = true
	var card := "giant" if n == BWRun.BOSS_FIGHT else ("opener" if n <= 2 else kind)
	var team := {}
	var real := {}
	for u in b.units:
		team[u.id] = u.team
		real[u.id] = not BWObelisk.is_objective(u)
	var t := BWBattleStats.tally(b.history, b.units)
	var dmg := { "player": 0, "enemy": 0 }
	for id in t.units:
		if real.get(id, false) and dmg.has(str(team[id])):
			dmg[str(team[id])] += int(t.units[id].taken)
	var heal := {}
	var ward_name := {}
	var evs := {}               # counted event kinds, self-damage by cause, skill uses
	var ov := ""                # the unit whose Overload is resolving
	for e in b.history:
		var src := ""
		var amt := 0
		var who := str(e.get("unit", ""))
		var ty := str(e.get("type", ""))
		if ty in ["fizzle", "la_nina", "rain", "submerge", "shatterer", "superconductor", "overflow", "hopekiller", "overload"]:
			_led_add(evs, "ev:" + ty, who, team, 1)
		match ty:
			"turn":
				ov = ""
			"overload":
				ov = who
			"leviathan_form":
				_led_add(evs, "ev:form " + str(e.get("form", "")), who, team, 1)
			"skill":
				_led_add(evs, "use:" + str(e.skill), who, team, 1)
				if str(team.get(who, "")) == "player":
					keys["sk:" + str(e.skill)] = true
			"tile_damage":
				if str(e.get("source", "")) == who and who != "":
					var c := str(e.get("cause", ""))
					_led_add(evs, "self:" + ("overload" if who == ov and c == "detonation" else c), who, team, int(e.amount))
		match ty:
			"heal":
				amt = int(e.amount)
				var c := str(e.get("cause", "?"))
				if c == "light":
					var tag := str(e.get("tag", "plain"))
					src = "light (Judicator)" if "judicator" in tag else ("light (Solar Wind)" if "solar_wind" in tag else "light tile")
					if "foe" in tag:
						_led_add(heal, "  of which on a foe's light", who, team, amt)
					if "stay" in tag:
						_led_add(heal, "  of which unmoved (same hex as last turn)", who, team, amt)
				else:
					src = _enchant_key(c)
			"light_ward":
				ward_name[who] = str(e.get("name", "Ward of Light"))
			"light_ward_break":
				amt = int(e.absorbed)
				src = "shield: " + str(ward_name.get(who, "Ward of Light"))
			"barrier_hit":
				amt = int(e.absorbed)
				src = "shield: Consume barrier"
			"hopekiller":
				_led_add(heal, "(Hopekiller: heals turned to harm)", who, team, int(e.amount))
		if src != "" and amt > 0 and real.get(who, true):
			_led_add(heal, src, who, team, amt)
	led.recs.append({ "n": n, "card": card, "won": won, "rounds": b.cycle, "keys": keys.keys(), "dmg": dmg, "heal": heal,
		"stall": stalled, "evs": evs })


## "enchant:Leeching Recurve Bow" -> "enchant:Leeching {item}" (one row per enchantment).
static func _enchant_key(c: String) -> String:
	if not c.begins_with("enchant:"):
		return c
	var name := c.substr(8)
	for r in BWData.table("equipment"):
		var n := str(r.name)
		if n != "" and name.contains(n):
			return "enchant:" + name.replace(n, "{item}")
	return c


func _led_add(heal: Dictionary, src: String, who: String, team: Dictionary, amt: int) -> void:
	var k := "%s|%s" % [src, str(team.get(who, "?"))]
	heal[k] = int(heal.get(k, 0)) + amt


func _ledger_report() -> PackedStringArray:
	var path := OS.get_environment("LEDGER_OUT")
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(led.recs))
		f.close()
	return ledger_lines(led.recs)


## The report from a list of fight records (one sim, or merged shards).
static func ledger_lines(recs: Array) -> PackedStringArray:
	var out: PackedStringArray = ["  --- D473 ledger (%d fights) ---" % recs.size()]
	var kind := {}
	var byf := {}
	var pn := {}
	var heal := {}
	var dmg := { "player": 0, "enemy": 0 }
	var stall := 0
	var longf := 0
	for r in recs:
		var hsum := 0
		for k in r.heal:
			heal[k] = int(heal.get(k, 0)) + int(r.heal[k])
			if not str(k).begins_with(" ") and not str(k).begins_with("("):
				hsum += int(r.heal[k])
		var d := int(r.dmg.player) + int(r.dmg.enemy)
		dmg.player += int(r.dmg.player)
		dmg.enemy += int(r.dmg.enemy)
		var kp: Array = kind.get(str(r.card), [0, 0, 0, 0, 0])   # heal, dmg, fights, rounds, wins
		kind[str(r.card)] = [kp[0] + hsum, kp[1] + d, kp[2] + 1, kp[3] + int(r.rounds), kp[4] + (1 if r.won else 0)]
		var f: Array = byf.get(int(r.n), [0, 0, 0])
		byf[int(r.n)] = [f[0] + (1 if r.won else 0), f[1] + 1, f[2] + int(r.rounds)]
		stall += 1 if r.get("stall", false) else 0
		longf += 1 if int(r.rounds) >= 20 else 0
	out.append("  card        fights  win%  rounds(mean)  heal+shield / HP lost")
	for c in ["opener", "standard", "hard", "obelisks", "twins", "splitfront", "fords", "defend", "storm", "horde", "giant"]:
		if kind.has(c):
			var k: Array = kind[c]
			out.append("  %-11s %5d  %4d  %6.1f  %5.1f%%" % [c, k[2], roundi(100.0 * k[4] / k[2]), float(k[3]) / k[2], 100.0 * k[0] / maxf(k[1], 1)])
	var fl: PackedStringArray = []
	for n in range(1, BWRun.BOSS_FIGHT + 1):
		if byf.has(n):
			pn[n] = float(byf[n][0]) / byf[n][1]
			fl.append("%d: %d%% %.1fr (%d)" % [n, roundi(100.0 * pn[n]), float(byf[n][2]) / byf[n][1], byf[n][1]])
	out.append("  by fight (win, mean rounds, n): " + " | ".join(fl))
	out.append("  stalls (1500-turn guard) %d, fights of 20+ rounds %d" % [stall, longf])
	var tot := { "player": 0, "enemy": 0 }
	var srcs := {}
	for k in heal:
		var p: PackedStringArray = str(k).split("|")
		srcs[p[0]] = true
		if not p[0].begins_with(" ") and not p[0].begins_with("(") and tot.has(p[1]):
			tot[p[1]] += int(heal[k])
	out.append("  healing+shields / HP lost: player %d / %d (%.1f%%), enemy %d / %d (%.1f%%)" % [tot.player, dmg.player,
		100.0 * tot.player / maxf(dmg.player, 1), tot.enemy, dmg.enemy, 100.0 * tot.enemy / maxf(dmg.enemy, 1)])
	var sl: Array = srcs.keys()
	sl.sort_custom(func(a, c): return int(heal.get(a + "|player", 0)) + int(heal.get(a + "|enemy", 0)) > int(heal.get(c + "|player", 0)) + int(heal.get(c + "|enemy", 0)))
	for s in sl:
		var hp := int(heal.get(s + "|player", 0))
		var he := int(heal.get(s + "|enemy", 0))
		out.append("    %-44s player %6d (%4.1f%%)  enemy %6d (%4.1f%%)" % [s, hp, 100.0 * hp / maxf(dmg.player, 1), he, 100.0 * he / maxf(dmg.enemy, 1)])
	var evs := {}
	for r in recs:
		for k in r.get("evs", {}):
			evs[k] = int(evs.get(k, 0)) + int(r.evs[k])
	var el: Array = evs.keys()
	el.sort()
	var evl: PackedStringArray = []
	for k in el:
		if not str(k).begins_with("use:"):
			evl.append("%s %d" % [k, evs[k]])
	out.append("  events / self-damage (key|side total): " + ", ".join(evl))
	var ul: Array = el.filter(func(k): return str(k).begins_with("use:") and str(k).ends_with("|player"))
	ul.sort_custom(func(a, c): return int(evs[a]) > int(evs[c]))
	out.append("  player skill uses: " + ", ".join(ul.map(func(k): return "%s %d" % [str(k).substr(4).trim_suffix("|player"), evs[k]])))
	var cnt := {}
	var n10 := 0
	var w10 := 0
	for r in recs:
		if int(r.n) >= BWRun.BOSS_FIGHT:
			continue
		n10 += 1
		w10 += 1 if r.won else 0
		for k in r.keys:
			var c: Array = cnt.get(k, [0, 0, 0.0])
			cnt[k] = [c[0] + 1, c[1] + (1 if r.won else 0), c[2] + ((1.0 if r.won else 0.0) - float(pn.get(int(r.n), 0.0)))]
	var ks: Array = cnt.keys()
	ks.sort()
	out.append("  picks (fights 1-10: %d, %d%% won): key  fights-with (share)  win%% with / without  vs-fight-avg" % [n10, roundi(100.0 * w10 / maxf(n10, 1))])
	for k in ks:
		var c: Array = cnt[k]
		var wo_n: int = n10 - int(c[0])
		var wo_w: int = w10 - int(c[1])
		out.append("    %-26s %4d (%3d%%)  %3d%% / %4s  %+5.1f" % [k, c[0], roundi(100.0 * c[0] / maxf(n10, 1)), roundi(100.0 * c[1] / c[0]),
			("%d%%" % roundi(100.0 * wo_w / wo_n)) if wo_n > 0 else "-", 100.0 * float(c[2]) / c[0]])
	return out
