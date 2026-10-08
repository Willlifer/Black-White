extends BWSkillDef
## Sword. Free (D87): set a guard and still act, before or after acting. The
## first blow to land on you is halved (BWFormulas.guard) and answered with
## RIPOSTE_DMG to your ring (BWBattle._answer); a landed answer refunds 1
## cooldown. An unspent guard drops at your next turn. Riposte+ (D103): the
## guard re-arms once after the first answer, so two blows are halved and
## answered.
## D425 (the author: "if not triggered, upon turn start, trigger a
## distance-3 line of element in all 6 directions around the user"): a guard
## that answered nothing by the start of your next turn releases: six lines
## of RELEASE_LEN hexes of its element run out from you (jagged rock stops a
## line), painted like Ley Line (BWKit2.turn_start calls `release`).

const PLUS_BLOWS := 2
const RELEASE_LEN := 3


func _init() -> void:
	define({
		"key": "riposte", "name": "Riposte", "weapon": "sword", "clip": "brace",
		"desc": "Free: set your guard and still act. The first blow to land is halved, and answered; a landed answer takes 1 off the cooldown. Unanswered by your next turn, the guard releases: six 3-tile lines of its element run out from you",
		"plus": "Riposte+: answers the first two blows, both halved",
		"targeting": "self", "needs_element": true, "range": 0, "cd": BWSkills.RIPOSTE_CD,
		"power": BWSkills.RIPOSTE_DMG, "free_action": true,
	}, 130)


func plan(b: BWBattle, u: BWUnit, element: String, _target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._without(b._on_board(b.board.area(u.pos, 1)), u.pos)          # where the answer lands
	if upgraded(u):
		p.notes.append("Riposte+: answers the first %d blows, both halved" % PLUS_BLOWS)
	p["release"] = release_hexes(b, u)                                          # D425: the preview
	if element != "":
		p.notes.append("Unanswered by your next turn: six lines of %s, %d tiles each (%d tiles)" % [
			element, RELEASE_LEN, (p.release as Array).size()])


func ground(b: BWBattle, u: BWUnit, el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	u.riposte = { "element": el }
	u.fx.erase("riposte_answered")          # D425: a fresh guard has answered nothing yet
	if upgraded(u):
		u.fx["riposte_more"] = PLUS_BLOWS - 1
		var cb := Callable(self, "_rearm").bind(u)
		if not b.event.is_connected(cb):
			b.event.connect(cb)
	return 0


## Riposte+: an answer was given; the guard goes straight back up while
## blows remain. Your own turn starting drops what's left.
func _rearm(e: Dictionary, u: BWUnit) -> void:
	if str(e.get("unit", "")) != u.id:
		return
	if e.type == "turn":
		u.fx.erase("riposte_more")
	elif e.type == "riposte" and int(u.fx.get("riposte_more", 0)) > 0 and u.alive() and u.riposte.is_empty():
		u.fx["riposte_more"] = int(u.fx.riposte_more) - 1
		u.riposte = { "element": str(e.get("element", "")) }


## D87: set last in the AI's turn when a foe is within 3 hexes.
func ai_free_wanted(b: BWBattle, u: BWUnit) -> bool:
	return u.riposte.is_empty() and b.foes_of(u).any(func(f): return b.gap(u, f) <= 3)


## D425: the six release lines from `u` (or `at`): RELEASE_LEN hexes each,
## stopping at the map edge or jagged rock. Units don't stop a line.
func release_hexes(b: BWBattle, u: BWUnit, at: Vector2i = BWBattle.NOWHERE) -> Array:
	var c := u.pos if at == BWBattle.NOWHERE else at
	var out: Array = []
	for n in BWHex.neighbors(c):
		for h in b.board.ray(c, n, RELEASE_LEN):
			if b.board.terrain(h) == BWBoard.JAGGED:
				break
			out.append(h)
	return out


## D425: the guard went unanswered: it lets go as six painted lines.
func release(b: BWBattle, u: BWUnit, el: String) -> void:
	if el == "" or b.over or not u.alive():
		return
	var hexes := release_hexes(b, u)
	if hexes.is_empty():
		return
	b._emit({ "type": "riposte_release", "unit": u.id, "element": el, "hexes": hexes })
	b.paint(hexes, el, u)
