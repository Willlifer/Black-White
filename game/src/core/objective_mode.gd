class_name BWObjectiveMode
extends RefCounted
## D327: the base class of a fight MODE's rules (Split Front, Stop the Horde,
## Defend / Storm the Castle). BWObjectives dispatches the battle's hooks to
## the map's mode (board.objective.mode) through one instance of this class;
## every method is a no-op by default, so a mode overrides only what it needs.
## Instances are stateless: the state lives in BWBattle.objective_state (ids
## and numbers, so BWBattle.clone copies it). Pure rules, no nodes.


## Display name ("Split Front") and the one-line objective for the banners,
## the pre-battle screen and the results.
func title() -> String:
	return ""


func objective_text(_b: BWBattle) -> String:
	return ""


## BWBattle.setup, after both sides and the map's objects are placed.
func setup(_b: BWBattle) -> void:
	pass


## BWBattle._new_cycle, before cycle `c` starts and its queue is built (after
## the tick). BWObjectives runs the wave spawner just before this.
func cycle_start(_b: BWBattle, _c: int) -> void:
	pass


## After `u` walks (BWBattle.move).
func after_move(_b: BWBattle, _u: BWUnit) -> void:
	pass


## At `u`'s turn end (BWBattle.end_turn).
func turn_end(_b: BWBattle, _u: BWUnit) -> void:
	pass


## After a KO (BWBattle._ko). An objective object breaking lands here too.
func on_ko(_b: BWBattle, _victim: BWUnit, _by: BWUnit) -> void:
	pass


## After `u`'s basic attack on `target` resolved (BWBattle.attack).
func after_basic(_b: BWBattle, _u: BWUnit, _target: BWUnit, _first: Dictionary) -> void:
	pass


## The mode's verdict (BWBattle._check_end, before the default rules):
## "" = use the default rules (squad down: lose; enemy down: win);
## "player" / "enemy" = the battle ends with that winner; "-" = not over.
func verdict(_b: BWBattle) -> String:
	return ""


## BWAI.take_turn: play `u`'s whole turn and return true, or false for the
## usual AI.
func ai_turn(_b: BWBattle, _u: BWUnit) -> bool:
	return false


## BWAI._best_target: a multiplier on the score of a blow by `u` on `f`.
func ai_target_weight(_b: BWBattle, _u: BWUnit, _f: BWUnit) -> float:
	return 1.0


## Lines for the HUD's objective plate (wave counter, escapes, divider ...).
func hud_lines(_b: BWBattle) -> Array:
	return []
