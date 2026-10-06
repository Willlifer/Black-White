class_name BWEffects
## The effect engine for enchantments and abilities (design/EQUIPMENT.md §1).
##
## A unit's active effects are one per equipped item's enchantment, one per
## equipped ability (BWUnit.abilities, filled by BWRun.prepare_for_battle) at
## its rank, and one per element perk (BWUnit.perks, D90). Each is a record:
##   { key, params, source, element, kind, rank, name }
## `key` is one of the 25 effect_keys, `params` the parsed "a=1;b=2" cell,
## `source` the enchantment or ability id, `element` the enchantment's element
## column ("" for weapon enchantments and abilities), `name` what the forecast
## hover prints ("Stormcaller's Tiara", "Deadeye").
##
## This file holds the data side and the pure queries. The battle consults it
## through hooks marked "# FX hook:" in battle.gd, tiles.gd, formulas.gd and
## unit.gd; each hook names the keys it serves. Records are cached on the unit
## (BWUnit.effects) by BWUnit.refresh_effects(), which begin_battle() calls.

const TYPES := ["reactive", "supportive", "passive"]
const SLOT_ORDER := ["main_hand", "head", "chest", "legs"]

## Ability ranks (EQUIPMENT.md §9 "Train in an ability"): every rank above 1
## adds RANK_STEP to the effect's magnitude, up to MAX_RANK. Rank 3 = ×1.5.
const MAX_RANK := 3
const RANK_STEP := 0.25
## Params that are shape, gating or bookkeeping, never magnitude: ranks leave
## them alone. "move" and "plus" (range) are here on purpose: a +1 hex is
## already a big step on a 3v3 board.
const UNSCALED := ["radius", "allies", "threshold", "once", "once_per_battle", "min_range",
	"per_turn", "range", "count", "mult", "plus", "ranged_only", "basic", "skills", "friendly",
	"delay", "consume", "melee_only", "chance", "turns", "steps", "step", "hexes", "push",
	"move", "cap_pct", "cap"]
## Multiplier params scale only their excess over 1 (×2 → ×2.5 at rank 3).
const MULT_PARAMS := ["chance_mult", "reduction_mult"]

## D33 / E2: enchantment damage written as flat points converts to % of the
## victim's max HP at V8's own ratio (flat 3 per point → 4% per point, as
## ELEMENTS §10 did for fire and detonations). Rounded to a whole percent.
const FLAT_TO_PCT := 4.0 / 3.0

## Keys that work whatever elements the wearer has learned (EQUIPMENT.md §1).
## Every other element-tagged enchantment sleeps until its element is learned.
const DEFENSIVE := ["damage_taken_mod", "immune"]

## The 25 equipment / ability keys (EQUIPMENT.md §1).
const GEAR_KEYS := ["element_damage_pct", "damage_taken_mod", "tile_duration_plus", "affinity_gain_plus",
	"stand_on_bonus", "aura_mod", "attack_mod", "lay_on", "cast_step_plus", "tile_potency_pct", "trigger_stat",
	"element_area_plus", "glance_mod", "stat_share", "immune", "effect_repeat", "tile_erupt", "range_mod",
	"multi_hit", "move_after_attack", "knockback", "counter_attack", "skill_cd_minus", "guard", "aoe_radius_plus"]
## D93: keys added for the 35 element perks (data/perks.csv; ELEMENTS.md §12).
## Each is served by a "Perk hook:" in battle.gd (tiles.gd for wildfire and
## static_field's fuse timer, via paint_opts). "level" in a param means the
## charge level of the hex (level_at).
##   move_cost      on, cost        entering an `on` hex costs `cost` (Waterwalking)
##   stand_on_mod   on, side, stage, per_point, team   a forecast term scaled by the
##                  level under the attacker (att), the defender (def) or the higher of
##                  the two (either); team=1 covers the holder's allies (Flow State)
##   start_move     on, per_point | l1..l3, team   move at turn start by level (Coal Engine, Sunpath)
##   undertow, heat_rush, ember_skin, wildfire, skate, rime_armour, fault_lines, frostbite,
##   frost_ward, bolt_step, grounded, overcharge, static_field, lightning_rod, tailwind,
##   eye_of_storm, gust, slipstream, shadowstep, nightborn, hit_status, cover,
##   radiant_guard, judgement, glare, sanctuary: one rule each (see perks.csv text)
const PERK_KEYS := ["move_cost", "stand_on_mod", "start_move", "undertow", "heat_rush", "ember_skin",
	"wildfire", "skate", "rime_armour", "fault_lines", "frostbite", "frost_ward", "bolt_step", "grounded",
	"overcharge", "static_field", "lightning_rod", "tailwind", "eye_of_storm", "gust", "slipstream",
	"shadowstep", "nightborn", "hit_status", "cover", "radiant_guard", "judgement", "glare", "sanctuary"]
const KEYS := GEAR_KEYS + PERK_KEYS

## "AoE skills" for aoe_radius_plus (Cleaving, Channelling) are the skill
## defs with `aoe: true` in their row (D89): arcing_shot, surge,
## tridentpierce, cleave, daggerleap.


## "a=1;b=wil+res" -> { a: 1, b: "wil+res" }. Numbers become numbers.
static func parse_params(cell: Variant) -> Dictionary:
	var out := {}
	for part in str(cell).split(";", false):
		var kv := part.split("=", true, 1)
		if kv.size() != 2:
			continue
		var k := kv[0].strip_edges()
		var v := kv[1].strip_edges()
		if v.is_valid_int():
			out[k] = v.to_int()
		elif v.is_valid_float():
			out[k] = v.to_float()
		else:
			out[k] = v
	return out


## Every effect the unit carries right now, enchantments first (slot order),
## then abilities (reactive, supportive, passive), then perks (order taken).
## Deterministic order.
static func collect(u: BWUnit) -> Array:
	var out: Array = []
	for slot in SLOT_ORDER:
		var it: Dictionary = u.equipment.get(slot, {})
		var ench := str(it.get("enchant", ""))
		if ench == "":
			continue
		var row := BWData.row("enchantments", ench)
		if row.is_empty():
			continue
		var base_name := str(BWData.row("equipment", str(it.get("base", ""))).get("name", it.get("base", "")))
		var nm := str(row.get("name_pattern", ench)).replace("{item}", base_name)
		out.append(make(row, "enchant", 1, nm))
	for type in TYPES:
		var a: Dictionary = u.abilities.get(type, {})
		if a.is_empty():
			continue
		var row := BWData.row("abilities", str(a.get("id", "")))
		if row.is_empty():
			continue
		var rank := int(a.get("rank", 1))
		var nm := str(row.get("name", a.id))
		if rank > 1:
			nm += " %d" % mini(rank, MAX_RANK)
		out.append(make(row, "ability", rank, nm))
	# D90: element perks (data/perks.csv), in the order taken. The row's
	# element column gates them like an element enchantment (always learned:
	# a perk is only granted at affinity rank 1+).
	for id in u.perks:
		var row := BWData.row("perks", str(id))
		if not row.is_empty():
			out.append(make(row, "perk", 1, str(row.get("name", id))))
	return out


## One record from a CSV row (enchantments.csv or abilities.csv).
static func make(row: Dictionary, kind: String, rank: int = 1, display: String = "") -> Dictionary:
	var params := parse_params(row.get("params", ""))
	var key := str(row.get("effect_key", ""))
	if key == "tile_erupt":
		# D33: flat damage/heal per point -> % max HP per point (EQUIPMENT.md §8).
		if not params.has("dmg_pct_per_point"):
			params["dmg_pct_per_point"] = roundi(float(params.get("dmg_per_point", 0)) * FLAT_TO_PCT)
		if not params.has("heal_pct_per_point"):
			params["heal_pct_per_point"] = roundi(float(params.get("heal_per_point", 0)) * FLAT_TO_PCT)
	if rank > 1:
		params = scale(params, rank)
	return {
		"key": key, "params": params, "source": str(row.get("id", "")),
		"element": str(row.get("element", "")), "kind": kind, "rank": rank,
		"name": display if display != "" else str(row.get("name", row.get("id", ""))),
	}


## Rank scaling: magnitude × (1 + 0.25 × (rank − 1)), rank capped at 3.
static func scale(params: Dictionary, rank: int) -> Dictionary:
	var f := 1.0 + RANK_STEP * (clampi(rank, 1, MAX_RANK) - 1)
	var out := params.duplicate()
	for k in out:
		var v: Variant = out[k]
		if k in UNSCALED or not (v is int or v is float):
			continue
		if k in MULT_PARAMS:
			out[k] = 1.0 + (float(v) - 1.0) * f
		elif v is int:
			out[k] = roundi(v * f)
		else:
			out[k] = v * f
	return out


## Is the record awake? Element enchantments sleep until the element is
## learned (affinity rank ≥ 1); defensive keys and element-less rows never do.
static func awake(u: BWUnit, e: Dictionary) -> bool:
	if e.element == "" or e.key in DEFENSIVE:
		return true
	return u.affinity_rank(e.element) >= 1


## Awake records of one key; `element` "*" = any, otherwise that row element.
static func list(u: BWUnit, key: String, element: String = "*") -> Array:
	var out: Array = []
	for e in u.effects:
		if e.key == key and (element == "*" or e.element == element) and awake(u, e):
			out.append(e)
	return out


static func has(u: BWUnit, key: String, element: String = "*") -> bool:
	return not list(u, key, element).is_empty()


## Sum of one numeric param over awake records of a key.
static func total(u: BWUnit, key: String, param: String, element: String = "*") -> float:
	var s := 0.0
	for e in list(u, key, element):
		s += float(e.params.get(param, 0))
	return s


static func p(e: Dictionary, param: String, default: Variant = 0) -> Variant:
	return e.params.get(param, default)


# ----------------------------------------------------------------- stat_share

## stat_share (Steel Under Cloth, Nimble Strength, Insight): pct% of the
## `from` stat, read from base + gear only so two shares can never loop.
static func share(u: BWUnit, key: String) -> int:
	var v := 0
	for e in u.effects:
		if e.key != "stat_share" or str(e.params.get("to", "")) != key:
			continue
		var from := str(e.params.get("from", ""))
		var raw: int = int(u.stats.get(from, 0))
		for item in u.equipment.values():
			raw += int(item.get("stats", {}).get(from, 0))
		v += floori(raw * float(e.params.get("pct", 0)) / 100.0)
	return v


## aura_mod that the holder itself gets (radius 0, or allies=0): what a sheet
## shows outside a battle. In battle the battle's _auras() covers this.
static func self_aura(u: BWUnit, key: String) -> float:
	var v := 0.0
	for e in u.effects:
		if e.key == "aura_mod" and (int(e.params.get("radius", 0)) == 0 or int(e.params.get("allies", 0)) == 0):
			v += float(e.params.get(key, 0))
	return v


# ----------------------------------------------------------------- tiles

## Options handed to BWTiles.apply for one paint by `u` (tile_duration_plus,
## cast_step_plus, element_area_plus, tile_erupt). `cast` = an action's own
## shape; lay_on triggers and erupts are not casts and get no step or ring.
static func paint_opts(u: BWUnit, element: String, hexes: Array, board: BWBoard, cast: bool) -> Dictionary:
	var o := { "steps_plus": 0 }
	if u == null:
		return o
	var turns := int(total(u, "tile_duration_plus", "turns", element))
	if turns > 0:
		match element:
			"ice": o["glaze_plus"] = turns
			"wind": o["gale_timer_plus"] = turns
			"thunder": pass
			_: o["timer_plus"] = turns
	if cast:
		if element in BWTiles.AXIS:
			o.steps_plus = int(total(u, "cast_step_plus", "steps", element))
		for e in list(u, "element_area_plus", element):
			var r := int(p(e, "radius", 0))
			if r <= 0:
				continue
			if element == "wind":
				o["gale_radius"] = int(o.get("gale_radius", 1)) + r
			elif element == "thunder":
				pass                      # Arcing: splash radius, read at the detonation
			else:
				var step := int(p(e, "step", 1)) if element in BWTiles.AXIS else 1
				if step <= 0:
					continue
				var ring: Dictionary = o.get("ring", {})
				for h in BWHex.fringe(hexes, r):
					if not h in hexes and board.exists(h) and not ring.has(h):
						ring[h] = step
				o["ring"] = ring
	# D93 perk hooks: Static Field fuses last longer; Wildfire marks fresh fire.
	if element == "thunder" and has(u, "static_field"):
		o["fuse_plus"] = int(total(u, "static_field", "cycles"))
	if element == "fire" and cast and has(u, "wildfire"):
		o["wild"] = int(p(list(u, "wildfire")[0], "min", 2))
	if element in BWTiles.AXIS:
		for e in list(u, "tile_erupt", element):
			o["erupt"] = {
				"owner": u.id, "element": element, "left": int(p(e, "delay", 1)),
				"dmg_pct": int(p(e, "dmg_pct_per_point", 0)), "heal_pct": int(p(e, "heal_pct_per_point", 0)),
				"radius": int(p(e, "radius", 0)), "push": int(p(e, "push", 0)),
				"consume": int(p(e, "consume", 0)) == 1, "name": e.name,
			}
			break
	return o


## tile_potency_pct: multiplier for the per-point effect of `u`'s tiles.
static func potency(u: BWUnit, element: String) -> float:
	if u == null:
		return 1.0
	return 1.0 + total(u, "tile_potency_pct", "pct", element) / 100.0


## damage_taken_mod `tile_pct` (Fireproof, Grounded): multiplier on tile
## damage of `element` (burning, crossing, detonations, eruptions).
static func tile_taken(u: BWUnit, element: String) -> float:
	var m := 1.0
	for e in list(u, "damage_taken_mod"):
		if str(p(e, "source", "")) == element and float(p(e, "tile_pct", 0)) != 0.0:
			m *= 1.0 + float(p(e, "tile_pct", 0)) / 100.0
	return maxf(0.0, m)


# ----------------------------------------------------------------- perks (D93)

## The charge level of `on` at `hex`: an axis element's intensity (0-3); for
## the operators 1 when the hex holds their marker (ice: stasis or glaze).
static func level_at(tiles: BWTiles, hex: Vector2i, on: String) -> int:
	if on in BWTiles.AXIS:
		return tiles.intensity(hex, on)
	return 1 if tiles.carries(hex, on) else 0


## A by-level param: `l1`/`l2`/`l3` when given, else per_point × level.
static func by_level(e: Dictionary, level: int) -> float:
	if level <= 0:
		return 0.0
	var k := "l%d" % clampi(level, 1, 3)
	if e.params.has(k):
		return float(e.params[k])
	return float(p(e, "per_point", 0)) * level


## "Fire 2", "Water 3", "Ice" — the ground a perk term reads, for labels.
static func ground_label(on: String, level: int) -> String:
	return on.capitalize() if not on in BWTiles.AXIS else "%s %d" % [on.capitalize(), level]


# ----------------------------------------------------------------- range

## range_mod: basic range = range × mult + plus (Piercing, Longshot,
## Throwing, Ammo Belt). `ranged_only` limits a row to bows and pistols.
static func basic_range(u: BWUnit) -> int:
	var r := float(u.weapon().get("range", 1))
	for e in list(u, "range_mod"):
		if int(p(e, "ranged_only", 0)) == 1 and not u.weapon_class in ["bow", "pistols"]:
			continue
		r = r * float(p(e, "mult", 1)) + float(p(e, "plus", 0))
	return int(r)


# ----------------------------------------------------------------- forecast

static func _m(stage: String, label: String, value: float, extra: Dictionary = {}) -> Dictionary:
	var m := { "stage": stage, "label": label, "value": value }
	m.merge(extra)
	return m


## Every effect modifier on one blow, as forecast mods for BWFormulas
## ([{stage, label, value}]; stages: hit avoid crit crit_mult glance glance_x
## glance_red resist def_ignore dmg). `ctx`:
##   dist      hexes between the two footprints
##   basic     a basic weapon attack (range_mod's long-throw penalty)
##   base_range the weapon's unmodified range
##   moved     hexes the attacker moved this turn
##   height    attacker elevation − target elevation
##   charged   the target's hex holds charge
## `auras` is a Callable(unit, key) -> float for team auras (the battle's).
static func attack_mods(att: BWUnit, dfn: BWUnit, kind: String, element: String, ctx: Dictionary, auras: Callable) -> Array:
	var out: Array = []
	var dist := int(ctx.get("dist", 1))
	# attack_mod (Keen, Serrated, Sundering, Jousting, Conducting, Deadeye,
	# Fletcher's Eye, Dragoon's Descent)
	for e in list(att, "attack_mod"):
		if dist < int(p(e, "min_range", 0)):
			continue
		if float(p(e, "hit", 0)) != 0.0:
			out.append(_m("hit", e.name, float(p(e, "hit"))))
		if float(p(e, "hit_per_hex", 0)) != 0.0 and dist > 1:
			out.append(_m("hit", "%s (%d hexes between)" % [e.name, dist - 1], float(p(e, "hit_per_hex")) * (dist - 1)))
		if float(p(e, "crit", 0)) != 0.0:
			out.append(_m("crit", e.name, float(p(e, "crit"))))
		if float(p(e, "crit_mult", 0)) != 0.0:
			out.append(_m("crit_mult", e.name, float(p(e, "crit_mult"))))
		if float(p(e, "def_ignore_pct", 0)) != 0.0:
			out.append(_m("def_ignore", e.name, float(p(e, "def_ignore_pct")) / 100.0))
		if float(p(e, "dmg_pct", 0)) != 0.0:
			out.append(_m("dmg", e.name, 1.0 + float(p(e, "dmg_pct")) / 100.0))
		var per_move := float(p(e, "dmg_per_hex_moved_pct", 0))
		if per_move != 0.0 and int(ctx.get("moved", 0)) > 0:
			var cap := float(p(e, "max_pct", 1000))
			var pct := minf(cap, per_move * int(ctx.moved))
			out.append(_m("dmg", "%s (%d hexes moved)" % [e.name, ctx.moved], 1.0 + pct / 100.0))
		if float(p(e, "vs_charged_pct", 0)) != 0.0 and ctx.get("charged", false):
			out.append(_m("dmg", "%s (target on charge)" % e.name, 1.0 + float(p(e, "vs_charged_pct")) / 100.0))
		var per_h := float(p(e, "dmg_per_height_pct", 0))
		if per_h != 0.0 and int(ctx.get("height", 0)) > 0:
			out.append(_m("dmg", "%s (%d above)" % [e.name, ctx.height], 1.0 + per_h * int(ctx.height) / 100.0))
	# range_mod: hits past the weapon's own range (Throwing 75%)
	if ctx.get("basic", false) and dist > int(ctx.get("base_range", dist)):
		for e in list(att, "range_mod"):
			var dp := float(p(e, "dmg_pct", 100))
			if dp != 100.0 and not (int(p(e, "ranged_only", 0)) == 1 and not att.weapon_class in ["bow", "pistols"]):
				out.append(_m("dmg", "%s (beyond normal range)" % e.name, dp / 100.0))
	# element_damage_pct (Stormcaller's; Imbued with next_same)
	if element != "":
		for e in list(att, "element_damage_pct"):
			var same := int(p(e, "next_same", 0)) == 1
			if same:
				if str(att.fx.get("imbued", "")) != element:
					continue
			elif e.element != "" and e.element != element:
				continue
			out.append(_m("dmg", e.name, 1.0 + float(p(e, "pct", 0)) / 100.0))
	# aura_mod / own passives on the attacker: hit, crit, dmg_pct
	if auras.is_valid():
		for key in ["hit", "crit"]:
			for a in auras.call(att, key):
				out.append(_m(key, a.label, a.value))
		for a in auras.call(att, "dmg_pct"):
			out.append(_m("dmg", a.label, 1.0 + a.value / 100.0))
		# defender side: avoid, resist, glance (aura_mod / glance_mod)
		for a in auras.call(dfn, "avoid"):
			out.append(_m("avoid", a.label, a.value))
		for a in auras.call(dfn, "resist"):
			out.append(_m("resist", a.label, a.value))
		for a in auras.call(dfn, "glance:" + ("melee" if dist <= 1 else "ranged")):
			out.append(a)
	# damage_taken_mod on the defender (Fireproof, Windbreak, Hardened, Visor)
	for e in list(dfn, "damage_taken_mod"):
		var src := str(p(e, "source", ""))
		var applies := src == element and element != "" \
			or (src == "spell" and kind == BWFormulas.SPELL) \
			or (src == "weapon" and kind == BWFormulas.WEAPON) \
			or (src == "skill" and kind == BWFormulas.SKILL)
		if applies and float(p(e, "pct", 0)) != 0.0:
			out.append(_m("dmg", e.name, 1.0 + float(p(e, "pct")) / 100.0))
		if float(p(e, "crit_mult_minus", 0)) != 0.0:
			out.append(_m("crit_mult", e.name, -float(p(e, "crit_mult_minus"))))
	# guard (Guarding): the defender attacked last turn and braced
	if float(dfn.fx.get("guard", 0)) > 0.0:
		out.append(_m("dmg", str(dfn.fx.get("guard_name", "Guard")), 1.0 - float(dfn.fx.guard) / 100.0))
	return out


## glance_mod records that touch `dfn` from `holder` (itself, or an ally whose
## record reaches it), as forecast mods. `vs` = "melee" or "ranged".
static func glance_mods(holder: BWUnit, is_self: bool, vs: String, dist: int = 0) -> Array:
	var out: Array = []
	for e in list(holder, "glance_mod"):
		var r := int(p(e, "radius", 0))
		var allies := int(p(e, "allies", 0)) == 1
		if is_self and r >= 1 and allies:
			continue                          # Ring Guard is for the neighbours
		if not is_self and not (r >= 1 and allies and dist <= r):
			continue
		if str(p(e, "vs", "")) == "melee" and vs != "melee":
			continue
		if float(p(e, "chance_plus", 0)) != 0.0:
			out.append(_m("glance", e.name, float(p(e, "chance_plus"))))
		if float(p(e, "chance_mult", 1)) != 1.0:
			out.append(_m("glance_x", e.name, float(p(e, "chance_mult"))))
		if float(p(e, "reduction_mult", 1)) != 1.0:
			out.append(_m("glance_red", e.name, float(p(e, "reduction_mult")), { "cap": float(p(e, "cap", 100)) }))
	return out
