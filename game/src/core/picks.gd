class_name BWPicks
## Picks (D90, D91): what a unit chooses as it grows. Pure rules, no nodes.
##
## Element perks (data/perks.csv, four per element, D281) and keystones
## (data/keystones.csv, three per element, BWKeystones) climb one ladder per
## element (D277, ELEMENTS-v3 §9; it replaced "rank 3 grants all"):
##   rank 1: perk pick · rank 2: perk pick · rank 3: KEYSTONE (1 of 2 drawn
##   from the element's 3) · rank 4: third perk · rank 5: fourth perk ·
##   rank 6: second keystone (the 2 left).
## A unit holds at most BWKeystones.MAX_PER_UNIT (2) keystones across all
## elements. Units start at rank 1 in their own element; that first perk is
## drawn at random (D233, BWRun.auto_first_perk). Perks are one more effect
## source in BWEffects.collect, next to equipment and abilities.
##
## Weapon-skill picks: every expertise letter gained (E→D, D→C, C→B, B→A) in
## a weapon class owes one pick: improve a skill the unit knows for that
## class (BWUnit.skill_ranks = 2, BWSkillDef.upgraded) or learn a new one
## from the class's pool (BWSkillRegistry.pool). A pick with nothing left to
## choose is spent empty.
##
## No banking (author): a pick is made as soon as it is owed. The state says
## what is owed (ranks against picks already made), so nothing can be carried
## over: the screens open the picker at once, and AI / enemy units resolve
## theirs with auto_resolve(), deterministically (no rng of their own).
##
## D174 fewer, better choices: a pick OFFERS only OFFER (2) options, drawn at
## random from what the unit could take (perks of the element it doesn't own;
## the class's improve / learn pool). The draw is a hash of the unit's
## pick_seed (BWRun.seed_unit: the run seed + the unit id), the request and
## how many picks of that kind it has made, so it is reproducible, survives a
## save, and the same request shows the same two cards every time it opens.
## apply() takes only an offered option; the AI takes the first of the two.
##
## A request is { kind: "perk", element }, { kind: "keystone", element }
## (D277) or { kind: "skill", weapon }.
## A choice id is a perk id, or "improve:<skill>" / "learn:<skill>".

const TABLE := "perks"
## D277: perks the ladder allows by affinity rank (index = rank, 6+ = the last).
const PERK_LADDER := [0, 1, 2, 2, 3, 4, 4]
## D277: the affinity rank of the first keystone pick (the second is at
## BWKeystones.RANKS[1] = 6). Kept under its old name for the callers.
const ALL_RANK := 3
const KEYSTONE_RANK := 3
const OFFER := 2                    # D174: options a pick shows


# ---------------------------------------------------------------- perks

## The element's perks, CSV order.
static func perks_of(element: String) -> Array:
	return BWData.table(TABLE).filter(func(r): return str(r.element) == element)


static func perk(id: String) -> Dictionary:
	return BWData.row(TABLE, id)


## Perks of `element` the unit has, in the order taken.
static func owned(u: BWUnit, element: String) -> Array:
	return u.perks.filter(func(id): return str(perk(id).get("element", "")) == element)


## How many of the element's perks the unit's rank entitles it to (D277 ladder).
static func allowance(u: BWUnit, element: String) -> int:
	var n := perks_of(element).size()
	var r := mini(u.affinity_rank(element), PERK_LADDER.size() - 1)
	return mini(int(PERK_LADDER[r]) + int(u.bonus_perks.get(element, 0)), n)   # D128: + Specialize's free picks


# ---------------------------------------------------------------- keystones (D277)

## Keystones of `element` the unit holds, in the order taken.
static func keystones_owned(u: BWUnit, element: String) -> Array:
	return u.keystones.filter(func(id): return BWKeystones.element_of(str(id)) == element)


## How many of the element's keystones its rank entitles the unit to (rank 3: 1,
## rank 6: 2), before the 2-per-unit cap.
static func keystone_allowance(u: BWUnit, element: String) -> int:
	var r := u.affinity_rank(element)
	var n := 0
	for k in BWKeystones.RANKS:
		if r >= int(k):
			n += 1
	return mini(n, BWKeystones.of_element(element).size())


## Keystone picks owed in `element` right now (rank minus held, within the
## unit-wide cap of BWKeystones.MAX_PER_UNIT).
static func keystones_owed(u: BWUnit, element: String) -> int:
	var owed := keystone_allowance(u, element) - keystones_owned(u, element).size()
	var room := BWKeystones.cap(u) - u.keystones.size()
	return maxi(0, mini(owed, room))


# ---------------------------------------------------------------- skills

## Can skill `key` be improved? Only a def whose row carries a `plus` (the
## Improve rider's text) has one (author, via Lane 3).
static func improvable(key: String) -> bool:
	return str(BWSkills.get_skill(key).get("plus", "")) != ""


## Expertise picks owed in a weapon class (letters gained minus picks made).
static func skill_picks_owed(u: BWUnit, wc: String) -> int:
	return maxi(0, u.expertise_rank(wc) + int(u.bonus_skills.get(wc, 0)) - int(u.skill_picks.get(wc, 0)))   # D128: + free picks


## Choice ids for one skill pick: improve each known skill not yet improved
## (loadout first, then the rest it knows), then learn each pool skill it
## doesn't know yet (pool order).
static func skill_choices(u: BWUnit, wc: String) -> Array:
	var out: Array = []
	var known := u.known(wc)
	var order: Array = u.loadout(wc) + known.filter(func(k): return not k in u.loadout(wc))
	for k in order:
		if improvable(k) and not u.skill_upgraded(k):
			out.append("improve:" + k)
	for k in BWSkillRegistry.pool(wc):
		if not k in known:
			out.append("learn:" + k)
	return out


# ---------------------------------------------------------------- requests

## Everything owed right now that needs a choice, in the order to ask:
## perks by element order, then skill picks by weapon class order.
static func pending(u: BWUnit) -> Array:
	var out: Array = []
	for el in BWFormulas.ELEMENTS:
		for i in maxi(0, allowance(u, el) - owned(u, el).size()):
			out.append({ "kind": "perk", "element": el })
		for i in keystones_owed(u, el):               # D277: rank 3 / rank 6
			out.append({ "kind": "keystone", "element": el })
	for wc in _classes(u):
		for i in skill_picks_owed(u, wc):
			out.append({ "kind": "skill", "weapon": wc })
	return out


## The next pick the unit owes, or {} (after settle()).
static func next_request(u: BWUnit) -> Dictionary:
	settle(u)
	var p := pending(u)
	return p[0] if not p.is_empty() else {}


## Grant what needs no choice: a skill pick with nothing to choose is spent.
## (D277: rank 3 no longer grants the element's perks; it owes a keystone.)
## Returns the pick records made.
static func settle(u: BWUnit) -> Array:
	var made: Array = []
	for wc in _classes(u):
		while skill_picks_owed(u, wc) > 0 and skill_choices(u, wc).is_empty():
			u.skill_picks[wc] = int(u.skill_picks.get(wc, 0)) + 1
			made.append(_record("skill", wc, "", true))
	return made


## D174: the cards a request shows: OFFER options drawn from the ones the
## unit can take (all_options, not owned), shown in data order. Stable: the
## same unit, request and pick count give the same cards.
## [{ id, name, text, element, owned (false), kind }]
static func options(u: BWUnit, req: Dictionary) -> Array:
	var free: Array = all_options(u, req).filter(func(o): return not o.owned)
	if free.size() <= OFFER:
		return free
	var draw := RandomNumberGenerator.new()      # a string hash alone mixes too little
	draw.seed = hash(_offer_salt(u, req))
	var keyed: Array = []
	for i in free.size():
		keyed.append([draw.randi(), i])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var take: Array = keyed.slice(0, OFFER).map(func(k): return k[1])
	take.sort()
	return take.map(func(i): return free[i])


## The ids options() offers.
static func offered(u: BWUnit, req: Dictionary) -> Array:
	return options(u, req).map(func(o): return str(o.id))


## What a request's draw hashes: the unit's seed, the request, and how many
## picks of that kind the unit has made (so each new pick draws afresh).
static func _offer_salt(u: BWUnit, req: Dictionary) -> String:
	if str(req.get("kind", "")) == "keystone":
		var kel := str(req.get("element", ""))
		return "keystone|%d|%s|%d|%s" % [u.pick_seed, kel, keystones_owned(u, kel).size(), u.id]
	if str(req.get("kind", "")) == "perk":
		var el := str(req.get("element", ""))
		return "perk|%d|%s|%d|%s" % [u.pick_seed, el, owned(u, el).size(), u.id]
	var wc := str(req.get("weapon", ""))
	return "skill|%d|%s|%d|%s" % [u.pick_seed, wc, int(u.skill_picks.get(wc, 0)), u.id]


## Every option of a request, already-owned ones flagged (the codex and the
## draw's pool). [{ id, name, text, element, owned, kind }]
static func all_options(u: BWUnit, req: Dictionary) -> Array:
	var out: Array = []
	if req.get("kind", "") == "perk":
		var el := str(req.element)
		for r in perks_of(el):
			out.append({ "id": str(r.id), "name": str(r.name), "text": str(r.effect_text), "element": el,
				"owned": str(r.id) in u.perks, "kind": "perk" })
	elif req.get("kind", "") == "keystone":
		var kel := str(req.element)
		for id in BWKeystones.of_element(kel):
			var kr := BWKeystones.row(str(id))
			out.append({ "id": str(id), "name": str(kr.get("name", id)), "text": str(kr.get("text", "")),
				"element": kel, "owned": str(id) in u.keystones, "kind": "keystone",
				"action": BWKeystones.is_action(str(id)) })
	elif req.get("kind", "") == "skill":
		var wc := str(req.weapon)
		var free := skill_choices(u, wc)
		var listed: Array = []
		# known skills in loadout-then-known order: improvable, or already improved (greyed)
		for k in u.loadout(wc) + u.known(wc).filter(func(x): return not x in u.loadout(wc)):
			if k in listed or not improvable(k):
				continue                         # no Improve rider: no card
			listed.append(k)
			var row := BWSkills.get_skill(k)
			var done := u.skill_upgraded(k)
			out.append({ "id": "improve:" + k, "name": ("Improved " if done else "Improve ") + str(row.get("name", k)),
				"text": str(row.get("plus", "")), "element": "", "owned": done or not ("improve:" + k) in free,
				"kind": "improve", "skill": k })
		for c in free:
			if not str(c).begins_with("learn:"):
				continue
			var key := str(c).trim_prefix("learn:")
			var row := BWSkills.get_skill(key)
			out.append({ "id": c, "name": "Learn " + str(row.get("name", key)),
				"text": str(row.get("desc", "")), "element": "", "owned": false, "kind": "learn", "skill": key })
	return out


## Make one choice. Returns the pick record, or {} if it isn't a legal answer
## to `req` right now.
static func apply(u: BWUnit, req: Dictionary, choice: String) -> Dictionary:
	match str(req.get("kind", "")):
		"perk":
			var el := str(req.element)
			var row := perk(choice)
			if row.is_empty() or str(row.element) != el or choice in u.perks:
				return {}
			if owned(u, el).size() >= allowance(u, el):
				return {}
			if not choice in offered(u, req):
				return {}                        # D174: only one of the two offered
			u.perks.append(choice)
			return _record("perk", el, choice, false)
		"keystone":
			var kel := str(req.element)
			if BWKeystones.element_of(choice) != kel or choice in u.keystones:
				return {}
			if keystones_owed(u, kel) <= 0 or not choice in offered(u, req):
				return {}                        # D277: one of the two offered, within the cap
			BWKeystones.grant(u, choice)
			return _record("keystone", kel, choice, false)
		"skill":
			var wc := str(req.weapon)
			if skill_picks_owed(u, wc) <= 0 or not choice in skill_choices(u, wc):
				return {}
			if not choice in offered(u, req):
				return {}                        # D174: only one of the two offered
			var parts: PackedStringArray = choice.split(":")
			var key := parts[1]
			if parts[0] == "improve":
				u.skill_ranks[key] = 2
			else:
				u.known_skills.append(key)
				# into the loadout while there's room (it stays known either way)
				u.set_equipped(wc, key, true)
			u.skill_picks[wc] = int(u.skill_picks.get(wc, 0)) + 1
			return _record("skill", wc, choice, false)
	return {}


## The AI's answer: the first of the offered options (D174), data order, so
## it is deterministic: perks in CSV order, skills improve-before-learn.
static func auto_choice(u: BWUnit, req: Dictionary) -> String:
	for o in options(u, req):
		if not o.owned:
			return str(o.id)
	return ""


## Settle, then answer every pick owed with auto_choice. Returns the records.
static func auto_resolve(u: BWUnit) -> Array:
	var made: Array = []
	for guard in 64:
		made.append_array(settle(u))
		var p := pending(u)
		if p.is_empty():
			break
		var req: Dictionary = p[0]
		var rec := apply(u, req, auto_choice(u, req))
		if rec.is_empty():
			break
		rec["auto"] = true
		made.append(rec)
	return made


static func _record(kind: String, what: String, id: String, auto: bool) -> Dictionary:
	var r := { "kind": kind, "id": id, "auto": auto }
	r["weapon" if kind == "skill" else "element"] = what
	return r


## Weapon classes the unit has expertise in, plus the one it holds (stable order).
static func _classes(u: BWUnit) -> Array:
	var out: Array = []
	for wc in BWData.table("weapons").map(func(r): return str(r.id)):
		if wc == u.weapon_class or int(u.expertise.get(wc, 0)) > 0:
			out.append(wc)
	return out


## One line for a pick record (feeds, results).
static func describe(u: BWUnit, rec: Dictionary) -> String:
	if rec.kind == "keystone":
		return "%s took the keystone %s (%s)" % [u.name, BWKeystones.name_of(str(rec.id)), str(rec.element)]
	if rec.kind == "perk":
		return "%s took %s (%s)" % [u.name, str(perk(str(rec.id)).get("name", rec.id)), str(rec.element)]
	if str(rec.id) == "":
		return "%s had nothing left to learn in %s" % [u.name, str(rec.weapon)]
	var parts: PackedStringArray = str(rec.id).split(":")
	var nm := str(BWSkills.get_skill(parts[1]).get("name", parts[1]))
	return "%s %s %s" % [u.name, "improved" if parts[0] == "improve" else "learned", nm]
