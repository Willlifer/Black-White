extends BWSkillDef
## Sword. Free (D87): set a guard and still act, before or after acting. The
## first blow to land on you is halved (BWFormulas.guard) and answered with
## RIPOSTE_DMG to your ring (BWBattle._answer); a landed answer refunds 1
## cooldown. An unspent guard drops at your next turn. Riposte+ (D103): the
## guard re-arms once after the first answer, so two blows are halved and
## answered.

const PLUS_BLOWS := 2


func _init() -> void:
	define({
		"key": "riposte", "name": "Riposte", "weapon": "sword", "clip": "brace",
		"desc": "Free: set your guard and still act. The first blow to land is halved, and answered; a landed answer takes 1 off the cooldown",
		"plus": "Riposte+: answers the first two blows, both halved",
		"targeting": "self", "needs_element": true, "range": 0, "cd": BWSkills.RIPOSTE_CD,
		"power": BWSkills.RIPOSTE_DMG, "free_action": true,
	}, 130)


func plan(b: BWBattle, u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.hexes = b._without(b._on_board(b.board.area(u.pos, 1)), u.pos)          # where the answer lands
	if upgraded(u):
		p.notes.append("Riposte+: answers the first %d blows, both halved" % PLUS_BLOWS)


func ground(b: BWBattle, u: BWUnit, el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	u.riposte = { "element": el }
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
