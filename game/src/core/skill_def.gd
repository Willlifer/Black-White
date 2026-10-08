class_name BWSkillDef
extends RefCounted
## One weapon skill: its data row and its rules, in one file under
## res://src/core/skill_defs/ (BWSkillRegistry loads the folder). BWBattle
## runs the shared order of an action (ELEMENTS §7.3: shape → direct hits
## against the pre-action ground → paint → one growth award → follow-up →
## riposte answers) and asks the def at each step. Every hook has a default,
## so a plain skill is just its data plus whatever makes it different.
##
## Data (`define(row, order)`): the row every caller reads as a Dictionary
## (BWSkills.get_skill / BWBattle.skills_for):
##   key, name, weapon (class), cd, targeting (shape: unit | adjacent_unit |
##   hex | leap | dir | self), range, desc, clip (the cutscene pose: a fists
##   clip key, else "strike" / "cast"), needs_element, power
##   optional: radius, steps, min_range, los, spell, hits, hit_pct, push,
##   slam_pct, follow_up [keys], follow_up_only, free (Quick Shot: ignores
##   `acted`), free_action (Riposte: spends nothing), basic (uses the basic
##   attack's forecast), aoe (aoe_radius_plus widens it: Cleaving, Channelling),
##   second_pick ("hex": the player picks one more hex after the target, D109)
## `order` is the menu / pool order inside the weapon class.
##
## Upgrades (the expertise pick "Improve"): `upgraded(u)` is true once the
## unit improved this skill. An Improve rider is one `if upgraded(u):` in
## whichever hook it changes. Numbers live in BWSkills (the tuning sheet) or
## as constants in the def's own file.
##
## Hooks receive the battle `b` and may use its skill toolkit (unit_at,
## foes_of, side, gap, behind, push_path, paint, skill_relocate, and the
## underscore helpers _foes_on, _on_board, _without, _rush, _heal,
## _add_status, _displace, _tile_hurt, _tile_dmg, _emit, _face, _reaches;
## D97: add_status, place_unit, set_zone, set_overwatch).
## Core rules: no nodes, every number through BWFormulas with a label, all
## randomness from b.rng.

var id := ""
var data := {}
var order := 1000


## Set the row (call from the def's _init).
func define(row: Dictionary, p_order: int = 1000) -> void:
	data = row
	data.make_read_only()           # shared by every caller, like the old const table
	id = str(row.get("key", ""))
	order = p_order


## Has `u` improved this skill (rank 2)?
func upgraded(u: BWUnit) -> bool:
	return u != null and u.skill_upgraded(id)


# ---------------------------------------------------------------- targeting

## Legal clicks for one element. The default covers every targeting kind;
## `target_ok` narrows it without rewriting the shape.
func targets(b: BWBattle, u: BWUnit, element: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rng_max := b.weapon_range(u) if data.get("basic", false) else int(data.get("range", 0))
	match str(data.get("targeting", "")):
		"self":
			out.append(u.pos)
		"unit":
			for f in b.foes_of(u):
				for h in f.footprint():
					if b._reaches(u.pos, h, rng_max) and target_ok(b, u, h, element):
						out.append(h)
		"adjacent_unit":
			for f in b.foes_of(u):
				for h in f.footprint():
					if b._reaches(u.pos, h, 1) and target_ok(b, u, h, element):
						out.append(h)
		"hex":
			var lo := int(data.get("min_range", 1))
			for h in b.board.area(u.pos, rng_max):
				var d := BWHex.distance(u.pos, h)
				if d < lo or not b.tiles.can_hold(h):
					continue
				if data.get("los", false) and d > 1 and not b.board.has_los(u.pos, h):
					continue
				if not target_ok(b, u, h, element):
					continue
				out.append(h)
		"leap":
			for h in b.board.cells():
				if h == u.pos or not b.can_stand(u, h):
					continue
				if (BWHex.distance(u.pos, h) <= rng_max or b.tiles.carries(h, element)) and target_ok(b, u, h, element):
					out.append(h)
		"dir":
			for n in b.board.neighbors(u.pos):
				var p := b._plan(u, data, element, n)
				if not p.hexes.is_empty() or p.dest != u.pos:
					out.append(n)
	return out


## Extra legality for one hex (Consume needs edible ground, Siphon a tile).
func target_ok(_b: BWBattle, _u: BWUnit, _h: Vector2i, _element: String) -> bool:
	return true


## D109 second pick. A row with "second_pick": "hex" asks the player for one
## more hex once the target is chosen (Transfer's destination, Grapple
## Throw's landing): these are the legal ones for `target`. The choice reaches
## `plan` as p.choice; BWBattle.NOWHERE (the AI, and any caller that passes
## none) means "choose automatically", so every def keeps its own default.
## [] = nothing to choose (the UI goes straight to the forecast).
func second_targets(_b: BWBattle, _u: BWUnit, _element: String, _target: Vector2i) -> Array[Vector2i]:
	return []


# ---------------------------------------------------------------- plan + forecast

## Fill the plan `p` (already holding hexes [], steps, victims [], element,
## dest, walk [], shove {}, notes [], shares {}): the shape, who is hit, and
## any per-skill keys later hooks read. Shares are per-victim damage cuts or
## boosts: p.shares[id] = [mult, label, tag?].
func plan(_b: BWBattle, _u: BWUnit, _element: String, _target: Vector2i, _p: Dictionary) -> void:
	pass


## A power that isn't the row's `power` (Consume eats points): a BWFormulas
## breakdown {value, ...} or {} for the row's own.
func power_formula(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary) -> Dictionary:
	return {}


## Per-skill forecast modifiers on victim `v` (labelled, for the hover
## breakdown) and ◆ notes. `strike` is which strike of a multi-strike skill.
func forecast_mods(_b: BWBattle, _u: BWUnit, _el: String, _v: BWUnit, _p: Dictionary, _strike: int,
		_mods: Array, _notes: Array) -> void:
	pass


# ---------------------------------------------------------------- resolve

## Before the hits: move the user (leaps, charges). Default: face the target.
func relocate(b: BWBattle, u: BWUnit, p: Dictionary, target_hex: Vector2i) -> void:
	if target_hex != u.pos:
		b._face(u, target_hex)


## Extra keys on the "skill" event (after hits / bounce / pierce).
func decorate(_e: Dictionary, _p: Dictionary) -> void:
	pass


## After every strike landed (and lay_on struck): knockbacks, staggers.
func after_hits(_b: BWBattle, _u: BWUnit, _p: Dictionary, _results: Array) -> void:
	pass


## The ground changes whatever the rolls were (§7.3 step 3). Returns the
## steps stripped (Siphon), else 0. Default: paint the shape.
func ground(b: BWBattle, u: BWUnit, el: String, _target_hex: Vector2i, p: Dictionary) -> int:
	if el != "" and not p.hexes.is_empty():
		b.paint(p.hexes, el, u, p.steps)
	return 0


## Riders that land after the ground changed (heals, statuses, pushes).
## Only called while the battle runs and the user stands.
func after_paint(_b: BWBattle, _u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary,
		_results: Array, _stripped: int) -> void:
	pass


## Turns of cooldown set after use (before skill_cd_minus).
func cooldown(_u: BWUnit) -> int:
	return int(data.get("cd", 0))


## Vault: the momentum flag survives this skill (it is what sets it).
func keeps_momentum() -> bool:
	return false


## A follow-up was just granted (Vault momentum, Striketwice's first cut).
func on_follow_up(_b: BWBattle, _u: BWUnit, _p: Dictionary) -> void:
	pass


# ---------------------------------------------------------------- D97 engine hooks

## Zone control (Set Spear): hexes this unit holds after the skill resolves.
## Enemy movement entering one stops there (it can't path through); the zone
## expires at the holder's next turn. [] = no zone.
func zone(_b: BWBattle, _u: BWUnit, _p: Dictionary, _target_hex: Vector2i) -> Array:
	return []


## An enemy just ended its move inside `holder`'s zone (set by this skill).
func on_zone_enter(_b: BWBattle, _holder: BWUnit, _mover: BWUnit) -> void:
	pass


## Ally-attacked trigger (Covering Fire): a radius > 0 sets an overwatch until
## the holder's next turn. The first enemy action that attacks an ally of the
## holder within it draws the holder's basic attack (if in range).
func overwatch(_b: BWBattle, _u: BWUnit, _p: Dictionary) -> int:
	return 0


## The overwatch fired on `attacker`. Return true if the def answered itself;
## false lets the battle make the default answer (one basic attack).
func on_overwatch(_b: BWBattle, _holder: BWUnit, _attacker: BWUnit) -> bool:
	return false


## Free-placement displacement (Grapple Throw): move `v` to a chosen free hex
## (in bounds, free, not jagged), no crossing damage. False if not valid.
func place(b: BWBattle, v: BWUnit, hex: Vector2i) -> bool:
	return b.place_unit(v, hex)


# ---------------------------------------------------------------- AI

## Does BWAI weigh this skill as an attack? Default: damaging, not a
## follow-up granter, not free, not self-targeted.
func ai_considers(row: Dictionary) -> bool:
	return not (row.has("follow_up") or row.get("free", false) or not BWSkills.is_damaging(str(row.key))
		or row.targeting == "self")


## Score of one preview: expected damage over everyone hit, +1000 per likely
## finishing blow, plus a conductive target's expected arc (D86).
func ai_score(b: BWBattle, _u: BWUnit, pv: Dictionary) -> float:
	var score := 0.0
	for vid in pv.forecasts:
		# a multi-strike skill (Flurry) forecasts one strike of `hits`
		var ev: float = pv.forecasts[vid].expected.value * int(pv.get("hits", 1))
		score += ev + (1000.0 if ev >= b._unit(vid).hp else 0.0)
		score += float(pv.forecasts[vid].get("arc_ev", 0.0))
	return score


## A free action the AI sets at the end of its turn (Riposte), if wanted.
func ai_free_wanted(_b: BWBattle, _u: BWUnit) -> bool:
	return false


## D437: a free action the AI opens its turn with (Hook: pull a foe in,
## then move and act as normal): {target, element} or {} to skip.
func ai_opener(_b: BWBattle, _u: BWUnit, _row: Dictionary) -> Dictionary:
	return {}


## D112: a support skill (no damage of its own) the AI may spend its action
## on: {target, element, score} or {} to skip. The score is in the attack
## scores' units (expected damage); BWAI adds a granted basic follow-up's
## value itself. Keep it modest: an attack in hand should usually win.
func ai_support(_b: BWBattle, _u: BWUnit, _row: Dictionary) -> Dictionary:
	return {}


# ---------------------------------------------------------------- D110 confirm

## A strike the skill makes through BWBattle.attack after it resolves
## (Vault), for the confirm box: {unit: BWUnit, forecast} or {}.
func strike_preview(_b: BWBattle, _u: BWUnit, _p: Dictionary) -> Dictionary:
	return {}
