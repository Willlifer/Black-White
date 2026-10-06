extends BWSkillDef
## Sword, follow-up only (Striketwice's follow-through), at any adjacent foe.
## Same element as the first cut: the ring floods. D87: the same foe twice
## can't glance and is Staggered; opposite elements react on the hex
## (BWSkills.REACTIONS: steam, eclipse, storm). Striketwice+ (D103): if
## both cuts land, a third cut hits an adjacent foe (the lowest HP) at
## THIRD_PCT%.

const THIRD_PCT := 50


func _init() -> void:
	define({
		"key": "striketwice_second", "name": "Second Cut", "weapon": "sword", "clip": "",
		"desc": "The follow-through, at any adjacent foe. Same foe: can't glance, staggers (no skills next turn). Same element: flood. Opposite: fire+water steam (8% to the ring), light+dark eclipse (blinds), thunder+wind storm (pushes the ring 1)",
		"targeting": "adjacent_unit", "needs_element": true, "range": 1, "cd": 0,
		"power": BWSkills.STRIKE_DMG, "follow_up_only": true,
	}, 120)


func plan(b: BWBattle, u: BWUnit, element: String, target: Vector2i, p: Dictionary) -> void:
	p.hexes = [target]
	if element != "" and element == u.follow_up_element:
		p.hexes = b._without(b._on_board(BWHex.fringe([target], 1)), u.pos)    # the flood
		p.notes.append("Same element twice: the ground floods")
	p.victims = b._foes_on(u, [target])
	var first_id := str(u.fx.get("first_cut", ""))
	p["same"] = not p.victims.is_empty() and first_id != "" and p.victims[0].id == first_id
	if not p.victims.is_empty() and not p.same:
		p.notes.append("Retargeted: the second cut turns to %s" % p.victims[0].name)
	var rx: String = BWSkills.REACTIONS.get("%s|%s" % [u.follow_up_element, element], "")
	if rx != "":
		p["reaction"] = rx
		p.notes.append({
			"steam": "Fire meets water: steam bursts on the ring (%d%% HP)" % BWSkills.STEAM_PCT,
			"eclipse": "Light meets dark: an eclipse Blinds the foes there (no crits; targets within 2)",
			"storm": "Thunder meets wind: a storm pushes the ring back 1",
		}[rx])
	if u.skill_upgraded("striketwice") and u.fx.get("first_cut_hit", false):
		p.notes.append("Striketwice+: if this cut lands too, a third cut hits the weakest adjacent foe at %d%%" % THIRD_PCT)


func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, p: Dictionary, _strike: int,
		mods: Array, notes: Array) -> void:
	if p.get("same", false):
		mods.append({ "stage": "glance_x", "value": 0.0, "label": "Follow-through (same foe): can't glance" })
		notes.append("Same foe twice: can't glance, and Staggers it (no skills next turn)")


func decorate(e: Dictionary, p: Dictionary) -> void:
	e["retarget"] = not p.get("same", true)


## D87: the same foe twice is Staggered (a secondary effect).
func after_hits(b: BWBattle, u: BWUnit, p: Dictionary, results: Array) -> void:
	if p.get("same", false) and not results.is_empty():
		var sv: BWUnit = p.victims[0]
		if sv.alive() and results[0].result.secondary:
			b._add_status(sv, "staggered", u)


func after_paint(b: BWBattle, u: BWUnit, el: String, target_hex: Vector2i, p: Dictionary,
		results: Array, _stripped: int) -> void:
	var kind := str(p.get("reaction", ""))
	if kind != "":
		reaction(b, u, kind, target_hex)
	var both: bool = not results.is_empty() and results[0].result.hit and u.fx.get("first_cut_hit", false)
	if u.skill_upgraded("striketwice") and both and u.alive() and not b.over:
		third_cut(b, u, el)


## Striketwice+ (D103): one more cut, its own roll, at THIRD_PCT% to the
## adjacent foe with the least HP (the UI has no third pick yet).
func third_cut(b: BWBattle, u: BWUnit, el: String) -> void:
	var f: BWUnit = null
	for o in b.foes_of(u):
		if b._reaches_unit(u, u.pos, o, 1) and (f == null or o.hp < f.hp):
			f = o
	if f == null:
		return
	var p := { "victims": [f], "shares": { f.id: [THIRD_PCT / 100.0, "Third cut (Striketwice+): %d%%" % THIRD_PCT, "Third cut"] } }
	var fc := b._skill_forecast(u, data, el, f, p)
	var res := b.roll(fc)
	var before := f.hp
	f.hp = maxi(0, f.hp - res.damage)
	b._emit({ "type": "attack", "unit": u.id, "target": f.id, "result": res, "forecast_hit": fc.hit.value, "odds": BWBattle.odds(fc),
		"ko": not f.alive(), "target_hp": f.hp, "skill": id, "pattern": "third_cut", "tags": BWBattle._tags(fc) })
	b._after_blow(u, f, res, before, "")
	b._conduct(u, f, int(res.damage))
	b._answer(b._riposte_check(f, res))
	b._check_end()


## D87: the opposite-element reaction on the second cut's hex. steam
## (fire+water): STEAM_PCT% max HP fire damage to every unit on the ring;
## eclipse (light+dark): the foe on the hex and the cutter's foes on the ring
## are Blinded; storm (thunder+wind): every unit on the ring is pushed 1
## straight out. The cutter is never caught in its own reaction; the ground
## does not roll, so neither do these.
static func reaction(b: BWBattle, u: BWUnit, kind: String, hex: Vector2i) -> void:
	var ring: Array = []
	for h in b.board.neighbors(hex):
		var o := b._centre_at(h)
		if o != null and o != u:
			ring.append(o)
	b._emit({ "type": "reaction", "unit": u.id, "kind": kind, "hex": hex,
		"units": ring.map(func(o): return o.id) })
	match kind:
		"steam":
			for o in ring:
				if o.alive():
					b._tile_hurt(o, b._tile_dmg(o, BWSkills.STEAM_PCT, "fire"), "steam", u.id)
		"eclipse":
			var c := b._centre_at(hex)
			if c != null and c.team != u.team:
				b._add_status(c, "blinded", u)
			for o in ring:
				if o.team != u.team and o.alive():
					b._add_status(o, "blinded", u)
		"storm":
			for o in ring:
				if o.alive():
					b._displace(o, BWHex.direction_index(hex, o.pos), 1, "push")
