class_name BWPicks
## Picks (D90, D91): what a unit chooses as it grows. Pure rules, no nodes.
##
## Element perks (data/perks.csv, five per element once the designer fills
## it): affinity rank 1 in an element gives the first pick, rank 2 a second,
## rank 3 grants every perk of that element (no choice). Units start at rank
## 1 in their own element, so each owes one pick at run start. Perks are one
## more effect source in BWEffects.collect, next to equipment and abilities.
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
## Rank 3 still grants the element's every perk (settle).
##
## A request is { kind: "perk", element } or { kind: "skill", weapon }.
## A choice id is a perk id, or "improve:<skill>" / "learn:<skill>".

const TABLE := "perks"
const ALL_RANK := 3                 # affinity rank that grants the whole element
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


## How many of the element's perks the unit's rank entitles it to.
static func allowance(u: BWUnit, element: String) -> int:
	var n := perks_of(element).size()
	var r := u.affinity_rank(element)
	return n if r >= ALL_RANK else mini(r + int(u.bonus_perks.get(element, 0)), n)   # D128: + Specialize's free picks


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
		if u.affinity_rank(el) >= ALL_RANK:
			continue                     # granted by settle(), no choice
		for i in maxi(0, allowance(u, el) - owned(u, el).size()):
			out.append({ "kind": "perk", "element": el })
	for wc in _classes(u):
		for i in skill_picks_owed(u, wc):
			out.append({ "kind": "skill", "weapon": wc })
	return out


## The next pick the unit owes, or {} (after settle()).
static func next_request(u: BWUnit) -> Dictionary:
	settle(u)
	var p := pending(u)
	return p[0] if not p.is_empty() else {}


## Grant what needs no choice: rank 3 = the element's remaining perks; a
## skill pick with nothing to choose is spent. Returns the pick records made.
static func settle(u: BWUnit) -> Array:
	var made: Array = []
	for el in BWFormulas.ELEMENTS:
		if u.affinity_rank(el) < ALL_RANK:
			continue
		for r in perks_of(el):
			if not str(r.id) in u.perks:
				u.perks.append(str(r.id))
				made.append(_record("perk", el, str(r.id), true))
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
	r["element" if kind == "perk" else "weapon"] = what
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
	if rec.kind == "perk":
		return "%s took %s (%s)" % [u.name, str(perk(str(rec.id)).get("name", rec.id)), str(rec.element)]
	if str(rec.id) == "":
		return "%s had nothing left to learn in %s" % [u.name, str(rec.weapon)]
	var parts: PackedStringArray = str(rec.id).split(":")
	var nm := str(BWSkills.get_skill(parts[1]).get("name", parts[1]))
	return "%s %s %s" % [u.name, "improved" if parts[0] == "improve" else "learned", nm]
