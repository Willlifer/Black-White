class_name BWObjective
extends BWObelisk
## D327: a generic objective OBJECT on the board (a wall segment, a gate, a
## throne, a banner): HP, no move, team "neutral" (so it never joins a side's
## roster, side("player") / side("enemy") stay the fighters), and an
## `allegiance` it belongs to for display and the AI ("player", "enemy" or
## "none"). Built on BWObelisk so every stone rule already in the code holds
## for it for free (D141: no ground damage, no statuses, never displaced,
## never a chain target, not hit by pulses), but it does NOT pulse and, unless
## `acts` is set, never takes a turn (BWTurnQueue skips it).
##
## Who may strike it: `hittable` (team names). BWBattle.foes_of / can_harm read
## hittable_by(). A wall segment both sides can break: ["player", "enemy"]; a
## gate the enemy must break (Defend the Castle): ["enemy"]; a throne the
## squad must break (Storm the Castle): ["player"].
##
## Build one with BWObjective.make(kind, at, opts) and hand it to
## BWObjectives.place(b, o) (from a mode's setup), or list it in the map JSON
## under objective.objects (BWObjectives.setup places them):
##   "objects": [ { "kind": "gate", "at": [q, r], "hp": 400, "name": "The Gate",
##                  "allegiance": "player", "hittable": ["enemy"], "def": 8,
##                  "res": 8, "look": "bright", "rule": "...", "codex": "..." } ]

var allegiance := "none"
var hittable: Array = ["player", "enemy"]
var acts := false                    # takes a turn in the speed queue (BWObjectives.object_turn)
var rule := ""
var codex := ""
var look_key := "bright"             # BWObeliskView's fallback prism: "bright" (white) or "dark"
var view_height := 3.2               # the view's prism height (world units)
var tag := ""                        # free mode tag (e.g. "divider"), for the mode's own lookups


static func make(p_kind: String, p_at: Vector2i, opts: Dictionary = {}) -> BWObjective:
	var o := BWObjective.new()
	o.kind = p_kind
	o.id = str(opts.get("id", "obj_%s_%d_%d" % [p_kind, p_at.x, p_at.y]))
	o.name = str(opts.get("name", p_kind.capitalize()))
	o.team = TEAM
	o.friendliness = "unfriendly"
	o.element = str(opts.get("element", ""))
	o.weapon_class = ""
	o.weapon_model = ""
	for s in BWUnit.STATS:
		o.stats[s] = 0
	o.stats["def"] = int(opts.get("def", 6))
	o.stats["res"] = int(opts.get("res", 6))
	o.stats["spd"] = int(opts.get("spd", 0))
	o.pulse_kind = ""
	o.pulse_damage = 0
	o.dodge_vs = str(opts.get("dodge", "none"))    # "ranged" / "melee" halves that kind's hit (D142); "none" = no veil
	o.hp_cap = maxi(1, int(opts.get("hp", 100)))
	o.allegiance = str(opts.get("allegiance", "none"))
	o.hittable = Array(opts.get("hittable", ["player", "enemy"])).map(func(t): return str(t))
	o.acts = bool(opts.get("acts", false))
	o.rule = str(opts.get("rule", ""))
	o.codex = str(opts.get("codex", ""))
	o.look_key = str(opts.get("look", "bright"))
	o.view_height = float(opts.get("height", 3.2))
	o.tag = str(opts.get("tag", ""))
	o.at = p_at
	o.cosmetics["tagline"] = o.codex
	o.hp = o.hp_cap
	return o


func hittable_by(t: String) -> bool:
	return t in hittable


func rule_text() -> String:
	return rule


func codex_line() -> String:
	return codex


func veil_name() -> String:
	return "Veil"


func look() -> String:
	return look_key


static func is_object(u: BWUnit) -> bool:
	return u is BWObjective
