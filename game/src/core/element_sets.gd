class_name BWSets
## Element set bonuses (D282; design/PASSIVES-v2.md §3, re-cut by
## ELEMENTS-v3 §10 and the author's 2026-10-07 rulings). Pure counting plus
## the 3-piece battle hooks (called from BWEnchant's hook points).
##
## What counts: head, chest and legs (each toward its colour, BWRun.item_element:
## its enchantment's element, a Warded piece's ward), and the DRAWN weapon's
## imbue toward that element. The carried weapon counts for nothing (D180);
## a swap updates the count at once (BWUnit.swap_weapons refreshes effects).
## Tiers: 2 pieces and 3 pieces; a 4th adds nothing. A set sleeps until its
## element is learned (affinity > 0).
##
## data/sets.csv: id (= element), element, two_text, two (the 2-piece's
## effect records, "key(params) | key(params)", served by the existing
## hooks: stand_on_bonus, heat_rush, aura_mod, element_damage_pct), three
## (the 3-piece's name), three_text, three_params. The 3-piece is ONE record,
## key "set_bonus", params kind=<element> + three_params; a once-a-battle one
## is spent in u.fx["set3:<element>"] (a swap never re-arms it).

const TABLE := "sets"
const SLOTS := ["head", "chest", "legs"]
const TIERS := [2, 3]


## element -> pieces (head, chest, legs by colour; the drawn weapon by imbue).
static func counts(u) -> Dictionary:
	var out := {}
	if u == null:
		return out
	for slot in SLOTS:
		var el := BWRun.item_element(u.equipment.get(slot, {}))
		if el != "":
			out[el] = int(out.get(el, 0)) + 1
	var imb := str(u.equipment.get("main_hand", {}).get("imbue", ""))
	if imb != "":
		out[imb] = int(out.get(imb, 0)) + 1
	return out


## The pieces `u` has toward `el`, before the learned gate.
static func pieces(u, el: String) -> int:
	return int(counts(u).get(el, 0))


## The tier `u` has in `el`: 0, 2 or 3 (asleep = 0 while unlearned).
static func tier(u, el: String) -> int:
	if u == null or int(u.affinity.get(el, 0)) <= 0:
		return 0
	var n := pieces(u, el)
	return 3 if n >= 3 else (2 if n >= 2 else 0)


static func row(el: String) -> Dictionary:
	return BWData.row(TABLE, el)


static func three_name(el: String) -> String:
	return str(row(el).get("three", ""))


## The active sets: [{ element, pieces, tier, two_text, three, three_text }],
## element order. Unlearned ones are left out.
static func active(u) -> Array:
	var out: Array = []
	for el in BWFormulas.ELEMENTS:
		var t := tier(u, el)
		if t == 0:
			continue
		var r := row(el)
		out.append({ "element": el, "pieces": mini(pieces(u, el), 3), "tier": t,
			"two_text": str(r.get("two_text", "")), "three": str(r.get("three", "")),
			"three_text": str(r.get("three_text", "")) })
	return out


## The gear panel's one line: "Sets: Fire 2/3 · Water 3/3 (Breakwater)", "" when none.
static func summary(u) -> String:
	var parts: Array = []
	for a in active(u):
		parts.append("%s %d/3%s" % [str(a.element).capitalize(), int(a.pieces),
			(" (%s)" % a.three) if int(a.tier) >= 3 else ""])
	return "" if parts.is_empty() else "Sets: " + " · ".join(parts)


## The item card's dim line for an item that counts toward a set:
## "Set: Fire 2/3 · next: Flashpoint". `u` = who wears it (null = loose: the
## count is the item alone). `as_if`: count it as if equipped on `u` (shop,
## loot and scroll cards: "Set: Fire → 2/3"). "" for an item that counts
## toward nothing (a carried weapon, an uncoloured piece).
static func card_line(item: Dictionary, u = null, as_if: bool = false) -> String:
	var el := item_set_element(item)
	if el == "" or row(el).is_empty():
		return ""
	var n := 1
	if u != null:
		n = pieces(u, el)
		if as_if:
			var slot := str(item.get("slot", ""))
			var cur: Dictionary = u.equipment.get(slot, {})
			var cur_el := item_set_element(cur) if slot in SLOTS or slot == "main_hand" else ""
			if cur.get("uid", "") != item.get("uid", "-"):
				n += 1
				if cur_el == el:
					n -= 1
	n = clampi(n, 1, 3)
	var nxt := ""
	if n < 2:
		nxt = " · next: 2-piece"
	elif n < 3:
		nxt = " · next: %s" % three_name(el)
	else:
		nxt = " · %s" % three_name(el)
	return "Set: %s %s%d/3%s" % [el.capitalize(), "→ " if as_if else "", n, nxt]


## The element an item counts toward: armour by colour, a weapon by its imbue.
static func item_set_element(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	var slot := str(item.get("slot", ""))
	if slot == "main_hand":
		return str(item.get("imbue", ""))
	if slot in SLOTS:
		return BWRun.item_element(item)
	return ""


## Effect records for BWEffects.collect: each active 2-piece's records, and
## the 3-piece's set_bonus record. Named "Fire set (2)" / "Flashpoint (Fire set)".
static func records(u) -> Array:
	var out: Array = []
	for el in BWFormulas.ELEMENTS:
		var t := tier(u, el)
		if t == 0:
			continue
		var r := row(el)
		var pseudo := { "id": "set_" + el, "element": el, "effect_key": "", "params": "", "also": str(r.get("two", "")) }
		var recs := BWEffects.records(pseudo, "%s set (2)" % el.capitalize())
		recs.pop_front()                         # the empty primary; the 2-piece lives in `also`
		for rec in recs:
			rec["kind"] = "set"
			out.append(rec)
		if t >= 3:
			var p := BWEffects.parse_params(str(r.get("three_params", "")))
			p["kind"] = el
			out.append({ "key": "set_bonus", "params": p, "source": "set_" + el, "element": el,
				"kind": "set", "rank": 1, "name": "%s (%s set)" % [str(r.get("three", "")), el.capitalize()] })
			if el == "ice":                      # Frost Ward rides the existing hook (battle.gd)
				out.append({ "key": "frost_ward", "params": { "radius": int(p.get("radius", 2)) }, "source": "set_ice",
					"element": "ice", "kind": "set", "rank": 1, "name": "Frost Ward (Ice set)" })
	return out


## The 3-piece record of `el` on `u`, {} if not active.
static func three(u, el: String) -> Dictionary:
	if u == null:
		return {}
	for e in u.effects:
		if str(e.key) == "set_bonus" and str(e.params.get("kind", "")) == el:
			return e
	return {}


static func _spent(u, el: String) -> bool:
	return u.fx.has("set3:" + el)


static func _spend(b, u, el: String, e: Dictionary, text: String, extra: Dictionary = {}) -> void:
	u.fx["set3:" + el] = true
	var ev := { "type": "set_trigger", "unit": u.id, "element": el, "name": str(e.name), "text": text }
	ev.merge(extra)
	b._emit(ev)


# ---------------------------------------------------------------- 2-piece riders read by other files

## Ice 2: your pillars last this many more ticks (BWPools.raise_pillar).
static func pillar_plus(u) -> int:
	return 1 if tier(u, "ice") >= 2 else 0


## Water 2: pools your casts reach run this far (BWPools.pool, D307).
const WATER_POOL_MAX := 25

static func pool_max(u) -> int:
	return WATER_POOL_MAX if tier(u, "water") >= 2 else BWPools.POOL_MAX


## Thunder 2: electrified water shocks you at this factor (BWPools shock).
static func shock_mult(u) -> float:
	return 0.5 if tier(u, "thunder") >= 2 else 1.0


## Dark 2: no dark drain on you (BWBattle turn start).
static func no_drain(u) -> bool:
	return tier(u, "dark") >= 2


## Wind 2: your fields and modes skip your allies (BWWind).
static func spares_allies(owner, v) -> bool:
	return owner != null and v != null and owner != v and owner.team == v.team and tier(owner, "wind") >= 2


## Light 2: Empowered allies of yours get this many % more (the light lane's Empowered).
static func empower_plus(u) -> float:
	return 5.0 if tier(u, "light") >= 2 else 0.0


# ---------------------------------------------------------------- 3-piece hooks (via BWEnchant)

## Forecast lines (BWEnchant.mods): the 2-piece stat terms the attacker and
## defender stand in, as notes; Slipstream's sure hit.
static func mods(att, dfn, ctx: Dictionary) -> Array:
	var out: Array = []
	for who in [att, dfn]:
		if who == null or not who.fx_hook.is_valid():
			continue
		var b = who.fx_hook.get_object()                 # the battle (BWBattle._situational)
		if b == null or not "tiles" in b:
			continue
		for e in who.effects:
			if str(e.get("kind", "")) != "set" or str(e.key) != "stand_on_bonus":
				continue
			var el := str(e.element)
			var st := str(e.params.get("stat", ""))
			var pts := 0
			if el in BWTiles.AXIS:
				pts = b.tiles.intensity(who.pos, el)
			elif el == "ice" and b.tiles.is_glazed(who.pos):
				pts = 1
			if pts <= 0:
				continue
			var val := BWEnchant.stand_on(who, e, st, pts if el in BWTiles.AXIS else 0)
			out.append({ "stage": "note", "value": 0.0,
				"label": "%s set: +%d %s (%s on %s)" % [el.capitalize(), roundi(val), st.to_upper(), who.name,
					("%s %d" % [el, pts]) if el in BWTiles.AXIS else "glaze"] })
	if att != null:
		var s := three(att, "wind")
		if not s.is_empty() and int(ctx.get("moved", 0)) >= int(s.params.get("moved", 4)):
			out.append({ "stage": "hit", "value": 1000.0, "label": "%s (moved %d): can't be avoided" % [str(s.name), int(ctx.moved)] })
	return out


## Vanish (dark 3), from BWEnchant.roll_blow: a hit worth min_pct% of the
## victim's max HP misses, once a battle, standing on dark; then it shifts
## to the nearest free dark hex within radius.
static func roll(b, att, v, fc: Dictionary, res: Dictionary) -> Dictionary:
	if b.expected_rolls or v == null or not res.get("hit", false) or att == null or att.team == v.team:
		return res
	var e := three(v, "dark")
	if e.is_empty() or _spent(v, "dark") or b.tiles.intensity(v.pos, "dark") <= 0:
		return res
	if float(res.get("damage", 0)) * 100.0 < float(e.params.get("min_pct", 25)) * v.max_hp():
		return res
	res["hit"] = false
	res["damage"] = 0
	res["crit"] = false
	_spend(b, v, "dark", e, "the hit misses")
	var best := Vector2i(-9999, -9999)
	var bd := 99
	for h in b.board.area(v.pos, int(e.params.get("radius", 3))):
		if h == v.pos or b.tiles.intensity(h, "dark") <= 0 or b.unit_at(h) != null or not b.board.is_passable(h):
			continue
		var d := BWHex.distance(v.pos, h)
		if d < bd:
			bd = d
			best = h
	if bd < 99:
		var from: Vector2i = v.pos
		v.pos = best
		b._emit({ "type": "move", "unit": v.id, "path": [from, best], "kind": "shift" })
	return res


## Dawnward (light 3), from BWEnchant.land: a KO blow on `v` (or an ally
## within radius of the holder) leaves it at 1 HP on light 3. Returns the damage.
static func land(b, v, dmg: int) -> int:
	if dmg < v.hp or b.expected_rolls:
		return dmg
	for o in b.units:
		if not o.alive() or o.team != v.team:
			continue
		var e := three(o, "light")
		if e.is_empty() or _spent(o, "light") or b.gap(o, v) > int(e.params.get("radius", 3)):
			continue
		_spend(b, o, "light", e, "%s holds at 1 HP" % v.name, { "target": v.id })
		b.paint([v.pos], "light", o, int(e.params.get("level", 3)), false)
		return maxi(0, v.hp - 1)
	return dmg


## Flashpoint (fire 3), from BWEnchant.hurt: dropping under threshold% once a
## battle sets its hex and ring to fire 3 and heals heal_pct%.
static func hurt(b, v, before: int) -> void:
	var e := three(v, "fire")
	if e.is_empty() or _spent(v, "fire") or not v.alive():
		return
	var thr := float(e.params.get("threshold", 50))
	var m := float(v.max_hp())
	if before * 100.0 >= thr * m and v.hp * 100.0 < thr * m:
		_spend(b, v, "fire", e, "fire 3 around, +%d%%" % int(e.params.get("heal_pct", 20)))
		var hexes: Array = b.board.area(v.pos, 1).filter(func(h): return b.board.exists(h))
		b.paint(hexes, "fire", v, int(e.params.get("level", 3)), false)
		b._heal(v, float(e.params.get("heal_pct", 20)), "set:Flashpoint")


## Breakwater (water 3), from BWEnchant.after_blow: once a battle, a foe that
## hits the holder is swept `push` hexes away and Drenched.
static func after_blow(b, att, v, res: Dictionary) -> void:
	if att == null or b.over or not res.get("hit", false) or att.team == v.team or not att.alive() or not v.alive():
		return
	var e := three(v, "water")
	if e.is_empty() or _spent(v, "water"):
		return
	_spend(b, v, "water", e, "%s is swept away" % att.name, { "target": att.id })
	var dir := _dir_toward(v.pos, att.pos)          # away from the holder
	b._displace(att, dir, int(e.params.get("push", 2)), "push", true)
	if att.alive():
		b._add_status(att, str(e.params.get("status", "drenched")), v, 1)


## The neighbour direction (0-5) from `a` whose step gets closest to `c`.
static func _dir_toward(a: Vector2i, c: Vector2i) -> int:
	var best := -1
	var bd := 1 << 30
	for i in 6:
		var d := BWHex.distance(BWHex.neighbors(a)[i], c)
		if d < bd:
			bd = d
			best = i
	return best


## Stormfront (thunder 3), from BWEnchant.after_blast: the first detonation
## each turn of a holder also arcs to every conductive foe (on a fuse or a
## shocked hex, or Lightning-Touched) it didn't already hurt: arc_pct% max
## HP each, thunder class.
static func after_blast(b, hurt: Dictionary) -> void:
	var srcs := {}
	for u in hurt:
		var s = b._unit(str(hurt[u][1]))
		if s != null:
			srcs[s] = true
	for src in srcs:
		var e := three(src, "thunder")
		if e.is_empty() or int(src.fx.get("stormfront_turn", -1)) == b._turn_serial:
			continue
		var targets: Array = []
		for v in b.units:
			if v.alive() and v.team != src.team and not hurt.has(v) and (b.tiles.conductive(v.pos) or BWEnchant.conductive(v)):
				targets.append(v)
		if targets.is_empty():
			continue
		src.fx["stormfront_turn"] = b._turn_serial
		b._emit({ "type": "set_trigger", "unit": src.id, "element": "thunder", "name": str(e.name),
			"text": "arcs to %d" % targets.size() })
		var pct := float(e.params.get("arc_pct", 10))
		for v in targets:
			b._tile_hurt(v, b._tile_dmg(v, pct, "thunder"), "arc", src.id)
