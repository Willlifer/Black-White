class_name BWCastle
extends RefCounted
## D335-D342: what Defend the Castle and Storm the Castle share (the two 6v6
## castle modes; design/MAPS.md §13-§14). One castle, two sides: the map
## (tools/castle_maps.py) is a walled keep with a GATE, a curtain wall at
## elevation 3 you can stand on, two breaches onto the wall walk, a moat of
## static water 2 and two braziers (static fire 2) on the berm. Defend
## (`keep.json`, BWCastleDefend) has the keep on the player's side; Storm
## (`stronghold.json`, BWCastleStorm) flips it and the squad attacks.
##
## Shared rules (this file):
##   HEIGHT   on a castle map a blow from higher ground deals +HEIGHT_PCT % per
##            level above the target, at most HEIGHT_MAX levels (D336). Both
##            sides; shown as its own forecast line "High ground".
##   GATE     an objective object (BWObjective) with HP (D337). No dodge, no
##            statuses, no ground damage, never moved (the stone rules). Ranged
##            and element blows work on it. A WOOD gate takes fire x WOOD_FIRE;
##            any gate standing on a glazed hex takes thunder x SHATTER_GATE
##            ("the gate shatters"), on top of the usual glaze Shatter.
##   SCALE    the gate's and the throne's HP are a multiple of the squad's mean
##            max HP, the enemies are built at the squad's level (D341).
##   AI       march(): with nothing to hit from any hex it can reach this turn,
##            a unit walks toward its goal (the gate, then the throne) instead
##            of the nearest foe; the modes' target weights make the gate the
##            enemy's (Defend) or the squad's (Storm) first target.
## Pure rules, no nodes.

const MODES := ["defend", "storm"]
const HEIGHT_PCT := 5.0
const HEIGHT_MAX := 3
const WOOD_FIRE := 1.5
const SHATTER_GATE := 1.5

## D341 tuning (tools/castle_sim.gd EMULT / EHP): a factor on both modes'
## enemy multipliers (BWCastleDefend / BWCastleStorm ENEMY_MULT, ENEMY_HP).
static var ENEMY_MULT := 1.0
static var ENEMY_HP := 1.0
## D357: per mode and fight, a factor on the soldiers' stats and HP (absent =
## 1). D353 puts castle cards at fights 7-10; D341 tuned 8 and 10, and 7 and 9
## measured ~25-40 points harder on campaign squads (castle_sim CFIGHT).
static var FIGHT_MULT := { "defend": { 7: 0.85, 9: 0.87 }, "storm": { 7: 0.8, 8: 0.7, 9: 0.6 } }   # D478: Storm at 8 (35% in whole runs at 1.0)


static func fight_mult(mode: String, n: int) -> float:
	return float(FIGHT_MULT.get(mode, {}).get(n, 1.0))

const HAIR := ["buzzed", "bob", "mullet", "ponytail", "short_mohawk"]


static func mode(b: BWBattle) -> String:
	var m := str(b.board.objective.get("mode", ""))
	return m if m in MODES else ""


static func active(b: BWBattle) -> bool:
	return mode(b) != ""


static func gate_hex(b: BWBattle) -> Vector2i:
	var g: Array = b.board.objective.get("gate", [])
	return Vector2i(int(g[0]), int(g[1])) if g.size() == 2 else BWBattle.NOWHERE


static func hexes(b: BWBattle, key: String) -> Array:
	var out: Array = []
	for p in b.board.objective.get(key, []):
		out.append(Vector2i(int(p[0]), int(p[1])))
	return out


## The fight's object tagged `tag` ("gate", "throne"), standing or broken.
static func object(b: BWBattle, tag: String) -> BWObjective:
	for o in BWObjectives.objects(b, tag):
		return o
	return null


static func gate(b: BWBattle) -> BWObjective:
	return object(b, "gate")


static func is_gate(u: BWUnit) -> bool:
	return u is BWObjective and (u as BWObjective).tag == "gate"


## Mean max HP of the squad on the board (the structures' HP scale, D341).
static func squad_hp(b: BWBattle) -> float:
	var us: Array = b.units.filter(func(u): return u.team == "player")
	if us.is_empty():
		return 150.0
	var t := 0.0
	for u in us:
		t += u.max_hp()
	return t / us.size()


## The gate (D337): kind "iron" (Defend) or "wood" (Storm), HP `hp`.
static func make_gate(b: BWBattle, kind: String, hp: int, allegiance: String) -> BWObjective:
	var wood := kind == "wood"
	var rule := "An objective with HP: no dodge, no statuses, no ground damage."
	if wood:
		rule += " Wood: fire deals x%.1f." % WOOD_FIRE
	rule += " Glazed: thunder shatters it for x%.1f." % SHATTER_GATE
	var o := BWObjective.make("%s_gate" % kind, gate_hex(b), {
		"id": "castle_gate", "name": "The Wooden Gate" if wood else "The Iron Gate", "hp": hp,
		"def": 8, "res": 6, "allegiance": allegiance,
		"hittable": ["enemy"] if allegiance == "player" else ["player"],
		"look": "bright" if wood else "dark", "height": 2.0, "tag": "gate", "dodge": "none",
		"rule": rule,
		"codex": "Oak planks banded in black iron." if wood else "A black iron portcullis in a white stone arch.",
	})
	return o


# ---------------------------------------------------------------- the blow (BWBattle._mods)

## D336/D337: the castle's terms on one blow by `att` (standing at `ap`) on
## `dfn` with element `el`: high ground, wood burning, a glazed gate shattering.
static func mods(b: BWBattle, att: BWUnit, dfn: BWUnit, ap: Vector2i, el: String, out: Array) -> void:
	if not active(b) or att == null or dfn == null:
		return
	var up := b.board.elevation(ap) - b.board.elevation(dfn.pos)
	if up > 0 and not att is BWObjective:
		var lv := mini(up, HEIGHT_MAX)
		out.append({ "stage": "dmg", "value": 1.0 + HEIGHT_PCT * lv / 100.0,
			"label": "High ground (%d above): +%d%%" % [up, int(HEIGHT_PCT * lv)], "tag": "High ground" })
	if not is_gate(dfn):
		return
	if el == "fire" and (dfn as BWObjective).kind == "wood_gate":
		out.append({ "stage": "dmg", "value": WOOD_FIRE,
			"label": "Wood burns: x%.1f" % WOOD_FIRE, "tag": "Burns" })
	if el == "thunder" and b.tiles.is_glazed(dfn.pos):
		out.append({ "stage": "dmg", "value": SHATTER_GATE,
			"label": "The glazed gate shatters: x%.1f" % SHATTER_GATE, "tag": "Shatter" })


# ---------------------------------------------------------------- AI

## D338: a castle turn's movement. If some hex `u` can reach this turn has a
## target (BWAI._best_hex), step there (the usual AI then strikes from it);
## otherwise walk toward `goal` (an object or a hex): the reachable stop with
## the least walking left to it. `goal` null: nothing (the usual AI moves).
## Returns nothing: BWAI's own turn finishes the action.
static func march(b: BWBattle, u: BWUnit, goal: Variant, hold := false) -> void:
	if goal == null or not b.can_move(u):
		return
	# cheap outs (the 6v6 budget): a guard holding its post with a blow in reach
	# strikes from where it stands; a unit already in reach of its goal object
	# strikes it from here (the usual AI picks the blow)
	var here := BWAI._best_target(b, u, u.pos)
	if not here.is_empty() and (hold or (goal is BWUnit and (b.in_range(u, goal)
			or BWHex.distance(u.pos, (goal as BWUnit).pos) > u.move_range() + b.weapon_range(u) + 1))):
		return                                     # (the goal out of reach this turn: no repositioning look)
	var dest := BWAI._best_hex(b, u)
	if not BWAI._best_target(b, u, dest).is_empty():
		if dest != u.pos:
			b.move(u, dest)
		return
	var field: Dictionary = walk_field(b, goal)
	var reach := b.reachable(u)
	var best := u.pos
	var best_d: float = float(field.get(u.pos, 999))
	if hold and best_d <= 0.0:
		return
	var keys := reach.keys()
	keys.sort()
	for h in keys:
		if not reach[h].stop:
			continue
		var d := float(field.get(h, 999)) + float(reach[h].cost) * 0.01
		if d < best_d - 1e-6:
			best_d = d
			best = h
	if best != u.pos:
		b.move(u, best)


## Walking cost from every hex to `goal` (beside an object, or onto a hex),
## terrain and climbs only, cached on the battle.
static func walk_field(b: BWBattle, goal: Variant) -> Dictionary:
	if goal is BWUnit:
		return BWAI.walk_field(b, goal)
	var at: Vector2i = goal
	var key := "_walk_hex_%d_%d" % [at.x, at.y]
	if b.has_meta(key):
		return b.get_meta(key)
	var dist := { at: 0 }
	var frontier: Array = [[0, at]]
	while not frontier.is_empty():
		var idx := 0
		for i in frontier.size():
			if frontier[i][0] < frontier[idx][0]:
				idx = i
		var cur: Array = frontier.pop_at(idx)
		var c: int = cur[0]
		var h: Vector2i = cur[1]
		if c > int(dist.get(h, 1 << 20)):
			continue
		for n in b.board.neighbors(h):
			var sc := b.board.step_cost(n, h, BWBoard.WALK)
			if sc < 0:
				continue
			if c + sc < int(dist.get(n, 1 << 20)):
				dist[n] = c + sc
				frontier.append([c + sc, n])
	b.set_meta(key, dist)
	return dist


# ---------------------------------------------------------------- the enemies (BWRun)

## D341: `count` castle soldiers for fight n at the squad's level: a random
## weapon class (or one of `classes`) and element each, the Standard build's
## curve held near 1 (as an encounter), x `mult` stats, `hp_share` x their own
## HP (each times the ENEMY_* tuning factor). Seeded per run, fight and `key`.
static func soldiers(run: BWRun, n: int, key: String, label: String, count: int, classes: Array,
		hp_share: float, mult: float, mode: String = "") -> Array:
	var bld := BWRooms.enemy_build(n, BWRooms.STANDARD)
	bld.mult = clampf(BWRun.enemy_curve(n).mult, BWEncounters.CURVE_MIN, BWEncounters.CURVE_MAX)
	var lvl := run.squad_level()
	var tier := run.tier_for(int(bld.stage))
	var ranks: Array = BWRun.ENEMY_RANKS[tier]
	var erng := RandomNumberGenerator.new()
	erng.seed = hash("castle|%d|%d|%s" % [run.seed_value, n, key])
	var out: Array = []
	for i in count:
		var pool: Array = classes if not classes.is_empty() else BWRosterGen.CLASSES
		var wc: String = BWRun.active_class(str(pool[erng.randi() % pool.size()]))   # D419: benched -> its stand-in
		var el: String = BWFormulas.ELEMENTS[erng.randi() % BWFormulas.ELEMENTS.size()]
		var u := BWEncounters._unit(run, n, "%s%d" % [key, i + 1], "%s %d" % [label, i + 1], BWEncounters._model(wc, erng), el,
			lvl, tier, ranks, bld, mult * ENEMY_MULT * fight_mult(mode, n), hp_share * ENEMY_HP * fight_mult(mode, n), erng)
		u.cosmetics = { "hair_style": HAIR[erng.randi() % HAIR.size()], "top": BWRosterGen.TOPS[erng.randi() % BWRosterGen.TOPS.size()],
			"bottom": BWRosterGen.BOTTOMS[erng.randi() % BWRosterGen.BOTTOMS.size()],
			"clothing_shade": ["dark", "mid", "light"][erng.randi() % 3], "voice_pitch": 0.85 + 0.3 * erng.randf() }
		out.append(u)
	return out


## Mark `units` as wave `k` (BWObjectives.schedule_wave at setup).
static func as_wave(units: Array, k: int) -> Array:
	for u in units:
		u.set_meta("castle_wave", k)
	return units


static func wave_of(u: BWUnit) -> int:
	return int(u.get_meta("castle_wave", 0))


## The battle's units held for wave k (still on the board at setup).
static func wave_units(b: BWBattle, k: int) -> Array:
	return b.units.filter(func(u): return u.team == "enemy" and wave_of(u) == k)


## D341: a castle fight off a run, for --combat --mode, the castle sim and the
## tests: a squad of six from the roster (seeded order), levelled and geared to
## fight n (the --encounter way), against the mode's own enemies.
## { map, players, enemies, run }.
static func quick_run(p_mode: String, seed_value: int, n: int) -> Dictionary:
	var ids: Array = BWData.table("roster").map(func(r): return str(r.id))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	var run := BWRun.start(ids.slice(0, BWRun.SQUAD), seed_value)
	for u in run.squad:
		BWProgression.level_up(u, n - u.level)
		BWPicks.auto_resolve(u)
		for slot in BWRun.ARMOR_SLOTS:
			var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
			u.equipment[slot] = run.make_item(str(bases[absi(hash(u.id + slot)) % bases.size()].id), run.tier_for(n))
		u.equipment["main_hand"] = run.make_item(u.weapon_model, run.tier_for(n))
		u.sync_weapon()
	run.fight = n
	var players: Array = run.squad.slice(0, 6)
	run.prepare_for_battle(players)
	var storm := p_mode == "storm"
	var enemies: Array = BWCastleStorm.build(run, n) if storm else BWCastleDefend.build(run, n)
	BWKeystones.arm_enemies(enemies, n)
	return { "map": "stronghold" if storm else "keep", "players": players, "enemies": enemies, "run": run }
