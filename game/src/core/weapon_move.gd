class_name BWWeaponMove
## D359–D364: movement by weapon. Rules only (no nodes); the numbers are
## data (data/weapons.csv: move, jump, traits).
##
##   Move  — a unit's base move is its DRAWN weapon's `move` (ranged 4, sword /
##           daggers / fists 5, axe / lance 4), read when its turn starts and
##           kept for that turn: a mid-turn swap changes nothing until the
##           next turn (BWBattle sets fx.move_class at turn start). Outside a
##           turn (sheets, cards) it follows the weapon drawn now. Perks,
##           sets, statuses, terrain and Wander still add on top (D359).
##   Jump  — the most levels one step may rise (D360, D371). 2 by default;
##           the lance's `jump` is 4 (double). D375: a climb within the jump
##           costs the normal step (no +1 a level); dropping is unlimited.
##   Updraft — D376/D377: part of the wind perk Tailwind. Its holder gets +1
##           jump after every other modifier (a lance 5, a HighGrounder bow
##           5); a unit of the holder's team whose turn starts on one of the
##           holder's gale markers / wind fields gets +1 more for that turn
##           (read at turn start, fx.updraft, like the move-class lock). They
##           stack: +2 at most (one tile bonus, however many holders).
##   Passives — D372: a weapon class's pickable passives (weapons.csv
##           `passives`; the bow's HighGrounder) are offered in that class's
##           expertise picks next to Improve / Learn (BWPicks, "passive:<id>").
##           Taken, the id is stored in BWUnit.known_skills (saved as is); it
##           has no skill def, so it never enters a loadout and takes no
##           slot. It works while its class is drawn (the turn-start lock).
##           HighGrounder doubles the jump (bow: 4).
##   Rough — axe and daggers (trait rough_footed) pay 1 for mud, not 2. Only
##           the mud: water and every other cost stay (D361).
##   High ground — Daggerleap, Charge, Vault and Dragoon Dive from 1+ level
##           above the landing / first hex / target: +1 range; Daggerleap and
##           the Dive land on a ring 1 wider; Charge shoves 2 hexes (D362).

const HIGH_GROUNDER := "high_grounder"
const ROUGH_FOOTED := "rough_footed"
const HIGH_GROUNDER_MULT := 2          # D372: doubles the jump while a bow is drawn
const HIGH_GROUND_MIN := 1             # levels above the destination
const UPDRAFT := 1                     # D376: Tailwind's jump, and its tiles' (D377)
const UPDRAFT_KEY := "tailwind"        # the effect key that carries it
const TRAITS := {
	ROUGH_FOOTED: ["Rough-Footed", "mud costs 1 move, not 2"],
}
## D372: pickable weapon passives, [name, card words, pick-card text].
const PASSIVES := {
	HIGH_GROUNDER: ["HighGrounder", "jump 4 with a bow drawn",
		"Passive: takes no skill slot. With a bow drawn your jump doubles to 4, so one step may climb 4 levels."],
	# D427: the sword's (BWKit2: the step's rules, its prompt in the combat screen)
	"blade_dance": ["Blade Dance", "a free step after a sword skill lands",
		"Passive: takes no skill slot. With a sword drawn, after one of your sword skills lands you may take a free step of up to 2 tiles (pick the tile, or skip)."],
}


## The class whose move this unit has now: the turn-start lock in battle,
## else the drawn weapon.
static func move_class(u: BWUnit) -> String:
	return str(u.fx.get("move_class", u.weapon_class))


static func row(wc: String) -> Dictionary:
	return BWData.row("weapons", wc)


## A class's base move (4 when the row is missing: an obelisk, a test stub).
static func base_move(wc: String) -> int:
	var r := row(wc)
	return int(r.get("move", BWUnit.BASE_MOVE)) if not r.is_empty() and str(r.get("move", "")) != "" else BWUnit.BASE_MOVE


static func traits(wc: String) -> Array:
	return Array(BWData.list(str(row(wc).get("traits", ""))))


static func has_trait(u: BWUnit, t: String) -> bool:
	return t in traits(move_class(u))


## A class's own jump (weapons.csv `jump`; 2 when blank or the row is missing).
static func class_jump(wc: String) -> int:
	var r := row(wc)
	return maxi(1, int(r.get("jump", BWBoard.DEFAULT_JUMP)) if str(r.get("jump", "")) != "" else BWBoard.DEFAULT_JUMP)


## Max levels a step may rise for this unit (D360, D371, D372), Updraft
## added last (D376).
static func jump(u: BWUnit) -> int:
	var j := class_jump(move_class(u))
	if has_passive(u, HIGH_GROUNDER):
		j *= HIGH_GROUNDER_MULT
	return j + updraft(u)


## The jump before Updraft (what jump_source names).
static func base_jump(u: BWUnit) -> int:
	return jump(u) - updraft(u)


# ---------------------------------------------------------------- updraft (D376/D377)

## Does `u` hold Tailwind (the Updraft perk)?
static func has_updraft(u: BWUnit) -> bool:
	return u != null and BWEffects.has(u, UPDRAFT_KEY)


## [label, value] per Updraft term: the holder's own, then the turn-start
## tile's ("on Ana's gale"), stamped by BWBattle at turn start.
static func updraft_notes(u: BWUnit) -> Array:
	var out: Array = []
	if has_updraft(u):
		out.append(["Tailwind", UPDRAFT])
	var tile := str(u.fx.get("updraft", ""))
	if tile != "":
		out.append(["Tailwind, " + tile, UPDRAFT])
	return out


static func updraft(u: BWUnit) -> int:
	var n := 0
	for x in updraft_notes(u):
		n += int(x[1])
	return n


## BWBattle turn start: the tile half. "" when `u` starts off any holder's
## wind; else words for the breakdown ("on its gale", "on Ana's gale").
static func updraft_tile(b: BWBattle, u: BWUnit) -> String:
	var e := b.tiles.at(u.pos)
	if str(e.get("marker", "")) != "gale":
		return ""
	var o := b._unit(str(e.get("source", "")))
	if o == null or o.team != u.team or not has_updraft(o):
		return ""
	return "on its gale" if o == u else "on %s's gale" % o.name


## "Updraft +1 (Tailwind) +1 (Tailwind, on Ana's gale)", or "".
static func updraft_text(u: BWUnit) -> String:
	var n := updraft_notes(u)
	if n.is_empty():
		return ""
	var t := "Updraft"
	for x in n:
		t += " %+d (%s)" % [int(x[1]), str(x[0])]
	return t


## Where the jump comes from, for the hover ("Lance", "HighGrounder"); ""
## for the plain 2.
static func jump_source(u: BWUnit) -> String:
	if has_passive(u, HIGH_GROUNDER):
		return passive_name(HIGH_GROUNDER)
	return class_name_of(move_class(u)) if base_jump(u) > BWBoard.DEFAULT_JUMP else ""


# ---------------------------------------------------------------- passives (D372)

## A class's pickable passives (weapons.csv `passives`).
static func passives_of(wc: String) -> Array:
	return Array(BWData.list(str(row(wc).get("passives", "")))).filter(func(k): return PASSIVES.has(str(k)))


static func is_passive(key: String) -> bool:
	return PASSIVES.has(key)


## Has the unit picked passive `key` (whatever is drawn)?
static func owns(u: BWUnit, key: String) -> bool:
	return key in u.known_skills


## Owned AND its class is the one moving now (the turn-start lock).
static func has_passive(u: BWUnit, key: String) -> bool:
	return owns(u, key) and key in passives_of(move_class(u))


## The passives the unit owns, in PASSIVES order.
static func owned_passives(u: BWUnit) -> Array:
	return PASSIVES.keys().filter(func(k): return owns(u, str(k)))


static func passive_name(key: String) -> String:
	return str(PASSIVES.get(key, [key.capitalize()])[0])


static func passive_text(key: String) -> String:
	return str(PASSIVES.get(key, ["", "", ""])[2])


static func class_name_of(wc: String) -> String:
	return str(row(wc).get("name", wc.capitalize()))


static func ignores_mud(u: BWUnit) -> bool:
	return has_trait(u, ROUGH_FOOTED)


## "Move 5" for the unit cards' stat line (the jump and traits go on
## their own line, card_lines, so the stat line never wraps).
static func card_text(u: BWUnit) -> String:
	return "Move %d" % u.move_range()


## card_text with the breakdown on hover (BBCode [hint]): "Move 3" over
## "Move 5 (Daggers) -2 Leaden Chaps (cursed)".
static func card_bb(u: BWUnit) -> String:
	return "[hint=%s]%s[/hint]" % [BWFormulas.move_text(u).replace("[", "(").replace("]", ")").replace("'", "’"), card_text(u)]   # D377: a bare ' breaks the tag


## [name, words] per movement line on a unit card: the class's own jump
## when above 2 ("Jump 4", the lance), each trait, then each owned passive
## (shown whatever is drawn; D372).
static func card_lines(u: BWUnit) -> Array:
	var out: Array = []
	var wc := move_class(u)
	if class_jump(wc) > BWBoard.DEFAULT_JUMP:
		out.append(["Jump %d" % class_jump(wc), "climbs %d levels a step" % class_jump(wc)])
	for t in traits(wc):
		if TRAITS.has(t):
			out.append(TRAITS[t])
	for k in owned_passives(u):
		out.append([passive_name(str(k)), str(PASSIVES[k][1])])
	return out


## Item card / sheet line for a weapon class: "Move 4 · Jump 4", "Move 4 ·
## HighGrounder (pick): jump 4".
static func class_line(wc: String) -> String:
	var r := row(wc)
	if r.is_empty():
		return ""
	var bits: PackedStringArray = ["Move %d" % base_move(wc)]
	if class_jump(wc) > BWBoard.DEFAULT_JUMP:
		bits.append("Jump %d" % class_jump(wc))
	for t in traits(wc):
		if TRAITS.has(t):
			bits.append("%s: %s" % [TRAITS[t][0], TRAITS[t][1]])
	for k in passives_of(wc):
		bits.append("%s (pick): jump %d" % [passive_name(str(k)), class_jump(wc) * HIGH_GROUNDER_MULT])
	return " · ".join(bits)


# ---------------------------------------------------------------- high ground (D362)

## Is `u` standing at least HIGH_GROUND_MIN levels above hex `h`?
static func above(b: BWBattle, u: BWUnit, h: Vector2i) -> bool:
	return b.board.exists(h) and b.board.elevation(u.pos) - b.board.elevation(h) >= HIGH_GROUND_MIN


## The rising part of a walk: the biggest single-step climb along `path`.
static func max_rise(board: BWBoard, path: Array) -> int:
	var m := 0
	for i in range(1, path.size()):
		m = maxi(m, board.elevation(path[i]) - board.elevation(path[i - 1]))
	return m


## D360/D361: the move hover's words for walking to `h` (`r` = reachable):
## "Kira — 3 of 4 move · Climb 4 (HighGrounder) · mud at 1 (Rough-Footed)".
static func walk_hint(b: BWBattle, u: BWUnit, r: Dictionary, h: Vector2i) -> String:
	var path := BWBoard.path_to(r, h)
	var t := "%s — %d of %d move" % [u.name, int(r[h].get("cost", 0)), u.move_range()]
	var rise := max_rise(b.board, path)
	if rise > base_jump(u) and updraft(u) > 0:
		t += " · Climb %d · %s" % [rise, updraft_text(u)]          # D376/D377
	elif rise > BWBoard.DEFAULT_JUMP:
		t += " · Climb %d (%s)" % [rise, jump_source(u)]
	elif rise >= 2:
		t += " · Climb %d" % rise
	if ignores_mud(u):
		for i in range(1, path.size()):
			if b.board.terrain(path[i]) == BWBoard.MUDDY:
				t += " · mud at 1 (%s)" % TRAITS[ROUGH_FOOTED][0]
				break
	return t
