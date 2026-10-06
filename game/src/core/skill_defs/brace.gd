extends BWSkillDef
## Fists. Free (spends nothing): set your feet. You take GUARD_PCT% less
## damage until your next turn starts (the FX `guard`, Phalanx.guard), and
## your next Flurry throws one more strike (flurry.gd reads `brace_flurry`).

const Phalanx := preload("res://src/core/skill_defs/phalanx.gd")

const CD := 3
const GUARD_PCT := 25


func _init() -> void:
	define({
		"key": "brace", "name": "Brace", "weapon": "fists", "clip": "brace",
		"desc": "Free: brace yourself. You take 25% less damage until your next turn, and your next Flurry throws one more strike",
		"targeting": "self", "needs_element": false, "range": 0, "cd": CD,
		"power": 0, "free_action": true,
	}, 372)


func plan(_b: BWBattle, _u: BWUnit, _element: String, _target: Vector2i, p: Dictionary) -> void:
	p.notes.append("Brace: -%d%% damage taken until your next turn; next Flurry +1 strike" % GUARD_PCT)


func ground(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, _p: Dictionary) -> int:
	Phalanx.guard(b, u, GUARD_PCT, "Brace")
	u.fx["brace_flurry"] = true
	return 0


## Set last in the AI's turn when a foe is within 2 and no stronger guard is up.
func ai_free_wanted(b: BWBattle, u: BWUnit) -> bool:
	return float(u.fx.get("guard", 0)) < GUARD_PCT and b.foes_of(u).any(func(f): return b.gap(u, f) <= 2)
