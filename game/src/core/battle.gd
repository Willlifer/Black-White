class_name BWBattle
extends RefCounted
## One fight, as pure rules. No nodes, no timing, no drawing.
##
## The presentation drives it (move/attack/end_turn) and replays the event
## list it produces; the self-test drives it headless with the same calls.
## Every random roll comes from `rng`, so a seed reproduces a fight exactly.
##
## Turn shape (brief): a unit may move then act, or act then move. Each is
## spent once per turn; end_turn() passes to the next unit in speed order.
## When the queue runs out a new cycle starts.
##
## Equipment effects (BWEffects, design/EQUIPMENT.md) enter at the lines
## marked "FX hook:", each naming the effect_keys it serves. A rule with no
## effect equipped behaves exactly as before: hooks only add.
##
## Multi-hex units (the boss, size 2 = 7 hexes): unit_at() answers for every
## hex of a footprint, movement and placement need the whole footprint free,
## range and sight are measured between the nearest pair of hexes, and a
## shape that covers several of its hexes hits it once. Tiles read only its
## centre (ELEMENTS E15).

signal event(e: Dictionary)

const MELEE_MAX_RISE := 2    # D31: melee can't reach more than 2 levels up or down
const NOWHERE := Vector2i(-9999, -9999)

var board: BWBoard
var tiles: BWTiles
var units: Array = []          # BWUnit
var rng := RandomNumberGenerator.new()
var queue: Array = []
var turn_index := -1
var cycle := 0
var history: Array = []        # every event, in order
var _undo := {}                # D48: the last move's snapshot, until the unit commits
const _COMMITS := ["attack", "skill", "turn_end", "turn", "cycle", "battle_end", "follow_up", "guard"]
var over := false
var winner := ""
var _fx_units: Array = []      # units carrying any effect (fast path for stat hooks)
## D90/D91 picks mid-fight. Off for a bare battle (the self-test, --pace,
## the forecast sheet: the Gate-0 rules sandbox); the run's combat screen
## turns it on. When on, a unit on an `auto_pick_teams` team resolves what
## a rank-up owes at once (BWPicks.auto_resolve, deterministic) and rank 3
## grants are applied for everyone; a player unit's choices wait for
## apply_pick(), which the screen calls before play goes on (no banking).
var picks_live := false
var auto_pick_teams: Array = ["enemy"]
## D93: a counter of unit turns (Nightborn's "first effect each turn") and the
## units arced during the current action (Overcharge: nobody arced twice).
var _turn_serial := 0
var _arced := {}
## D196-D205 (BWEnchant, src/core/enchant_v2.gd): an action counter (the
## on-event heal cap), the on-kill depth (on-kill never triggers on-kill) and
## Covering's shares waiting to be paid after the blow.
var _action_serial := 0
var _onkill_depth := 0
var _pending_cover: Array = []
## D255: a boss fight's state (BWPhases: the phase script, fired / pending
## phases, per-unit rules; the boss's own keys, e.g. the Twins' beam). Ids
## and numbers only, so clone() copies it. {} = no boss.
var boss := {}
## D249-D254 weather (BWWeather, src/core/weather.gd): the fight's weather
## state, {} for none. Set with set_weather() before setup().
var weather := {}
## D269-D274 wind (BWWind, src/core/wind_modes.gd): walls { owner id: {hexes,
## ticks} } and the tick flag. Ids and numbers only, so clone() copies it.
var wind := {}


func _init(p_board: BWBoard, seed_value: int = 1) -> void:
	board = p_board
	tiles = BWTiles.new(board)
	board.extra_cost = tiles.move_penalty
	tiles.potency = _tile_potency          # FX hook: tile_potency_pct
	board.blocker = tiles.blocks_move      # D262: ice pillars are impassable
	board.sight_blocker = tiles.blocks_sight   # D262/D265: pillars and steam block sight
	tiles.occupant = unit_at               # D261/D262: slides and pillars see the units
	rng.seed = seed_value
	BWWind.hook_board(self)                # D273: wind walls join the board's blocker (last: composes)


## Place both sides. `player_at` overrides the map's default player spawns
## (the pre-battle placement screen); missing positions fall back to spawns.
## A multi-hex enemy takes the first enemy spawn its whole footprint fits on,
## else the nearest hex that fits (the maps' spawns are single hexes).
func setup(players: Array, enemies: Array, player_at: Array = []) -> void:
	units.clear()
	var starts := board.default_starts("player", players.size(), player_at.slice(0, players.size()))   # D320: any count
	var si := 0
	for i in players.size():
		var u: BWUnit = players[i]
		u.team = "player"
		u.begin_battle()
		if i < player_at.size():
			u.pos = player_at[i]
		else:
			u.pos = starts[si] if si < starts.size() else Vector2i.ZERO
			si += 1
		units.append(u)
	var lay := enemy_layout(board, enemies, units.map(func(p): return p.pos))   # D211: any number, any size
	for i in enemies.size():
		var u: BWUnit = enemies[i]
		u.team = "enemy"
		u.begin_battle()
		u.pos = lay[i]
		units.append(u)
	_place_objectives()                       # D140: the map's obelisks, a third side
	BWPhases.setup(self)                      # D255: a boss's phase script (the Twins)
	_fx_units = units.filter(func(u: BWUnit): return not u.effects.is_empty())
	for u in units:
		u.fx_hook = _situational              # FX hook: stand_on_bonus, aura_mod stats/move
		var near: BWUnit = null               # D87: everyone starts facing the nearest foe
		for f in foes_of(u):
			if near == null or gap(u, f) < gap(u, near):
				near = f
		if near != null:
			u.facing = BWHex.direction_index(u.pos, near.pos)
	BWWind.hook_board(self)                   # D273 (re-composes if the blocker was replaced since _init)
	_emit({ "type": "battle_start" })
	_new_cycle()


## D211: where the enemies start. Enemy i takes spawn i; a multi-hex unit the
## first spawn (from its own, rotating) its whole footprint fits; past the
## map's spawns (the Horde's ten) or when nothing fits, the free hex nearest
## the spawns (its own spawn for a multi-hex unit), ties in hex order; a crowd
## fans out over the enemy half, a hex apart where it can. `taken`: hexes already held (the
## player's units). Static, so the pre-battle screen shows the same layout.
static func enemy_layout(bd: BWBoard, enemies: Array, taken: Array = []) -> Array:
	var occ := {}
	for h in taken + Array(bd.deploy.get("player", [])) + Array(bd.spawns.get("player", [])):
		occ[h] = true                              # never on the player's side of the start
	var sp: Array = bd.spawns.enemy
	var out: Array = []
	var cells: Array = []
	var psp: Array = Array(bd.spawns.get("player", [])) + Array(bd.deploy.get("player", []))
	for i in enemies.size():
		var u: BWUnit = enemies[i]
		var r := maxi(u.size, 1) - 1
		var pick := NOWHERE
		if r == 0 and i < sp.size() and not occ.has(sp[i]) and bd.fits(sp[i], 0):
			pick = sp[i]
		elif r > 0 and not sp.is_empty():
			var k := i % sp.size()
			for h in sp.slice(k) + sp.slice(0, k):
				if _free_fit(bd, h, r, occ):
					pick = h
					break
		if pick == NOWHERE:
			var anchors: Array = [sp[i]] if r > 0 and i < sp.size() else sp
			if anchors.is_empty():
				anchors = [Vector2i(bd.cols / 2, 0)]
			if cells.is_empty():
				cells = bd.cells()
			var best_d := 1 << 20
			for h in cells:
				if not _free_fit(bd, h, r, occ):
					continue
				var d := 1 << 20
				for a in anchors:
					d = mini(d, BWHex.distance(h, a))
				if r == 0:
					# a crowd spreads over the enemy half: crowded hexes and the
					# player's half cost more (an even spread, readable HP bars)
					var near_p := 1 << 20
					for ph in psp:
						near_p = mini(near_p, BWHex.distance(h, ph))
					if near_p <= d:
						d += 1000
					for nb in BWHex.neighbors(h):
						if occ.has(nb):
							d += 2
				if d < best_d or (d == best_d and h < pick):
					best_d = d
					pick = h
		if pick == NOWHERE:
			pick = sp[i % sp.size()] if not sp.is_empty() else Vector2i.ZERO
		out.append(pick)
		for f in BWHex.area(pick, r):
			occ[f] = true
	return out


static func _free_fit(bd: BWBoard, h: Vector2i, r: int, occ: Dictionary) -> bool:
	if not bd.fits(h, r):
		return false
	for f in BWHex.area(h, r):
		if occ.has(f):
			return false
	return true


func current() -> BWUnit:
	if turn_index < 0 or turn_index >= queue.size():
		return null
	return queue[turn_index]


## The living unit covering hex `h` (any hex of a multi-hex footprint).
func unit_at(h: Vector2i) -> BWUnit:
	for u in units:
		if not u.alive():
			continue
		if u.size <= 1:
			if u.pos == h:
				return u
		elif BWHex.distance(u.pos, h) <= u.size - 1:
			return u
	return null


## The living unit whose centre is `h`: what tile effects read (E15).
func _centre_at(h: Vector2i) -> BWUnit:
	for u in units:
		if u.alive() and u.pos == h:
			return u
	return null


## Could `u` stand with its centre on `h`? Every footprint hex on the map,
## passable, and free of other living units.
func can_stand(u: BWUnit, h: Vector2i) -> bool:
	if not board.fits(h, maxi(u.size, 1) - 1):
		return false
	for f in u.footprint(h):
		var o := unit_at(f)
		if o != null and o != u:
			return false
	return true


## Hexes between two units' nearest footprint hexes (1 = touching).
func gap(a: BWUnit, b: BWUnit, a_at: Vector2i = NOWHERE) -> int:
	var at := a.pos if a_at == NOWHERE else a_at
	return maxi(0, BWHex.distance(at, b.pos) - (maxi(a.size, 1) - 1) - (maxi(b.size, 1) - 1))


func side(team: String) -> Array:
	return units.filter(func(u: BWUnit): return u.team == team and u.alive())


## Who `u` may attack. D140: the obelisks (team "neutral") are the player's
## targets only; the enemy defends them and never strikes one; an obelisk
## has no foes (its pulse is not an attack).
func foes_of(u: BWUnit) -> Array:
	match u.team:
		"player":
			return side("enemy") + side(BWObelisk.TEAM)
		"enemy":
			return side("player")
	return []


# ---------------------------------------------------------------- D140-D145 objectives

## Obelisk fights (the "Obelisks" map, fight 4): the map's objective.
func objective_mode() -> bool:
	return str(board.objective.get("mode", "")) == "obelisks"


## Every obelisk of the fight, standing or broken, in map order.
func objectives() -> Array:
	return units.filter(func(u: BWUnit): return BWObelisk.is_objective(u))


func _place_objectives() -> void:
	if not objective_mode():
		return
	for o in board.objective.get("obelisks", []):
		var at: Array = o.get("at", [])
		if at.size() != 2:
			continue
		var ob := BWObelisk.create(str(o.get("kind", "lantern")), Vector2i(int(at[0]), int(at[1])))
		ob.begin_battle()
		units.append(ob)


## May `u`'s blows land on `v` at all? D140: the enemy's never touch an
## obelisk (they defend them; their area skills pass over it).
func can_harm(u: BWUnit, v: BWUnit) -> bool:
	return not (BWObelisk.is_objective(v) and (u == null or u.team != "player"))


## D140: one obelisk's turn. Its pulse hits EVERY other unit on the map, both
## sides, for its flat damage (no roll, no resist, no ward: environmental,
## D141), then moves them one hex: the Lantern pushes away, the Well pulls
## toward (D143). Then the turn passes. BWAI.take_turn calls this.
func obelisk_turn(o: BWObelisk) -> void:
	if over or o != current():
		return
	var hit: Array = units.filter(func(v: BWUnit): return v.alive() and not BWObelisk.is_objective(v))
	_emit({ "type": "pulse", "unit": o.id, "kind": o.pulse_kind, "damage": o.pulse_damage, "hex": o.pos,
		"targets": hit.map(func(v): return v.id) })
	for v in hit:
		_pulse_hurt(v, o.pulse_damage, "pulse", o)
		if over:
			return
	_pulse_move(o)
	if not over:
		end_turn()


## D141: flat damage, credited to nobody (a pulse KO gives no XP). Reactive
## stat triggers fire as for any damage; no Frost Ward, no chain arc.
func _pulse_hurt(v: BWUnit, amount: int, cause: String, o: BWObelisk) -> void:
	if amount <= 0 or not v.alive():
		return
	var before := v.hp
	v.hp = maxi(0, v.hp - amount)
	_emit({ "type": "tile_damage", "unit": v.id, "amount": amount, "cause": cause, "hp": v.hp, "source": "",
		"obelisk": o.id })
	if not v.alive():
		_ko(v, null, cause)
		_check_end()
	else:
		_hurt_triggers(v, before)


## D143: every non-obelisk unit moves one hex, resolved one at a time in a
## fixed order so nobody blocks a hex that is about to empty: pushes go
## farthest first, pulls closest first; ties by setup order. Each unit's
## heading is the neighbour one step farther from (push) / nearer to (pull)
## the obelisk that lies closest to the straight line through it (ties: the
## lower heading index). The existing displacement rules apply: rock or a
## unit in the way stops it and it slams (SLAM_PCT); the map edge (void) is
## open air, no slam; immune displace holds. A unit already beside the Well
## stays put (nothing to slam into but the Well itself).
func _pulse_move(o: BWObelisk) -> void:
	var push := o.pulse_kind == "push"
	var order: Array = []
	for i in units.size():
		var v: BWUnit = units[i]
		if v.alive() and not BWObelisk.is_objective(v):
			order.append([BWHex.distance(o.pos, v.pos), i, v])
	order.sort_custom(func(a, b) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0] if push else a[0] < b[0]
		return a[1] < b[1])
	for row in order:
		var v: BWUnit = row[2]
		if over or not v.alive():
			continue
		var d: int = BWHex.distance(o.pos, v.pos)
		if not push and d <= 1:
			continue
		var dir := pulse_heading(o.pos, v.pos, push)
		if dir < 0:
			continue
		if _immune(v, "displace"):
			_emit({ "type": "displace_resisted", "unit": v.id, "kind": o.pulse_kind })
			continue
		var pp := push_path(v, dir, 1)
		if (pp.path as Array).size() > 1:
			v.pos = pp.path[-1]
			_emit({ "type": "move", "unit": v.id, "path": pp.path, "kind": o.pulse_kind })
			BWSlides.after_push(self, v, dir)     # D261
		elif str(pp.stop) in ["rock", "unit"]:
			_emit({ "type": "slam", "unit": v.id, "by": o.id, "into": pp.stop, "name": o.name })
			var dmg := BWTiles.tile_damage(v, BWObelisk.SLAM_PCT, "", 1.0)
			_pulse_hurt(v, dmg, "slam", o)


## D143: the heading (0-5) that moves `from` one hex farther from (push) or
## nearer to (pull) `centre`, closest to the straight line; -1 at the centre.
static func pulse_heading(centre: Vector2i, from: Vector2i, push: bool) -> int:
	var d := BWHex.distance(centre, from)
	if d == 0:
		return -1
	var c := BWHex.to_world(centre)
	var f := BWHex.to_world(from)
	var want := (f - c).normalized() if push else (c - f).normalized()
	var best := -1
	var best_dot := -INF
	var nb := BWHex.neighbors(from)
	for i in nb.size():
		if BWHex.distance(centre, nb[i]) != (d + 1 if push else d - 1):
			continue
		var dot := (BWHex.to_world(nb[i]) - f).normalized().dot(want)
		if dot > best_dot + 1e-6:
			best_dot = dot
			best = i
	return best


## D142: the obelisk's flat dodge against the attack type it shrugs off. The
## hit chance is halved (a second, independent 50% roll), shown as its own
## forecast line `dodge` plus a note, and the expected damage follows.
func _obelisk_dodge(fc: Dictionary, v: BWUnit, att: BWUnit) -> void:
	if not BWObelisk.is_objective(v) or att == null:
		return
	var o := v as BWObelisk
	var kind := BWObelisk.attack_type(att, gap(att, v))
	if kind != o.dodge_vs:
		fc["notes"] = (fc.get("notes", []) as Array) + ["%s: no dodge against %s attacks (it dodges %s)" % [o.name, kind, o.dodge_vs]]
		return
	var keep := 1.0 - BWObelisk.DODGE_PCT / 100.0
	var h: Dictionary = fc.hit
	fc.hit = BWFormulas.calc("Hit", float(h.value) * keep, "(%s) × (1 − %s %d%% vs %s)" % [h.formula, o.veil_name(), int(BWObelisk.DODGE_PCT), kind],
		"(%s) × %.2f" % [h.values, keep])
	fc["dodge"] = BWFormulas.calc("%s (vs %s)" % [o.veil_name(), kind], BWObelisk.DODGE_PCT,
		"flat %d%% against %s attacks" % [int(BWObelisk.DODGE_PCT), kind], "%s: %d%%" % [o.name, int(BWObelisk.DODGE_PCT)])
	var ex: Dictionary = fc.expected
	fc.expected = BWFormulas.calc(ex.label, float(ex.value) * keep, ex.formula + " × dodge", ex.values)
	fc["notes"] = (fc.get("notes", []) as Array) + ["%s: %d%% of %s attacks miss it" % [o.veil_name(), int(BWObelisk.DODGE_PCT), kind]]


# ---------------------------------------------------------------- movement

## FX hooks: move_after_attack (a second, short move after acting), immune
## muddy / water_wading (cost), and the footprint of a multi-hex unit.
func reachable(u: BWUnit) -> Dictionary:
	var budget := u.move_range()
	if u.moved:
		budget = int(u.fx.get("bonus_move", 0))
		if budget <= 0:
			return { u.pos: { "cost": 0, "from": u.pos, "stop": true } }
	if u.statuses.has("becalmed"):            # D270: Becalmed, no move of any kind
		return { u.pos: { "cost": 0, "from": u.pos, "stop": true } }
	var blocked := {}
	var no_stop := {}
	for o in units:
		if o == u or not o.alive():
			continue
		for f in o.footprint():
			if o.team == u.team:
				no_stop[f] = true
			else:
				blocked[f] = true
	var opts := {
		"footprint": maxi(u.size, 1) - 1,
		"no_muddy": _immune(u, "muddy"),
		"no_water": _immune(u, "water_wading"),
	}
	# D93/D97: perk movement (Waterwalking, Skate, Heat Rush, Shadowstep) and
	# enemy zones need the battle's own search; plain units keep the board's.
	var rules := _move_rules(u)
	var pull := _undertow_for(u)          # D93 Undertow: search with move+1, filter by destination
	if not pull.is_empty():
		budget += int(pull.move)
	var ice := BWSlides.ice_for(self, u)  # D261: a walk can't cross ice; entering it slides
	var walk_blocked := blocked if ice.is_empty() else blocked.merged(ice)
	var r: Dictionary
	if rules.is_empty():
		r = board.reachable(u.pos, budget, walk_blocked, no_stop, opts)
	else:
		r = _reach_fx(u, budget, walk_blocked, no_stop, opts, rules)
	BWSlides.walk_reach(self, u, r, budget, opts, rules, ice)   # D261: the slides' end hexes
	if not pull.is_empty():
		_undertow_filter(u, r, budget, pull)
	BWEnchant.add_swaps(self, u, r)       # v2 hook: swap mode=move (Bodyguard)
	return r


## May `u` move now? Once per turn, plus a Flowing move after acting.
func can_move(u: BWUnit) -> bool:
	return u.follow_up.is_empty() and (not u.moved or int(u.fx.get("bonus_move", 0)) > 0)


func can_move_to(u: BWUnit, h: Vector2i) -> bool:
	var r := reachable(u)
	return r.has(h) and r[h].stop and can_move(u)


func move(u: BWUnit, h: Vector2i) -> bool:
	if over or u != current() or not can_move(u):
		return false
	var flow := u.moved
	var r := reachable(u)
	if r.has(h) and r[h].has("swap"):
		return BWEnchant.swap_move(self, u, h, r[h])     # v2 hook: Bodyguard
	var path := BWBoard.path_to(r, h)
	if path.is_empty():
		return false
	var slide: Dictionary = r[h].get("slide", {})   # D261: the walk ends in a slide
	# Undo snapshot (D48): everything a move can touch, so Esc can put it back.
	_undo = { "unit": u, "pos": u.pos, "moved": u.moved, "hp": u.hp, "fx": u.fx.duplicate(true), "facing": u.facing,
		"mods": u.battle_mods.duplicate(true), "tiles": tiles.entries.duplicate(true) }
	u.pos = h
	u.moved = true
	u.facing = BWHex.direction_index(path[-2], path[-1]) if path.size() > 1 else u.facing   # D87
	u.fx["moved_hexes"] = int(u.fx.get("moved_hexes", 0)) + path.size() - 1   # Jousting
	var e := { "type": "move", "unit": u.id, "path": BWSlides.walk_part(path, slide) }
	if flow:
		u.fx["bonus_move"] = 0
		e["kind"] = "flow"
	_mark_move_perks(u, path, e)              # D93: Heat Rush / Shadowstep spent
	BWKsIce.after_walk(self, u, path)         # D294 Skater: free ice hexes spent
	_emit(e)
	BWSlides.emit_slide(self, u, slide)       # D261
	# Fire burns every hex entered along the way, start excluded (ELEMENTS §2.2).
	# D93 Heat Rush: no crossing damage.
	var no_cross := BWEffects.has(u, "heat_rush") or BWOverheat.no_cross(u)   # D286: Trailblazer too
	for i in range(1, path.size()):
		if tiles.intensity(path[i], "water") > 0:          # v2 hook: Tidewalker counts water entered
			u.fx["on_hexes:water"] = int(u.fx.get("on_hexes:water", 0)) + 1
		var pct := tiles.crossing_pct(path[i])
		if pct > 0 and u.alive() and not no_cross:
			_tile_hurt(u, _tile_dmg(u, pct, "fire"), "fire_cross", str(tiles.at(path[i]).get("source", "")))
	_lay_on_move(u, path)
	BWOverheat.after_walk(self, u, path)      # D286: Trailblazer's fire 1 behind it
	BWPools.on_walk(self, u, path)            # D264: an electrified pool's entry shock
	BWSlides.after_walk(self, u, slide)       # D261: the slam, then +1 move
	BWPhases.after_move(self, u, path)        # D256: the Twins' beam (crossing it)
	if u.alive() and not over:
		_static_field_check(u)                # D93 Static Field: ending a move on its fuse
		_zone_check(u)                        # D97: ending a move inside an enemy zone
		BWWind.after_move(self, u, path)      # D270: a gust field pushes, a becalm field stopped it
	return true


## D48: a move can be taken back until the unit acts or the turn ends —
## including fire it walked through and tiles it laid. Not after a KO.
func can_undo_move(u: BWUnit) -> bool:
	return not over and not _undo.is_empty() and _undo.unit == u and u == current() and u.alive()


func undo_move(u: BWUnit) -> bool:
	if not can_undo_move(u):
		return false
	var from := u.pos
	u.pos = _undo.pos
	u.moved = _undo.moved
	u.facing = int(_undo.get("facing", u.facing))
	u.hp = _undo.hp
	u.fx = _undo.fx
	u.battle_mods = _undo.mods
	tiles.entries = _undo.tiles
	_undo = {}
	_emit({ "type": "undo_move", "unit": u.id, "from": from, "to": u.pos, "hp": u.hp })
	return true


# ---------------------------------------------------------------- attacking

## FX hook: range_mod (Piercing, Longshot, Throwing, Ammo Belt).
func weapon_range(u: BWUnit) -> int:
	return BWEffects.basic_range(u)


## Range and sight between the nearest pair of footprint hexes that works.
func in_range(u: BWUnit, target: BWUnit, from: Vector2i = NOWHERE) -> bool:
	var at := u.pos if from == NOWHERE else from
	if u.statuses.has("blinded") and gap(u, target, at) > BWSkills.BLIND_RANGE:
		return false                          # D94: Blinded targets within 2 only
	if BWPools.steam_hides(self, u, at, target):
		return false                          # D265: a unit in steam, only from within 2
	return _reaches_unit(u, at, target, weapon_range(u))


func _reaches_unit(u: BWUnit, at: Vector2i, target: BWUnit, max_range: int) -> bool:
	for fa in u.footprint(at):
		for fb in target.footprint():
			if _reaches(fa, fb, max_range):
				return true
	return false


## D182: the element a basic attack carries: the weapon's imbue, else the
## staff's attunement (D5), else none.
func basic_element(u: BWUnit) -> String:
	if u.imbue() != "":
		return u.imbue()
	return u.attuned if str(u.weapon().get("damage_type", "")) == "spell" else ""


## D181/D195: may `u` swap weapons now? Its own turn, a weapon carried, and
## not inside a follow-up. Free and unlimited (D195): no action, no move.
func can_swap(u: BWUnit) -> bool:
	return not over and u != null and u == current() and u.alive() and not u.second_weapon().is_empty() and u.follow_up.is_empty()


## D181: draw the carried weapon (free, any number of times a turn, D195). The class, range,
## damage, enchantment and skills follow the new main hand; cooldowns are
## per skill and stay. Emits `swap` { unit, from, to, weapon_class }.
func swap_weapon(u: BWUnit) -> bool:
	if not can_swap(u):
		return false
	var from := str(u.equipment.get("main_hand", {}).get("base", ""))
	u.swap_weapons()
	_fx_units = units.filter(func(x: BWUnit): return not x.effects.is_empty())
	_emit({ "type": "swap", "unit": u.id, "from": from, "to": str(u.equipment.get("main_hand", {}).get("base", "")),
		"weapon_class": u.weapon_class, "imbue": u.imbue() })
	return true


func attack_targets(u: BWUnit) -> Array:
	return foes_of(u).filter(func(f: BWUnit): return in_range(u, f))


## Basic weapon attack forecast. Staff basics are spells in the unit's own
## element (D5); everything else is a plain weapon strike.
## Ground terms (ELEMENTS §8.3): light/dark on the target's hex shift hit,
## thunder into water conducts. FX hook: every effect modifier rides in as a
## labelled forecast mod (BWEffects.attack_mods); `share`/`share_label` is a
## multi-strike's per-hit cut (Doubleshot 75%, Spreadshot 50%, counters).
## `from`: forecast as if `u` stood there (the AI weighing a hex: ground,
## facing and the perks that read the attacker's hex).
func forecast_basic(u: BWUnit, target: BWUnit, share: float = 1.0, share_label: String = "", from: Vector2i = NOWHERE) -> Dictionary:
	var w := u.weapon()
	var power := int(w.get("base_dmg", 10))
	var spell := str(w.get("damage_type", "")) == "spell"
	var el := basic_element(u)
	var kind := BWFormulas.SPELL if spell else BWFormulas.WEAPON
	# D87: a pistol's seated round rides the shot (Spark if thunder, +10% if your own element)
	var rnd := u.loaded if u.weapon_class == "pistols" else ""
	if not spell and BWFormulas.strips_element(target):
		el = ""                                # D209: a Blank takes the cut, not the imbue's element
		rnd = ""
	var mods := _mods(u, target, kind, el, true, rnd, from)
	if rnd != "" and rnd == u.element:
		mods.append({ "stage": "dmg", "value": 1.0 + BWSkills.OWN_ROUND_PCT / 100.0,
			"label": "Own round (%s): +%d%%" % [rnd, BWSkills.OWN_ROUND_PCT], "tag": "Own round" })
	if share != 1.0:
		mods.append({ "stage": "dmg", "label": share_label, "value": share })
	return _annotate(_guarded(BWFormulas.forecast(u, target, kind, power, el, 0.0, 0.0, 1.0, mods), target), target, u)


## Every modifier on one blow: the ground's, the statuses', then the effects'.
## `round_el`: a pistol's seated round, which Sparks like a thunder hit (D87).
func _mods(att: BWUnit, dfn: BWUnit, kind: String, el: String, basic: bool, round_el: String = "", at: Vector2i = NOWHERE) -> Array:
	var mods: Array = []
	var ap := att.pos if at == NOWHERE else at
	var hm := tiles.hit_mod(dfn.pos)
	if hm != 0.0:
		var lit := tiles.intensity(dfn.pos, "light")
		if lit > 0 and (BWEffects.has(dfn, "radiant_guard") or BWPerkRules.team_has(self, dfn.team, "radiant_guard", "allies")):     # D93 Radiant Guard; D281 Sanctuary: allies too
			mods.append({ "stage": "hit", "value": 0.0, "label": "Target on Light %d: Radiant Guard ignores it" % lit })
		else:
			mods.append({ "stage": "hit", "value": hm,
				"label": "Target on Light %d" % lit if lit > 0 else "Target on Dark %d" % tiles.intensity(dfn.pos, "dark") })
	var cm := tiles.conduct_mult(dfn.pos, el)
	if cm != 1.0:
		mods.append({ "stage": "dmg", "value": cm,
			"label": "Conducted through Water %d" % tiles.intensity(dfn.pos, "water") })
	# D86 (ELEMENTS §8.5): Spark — a thunder hit on uncharged ground; Shatter —
	# any attack on a glazed hex (the glaze is not consumed).
	if (el == "thunder" or (el == "" and round_el == "thunder")) and not tiles.charged(dfn.pos):
		mods.append({ "stage": "dmg", "value": 1.0 + BWTiles.SPARK_PCT / 100.0,
			"label": "Spark: +%d%%" % BWTiles.SPARK_PCT, "tag": "Spark" })
	if tiles.is_glazed(dfn.pos):
		if BWEffects.has(dfn, "rime_armour"):                    # D93 Rime Armour
			mods.append({ "stage": "dmg", "value": 1.0, "label": "Shatter: Rime Armour ignores it" })
		elif BWEffects.has(att, "fault_lines"):                  # D93 Fault Lines
			var fl := float(BWEffects.p(BWEffects.list(att, "fault_lines")[0], "pct", 30))
			var brk := int(BWEffects.p(BWEffects.list(att, "fault_lines")[0], "nobreak", 0)) != 1   # D281: no break now
			mods.append({ "stage": "dmg", "value": 1.0 + fl / 100.0,
				"label": "Shatter (Fault Lines): +%d%%%s" % [int(fl), ", breaks the glaze" if brk else ""], "tag": "Shatter" })
		else:
			mods.append({ "stage": "dmg", "value": 1.0 + BWTiles.SHATTER_HIT_PCT / 100.0,
				"label": "Shatter (glazed): +%d%%" % BWTiles.SHATTER_HIT_PCT, "tag": "Shatter" })
	# D94 statuses (no hit penalties any more), D96 facing, D93 perks.
	if att.statuses.has("blinded"):
		mods.append({ "stage": "crit_x", "value": 0.0, "label": "Blinded: can't crit" })
	_facing_mods(ap, dfn, mods)
	_perk_mods(att, dfn, ap, mods)
	if dfn.statuses.has("scorched"):
		mods.append({ "stage": "dmg", "value": 1.0 + BWSkills.SCORCH_PCT / 100.0,
			"label": "Scorched: +%d%%" % BWSkills.SCORCH_PCT })
	if dfn.statuses.has("drenched") and el == "thunder":
		mods.append({ "stage": "dmg", "value": 1.0 + BWSkills.DRENCH_THUNDER_PCT / 100.0,
			"label": "Drenched: +%d%%" % BWSkills.DRENCH_THUNDER_PCT })
	if att.fx.get("momentum", false):
		mods.append({ "stage": "dmg", "value": 1.0 + BWSkills.VAULT_MOMENTUM_PCT / 100.0,
			"label": "Momentum (Vault): +%d%%" % BWSkills.VAULT_MOMENTUM_PCT, "tag": "Momentum" })
	# D209: special encounters (Blank, Elemental Being) by the blow's damage class
	if dfn.encounter != "":
		var em := BWFormulas.encounter_mod(dfn, BWFormulas.damage_class({ "source": "basic" if basic else "skill", "kind": kind, "element": el }),
			BWObelisk.attack_type(att, gap(att, dfn, ap)) == "melee")
		if not em.is_empty():
			mods.append(em)
	BWCurse.rot_mods(dfn, mods)               # D275: Rot, +5% taken per stack
	BWBeams.mods(self, att, mods)             # D287: Empowered, on its own turn
	BWOverheat.basic_mods(self, att, dfn, el, basic, mods)   # D285: an Overheat note
	BWOverfreeze.basic_mods(self, dfn, el, basic, mods)      # D312: an Overfreeze note
	BWKeystoneFx.blow_mods(self, att, dfn, mods)   # D294: Frozen (x2, counts as glazed)
	if _fx_units.is_empty():
		return mods
	var e := tiles.at(dfn.pos)
	var ctx := {
		"dist": gap(att, dfn, ap), "basic": basic, "base_range": int(att.weapon().get("range", 1)),
		"moved": int(att.fx.get("moved_hexes", 0)),
		"height": board.elevation(ap) - board.elevation(dfn.pos),
		"charged": not e.is_empty() and (int(e.h) != 0 or int(e.v) != 0),
		# v2 (BWEnchant.mods): Flanker, Planted, Lone Wolf, Resonance, Shieldwall
		"rear": dfn.facing >= 0 and ap != dfn.pos and BWHex.direction_index(dfn.pos, ap) >= 0 and (BWHex.direction_index(dfn.pos, ap) - dfn.facing + 6) % 6 in [2, 3, 4],
		"still": not att.moved,
		"att_alone": _alone(att, ap), "dfn_alone": _alone(dfn, dfn.pos),
		"charge_levels": 0 if e.is_empty() else absi(int(e.h)) + absi(int(e.v)),
		"dfn_adjacent": side(dfn.team).filter(func(o): return o != dfn and gap(o, dfn) <= 1).size(),
		"att_adjacent": side(att.team).filter(func(o): return o != att and gap(att, o, ap) <= 1).size(),   # D244 Lockstep
	}
	mods.append_array(BWEffects.attack_mods(att, dfn, kind, el, ctx, _auras))
	return mods


## v2 Lone Wolf: no living ally within 2 of `u` standing at `at`.
func _alone(u: BWUnit, at: Vector2i) -> bool:
	for o in side(u.team):
		if o != u and gap(u, o, at) <= 2:
			return false
	return true


## The strikes one basic attack makes: [{unit, share, label, pattern}].
## FX hooks: multi_hit (same / fan / line) and aoe_radius_plus basic=1
## (Cleaving's ring around the target). A unit is struck by one line only.
func basic_strikes(u: BWUnit, target: BWUnit) -> Array:
	var out: Array = [{ "unit": target, "share": 1.0, "label": "", "pattern": "single" }]
	if u.encounter == "colossus":
		return colossus_thrust(u, target)        # D210: the long spear runs through a line
	for e in BWEffects.list(u, "multi_hit"):
		if str(BWEffects.p(e, "skill", "")) != "":
			continue                  # a skill's own rider (Pummeling: Flurry), not the basic attack
		var count := int(BWEffects.p(e, "count", 1))
		var share := float(BWEffects.p(e, "dmg_pct", 100)) / 100.0
		var pattern := str(BWEffects.p(e, "pattern", "same"))
		var di := BWHex.direction_index(u.pos, target.pos)
		match pattern:
			"same":
				out.clear()
				for k in count:
					out.append({ "unit": target, "share": share, "label": "%s (%d of %d)" % [e.name, k + 1, count], "pattern": pattern })
			"fan":
				out[0] = { "unit": target, "share": share, "label": e.name, "pattern": pattern }
				var offs := [-1, 1, -2, 2, 3]
				for k in mini(count - 1, offs.size()):
					if di < 0:
						break
					var d: int = (di + offs[k] + 6) % 6
					var nb: Vector2i = BWHex.neighbors(u.pos)[d]
					for h in board.ray(u.pos, nb, weapon_range(u)):
						var o := unit_at(h)
						if o != null and o.team != u.team and not _struck(out, o) and _reaches(u.pos, h, weapon_range(u)):
							out.append({ "unit": o, "share": share, "label": "%s (side line)" % e.name, "pattern": pattern })
							break
			"line":
				if di >= 0:
					var h := target.pos
					for k in maxi(1, weapon_range(u)) + maxi(target.size, 1) - 1:
						h = BWHex.neighbors(h)[di]
						if not board.exists(h):
							break
						var o := unit_at(h)
						if o != null and o != target and o.team != u.team:
							out.append({ "unit": o, "share": share, "label": "%s (behind)" % e.name, "pattern": pattern })
							break
		break
	for e in BWEffects.list(u, "aoe_radius_plus"):
		if int(BWEffects.p(e, "basic", 0)) != 1:
			continue
		var share := float(BWEffects.p(e, "ring_pct", 100)) / 100.0
		var inner := target.footprint()
		var mine := u.footprint()
		for h in BWHex.fringe(inner, int(BWEffects.p(e, "radius", 1))):
			if h in inner or h in mine:
				continue
			var o := unit_at(h)
			if o == null or o == u or _struck(out, o):
				continue
			if o.team == u.team and int(BWEffects.p(e, "friendly", 0)) != 1:
				continue
			out.append({ "unit": o, "share": share, "label": "%s (outer ring)" % e.name if share != 1.0 else "", "pattern": "cleave" })
		break
	return out.filter(func(s): return can_harm(u, s.unit))     # D140: side lines and rings pass over an obelisk


## D210: the Colossus's signature. Its spear thrusts THRUST_LEN hexes straight
## out from its body toward the target: every foe on that line is struck (the
## target at full, the rest at THRUST_SHARE). A target off the six headings
## is struck alone.
const THRUST_LEN := 3
const THRUST_SHARE := 0.75


func thrust_line(u: BWUnit, target: BWUnit) -> Array:
	var di := BWHex.direction_index(u.pos, target.pos)
	if di < 0:
		return []
	var out: Array = []
	var h := u.pos
	for k in maxi(u.size, 1) - 1 + THRUST_LEN:
		h = BWHex.neighbors(h)[di]
		if not board.exists(h):
			break
		if k >= maxi(u.size, 1) - 1:
			out.append(h)
	return out


func colossus_thrust(u: BWUnit, target: BWUnit) -> Array:
	var out: Array = [{ "unit": target, "share": 1.0, "label": "Line thrust", "pattern": "line" }]
	var line := thrust_line(u, target)
	var on_line := false
	for f in target.footprint():
		on_line = on_line or f in line
	if not on_line:
		out[0].label = ""
		out[0].pattern = "single"
		return out
	for h in line:
		var o := unit_at(h)
		if o != null and o != target and o.team != u.team and not _struck(out, o) and can_harm(u, o):
			out.append({ "unit": o, "share": THRUST_SHARE, "label": "Line thrust (through)", "pattern": "line" })
	return out


func _struck(strikes: Array, o: BWUnit) -> bool:
	for s in strikes:
		if s.unit == o:
			return true
	return false


func attack(u: BWUnit, target: BWUnit) -> Dictionary:
	if over or u != current() or u.acted or not in_range(u, target):
		return {}
	if not u.follow_up.is_empty() and not "basic" in u.follow_up:
		return {}
	u.follow_up = []
	_arced.clear()
	BWEnchant.begin_action(self, u)            # v2 hook
	u.fx["_basic"] = true                      # Spotter: a basic attack's blows
	var target_hex := target.pos
	var strikes := basic_strikes(u, target)
	u.acted = true
	_face(u, target_hex)
	var first := {}
	var ko_any := false
	var counters: Array = []
	var struck: Array = []        # [unit, landed?] once per unit, for lay_on struck + counters
	for i in strikes.size():
		var s: Dictionary = strikes[i]
		var v: BWUnit = s.unit
		if not v.alive() or over:
			continue
		var fc := forecast_basic(u, v, s.share, s.label)
		var res := BWEnchant.roll_blow(self, u, v, fc, true)    # v2 hook: Second Chance, Graze, pity
		BWEnchant.land(self, u, v, res)                         # v2 hook: Bulwark, Covering, Undying
		var before := v.hp
		v.hp = maxi(0, v.hp - res.damage)
		var ko := not v.alive()
		ko_any = ko_any or ko
		var e := {
			"type": "attack", "unit": u.id, "target": v.id, "result": res,
			"forecast_hit": fc.hit.value, "odds": odds(fc), "ko": ko, "target_hp": v.hp, "tags": _tags(fc),
		}
		if strikes.size() > 1:
			e["strike"] = i
			e["strikes"] = strikes.size()
			e["pattern"] = s.pattern
		_emit(e)
		if first.is_empty():
			first = res
		_after_blow(u, v, res, before, "")
		BWEnchant.after_blow(self, u, v, res, true, true)      # v2 hook
		_conduct(u, v, int(res.damage))
		counters.append_array(_riposte_check(v, res))
		_note_struck(struck, v, res)
	u.fx.erase("momentum")          # D87: Vault's momentum is spent on the follow-up
	# FX hook: knockback on=hit (Impact pushes, Hooking pulls) — a secondary
	# effect, so it lands on an avoid too and is stopped only by a resist.
	if target.alive() and not first.is_empty() and first.secondary:
		_knockback_hit(u, target)
	# FX hook: lay_on hit (Frostbitten) when the blow on the target lands.
	if not first.is_empty() and first.hit and not BWFormulas.strips_element(target):   # D209: no riders on a Blank
		_lay_on(u, "hit", { "target_hex": target_hex })
	elif not first.is_empty():
		_lay_on(u, "miss", { "target_hex": target_hex })   # v2: Rerouted
	_lay_on_struck(u, struck)
	# Basic attacks carry the attuned element for growth (§7.1); only the
	# staff's Channel paints, onto the target's hex, hit or miss (§7.2, E11).
	# A pistol shot lays a Reload-seated element on its trail instead.
	_emit({ "type": "growth", "unit": u.id, "events": _award(u, ko_any, u.attuned) })
	var spell := str(u.weapon().get("damage_type", "")) == "spell"
	if u.imbue() != "" and BWFormulas.strips_element(target):
		pass                                   # D209: the imbue doesn't paint under a Blank
	elif u.imbue() != "":
		# D182: an imbued weapon's blow paints its element on the target's
		# hex, hit or miss, like the staff's Channel; the attunement stays.
		var att := u.attuned
		paint([target_hex], u.imbue(), u)
		u.attuned = att
	elif spell and u.attuned != "":
		paint([target_hex], u.attuned, u)
	_fire_pistol(u, target_hex)
	BWThunderKeys.after_basic(self, u, target, first, target_hex)   # D290: Static Blades (burst, else arm)
	BWWind.after_basic(self, u, target, first)  # D271: a wind basic's mode on its target
	_after_action(u, u.attuned if spell else "", true)
	_answer(counters)
	_counter_check(u, struck)
	_overwatch_check(u, struck)               # D97: Covering Fire
	u.fx.erase("_basic")
	BWEnchant.end_action(self, u, true)       # v2 hook: Steady Hand, Bloodpact, Pincer, Relentless
	_check_end()
	return first


## D113: a forecast's odds in brief, carried on every blow's event for the
## cutscene's odds strip: hit (miss = 100 - hit), glance, crit, resist (only
## when `magic`), the per-hit damage and the expected value.
static func odds(fc: Dictionary) -> Dictionary:
	var o := { "hit": float(fc.hit.value), "glance": float(fc.glance.value), "crit": float(fc.crit.value),
		"magic": bool(fc.get("magic", false)), "damage": float(fc.damage.value), "expected": float(fc.expected.value) }
	if o.magic and fc.has("resist"):
		o["resist"] = float(fc.resist.value)
	return o


## A riposte guard halves whatever lands on the target (BWFormulas.guard).
func _guarded(fc: Dictionary, target: BWUnit) -> Dictionary:
	if not target.riposte.is_empty():
		BWFormulas.guard(fc)
	return fc


## D86/D87 forecast extras: `notes` (one line each, shown under the numbers)
## and `arc_ev` (expected arc damage onto the chained unit, for the AI).
func _annotate(fc: Dictionary, v: BWUnit, att: BWUnit = null) -> Dictionary:
	_obelisk_dodge(fc, v, att)                 # D142: the obelisks' flat dodge, a named line
	var notes: Array = fc.get("notes", [])
	if tiles.conductive(v.pos) or BWEnchant.conductive(v):
		var w := _chain_target(v)
		if w != null:
			# D93: Lightning Rod redirects (at its pct), Grounded halves, Overcharge adds a second arc
			var frac := BWEnchant.chain_frac(att)
			var rod := _rod_for(w, v)
			var line := "Conductive (thunder tile): %d%% arcs to %s" % [int(frac * 100), w.name]
			if rod != null:
				frac *= float(BWEffects.p(BWEffects.list(rod, "lightning_rod")[0], "pct", 50)) / 100.0
				line += ", pulled onto %s by Lightning Rod (%d%%)" % [rod.name, int(frac * 100)]
				w = rod
			for e in BWEffects.list(w, "grounded"):
				frac *= float(BWEffects.p(e, "pct", 50)) / 100.0
				line += ", Grounded (%d%%)" % int(frac * 100)
			var ev := float(fc.expected.value) * frac
			if att != null and BWEffects.has(att, "overcharge"):
				var w2 := _chain_target(v, [w])
				if w2 != null:
					line += "; Overcharge: then %d%% on to %s" % [int(frac * 50), w2.name]
					ev += float(fc.expected.value) * frac * 0.5
			notes.append(line)
			fc["arc_ev"] = ev
			fc["arc_to"] = w.id
	for m in fc.get("mods", []):
		if (str(m.stage) == "dmg" and m.has("tag") or str(m.stage) == "note") and not notes.has(str(m.label)):
			notes.append(str(m.label))
	if v.statuses.has("steadied"):
		notes.append("Steadied: immune to stagger")   # D94
	if fc.has("immune"):
		notes = [str(fc.immune)]                   # D209: "Immune: physical", and no riders that won't land
	fc["notes"] = notes
	return fc


## Named riders on a blow, for the cutscene's floating tags ("Spark", "Shatter").
static func _tags(fc: Dictionary) -> Array:
	var out: Array = []
	for m in fc.get("mods", []):
		if m.has("tag") and not str(m.tag) in out:
			out.append(str(m.tag))
	return out


# ---------------------------------------------------------------- skills
# Shapes and rules: design/ELEMENTS.md §7 (weapons) and §9 (staff). Each skill
# is one BWSkillDef in src/core/skill_defs/ (D89); the battle runs the shared
# order of an action (§7.3): shape → direct hits against the pre-action
# ground → paint (detonations) → one growth award → follow-up → riposte
# answers, and asks the def at each step (plan, forecast_mods, relocate,
# after_hits, ground, after_paint, on_follow_up). Numbers: BWSkills.

## Elements the unit can lay: affinity rank ≥ 1 (§7.1, E12).
func learned_elements(u: BWUnit) -> Array:
	return BWFormulas.ELEMENTS.filter(func(el): return u.affinity_rank(el) >= 1)


## Skills usable right now, each a copy of its BWSkills row plus "elements":
## the elements it is off cooldown in ([""] for a skill that takes none).
## Inside a follow-up only the granted keys are offered ("basic" is attack()).
func skills_for(u: BWUnit) -> Array:
	var out: Array = []
	if over or not u.alive():
		return out
	if u.statuses.has("staggered"):
		return out                            # D94: Staggered = basic attack only
	# D89: the unit's loadout, else the weapon's kit; D98: plus skills learned
	# mid-fight past the cap (usable for the rest of this battle).
	# D273: plus the keystone actions it holds (Wind Wall).
	for s in BWSkillRegistry.expand(u.fight_loadout(u.weapon_class) + BWWind.keystone_actions(u)).map(func(k): return BWSkillRegistry.row(k)):
		if not _skill_open(u, s):
			continue
		var els: Array = []
		for el in (learned_elements(u) if s.needs_element else [""]):
			if int(u.cooldowns.get(BWSkills.cd_key(s.key, el), 0)) <= 0:
				els.append(el)
		if els.is_empty():
			continue
		var row: Dictionary = s.duplicate(true)
		row["elements"] = els
		if u.skill_upgraded(str(s.key)):
			row["upgraded"] = true              # D89: improved (the menu marks it)
		out.append(row)
	return out


func _skill_open(u: BWUnit, s: Dictionary) -> bool:
	if not u.follow_up.is_empty():
		return s.key in u.follow_up
	if s.get("follow_up_only", false):
		return false
	if s.get("free_action", false):
		return true                           # D87: Riposte spends nothing; set it before or after acting
	if s.get("free", false):
		# Quick Shot ignores `acted`; the fanned second shot only while unmoved (D87)
		return u.quick_shot_ready and not (int(u.fx.get("fan", 0)) > 0 and u.moved)
	return not u.acted


## Legal clicks for one skill in one element. A multi-hex foe can be clicked
## on any of its hexes that the skill reaches.
func skill_targets(u: BWUnit, key: String, element: String = "") -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := BWSkills.get_skill(key)
	if s.is_empty() or not u.alive():
		return out
	if s.needs_element and not element in learned_elements(u):
		return out
	out = BWSkillRegistry.get_def(key).targets(self, u, element)
	if u.statuses.has("blinded") and str(s.get("targeting", "")) != "self":
		# D94: Blinded can only target within 2 hexes
		var near: Array[Vector2i] = []
		for h in out:
			if BWHex.distance(u.pos, h) <= BWSkills.BLIND_RANGE:
				near.append(h)
		out = near
	if str(s.get("targeting", "")) in ["unit", "adjacent_unit"]:
		var seen: Array[Vector2i] = []        # D265: a unit in steam, only from within 2
		for h in out:
			var o := unit_at(h)
			if o == null or not BWPools.steam_hides(self, u, u.pos, o):
				seen.append(h)
		out = seen
	out = BWWind.filter_targets(self, u, out, s)   # D273: a Wind Wall blocks skills both ways
	return out


## What a skill would do, resolved but not applied: affected hexes, units hit
## and a forecast per unit (kind SKILL, or SPELL for the staff, with the same
## ground terms as forecast_basic). {} when the click is not legal.
## "ring" lists the hexes Cleaving / Channelling added (damage only).
## D109: `choice` is a second-pick skill's extra hex (NOWHERE = automatic).
func skill_preview(u: BWUnit, key: String, element: String, target_hex: Vector2i, choice: Vector2i = NOWHERE) -> Dictionary:
	var s := BWSkills.get_skill(key)
	if s.is_empty():
		return {}
	if not s.needs_element:
		element = ""
	if not target_hex in skill_targets(u, key, element) or not _choice_ok(u, key, element, target_hex, choice):
		return {}
	var p := _plan(u, s, element, target_hex, choice)
	var pre := BWWind.pre_hit(self, u, s, p, target_hex, true)   # D271: wind's mode first (positions only)
	var forecasts := {}
	for v in p.victims:
		forecasts[v.id] = _skill_forecast(u, s, p.element, v, p)
	BWWind.restore(pre)
	return {
		"wind": pre,                                             # D271: { moves, becalm, origin, mode }
		"skill": key, "element": p.element, "hexes": p.hexes, "steps": p.steps,
		"units": p.victims.map(func(v): return v.id), "forecasts": forecasts,
		"dest": p.dest, "shove": p.shove, "follow_up": s.get("follow_up", []),
		"ring": p.get("ring", []),
		# Flurry: each forecast is ONE strike; the skill lands `hits` of them.
		"hits": int(p.get("hits", 1)),
		# Uppercut: { unit, dir, hexes, path, slam: ""|rock|unit|edge, into }
		"knockback": p.get("knockback", {}),
		# D87: skill-level riders in words (slams, heals, statuses, reactions),
		# for the hint while aiming and the forecast box; per-target lines are
		# in each forecast's `notes`.
		"notes": p.get("notes", []),
		"reaction": p.get("reaction", ""),
		# D110: a strike made through attack() after the skill (Vault), for the confirm box
		"strike": BWSkillRegistry.get_def(key).strike_preview(self, u, p),
	}


## D109: a second pick must be one the def lists for this target.
func _choice_ok(u: BWUnit, key: String, element: String, target_hex: Vector2i, choice: Vector2i) -> bool:
	return choice == NOWHERE or choice in BWSkillRegistry.get_def(key).second_targets(self, u, element, target_hex)


## Resolve one skill. Returns the "skill" event ({} if not allowed).
## D109: `choice` is a second-pick skill's extra hex (NOWHERE = automatic).
func use_skill(u: BWUnit, key: String, element: String, target_hex: Vector2i, choice: Vector2i = NOWHERE) -> Dictionary:
	if over or u != current():
		return {}
	var s := BWSkills.get_skill(key)
	if s.is_empty():
		return {}
	if not s.needs_element:
		element = ""
	var allowed := false
	for row in skills_for(u):
		if row.key == key and element in row.elements:
			allowed = true
	if not allowed or not target_hex in skill_targets(u, key, element):
		return {}
	if not _choice_ok(u, key, element, target_hex, choice):
		return {}
	var p := _plan(u, s, element, target_hex, choice)
	var el: String = p.element
	BWBeams.spend_magnify(self, u, p)          # D289: a magnified cast spends this turn's Magnify
	_arced.clear()
	BWEnchant.begin_action(self, u)            # v2 hook
	BWWind.pre_hit(self, u, s, p, target_hex)  # D271: wind on every weapon, the mode BEFORE the hits
	# Direct hits read the ground BEFORE this action changes it (§7.3 step 2).
	var fcs: Array = []
	for v in p.victims:
		fcs.append(_skill_forecast(u, s, el, v, p))
	if not s.get("free", false) and not s.get("free_action", false):
		u.acted = true
	u.follow_up = []

	# Movement skills relocate first: the leap's flourish centres on landing.
	var d := BWSkillRegistry.get_def(key)
	d.relocate(self, u, p, target_hex)

	var results: Array = []
	var ko_any := false
	var counters: Array = []
	var blows: Array = []
	var struck: Array = []
	for i in p.victims.size():
		var v: BWUnit = p.victims[i]
		if not v.alive():
			continue
		var res := BWEnchant.roll_blow(self, u, v, fcs[i], false)   # v2 hook
		BWEnchant.land(self, u, v, res)
		var before := v.hp
		v.hp = maxi(0, v.hp - res.damage)
		var ko := not v.alive()
		ko_any = ko_any or ko
		results.append({ "target": v.id, "result": res, "forecast_hit": fcs[i].hit.value, "odds": odds(fcs[i]),
			"ko": ko, "target_hp": v.hp, "tags": _tags(fcs[i]) })
		blows.append([v, res, before])
		counters.append_array(_riposte_check(v, res))
		_note_struck(struck, v, res)
	var e := { "type": "skill", "unit": u.id, "skill": key, "element": el, "target": target_hex,
		"hexes": p.hexes, "results": results, "ko": ko_any }
	var hits := int(p.get("hits", 1))
	if hits > 1:
		e["hits"] = hits
	if p.has("bounce"):
		e["bounce"] = p.bounce                 # D87: Second Dagger's bounce victim
	if p.has("pierce_to"):
		e["pierce"] = p.pierce_to              # D87: Energized Shot's pierced foe
	d.decorate(e, p)
	_emit(e)
	for b in blows:
		_after_blow(u, b[0], b[1], b[2], "")
		BWEnchant.after_blow(self, u, b[0], b[1])   # v2 hook
		_conduct(u, b[0], int(b[1].damage))
	# Flurry: the remaining strikes, each its own roll and its own "attack"
	# event (strike k of n, like a Doubleshot), re-forecast so a spent riposte
	# guard or a Ward that just fired counts. Same pre-action ground (§7.3).
	for k in range(1, hits):
		for vic in p.victims:
			var v: BWUnit = vic
			if not v.alive() or over or not u.alive():
				continue
			var fc := _skill_forecast(u, s, el, v, p, k)
			var res := BWEnchant.roll_blow(self, u, v, fc, false)   # v2 hook
			BWEnchant.land(self, u, v, res)
			var before := v.hp
			v.hp = maxi(0, v.hp - res.damage)
			var ko := not v.alive()
			ko_any = ko_any or ko
			_emit({ "type": "attack", "unit": u.id, "target": v.id, "result": res, "forecast_hit": fc.hit.value, "odds": odds(fc),
				"ko": ko, "target_hp": v.hp, "strike": k, "strikes": hits, "pattern": key, "skill": key, "tags": _tags(fc) })
			_after_blow(u, v, res, before, "")
			BWEnchant.after_blow(self, u, v, res)       # v2 hook
			_conduct(u, v, int(res.damage))
			counters.append_array(_riposte_check(v, res))
			_note_struck(struck, v, res)
	_lay_on_struck(u, struck)
	d.after_hits(self, u, p, results)       # Uppercut's knockback, the Second Cut's stagger

	# The ground changes whatever the rolls were (§7.3 step 3, E11).
	var stripped := d.ground(self, u, el, target_hex, p)
	BWKeystoneFx.after_skill(self, u, p)       # D294 Glacier Wall: a shape on your pillar shatters it
	if not over and u.alive():
		d.after_paint(self, u, el, target_hex, p, results, stripped)
	if el == "wind" and not over and u.alive():
		_gust(u, blows)                        # D93 Gust
	if not over and u.alive():
		# D97 engine hooks: zone control (Set Spear), ally-attacked trigger (Covering Fire)
		var zh: Array = d.zone(self, u, p, target_hex)
		if not zh.is_empty():
			set_zone(u, zh, key)
		var ow: int = d.overwatch(self, u, p)
		if ow > 0:
			set_overwatch(u, ow, key)
	if el != "":
		u.attuned = el
		_lay_on(u, "cast", { "target_hex": target_hex, "element": el })
	# FX hook: skill_cd_minus (Quickdraw every time; Quick Draw once a battle).
	var cd := d.cooldown(u)
	if cd > 0:
		for fx in BWEffects.list(u, "skill_cd_minus"):
			if int(BWEffects.p(fx, "once_per_battle", 0)) == 1:
				if u.fx.has("cd_once:" + fx.source):
					continue
				u.fx["cd_once:" + fx.source] = true
			cd -= int(BWEffects.p(fx, "amount", 0))
		u.cooldowns[BWSkills.cd_key(key, element)] = maxi(cd, 0)
	# One award per action, for the element it carried (§8.4, E13).
	var grow_el := u.attuned if s.get("basic", false) else el
	_emit({ "type": "growth", "unit": u.id, "events": _award(u, ko_any, grow_el) })
	_after_action(u, el, BWSkills.is_damaging(key))
	if not d.keeps_momentum():
		u.fx.erase("momentum")                 # D87: spent by whatever followed the vault
	if s.has("follow_up") and not u.follow_up_used and u.alive() and not over:
		u.follow_up = (s.follow_up as Array).duplicate()
		u.follow_up_element = el
		u.follow_up_used = true
		u.acted = false                        # re-arm the action, for the listed keys only
		d.on_follow_up(self, u, p)             # Vault's momentum, Striketwice's first cut
		_emit({ "type": "follow_up", "unit": u.id, "allow": u.follow_up })
	_answer(counters)
	_counter_check(u, struck)
	_overwatch_check(u, struck)               # D97: Covering Fire
	if not u.alive():
		u.follow_up = []
	BWEnchant.end_action(self, u, BWSkills.is_damaging(key))   # v2 hook
	_check_end()
	return e


## Shape, victims and movement of one skill (ELEMENTS §7.2 table, §9).
## { hexes, steps, victims, element, dest, walk, shove [, points, ring, shares] }
## D87 riders ride along: notes (words for the hint), shares (per-victim
## damage cuts or boosts: [mult, label, tag?]), and per-skill keys (slam,
## bounce, pierce_to, same, reaction, sat_before, palm_push).
func _plan(u: BWUnit, s: Dictionary, element: String, target: Vector2i, choice: Vector2i = NOWHERE) -> Dictionary:
	var p := { "hexes": [], "steps": int(s.get("steps", 1)), "victims": [], "element": element,
		"dest": u.pos, "walk": [], "shove": {}, "notes": [], "shares": {}, "choice": choice }
	var d := BWSkillRegistry.get_def(str(s.key))
	d.plan(self, u, element, target, p)
	_widen(u, d, p)
	BWBeams.magnify(self, u, d, p)            # D289: an ally on a Magnify holder's light casts magnified
	BWOverheat.plan_notes(self, u, p)         # D285: the forecast names an Overheat
	BWOverfreeze.plan_notes(self, u, p)       # D312: ... an Overfreeze
	BWSquall.plan_notes(self, u, p)           # D309: ... a Squall
	p.victims = (p.victims as Array).filter(func(v): return can_harm(u, v))   # D140: the enemy's shapes pass over an obelisk
	return p


## D87: up to `reach` hexes past `to` on the straight line from `from`.
func _line_beyond(from: Vector2i, to: Vector2i, reach: int) -> Array:
	var n := BWHex.distance(from, to)
	if n == 0:
		return []
	var ac := BWHex.to_cube(from)
	var tc := BWHex.to_cube(to)
	var k := float(n + reach) / float(n)
	var x: float = ac.x + (tc.x - ac.x) * k
	var z: float = ac.z + (tc.z - ac.z) * k
	var far := BWHex.cube_round(x + 1e-6, -x - z - 2e-6, z + 1e-6)
	var whole := BWHex.line(from, far)
	var i := whole.find(to)
	return Array(whole.slice(i + 1)) if i >= 0 else []


## D87: is hex `h` behind `v`? The back three of its six sides, against the
## heading it last faced (BWUnit.facing: its last step, or the last thing it
## struck; at battle start, toward the nearest foe). Unknown facing = never.
func behind(v: BWUnit, h: Vector2i) -> bool:
	if v.facing < 0 or h == v.pos:
		return false
	var d := BWHex.direction_index(v.pos, h)
	return d >= 0 and ((d - v.facing + 6) % 6) in [2, 3, 4]


## D87: face `h` (the target of an attack or skill).
func _face(u: BWUnit, h: Vector2i) -> void:
	var d := BWHex.direction_index(u.pos, h)
	if d >= 0:
		u.facing = d


## Skill toolkit (BWSkillDef.relocate): move the user to the plan's `dest`
## along `path` (and its shoved unit to `shove.to`), counting the hexes and
## turning it to the heading. Emits the moves; no crossing damage, no lay_on
## (a running skill adds those itself: Charge).
func skill_relocate(u: BWUnit, p: Dictionary, path: Array, kind: String) -> void:
	var start := u.pos
	if not p.shove.is_empty():
		var t: BWUnit = p.shove.unit
		t.pos = p.shove.to                 # shoved units take no crossing damage
	u.pos = p.dest
	u.fx["moved_hexes"] = int(u.fx.get("moved_hexes", 0)) + path.size() - 1
	if p.dest != start:
		u.facing = BWHex.direction_index(start, p.dest)
	_emit({ "type": "move", "unit": u.id, "path": path, "kind": kind })
	if not p.shove.is_empty():
		_emit({ "type": "move", "unit": p.shove.unit.id, "path": [p.shove.from, p.shove.to], "kind": "shove" })
		BWSlides.after_push(self, p.shove.unit, BWHex.direction_index(p.shove.from, p.shove.to), u.id)   # D261


## FX hook: aoe_radius_plus skills=1 (Cleaving, Channelling). An AoE skill's
## shape reaches `radius` more rings for damage: foes there are hit at
## ring_pct% (allies too only with friendly=1). The ring is not painted: the
## ground keeps the skill's own shape (E10's lesson about free area denial).
func _widen(u: BWUnit, d: BWSkillDef, p: Dictionary) -> void:
	if not d.data.get("aoe", false) or p.hexes.is_empty():
		return
	for e in BWEffects.list(u, "aoe_radius_plus"):
		if int(BWEffects.p(e, "skills", 0)) != 1:
			continue
		var share := float(BWEffects.p(e, "ring_pct", 100)) / 100.0
		var mine := u.footprint()
		var ring: Array = []
		var shares := {}
		for h in _on_board(BWHex.fringe(p.hexes, int(BWEffects.p(e, "radius", 1)))):
			if h in p.hexes or h in mine:
				continue
			ring.append(h)
			var o := unit_at(h)
			if o == null or o == u or o in p.victims:
				continue
			if o.team == u.team and int(BWEffects.p(e, "friendly", 0)) != 1:
				continue
			p.victims.append(o)
			if share != 1.0:
				shares[o.id] = [share, "%s (outer ring)" % e.name]
		p["ring"] = ring
		(p["shares"] as Dictionary).merge(shares)
		return


## Charge / Vault (V8 _rush_destination): walk the heading as far as the
## ground allows. Vault stops at any unit. Charge stops at an ally or a
## second enemy, and shoves one enemy to the hex beyond where it ends; if that
## hex is blocked the charge stops short of the enemy instead (no shove).
## A multi-hex enemy stops the charge at its edge and is shoved one hex along
## the heading. immune displace (Unbowed, Rooted) also stops it short.
func _rush(u: BWUnit, toward: Vector2i, p: Dictionary, shove: bool) -> void:
	var dist := BWSkills.CHARGE_LEN if shove else BWSkills.VAULT_LEN
	var prev := u.pos
	var walk: Array = []
	var caught: BWUnit = null
	var caught_at := -1
	for h in board.ray(u.pos, toward, dist):
		if board.step_cost(prev, h) < 0:
			break
		var o := unit_at(h)
		if o != null and o != u:
			if o == caught or not shove or o.team == u.team or caught != null:
				break
			caught = o
			caught_at = walk.size()
		walk.append(h)
		prev = h
	if caught != null:
		var dest: Vector2i = walk[-1]
		var landing := BWHex.step_beyond(u.pos, dest)
		var from := dest
		if caught.size > 1:
			landing = BWHex.neighbors(caught.pos)[BWHex.direction_index(u.pos, toward)]
			from = caught.pos
		var ok := not _immune(caught, "displace") and board.step_cost(from, landing) >= 0 \
			and can_stand(caught, landing) and not dest in caught.footprint(landing)
		if ok:
			p.shove = { "unit": caught, "from": caught.pos, "to": landing }
		else:
			walk = walk.slice(0, caught_at)     # stop short; it stays put
			# D87: it slams into what stopped it (Uppercut's rule: rock or a unit
			# slams, the map edge is open air, an immune foe braced).
			if caught.size <= 1 and not _immune(caught, "displace") and board.exists(landing):
				var o := unit_at(landing)
				if o != null and o != caught and o != u:
					p["slam"] = { "unit": caught, "kind": "unit", "into": o }
				elif o == null:
					p["slam"] = { "unit": caught, "kind": "rock", "into": null }
	p.walk = walk
	p.dest = walk[-1] if not walk.is_empty() else u.pos


## `strike`: which strike of a multi-strike skill (Flurry) this forecast is.
func _skill_forecast(u: BWUnit, s: Dictionary, el: String, v: BWUnit, p: Dictionary = {}, strike: int = 0) -> Dictionary:
	if s.get("basic", false):
		return forecast_basic(u, v)
	var kind := BWFormulas.SPELL if s.get("spell", false) else BWFormulas.SKILL
	var power := int(s.get("power", 0))
	var d := BWSkillRegistry.get_def(str(s.key))
	var pc := d.power_formula(self, u, el, v, p)       # Consume: power from the points eaten
	if not pc.is_empty():
		power = int(pc.value)
	var mods := _mods(u, v, kind, el, false)
	var sh: Array = p.get("shares", {}).get(v.id, [])
	if not sh.is_empty():
		var m := { "stage": "dmg", "label": sh[1], "value": sh[0] }
		if sh.size() > 2:
			m["tag"] = sh[2]
		mods.append(m)
	var hits := int(p.get("hits", 1))
	if hits > 1:
		var pct := float(s.get("hit_pct", 100))
		mods.append({ "stage": "dmg", "value": pct / 100.0,
			"label": "%s: strike %d of %d at %d%%" % [s.name, strike + 1, hits, int(pct)] })
	# The skill's own riders (D87), labelled for the breakdown.
	var notes: Array = []
	d.forecast_mods(self, u, el, v, p, strike, mods, notes)
	var fc := BWFormulas.forecast(u, v, kind, power, el, 0.0, 0.0, 1.0, mods)
	if not pc.is_empty():
		fc["power"] = pc
	fc["notes"] = notes
	return _annotate(_guarded(fc, v), v, u)


## Melee reach (D31) at distance 1, line of sight beyond.
func _reaches(from: Vector2i, to: Vector2i, max_range: int) -> bool:
	var d := BWHex.distance(from, to)
	if d < 1 or d > max_range:
		return false
	if d == 1:
		return absi(board.elevation(from) - board.elevation(to)) <= MELEE_MAX_RISE
	return board.has_los(from, to)


## Foes covering any of `hexes`, each once (a 7-hex boss under a whole Surge
## is one victim).
func _foes_on(u: BWUnit, hexes: Array) -> Array:
	var out: Array = []
	for h in hexes:
		var o := unit_at(h)
		if o != null and o.team != u.team and not o in out and can_harm(u, o):
			out.append(o)
	return out


func _on_board(hexes: Array) -> Array:
	var out: Array = []
	for h in hexes:
		if board.exists(h):
			out.append(h)
	return out


func _without(hexes: Array, skip: Vector2i) -> Array:
	return hexes.filter(func(h): return h != skip)


## A pistol shot (basic or Quick Shot) spends the quick-shot readiness, and
## lays a seated element along its trail, once (§7.2, V8 _apply_loaded_trail).
func _fire_pistol(u: BWUnit, target: Vector2i) -> void:
	if u.weapon_class != "pistols":
		return
	u.quick_shot_ready = false
	if u.loaded == "":
		return
	var el := u.loaded
	u.loaded = ""
	paint(_on_board(BWHex.trail(u.pos, target)), el, u)


## A landed hit on a guarded unit spends the guard (V8: first blow only).
func _riposte_check(v: BWUnit, res: Dictionary) -> Array:
	if v.riposte.is_empty() or not res.hit:
		return []
	var el := str(v.riposte.get("element", ""))
	v.riposte = {}
	return [{ "unit": v, "element": el }]


## The answer: skill RIPOSTE_DMG to each enemy on the duelist's ring, then
## the ring takes the element. Counters cannot themselves be riposted.
func _answer(counters: Array) -> void:
	for c in counters:
		var d: BWUnit = c.unit
		if not d.alive() or over:
			continue
		var el: String = c.element
		var ring := _without(_on_board(board.area(d.pos, 1)), d.pos)
		var results: Array = []
		var blows: Array = []
		var landed := false
		for t in _foes_on(d, ring):
			var fc := BWFormulas.forecast(d, t, BWFormulas.SKILL, BWSkills.RIPOSTE_DMG, el,
				0.0, 0.0, 1.0, _mods(d, t, BWFormulas.SKILL, el, false))
			_obelisk_dodge(fc, t, d)                 # D142
			var res := roll(fc)
			BWEnchant.land(self, d, t, res)          # v2 hook
			var before: int = t.hp
			t.hp = maxi(0, t.hp - res.damage)
			landed = landed or res.hit
			results.append({ "target": t.id, "result": res, "forecast_hit": fc.hit.value, "odds": odds(fc),
				"ko": not t.alive(), "target_hp": t.hp, "tags": _tags(fc) })
			blows.append([t, res, before])
		_emit({ "type": "riposte", "unit": d.id, "element": el, "hexes": ring, "results": results })
		for b in blows:
			_after_blow(d, b[0], b[1], b[2], "riposte")
			BWEnchant.after_blow(self, d, b[0], b[1])   # v2 hook
			_conduct(d, b[0], int(b[1].damage))
		# D87: an answer that lands takes 1 off Riposte's cooldown.
		var ck := BWSkills.cd_key("riposte", el)
		if landed and d.alive() and int(d.cooldowns.get(ck, 0)) > 0:
			d.cooldowns[ck] = int(d.cooldowns[ck]) - 1
			_emit({ "type": "riposte_refund", "unit": d.id, "cd": d.cooldowns[ck] })
		if el != "":
			paint(ring, el, d)
		_check_end()


# ---------------------------------------------------------------- effects
# The battle-side halves of BWEffects: things that move units, roll, or emit.

## After one blow's event: KO (with trigger_stat knockout / ally_ko), or the
## victim's damage triggers (trigger_stat damaged / low_hp), and avoided.
func _after_blow(att: BWUnit, v: BWUnit, res: Dictionary, before: int, cause: String) -> void:
	_fault_lines(att, v, res)              # D93: a Shatter hit breaks the glaze
	BWOverheat.after_hurt(self, v)         # D286: Phoenix Heart's held KO Overheats the hex
	BWKeystoneFx.after_blow(self, att, v, res)   # D294: a landed hit thaws Frozen
	if not v.alive():
		if before > 0:
			_ko(v, att, cause)
		return
	_gale_force(att, v, res)               # D307: after moving 4+, the first hit applies your mode
	if not res.hit:
		_trigger(v, "avoided")             # FX hook: trigger_stat avoided (Poise, Tumble)
	elif res.damage > 0:
		_hurt_triggers(v, before)
	_perk_after_blow(att, v, res)          # D93: Pall, Ember Skin


func _note_struck(struck: Array, v: BWUnit, res: Dictionary) -> void:
	for s in struck:
		if s[0] == v:
			s[1] = s[1] or res.hit
			return
	struck.append([v, res.hit])


## FX hook: trigger_stat damaged and low_hp (Ward, Iron Wall, Enrage, Brace,
## Light Footed; Second Wind, Bloodied).
func _hurt_triggers(v: BWUnit, before: int) -> void:
	if not v.alive() or v.hp >= before:
		return
	_trigger(v, "damaged")
	var m := v.max_hp()
	for e in BWEffects.list(v, "trigger_stat"):
		if str(BWEffects.p(e, "trigger", "")) != "low_hp":
			continue
		var thr := float(BWEffects.p(e, "threshold", 50))
		if before * 100.0 >= thr * m and v.hp * 100.0 < thr * m:
			_fire_stat(v, e)
	_sanctuary_check(v, before)            # D93 Sanctuary
	BWEnchant.hurt(self, v, before)        # v2 hook: Rally Cry, Lifeline
	BWPhases.check(self)                   # D255: HP thresholds (the Twins' swap)


## A knockout event, plus trigger_stat knockout (the killer: Encore, Crowd
## Pleaser) and ally_ko (the fallen's team: Heavy Is the Head).
func _ko(victim: BWUnit, by: BWUnit, cause: String = "") -> void:
	var e := { "type": "ko", "unit": victim.id, "by": by.id if by != null else "" }
	if cause != "":
		e["cause"] = cause
	_emit(e)
	if by != null and by.team != victim.team:
		_trigger(by, "knockout")
	for a in side(victim.team):
		_trigger(a, "ally_ko")
	BWEnchant.on_ko(self, victim, by, cause)   # v2 hook: on-kill, ally_kill, ally_ko
	BWPhases.on_ko(self, victim)               # D255: a boss unit fell (the rage clock)
	BWCurse.on_ko(self, victim, by)            # D275: Lane C's Contagion hooks here


func _trigger(u: BWUnit, trig: String) -> void:
	if not u.alive() or u.effects.is_empty():
		return
	for e in BWEffects.list(u, "trigger_stat"):
		if str(BWEffects.p(e, "trigger", "")) == trig:
			_fire_stat(u, e)


## Fire a trigger_stat (D245: thresholds, not stacks). Gates: `hits` (fires
## on the Nth trigger), `once`, `times` (fires at most N times), `cap` (flat
## stat points per stat). Then, for the battle: `amount` flat or `pct` % of
## base + gear to each of `stats` ("stat_up"), `move` and `taken_pct` as the
## holder's own aura terms (BWEnchant.self_auras), and next_crit /
## next_dmg_pct / next_sure as an empowerment on the next attack.
func _fire_stat(u: BWUnit, e: Dictionary) -> void:
	var key := "ts:" + str(e.source)
	var hits := int(BWEffects.p(e, "hits", 0))
	if hits > 0:
		var n := int(u.fx.get(key + "@", 0)) + 1
		u.fx[key + "@"] = n
		if n < hits:
			return
	var fired := int(u.fx.get(key + "#", 0))
	if int(BWEffects.p(e, "once", 0)) == 1 and fired > 0:
		return
	if int(BWEffects.p(e, "times", 0)) > 0 and fired >= int(BWEffects.p(e, "times", 0)):
		return
	var given := int(u.fx.get(key, 0))
	var amt := int(BWEffects.p(e, "amount", 0))
	var cap := int(BWEffects.p(e, "cap", 0))
	if cap > 0:
		amt = mini(amt, cap - given)
		if amt <= 0:
			return
	u.fx[key + "#"] = fired + 1
	var stats := str(BWEffects.p(e, "stats", "")).split("+", false)
	var pct := float(BWEffects.p(e, "pct", 0))
	for s in stats:
		var a := amt
		if pct > 0.0:
			a = maxi(1, floori(BWEffects._raw_stat(u, s) * pct / 100.0))
		if a <= 0:
			continue
		u.battle_mods[s] = int(u.battle_mods.get(s, 0)) + a
		_emit({ "type": "stat_up", "unit": u.id, "stats": [s], "amount": a, "source": e.source, "name": e.name })
	if amt > 0 and pct <= 0.0:
		u.fx[key] = given + amt
	BWEnchant.trigger_extras(self, u, e)       # move / taken_pct / next attack (D245)


## One growth award, plus affinity_gain_plus (Whistling, Attuned).
func _award(u: BWUnit, ko: bool, el: String) -> Array:
	var events := BWProgression.award(u, ko, el)
	if el == "":
		return events
	var extra := 0
	for e in BWEffects.list(u, "affinity_gain_plus"):
		if e.element == "" or e.element == el:
			extra += int(BWEffects.p(e, "amount", 0))
	if extra > 0:
		var before := u.affinity_rank(el)
		u.affinity[el] = int(u.affinity.get(el, 0)) + extra
		events.append({ "type": "affinity_bonus", "element": el, "amount": extra })
		if u.affinity_rank(el) > before:
			events.append({ "type": "affinity_rank", "element": el, "rank": u.affinity_rank(el) })
	return events


## After an action: element_damage_pct next_same (Imbued) primes the element
## just used; an attacking action raises guard (Guarding) and, if the unit
## had already moved, grants move_after_attack (Flowing).
func _after_action(u: BWUnit, el: String, attacked: bool) -> void:
	if not u.alive():
		return
	if el != "":
		u.fx["imbued"] = el
	_after_action_move(u, el)              # D93: Bolt Step, Tailwind
	BWBeams.after_action(self, u, attacked)   # D287: an attack spends Empowered
	if not attacked:
		return
	for e in BWEffects.list(u, "guard"):
		if str(BWEffects.p(e, "when", "after_attack")) == "after_attack":
			u.fx["guard"] = maxf(float(u.fx.get("guard", 0)), float(BWEffects.p(e, "pct", 0)))
			u.fx["guard_name"] = e.name
			_emit({ "type": "guard", "unit": u.id, "pct": u.fx.guard, "name": e.name })
	if u.moved:
		for e in BWEffects.list(u, "move_after_attack"):
			u.fx["bonus_move"] = maxi(int(u.fx.get("bonus_move", 0)), int(BWEffects.p(e, "hexes", 0)))
		if int(u.fx.get("bonus_move", 0)) > 0:
			_emit({ "type": "bonus_move", "unit": u.id, "hexes": u.fx.bonus_move })


## FX hook: knockback on=hit. Positive hexes push straight away from the
## attacker, negative pull toward it.
func _knockback_hit(att: BWUnit, v: BWUnit) -> void:
	for e in BWEffects.list(att, "knockback"):
		if str(BWEffects.p(e, "on", "hit")) != "hit" or not _chance(e):
			continue
		var n := int(BWEffects.p(e, "hexes", 1))
		if int(BWEffects.p(e, "choice", 0)) == 1 and att.fx.get("force_pull", false):
			n = -absi(n)                       # D244 Forceful: the player chose pull on the forecast
		if n > 0:
			_displace(v, BWHex.direction_index(att.pos, v.pos), n, "knockback")
		elif n < 0:
			_displace(v, BWHex.direction_index(v.pos, att.pos), -n, "pull")


## Move `v` up to `n` hexes along heading `dir`, stopping before anything it
## can't stand on or climb. Displacement is not moving: no crossing damage,
## no lay_on. immune displace (Unbowed, Rooted, Unflinching) stops it.
## `elemental`: the push comes from an element (a gale, a blast, an
## eruption, Gust), so a Frost Ward or Nightborn can negate it (D93).
func _displace(v: BWUnit, dir: int, n: int, kind: String, elemental: bool = false) -> bool:
	if dir < 0 or n <= 0 or not v.alive() or over:
		return false
	if _immune(v, "displace"):
		_emit({ "type": "displace_resisted", "unit": v.id, "kind": kind })
		return false
	if elemental and _negate(v, "displacement"):
		return false
	n = BWCurse.gravity_step(self, v, dir, n)  # D276: a foe's dark 3 pulls (+1 toward, -1 away)
	var path: Array = push_path(v, dir, n).path
	if path.size() < 2:
		return false
	v.pos = path[-1]
	_emit({ "type": "move", "unit": v.id, "path": path, "kind": kind })
	BWSlides.after_push(self, v, dir)         # D261: pushed onto ice, it slides on
	return true


## Where a push of `n` hexes along `dir` would take `v`, and what stops it:
## { path: [start, ...], stop: "" (went the full way) | "rock" (jagged, or a
## rise too steep to be shoved up) | "unit" | "edge" (off the map), into:
## the blocking unit's name }. Pure: nothing moves. Immunity is not checked.
func push_path(v: BWUnit, dir: int, n: int) -> Dictionary:
	var cur := v.pos
	var path: Array = [cur]
	var stop := ""
	var into := ""
	for i in n:
		var nxt: Vector2i = BWHex.neighbors(cur)[dir]
		if board.step_cost(cur, nxt) < 0 or not can_stand(v, nxt):
			stop = "rock"
			for f in v.footprint(nxt):
				var o := unit_at(f)
				if o != null and o != v:
					stop = "unit"
					into = o.name
					break
				if not board.exists(f):
					stop = "edge"
			break
		cur = nxt
		path.append(cur)
	return { "path": path, "stop": stop, "into": into }


# ---------------------------------------------------------------- fists (D76)

## Sum of `param` over a unit's records of `key` that name `skill` (the fist
## enchantments ride existing keys with a skill= param: Welling, Rebound).
func _skill_rider(u: BWUnit, key: String, skill: String, param: String) -> int:
	var v := 0
	for e in BWEffects.list(u, key):
		if str(BWEffects.p(e, "skill", "")) == skill:
			v += int(BWEffects.p(e, param, 0))
	return v


## immune `what` from your own records, or from an ally's whose radius
## reaches you (Unflinching covers you and your neighbours).
func _immune(u: BWUnit, what: String) -> bool:
	if what == "displace" and BWObelisk.is_objective(u):
		return true                            # D140: an obelisk never moves
	if what == "displace" and u.encounter == "colossus":
		return true                            # D210: the Colossus is never moved
	if what == "displace" and BWEffects.has(u, "eye_of_storm"):
		return true                            # D93 Eye of the Storm
	if what == "displace" and BWKeystoneFx.holds(u):
		return true                            # D294: Frozen can't be displaced
	if what == "displace" and BWEnchant.planted(self, u):
		return true                            # v2: Planted
	for e in BWEffects.list(u, "immune"):
		if what in str(BWEffects.p(e, "what", "")).split("+"):     # D245 Sure Stride: muddy+water_wading
			return true
	for o in _fx_units:
		if o == u or not o.alive() or o.team != u.team:
			continue
		for e in BWEffects.list(o, "immune"):
			var r := int(BWEffects.p(e, "radius", 0))
			if str(BWEffects.p(e, "what", "")) == what and r >= 1 and gap(o, u) <= r:
				return true
	return false


func _chance(e: Dictionary) -> bool:
	var ch := float(BWEffects.p(e, "chance", 100))
	return ch >= 100.0 or rng.randf() * 100.0 < ch


## FX hook: lay_on (Emberstep, Shadowtrail, Soaking, Static, Gleaming,
## Frostbitten). Lays the row's element as a trigger, not a cast: no
## cast_step_plus or ring, and the unit's attuned element is unchanged.
## ctx: target_hex, attacker, dist, path.
func _lay_on(u: BWUnit, trigger: String, ctx: Dictionary) -> void:
	if over or not u.alive():
		return
	for e in BWEffects.list(u, "lay_on"):
		var lay_el: String = e.element
		if lay_el == "" and str(BWEffects.p(e, "element", "")) == "attuned":
			lay_el = u.attuned                     # v2 Rerouted: your attuned element
		if str(BWEffects.p(e, "trigger", "")) != trigger or lay_el == "":
			continue
		if trigger == "cast" and str(ctx.get("element", "")) != e.element:
			continue
		if int(BWEffects.p(e, "melee_only", 0)) == 1 and int(ctx.get("dist", 1)) > 1:
			continue
		var hexes: Array = []
		match str(BWEffects.p(e, "where", "target")):
			"target": hexes = [ctx.get("target_hex", NOWHERE)]
			"attacker":
				var a: BWUnit = ctx.get("attacker", null)
				if a != null and a.alive():
					hexes = [a.pos]
			"self": hexes = [u.pos]
			"path": hexes = ctx.get("path", [])
		hexes = _on_board(hexes)
		if hexes.is_empty() or not _chance(e):
			continue
		if int(BWEffects.p(e, "per_turn", 0)) == 1:   # D243 Frostbitten: the first basic each turn
			var tk := "lay_turn:%s:%s" % [str(e.source), trigger]
			if int(u.fx.get(tk, -1)) == _turn_serial:
				continue
			u.fx[tk] = _turn_serial
		paint(hexes, lay_el, u, maxi(1, int(BWEffects.p(e, "step", 1))), false)


func _lay_on_move(u: BWUnit, path: Array) -> void:
	if path.size() > 1:
		_lay_on(u, "move", { "path": path.slice(0, path.size() - 1) })


func _lay_on_struck(att: BWUnit, struck: Array) -> void:
	for s in struck:
		var v: BWUnit = s[0]
		if s[1] and v.alive():
			_lay_on(v, "struck", { "attacker": att, "dist": gap(v, att) })


## FX hook: counter_attack (Riposting). Each struck unit with the row strikes
## back at dmg_pct% of its basic attack if the attacker is within `range`,
## up to per_turn times in one enemy turn. Counters are never countered.
func _counter_check(att: BWUnit, struck: Array) -> void:
	for s in struck:
		var v: BWUnit = s[0]
		if over or not att.alive() or not v.alive() or v.team == att.team:
			continue
		for e in BWEffects.list(v, "counter_attack"):
			var r := int(BWEffects.p(e, "range", 1))
			if gap(v, att) > r or not _reaches_unit(v, v.pos, att, r):
				continue
			var turn_key := "%d:%d" % [cycle, turn_index]
			if str(v.fx.get("counter_turn", "")) != turn_key:
				v.fx["counter_turn"] = turn_key
				v.fx["counter_n"] = 0
			if int(v.fx.counter_n) >= int(BWEffects.p(e, "per_turn", 1)):
				continue
			v.fx.counter_n = int(v.fx.counter_n) + 1
			var share := float(BWEffects.p(e, "dmg_pct", 50)) / 100.0
			var fc := forecast_basic(v, att, share, "%s (counter)" % e.name)
			var res := roll(fc)
			BWEnchant.land(self, v, att, res)        # v2 hook
			var before := att.hp
			att.hp = maxi(0, att.hp - res.damage)
			_emit({ "type": "counter", "unit": v.id, "target": att.id, "result": res,
				"forecast_hit": fc.hit.value, "odds": odds(fc), "ko": not att.alive(), "target_hp": att.hp, "name": e.name, "tags": _tags(fc) })
			_after_blow(v, att, res, before, "counter")
			BWEnchant.after_blow(self, v, att, res)  # v2 hook
			_conduct(v, att, int(res.damage))
			_check_end()
			break


## FX hook: the situational stat bonus BWUnit.stat() adds in battle:
## stand_on_bonus (Blazing, Riptide, Shrouded, Sunlit, Rimed) and aura_mod
## stats and move (own passives, allies' supportives).
func _situational(u: BWUnit, key: String) -> int:
	var v := 0.0
	if key == "move":                      # D93: turn-start and after-action move perks
		v += float(u.fx.get("start_move", 0)) + float(u.fx.get("extra_move", 0))
		v += BWEnchant.move_mod(u)             # v2: Leaden's cost
		v += BWPhases.move_plus(self, u)       # D255: a boss phase's move (the Twins' rage)
	if _fx_units.is_empty():
		return int(v)
	for a in _auras(u, key):
		v += float(a.value)
	for e in BWEffects.list(u, "stand_on_bonus"):
		if str(BWEffects.p(e, "stat", "")) != key:
			continue
		if e.element in BWTiles.AXIS:
			var pts := tiles.intensity(u.pos, e.element)
			if pts > 0:
				v += BWEnchant.stand_on(u, e, key, pts)     # D196: % of the stat, the flat value as the floor
		elif e.element == "ice" and tiles.is_glazed(u.pos) or e.element != "ice" and tiles.carries(u.pos, e.element):
			v += BWEnchant.stand_on(u, e, key, 0)
	return int(v)


## aura_mod / glance_mod reaching `u`: [{label, value}] for a key, or forecast
## mods for "glance:melee" / "glance:ranged". Own rows with radius 0 (or
## allies=0) apply to the holder; radius ≥ 1 with allies=1 to allies within
## that many hexes, not the holder.
func _auras(u: BWUnit, key: String) -> Array:
	var out: Array = []
	if _fx_units.is_empty():
		return out
	if key.begins_with("glance:"):
		var vs := key.get_slice(":", 1)
		out.append_array(BWEffects.glance_mods(u, true, vs))
		for o in _fx_units:
			if o != u and o.alive() and o.team == u.team:
				for m in BWEffects.glance_mods(o, false, vs, gap(o, u)):
					out.append(m)
		return out
	for e in BWEffects.list(u, "aura_mod"):
		var r := int(BWEffects.p(e, "radius", 0))
		if (r == 0 or int(BWEffects.p(e, "allies", 0)) == 0) and float(BWEffects.p(e, key, 0)) != 0.0:
			out.append({ "label": e.name, "value": float(BWEffects.p(e, key)) })
	out.append_array(BWEnchant.self_auras(self, u, key))   # v2: Lockstep
	for o in _fx_units:
		if o == u or not o.alive() or o.team != u.team:
			continue
		for e in BWEffects.list(o, "aura_mod"):
			var r := int(BWEffects.p(e, "radius", 0))
			if r >= 1 and float(BWEffects.p(e, key, 0)) != 0.0 and gap(o, u) <= r:
				out.append({ "label": "%s (%s)" % [e.name, o.name], "value": float(BWEffects.p(e, key)) })
	return out


## Re-read every unit's effects (after changing gear or abilities mid-fight,
## which only tests and tools do).
func refresh_effects() -> void:
	for u in units:
		u.refresh_effects()
	_fx_units = units.filter(func(u: BWUnit): return not u.effects.is_empty())


func _tile_potency(source: String, element: String) -> float:
	if _fx_units.is_empty():
		return 1.0
	return BWEffects.potency(_unit(source), element)


## Tile damage to `u` with its damage_taken_mod tile_pct (Fireproof, Grounded).
## D130: a quarter from an element the unit is braced against (standing,
## crossing, eruptions, steam, detonations: every ground source comes here).
func _tile_dmg(u: BWUnit, pct: float, element: String, mult: float = 1.0) -> int:
	if u.braced_against(element):
		mult *= BWUnit.BRACE_TAKEN
	mult *= BWEnchant.tile_mult(u, element)   # v2: Pyre's cost
	mult *= BWCurse.taken_mult(u)              # D275: Rot
	return BWTiles.tile_damage(u, pct, element, mult * BWEffects.tile_taken(u, element))


# ---------------------------------------------------------------- turns

func wait() -> void:
	end_turn()


func end_turn() -> void:
	if over:
		return
	var u := current()
	if u:
		BWPhases.turn_end(self, u)  # D256: the Twins paint; a foe ending on the beam pays
		if over:
			return
		u.follow_up = []           # waiting declines a follow-up
		u.fx.erase("momentum")
		var st_steady: Dictionary = u.statuses.get("steadied", {})
		if not st_steady.is_empty() and st_steady.armed:   # D94: Steadied counts its holder's turns
			st_steady.turns = int(st_steady.turns) - 1
			if int(st_steady.turns) <= 0:
				u.statuses.erase("steadied")
				_emit({ "type": "status_end", "unit": u.id, "status": "steadied" })
		BWWind.turn_end(self, u)                   # D270: Becalmed ends into Restless (2 turns)
		BWCurse.turn_end(self, u)                  # D275: ending on a foe's dark: +1 Rot
		BWBeams.turn_end(self, u)                  # D287: Empowered lasts until the end of this turn
		for k in u.statuses.keys():                # D87: armed statuses end with this turn
			if u.statuses[k].armed and not u.statuses[k].get("keep", false):
				u.statuses.erase(k)
				_emit({ "type": "status_end", "unit": u.id, "status": k })
				if k == "staggered":               # D94: then immune to it for its next 2 turns
					u.statuses["steadied"] = { "armed": false, "keep": true, "turns": BWSkills.STEADIED_TURNS, "source": "" }
					_emit({ "type": "status", "unit": u.id, "status": "steadied", "label": BWSkills.STATUS.steadied[0],
						"rule": BWSkills.STATUS.steadied[1], "by": "" })
		u.fx["start_move"] = 0                     # D93: turn-start move is spent with the turn
		u.fx["extra_move"] = 0
		u.fx["move_notes"] = []
		BWEnchant.turn_end(self, u)                # v2 hook: Tending, empowerments, Planted
		_emit({ "type": "turn_end", "unit": u.id })
	turn_index += 1
	while turn_index < queue.size() and not queue[turn_index].alive():
		turn_index += 1
	if turn_index >= queue.size():
		_new_cycle()
	else:
		_begin_turn()


## D249: this fight's weather (BWWeather.KINDS, "" = none), seeded from the
## fight seed unless given. Call before setup() so cycle 1 shows the telegraphs.
func set_weather(kind: String, seed_value: int = -1) -> void:
	weather = BWWeather.start(self, kind, seed_value if seed_value >= 0 else int(rng.seed))


func _new_cycle() -> void:
	if cycle > 0:
		BWWind.tick(self)                      # D270: vortex fields pull, walls count down (v3 tick step 2)
		if over:
			return
		BWBeams.tick(self)                     # D287: light beams resolve (v3 tick step 3)
		if over:
			return
		var seeded := tiles.tick()
		_emit({ "type": "tiles_tick", "seeded": seeded, "spine": tiles.spine_tick.duplicate(true) })
		for er in tiles.eruptions:             # FX hook: tile_erupt, after the tick
			_erupt(er)
		if not over and not weather.is_empty():
			BWWeather.tick(self)               # D250: the weather acts at the cycle tick
		if over:
			return
	cycle += 1
	queue = BWTurnQueue.build(units)
	turn_index = 0
	_emit({ "type": "cycle", "cycle": cycle, "order": queue.map(func(u): return u.id) })
	BWPhases.new_cycle(self)               # D255: pending phases come due (the rage)
	_begin_turn()


func _begin_turn() -> void:
	var u := current()
	if u == null:
		return
	u.moved = false
	u.acted = false
	u.follow_up = []
	u.follow_up_used = false
	u.fx["moved_hexes"] = 0
	u.fx["bonus_move"] = 0
	if u.fx.has("guard"):          # FX hook: guard lasts until your next turn
		u.fx.erase("guard")
		_emit({ "type": "guard_end", "unit": u.id })
	if not u.riposte.is_empty():
		u.riposte = {}             # an unspent guard drops at your next turn (V8)
		_emit({ "type": "riposte_end", "unit": u.id })
	for k in u.cooldowns.keys():
		u.cooldowns[k] = maxi(0, u.cooldowns[k] - 1)
	u.fx.erase("momentum")
	for k in u.statuses:                           # D87: this is the turn they bite
		u.statuses[k].armed = true
	_turn_serial += 1
	_arced.clear()
	_expire_holds(u)                               # D97: zone / overwatch end at the holder's turn
	_emit({ "type": "turn", "unit": u.id, "team": u.team })
	if BWObelisk.is_objective(u):
		return                                     # D140: no ground, perks or statuses; BWAI pulses it
	_perk_turn_start(u)                            # D93: Frost Ward, Frostbite, Glare, move perks
	BWEnchant.turn_start(self, u)                  # v2 hook: Hearthbound, Sheltering, Beacon, banked move
	var night := BWEffects.has(u, "nightborn") or BWSets.no_drain(u)     # D93 Nightborn; D282 the Dark set: no dark drain on you
	if u.statuses.has("shrouded") and not night:
		_tile_hurt(u, _tile_dmg(u, BWSkills.SHROUD_DRAIN_PCT, "dark"), "shrouded", str(u.statuses.shrouded.source))
	# Standing on the ground: damage first, then healing (ELEMENTS §2.2).
	var st := tiles.standing(u.pos)
	var own := BWPhases.turn_start(self, u)        # D256: a Twin heals on its own colour instead
	if st.fire > 0 and u.alive():
		var half := 1.0
		for e in BWEffects.list(u, "ember_skin"):  # D93 Ember Skin: your standing fire halved
			half = float(BWEffects.p(e, "stand_pct", 50)) / 100.0
		_tile_hurt(u, _tile_dmg(u, st.fire, "fire", half), "fire", st.source)
	BWPools.turn_shock(self, u)                    # D264: an electrified pool shocks (after fire, before the drain)
	if st.drain > 0 and u.alive() and not night and not own:
		_tile_hurt(u, _tile_dmg(u, st.drain, "dark"), "dark", st.source)
	var heal := 0.0 if own else _light_heal(u, st)  # D93 Sanctuary / Glare
	if heal > 0 and u.alive():
		BWBeams.light_heal(self, u, heal, str(st.source))   # D288: Overflow turns the excess into a Ward of Light
	BWBeams.turn_start(self, u)                    # D287: Dawn, -1 on the longest cooldown on light 2+
	BWThunderKeys.turn_start(self, u)              # D291: Blast Rider's launch lock lifts
	BWWind.turn_start(self, u)                     # D270: starting on a gust field pushes 1
	if over:
		return
	if u.alive() and BWKeystoneFx.turn_start(self, u):   # D295 Riptide; D294 Frozen skips the turn
		if not over:
			end_turn()
		return
	if over:
		return
	if not u.alive():
		end_turn()


func _heal(u: BWUnit, pct: float, cause: String = "") -> void:
	if BWKeystoneFx.heal_blocked(self, u):              # D296 Event Horizon: no heals on its dark 3
		_emit({ "type": "enchant", "unit": u.id, "name": "Event Horizon", "text": "can't be healed" })
		return
	var blocked := BWEnchant.heal_blocked(u, cause)     # v2: Hollow, Forsaken
	if blocked != "":
		_emit({ "type": "enchant", "unit": u.id, "name": blocked, "text": "can't be healed" })
		return
	var amt := maxi(1, roundi(u.max_hp() * pct / 100.0))
	var healed := mini(amt, u.max_hp() - u.hp)
	u.hp += healed
	var e := { "type": "heal", "unit": u.id, "amount": healed, "hp": u.hp }
	if cause != "":
		e["cause"] = cause
	_emit(e)
	BWEnchant.on_healed(self, u, healed, cause)         # v2 hook: Mend-Link
	BWCurse.on_heal(self, u, cause)                     # D275: a light heal cleans 1 Rot


## Lay `element` on hexes for `by`, and deal any detonations (ELEMENTS §3.5,
## §8.2): occupant takes the blast, neighbours half, summed per unit.
## `cast` false = a lay_on trigger (no cast bonuses, attuned unchanged).
## FX hooks: BWEffects.paint_opts (tile_duration_plus, cast_step_plus,
## element_area_plus, tile_erupt), and on each detonation the credited unit's
## element_damage_pct thunder (Stormcaller's), element_area_plus thunder
## (Arcing: splash reaches further), effect_repeat thunder (Thundering: an
## echo at 50%), knockback on=trigger thunder (Jolting); on each gale the
## caster's knockback on=trigger wind (Howling).
func paint(hexes: Array, element: String, by: BWUnit, steps: int = 1, cast: bool = true, extra: Dictionary = {}) -> Dictionary:
	var o := BWEffects.paint_opts(by, element, hexes, board, cast)
	o.merge(extra, true)                       # v2: `propagated` (on-kill paint arrives as spread)
	var guard: Array = []                      # D307 Static Field: allies' paint can't set off your fuses
	for w in _fx_units:
		if w != by and w.team == by.team and BWEffects.has(w, "static_field"):
			guard.append(w.id)
	if not guard.is_empty():
		o["fuse_guard"] = guard
	BWKeystoneFx.paint_opts(by, o)             # D293 Jetstream: gale 3, copies last 2
	BWOverheat.paint_opts(by, element, o)      # D285: Conflagration
	hexes = BWThunderKeys.filter_rearm(self, by, element, hexes)   # D291: Blast Rider's locked hex
	var wsnap := BWWind.before_paint(self, hexes)   # D270: the fields about to fire (their mode)
	var r := tiles.apply(hexes, element, by.id, steps + int(o.steps_plus), o)
	BWThunderKeys.inject_self_det(self, by, o, r)    # D306: Self-detonate on the holder's own empty fuse
	BWThunderKeys.after_apply(self, by, element, r)   # D291: Daisy Chain, Blast Rider's self-detonation
	if cast:
		by.attuned = element
	var pe := { "type": "paint", "unit": by.id, "element": element, "hexes": r.changed }
	if not cast:
		pe["kind"] = "lay_on"
	for g in r.gales:
		if int(g.get("level", 1)) > 1:
			pe["gale2"] = true                 # D95: a gale 2 fired (radius 2 copies)
	if not r.gales.is_empty():                 # D160: which hexes each gale copied onto (preview, recap)
		pe["gales"] = r.gales.map(func(g): return { "origin": g.origin, "copies": (g.copies as Array).duplicate() })
	if r.has("pools"):
		pe["pools"] = r.pools                  # D262-D265: steam / rink / shock / pillars / melted
	_emit(pe)
	if not r.detonations.is_empty():
		by.fx["detonated"] = true              # D93 Bolt Step reads it after the action
	var hurt := {}       # unit -> [pct sum, source]
	var pushes: Array = []
	for d in r.detonations:
		var src := _unit(str(d.source))
		var mult := 1.0 + BWFormulas.AFFINITY_DMG_PER_RANK * (src.affinity_rank("thunder") if src else 0)
		var radius := 1
		var echoes: Array = []
		if src:
			for e in BWEffects.list(src, "element_damage_pct", "thunder"):
				if int(BWEffects.p(e, "next_same", 0)) != 1:
					mult *= 1.0 + float(BWEffects.p(e, "pct", 0)) / 100.0
			radius += int(BWEffects.total(src, "element_area_plus", "radius", "thunder"))
			mult *= BWEnchant.overload(src, int(d.get("points", 0)))   # v2: Overload
			for e in BWEffects.list(src, "effect_repeat", "thunder"):
				for k in int(BWEffects.p(e, "extra", 0)):
					echoes.append(float(BWEffects.p(e, "scale_pct", 100)) / 100.0)
		_emit({ "type": "detonate", "hex": d.hex, "pct": d.pct, "radius": radius })
		var factor := 1.0
		for sc in echoes:
			_emit({ "type": "detonate", "hex": d.hex, "pct": d.pct * sc, "radius": radius, "echo": true })
			factor += sc
		for u in units:
			if not u.alive():
				continue
			var dist := BWHex.distance(u.pos, d.hex)
			if dist > radius:
				continue
			var dmg := _tile_dmg(u, d.pct * factor, "thunder", mult)
			if dist >= 1:
				dmg = maxi(1, int(dmg / 2.0))
				for e in BWEffects.list(u, "grounded"):  # D93 Grounded: splash halved again
					dmg = maxi(1, int(dmg * float(BWEffects.p(e, "pct", 50)) / 100.0))
			var prev: Array = hurt.get(u, [0, str(d.source)])
			hurt[u] = [prev[0] + dmg, prev[1]]
		if src and src.alive():
			var occ := _centre_at(d.hex)
			for e in BWEffects.list(src, "knockback", "thunder"):
				if occ != null and occ != src and str(BWEffects.p(e, "on", "")) == "trigger" and _chance(e):
					pushes.append([occ, BWHex.direction_index(src.pos, d.hex), int(BWEffects.p(e, "hexes", 1))])
	for u in hurt:
		_tile_hurt(u, hurt[u][0], "detonation", hurt[u][1])
	BWEnchant.after_blast(self, hurt)          # v2 hook: Sapping
	BWOverheat.after_paint(self, by, r)        # D285: Overheat rings (events, 6% summed per unit)
	BWOverfreeze.after_paint(self, by, r)      # D312: Overfreeze bursts (12%, once per unit)
	for g in r.gales:
		for e in BWEffects.list(by, "knockback", "wind"):
			if str(BWEffects.p(e, "on", "")) != "trigger" or not _chance(e):
				continue
			for h in g.copies:
				var occ := _centre_at(h)
				if occ != null:
					pushes.append([occ, BWHex.direction_index(g.origin, h), int(BWEffects.p(e, "hexes", 1))])
	for pu in pushes:
		_displace(pu[0], pu[1], pu[2], "push", true)
	BWWind.after_paint(self, by, element, r, wsnap)   # D270: stamp the mode on new gales; fired fields act; copies carry states
	BWSquall.after_paint(self, by, r, wsnap)       # D309: a fresh gale on light/dark 2+ starts a squall
	BWKeystoneFx.after_paint(self, by, r)          # D294 Glacier Wall: its pillars last all battle
	BWEnchant.after_paint(self, by, element, r)   # v2 hook: Cold Snap, Windrider
	BWPhases.after_paint(self, hexes, element, by)   # D256: thunder breaks the Twins' beam
	return r


## FX hook: one tile_erupt going off (Explosive, Geyser, Collapsing, Flaring).
## Everyone whose centre is within `radius` takes dmg_pct × points (% max HP,
## the tile's element, after resistance); the owner's side heals heal_pct ×
## points; then `push` moves them (+ out from the tile, − in toward it; the
## occupant is pushed away from the owner). Nothing is painted, so an
## eruption never chains; the tick already erased the tile if `consume`.
func _erupt(er: Dictionary) -> void:
	if over:
		return
	var owner := _unit(str(er.owner))
	var hex: Vector2i = er.hex
	var pts := int(er.points)
	_emit({ "type": "erupt", "hex": hex, "element": er.element, "points": pts, "owner": er.owner,
		"radius": er.radius, "push": er.push, "consume": er.consume, "name": er.get("name", "") })
	var near: Array = []
	for u in units:
		if u.alive() and BWHex.distance(u.pos, hex) <= int(er.radius):
			near.append(u)
	for u in near:
		if int(er.heal_pct) > 0 and owner != null and u.team == owner.team and u.alive():
			_heal(u, float(er.heal_pct) * pts, "erupt")
	for u in near:
		if int(er.dmg_pct) > 0 and u.alive():
			_tile_hurt(u, _tile_dmg(u, float(er.dmg_pct) * pts, str(er.element)), "erupt", str(er.owner))
	var push := int(er.push)
	if push == 0 or over:
		return
	for u in near:
		if not u.alive():
			continue
		var dist := BWHex.distance(u.pos, hex)
		if push > 0:
			var dir := -1
			if dist >= 1:
				dir = BWHex.direction_index(hex, u.pos)
			elif owner != null and owner.pos != hex:
				dir = BWHex.direction_index(owner.pos, hex)
			_displace(u, dir, push, "push", true)
		elif dist >= 1:
			_displace(u, BWHex.direction_index(u.pos, hex), -push, "pull", true)


## D209: `u` takes nothing from damage of class `cls` (BWFormulas.damage_class);
## emits `immune` so the view can say so.
func _class_immune(u: BWUnit, cls: String) -> bool:
	if u == null or u.encounter == "" or not BWFormulas.immune_to(u, cls):
		return false
	_emit({ "type": "immune", "unit": u.id, "class": cls })
	return true


func _tile_hurt(u: BWUnit, amount: int, cause: String, source: String) -> void:
	if amount <= 0 or not u.alive() or BWObelisk.is_objective(u):
		return                                 # D141: ground, blasts and slams never hurt an obelisk
	if _class_immune(u, BWFormulas.damage_class({ "source": "tile" if cause in ELEMENTAL_CAUSES else cause })):
		return                                 # D209: a Blank shrugs off the ground, a Being a slam
	amount = BWOverheat.filter_hurt(self, u, amount, cause, source)   # D285-D291: Phoenix, Blast Rider, Ward of Light
	if amount <= 0 or not u.alive():
		return
	if cause in ELEMENTAL_CAUSES and _negate(u, cause):
		return                                 # D93: a Frost Ward / Nightborn took it
	var before := u.hp
	u.hp = maxi(0, u.hp - amount)
	_emit({ "type": "tile_damage", "unit": u.id, "amount": amount, "cause": cause, "hp": u.hp, "source": source })   # D119: source for the battle summary
	var src := _unit(source)
	if not u.alive():
		# KO credit to the tile's source if hostile (E14); no xp for tile damage itself.
		var by: BWUnit = src if src and src.team != u.team else null
		_ko(u, by, cause)
		if by != null:
			_emit({ "type": "growth", "unit": by.id, "events": _award(by, true, "") })
		_check_end()
	else:
		_hurt_triggers(u, before)
		BWOverheat.after_hurt(self, u)     # D286: Phoenix Heart's held KO Overheats the hex
	_conduct(src, u, amount)            # D86: tile damage on a fuse arcs too


# ---------------------------------------------------------------- D86 chain lightning

## The unit a conductive `v` arcs to: the nearest other living unit of v's
## team by hex distance (footprint gap), no range limit; ties go to the
## earlier unit in setup order (players, then enemies, as placed).
func _chain_target(v: BWUnit, skip: Array = []) -> BWUnit:
	var best: BWUnit = null
	var best_d := 1 << 20
	for o in units:
		if o == v or not o.alive() or o.team != v.team or o in skip or BWObelisk.is_objective(o):
			continue                               # D141: an obelisk is never arced to
		var d := gap(v, o)
		if d < best_d:
			best_d = d
			best = o
	return best


## ELEMENTS §8.5: `v` took `amount` while standing on a fuse (conductive), so
## CHAIN_FRACTION of it arcs to its nearest teammate. The arc is unrolled
## thunder ground damage (the victim's thunder resistance and tile_pct
## damage_taken_mod apply, min 1), credited to `by` for a KO, and it chains
## once: the arc never arcs again, even onto another fuse.
## D93 perks: Overcharge (the attacker's) sends a second arc at 50% of the
## first to the next-nearest, and then nobody is arced twice in one action;
## Lightning Rod pulls an arc meant for an ally within 3 onto the holder at
## 50%; Grounded halves an arc that reaches its holder; a Frost Ward or
## Nightborn negates one.
func _conduct(by: BWUnit, v: BWUnit, amount: int) -> void:
	if amount <= 0 or over or not (tiles.conductive(v.pos) or BWEnchant.conductive(v)) or BWObelisk.is_objective(v):
		return
	var oc := by != null and BWEffects.has(by, "overcharge")
	var skip: Array = _arced.keys() if oc else []
	var w := _chain_target(v, skip)
	if w == null:
		return
	var dealt := _arc(by, v, w, BWEnchant.chain_frac(by) * amount)   # v2: Lightning-Touched
	if not oc or over:
		return
	var w2 := _chain_target(v, _arced.keys() + [w])
	if w2 == null or dealt <= 0:
		return
	var pct := float(BWEffects.p(BWEffects.list(by, "overcharge")[0], "pct", 50)) / 100.0
	_arc(by, v, w2, dealt * pct, "overcharge")


## One arc of `raw` HP-points from `v` toward `w`. Returns the damage dealt.
func _arc(by: BWUnit, v: BWUnit, w: BWUnit, raw: float, kind: String = "") -> int:
	var rod := _rod_for(w, v)
	var e_extra := {}
	if rod != null:
		e_extra["rod"] = rod.id
		e_extra["meant"] = w.id
		raw *= float(BWEffects.p(BWEffects.list(rod, "lightning_rod")[0], "pct", 50)) / 100.0
		w = rod
	_arced[w] = true
	if _class_immune(w, BWFormulas.damage_class({ "source": "chain" })):
		return 0                               # D209: a Blank is never shocked
	if _negate(w, "chain"):
		return 0
	if w.braced_against("thunder"):               # D130: an arc is thunder
		raw *= BWUnit.BRACE_TAKEN
	for e in BWEffects.list(w, "grounded"):
		raw *= float(BWEffects.p(e, "pct", 50)) / 100.0
	var dmg := BWTiles.tile_damage(w, 100.0 * raw / maxf(w.max_hp(), 1.0),
		"thunder", BWEffects.tile_taken(w, "thunder"))
	if dmg <= 0:
		return 0
	var before := w.hp
	w.hp = maxi(0, w.hp - dmg)
	var ev := { "type": "chain", "from": v.id, "to": w.id, "amount": dmg, "hp": w.hp,
		"by": by.id if by != null else "", "hex": v.pos, "to_hex": w.pos }
	if kind != "":
		ev["kind"] = kind
	ev.merge(e_extra)
	_emit(ev)
	BWEnchant.after_arc(self, by, dmg)         # v2 hook: Conductor
	if not w.alive():
		var credit: BWUnit = by if by != null and by.team != w.team else null
		_ko(w, credit, "chain")
		if credit != null:
			_emit({ "type": "growth", "unit": credit.id, "events": _award(credit, true, "") })
		_check_end()
	else:
		_hurt_triggers(w, before)
	return dmg


## D93 Lightning Rod: a living teammate of `w` (not `w`, not the conductive
## `v`) holding the perk with `w` within its radius. First in setup order.
func _rod_for(w: BWUnit, v: BWUnit) -> BWUnit:
	for o in _fx_units:
		if o == w or o == v or not o.alive() or o.team != w.team:
			continue
		for e in BWEffects.list(o, "lightning_rod"):
			if gap(o, w) <= int(BWEffects.p(e, "radius", 3)):
				return o
	return null


# ---------------------------------------------------------------- D87 statuses

## Mark `v` with a short status (BWSkills.STATUS) until the end of its next
## turn. Re-applying refreshes it.
## D93: an elemental status (BWSkills.ELEMENTAL_STATUS, or `elemental` =
## 1 when an element lays it) can be negated by a Frost Ward or Nightborn.
## `armed` true = it lands at the holder's own turn start and ends with it.
func _add_status(v: BWUnit, key: String, by: BWUnit, elemental: int = -1, armed: bool = false) -> void:
	if not v.alive():
		return
	if key == "staggered" and v.statuses.has("steadied"):
		_emit({ "type": "status_resisted", "unit": v.id, "status": key, "reason": "Steadied: immune to stagger" })
		return                                 # D94: Steadied
	if BWObelisk.is_objective(v):                 # D141: stone takes no status
		_emit({ "type": "status_resisted", "unit": v.id, "status": key, "reason": "Stone" })
		return
	if BWEnchant.shrug_status(self, v, key, by):  # v2: Unshaken
		return
	if BWFormulas.strips_element(v) and (key in BWSkills.ELEMENTAL_STATUS if elemental < 0 else elemental == 1):
		_emit({ "type": "status_resisted", "unit": v.id, "status": key, "reason": "Immune: elemental" })
		return                                 # D209: no element effect lands on a Blank
	var el: bool = key in BWSkills.ELEMENTAL_STATUS if elemental < 0 else elemental == 1
	if v.immune_to_status(key) or (el and v.braced_against(status_element(key))):
		_emit({ "type": "status_resisted", "unit": v.id, "status": key,
			"reason": "Immune" if v.immune_to_status(key) else "Braced" })
		return                                 # D130: Wander's immunity / brace
	if el and _negate(v, "status:" + key):
		return
	v.statuses[key] = { "armed": armed, "source": by.id if by != null else "" }
	_emit({ "type": "status", "unit": v.id, "status": key, "label": BWSkills.STATUS[key][0],
		"rule": BWSkills.STATUS[key][1], "by": by.id if by != null else "" })


## D130: the element behind an elemental status (Saturate's table; an
## elemental Staggered is Static Field's thunder).
static func status_element(key: String) -> String:
	for el in BWSkills.SATURATE_STATUS:
		if BWSkills.SATURATE_STATUS[el] == key:
			return el
	return "thunder" if key == "staggered" else ""


func _unit(id: String) -> BWUnit:
	for u in units:
		if u.id == id:
			return u
	return null


func _check_end() -> void:
	if over:
		return
	if side("player").is_empty():
		over = true
		winner = "enemy"
	elif objective_mode():
		# D140: break any obelisk to win; wiping the enemy does not end it (the
		# pulses go on until a stone falls or the squad does, no time limit).
		if objectives().any(func(o: BWUnit): return not o.alive()):
			over = true
			winner = "player"
	elif side("enemy").is_empty():
		over = true
		winner = "player"
	if over:
		for u in units:
			u.fx_hook = Callable()             # the sheet reads plain again
			u.overcap = []                     # D98: over-cap skills were for this battle only
			u.zone = {}
			u.overwatch = {}
		_emit({ "type": "battle_end", "winner": winner })


func _emit(e: Dictionary) -> void:
	if e.type in _COMMITS:
		_undo = {}         # acting (or the turn ending) makes the move final
	e["cycle"] = cycle
	history.append(e)
	event.emit(e)
	if picks_live and e.type == "growth":
		_after_growth(_unit(str(e.unit)), e.events)


# ---------------------------------------------------------------- D90/D91 picks

## A growth award just landed: if it crossed an affinity or expertise rank,
## settle what needs no choice, and let an auto-pick team choose at once.
func _after_growth(u: BWUnit, events: Array) -> void:
	if u == null or not events.any(func(g): return g.type in ["affinity_rank", "expertise_rank"]):
		return
	var made: Array = BWPicks.auto_resolve(u) if u.team in auto_pick_teams else BWPicks.settle(u)
	for rec in made:
		_picked(u, rec)


## Whose pick is owed right now (player side, for the screen): [[unit, request]].
func pending_picks(team: String = "player") -> Array:
	var out: Array = []
	for u in units:
		if u.team != team:
			continue
		for rec in BWPicks.settle(u):      # rank-3 grants first, announced
			_picked(u, rec)
		var req := BWPicks.next_request(u)
		if not req.is_empty():
			out.append([u, req])
	return out


## The player's choice for an owed pick (BWPicks.apply). Emits "pick".
func apply_pick(u: BWUnit, req: Dictionary, choice: String) -> bool:
	var rec := BWPicks.apply(u, req, choice)
	if rec.is_empty():
		return false
	_picked(u, rec)
	return true


func _picked(u: BWUnit, rec: Dictionary) -> void:
	if rec.kind == "perk" or rec.kind == "keystone":   # D277: a keystone may be an effect source too
		u.refresh_effects()                # a perk is an effect source (BWEffects.collect)
		_fx_units = units.filter(func(o: BWUnit): return not o.effects.is_empty())
	elif str(rec.get("id", "")).begins_with("learn:"):
		# D98: a skill learned mid-fight is usable at once, over the cap if need be
		var key := str(rec.id).trim_prefix("learn:")
		if not key in u.loadout(str(rec.weapon)) and not key in u.overcap:
			u.overcap.append(key)
	var e := rec.duplicate()
	e["type"] = "pick"
	e["unit"] = u.id
	e["text"] = BWPicks.describe(u, rec)
	_emit(e)


# ---------------------------------------------------------------- D93 element perks
# The battle halves of the perk keys (BWEffects.PERK_KEYS, data/perks.csv,
# design/ELEMENTS.md §12). "Level" is the charge level of the hex
# (BWEffects.level_at). Every number is a labelled forecast term, a named
# move term (BWUnit.move_notes) or an event.

## Tile damage causes that count as an elemental effect (D93: a Frost Ward or
## Nightborn negates one). Slams and plain blows don't.
const ELEMENTAL_CAUSES := ["fire", "fire_cross", "dark", "detonation", "erupt", "shrouded", "steam", "ember_skin", "shock", "overheat", "light_beam", "overfreeze"]   # D285/D287/D312


## D93: negate one elemental effect landing on `u`, if it holds a negation.
## Nightborn (standing on dark, first effect each turn) goes before a Frost
## Ward so the ward is kept. Emits `ward_break`.
func _negate(u: BWUnit, what: String) -> bool:
	if u == null or not u.alive():
		return false
	if (BWEffects.has(u, "nightborn") or BWPerkRules.nightborn_cover(self, u)) and tiles.intensity(u.pos, "dark") > 0 \
			and int(u.fx.get("nightborn_turn", -1)) != _turn_serial:      # D281: an adjacent Nightborn ally covers it
		u.fx["nightborn_turn"] = _turn_serial
		_emit({ "type": "ward_break", "unit": u.id, "source": "nightborn", "what": what })
		return true
	if u.statuses.has("frost_ward"):
		var by := str(u.statuses.frost_ward.get("source", ""))
		u.statuses.erase("frost_ward")
		_emit({ "type": "ward_break", "unit": u.id, "source": "frost_ward", "by": by, "what": what })
		return true
	return false


## A labelled forecast term from a perk: points for hit/avoid/glance/crit,
## a multiplier for dmg.
func _stage_mod(mods: Array, stage: String, value: float, label: String) -> void:
	if value == 0.0:
		return
	if stage == "dmg":
		mods.append({ "stage": "dmg", "value": 1.0 + value / 100.0, "label": "%s: %+d%%" % [label, int(value)] })
	elif stage == "def_ignore":
		mods.append({ "stage": "def_ignore", "value": value / 100.0, "label": "%s: ignores %d%% DEF" % [label, int(value)] })
	elif stage == "crit_mult":
		mods.append({ "stage": "crit_mult", "value": value, "label": "%s: %+.1f crit multiplier" % [label, value] })
	else:
		mods.append({ "stage": stage, "value": value, "label": "%s: %+d %s" % [label, int(value), stage] })


## D96: the defender's facing against an attack from `ap`.
func _facing_mods(ap: Vector2i, dfn: BWUnit, mods: Array) -> void:
	if dfn.facing < 0 or ap == dfn.pos:
		return
	var d := BWHex.direction_index(dfn.pos, ap)
	if d < 0:
		return
	var m := BWFormulas.facing_mod((d - dfn.facing + 6) % 6)
	if not m.is_empty():
		mods.append(m)


## Is this a missile (Eye of the Storm): a bow or pistol attack, or a dagger
## thrown from beyond reach.
func _missile(att: BWUnit, dfn: BWUnit, ap: Vector2i) -> bool:
	return att.weapon_class in ["bow", "pistols"] or (att.weapon_class == "daggers" and gap(att, dfn, ap) > 1)


## The perks' forecast terms on one blow: stand_on_mod (Flow State, Current
## Push, Tidal Guard, Kindling, Ambush), Judgement, Eye of the Storm, Cover of
## Night, Rime Armour, and ◆ notes for Ember Skin and Pall.
func _perk_mods(att: BWUnit, dfn: BWUnit, ap: Vector2i, mods: Array) -> void:
	if _fx_units.is_empty():
		return
	for e in BWEffects.list(att, "stand_on_mod"):
		var side := str(BWEffects.p(e, "side", "def"))
		if side == "def":
			continue
		var on := str(BWEffects.p(e, "on", ""))
		var lv := BWEffects.level_at(tiles, ap, on)
		var where := "from"
		if side == "either":
			var lt := BWEffects.level_at(tiles, dfn.pos, on)
			if lt > lv:
				lv = lt
				where = "target on"
		if lv > 0:
			_stage_mod(mods, str(BWEffects.p(e, "stage", "dmg")), BWEffects.by_level(e, lv),
				"%s (%s %s)" % [e.name, where, BWEffects.ground_label(on, lv)])
	for o in _fx_units:
		if not o.alive() or o.team != dfn.team:
			continue
		for e in BWEffects.list(o, "stand_on_mod"):
			if str(BWEffects.p(e, "side", "def")) != "def" or (o != dfn and int(BWEffects.p(e, "team", 0)) != 1):
				continue
			var on := str(BWEffects.p(e, "on", ""))
			var lv := BWEffects.level_at(tiles, dfn.pos, on)
			if int(BWEffects.p(e, "own", 0)) == 1 and str(tiles.at(dfn.pos).get("glaze_source" if on == "ice" else "source", "")) != o.id:
				lv = 0                                 # v2 Permafrost: your own glaze only
			if lv > 0:
				_stage_mod(mods, str(BWEffects.p(e, "stage", "avoid")), BWEffects.by_level(e, lv),
					"%s (%s%s)" % [e.name, BWEffects.ground_label(on, lv), "" if o == dfn else ", " + o.name])
		if o != dfn:
			for e in BWEffects.list(o, "cover"):
				if gap(o, dfn) <= int(BWEffects.p(e, "radius", 1)):
					_stage_mod(mods, "hit", float(BWEffects.p(e, "hit", -7)), "%s (%s)" % [e.name, o.name])
	var lit := tiles.intensity(dfn.pos, "light")
	if lit > 0:
		for e in BWEffects.list(att, "judgement"):
			mods.append({ "stage": "glance_x", "value": 0.0, "label": "%s (target on Light %d): can't glance" % [e.name, lit] })
			break
	for e in BWEffects.list(dfn, "eye_of_storm"):
		if _missile(att, dfn, ap):
			_stage_mod(mods, "hit", float(BWEffects.p(e, "hit", -15)), "%s (missile)" % e.name)
			if int(BWEffects.p(e, "nocrit", 0)) == 1:     # D281: ranged can't crit it (was -15 hit)
				mods.append({ "stage": "crit_x", "value": 0.0, "label": "%s (missile): can't crit" % e.name })
	for e in BWEffects.list(dfn, "rime_armour"):
		if BWEffects.level_at(tiles, dfn.pos, "ice") > 0:
			_stage_mod(mods, "dmg", float(BWEffects.p(e, "pct", -10)), "%s (on ice)" % e.name)
	var fl := tiles.intensity(dfn.pos, "fire")
	if fl > 0 and gap(att, dfn, ap) <= 1 and att.team != dfn.team:
		for e in BWEffects.list(dfn, "ember_skin"):
			mods.append({ "stage": "note", "label": "%s: a hit burns %s for %d%%" % [e.name, att.name,
				int(float(BWEffects.p(e, "per_point", 2)) * fl)] })
	for e in BWEffects.list(att, "hit_status"):
		var on := str(BWEffects.p(e, "on", "dark"))
		if on == "any" or BWEffects.level_at(tiles, dfn.pos, on) >= int(BWEffects.p(e, "min", 1)):
			var st: Array = BWSkills.STATUS.get(str(BWEffects.p(e, "status", "")), ["?", ""])
			mods.append({ "stage": "note", "label": "%s: a hit leaves it %s" % [e.name, st[0]] })


## D93 Fault Lines: the attacker's Shatter hit breaks the glaze it read.
func _fault_lines(att: BWUnit, v: BWUnit, res: Dictionary) -> void:
	if att == null or not res.hit or not BWEffects.has(att, "fault_lines") or BWEffects.has(v, "rime_armour"):
		return
	if int(BWEffects.p(BWEffects.list(att, "fault_lines")[0], "nobreak", 0)) == 1:
		return                                     # D281: Fault Lines no longer breaks the glaze
	if tiles.break_glaze(v.pos):
		_emit({ "type": "glaze_break", "hex": v.pos, "unit": att.id, "name": "Fault Lines" })


## After a blow on a standing victim: Pall (the attacker's) and Ember Skin
## (the victim's).
func _perk_after_blow(att: BWUnit, v: BWUnit, res: Dictionary) -> void:
	if over or att == null or att.team == v.team or not res.hit:
		return
	if res.secondary:
		for e in BWEffects.list(att, "hit_status"):
			var on := str(BWEffects.p(e, "on", "dark"))
			if int(BWEffects.p(e, "basic", 0)) == 1 and not att.fx.get("_basic", false):
				continue                               # v2 Spotter: basic attacks only
			if on == "any" or BWEffects.level_at(tiles, v.pos, on) >= int(BWEffects.p(e, "min", 1)):
				_add_status(v, str(BWEffects.p(e, "status", "blinded")), att, 1)
	BWPerkRules.after_blow(self, att, v, res)      # D281: Current Push's push along the water
	var fl := tiles.intensity(v.pos, "fire")
	if fl > 0 and att.alive() and v.alive() and gap(v, att) <= 1:
		for e in BWEffects.list(v, "ember_skin"):
			_emit({ "type": "perk", "unit": v.id, "perk": e.name, "target": att.id })
			_tile_hurt(att, _tile_dmg(att, float(BWEffects.p(e, "per_point", 2)) * fl, "fire"), "ember_skin", v.id)
			break


## D93 Sanctuary: once per battle, an ally within 3 of the holder dropping
## under 35% HP gets light 2 on its hex.
func _sanctuary_check(v: BWUnit, before: int) -> void:
	if over or not v.alive():
		return
	var m := v.max_hp()
	for o in _fx_units:
		if o == v or not o.alive() or o.team != v.team or o.fx.get("sanctuary_used", false):
			continue
		for e in BWEffects.list(o, "sanctuary"):
			var thr := float(BWEffects.p(e, "threshold", 35))
			if gap(o, v) <= int(BWEffects.p(e, "radius", 3)) and before * 100.0 >= thr * m and v.hp * 100.0 < thr * m:
				o.fx["sanctuary_used"] = true
				_emit({ "type": "perk", "unit": o.id, "perk": e.name, "target": v.id, "hex": v.pos })
				paint([v.pos], "light", o, int(BWEffects.p(e, "steps", 2)), false)
				return


## Light healing at a turn start, with Sanctuary (the tile's layer heals its
## own side more) and Glare (it heals no foe of its layer).
func _light_heal(u: BWUnit, st: Dictionary) -> float:
	var heal: float = st.heal * BWWeather.heal_mult(weather)   # D250: Eclipse, light heals x2
	if heal <= 0.0:
		return 0.0
	var src := _unit(str(st.source))
	if src == null:
		return heal
	if src.team != u.team:
		for e in BWEffects.list(src, "glare"):
			_emit({ "type": "perk", "unit": src.id, "perk": e.name, "target": u.id, "what": "no_heal" })
			return 0.0
	else:
		for e in BWEffects.list(src, "sanctuary"):
			return maxf(heal, BWEffects.by_level(e, tiles.intensity(u.pos, "light")))
	return heal


## Bolt Step (an action that detonated something) and Tailwind (a wind
## action): more move, after a move (bonus_move) or on top of the turn's.
func _after_action_move(u: BWUnit, el: String) -> void:
	var more := 0
	var names: Array = []
	if u.fx.get("detonated", false):
		u.fx.erase("detonated")
		for e in BWEffects.list(u, "bolt_step"):
			more += int(BWEffects.p(e, "hexes", 2))
			names.append(e.name)
	if el == "wind":
		for e in BWEffects.list(u, "tailwind"):
			more += int(BWEffects.p(e, "after", 1))
			names.append(e.name)
	more = BWThunderKeys.launch_move(u, more, names)   # D291: Blast Rider's launch replaces Bolt Step's +2
	if more <= 0:
		return
	if u.moved:
		u.fx["bonus_move"] = int(u.fx.get("bonus_move", 0)) + more
		_emit({ "type": "bonus_move", "unit": u.id, "hexes": u.fx.bonus_move, "perks": names })
	else:
		u.fx["extra_move"] = int(u.fx.get("extra_move", 0)) + more
		_emit({ "type": "move_bonus", "unit": u.id, "amount": more, "notes": names })


## D93 Gust: each foe a wind skill hit (and didn't resist) is pushed 1 away;
## if rock or a unit stops it, it slams for slam_pct% (the edge is open air).
func _gust(u: BWUnit, blows: Array) -> void:
	var gs := BWEffects.list(u, "gust")
	if gs.is_empty():
		return
	var e: Dictionary = gs[0]
	for b in blows:
		var v: BWUnit = b[0]
		var res: Dictionary = b[1]
		if over or not v.alive() or not res.hit or not res.secondary or v.team == u.team:
			continue
		if BWWind.moved_this_action(self, v):
			continue                               # D272: wind moves a unit once per action
		var dir := BWHex.direction_index(u.pos, v.pos)
		if dir < 0:
			continue
		if _immune(v, "displace"):
			_emit({ "type": "displace_resisted", "unit": v.id, "kind": "gust" })
			continue
		if _negate(v, "displacement"):
			continue
		var pp := push_path(v, dir, int(BWEffects.p(e, "push", 1)))
		if (pp.path as Array).size() > 1:
			_displace(v, dir, (pp.path as Array).size() - 1, "push")
		if str(pp.stop) in ["rock", "unit"]:
			_emit({ "type": "slam", "unit": v.id, "by": u.id, "into": pp.stop, "name": e.name })
			_tile_hurt(v, _tile_dmg(v, float(BWEffects.p(e, "slam_pct", 8)), ""), "slam", u.id)


## D307 Gale Force's v3 rider: after moving GALE_FORCE_MOVED+ hexes this turn,
## the holder's first landed hit on a foe applies its wind mode (once a turn,
## within the wind caps: nothing if the foe was already moved this action).
func _gale_force(att: BWUnit, v: BWUnit, res: Dictionary) -> void:
	if att == null or over or not res.get("hit", false) or v.team == att.team or not v.alive():
		return
	if not att.perks.has(GALE_FORCE) or int(att.fx.get("moved_hexes", 0)) < GALE_FORCE_MOVED:
		return
	if int(att.fx.get("gale_force_turn", -1)) == _turn_serial or BWWind.moved_this_action(self, v):
		return
	if BWFormulas.strips_element(v):
		return
	att.fx["gale_force_turn"] = _turn_serial
	BWWind.apply_mode(self, att, BWWind.mode(att), [v], att.pos, false)


## A unit's turn start: per-turn perk state, Frost Ward, Frostbite, Glare's
## blind, and the turn-start move terms.
func _perk_turn_start(u: BWUnit) -> void:
	for k in ["heat_rush_used", "shadowstep_used", "detonated", "free_water_used"]:
		u.fx.erase(k)
	u.fx["extra_move"] = 0
	u.fx["start_move"] = 0
	u.fx["move_notes"] = []
	if _fx_units.is_empty():
		return
	for e in BWEffects.list(u, "frost_ward"):
		# D93 cadence: a ward on the holder's 1st turn, then every 2nd turn
		if u.statuses.has("ward_cd"):
			u.statuses.erase("ward_cd")
			_emit({ "type": "status_end", "unit": u.id, "status": "ward_cd" })
			break
		u.statuses["ward_cd"] = { "armed": true, "keep": true, "source": u.id }
		_emit({ "type": "status", "unit": u.id, "status": "ward_cd", "label": BWSkills.STATUS.ward_cd[0],
			"rule": BWSkills.STATUS.ward_cd[1], "by": u.id })
		var r := int(BWEffects.p(e, "radius", 2))
		var best: BWUnit = null
		for o in side(u.team):
			if o == u or o.statuses.has("frost_ward") or gap(u, o) > r:
				continue
			if best == null or gap(u, o) < gap(u, best):
				best = o
		if best == null and not u.statuses.has("frost_ward"):
			best = u
		if best != null:
			best.statuses["frost_ward"] = { "armed": true, "keep": true, "source": u.id }
			_emit({ "type": "status", "unit": best.id, "status": "frost_ward", "label": BWSkills.STATUS.frost_ward[0],
				"rule": BWSkills.STATUS.frost_ward[1], "by": u.id })
		break
	if tiles.is_glazed(u.pos):
		var gsrc := _unit(str(tiles.at(u.pos).get("glaze_source", "")))
		if gsrc != null and gsrc.team != u.team:
			for e in BWEffects.list(gsrc, "frostbite"):
				_add_status(u, str(BWEffects.p(e, "status", "drenched")), gsrc, 1, true)
				break
	var lt := tiles.intensity(u.pos, "light")
	if lt > 0 and u.alive():
		var lsrc := _unit(str(tiles.at(u.pos).get("source", "")))
		if lsrc != null and lsrc.team != u.team:
			for e in BWEffects.list(lsrc, "glare"):
				if lt >= int(BWEffects.p(e, "min", 2)):
					_add_status(u, str(BWEffects.p(e, "status", "blinded")), lsrc, 1, true)
				break
	_start_move(u)


## Turn-start move: start_move (Coal Engine for the team, Sunpath), Skate,
## Tailwind and allies' Slipstream. Kept in fx for move_range() and named in
## fx.move_notes for the Move hover.
const SUNPATH := "light_sun"
const GALE_FORCE := "wind_force"
const GALE_FORCE_MOVED := 4

func _start_move(u: BWUnit) -> void:
	var notes: Array = []
	for o in _fx_units:
		if not o.alive() or o.team != u.team:
			continue
		for e in BWEffects.list(o, "start_move"):
			if o != u and int(BWEffects.p(e, "team", 0)) != 1:
				continue
			var on := str(BWEffects.p(e, "on", ""))
			var lv := BWEffects.level_at(tiles, u.pos, on)
			var val := int(BWEffects.by_level(e, lv))
			if val != 0:
				notes.append(["%s (%s%s)" % [e.name, BWEffects.ground_label(on, lv), "" if o == u else ", " + o.name], val])
		if o != u and o.perks.has(SUNPATH) and BWBeams.on_beam_of(self, o, u):
			notes.append(["Sunpath (on %s's beam)" % o.name, 1])   # D307: the v3 rider, read live
		if o != u:
			for e in BWEffects.list(o, "slipstream"):
				if gap(o, u) <= int(BWEffects.p(e, "radius", 2)):
					notes.append(["%s (%s)" % [e.name, o.name], int(BWEffects.p(e, "move", 1))])
	for e in BWEffects.list(u, "skate"):
		if BWEffects.level_at(tiles, u.pos, "ice") > 0:
			notes.append(["%s (on ice)" % e.name, int(BWEffects.p(e, "move", 1))])
	for e in BWEffects.list(u, "tailwind"):
		if str(tiles.at(u.pos).get("marker", "")) == "gale":
			notes.append(["%s (on a gale)" % e.name, int(BWEffects.p(e, "start", 2))])
	var total := 0
	for n in notes:
		total += int(n[1])
	u.fx["start_move"] = total
	u.fx["move_notes"] = notes
	if total != 0:
		_emit({ "type": "move_bonus", "unit": u.id, "amount": total, "notes": notes.map(func(n): return n[0]) })


## D93 Static Field: a foe ending its move on a fuse laid by a holder.
func _static_field_check(u: BWUnit) -> void:
	var en := tiles.at(u.pos)
	if str(en.get("marker", "")) != "fuse":
		return
	var src := _unit(str(en.get("source", "")))
	if src == null or src.team == u.team:
		return
	for e in BWEffects.list(src, "static_field"):
		_add_status(u, str(BWEffects.p(e, "status", "staggered")), src, 1)
		return


# ---------------------------------------------------------------- D93 movement perks, D97 zones

## What a unit's search needs beyond the board's: move_cost (Waterwalking),
## Skate, Heat Rush, Shadowstep (each once per turn) and enemy zones.
func _move_rules(u: BWUnit) -> Dictionary:
	var r := {}
	if not u.effects.is_empty():
		for e in BWEffects.list(u, "move_cost"):
			if int(BWEffects.p(e, "once", 0)) == 1:             # D204 Waterwalking: the first one each turn
				if not u.fx.get("free_water_used", false):
					r["free_on"] = str(BWEffects.p(e, "on", "water"))
			else:
				r["cost_on"] = [str(BWEffects.p(e, "on", "water")), int(BWEffects.p(e, "cost", 0))]
		for e in BWEffects.list(u, "skate"):
			r["skate"] = int(BWEffects.p(e, "cost", 1))
		if not u.fx.get("heat_rush_used", false):
			for e in BWEffects.list(u, "heat_rush"):
				r["heat"] = int(BWEffects.p(e, "move", 1))
		if not u.fx.get("shadowstep_used", false):
			for e in BWEffects.list(u, "shadowstep"):
				r["shadow"] = [int(BWEffects.p(e, "range", 3)), int(BWEffects.p(e, "cost", 1)), int(BWEffects.p(e, "los", 0))]
	var z := _enemy_zones(u)
	if not z.is_empty():
		r["zone"] = z
	BWWind.stop_rules(self, u, r)             # D270: gust fields and a foe's becalm fields end a walk
	BWCurse.move_rules(self, u, r)            # D276: a foe's dark 3 is heavy to climb out of
	BWKsIce.move_rules(self, u, r)            # D294 Skater: the first 4 ice hexes cost 0
	return r


## Every hex of an enemy zone: hex -> holder.
func _enemy_zones(u: BWUnit) -> Dictionary:
	var z := {}
	for o in units:
		if o.alive() and o.team != u.team and not o.zone.is_empty():
			for h in o.zone.get("hexes", []):
				z[h] = o
	return z


## One step's cost under the unit's perks.
func _perk_step(rules: Dictionary, h: Vector2i, n: Vector2i, sc: int) -> int:
	var g := BWCurse.step_extra(rules, h, n)        # D276: +1 to step out of a foe's dark 3
	if rules.has("cost_on") and BWEffects.level_at(tiles, n, str(rules.cost_on[0])) > 0:
		return int(rules.cost_on[1]) + g
	if rules.has("skate") and BWEffects.level_at(tiles, n, "ice") > 0:
		return int(rules.skate) + maxi(board.elevation(n) - board.elevation(h), 0) + g
	return sc + g


## Dijkstra like BWBoard.reachable, over (hex, once-per-turn bonuses spent):
## bit 1 = Heat Rush's +1 (the first fire hex entered), bit 2 = Shadowstep's
## jump (dark hex to dark hex within range, for `cost`, ignoring the path).
## Entering an enemy zone hex ends the search there. Each hex keeps its
## cheapest state; `path` is that state's route (BWBoard.path_to reads it).
func _reach_fx(u: BWUnit, budget: int, blocked: Dictionary, no_stop: Dictionary, opts: Dictionary, rules: Dictionary) -> Dictionary:
	var fp := int(opts.get("footprint", 0))
	var start := u.pos
	var zone: Dictionary = rules.get("zone", {})
	var k0 := Vector3i(start.x, start.y, 0)
	var best := { k0: [0, k0] }
	var frontier: Array = [[0, k0]]
	while not frontier.is_empty():
		var idx := 0
		for i in frontier.size():
			if frontier[i][0] < frontier[idx][0]:
				idx = i
		var cur: Array = frontier.pop_at(idx)
		var cost: int = cur[0]
		var k: Vector3i = cur[1]
		if cost > best[k][0]:
			continue
		var h := Vector2i(k.x, k.y)
		if h != start and zone.has(h):
			continue                                  # D97: a zone hex ends the move
		var steps: Array = []
		for n in board.neighbors(h):
			if blocked.has(n) or (fp > 0 and not board.fits(n, fp, blocked)):
				continue
			var sc := board.step_cost(h, n, opts)
			if sc < 0:
				continue
			sc = _perk_step(rules, h, n, sc)
			var nm := k.z
			if rules.has("skater"):                   # D294 Skater: free ice hexes, counted in bits 3+
				var sk := BWKsIce.step(self, rules, h, n, sc, nm)
				sc = sk[0]
				nm = sk[1]
			if rules.has("heat") and nm & 1 == 0 and tiles.intensity(n, "fire") > 0:
				nm |= 1
				sc = maxi(0, sc - int(rules.heat))
			if rules.has("free_on") and nm & 4 == 0 and BWEffects.level_at(tiles, n, str(rules.free_on)) > 0:
				nm |= 4                                   # D204 Waterwalking: this hex costs nothing
				sc = 0
			steps.append([n, sc, nm])
		if rules.has("shadow") and k.z & 2 == 0 and tiles.intensity(h, "dark") > 0:
			for t in board.area(h, int(rules.shadow[0])):
				if t == h or blocked.has(t) or not board.is_passable(t) or tiles.intensity(t, "dark") <= 0:
					continue
				if rules.shadow.size() > 2 and int(rules.shadow[2]) == 1 and not board.has_los(h, t):
					continue                                  # D281: Shadowstep needs sight of the hex
				if fp > 0 and not board.fits(t, fp, blocked):
					continue
				steps.append([t, int(rules.shadow[1]), k.z | 2])
		for st in steps:
			var nc: int = cost + int(st[1])
			if nc > budget:
				continue
			var nk := Vector3i(st[0].x, st[0].y, st[2])
			if not best.has(nk) or nc < best[nk][0]:
				best[nk] = [nc, k]
				frontier.append([nc, nk])
	var pick := {}                                    # hex -> state key
	for key in best:
		var hh := Vector2i(key.x, key.y)
		if not pick.has(hh) or best[key][0] < best[pick[hh]][0] \
				or (best[key][0] == best[pick[hh]][0] and key.z < pick[hh].z):
			pick[hh] = key
	var out := {}
	for hh in pick:
		var path: Array = []
		var key: Vector3i = pick[hh]
		while true:
			path.push_front(Vector2i(key.x, key.y))
			var prev: Vector3i = best[key][1]
			if prev == key:
				break
			key = prev
		var stop: bool = hh == start or not no_stop.has(hh)
		if fp > 0 and hh != start:
			for f in BWHex.area(hh, fp):
				if no_stop.has(f):
					stop = false
		out[hh] = { "cost": best[pick[hh]][0], "from": path[-2] if path.size() > 1 else hh, "stop": stop, "path": path }
	return out


## D93 Undertow: the enemy holder's pull, while any water `level`+ hex exists.
func _undertow_for(u: BWUnit) -> Dictionary:
	for o in _fx_units:
		if not o.alive() or o.team == u.team:
			continue
		for e in BWEffects.list(o, "undertow"):
			var lvl := int(BWEffects.p(e, "level", 3))
			var pools: Array = []
			for h in tiles.entries:
				if tiles.intensity(h, "water") >= lvl:
					pools.append(h)
			if pools.is_empty():
				return {}
			return { "move": int(BWEffects.p(e, "move", 1)), "pools": pools, "name": e.name, "holder": o.id }
	return {}


## Undertow's filter over a reach searched with move+1: closer to the
## nearest pool keeps the +1, level with it gets the normal move, farther
## loses 1. Filtered hexes stay routable (stop = false).
func _undertow_filter(u: BWUnit, r: Dictionary, budget: int, pull: Dictionary) -> void:
	var m := int(pull.move)
	var d0 := _nearest(u.pos, pull.pools)
	for h in r:
		if h == u.pos or not r[h].stop:
			continue
		var dd := _nearest(h, pull.pools)
		var allowed := budget if dd < d0 else (budget - m if dd == d0 else budget - 2 * m)
		if int(r[h].cost) > allowed:
			r[h].stop = false
			r[h]["undertow"] = true


func _nearest(h: Vector2i, pools: Array) -> int:
	var best := 1 << 20
	for p in pools:
		best = mini(best, BWHex.distance(h, p))
	return best


## A move just taken: spend Heat Rush (first fire hex entered) and
## Shadowstep (a jump in the path), and say so on the move event.
func _mark_move_perks(u: BWUnit, path: Array, e: Dictionary) -> void:
	var heat: bool = BWEffects.has(u, "heat_rush") and not u.fx.get("heat_rush_used", false)
	var free_water: bool = str(_move_rules(u).get("free_on", "")) != ""
	for i in range(1, path.size()):
		if free_water and BWEffects.level_at(tiles, path[i], "water") > 0:
			free_water = false
			u.fx["free_water_used"] = true             # D204 Waterwalking: spent
			e["free_water"] = path[i]
		if BWHex.distance(path[i - 1], path[i]) > 1:
			u.fx["shadowstep_used"] = true
			e["shadowstep"] = [path[i - 1], path[i]]
		if heat and tiles.intensity(path[i], "fire") > 0:
			heat = false
			u.fx["heat_rush_used"] = true
			e["heat_rush"] = path[i]


# ---------------------------------------------------------------- D97 engine hooks

## Zone control: `u` holds `hexes` until its next turn (BWSkillDef.zone).
func set_zone(u: BWUnit, hexes: Array, skill: String = "") -> void:
	u.zone = { "hexes": _on_board(hexes), "skill": skill }
	_emit({ "type": "zone", "unit": u.id, "hexes": u.zone.hexes, "skill": skill })


## Ally-attacked trigger: `u` watches allies within `radius` until its next turn.
func set_overwatch(u: BWUnit, radius: int, skill: String = "") -> void:
	u.overwatch = { "radius": radius, "skill": skill }
	_emit({ "type": "overwatch_set", "unit": u.id, "radius": radius, "skill": skill })


## The holder's turn came round: its zone and overwatch end.
func _expire_holds(u: BWUnit) -> void:
	if not u.zone.is_empty():
		u.zone = {}
		_emit({ "type": "zone_end", "unit": u.id })
	if not u.overwatch.is_empty():
		u.overwatch = {}
		_emit({ "type": "overwatch_end", "unit": u.id })


## A move ended inside an enemy zone: tell the zone's skill.
func _zone_check(u: BWUnit) -> void:
	for o in units:
		if over or not u.alive():
			return
		if not o.alive() or o.team == u.team or o.zone.is_empty() or not u.pos in o.zone.get("hexes", []):
			continue
		var key := str(o.zone.get("skill", ""))
		_emit({ "type": "zone_stop", "unit": u.id, "holder": o.id, "hex": u.pos, "skill": key })
		var d := BWSkillRegistry.get_def(key)
		if d != null:
			d.on_zone_enter(self, o, u)


## After `att`'s action: the first enemy action that attacked an ally of an
## overwatch holder within its radius draws the holder's answer (the def's
## on_overwatch, else one basic attack if in range). Emits `overwatch`.
func _overwatch_check(att: BWUnit, struck: Array) -> void:
	for h in units:
		if over or not att.alive():
			return
		if not h.alive() or h.team == att.team or h.overwatch.is_empty():
			continue
		var r := int(h.overwatch.get("radius", 0))
		var hit_ally := false
		for s in struck:
			var v: BWUnit = s[0]
			if v != h and v.team == h.team and gap(h, v) <= r:
				hit_ally = true
		if not hit_ally:
			continue
		var key := str(h.overwatch.get("skill", ""))
		h.overwatch = {}
		_emit({ "type": "overwatch", "unit": h.id, "target": att.id, "skill": key })
		var d := BWSkillRegistry.get_def(key)
		if d != null and d.on_overwatch(self, h, att):
			continue
		if in_range(h, att):
			_reaction_basic(h, att, "overwatch", str(BWSkills.get_skill(key).get("name", "Overwatch")))


## One out-of-turn basic attack (an overwatch answer). Replayed by the view
## as a `counter` (with `cause`).
func _reaction_basic(h: BWUnit, t: BWUnit, cause: String, label: String) -> void:
	_face(h, t.pos)
	var fc := forecast_basic(h, t)
	var res := roll(fc)
	BWEnchant.land(self, h, t, res)            # v2 hook
	var before := t.hp
	t.hp = maxi(0, t.hp - res.damage)
	_emit({ "type": "counter", "unit": h.id, "target": t.id, "result": res, "forecast_hit": fc.hit.value, "odds": odds(fc),
		"ko": not t.alive(), "target_hp": t.hp, "name": label, "cause": cause, "tags": _tags(fc) })
	_after_blow(h, t, res, before, cause)
	BWEnchant.after_blow(self, h, t, res)      # v2 hook
	_conduct(h, t, int(res.damage))
	_check_end()


## Free-placement displacement: may `v` be set down on `hex`? In bounds, on
## the map, not jagged, and free for its whole footprint.
func can_place(v: BWUnit, hex: Vector2i) -> bool:
	return board.in_bounds(hex) and board.is_passable(hex) and can_stand(v, hex)


## Move `v` straight to `hex` (Grapple Throw). No crossing damage, no lay_on;
## immune displace stops it. Emits a `move` of kind "place".
func place_unit(v: BWUnit, hex: Vector2i) -> bool:
	if over or not v.alive() or not can_place(v, hex):
		return false
	if _immune(v, "displace"):
		_emit({ "type": "displace_resisted", "unit": v.id, "kind": "place" })
		return false
	var from := v.pos
	v.pos = hex
	_emit({ "type": "move", "unit": v.id, "path": [from, hex], "kind": "place" })
	return true


## Public status helper for skills (Pinned, Staggered, ...): until the end of
## the holder's next turn. `elemental` 1 = an element laid it (wardable).
func add_status(v: BWUnit, key: String, by: BWUnit, elemental: int = -1) -> void:
	_add_status(v, key, by, elemental)



# ---- D160 readability: rolls, the action simulator, ground reports (readability lane) ----

## D160: when true, every roll resolves to its expected value instead of
## drawing from `rng` (the blast preview's simulator sets it on a clone).
var expected_rolls := false


## Every blow's roll goes through here (and BWSkillDef code calls b.roll).
func roll(fc: Dictionary) -> Dictionary:
	if expected_rolls:
		return expected_result(fc)
	return BWFormulas.resolve(fc, rng)


## A forecast's expected outcome as a resolve() result: damage = the
## forecast's expected value (hit chance x the glance/crit/resist mix),
## "hit" when the hit chance is 50 or more (so on-hit riders show), no
## crit, no glance. Flagged `expected` so the preview labels it "~".
static func expected_result(fc: Dictionary) -> Dictionary:
	var ex := float(fc.expected.value)
	var hit := float(fc.hit.value) >= 50.0 and not fc.has("immune")   # D209
	return { "hit": hit, "glance": false, "crit": false, "resisted": false,
		"damage": maxi(0, roundi(ex)), "secondary": true, "rolls": {}, "expected": true }


## D160: an independent copy of this battle: board data shared (terrain is
## read-only), tiles, units, queue and per-battle state copied deep, unit
## references remapped to the copies. Its rng is its own (a fixed seed), so
## nothing run on the copy touches this battle's rolls; nothing listens to
## its `event` signal.
func clone() -> BWBattle:
	var bd := BWBoard.new()
	_copy_vars(board, bd, false)
	var c := BWBattle.new(bd, 0x5EED)
	_copy_vars(tiles, c.tiles, true)
	c.tiles.board = bd
	c.tiles.potency = c._tile_potency
	var m := {}
	for u in units:
		var nu: BWUnit = u.get_script().new()
		_copy_vars(u, nu, true)
		nu.fx_hook = c._situational
		m[u] = nu
	for nu in m.values():
		for p in _script_vars(nu):
			var val = nu.get(p)
			if val is Array or val is Dictionary:
				_remap(val, m)
	for p in _script_vars(self):
		if p in ["board", "tiles", "rng", "history", "expected_rolls"]:
			continue
		var val = get(p)
		if val is Array or val is Dictionary:
			c.set(p, _remap(val.duplicate(true), m))
		elif val is Object:
			c.set(p, m.get(val, val))
		elif not val is Callable:
			c.set(p, val)
	c._undo = {}
	c.picks_live = false
	return c


static func _script_vars(o: Object) -> Array:
	var out: Array = []
	for pr in o.get_property_list():
		if int(pr.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(str(pr.name))
	return out


static func _copy_vars(src: Object, dst: Object, deep: bool) -> void:
	for p in _script_vars(src):
		var val = src.get(p)
		if val is Callable or val is Signal:
			continue
		if deep and (val is Array or val is Dictionary):
			val = val.duplicate(true)
		dst.set(p, val)


## Replace every original-unit reference inside `v` (in place for arrays
## and dictionaries, keys included) with its copy from `m`.
static func _remap(v: Variant, m: Dictionary) -> Variant:
	if v is Object:
		return m.get(v, v)
	if v is Array:
		for i in (v as Array).size():
			v[i] = _remap(v[i], m)
		return v
	if v is Dictionary:
		for k in (v as Dictionary).keys():
			var nv = _remap(v[k], m)
			if k is Object and m.has(k):
				v.erase(k)
				v[m[k]] = nv
			else:
				v[k] = nv
		return v
	return v


## D160: what an action would do, resolved on a clone with expected rolls.
## `action`: { kind: "attack", target: id } or { kind: "skill", key,
## element, hex [, choice] }. Pure for this battle (no event, no rng, no
## state touched). Returns {} when the action isn't legal now, else:
##   hexes:  { hex: { kinds: [..], before: entry, after: entry } }, kinds
##           from detonate / glaze / gale (the origin) / spread (a gale
##           copy) / arm (a marker laid) / paint / erase / ignite (fire 2+
##           cast on grass: spreads at the cycle's end)
##   detonations: [{ hex, pct, radius }]
##   chains: [{ from, to, amount, hex, to_hex, approx }]
##   moves:  [{ unit, path, kind }] displacements (knockback, push, pull ...)
##   units:  { id: { name, team, friendly, self, hp, hp_after, damage, heal,
##             ko, approx, pos, sources: [{ kind, amount, approx }] } } for
##             every unit whose HP changes (the actor too: answers, splash)
##   events: the clone's event list
func simulate(u: BWUnit, action: Dictionary) -> Dictionary:
	if u == null or over or u != current():
		return {}
	var c := clone()
	c.expected_rolls = true
	var cu := c._unit(u.id)
	var before: Dictionary = c.tiles.entries.duplicate(true)
	var hp0 := {}
	for w in c.units:
		hp0[w.id] = w.hp
	var r := {}
	match str(action.get("kind", "")):
		"attack":
			var t := c._unit(str(action.get("target", "")))
			if t == null:
				return {}
			r = c.attack(cu, t)
		"skill":
			r = c.use_skill(cu, str(action.key), str(action.get("element", "")), action.hex,
				action.get("choice", NOWHERE))
	if r.is_empty() and not c.history.any(func(e): return str(e.type) in ["attack", "skill"]):
		return {}
	return c._digest(u, before, hp0)


func _digest(actor: BWUnit, before: Dictionary, hp0: Dictionary) -> Dictionary:
	var out := { "actor": actor.id, "team": actor.team, "hexes": {}, "detonations": [], "chains": [],
		"moves": [], "units": {}, "events": history, "approx": false }
	var hx: Dictionary = out.hexes
	var last_kind := {}            # unit id -> "hit" | "ground", for an arc's "~"
	var src := {}                  # unit id -> [{kind, amount, approx}]
	for e in history:
		match str(e.type):
			"attack", "counter":
				var res: Dictionary = e.get("result", {})
				_note_src(src, out, str(e.target), "hit" if e.type == "attack" else "counter",
					int(res.get("damage", 0)), bool(res.get("expected", false)))
				last_kind[str(e.target)] = "hit"
			"skill", "riposte":
				for rr in e.get("results", []):
					var res2: Dictionary = rr.get("result", {})
					_note_src(src, out, str(rr.target), "hit" if e.type == "skill" else "counter",
						int(res2.get("damage", 0)), bool(res2.get("expected", false)))
					last_kind[str(rr.target)] = "hit"
			"tile_damage":
				var kind := str(e.get("cause", "ground"))
				if kind == "detonation":
					kind = "splash"
					var w0 := _unit(str(e.unit))
					for d in out.detonations:
						if w0 != null and w0.pos == d.hex:
							kind = "blast"
				_note_src(src, out, str(e.unit), kind, int(e.amount), false)
				last_kind[str(e.unit)] = "ground"
			"chain":
				var ap := str(last_kind.get(str(e.from), "")) == "hit"
				out.chains.append({ "from": str(e.from), "to": str(e.to), "amount": int(e.amount),
					"hex": e.hex, "to_hex": e.to_hex, "approx": ap })
				_note_src(src, out, str(e.to), "arc", int(e.amount), ap)
				last_kind[str(e.to)] = "ground"
			"heal":
				_note_src(src, out, str(e.unit), "heal", -int(e.amount), false)
			"detonate":
				if not e.get("echo", false):
					out.detonations.append({ "hex": e.hex, "pct": float(e.pct), "radius": int(e.get("radius", 1)) })
				_hex_kind(hx, before, e.hex, "detonate")
			"paint":
				var copies := {}
				for g in e.get("gales", []):
					_hex_kind(hx, before, g.origin, "gale")
					for h in g.copies:
						copies[h] = true
						_hex_kind(hx, before, h, "spread")
				var pools: Dictionary = e.get("pools", {})      # D266: the pool that reacts, pillars
				for pk in ["steam", "rink", "shock", "pillars", "melted"]:
					for h in pools.get(pk, []):
						_hex_kind(hx, before, h, "pillar" if pk == "pillars" else pk)
				for h in e.get("hexes", []):
					if copies.has(h):
						continue
					var b0: Dictionary = before.get(h, {})
					var a: Dictionary = tiles.at(h)
					var kinds: Array = hx[h].kinds if hx.has(h) else []
					if a.is_empty():
						if not "detonate" in kinds:
							_hex_kind(hx, before, h, "erase")
					elif int(a.get("glaze", 0)) > 0 and int(b0.get("glaze", 0)) <= 0:
						_hex_kind(hx, before, h, "glaze")
					elif str(a.get("marker", "")) != "" and str(a.get("marker", "")) != str(b0.get("marker", "")):
						_hex_kind(hx, before, h, "arm")
					elif not "gale" in kinds:
						_hex_kind(hx, before, h, "paint")
			"move":
				if str(e.get("kind", "")) in ["knockback", "push", "pull", "shove", "place", "charge", "leap", "slide"]:
					out.moves.append({ "unit": str(e.unit), "path": e.path, "kind": str(e.kind), "stop": str(e.get("stop", "")) })
			"slam":                                    # D261: a slide (or push) that slams
				if not out.has("slams"):
					out["slams"] = []
				out.slams.append({ "unit": str(e.unit), "into": str(e.get("into", "")), "name": str(e.get("name", "")),
					"hex": e.get("hex", NOWHERE), "target": str(e.get("target", "")) })
	for h in hx:                                   # fire 2+ freshly cast on grass catches at the cycle's end
		hx[h].after = tiles.at(h).duplicate()
		var a2: Dictionary = hx[h].after
		if not a2.is_empty() and int(a2.h) >= BWTiles.GRASS_IGNITE_MIN and str(a2.origin) == "cast" \
				and int(a2.glaze) == 0 and board.terrain(h) == BWBoard.GRASSY:
			hx[h].kinds.append("ignite")
	for w in units:
		if not src.has(w.id):
			continue
		var heal := 0
		var dmg := 0
		var approx := false
		for s in src[w.id]:
			if int(s.amount) < 0:
				heal -= int(s.amount)
			else:
				dmg += int(s.amount)
			approx = approx or bool(s.approx)
		if dmg == 0 and heal == 0:
			continue
		out.units[w.id] = { "name": w.name, "team": w.team, "friendly": w.team == actor.team,
			"self": w.id == actor.id, "hp": int(hp0.get(w.id, w.hp)), "hp_after": w.hp, "damage": dmg,
			"heal": heal, "ko": not w.alive(), "approx": approx, "sources": src[w.id], "pos": w.pos }
	BWBeams.digest(self, out)                      # D287: the beams the board would hold after it
	return out


static func _note_src(src: Dictionary, out: Dictionary, id: String, kind: String, amount: int, approx: bool) -> void:
	if not src.has(id):
		src[id] = []
	src[id].append({ "kind": kind, "amount": amount, "approx": approx })
	if approx:
		out.approx = true


static func _hex_kind(hx: Dictionary, before: Dictionary, h: Vector2i, kind: String) -> void:
	if not hx.has(h):
		hx[h] = { "kinds": [], "before": before.get(h, {}), "after": {} }
	if not kind in hx[h].kinds:
		hx[h].kinds.append(kind)


## D161: what a hex is and does, for the tile hover card. Pure.
##   entry (copy), terrain, elevation, static (Vector2i floor or null),
##   scarred, seeded, move_extra, hit_mod, conductive, unit (id or ""),
##   turn: { damage, heal, lines: [[label, signed amount]] } the occupant's
##   tile effects at its next turn start if the ground holds (fire, the
##   dark 3 drain, Shrouded, light; Ember Skin, Nightborn, Glare, Sanctuary).
func ground_report(hex: Vector2i) -> Dictionary:
	var e := tiles.at(hex).duplicate()
	var out := { "hex": hex, "entry": e, "exists": board.exists(hex), "terrain": board.terrain(hex),
		"elevation": board.elevation(hex), "static": tiles.static_at(hex) if tiles.is_static(hex) else null,
		"scarred": tiles.is_scarred(hex), "seeded": tiles.is_seeded(hex),
		"move_extra": tiles.move_penalty(hex), "hit_mod": tiles.hit_mod(hex),
		"conductive": tiles.conductive(hex), "unit": "", "turn": { "damage": 0, "heal": 0, "lines": [] },
		"spine": BWPools.report(self, hex) }        # D266: rink, pillar, steam, electrified, pool
	var u := _centre_at(hex)
	if u == null or not u.alive() or BWObelisk.is_objective(u):
		return out
	out.unit = u.id
	var t: Dictionary = out.turn
	var night := BWEffects.has(u, "nightborn") or BWSets.no_drain(u)   # D282
	if u.statuses.has("shrouded") and not night:
		var sd := _tile_dmg(u, BWSkills.SHROUD_DRAIN_PCT, "dark")
		t.damage += sd
		t.lines.append(["Shrouded drain", -sd])
	var st := tiles.standing(hex)
	if st.fire > 0:
		var half := 1.0
		for fx in BWEffects.list(u, "ember_skin"):
			half = float(BWEffects.p(fx, "stand_pct", 50)) / 100.0
		var fd := _tile_dmg(u, st.fire, "fire", half)
		t.damage += fd
		t.lines.append(["Fire burns", -fd])
	var sh := BWPools.shock_next(self, u, hex)       # D264
	if sh > 0:
		t.damage += sh
		t.lines.append(["Electrified shock", -sh])
	if st.drain > 0 and not night:
		var dd := _tile_dmg(u, st.drain, "dark")
		t.damage += dd
		t.lines.append(["Dark 3 drains", -dd])
	if st.heal > 0:
		var pct := float(st.heal) * BWWeather.heal_mult(weather)   # D250: Eclipse
		var s := _unit(str(st.source))
		if s != null and s.team != u.team and BWEffects.has(s, "glare"):
			pct = 0.0
		elif s != null and s.team == u.team:
			for fx in BWEffects.list(s, "sanctuary"):
				pct = maxf(pct, BWEffects.by_level(fx, tiles.intensity(hex, "light")))
		if pct > 0.0:
			var hl := mini(maxi(1, roundi(u.max_hp() * pct / 100.0)), u.max_hp() - maxi(u.hp - int(t.damage), 0))
			if hl > 0:
				t.heal = hl
				t.lines.append(["Light heals", hl])
	return out
# ---- end D160/D161 ----
