class_name BWPerkRules
## D281: the battle halves of the re-cut perks' new riders (design/ELEMENTS-v3.md
## §10 with the author's 2026-10-07 rulings). Each is called from one hook line
## in battle.gd, slides.gd or wind_modes.gd. Pure rules over the battle, no nodes.
##   Current Push (pool_push)   your hit on a foe standing in water pushes it 1, onto water
##   Rime Armour (noslam)       you and allies on glaze take no slam damage
##   Fault Lines (slam_pct)     slams you cause deal +8%
##   Frostbite (pillar_pin)     a foe slamming into your pillar is Pinned
##   Crosswind (crosswind)      your wind slams deal 12%, and Becalm the foe
##   Nightborn (allies)         an adjacent ally on dark is covered too
##   Sanctuary (radiant_guard allies)  light's hit bonus spares your allies


## A living unit of `team` holds `key` with `param` = 1.
static func team_has(b, team: String, key: String, param: String) -> bool:
	for o in b._fx_units:
		if o.alive() and o.team == team:
			for e in BWEffects.list(o, key):
				if int(BWEffects.p(e, param, 0)) == 1:
					return true
	return false


## Nightborn's cover: an adjacent living ally of `u` holds Nightborn (allies=1).
static func nightborn_cover(b, u) -> bool:
	for o in b._fx_units:
		if o != u and o.alive() and o.team == u.team and b.gap(o, u) <= 1:
			for e in BWEffects.list(o, "nightborn"):
				if int(BWEffects.p(e, "allies", 0)) == 1:
					return true
	return false


## Current Push: once per action, a hit by `att` on a foe standing in water
## pushes it 1 straight away from `att`, when that hex is water too ("along
## the water"); otherwise along the water hex beside it farthest from `att`.
static func after_blow(b, att, v, res: Dictionary) -> void:
	if b.over or att == null or not v.alive() or att.team == v.team or not res.get("hit", false):
		return
	var es := BWEffects.list(att, "pool_push")
	if es.is_empty() or BWEffects.level_at(b.tiles, v.pos, "water") <= 0:
		return
	if int(att.fx.get("pool_push_act", -1)) == b._action_serial:
		return
	var best := -1
	var bd := -1
	for i in 6:
		var n: Vector2i = BWHex.neighbors(v.pos)[i]
		if not b.board.exists(n) or BWEffects.level_at(b.tiles, n, "water") <= 0 or b.unit_at(n) != null:
			continue
		var d := BWHex.distance(n, att.pos)
		if d > bd:
			bd = d
			best = i
	if best < 0:
		return
	att.fx["pool_push_act"] = b._action_serial
	b._emit({ "type": "perk", "unit": att.id, "perk": BWEffects.list(att, "pool_push")[0].name, "target": v.id })
	b._displace(v, best, int(BWEffects.p(es[0], "push", 1)), "push", true)


## The slam % on `v` (Slide or Gust): `base`, Fault Lines' +slam_pct when
## `by` caused it, Crosswind's flat slam_pct for a wind slam, and 0 when
## Rime Armour (noslam) covers `v` on glaze.
static func slam_pct(b, v, by_id: String, base: float, wind: bool) -> float:
	if v == null:
		return base
	if b.tiles.is_glazed(v.pos) and (_noslam(v) or team_has(b, v.team, "rime_armour", "noslam")):
		return 0.0
	var by = b._unit(by_id) if by_id != "" else null
	var pct := base
	if by != null and by.team != v.team:
		if wind:
			for e in BWEffects.list(by, "crosswind"):
				pct = maxf(pct, float(BWEffects.p(e, "slam_pct", 12)))
		for e in BWEffects.list(by, "fault_lines"):
			pct += float(BWEffects.p(e, "slam_pct", 0))
	return pct


static func _noslam(v) -> bool:
	for e in BWEffects.list(v, "rime_armour"):
		if int(BWEffects.p(e, "noslam", 0)) == 1:
			return true
	return false


## After a slam on `v`: Crosswind Becalms it (a wind slam by a holder);
## Frostbite Pins it when it hit the holder's pillar at `pillar`.
static func after_slam(b, v, by_id: String, wind: bool, pillar: Vector2i = Vector2i(-9999, -9999)) -> void:
	if b.over or v == null or not v.alive():
		return
	var by = b._unit(by_id) if by_id != "" else null
	if wind and by != null and by.team != v.team and BWEffects.has(by, "crosswind"):
		BWWind.becalm(b, v, by)
	if pillar != Vector2i(-9999, -9999) and b.tiles.pillars.has(pillar):
		var owner = b._unit(str(b.tiles.pillars[pillar].get("owner", "")))
		if owner != null and owner.team != v.team:
			for e in BWEffects.list(owner, "frostbite"):
				if int(BWEffects.p(e, "pillar_pin", 0)) == 1:
					b._emit({ "type": "perk", "unit": owner.id, "perk": e.name, "target": v.id })
					b._add_status(v, "pinned", owner, 1)
					break
