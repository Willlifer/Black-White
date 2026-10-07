class_name BWGame
extends Node
## The run's flow (brief): title → pick 6 of 20 (the first perks auto-picked, D233) →
## the hall (share out the gear, D84) → [pre-battle (pick 3, place)
## → combat → results → downtime] × 10 → the boss → the end.
## One screen at a time; each screen emits `done(payload)` and this decides
## what comes next. The run autosaves at every screen change.

const SAVE_PATH := "user://run.json"

var run: BWRun
var screen: Node
var _fade: ColorRect


func _ready() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_fade)
	BWMusic.ensure(self)
	go_title()


# ---------------------------------------------------------------- screens

func go_title() -> void:
	var s := BWTitleScreen.new()
	s.has_save = FileAccess.file_exists(SAVE_PATH)
	s.old_save = s.has_save and not BWRun.can_load(_read_save())    # D150: a pre-rename save
	await _swap(s)
	BWMusic.play("title")
	var choice: String = await s.done
	if choice == "tutorial":                     # ---- D223: the practice fight, never the run or the save
		go_tutorial()
		return
	if choice == "continue" and not s.old_save and _load():
		_next_after_load()
	else:
		go_roster()


## D223: the guided practice fight. It brings its own squad and run and
## never touches `run` or the save; back to the title when it ends or exits.
func go_tutorial() -> void:
	var s := BWTutorial.new()
	await _swap(s)
	BWMusic.play("combat")
	await s.finished
	go_title()


func go_roster() -> void:
	var s := BWRosterScreen.new()
	await _swap(s)
	BWMusic.play("roster")
	var chosen: Array = await s.done
	var run_seed := int(Time.get_unix_time_from_system()) & 0x7fffffff
	if BWRosterGen.fixed_seed >= 0:
		run_seed = BWRosterGen.fixed_seed                      # D154: --seed / probes reproduce
	run = BWRun.start(chosen, run_seed, s.rows, s.roster_seed)   # D150: the screen's roll
	_save()
	go_prep()                                      # D233: first perks auto-picked in BWRun.start, no picker


## D90: owed picks, one picker per unit, before anything else happens
## (after a load that owes any; D233: no longer at run start).
func go_picks(title: String = "Picks owed") -> void:
	if run.pending_picks().is_empty():
		return
	var s := BWPicksScreen.new()
	s.run = run
	s.title_text = title
	await _swap(s)
	BWMusic.play("rest")
	await s.done
	_save()


## Before the first fight: the marble hall, sharing out the starting gear
## (D84; replaced the loading-screen intro on this path).
func go_prep() -> void:
	var s := BWPrepScreen.new()
	s.run = run
	await _swap(s)
	BWMusic.play("rest")
	await s.done
	_save()
	go_rooms(true)


## D186/D190: the room choice before the pre-battle (not at the Obelisks or
## the Giant, and not again once made: a load mid-choice shows the same two).
## Esc goes back to the hall before fight 1 (`from_hall`); after a day it can't.
func go_rooms(from_hall: bool = false) -> void:
	if not BWRooms.has_choice(run.fight) or BWRooms.chosen_index(run) >= 0:
		go_prebattle()
		return
	var s := BWRoomScreen.new()
	s.run = run
	s.can_back = from_hall
	await _swap(s)
	_save()                                        # the offer is stored: a reload shows the same two
	var i: int = await s.done
	if i < 0:
		go_prep()
		return
	BWRooms.choose(run, i)
	_save()
	go_prebattle()


func go_prebattle() -> void:
	var s := BWPrebattleScreen.new()
	s.run = run
	await _swap(s)
	BWMusic.play("prebattle")
	var plan: Dictionary = await s.done           # { units: [BWUnit], at: [Vector2i] }
	go_combat(plan)


func go_combat(plan: Dictionary) -> void:
	var enemies := run.enemies_for(run.fight)
	run.empty_trash()                              # D234: the discard pile is gone once the battle starts
	run.prepare_for_battle(plan.units)
	var s := BWCombatScreen.new()
	s.configure("res://maps/%s.json" % run.map_for(run.fight), plan.units, enemies, plan.at,
		run.seed_value * 31 + run.fight)
	s.trust_fn = run.trust_stage
	s.picks_live = true                            # D91: rank-ups pick mid-fight
	await _swap(s)
	BWMusic.play("boss" if run.is_boss() else "combat")
	var result: Array = await s.finished           # [winner, battle]
	var battle: BWBattle = result[1]
	var won: bool = result[0] == "player"
	var defeated := enemies.filter(func(e): return not e.alive())
	var was_boss := run.is_boss()
	var report := run.after_fight(won, plan.units, defeated, enemies, battle.history, battle.objectives())   # D140
	for u in run.squad:
		u.hp = u.max_hp()        # everyone is patched up between fights
	_save()
	if was_boss:
		go_end(won, was_boss, report)
		return
	go_results(report)        # won or lost, the run goes on (author 10/4)


func go_results(report: Dictionary) -> void:
	var s := BWResultsScreen.new()
	s.run = run
	s.report = report
	await _swap(s)
	BWMusic.play("rest")
	await s.done
	go_downtime()


func go_downtime() -> void:
	var s := BWDowntimeScreen.new()
	s.run = run
	await _swap(s)
	BWMusic.play("rest")
	await s.done
	_save()
	go_rooms()


func go_end(won: bool, boss: bool, report: Dictionary = {}) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var s := BWEndScreen.new()
	s.run = run                    # D121: the run summary under the card
	s.report = report
	s.text = ("The squad stood against the Giant.\nNobody does that." if won else "The Giant wins.\nIt always does.") if boss \
		else "The squad fell in fight %d." % run.fight
	await _swap(s)
	BWMusic.play("title")
	await s.done
	go_title()


func _next_after_load() -> void:
	await go_picks("Picks owed")
	go_rooms()                                     # D190: mid-choice, the same two rooms


# ---------------------------------------------------------------- plumbing

func _swap(next: Node) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	await tw.finished
	if screen:
		screen.queue_free()
		await get_tree().process_frame
	screen = next
	add_child(screen)
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.6)


func _save() -> void:
	if run == null:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(run.to_dict()))


func _read_save() -> Variant:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))


func _load() -> bool:
	var parsed: Variant = _read_save()
	if not BWRun.can_load(parsed):           # D150: older versions start fresh
		return false
	run = BWRun.from_dict(parsed)
	return true
