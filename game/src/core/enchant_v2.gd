class_name BWEnchant
## Enchantments v2 (design/ENCHANTMENTS-v2.md, D196-D205): the battle halves of
## the four generic keys (on_event, pity, drawback, swap) and the new params on
## the old keys. Pure rules, no nodes. BWBattle calls in at the lines marked
## "v2 hook:"; the forecast terms ride BWEffects.attack_mods.
##
## Every number that fires is a labelled forecast term, or an `enchant` event
## { unit, name, text } that the combat screen floats over the unit and feeds.
##
## The §5 loop caps live here:
##   Relentless      once per turn per unit, an attack only (no move)
##   on-kill         never triggers on-kill (BWBattle._onkill_depth)
##   kill paint      arrives as spread (tiles.apply `propagated`): no marker fires
##   on-event heals  at most HEAL_CAP_PCT of max HP per unit per action; Leeching
##                   reads direct hits only (never tiles, arcs or bursts)
##   Follow-Through  the doubled strike can't crit

const HEAL_CAP_PCT := 20.0
const ADV_CD := 3                  # Second Opinion / Stubborn: once every 3 turns


static func _ev(b: BWBattle, u: BWUnit, name: String, text: String, extra: Dictionary = {}) -> void:
	var e := { "type": "enchant", "unit": u.id, "name": name, "text": text }
	e.merge(extra)
	b._emit(e)


static func _on(u: BWUnit, on: String) -> Array:
	return BWEffects.list(u, "on_event").filter(func(e): return str(BWEffects.p(e, "on", "")) == on)


static func _pity(u: BWUnit, kind: String) -> Array:
	return BWEffects.list(u, "pity").filter(func(e): return str(BWEffects.p(e, "kind", "")) == kind)


static func _drawback(u: BWUnit, param: String) -> Dictionary:
	for e in BWEffects.list(u, "drawback"):
		if e.params.has(param):
			return e
	return {}


static func _pct_hp(u: BWUnit, amount: float) -> float:
	return 100.0 * amount / maxf(1.0, float(u.max_hp()))


# ================================================================ forecast terms

## The v2 terms on one blow (appended by BWEffects.attack_mods). ctx adds:
## rear, still, att_alone, dfn_alone, charge_levels, dfn_adjacent (BWBattle._mods).
static func mods(att: BWUnit, dfn: BWUnit, kind: String, element: String, ctx: Dictionary, auras: Callable) -> Array:
	var out: Array = []
	var dist := int(ctx.get("dist", 1))
	var m := func(stage: String, label: String, value: float) -> void:
		out.append({ "stage": stage, "label": label, "value": value })
	for e in BWEffects.list(att, "attack_mod"):
		if dist < int(BWEffects.p(e, "min_range", 0)):
			continue
		var ch := float(BWEffects.p(e, "crit_per_height", 0))
		if ch != 0.0 and int(ctx.get("height", 0)) > 0:
			m.call("crit", "%s (%d above)" % [e.name, ctx.height], ch * int(ctx.height))
		if float(BWEffects.p(e, "rear_pct", 0)) != 0.0 and ctx.get("rear", false):
			m.call("dmg", "%s (from behind): +%d%%" % [e.name, int(BWEffects.p(e, "rear_pct"))], 1.0 + float(BWEffects.p(e, "rear_pct")) / 100.0)
		if float(BWEffects.p(e, "alone_dmg_pct", 0)) != 0.0 and ctx.get("att_alone", false):
			m.call("dmg", "%s (no ally within 2): +%d%%" % [e.name, int(BWEffects.p(e, "alone_dmg_pct"))], 1.0 + float(BWEffects.p(e, "alone_dmg_pct")) / 100.0)
		if float(BWEffects.p(e, "still_pct", 0)) != 0.0 and ctx.get("still", false):
			m.call("dmg", "%s (didn't move): +%d%%" % [e.name, int(BWEffects.p(e, "still_pct"))], 1.0 + float(BWEffects.p(e, "still_pct")) / 100.0)
		var per_lv := float(BWEffects.p(e, "vs_charged_per_level", 0))
		if per_lv != 0.0 and int(ctx.get("charge_levels", 0)) > 0:
			var pc := minf(float(BWEffects.p(e, "charged_cap", 1000)), per_lv * int(ctx.charge_levels))
			m.call("dmg", "%s (%d charge levels): +%d%%" % [e.name, ctx.charge_levels, int(pc)], 1.0 + pc / 100.0)
		var on_el := str(BWEffects.p(e, "per_hex_on", ""))
		if on_el != "" and int(att.fx.get("on_hexes:" + on_el, 0)) > 0:
			var n := int(att.fx.get("on_hexes:" + on_el, 0))
			var pc2 := minf(float(BWEffects.p(e, "on_max", 1000)), float(BWEffects.p(e, "per_hex_on_pct", 0)) * n)
			m.call("dmg", "%s (%d %s hexes entered): +%d%%" % [e.name, n, on_el, int(pc2)], 1.0 + pc2 / 100.0)
		var miss10 := float(BWEffects.p(e, "dmg_per_missing10", 0))
		if miss10 != 0.0:
			var tenths := floori(10.0 * (1.0 - float(att.hp) / maxf(1.0, float(att.max_hp()))))
			if tenths > 0:
				m.call("dmg", "%s (%d0%% HP missing): +%d%%" % [e.name, tenths, int(miss10 * tenths)], 1.0 + miss10 * tenths / 100.0)
		if float(BWEffects.p(e, "nocrit_pct", 0)) != 0.0:
			m.call("nocrit_x", "%s: hits that don't crit deal %d%%" % [e.name, int(BWEffects.p(e, "nocrit_pct"))], float(BWEffects.p(e, "nocrit_pct")) / 100.0)
	# Fury (trigger_stat dmg_pct): stacks banked for the battle
	for e in BWEffects.list(att, "trigger_stat"):
		var got := float(att.fx.get("fury:" + str(e.source), 0))
		if got > 0.0:
			m.call("dmg", "%s (hurt %d times): +%d%%" % [e.name, roundi(got / maxf(1.0, float(BWEffects.p(e, "dmg_pct", 1)))), int(got)], 1.0 + got / 100.0)
	# empowerments (Rallying, Vengeance, Relay, Beacon)
	for em in att.fx.get("empower", []):
		if float(em.get("dmg_pct", 0)) != 0.0:
			m.call("dmg", "%s: +%d%%" % [em.name, int(em.dmg_pct)], 1.0 + float(em.dmg_pct) / 100.0)
		if float(em.get("crit", 0)) != 0.0:
			m.call("crit", str(em.name), float(em.crit))
		if em.get("sure", false):
			m.call("hit", "%s: can't be avoided" % em.name, 1000.0)
	# pity (Steady Hand, Follow-Through, Building Pressure)
	if att.fx.has("steady"):
		m.call("hit", "%s: can't be avoided" % str(att.fx.steady), 1000.0)
	if att.fx.has("follow_mult"):
		var fm := float(att.fx.follow_mult)
		m.call("dmg", "%s (after a glance): x%s" % [str(att.fx.get("follow_name", "Follow-Through")), str(fm)], fm)
		m.call("crit_x", "%s: this strike can't crit" % str(att.fx.get("follow_name", "Follow-Through")), 0.0)
	if float(att.fx.get("pressure", 0)) > 0.0:
		m.call("crit", "%s (%d hits without a crit)" % [str(att.fx.get("pressure_name", "Pressure")), roundi(float(att.fx.pressure) / 8.0)], float(att.fx.pressure))
	# Advantage on the resist roll (Second Opinion: the attacker's; Stubborn: the defender's)
	if BWFormulas.is_magic(kind, element):
		for e in _pity(att, "resist"):
			if str(BWEffects.p(e, "side", "att")) == "att" and int(att.fx.get("adv_cd", 0)) <= 0:
				out.append({ "stage": "resist_adv", "value": 1.0, "label": "%s: advantage (the resist rolls twice, you keep the better)" % e.name, "who": att.id })
				break
		for e in _pity(dfn, "resist"):
			if str(BWEffects.p(e, "side", "att")) == "def" and int(dfn.fx.get("adv_cd", 0)) <= 0:
				out.append({ "stage": "resist_adv", "value": -1.0, "label": "%s: advantage (rolls the resist twice, keeps the better)" % e.name, "who": dfn.id })
				break
	# defender side
	for e in BWEffects.list(dfn, "attack_mod"):
		if float(BWEffects.p(e, "alone_avoid", 0)) != 0.0 and ctx.get("dfn_alone", false):
			m.call("avoid", "%s (no ally within 2)" % e.name, float(BWEffects.p(e, "alone_avoid")))
	for e in BWEffects.list(dfn, "aura_mod"):
		var ph := float(BWEffects.p(e, "avoid_per_hex_moved", 0))
		var mv := int(dfn.fx.get("moved_hexes", 0))
		if ph != 0.0 and mv > 0:
			m.call("avoid", "%s (moved %d)" % [e.name, mv], minf(float(BWEffects.p(e, "avoid_cap", 1000)), ph * mv))
	for e in BWEffects.list(dfn, "damage_taken_mod"):
		var pct := float(BWEffects.p(e, "pct", 0))
		if str(BWEffects.p(e, "source", "")) == "any" and pct != 0.0:
			var below := float(BWEffects.p(e, "below_hp", 0))
			if below <= 0.0 or dfn.hp * 100.0 < below * dfn.max_hp():
				m.call("dmg", "%s%s: %+d%%" % [e.name, " (below %d%% HP)" % int(below) if below > 0.0 else "", int(pct)], 1.0 + pct / 100.0)
		var per_ally := float(BWEffects.p(e, "per_adjacent_ally", 0))
		if per_ally != 0.0 and int(ctx.get("dfn_adjacent", 0)) > 0:
			var tot := maxf(-float(BWEffects.p(e, "max_pct", 1000)), per_ally * int(ctx.dfn_adjacent))
			m.call("dmg", "%s (%d adjacent allies): %+d%%" % [e.name, ctx.dfn_adjacent, int(tot)], 1.0 + tot / 100.0)
		if float(BWEffects.p(e, "cap_pct", 0)) > 0.0:
			out.append({ "stage": "note", "label": "%s: a hit above %d%% of its max HP deals half the excess" % [e.name, int(BWEffects.p(e, "cap_pct"))] })
	for e in BWEffects.list(dfn, "immune"):
		if str(BWEffects.p(e, "what", "")) == "ko" and not dfn.fx.has("undying_used"):
			out.append({ "stage": "note", "label": "%s: the first blow that would KO it leaves it at 1 HP" % e.name })
	if dfn.fx.has("parry"):
		m.call("dmg", "%s: next hit %d%% less" % [str(dfn.fx.get("parry_name", "Parry")), int(dfn.fx.parry)], 1.0 - float(dfn.fx.parry) / 100.0)
	var dw := _drawback(dfn, "status")
	if not dw.is_empty() and str(BWEffects.p(dw, "status", "")) == "scorched" and not dfn.statuses.has("scorched"):
		m.call("dmg", "%s: always Scorched +%d%%" % [dw.name, BWSkills.SCORCH_PCT], 1.0 + BWSkills.SCORCH_PCT / 100.0)
	dw = _drawback(dfn, "taken_pct")
	if not dw.is_empty():
		m.call("dmg", "%s (cursed): %+d%%" % [dw.name, int(BWEffects.p(dw, "taken_pct"))], 1.0 + float(BWEffects.p(dw, "taken_pct")) / 100.0)
	dw = _drawback(dfn, "no_glance")
	if not dw.is_empty():
		m.call("glance_x", "%s (cursed): can't glance" % dw.name, 0.0)
	if auras.is_valid():
		for a in auras.call(dfn, "taken_pct"):
			m.call("dmg", "%s: %+d%%" % [a.label, int(a.value)], 1.0 + float(a.value) / 100.0)
	return out


## Lockstep (aura_mod self_if_ally): the holder gets its own aura while an ally
## is within the radius. [{label, value}] for one key.
static func self_auras(b: BWBattle, u: BWUnit, key: String) -> Array:
	var out: Array = []
	for e in BWEffects.list(u, "aura_mod"):
		if int(BWEffects.p(e, "self_if_ally", 0)) != 1 or float(BWEffects.p(e, key, 0)) == 0.0:
			continue
		var r := int(BWEffects.p(e, "radius", 1))
		for o in b.side(u.team):
			if o != u and b.gap(o, u) <= r:
				out.append({ "label": "%s (ally beside you)" % e.name, "value": float(BWEffects.p(e, key)) })
				break
	return out


## stand_on_bonus (D196): the greater of the flat value (per_point × points +
## flat) and pct_per_point × points (or `pct` for a glaze) of the stat from
## base + gear (never other situational bonuses, so nothing loops).
static func stand_on(u: BWUnit, e: Dictionary, key: String, pts: int) -> float:
	var flat := float(BWEffects.p(e, "per_point", 0)) * pts + float(BWEffects.p(e, "flat", 0))
	var pct := float(BWEffects.p(e, "pct_per_point", 0)) * pts + float(BWEffects.p(e, "pct", 0))
	if pct <= 0.0:
		return flat
	var raw := int(u.stats.get(key, 0)) + int(u.battle_mods.get(key, 0))
	for slot in u.equipment:
		if slot != BWUnit.SECOND:
			raw += int(u.equipment[slot].get("stats", {}).get(key, 0))
	return maxf(flat, floorf(raw * pct / 100.0))


# ================================================================ rolls

static func begin_action(b: BWBattle, u: BWUnit) -> void:
	b._action_serial += 1
	u.fx["_rolls"] = 0
	u.fx["_hits"] = 0
	u.fx.erase("_pincer")
	u.fx.erase("relentless_pending")
	u.fx["_steady_live"] = u.fx.has("steady")


## One blow's roll, with Second Chance (a re-roll), Graze (a missed basic
## deals pct%), Advantage spent, and the pity counters moved on.
static func roll_blow(b: BWBattle, att: BWUnit, v: BWUnit, fc: Dictionary, basic: bool) -> Dictionary:
	var res := b.roll(fc)
	if att == null:
		return res
	if not res.hit and not b.expected_rolls:
		for e in _pity(att, "reroll"):
			if not att.fx.has("second_chance_used"):
				att.fx["second_chance_used"] = true
				_ev(b, att, e.name, "Second Chance: re-rolled the miss")
				res = b.roll(fc)
			break
	if not res.hit and basic:
		for e in _pity(att, "graze"):
			var dmg := maxi(1, roundi(float(fc.damage.value) * float(BWEffects.p(e, "pct", 25)) / 100.0))
			res["damage"] = dmg
			res["graze"] = true
			_ev(b, att, e.name, "Graze: %d" % dmg, { "target": v.id })
			break
	if res.hit and fc.get("magic", false):            # Advantage is spent on a resist roll
		for id in fc.get("adv_units", []):
			var w := b._unit(str(id))
			if w != null:
				w.fx["adv_cd"] = ADV_CD
				_ev(b, w, "Advantage", "rolled the resist twice%s" % (": resisted" if res.resisted else ": not resisted"))
	att.fx.erase("follow_mult")                        # Follow-Through is spent on this strike
	att.fx["_rolls"] = int(att.fx.get("_rolls", 0)) + 1
	if res.hit:
		att.fx["_hits"] = int(att.fx.get("_hits", 0)) + 1
		if res.glance:
			for e in _pity(att, "glance"):
				att.fx["follow_mult"] = float(BWEffects.p(e, "mult", 2))
				att.fx["follow_name"] = e.name
				_ev(b, att, e.name, "Follow-Through: next strike x%s" % str(BWEffects.p(e, "mult", 2)))
				break
		for e in _pity(att, "crit"):
			if res.crit:
				if float(att.fx.get("pressure", 0)) > 0.0:
					att.fx["pressure"] = 0
			else:
				var cap := float(BWEffects.p(e, "cap", 40))
				att.fx["pressure"] = minf(cap, float(att.fx.get("pressure", 0)) + float(BWEffects.p(e, "per", 8)))
				att.fx["pressure_name"] = e.name
			break
	return res


## Before a blow's damage lands: a Parry / Shelter is spent, Bulwark caps it,
## Covering takes a share (paid after the blow), Undying holds at 1 HP.
static func land(b: BWBattle, att: BWUnit, v: BWUnit, res: Dictionary) -> void:
	var dmg := int(res.get("damage", 0))
	if res.get("hit", false) and v.fx.has("parry"):
		v.fx.erase("parry")
		v.fx.erase("parry_name")
	if dmg <= 0 or not v.alive():
		return
	for e in BWEffects.list(v, "damage_taken_mod"):
		var cp := float(BWEffects.p(e, "cap_pct", 0))
		if cp <= 0.0:
			continue
		var cap := roundi(v.max_hp() * cp / 100.0)
		if dmg > cap:
			var now := cap + roundi((dmg - cap) * float(BWEffects.p(e, "excess", 50)) / 100.0)
			_ev(b, v, e.name, "Bulwark: %d → %d" % [dmg, now])
			dmg = now
	if not b.expected_rolls:
		for o in b._fx_units:
			if o == v or not o.alive() or o.team != v.team:
				continue
			var done := false
			for e in BWEffects.list(o, "damage_taken_mod"):
				var cv := float(BWEffects.p(e, "cover_pct", 0))
				if cv > 0.0 and b.gap(o, v) <= int(BWEffects.p(e, "radius", 1)):
					var share := roundi(dmg * cv / 100.0)
					if share > 0:
						dmg -= share
						b._pending_cover.append([o, share, att.id if att != null else "", e.name, v.id])
					done = true
					break
			if done:
				break
	if dmg >= v.hp:
		for e in BWEffects.list(v, "immune"):
			if str(BWEffects.p(e, "what", "")) == "ko" and not v.fx.has("undying_used"):
				v.fx["undying_used"] = true
				dmg = maxi(0, v.hp - 1)
				_ev(b, v, e.name, "Undying: held at 1 HP")
				break
	res["damage"] = maxi(0, dmg)


## After a blow's own triggers (BWBattle._after_blow): Covering pays its share,
## then Leeching, Thorned, Disengage, Second Breath, Evasive Roll, Relay,
## Parry Shield. `direct`: a hit from an action or a counter (Leeching).
static func after_blow(b: BWBattle, att: BWUnit, v: BWUnit, res: Dictionary, direct: bool = true, basic: bool = false) -> void:
	_flush_cover(b)
	if att == null or b.over:
		return
	var dealt := int(res.get("damage", 0))
	var foe := att.team != v.team
	if foe and direct and dealt > 0 and att.alive():
		for e in _on(att, "dealt"):
			if str(BWEffects.p(e, "do", "")) == "heal":
				ev_heal(b, att, _pct_hp(att, dealt * float(BWEffects.p(e, "pct_of", 15)) / 100.0), e.name)
	if not v.alive() or not foe:
		return
	var melee := b.gap(att, v) <= 1
	if res.get("hit", false) and dealt > 0:
		for e in _on(v, "struck"):
			if int(BWEffects.p(e, "melee_only", 0)) == 1 and not melee:
				continue
			match str(BWEffects.p(e, "do", "")):
				"reflect":
					if att.alive():
						var back := maxi(1, roundi(dealt * float(BWEffects.p(e, "pct_of", 20)) / 100.0))
						_ev(b, v, e.name, "Thorns: %d back" % back, { "target": att.id })
						b._tile_hurt(att, back, "thorns", v.id)
				"step":
					_step_once(b, v, att, e)
	if res.get("hit", false) and res.get("glance", false):
		for e in _on(v, "glanced"):
			ev_heal(b, v, float(BWEffects.p(e, "pct", 4)), e.name)
	if not res.get("hit", false):
		for e in _on(v, "avoided"):
			match str(BWEffects.p(e, "do", "")):
				"step":
					_step_once(b, v, att, e)
				"empower":
					var near: BWUnit = null
					for o in b.side(v.team):
						if o != v and (near == null or b.gap(v, o) < b.gap(v, near)):
							near = o
					if near != null:
						_empower(b, near, e, v)
		for e in BWEffects.list(v, "guard"):
			if str(BWEffects.p(e, "when", "")) == "avoided":
				v.fx["parry"] = maxf(float(v.fx.get("parry", 0)), float(BWEffects.p(e, "pct", 30)))
				v.fx["parry_name"] = e.name
				_ev(b, v, e.name, "Parry: next hit -%d%%" % int(BWEffects.p(e, "pct", 30)))
	if basic and res.get("hit", false) and att.alive():
		if not _on(att, "hit").is_empty():
			att.fx["_pincer"] = v.id


static func _flush_cover(b: BWBattle) -> void:
	var pend: Array = b._pending_cover.duplicate()
	b._pending_cover.clear()
	for c in pend:
		var o: BWUnit = c[0]
		if o.alive() and not b.over:
			_ev(b, o, str(c[3]), "Covering: takes %d" % int(c[1]), { "target": str(c[4]) })
			b._tile_hurt(o, int(c[1]), "covering", str(c[2]))


## Disengage / Evasive Roll: once per enemy turn, step 1 hex away from `from`.
static func _step_once(b: BWBattle, v: BWUnit, from: BWUnit, e: Dictionary) -> void:
	var key := "step_turn:" + str(e.source)
	if int(v.fx.get(key, -1)) == b._turn_serial or v.size > 1 or v == b.current():
		return
	var away := BWHex.direction_index(from.pos, v.pos)
	if away < 0:
		return
	for off in [0, -1, 1]:
		var d: int = (away + off + 6) % 6
		var h: Vector2i = BWHex.neighbors(v.pos)[d]
		if b.board.exists(h) and b.board.step_cost(v.pos, h) >= 0 and b.can_stand(v, h):
			v.fx[key] = b._turn_serial
			var was := v.pos
			v.pos = h
			_ev(b, v, e.name, "steps clear")
			b._emit({ "type": "move", "unit": v.id, "path": [was, h], "kind": "step" })
			return


static func _empower(b: BWBattle, u: BWUnit, e: Dictionary, by: BWUnit, scale: float = 1.0) -> void:
	var em := { "name": e.name, "uses": str(BWEffects.p(e, "uses", "next_attack")),
		"dmg_pct": float(BWEffects.p(e, "dmg_pct", 0)) * scale, "crit": float(BWEffects.p(e, "crit", 0)) * scale,
		"sure": int(BWEffects.p(e, "sure", 0)) == 1, "source": str(e.source) + ":" + by.id }
	var list: Array = u.fx.get("empower", [])
	list = list.filter(func(x): return str(x.source) != str(em.source))       # the same row doesn't stack
	list.append(em)
	u.fx["empower"] = list
	var bits: PackedStringArray = []
	if em.dmg_pct != 0.0: bits.append("+%d%% damage" % int(em.dmg_pct))
	if em.crit != 0.0: bits.append("+%d crit" % int(em.crit))
	if em.sure: bits.append("can't be avoided")
	_ev(b, u, e.name, ", ".join(bits))


# ================================================================ heals

## An on-event heal of `pct`% max HP, held to HEAL_CAP_PCT per unit per action.
static func ev_heal(b: BWBattle, u: BWUnit, pct: float, name: String) -> void:
	if not u.alive() or pct <= 0.0:
		return
	if int(u.fx.get("heal_act", -1)) != b._action_serial:
		u.fx["heal_act"] = b._action_serial
		u.fx["heal_used"] = 0.0
	var room := HEAL_CAP_PCT - float(u.fx.heal_used)
	if room <= 0.0:
		return
	pct = minf(pct, room)
	u.fx["heal_used"] = float(u.fx.heal_used) + pct
	b._heal(u, pct, "enchant:" + name)


## A drawback blocking this heal: the row's name, else "". `cause` "light" =
## a light tile or Flaring.
static func heal_blocked(u: BWUnit, cause: String) -> String:
	var dw := _drawback(u, "no_heal")
	if not dw.is_empty():
		return str(dw.name)
	dw = _drawback(u, "no_light_heal")
	if not dw.is_empty() and cause in ["light", "erupt"]:
		return str(dw.name)
	return ""


## Mend-Link: a heal received echoes to the most-hurt ally within the radius
## for `share`%. The echo never echoes.
static func on_healed(b: BWBattle, u: BWUnit, healed: int, cause: String) -> void:
	if healed <= 0 or cause == "mend_link":
		return
	for e in _on(u, "healed"):
		var best: BWUnit = null
		for o in b.side(u.team):
			if o == u or b.gap(u, o) > int(BWEffects.p(e, "radius", 2)) or o.hp >= o.max_hp():
				continue
			if best == null or float(o.hp) / o.max_hp() < float(best.hp) / best.max_hp():
				best = o
		if best != null:
			var amt := healed * float(BWEffects.p(e, "share", 50)) / 100.0
			_ev(b, u, e.name, "Mend-Link → %s" % best.name, { "target": best.id })
			b._heal(best, _pct_hp(best, amt), "mend_link")
		break


# ================================================================ knockouts

## After a KO event: ally_ko (Vengeance), then the killer's on-kill rows and
## its allies' ally_kill rows (Tag Team). On-kill never triggers on-kill.
static func on_ko(b: BWBattle, victim: BWUnit, by: BWUnit, cause: String) -> void:
	for a in b.side(victim.team):
		for e in _on(a, "ally_ko"):
			if str(BWEffects.p(e, "do", "")) == "empower":
				_empower(b, a, e, a)
	if by == null or by.team == victim.team or not by.alive():
		return
	if b._onkill_depth > 0 or cause == "knell":
		return
	b._onkill_depth += 1
	for e in _on(by, "kill"):
		if b.over:
			break
		match str(BWEffects.p(e, "do", "")):
			"action":
				if by == b.current():
					by.fx["relentless_pending"] = e.name
			"move":
				if by == b.current():
					_more_move(b, by, int(BWEffects.p(e, "hexes", 2)), e.name)
			"blast":
				var pct := float(BWEffects.p(e, "pct", 10))
				_ev(b, by, e.name, "Death Knell: %d%% burst around %s" % [int(pct), victim.name], { "hex": victim.pos })
				for f in b.foes_of(by):
					if f.alive() and BWHex.distance(f.pos, victim.pos) <= int(BWEffects.p(e, "radius", 1)) and b.can_harm(by, f):
						b._tile_hurt(f, maxi(1, roundi(f.max_hp() * pct / 100.0)), "knell", by.id)
			"paint":
				var hexes: Array = b._on_board(b.board.area(victim.pos, int(BWEffects.p(e, "radius", 1))))
				_ev(b, by, e.name, "%s spreads" % e.element.capitalize(), { "hex": victim.pos })
				b.paint(hexes, e.element, by, int(BWEffects.p(e, "step", 1)), false, { "propagated": true })
			"heal":
				if str(BWEffects.p(e, "target", "self")) == "allies":
					for o in b.side(by.team):
						if o != by and b.gap(o, by) <= int(BWEffects.p(e, "radius", 2)):
							ev_heal(b, o, float(BWEffects.p(e, "pct", 8)), e.name)
				else:
					ev_heal(b, by, float(BWEffects.p(e, "pct", 15)), e.name)
			"empower":
				for o in b.side(by.team):
					if o != by and b.gap(o, by) <= int(BWEffects.p(e, "radius", 2)):
						_empower(b, o, e, by)
	for a in b.side(by.team):
		if a == by:
			continue
		for e in _on(a, "ally_kill"):
			if b.gap(a, by) <= int(BWEffects.p(e, "radius", 2)):
				a.fx["next_move"] = int(a.fx.get("next_move", 0)) + int(BWEffects.p(e, "hexes", 2))
				a.fx["next_move_name"] = e.name
				_ev(b, a, e.name, "+%d move next turn" % int(BWEffects.p(e, "hexes", 2)))
	b._onkill_depth -= 1


## More move now: after a move (a second, short move) or before one (added).
static func _more_move(b: BWBattle, u: BWUnit, n: int, name: String) -> void:
	_ev(b, u, name, "+%d move" % n)
	if u.moved:
		u.fx["bonus_move"] = int(u.fx.get("bonus_move", 0)) + n
		b._emit({ "type": "bonus_move", "unit": u.id, "hexes": u.fx.bonus_move, "perks": [name] })
	else:
		u.fx["extra_move"] = int(u.fx.get("extra_move", 0)) + n
		b._emit({ "type": "move_bonus", "unit": u.id, "amount": n, "notes": [name] })


# ================================================================ action end

## After an attack or a skill: Steady Hand, empowerments spent, Bloodpact's
## cost, the Pincer's assist and Relentless's extra attack.
static func end_action(b: BWBattle, u: BWUnit, attacked: bool) -> void:
	var rolls := int(u.fx.get("_rolls", 0))
	var hits := int(u.fx.get("_hits", 0))
	if attacked and rolls > 0:
		if u.fx.get("_steady_live", false):
			u.fx.erase("steady")
		var em: Array = u.fx.get("empower", [])
		u.fx["empower"] = em.filter(func(x): return str(x.uses) != "next_attack")
	if rolls > 0 and hits == 0 and u.alive():
		for e in _pity(u, "miss"):
			u.fx["steady"] = e.name
			_ev(b, u, e.name, "Steady Hand: next attack can't miss")
			break
	u.fx.erase("_steady_live")
	if not u.alive() or b.over:
		return
	var dw := _drawback(u, "hp_cost")
	if not dw.is_empty() and u.hp > 1:
		var cost := mini(u.hp - 1, maxi(1, roundi(u.max_hp() * float(BWEffects.p(dw, "hp_cost", 4)) / 100.0)))
		u.hp -= cost
		_ev(b, u, dw.name, "Blood price: -%d" % cost)
		b._emit({ "type": "tile_damage", "unit": u.id, "amount": cost, "cause": "bloodpact", "hp": u.hp, "source": "" })
	_pincer(b, u)
	if u.fx.has("relentless_pending") and not b.over and u.alive() and u == b.current() and u.follow_up.is_empty():
		var nm := str(u.fx.relentless_pending)
		u.fx.erase("relentless_pending")
		if int(u.fx.get("relentless_turn", -1)) != b._turn_serial and not b.attack_targets(u).is_empty():
			u.fx["relentless_turn"] = b._turn_serial
			u.acted = false
			u.follow_up = ["basic"]
			_ev(b, u, nm, "Relentless: attack again")
			b._emit({ "type": "follow_up", "unit": u.id, "allow": u.follow_up })
	u.fx.erase("relentless_pending")


## The Pincer: once per turn, an ally next to the foe your basic attack hit
## strikes it for `share`%. Replayed as a `counter` with cause "assist".
static func _pincer(b: BWBattle, u: BWUnit) -> void:
	if not u.fx.has("_pincer"):
		return
	var t := b._unit(str(u.fx._pincer))
	u.fx.erase("_pincer")
	if t == null or not t.alive() or b.over:
		return
	for e in _on(u, "hit"):
		if str(BWEffects.p(e, "do", "")) != "assist" or int(u.fx.get("pincer_turn", -1)) == b._turn_serial:
			continue
		for o in b.side(u.team):
			if o == u or b.gap(o, t) > 1 or not b.in_range(o, t):
				continue
			u.fx["pincer_turn"] = b._turn_serial
			_ev(b, u, e.name, "Pincer: %s strikes" % o.name, { "target": t.id })
			var fc := b.forecast_basic(o, t, float(BWEffects.p(e, "share", 50)) / 100.0, "%s (assist)" % e.name)
			var res := b.roll(fc)
			land(b, o, t, res)
			var before := t.hp
			t.hp = maxi(0, t.hp - int(res.damage))
			b._emit({ "type": "counter", "unit": o.id, "target": t.id, "result": res, "forecast_hit": fc.hit.value,
				"odds": BWBattle.odds(fc), "ko": not t.alive(), "target_hp": t.hp, "name": e.name, "cause": "assist",
				"tags": BWBattle._tags(fc) })
			b._after_blow(o, t, res, before, "assist")
			after_blow(b, o, t, res, true, false)
			b._conduct(o, t, int(res.damage))
			b._check_end()
			return
		return


# ================================================================ turns

## The unit's turn start (after the D93 perks): Advantage recharges, a banked
## move (Tag Team, Windrider), Hearthbound, Sheltering, an ally's Beacon.
static func turn_start(b: BWBattle, u: BWUnit) -> void:
	for k in ["planted", "on_hexes:water", "free_water_used"]:
		u.fx.erase(k)
	if int(u.fx.get("adv_cd", 0)) > 0:
		u.fx["adv_cd"] = int(u.fx.adv_cd) - 1
	if int(u.fx.get("next_move", 0)) > 0:
		var n := int(u.fx.next_move)
		var nm := str(u.fx.get("next_move_name", "Banked move"))
		u.fx.erase("next_move")
		u.fx.erase("next_move_name")
		u.fx["start_move"] = int(u.fx.get("start_move", 0)) + n
		var notes: Array = u.fx.get("move_notes", [])
		notes.append([nm, n])
		u.fx["move_notes"] = notes
		b._emit({ "type": "move_bonus", "unit": u.id, "amount": n, "notes": [nm] })
	if b._fx_units.is_empty():
		return
	for e in _on(u, "turn_start"):
		match str(BWEffects.p(e, "do", "")):
			"heal":
				var el := str(e.element)
				var lv := b.tiles.intensity(u.pos, el) if el in BWTiles.AXIS else 0
				if lv > 0 and (int(BWEffects.p(e, "own", 0)) != 1 or str(b.tiles.at(u.pos).get("source", "")) == u.id):
					ev_heal(b, u, float(BWEffects.p(e, "pct", 3)) * lv, e.name)
			"shield":
				var best: BWUnit = null
				for o in b.side(u.team):
					if o == u or b.gap(o, u) > int(BWEffects.p(e, "radius", 2)) or o.hp >= o.max_hp():
						continue
					if best == null or float(o.hp) / o.max_hp() < float(best.hp) / best.max_hp():
						best = o
				if best != null:
					best.fx["parry"] = maxf(float(best.fx.get("parry", 0)), float(BWEffects.p(e, "pct", 30)))
					best.fx["parry_name"] = e.name
					_ev(b, best, e.name, "Sheltered: next hit -%d%%" % int(BWEffects.p(e, "pct", 30)))
	for o in b._fx_units:
		if not o.alive() or o.team != u.team:
			continue
		for e in _on(o, "ally_turn_start"):
			var on := str(BWEffects.p(e, "on_tile", "light"))
			var lv := b.tiles.intensity(u.pos, on)
			if lv > 0 and (int(BWEffects.p(e, "own", 0)) != 1 or str(b.tiles.at(u.pos).get("source", "")) == o.id):
				_empower(b, u, e, o, float(lv) if int(BWEffects.p(e, "per_level", 0)) == 1 else 1.0)


## The unit's turn end: Tending heals its neighbours, "this turn" empowerments
## end, and a Planted unit that never moved holds firm until its next turn.
static func turn_end(b: BWBattle, u: BWUnit) -> void:
	if not u.alive():
		return
	b._action_serial += 1
	for e in _on(u, "turn_end"):
		if str(BWEffects.p(e, "do", "")) == "heal":
			for o in b.side(u.team):
				if o != u and b.gap(o, u) <= int(BWEffects.p(e, "radius", 1)) and o.hp < o.max_hp():
					ev_heal(b, o, float(BWEffects.p(e, "pct", 4)), e.name)
	var em: Array = u.fx.get("empower", [])
	u.fx["empower"] = em.filter(func(x): return str(x.uses) != "turn")
	if not u.moved:
		for e in BWEffects.list(u, "attack_mod"):
			if float(BWEffects.p(e, "still_pct", 0)) != 0.0:
				u.fx["planted"] = true


## Planted: can't be displaced on a turn it hasn't moved, or until its next turn.
static func planted(b: BWBattle, u: BWUnit) -> bool:
	for e in BWEffects.list(u, "attack_mod"):
		if float(BWEffects.p(e, "still_pct", 0)) != 0.0:
			return u.fx.get("planted", false) or (u == b.current() and not u.moved)
	return false


# ================================================================ HP crossings

## Any damage on `v` (blows, tiles, arcs): Rally Cry and Lifeline watch its
## allies cross a threshold.
static func hurt(b: BWBattle, v: BWUnit, before: int) -> void:
	if not v.alive() or b.over:
		return
	var m := float(v.max_hp())
	for o in b._fx_units:
		if o == v or not o.alive() or o.team != v.team:
			continue
		for e in _on(o, "ally_low"):
			var thr := float(BWEffects.p(e, "threshold", 35))
			if b.gap(o, v) > int(BWEffects.p(e, "radius", 99)) or not (before * 100.0 >= thr * m and v.hp * 100.0 < thr * m):
				continue
			if str(BWEffects.p(e, "do", "")) == "guard" and not v.fx.has("rally_cry:" + o.id):
				v.fx["rally_cry:" + o.id] = true
				v.fx["guard"] = maxf(float(v.fx.get("guard", 0)), float(BWEffects.p(e, "pct", 25)))
				v.fx["guard_name"] = e.name
				_ev(b, v, e.name, "Rally Cry")
				b._emit({ "type": "guard", "unit": v.id, "pct": v.fx.guard, "name": e.name })
		for e in BWEffects.list(o, "swap"):
			if str(BWEffects.p(e, "on", "")) != "ally_low" or o.fx.has("lifeline_used") or o.size > 1 or v.size > 1:
				continue
			var thr2 := float(BWEffects.p(e, "threshold", 25))
			if b.gap(o, v) <= int(BWEffects.p(e, "radius", 3)) and before * 100.0 >= thr2 * m and v.hp * 100.0 < thr2 * m:
				o.fx["lifeline_used"] = true
				_ev(b, o, e.name, "Lifeline: trades places with %s" % v.name, { "target": v.id })
				_trade_places(b, o, v)


static func _trade_places(b: BWBattle, a: BWUnit, c: BWUnit) -> void:
	var pa := a.pos
	var pc := c.pos
	a.pos = pc
	c.pos = pa
	b._emit({ "type": "move", "unit": a.id, "path": [pa, pc], "kind": "place" })
	b._emit({ "type": "move", "unit": c.id, "path": [pc, pa], "kind": "place" })


# ================================================================ swap (Bodyguard)

## Bodyguard: allies within the radius are move targets for `cost`, once per
## turn (it is the unit's move). Entries carry `swap` = the ally's id.
static func add_swaps(b: BWBattle, u: BWUnit, r: Dictionary) -> void:
	if u.moved or u.size > 1 or u.effects.is_empty():
		return
	for e in BWEffects.list(u, "swap"):
		if str(BWEffects.p(e, "mode", "")) != "move":
			continue
		if u.move_range() < int(BWEffects.p(e, "cost", 1)):
			return
		for o in b.side(u.team):
			if o == u or o.size > 1 or b.gap(o, u) > int(BWEffects.p(e, "radius", 2)):
				continue
			r[o.pos] = { "cost": int(BWEffects.p(e, "cost", 1)), "from": u.pos, "stop": true, "swap": o.id,
				"path": [u.pos, o.pos], "name": e.name }
		return


## The swap itself (BWBattle.move on a `swap` entry).
static func swap_move(b: BWBattle, u: BWUnit, h: Vector2i, entry: Dictionary) -> bool:
	var o := b._unit(str(entry.swap))
	if o == null or not o.alive() or o.pos != h:
		return false
	b._undo = {}
	u.moved = true
	u.fx["moved_hexes"] = int(u.fx.get("moved_hexes", 0)) + 1
	u.facing = BWHex.direction_index(u.pos, h) if BWHex.distance(u.pos, h) == 1 else u.facing
	_ev(b, u, str(entry.get("name", "Bodyguard")), "swaps with %s" % o.name, { "target": o.id })
	_trade_places(b, u, o)
	return true


# ================================================================ ground

## Overload: the credited unit's +per_level% per charge point blown.
static func overload(src: BWUnit, points: int) -> float:
	var m := 1.0
	if src == null:
		return m
	for e in BWEffects.list(src, "element_damage_pct", "thunder"):
		var pl := float(BWEffects.p(e, "per_level", 0))
		if pl != 0.0 and points > 0:
			m *= 1.0 + pl * points / 100.0
	return m


## Sapping: each detonation source heals pct_of% of the blast it dealt to foes.
static func after_blast(b: BWBattle, hurt: Dictionary) -> void:
	var by_src := {}
	for u in hurt:
		var src := b._unit(str(hurt[u][1]))
		if src != null and src.team != (u as BWUnit).team:
			by_src[src] = int(by_src.get(src, 0)) + int(hurt[u][0])
	for src in by_src:
		for e in _on(src, "detonate"):
			ev_heal(b, src, _pct_hp(src, by_src[src] * float(BWEffects.p(e, "pct_of", 10)) / 100.0), e.name)


## After a paint: Cold Snap pins a foe on a glaze it just made; Windrider
## banks +1 move for allies under its gale copies.
static func after_paint(b: BWBattle, by: BWUnit, element: String, r: Dictionary) -> void:
	if by == null or b.over or by.effects.is_empty():
		return
	if element == "ice":
		for e in _on(by, "glaze"):
			for h in r.changed:
				if b.tiles.is_glazed(h) and str(b.tiles.at(h).get("glaze_source", "")) == by.id:
					var v := b._centre_at(h)
					if v != null and v.team != by.team:
						_ev(b, by, e.name, "Cold Snap", { "target": v.id })
						b._add_status(v, str(BWEffects.p(e, "status", "pinned")), by, 1)
	for g in r.gales:
		for e in _on(by, "gale"):
			for h in g.copies + [g.origin]:
				var v := b._centre_at(h)
				if v != null and v.team == by.team:
					v.fx["next_move"] = maxi(int(v.fx.get("next_move", 0)), int(BWEffects.p(e, "hexes", 1)))
					v.fx["next_move_name"] = e.name
					_ev(b, v, e.name, "+%d move next turn" % int(BWEffects.p(e, "hexes", 1)))


## Lightning-Touched: always conductive.
static func conductive(v: BWUnit) -> bool:
	return not _drawback(v, "conductive").is_empty()


## The share of a hit that arcs: CHAIN_FRACTION, or Lightning-Touched's chain_pct.
static func chain_frac(by: BWUnit) -> float:
	if by != null:
		for e in BWEffects.list(by, "element_damage_pct"):
			if float(BWEffects.p(e, "chain_pct", 0)) > 0.0:
				return float(BWEffects.p(e, "chain_pct")) / 100.0
	return BWTiles.CHAIN_FRACTION


## Conductor: an arc you caused heals you pct_of%.
static func after_arc(b: BWBattle, by: BWUnit, dmg: int) -> void:
	if by == null or dmg <= 0 or not by.alive():
		return
	for e in _on(by, "chain"):
		ev_heal(b, by, _pct_hp(by, dmg * float(BWEffects.p(e, "pct_of", 50)) / 100.0), e.name)


## Pyre: more damage from fire tiles.
static func tile_mult(u: BWUnit, element: String) -> float:
	var dw := _drawback(u, "fire_taken_pct")
	if element == "fire" and not dw.is_empty():
		return 1.0 + float(BWEffects.p(dw, "fire_taken_pct", 50)) / 100.0
	return 1.0


## Unshaken: the first status a foe lays on you each battle is ignored.
static func shrug_status(b: BWBattle, v: BWUnit, key: String, by: BWUnit) -> bool:
	if by == null or by.team == v.team or v.fx.has("unshaken_used"):
		return false
	for e in BWEffects.list(v, "immune"):
		if str(BWEffects.p(e, "what", "")) == "status":
			v.fx["unshaken_used"] = true
			b._emit({ "type": "status_resisted", "unit": v.id, "status": key, "reason": e.name })
			_ev(b, v, e.name, "Unshaken: shrugs it off")
			return true
	return false


## Fury (trigger_stat dmg_pct): +dmg_pct% per firing, up to cap_pct.
static func fury(b: BWBattle, u: BWUnit, e: Dictionary) -> void:
	var key := "fury:" + str(e.source)
	var got := float(u.fx.get(key, 0))
	var cap := float(BWEffects.p(e, "cap_pct", 20))
	var add := minf(float(BWEffects.p(e, "dmg_pct", 4)), cap - got)
	if add <= 0.0:
		return
	u.fx[key] = got + add
	_ev(b, u, e.name, "Fury +%d%% (%d%%)" % [int(add), int(got + add)])


## Leaden: the drawback's move.
static func move_mod(u: BWUnit) -> int:
	var dw := _drawback(u, "move")
	return int(BWEffects.p(dw, "move", 0)) if not dw.is_empty() else 0
