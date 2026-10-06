class_name BWBattleStats
extends RefCounted
## The end-of-battle summary (D119–D121), tallied from a finished
## BWBattle.history. Pure: no nodes, no battle object, just the event list
## and the units that fought (for names, teams and starting HP).
##
## tally(history, units) -> {
##   winner, rounds,
##   units: { id: { id, name, team, element, weapon_class,
##            dealt: { basic, skill, ground, chain }, dealt_total,
##            taken, kos, crits, misses, attempts, healed, statuses,
##            wards, downed, score, best_hit } },
##   order: [ids, player side first, in the order given],
##   mvp: id ("" if nobody on the player side scored),
##   highlights: [{ kind, unit, text, value, score }] (best first, ≤ 3),
##   wrong: "" or one factual line (only when the player side lost),
## }
##
## Damage is counted as HP actually lost: a blow that knocks out a unit on
## 9 HP counts 9, whatever it rolled (overkill is dropped), so a unit's
## `taken` minus its `healed` is exactly the HP it lost. A move undone
## (D48) takes back the damage its crossing did. Buckets (D119):
##   basic  = basic attacks and counters (the weapon's own swing)
##   skill  = skills, their extra strikes, ripostes
##   ground = tiles (fire, dark, steam, erupt, slam), detonations included
##   chain  = arcs on conductive ground
## Dealt counts only damage to the other side; friendly fire is still
## `taken` by its victim. Highlights and the MVP read the player side.

const BUCKETS := ["basic", "skill", "ground", "chain"]
const TEAM := "player"

## MVP score (D120): damage dealt + KO_PTS per knockout + STATUS_PTS per
## status inflicted on a foe + WARD_PTS per ward of yours that caught a blow.
const KO_PTS := 20
const STATUS_PTS := 4
const WARD_PTS := 15

## Highlight scores (D120): the biggest number wins its kind, and kinds are
## compared on these scales so a 30-point detonation can beat a 32 hit.
const DET_MULT := 1.25       # a detonation total counts 1.25× a hit
const ARC_BONUS := 6         # per arc beyond the first
const CLUTCH_PCT := 30       # a KO by a unit at or under 30% HP is clutch
const CLUTCH_BASE := 30
const WARD_SCORE := 24
const MAX_HIGHLIGHTS := 3


static func tally(history: Array, units: Array) -> Dictionary:
	var info := {}           # id -> { name, team, max, element, weapon_class }
	var order: Array = []
	for u in units:
		info[u.id] = { "name": u.name, "team": u.team, "max": u.max_hp(), "element": u.element,
			"weapon_class": u.weapon_class }
	for team in [TEAM, ""]:
		for u in units:
			if (team == TEAM) == (u.team == TEAM):
				order.append(u.id)
	var hp := {}
	for id in info:
		hp[id] = int(info[id].max)
	# Every countable thing becomes a record with its event index, so an
	# undo can take back what happened after the move it undoes.
	var recs: Array = []
	var marks := {}          # unit id -> recs.size() at its last undoable move
	var last_paint := -1
	var anchor := -1
	var winner := ""
	var rounds := 0
	for i in history.size():
		var e: Dictionary = history[i]
		var t := str(e.get("type", ""))
		rounds = maxi(rounds, int(e.get("cycle", 0)))
		match t:
			"move":
				var k := str(e.get("kind", ""))
				if k == "" or k == "flow":
					marks[str(e.unit)] = recs.size()
			"undo_move":
				var m := int(marks.get(str(e.unit), recs.size()))
				recs.resize(mini(m, recs.size()))
				hp[str(e.unit)] = int(e.hp)
			"attack", "counter":
				var cat := "skill" if e.has("skill") else "basic"
				var what: String
				if e.has("skill"):
					what = _skill_name(str(e.skill))
				elif t == "counter":
					what = str(e.get("name", "counter"))
					if what == "":
						what = "counter"
				else:
					what = "basic attack"
				_blow(recs, hp, i, str(e.unit), str(e.target), e.result, int(e.target_hp), cat, what)
			"skill":
				for r in e.get("results", []):
					_blow(recs, hp, i, str(e.unit), str(r.target), r.result, int(r.target_hp), "skill", _skill_name(str(e.skill)))
			"riposte":
				for r in e.get("results", []):
					_blow(recs, hp, i, str(e.unit), str(r.target), r.result, int(r.target_hp), "skill", "Riposte")
			"tile_damage":
				var v := str(e.unit)
				var amt := _eff(hp, v, int(e.amount), int(e.hp))
				var cause := str(e.get("cause", ""))
				recs.append({ "k": "dmg", "i": i, "src": str(e.get("source", "")), "dst": v, "amt": amt,
					"raw": int(e.amount), "cat": "ground", "cause": cause,
					"grp": last_paint if cause == "detonation" else -1 })
			"chain":
				var v := str(e.to)
				var amt := _eff(hp, v, int(e.amount), int(e.hp))
				recs.append({ "k": "dmg", "i": i, "src": str(e.get("by", "")), "dst": v, "amt": amt,
					"raw": int(e.amount), "cat": "chain", "grp": anchor })
			"heal":
				var v := str(e.unit)
				hp[v] = int(e.hp)
				recs.append({ "k": "heal", "i": i, "dst": v, "amt": int(e.amount) })
			"status":
				recs.append({ "k": "status", "i": i, "src": str(e.get("by", "")), "dst": str(e.unit) })
			"ko":
				var by := str(e.get("by", ""))
				var at := int(hp.get(by, 0))
				recs.append({ "k": "ko", "i": i, "src": by, "dst": str(e.unit), "src_hp": at })
			"ward_break":
				var src := str(e.get("by", e.unit)) if str(e.get("source", "")) == "frost_ward" else str(e.unit)
				recs.append({ "k": "ward", "i": i, "src": src, "dst": str(e.unit), "what": str(e.get("what", "")),
					"how": str(e.get("source", "")) })
			"paint":
				last_paint = i
			"battle_end":
				winner = str(e.get("winner", ""))
		if not t in ["chain", "ko", "growth", "status", "heal", "ward_break", "stat_up", "perk", "status_resisted"]:
			anchor = i
	return _sum(recs, info, order, winner, rounds)


## One blow (attack, counter, a skill's or riposte's result): its attempt,
## and its damage as HP lost.
static func _blow(recs: Array, hp: Dictionary, i: int, src: String, dst: String, res: Dictionary,
		after: int, cat: String, what: String) -> void:
	var dmg := int(res.get("damage", 0))
	var amt := _eff(hp, dst, dmg, after)
	recs.append({ "k": "dmg", "i": i, "src": src, "dst": dst, "amt": amt, "raw": dmg, "cat": cat,
		"hit": bool(res.get("hit", false)), "crit": bool(res.get("crit", false)), "what": what, "blow": true,
		"grp": -1 })


## HP actually lost: the roll, unless it knocked the unit out (then what
## it had left). Keeps the running HP.
static func _eff(hp: Dictionary, v: String, dmg: int, after: int) -> int:
	var before := int(hp.get(v, dmg))
	hp[v] = after
	if after > 0:
		return dmg
	return clampi(before, 0, dmg)


static func _skill_name(key: String) -> String:
	var row := BWSkills.get_skill(key)
	return str(row.get("name", key.capitalize())) if not row.is_empty() else key.capitalize()


static func _sum(recs: Array, info: Dictionary, order: Array, winner: String, rounds: int) -> Dictionary:
	var u := {}
	for id in info:
		var dealt := {}
		for b in BUCKETS:
			dealt[b] = 0
		u[id] = { "id": id, "name": info[id].name, "team": info[id].team, "element": info[id].element,
			"weapon_class": info[id].weapon_class, "max_hp": int(info[id].max),
			"dealt": dealt, "dealt_total": 0, "taken": 0, "kos": 0, "crits": 0, "misses": 0, "attempts": 0,
			"healed": 0, "statuses": 0, "wards": 0, "downed": false, "score": 0, "best_hit": 0 }
	var cands: Array = []        # highlight candidates
	var dets := {}               # paint index -> { src, amt, hit: [names] }
	var arcs := {}               # anchor index -> { src, amt, n }
	for r in recs:
		var s: Dictionary = u.get(r.get("src", ""), {})
		var d: Dictionary = u.get(r.get("dst", ""), {})
		var foe: bool = not s.is_empty() and not d.is_empty() and s.team != d.team
		match r.k:
			"dmg":
				if not d.is_empty():
					d.taken += int(r.amt)
				if r.get("blow", false) and not s.is_empty() and foe:
					s.attempts += 1
					if not r.hit:
						s.misses += 1
					elif r.crit:
						s.crits += 1
				if foe:
					s.dealt[r.cat] += int(r.amt)
					s.dealt_total += int(r.amt)
					if r.get("blow", false) and r.hit:
						s.best_hit = maxi(int(s.best_hit), int(r.raw))
						if s.team == TEAM:
							cands.append({ "kind": "hit", "unit": s.id, "value": int(r.raw), "score": float(r.raw),
								"text": "%s's %s%s on %s, %d" % [s.name, r.what, " crit" if r.crit else "", d.name, int(r.raw)] })
					if r.get("cause", "") == "detonation" and s.team == TEAM:
						var g: Dictionary = dets.get(r.grp, { "src": s.id, "amt": 0, "hit": [] })
						g.amt += int(r.raw)
						g.hit.append(d.name)
						dets[r.grp] = g
					if r.cat == "chain" and s.team == TEAM:
						var a: Dictionary = arcs.get(r.grp, { "src": s.id, "amt": 0, "n": 0 })
						a.amt += int(r.raw)
						a.n += 1
						arcs[r.grp] = a
			"heal":
				if not d.is_empty():
					d.healed += int(r.amt)
			"status":
				if foe:
					s.statuses += 1
			"ko":
				if not d.is_empty():
					d.downed = true
				if foe:
					s.kos += 1
					var pct := 100.0 * float(r.src_hp) / maxf(1.0, float(s.max_hp))
					if s.team == TEAM and r.src_hp > 0 and pct <= CLUTCH_PCT:
						cands.append({ "kind": "clutch", "unit": s.id, "value": int(r.src_hp),
							"score": CLUTCH_BASE + (CLUTCH_PCT - pct),
							"text": "%s, on %d HP, knocked out %s" % [s.name, int(r.src_hp), d.name] })
			"ward":
				if not s.is_empty() and not d.is_empty() and s.team == d.team:
					s.wards += 1
					if s.team == TEAM:
						var what := str(r.what).replace("status:", "").replace("_", " ")
						if what == "fire cross":
							what = "fire"
						var txt := ("%s's Frost Ward caught the %s meant for %s" % [s.name, what, d.name]) if s.id != d.id \
							else ("%s's %s shrugged off the %s" % [s.name, "Frost Ward" if r.how == "frost_ward" else "Nightborn", what])
						cands.append({ "kind": "ward", "unit": s.id, "value": 1, "score": WARD_SCORE, "text": txt })
	for g in dets.values():
		var s: Dictionary = u[g.src]
		var who: String = g.hit[0] if g.hit.size() == 1 else "%d foes" % g.hit.size()
		cands.append({ "kind": "detonation", "unit": g.src, "value": int(g.amt), "score": g.amt * DET_MULT,
			"text": "%s's detonation hit %s for %d" % [s.name, who, int(g.amt)] })
	for a in arcs.values():
		var s: Dictionary = u[a.src]
		cands.append({ "kind": "chain", "unit": a.src, "value": int(a.amt), "score": a.amt + ARC_BONUS * (a.n - 1),
			"text": ("%s's arc jumped %d times for %d" % [s.name, int(a.n), int(a.amt)]) if a.n > 1
				else "%s's arc for %d" % [s.name, int(a.amt)] })
	# MVP (D120)
	var mvp := ""
	for id in order:
		var s: Dictionary = u[id]
		s.score = int(s.dealt_total) + KO_PTS * int(s.kos) + STATUS_PTS * int(s.statuses) + WARD_PTS * int(s.wards)
		if s.team == TEAM and s.score > 0 and (mvp == "" or s.score > u[mvp].score):
			mvp = id
	return { "winner": winner, "rounds": rounds, "units": u, "order": order, "mvp": mvp,
		"highlights": pick_highlights(cands, MAX_HIGHLIGHTS), "wrong": _wrong(u, order) if winner != TEAM and winner != "" else "" }


## The best candidates, one per kind, best first.
static func pick_highlights(cands: Array, n: int) -> Array:
	var c := cands.duplicate()
	c.sort_custom(func(a, b): return a.score > b.score)
	var out: Array = []
	var kinds := {}
	for h in c:
		if kinds.has(h.kind):
			continue
		kinds[h.kind] = true
		out.append(h)
		if out.size() >= n:
			break
	return out


## D121: one factual line on a loss, the first that applies:
## a unit that took half or more of the enemy's damage, an enemy nobody
## damaged, a miss rate of 40%+ (5+ swings), else the damage totals.
static func _wrong(u: Dictionary, order: Array) -> String:
	var mine: Array = order.filter(func(id): return u[id].team == TEAM)
	var theirs: Array = order.filter(func(id): return u[id].team != TEAM)
	if mine.is_empty():
		return ""
	var enemy_dmg := 0
	var our_dmg := 0
	for id in theirs:
		enemy_dmg += int(u[id].dealt_total)
	for id in mine:
		our_dmg += int(u[id].dealt_total)
	if mine.size() >= 2 and enemy_dmg > 0:
		var top: String = mine[0]
		for id in mine:
			if u[id].taken > u[top].taken:
				top = id
		var share := float(u[top].taken) / float(enemy_dmg)
		if share >= 0.5:
			return "%s took %d%% of the enemy's damage." % [u[top].name, mini(100, roundi(share * 100.0))]
	for id in theirs:
		if int(u[id].taken) == 0:
			return "No one landed a hit on their %s (%s)." % [u[id].weapon_class, u[id].name] if u[id].weapon_class != "" \
				else "No one landed a hit on %s." % u[id].name
	var tries := 0
	var missed := 0
	for id in mine:
		tries += int(u[id].attempts)
		missed += int(u[id].misses)
	if tries >= 5 and float(missed) / tries >= 0.4:
		return "%d of %d swings missed." % [missed, tries]
	return "The enemy dealt %d damage; the squad dealt %d." % [enemy_dmg, our_dmg]
