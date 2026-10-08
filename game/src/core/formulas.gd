class_name BWFormulas
## The combat maths from the brief, one function per number. Every function
## returns a "calc": { value, label, formula, values } so the pre-combat
## window can show the formula, the values used and the result on hover.
## The game never computes a combat number anywhere else.
##
## Readings of the brief that needed a call are logged in DECISIONS.md
## (D23-D27) and marked here by number.

const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "dark", "light"]
const OPPOSITE := {
	"fire": "water", "water": "fire",
	"light": "dark", "dark": "light",
	"thunder": "wind", "wind": "thunder",
}

const BASE_HIT := 80.0
const HP_BASE := 100
const HP_PER_CON := 2           # D34 (brief said 5)
const HP_PER_LEVEL := 15        # D137, D178: HP grows with level, both sides (was 10)
const BASE_GLANCE := 10.0
const BASE_AVOID := 5.0
const BASE_RESIST := 10.0
const GLANCE_MULT := 0.5
const CRIT_MULT := 1.5
const RESIST_MULT := 0.8
const MITIGATION := 0.75
const AFFINITY_DMG_PER_RANK := 0.05
const AFFINITY_RES_PER_RANK := 5.0
const OPPOSITE_RES_PER_RANK := 2.5
const MIN_HIT_CHANCE := 5.0
const MAX_HIT_CHANCE := 100.0

## D96 facing (the defender's last facing, BWUnit.facing). The attacker's
## hex relative to the way the defender faces: 0 = straight ahead, 1/5 the
## front flanks, 2/4 the rear flanks, 3 directly behind.
const FACING_REAR_HIT := 15.0
const FACING_REAR_FLANK_HIT := 5.0
const FACING_FRONT_FLANK_GLANCE := 5.0
const FACING_FRONT_GLANCE := 10.0

## Attack kinds. Basic weapon attacks use "weapon"; named weapon skills use
## "skill"; staff attacks and element spells use "spell" (D5).
const WEAPON := "weapon"
const SKILL := "skill"
const SPELL := "spell"


## D424 (author: "Ranged attacks damage reduced by 10% if an enemy is within
## 2 tiles. Does not apply to AOE-targeted spells."): a ranged blow (reach
## PRESSURE_MIN_RANGE+: a ranged class's basic, or a single-target skill with
## that range) made while any foe stands within PRESSURE_RADIUS of the
## attacker deals ×PRESSURE_MULT. Lance (reach 2) is melee; areas are exempt.
const PRESSURE_RADIUS := 2
const PRESSURE_MULT := 0.9
const PRESSURE_MIN_RANGE := 3
const PRESSURE_TAG := "Pressured"


## D424: is this blow ranged? `reach` = the weapon's range for a basic, the
## skill's range otherwise; `single` = it targets one unit or one hex (no
## area, line or self shape).
static func is_ranged(reach: int, single: bool) -> bool:
	return single and reach >= PRESSURE_MIN_RANGE


## D424: the forecast modifier (a ×0.9 dmg stage, a named line).
static func pressure_mod() -> Dictionary:
	return { "stage": "dmg", "value": PRESSURE_MULT, "tag": PRESSURE_TAG,
		"label": "Pressured (enemy within %d) −%d%%" % [PRESSURE_RADIUS, roundi((1.0 - PRESSURE_MULT) * 100)] }


static func calc(label: String, value: float, formula: String, values: String) -> Dictionary:
	return { "label": label, "value": value, "formula": formula, "values": values }


## FX hook (BWEffects.attack_mods + the battle's ground terms): a forecast
## takes an optional list of labelled modifiers, { stage, label, value }.
## Each one is written into the hovered number's formula and values, so the
## player sees "+ Deadeye (2 hexes between)" and "+10.0", never a bare total.
## Stages: hit / avoid / crit / glance / resist (percentage points),
## crit_mult (adds to ×1.5), glance_x (× glance chance), glance_red (× the
## glance reduction, held to `cap`%), crit_x (× crit chance: 0 = can't crit,
## D94 Blinded), def_ignore (fraction of DEF ignored), dmg (× damage after
## mitigation), miss (any = the hit chance is 0: D245 Acrobat). Stage "note"
## is ignored here (a ◆ line for the forecast box).
static func _pts(mods: Array, stage: String) -> Array:
	var s := 0.0
	var f := ""
	var v := ""
	for m in mods:
		if m.stage == stage:
			s += float(m.value)
			f += " + " + str(m.label)
			v += " %+.1f" % float(m.value)
	return [s, f, v]


static func _prod(mods: Array, stage: String) -> Array:
	var s := 1.0
	var f := ""
	var v := ""
	for m in mods:
		if m.stage == stage:
			s *= float(m.value)
			f += " × " + str(m.label)
			v += " × %.2f" % float(m.value)
	return [s, f, v]


## D137, D178: HP = 100 + 2 × CON + 15 × level. A unit with a fixed pool (the
## Giant, D138) shows that instead.
static func hp(u: BWUnit) -> Dictionary:
	if u.fixed_hp > 0:
		return calc("HP", u.fixed_hp, "fixed (%s)" % ("the Giant" if u.id == "boss" else "its own pool"), "%d" % u.fixed_hp)
	var con := u.stat("con")
	return calc("HP", hp_value(con, u.level), HP_TEXT,
		"%d + %d × %d + %d × %d" % [HP_BASE, HP_PER_CON, con, HP_PER_LEVEL, u.level])


const HP_TEXT := "100 + 2 × CON + 15 × level"


static func hp_value(con: int, level: int) -> int:
	return HP_BASE + HP_PER_CON * con + HP_PER_LEVEL * level


## Damage base before the defender is considered.
static func damage_base(att: BWUnit, kind: String, power: int, element: String = "") -> Dictionary:
	var wpn := att.weapon()
	var base: float
	var f: String
	var v: String
	match kind:
		SPELL:
			base = power + att.stat("wil")
			f = "spell power + WIL"
			v = "%d + %d" % [power, att.stat("wil")]
		SKILL:
			base = power + 0.5 * att.stat("str") + 0.5 * att.stat("dex")
			f = "skill power + 0.5 × STR + 0.5 × DEX"
			v = "%d + 0.5 × %d + 0.5 × %d" % [power, att.stat("str"), att.stat("dex")]
		_:
			if str(wpn.get("damage_type", "martial")) == "dexterous":
				base = power + att.stat("dex")
				f = "weapon damage + DEX"
				v = "%d + %d" % [power, att.stat("dex")]
			elif str(wpn.get("damage_type", "")) == "spell":
				base = power + att.stat("wil")
				f = "weapon damage + WIL"
				v = "%d + %d" % [power, att.stat("wil")]
			else:
				base = power + att.stat("str")
				f = "weapon damage + STR"
				v = "%d + %d" % [power, att.stat("str")]
	if element != "":
		var rank := att.affinity_rank(element)
		if rank > 0:
			var mult := 1.0 + AFFINITY_DMG_PER_RANK * rank
			f = "(%s) × (1 + 5%% × %s affinity rank)" % [f, element]
			v = "(%s) × %.2f" % [v, mult]
			base *= mult
	return calc("Damage base", base, f, v)


## Damage after the defender's mitigation, on a clean hit. Never below 1.
static func damage_taken(att: BWUnit, dfn: BWUnit, kind: String, power: int, element: String = "", mods: Array = []) -> Dictionary:
	var b := damage_base(att, kind, power, element)
	var mit: float
	var f: String
	var v: String
	# FX hook (attack_mod def_ignore_pct, Sundering): part of DEF is ignored.
	var ig_p := _pts(mods, "def_ignore")
	var ig := clampf(ig_p[0], 0.0, 1.0)
	var dfs := "DEF"
	var dfv := "%d" % dfn.stat("def")
	if ig > 0.0:
		dfs = "DEF × (1 − %s)" % str(ig_p[1]).trim_prefix(" + ")
		dfv = "%d × %.2f" % [dfn.stat("def"), 1.0 - ig]
	var d_eff := dfn.stat("def") * (1.0 - ig)
	match kind:
		SPELL:
			mit = MITIGATION * dfn.stat("res")
			f = "base − 0.75 × RES"
			v = "%.1f − 0.75 × %d" % [b.value, dfn.stat("res")]
		SKILL:
			mit = MITIGATION * (dfn.stat("res") + d_eff) / 2.0
			f = "base − 0.75 × (RES + %s) / 2" % dfs
			v = "%.1f − 0.75 × (%d + %s) / 2" % [b.value, dfn.stat("res"), dfv]
		_:
			mit = MITIGATION * d_eff
			f = "base − 0.75 × %s" % dfs
			v = "%.1f − 0.75 × %s" % [b.value, dfv]
	var dmg := maxf(1.0, roundf(b.value - mit))
	# FX hook (every "dmg" mod: element_damage_pct, attack_mod, aura dmg_pct,
	# damage_taken_mod, guard, multi_hit share, ground conduction).
	var dm := _prod(mods, "dmg")
	if dm[1] != "":
		dmg = maxf(1.0, roundf(dmg * dm[0]))
		f = "(%s)%s" % [f, dm[1]]
		v = "(%s)%s" % [v, dm[2]]
	return calc("Damage", dmg, f + "  (min 1)", v)


## D23: weapon and skill attacks add expertise; spells add affinity.
static func hit_basis(att: BWUnit, kind: String, element: String = "") -> Dictionary:
	var dex := att.stat("dex")
	if kind == SPELL and element != "":
		var r := att.affinity_rank(element)
		return calc("Hit basis", BASE_HIT + dex + 5 * r,
			"80 + DEX + 5 × %s affinity rank" % element, "80 + %d + 5 × %d" % [dex, r])
	var e := att.expertise_rank(att.weapon_class)
	return calc("Hit basis", BASE_HIT + dex + 5 * e,
		"80 + DEX + 5 × %s expertise (E=0…A=4)" % att.weapon_class, "80 + %d + 5 × %d" % [dex, e])


static func avoid(dfn: BWUnit, mods: Array = []) -> Dictionary:
	var dex := dfn.stat("dex")
	var a := _pts(mods, "avoid")          # FX hook: aura_mod avoid (Supple, Heads Up)
	return calc("Avoid", BASE_AVOID + 0.1 * dex + a[0], "5 + 0.1 × target DEX" + a[1], "5 + 0.1 × %d%s" % [dex, a[2]])


static func hit_chance(att: BWUnit, dfn: BWUnit, kind: String, element: String = "", bonus: float = 0.0, mods: Array = []) -> Dictionary:
	var b := hit_basis(att, kind, element)
	var a := avoid(dfn, mods)
	var h := _pts(mods, "hit")            # FX hook: Deadeye, attack_mod hit, ground light/dark
	var v := clampf(b.value - a.value + bonus + h[0], MIN_HIT_CHANCE, MAX_HIT_CHANCE)
	var f := "hit basis − avoid"
	var vals := "%.1f − %.1f" % [b.value, a.value]
	if bonus != 0.0:
		f += " + modifiers"
		vals += " %+.1f" % bonus
	f += h[1]
	vals += h[2]
	var miss := _pts(mods, "miss")        # D245 Acrobat: this attack misses outright
	if miss[0] > 0.0:
		return calc("Hit", 0.0, f + "  → 0" + miss[1], vals + "  → 0")
	return calc("Hit", v, f + "  (5–100)", vals)


static func glance_chance(dfn: BWUnit, mods: Array = []) -> Dictionary:
	var d := dfn.stat("def")
	var g := _pts(mods, "glance")         # FX hook: glance_mod chance_plus / chance_mult
	var x := _prod(mods, "glance_x")
	var f: String = "10 + target DEF" + g[1]
	var v: String = "10 + %d%s" % [d, g[2]]
	if x[1] != "":
		f = "(%s)%s" % [f, x[1]]
		v = "(%s)%s" % [v, x[2]]
	var gm := glance_mult(mods)
	if gm[1] != "":
		f += "  [a glance deals %s]" % gm[1]
		v += "  [%.0f%%]" % (gm[0] * 100.0)
	return calc("Glance", clampf((BASE_GLANCE + d + g[0]) * x[0], 0.0, 100.0), f, v)   # D397: Unsteady can take it to 0, never below


## Share of damage a glance lets through: 50%, or less with glance_red mods
## (Woven Rings: the reduction doubles, held to its cap). [mult, text].
static func glance_mult(mods: Array) -> Array:
	var red := 1.0 - GLANCE_MULT
	var txt := ""
	for m in mods:
		if m.stage == "glance_red":
			red = minf(red * float(m.value), float(m.get("cap", 100.0)) / 100.0)
			txt += " × %s" % m.label
	var mult := clampf(1.0 - red, 0.0, 1.0)
	return [mult, "" if txt == "" else "50%% reduction%s → %.0f%% damage" % [txt, mult * 100.0]]


## D198 Advantage (Second Opinion, Stubborn): the resist is rolled twice and
## the side holding it keeps the better roll. Mods of stage "resist_adv":
## +1 for the attacker, -1 for the defender (both cancel). Returns
## [sign, effective chance, label text, unit ids].
static func resist_advantage(mods: Array, base: float) -> Array:
	var s := 0
	var ids: Array = []
	var txt := ""
	for m in mods:
		if m.stage == "resist_adv":
			s += signi(int(m.value))
			ids.append(str(m.get("who", "")))
			txt += " + " + str(m.label)
	var r := clampf(base / 100.0, 0.0, 1.0)
	if s > 0:
		return [1, 100.0 * r * r, txt, ids]
	if s < 0:
		return [-1, 100.0 * (1.0 - (1.0 - r) * (1.0 - r)), txt, ids]
	return [0, base, txt, ids]


## Crit multiplier: ×1.5 plus crit_mult mods (Serrated +0.5, Visor −0.25).
static func crit_mult(mods: Array) -> Array:
	var c := _pts(mods, "crit_mult")
	return [maxf(1.0, CRIT_MULT + c[0]), c[1], c[2]]


static func crit_chance(att: BWUnit, bonus: float = 0.0, mods: Array = []) -> Dictionary:
	var d := att.stat("dex")
	var c := _pts(mods, "crit")           # FX hook: Keen, Flair, Arena Born, Fletcher's Eye
	var f: String = "0.1 × DEX + modifiers" + c[1]
	var v: String = "0.1 × %d %+.1f%s" % [d, bonus, c[2]]
	var x := _prod(mods, "crit_x")        # D94: Blinded can't crit
	if x[1] != "":
		f = "(%s)%s" % [f, x[1]]
		v = "(%s)%s" % [v, x[2]]
	var cm := crit_mult(mods)
	if cm[1] != "":
		f += "  [a crit deals ×1.5%s]" % cm[1]
		v += "  [×1.5%s = ×%.2f]" % [cm[2], cm[0]]
	return calc("Crit", clampf((0.1 * d + bonus + c[0]) * x[0], 0.0, 100.0), f, v)


## D96: the facing term for an attack from `rel` (0..5, see FACING_*), as
## one labelled forecast mod, or {} when facing is unknown.
static func facing_mod(rel: int) -> Dictionary:
	match rel:
		3: return { "stage": "hit", "value": FACING_REAR_HIT, "label": "Rear attack +%d hit" % FACING_REAR_HIT, "tag": "Rear" }
		2, 4: return { "stage": "hit", "value": FACING_REAR_FLANK_HIT, "label": "Rear flank +%d hit" % FACING_REAR_FLANK_HIT }
		1, 5: return { "stage": "glance", "value": FACING_FRONT_FLANK_GLANCE, "label": "Front flank +%d glance" % FACING_FRONT_FLANK_GLANCE }
		0: return { "stage": "glance", "value": FACING_FRONT_GLANCE, "label": "Facing the blow +%d glance" % FACING_FRONT_GLANCE }
	return {}


## Affinity-driven resistance to one element, in percentage points (D24).
static func elemental_resist(dfn: BWUnit, element: String) -> float:
	if element == "":
		return 0.0
	var pts := AFFINITY_RES_PER_RANK * dfn.affinity_rank(element)
	var opp: String = OPPOSITE.get(element, "")
	if opp != "":
		pts += OPPOSITE_RES_PER_RANK * dfn.affinity_rank(opp)
	if element != "ice":
		pts += OPPOSITE_RES_PER_RANK * dfn.affinity_rank("ice")    # ice -> all
	return pts


## Only magic rolls resist: spells, and skills carrying an element (D25).
static func is_magic(kind: String, element: String) -> bool:
	return kind == SPELL or (kind == SKILL and element != "")


static func resist_chance(dfn: BWUnit, element: String, mods: Array = []) -> Dictionary:
	var r := dfn.stat("res")
	var e := elemental_resist(dfn, element)
	var m := _pts(mods, "resist")         # FX hook: aura_mod resist (Mana Veil)
	return calc("Resist", minf(100.0, BASE_RESIST + r + e + m[0]), "10 + target RES + affinity resistance" + m[1],
		"10 + %d + %.1f%s" % [r, e, m[2]])


## D209 (author's ruling): every blow and every point of ground damage is
## PHYSICAL or ELEMENTAL, decided here and nowhere else.
##   PHYSICAL   weapon basic attacks, even with an imbued weapon; weapon skills
##              cast without an element; slams (a body hitting rock or a unit)
##   ELEMENTAL  any skill cast with an element, staff spells (basic or skill),
##              tile damage (fire, dark, shroud, eruptions), detonations
##              and chain arcs
##   ""         neither: obelisk pulses, thorns, Death Knell, Covering shares
## `action`: { source: "basic" | "skill" | "tile" | "detonation" | "chain" |
## "slam" | other, kind: WEAPON | SKILL | SPELL, element }.
const PHYSICAL := "physical"
const ELEMENTAL := "elemental"
const BLANK_MELEE_MULT := 2.0


static func damage_class(action: Dictionary) -> String:
	var src := str(action.get("source", "basic"))
	match src:
		"tile", "detonation", "chain":
			return ELEMENTAL
		"slam":
			return PHYSICAL
		"basic", "skill":
			if str(action.get("kind", "")) == SPELL:
				return ELEMENTAL                     # staff spells
			if src == "basic":
				return PHYSICAL                      # even imbued
			return ELEMENTAL if str(action.get("element", "")) != "" else PHYSICAL
	return ""


## D209: what a special encounter's body does to one blow of class `cls`
## (`melee`: struck from melee reach): a forecast mod, or {}.
##   Blank   elemental: immune; physical from melee: x2
##   Being   physical: immune
static func encounter_mod(dfn: BWUnit, cls: String, melee: bool) -> Dictionary:
	match dfn.encounter:
		"blank":
			if cls == ELEMENTAL:
				return { "stage": "immune", "value": 0.0, "label": "Immune: elemental", "tag": "Immune" }
			if cls == PHYSICAL and melee:
				return { "stage": "dmg", "value": BLANK_MELEE_MULT, "label": "×2: melee vs Blank", "tag": "×2 melee" }
		"being":
			if cls == PHYSICAL:
				return { "stage": "immune", "value": 0.0, "label": "Immune: physical", "tag": "Immune" }
	return {}


## D209: does `dfn` take nothing from damage of class `cls`?
static func immune_to(dfn: BWUnit, cls: String) -> bool:
	return str(encounter_mod(dfn, cls, false).get("stage", "")) == "immune"


## D209: a Blank strips the element riders off a basic attack (an imbued
## weapon still cuts it, but paints, statuses and element bonuses don't land).
static func strips_element(dfn: BWUnit) -> bool:
	return dfn != null and dfn.encounter == "blank"


## Everything the pre-combat window shows, plus the expected damage.
static func forecast(att: BWUnit, dfn: BWUnit, kind: String, power: int, element: String = "", hit_bonus: float = 0.0, crit_bonus: float = 0.0, dmg_mult: float = 1.0, mods: Array = []) -> Dictionary:
	var magic := is_magic(kind, element)
	if dmg_mult != 1.0:
		mods = mods + [{ "stage": "dmg", "label": "ground modifier", "value": dmg_mult }]
	if dfn.braced_against(element):              # D130: Wander's brace, this battle
		mods = mods + [{ "stage": "dmg", "value": BWUnit.BRACE_TAKEN, "tag": "Braced",
			"label": "Braced against %s: -%d%%" % [element, roundi((1.0 - BWUnit.BRACE_TAKEN) * 100)] }]
	var out := {
		"kind": kind, "element": element, "magic": magic,
		"hit": hit_chance(att, dfn, kind, element, hit_bonus, mods),
		"avoid": avoid(dfn, mods),
		"glance": glance_chance(dfn, mods),
		"crit": crit_chance(att, crit_bonus, mods),
		"damage": damage_taken(att, dfn, kind, power, element, mods),
		"crit_mult": float(crit_mult(mods)[0]),        # read by resolve()
		"glance_mult": float(glance_mult(mods)[0]),
		"mods": mods,
	}
	if magic:
		out["resist"] = resist_chance(dfn, element, mods)
		var adv := resist_advantage(mods, out.resist.value)
		if not (adv[3] as Array).is_empty():
			out["adv_units"] = adv[3]                    # spent on the roll (BWEnchant.roll_blow)
		if int(adv[0]) != 0:
			out["resist_adv"] = int(adv[0])
			out["resist_base"] = float(out.resist.value)
			out.resist = calc("Resist", adv[1], str(out.resist.formula) + "  [advantage" + str(adv[2]) + "]",
				"%s  [%.0f%% rolled twice → %.0f%%]" % [out.resist.values, out.resist.value, adv[1]])
	# D201 Gambler's: hits that don't crit deal a share (glances and clean hits)
	var nx := _prod(mods, "nocrit_x")
	out["nocrit_mult"] = float(nx[0])
	if nx[1] != "":
		out.crit = calc("Crit", out.crit.value, str(out.crit.formula) + "  [other hits%s]" % nx[1], str(out.crit.values) + "  [×%.2f]" % nx[0])
	var p_hit: float = out.hit.value / 100.0
	var p_gl: float = out.glance.value / 100.0
	var p_cr: float = out.crit.value / 100.0
	var p_rs: float = out.resist.value / 100.0 if magic else 0.0
	var d: float = out.damage.value
	# D26: on a hit, glance is rolled first; only a clean (non-glancing) hit can crit.
	var nc: float = out.nocrit_mult
	var per_hit: float = p_gl * d * out.glance_mult * nc + (1.0 - p_gl) * (p_cr * d * out.crit_mult + (1.0 - p_cr) * d * nc)
	per_hit *= (1.0 - p_rs) + p_rs * RESIST_MULT
	out["expected"] = calc("Expected damage", per_hit * p_hit,
		"hit × (glance/crit/clean mix) × resist mix", "%.0f%% hit, %.1f per hit" % [out.hit.value, per_hit])
	for m in mods:                                   # D209: an immune body takes nothing from this blow
		if str(m.stage) == "immune":
			out["immune"] = str(m.label)
			out.damage = calc("Damage", 0, str(m.label), "0")
			out.expected = calc("Expected damage", 0.0, str(m.label), "0")
			out["notes"] = [str(m.label)]
			break
	return out


## Riposte (ELEMENTS §7.2, V8 RIPOSTE_MULT): a guarded target takes half of
## whatever lands. Rewrites a forecast in place, breakdown included.
const RIPOSTE_MULT := 0.5

static func guard(fc: Dictionary) -> Dictionary:
	var dm: Dictionary = fc.damage
	var before: float = dm.value
	fc.damage = calc("Damage", maxf(1.0, roundf(before * RIPOSTE_MULT)),
		"(%s) × riposte guard" % dm.formula, "(%s) × %.1f" % [dm.values, RIPOSTE_MULT])
	var ex: Dictionary = fc.expected
	fc.expected = calc(ex.label, ex.value * fc.damage.value / before,
		ex.formula + " × riposte guard", ex.values)
	fc["guarded"] = true
	return fc


## Consume's power (ELEMENTS §7.2): skill 14 + 2 per intensity point eaten.
static func consume_power(base: int, per_point: int, points: int, element: String) -> Dictionary:
	return calc("Skill power", base + per_point * points, "%d + %d × points eaten" % [base, per_point],
		"%d + %d × %d (%s)" % [base, per_point, points, element])


## Roll the forecast. Order (brief + D26): hit → glance → crit (clean hits
## only) → resist (magic only). Avoid deals 0 but secondary effects still land;
## resist deals 80% and blocks secondary effects.
static func resolve(fc: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var r := { "hit": false, "glance": false, "crit": false, "resisted": false,
		"damage": 0, "secondary": true, "rolls": {} }
	if fc.has("immune"):                           # D209: nothing lands, nothing rides along
		r.secondary = false
		r["immune"] = true
		return r
	var roll := rng.randf() * 100.0
	r.rolls["hit"] = roll
	if roll >= fc.hit.value:
		return r                      # avoided: secondary effects still apply
	r.hit = true
	var dmg: float = fc.damage.value
	roll = rng.randf() * 100.0
	r.rolls["glance"] = roll
	if roll < fc.glance.value:
		r.glance = true
		dmg *= float(fc.get("glance_mult", GLANCE_MULT))   # FX hook: Woven Rings
	else:
		roll = rng.randf() * 100.0
		r.rolls["crit"] = roll
		if roll < fc.crit.value:
			r.crit = true
			dmg *= float(fc.get("crit_mult", CRIT_MULT))   # FX hook: Serrated, Visor
	if not r.crit:
		dmg *= float(fc.get("nocrit_mult", 1.0))           # D201 Gambler's
	if fc.magic:
		roll = rng.randf() * 100.0
		r.rolls["resist"] = roll
		var adv := int(fc.get("resist_adv", 0))
		if adv != 0:                                      # D198 Advantage: a second roll, the better kept
			var roll2 := rng.randf() * 100.0
			r.rolls["resist2"] = roll2
			roll = maxf(roll, roll2) if adv > 0 else minf(roll, roll2)
		if roll < float(fc.get("resist_base", fc.resist.value)):
			r.resisted = true
			r.secondary = false
			dmg *= RESIST_MULT
	r.damage = maxi(1, roundi(dmg))
	return r


## Read-only calcs for the derived numbers BWUnit computes (move_range(),
## speed()), so the pre-battle sheet can show their formulas on hover.
## D93: turn-start move perks (Coal Engine, Sunpath, Ice Legs, Tailwind,
## Slipstream), after-action move (Bolt Step, Tailwind) and the move
## statuses are listed by name from BWUnit.move_notes().
## D359: the base is the class drawn at turn start ("Move 5 (Daggers) +1
## Tailwind"); D360/D371: the jump after it ("· Climb 2", "· Climb 4 (Lance)").
static func move(u: BWUnit) -> Dictionary:
	var wc := BWWeaponMove.move_class(u)
	var base := BWWeaponMove.base_move(wc)
	var fx := u.move_range() - base
	var f := "%s move" % BWWeaponMove.class_name_of(wc)
	var v := "%d" % base
	for n in u.move_notes():
		f += " + " + str(n[0])
		v += " %+d" % int(n[1])
		fx -= int(n[1])
	if fx != 0:
		f += " + passives"
		v += " %+d" % fx
	var c := calc("Move", u.move_range(), f, v)
	c["text"] = move_text(u)
	return c


## D359/D360/D371: the one-line move breakdown: "Move 5 (Daggers) +1 Tailwind ·
## Climb 2", "Move 4 (Lance) · Climb 4 (Lance)", "Climb 4 (HighGrounder)". Statuses and perks by name, unnamed passives summed.
static func move_text(u: BWUnit) -> String:
	var wc := BWWeaponMove.move_class(u)
	var base := BWWeaponMove.base_move(wc)
	var t := "Move %d (%s)" % [base, BWWeaponMove.class_name_of(wc)]
	var rest := u.move_range() - base
	for n in u.move_notes():
		t += " %+d %s" % [int(n[1]), str(n[0])]
		rest -= int(n[1])
	if rest != 0:
		t += " %+d passives" % rest
	var j := BWWeaponMove.jump(u)                # D371: always named; the source when above 2
	var src := BWWeaponMove.jump_source(u)
	t += " · Climb %d" % j + (" (%s)" % src if src != "" else "")
	var up := BWWeaponMove.updraft_text(u)       # D376/D377: "Updraft +1 (Tailwind)"
	if up != "":
		t += " · " + up
	if BWWeaponMove.ignores_mud(u):
		t += " · no mud penalty"
	return t


static func speed(u: BWUnit) -> Dictionary:
	var spd := u.stat("spd")
	var wm := int(u.weapon().get("speed_mod", 0))
	return calc("Speed", u.speed(), "SPD + weapon speed", "%d %+d" % [spd, wm])
