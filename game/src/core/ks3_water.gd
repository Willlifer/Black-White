class_name BWKs3Water
extends RefCounted
## D450c-D451b water's keystones (Keystones v3, design/ELEMENTS.md).
##
## Leviathan      once a battle, a walk of YOUR OWN that ends on water 3
##                (unglazed; pushes and pulls never count) offers to SUBMERGE
##                (a prompt: BWBattle.pending_picks asks { kind: "leviathan",
##                step: "submerge" }; the AI decides at once). Submerging ends
##                your turn (your action and move are spent). At your NEXT
##                turn, before acting ({ step: "form" }), choose for the rest of
##                the battle:
##                  * LEVIATHOS (D451b, the author's approved FALLBACK): it moves
##                    and occupies like any one-hex unit, with double max and
##                    current HP and a scaled-up model; its basic blows splash
##                    every foe next to the target for SPLASH_SHARE (Claude).
##                    The true 7-hex body stays a TODO: the multi-hex support is
##                    enemy-only in practice (the weapon-skill defs aim and
##                    relocate from a one-hex caster, the AI skips skills for
##                    multi-hex units, the view sizes a body once at setup).
##                  * DROWNED: you can't move and can't be moved; your basic
##                    attacks reach ANY foe on the board (no sight needed),
##                    measured from you. A melee blow lunges: the view takes
##                    you to the target for the blow, then back to your hex
##                    (events drowned_lunge / drowned_return; the rules never
##                    move you). Skills keep their own ranges.
## Being of Rain  water costs you no move to enter (BWKs3.move_rules: cost_on
##                water 0). You never paint as you walk (lay_on move riders
##                skip you). When a walk ends, every hex of it and their
##                neighbours gain water 1 (a propagated spread: it fires no
##                marker and skips glaze); a `rain` event drives the cloud.

const LEVIATHAN := "leviathan"
const RAIN := "being_of_rain"
const LEVIATHOS_READY := true         # D451b: the author's fallback (a one-hex body; the 7-hex one stays a TODO)
const SPLASH_SHARE := 0.5             # Leviathos: its basic blows splash foes next to the target at 50%


static func ks(u: BWUnit, id: String) -> bool:
	return BWKs3.ks(u, id)


static func state(u: BWUnit) -> String:
	return str(u.fx.get("lev", "")) if u != null else ""


static func drowned(u: BWUnit) -> bool:
	return state(u) == "drowned"


# ---------------------------------------------------------------- walking

## BWBattle.move, after the walk: the rain, then the Leviathan's offer.
static func after_walk(b: BWBattle, u: BWUnit, path: Array) -> void:
	if b.over or not u.alive() or path.size() < 2:
		return
	if ks(u, RAIN):
		var hexes: Array = []
		for h in path:
			for n in b.board.area(h, 1):
				if b.tiles.can_hold(n) and not n in hexes:
					hexes.append(n)
		hexes.sort()
		b._emit({ "type": "rain", "unit": u.id, "path": path.duplicate(), "hexes": hexes.duplicate() })
		b.paint(hexes, "water", u, int(BWKeystones.param(RAIN, "water", 1)), false, { "propagated": true })
	if b.over or not u.alive():
		return
	var dest: Vector2i = path[-1]
	if ks(u, LEVIATHAN) and not u.fx.get("lev_used", false) and state(u) == "" and u == b.current() \
			and maxi(u.size, 1) == 1 and b.tiles.intensity(dest, "water") >= int(BWKeystones.param(LEVIATHAN, "water", 3)) \
			and not b.tiles.is_glazed(dest):
		u.fx["lev"] = "offer"
		b._emit({ "type": "leviathan_offer", "unit": u.id, "hex": dest })
		if u.team in b.auto_pick_teams:
			answer(b, u, "submerge" if ai_submerge(b, u) else "stay")


## The AI submerges where it couldn't strike anyway (no foe in reach now).
static func ai_submerge(b: BWBattle, u: BWUnit) -> bool:
	return b.attack_targets(u).is_empty()


# ---------------------------------------------------------------- the prompts

## The prompt `u` owes now ({} for none): the offer after its walk, the form
## at its next turn (only while it is the current unit).
static func request(b: BWBattle, u: BWUnit) -> Dictionary:
	if u == null or u != b.current() or not u.alive():
		return {}
	match state(u):
		"offer":
			return { "kind": "leviathan", "step": "submerge", "element": "water",
				"ai": "submerge" if ai_submerge(b, u) else "stay" }
		"submerged":
			if int(u.fx.get("lev_turn", -1)) == b._turn_serial:
				return {}                     # the turn it sank in: the form waits for the next one
			return { "kind": "leviathan", "step": "form", "element": "water", "ai": ai_form(u) }
	return {}


## The cards a prompt shows ([{id, name, text, element, owned, kind}]).
static func options(_u: BWUnit, req: Dictionary) -> Array:
	if str(req.get("step", "")) == "submerge":
		return [
			{ "id": "submerge", "name": "Submerge", "text": "Once a battle: sink into the water 3. Your turn ends now. At your next turn, before acting, choose your form for the rest of the battle.",
				"element": "water", "owned": false, "kind": "leviathan" },
			{ "id": "stay", "name": "Stay above", "text": "Not now. You can still submerge later this battle, ending a walk on water 3.",
				"element": "water", "owned": false, "kind": "leviathan" },
		]
	return [
		{ "id": "leviathos", "name": "Leviathos", "text": "You grow huge: double max and current HP for the battle, and your basic blows splash foes next to the target (50%)." + ("" if LEVIATHOS_READY else " Not built yet."),
			"element": "water", "owned": not LEVIATHOS_READY, "locked": not LEVIATHOS_READY, "kind": "leviathan" },
		{ "id": "drowned", "name": "Drowned", "text": "You can't move or be moved. Your basic attacks reach any foe on the board; a melee blow lunges there and back.",
			"element": "water", "owned": false, "kind": "leviathan" },
	]


## Answer the prompt. True when it was a legal answer.
static func answer(b: BWBattle, u: BWUnit, choice: String) -> bool:
	match state(u):
		"offer":
			if choice == "submerge":
				u.fx["lev"] = "submerged"
				u.fx["lev_used"] = true
				u.fx["lev_turn"] = b._turn_serial
				u.acted = true
				u.moved = true
				u.follow_up = []
				u.fx["bonus_move"] = 0
				u.fx["extra_move"] = 0
				b._emit({ "type": "submerge", "unit": u.id, "hex": u.pos })
				return true
			if choice == "stay":
				u.fx["lev"] = ""
				return true
		"submerged":
			if choice == "drowned":
				u.fx["lev"] = "drowned"
				b._emit({ "type": "leviathan_form", "unit": u.id, "form": "drowned", "hex": u.pos })
				return true
			if choice == "leviathos" and LEVIATHOS_READY:
				var before := u.max_hp()
				u.fx["lev"] = "leviathos"
				u.hp = mini(u.max_hp(), u.hp + (u.max_hp() - before))   # current HP doubles with the max
				b._emit({ "type": "leviathan_form", "unit": u.id, "form": "leviathos", "hex": u.pos, "hp": u.hp })
				return true
	return false


static func leviathos(u: BWUnit) -> bool:
	return state(u) == "leviathos"


## BWBattle.basic_strikes: Leviathos's blow splashes the foes next to the target.
static func splash_strikes(b: BWBattle, u: BWUnit, target: BWUnit, out: Array) -> void:
	if not leviathos(u):
		return
	for n in b.board.neighbors(target.pos):
		var o := b.unit_at(n)
		if o == null or o == u or o == target or o.team == u.team or not o.alive():
			continue
		if out.any(func(st): return st.unit == o):
			continue
		out.append({ "unit": o, "share": SPLASH_SHARE, "label": "Leviathos (splash)", "pattern": "cleave" })


## BWAI: resolve what `u` owes (a sim's player side; enemies answer at once).
static func ai_resolve(b: BWBattle, u: BWUnit) -> void:
	var req := request(b, u)
	if not req.is_empty():
		answer(b, u, str(req.ai))


## The holder's turn start: an AI-side Leviathan picks its form at once.
static func turn_start(b: BWBattle, u: BWUnit) -> void:
	if state(u) == "submerged" and u.team in b.auto_pick_teams:
		answer(b, u, ai_form(u))


## The AI's form: a ranged weapon drowns (it shoots the whole board); a melee
## one becomes Leviathos (it keeps walking, double HP, splash).
static func ai_form(u: BWUnit) -> String:
	return "leviathos" if melee(u) and LEVIATHOS_READY else "drowned"


## Its turn end: an unanswered offer lapses.
static func turn_end(_b: BWBattle, u: BWUnit) -> void:
	if state(u) == "offer":
		u.fx["lev"] = ""


# ---------------------------------------------------------------- Drowned

## BWBattle.attack: a melee Drowned blow lunges to the target (the view) and
## back. The hex beside the target nearest the attacker, free, else the
## target's own neighbour on the line.
static func lunge_hex(b: BWBattle, u: BWUnit, target: BWUnit) -> Vector2i:
	var best := BWBattle.NOWHERE
	var bd := 1 << 20
	for n in b.board.neighbors(target.pos):
		if not b.board.is_passable(n):
			continue
		var o := b.unit_at(n)
		if o != null and o != u:
			continue
		var d := BWHex.distance(n, u.pos)
		if d < bd:
			bd = d
			best = n
	return best if best != BWBattle.NOWHERE else target.pos


static func melee(u: BWUnit) -> bool:
	return int(u.weapon().get("range", 1)) <= 1


static func card_lines(b: BWBattle, h: Vector2i) -> Array:
	var out: Array = []
	var u := b._centre_at(h)
	if u == null or not u.alive():
		return out
	if leviathos(u):
		out.append("%s is Leviathos (Leviathan): double HP; its basic blows splash the foes next to the target (50%%)" % u.name)
	if drowned(u):
		out.append("%s is Drowned (Leviathan): it can't move or be moved; its basic attacks reach any foe on the board" % u.name)
	elif ks(u, LEVIATHAN) and not u.fx.get("lev_used", false):
		out.append("%s (Leviathan): ending its own walk on water 3 may submerge it (once a battle)" % u.name)
	if ks(u, RAIN):
		out.append("%s (Being of Rain): water costs it no move; a walk rains water 1 on its path and around" % u.name)
	return out
