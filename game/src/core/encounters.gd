class_name BWEncounters
extends RefCounted
## D208-D212: special encounters. From fight 3 on (where the room choice
## starts), about a third of the offers replace the normal Hard room with one
## of four encounters, picked from the run seed. They are Hard rooms (Hard
## pay, the Hard tag) with their own squads, built at the squad's level when
## met (enemy level = squad level; base stats follow the fight's curve row,
## the Hard multiplier and the kind's own knob below):
##   horde     ten elementless melee grunts at a fraction of a normal enemy's HP
##   colossus  one elementless spear fighter, size 2 (7 hexes, like the
##             Giant), a big HP pool, reach 2, a line thrust, never displaced
##   blank     three: immune to elements, x2 damage from melee strikes
##   being     three, each a random element: immune to physical damage
## The damage classes (physical / elemental) are BWFormulas.damage_class.
## Pure rules, no nodes. The look is BWCharacter's (encounter looks).

const HORDE := "horde"
const COLOSSUS := "colossus"
const BLANK := "blank"
const BEING := "being"
const KINDS := [HORDE, COLOSSUS, BLANK, BEING]
const NAMES := { HORDE: "Horde", COLOSSUS: "Colossus", BLANK: "Blanks", BEING: "Elemental Beings" }
## The room card's counter hint.
const HINTS := {
	HORDE: "Ten weak foes: cut through them, mind the crowd",
	COLOSSUS: "One giant spear: it can't be moved, step out of its line",
	BLANK: "Immune to elements, ×2 from melee: use weapon basics up close",
	BEING: "Immune to physical: use element skills and the ground",
}
## The unit-level tag (BWUnit.encounter) per kind.
const UNIT_KIND := { HORDE: "grunt", COLOSSUS: "colossus", BLANK: "blank", BEING: "being" }

## D208: from this fight, a choice fight's Hard room is an encounter with
## this chance (seeded per run and fight).
const FROM_FIGHT := 3
const DEFAULT_RATE := 0.34
static var RATE := DEFAULT_RATE

## D212 tuning (tools/campaign_sim.gd ENC=1). Base-stat multiplier on top of
## the Hard build, and HP as a share of the unit's own D137 HP.
const HORDE_COUNT := 10
static var HORDE_MULT := 1.0
static var HORDE_HP := 0.45
static var COLOSSUS_MULT := 1.5
static var COLOSSUS_HP := 4.8
static var BLANK_MULT := 1.25
static var BLANK_HP := 1.2
static var BEING_MULT := 1.0
static var BEING_HP := 1.0
const CURVE_MIN := 0.9
const CURVE_MAX := 1.1
const GRUNT_WEAPONS := ["sword", "hatchet", "axe", "lance"]


## The encounter replacing fight n's Hard room ("" = a normal Hard room).
static func kind_for(run: BWRun, n: int) -> String:
	if n < FROM_FIGHT or not BWRooms.has_choice(n):
		return ""
	var r := RandomNumberGenerator.new()
	r.seed = hash("encounter|%d|%d" % [run.seed_value, n])
	if r.randf() >= RATE:
		return ""
	return str(KINDS[r.randi() % KINDS.size()])


## Fight n's encounter room on `map` (a Hard room).
static func room(n: int, kind: String, map: String) -> Dictionary:
	return { "kind": BWRooms.HARD, "map": map, "enemies": [], "fight": n, "encounter": kind }


## The squad for an encounter at fight n, scaled to the squad's level now.
static func build(run: BWRun, n: int, kind: String) -> Array:
	var b := BWRooms.enemy_build(n, BWRooms.HARD)
	# D212: the curve's big multipliers (fight 3's 1.7) make up for its stage
	# lag; an encounter is at the squad's own level, so only the curve's
	# shape near 1 carries over (clamped), times the Hard multiplier.
	b.mult = clampf(BWRun.enemy_curve(n).mult, CURVE_MIN, CURVE_MAX) * BWRooms.HARD_MULT
	var lvl := run.squad_level()
	var tier := run.tier_for(int(b.stage))
	var ranks: Array = BWRun.ENEMY_RANKS[tier]
	var erng := RandomNumberGenerator.new()
	erng.seed = hash("enc-build|%d|%d|%s" % [run.seed_value, n, kind])
	var out: Array = []
	match kind:
		HORDE:
			for i in HORDE_COUNT:
				var wm: String = GRUNT_WEAPONS[erng.randi() % GRUNT_WEAPONS.size()]
				var u := _unit(run, n, "grunt%d" % (i + 1), "Grunt %d" % (i + 1), wm, "", lvl, tier, ranks, b, HORDE_MULT, HORDE_HP, erng)
				u.encounter = "grunt"
				u.cosmetics = { "hair_style": "buzzed", "top": "tshirt", "bottom": "sweatpants", "clothing_shade": "mid", "voice_pitch": 0.9 }
				out.append(u)
		COLOSSUS:
			var c := _unit(run, n, "colossus", "The Colossus", "lance", "", lvl, tier, ranks, b, COLOSSUS_MULT, COLOSSUS_HP, erng)
			c.encounter = "colossus"
			c.size = 2
			c.cosmetics = { "hair_style": "short_mohawk", "top": "tank_top", "bottom": "tight_pants", "clothing_shade": "dark", "voice_pitch": 0.7 }
			out.append(c)
		BLANK:
			for i in BWRun.DEPLOY:
				var act := BWRosterGen.active_classes()      # D419: no benched class
				var wc: String = act[erng.randi() % act.size()]
				var u := _unit(run, n, "blank%d" % (i + 1), "Blank %d" % (i + 1), _model(wc, erng), "", lvl, tier, ranks, b, BLANK_MULT, BLANK_HP, erng)
				u.encounter = "blank"
				u.cosmetics = { "hair_style": "none", "top": "tshirt", "bottom": "tight_pants", "clothing_shade": "light", "voice_pitch": 1.0 }
				out.append(u)
		BEING:
			var els: Array = BWFormulas.ELEMENTS.duplicate()
			for i in BWRun.DEPLOY:
				var el: String = els.pop_at(erng.randi() % els.size())
				var act := BWRosterGen.active_classes()      # D419: no benched class
				var wc: String = act[erng.randi() % act.size()]
				var u := _unit(run, n, "being%d" % (i + 1), "%s Being" % el.capitalize(),
					_model(wc, erng), el, lvl, tier, ranks, b, BEING_MULT, BEING_HP, erng)
				u.encounter = "being"
				u.cosmetics = { "hair_style": "buzzed", "top": "tshirt", "bottom": "tight_pants", "clothing_shade": "light", "voice_pitch": 1.1 }
				out.append(u)
	return out


## A random model of weapon class `wc`.
static func _model(wc: String, erng: RandomNumberGenerator) -> String:
	var models: Array = BWData.table("equipment").filter(func(r): return str(r.slot) == "main_hand" and str(r.weight) == wc)
	return str(models[erng.randi() % models.size()].id) if not models.is_empty() else wc


## One encounter unit: the class profile's stats, levelled to `lvl`, scaled by
## the Hard build's multiplier x `mult`, its weapon at the stage's tier, ranks
## and picks the AI's way, HP fixed at `hp_share` of its own D137 HP.
static func _unit(run: BWRun, n: int, key: String, uname: String, model: String, element: String, lvl: int,
		tier: String, ranks: Array, b: Dictionary, mult: float, hp_share: float, erng: RandomNumberGenerator) -> BWUnit:
	var wc := str(BWData.row("equipment", model).get("weight", model))
	var row := { "id": "%s_f%d" % [key, n], "name": uname, "weapon_class": wc, "weapon_model": model,
		"element": element, "friendliness": "unfriendly" }
	var st := BWRosterGen.stats_for(wc if BWRosterGen.PROFILES.has(wc) else "sword", erng)
	for k in BWUnit.STATS.size():
		row[BWUnit.STATS[k]] = st[k]
	var u := BWUnit.from_roster(row)
	run.seed_unit(u)
	BWProgression.level_up(u, lvl - u.level)
	BWRun.scale_stats(u, float(b.mult) * mult)       # b.mult: see build() (no lag, so the curve is held near 1)
	var save := run.rng.state
	run.rng.seed = erng.randi()
	u.equipment["main_hand"] = run.make_item(model, tier)
	u.equipment["main_hand"].erase("imbue")         # D209: encounter weapons are plain
	u.equipment["main_hand"].erase("imbue_enchant")
	run.rng.state = save
	if element != "":
		u.affinity[element] = maxi(int(u.affinity.get(element, 0)), int(ranks[0]) * BWUnit.POINTS_PER_RANK)
	u.expertise[wc] = int(ranks[1]) * BWUnit.POINTS_PER_RANK
	BWPicks.auto_resolve(u)
	if not bool(b.perks):
		u.perks.clear()
	u.refresh_effects()
	u.fixed_hp = maxi(1, roundi(BWFormulas.hp_value(u.stat("con"), u.level) * hp_share))
	u.hp = u.max_hp()
	return u
