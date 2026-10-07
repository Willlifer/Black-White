class_name BWAudioCapture
extends Node
## `-- --audio-capture [dir]` (windowed): records what the game actually
## outputs (an AudioEffectRecord after the Master limiter) through a scripted
## 61 s run, and logs what it asked for, so tools/audio/analyse_capture.py
## can check levels, clipping, beat alignment and marker sync by analysis.
##
##   0.5 s   three sync clicks (UI bus, no music yet): the clock calibration
##   1.5 s   title screen, cue "title"
##   12 s    roster screen, cue "roster" (slow set); browse and pick four
##   24 s    an AI-vs-AI fight on the arena, cue "combat" (intensity follows HP)
##   50 s    cue "boss" (boss set, +10% tempo) over the same fight
##   61 s    stop, write capture.wav (Master), capture_sfx.wav (the SFX bus
##           alone, recorded in the same mix blocks) + capture.json, quit
## SFX pitch jitter is off so each sound matches its file for the analysis.

const SECTIONS := [["sync", 0.0], ["title", 1.5], ["roster", 12.0], ["combat", 24.0], ["boss", 50.0], ["end", 61.0]]
## D242: `--drop2`: the author's drop-2 cues and stings, each through the hook
## that plays it in the game (screens, the picker, the shop and gear panels).
const SECTIONS_DROP2 := [["sync", 0.0], ["title", 1.5], ["rest", 10.0], ["rooms", 19.0], ["prebattle", 28.0],
	["shop", 38.0], ["tutorial", 48.0], ["combat", 57.0], ["boss", 67.0], ["stings", 75.0], ["end", 87.0]]

var drop2 := false
var placeholders := false            # D394: `--placeholders`: the ph_* sounds and the short pick reveal
var out_dir := ""
var _rec: AudioEffectRecord
var _rec_sfx: AudioEffectRecord      # the SFX bus alone: a clean signal for the marker-sync check
var _t0 := 0
var _marks: Array = []
var _screen: Node


func _ready() -> void:
	_run.call_deferred()


func _now() -> float:
	return (Time.get_ticks_usec() - _t0) / 1e6


func _until(t: float) -> void:
	while _now() < t:
		await get_tree().process_frame


func _mark(what: String) -> void:
	_marks.append({ "what": what, "usec": Time.get_ticks_usec(), "frame": Engine.get_process_frames() })
	print("[audio-capture] %6.2f s  %s" % [_now(), what])


func _swap(next: Node) -> void:
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
		await get_tree().process_frame
	_screen = next
	get_parent().add_child(next)


func _run() -> void:
	if placeholders:
		await _run_placeholders()
		return
	if drop2:
		await _run_drop2()
		return
	BWSfx.jitter = 0.0
	BWSfx.log_enabled = true
	BWMusic.log_enabled = true
	BWUnitAudio.log_enabled = true
	BWVoice.log_enabled = true
	_rec = AudioEffectRecord.new()
	_rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, _rec)          # after the limiter: what the speakers get
	_rec_sfx = AudioEffectRecord.new()
	_rec_sfx.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), _rec_sfx)
	for i in 10:
		await get_tree().process_frame
	_rec.set_recording_active(true)
	_rec_sfx.set_recording_active(true)
	_t0 = Time.get_ticks_usec()
	_mark("record_start")
	await _until(0.5)
	for k in 3:
		BWSfx.ui("ui_click", { "variant": 1, "stack": true, "tag": "sync" })
		await _until(0.75 + 0.25 * k)

	await _until(1.5)
	await _swap(BWTitleScreen.new())
	BWMusic.play("title")
	_mark("title")

	await _until(12.0)
	var roster := BWRosterScreen.new()
	await _swap(roster)
	BWMusic.play("roster")
	_mark("roster")
	await _until(15.0)
	for i in 4:
		roster._select(i + 2)
		await get_tree().create_timer(0.45).timeout
		roster._toggle(i + 2)
		await get_tree().create_timer(0.9).timeout

	await _until(24.0)
	var roster_rows := BWData.table("roster")
	var players: Array = []
	var enemies: Array = []
	for i in 3:
		players.append(BWUnit.from_roster(roster_rows[[0, 4, 9][i]]))
		enemies.append(BWUnit.from_roster(roster_rows[[12, 15, 17][i]]))
	var combat := BWCombatScreen.new()
	combat.configure("res://maps/arena.json", players, enemies, [], 11)
	combat.autoplay = true
	await _swap(combat)
	# a scripted fight: everyone starts at 52% HP and one enemy is nearly out,
	# so intensity climbs and a KO (fall -> grounded) happens inside the window
	# (after the screen's setup, which heals everyone to full)
	for u in combat.battle.units:
		u.hp = int(u.max_hp() * 0.52)
	combat.battle.side("enemy")[0].hp = 6
	for v in combat._views.values():
		v.refresh()
	BWMusic.play("combat")
	_mark("combat")

	await _until(50.0)
	BWMusic.play("boss")
	_mark("boss")

	await _until(61.0)
	_mark("record_stop")
	_rec.set_recording_active(false)
	_rec_sfx.set_recording_active(false)
	var wav := _rec.get_recording()
	var stem := _rec_sfx.get_recording()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var wav_path := out_dir.path_join("capture.wav")
	var err := wav.save_to_wav(wav_path) if wav else ERR_CANT_CREATE
	if stem:
		stem.save_to_wav(out_dir.path_join("capture_sfx.wav"))
	var log := {
		"record_start_usec": _t0, "mix_rate": AudioServer.get_mix_rate(), "output_latency": AudioServer.get_output_latency(),
		"sections": SECTIONS, "marks": _marks, "sfx": BWSfx.events, "markers": BWUnitAudio.events,
		"music": _music_log(), "voice": BWVoice.events, "fps": Engine.get_frames_per_second(),
		"wav_seconds": wav.get_length() if wav else 0.0,
	}
	var f := FileAccess.open(out_dir.path_join("capture.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(log, " "))
	f.close()
	print("[audio-capture] wrote %s (%s), %.1f s at %d Hz" % [wav_path, error_string(err), wav.get_length() if wav else 0.0, AudioServer.get_mix_rate()])
	get_tree().quit(0 if err == OK else 1)


func _begin() -> void:
	BWSfx.jitter = 0.0
	BWSfx.log_enabled = true
	BWMusic.log_enabled = true
	BWUnitAudio.log_enabled = true
	BWVoice.log_enabled = true
	_rec = AudioEffectRecord.new()
	_rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, _rec)
	_rec_sfx = AudioEffectRecord.new()
	_rec_sfx.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(AudioServer.get_bus_index("SFX"), _rec_sfx)
	for i in 10:
		await get_tree().process_frame
	_rec.set_recording_active(true)
	_rec_sfx.set_recording_active(true)
	_t0 = Time.get_ticks_usec()
	_mark("record_start")
	await _until(0.5)
	for k in 3:
		BWSfx.ui("ui_click", { "variant": 1, "stack": true, "tag": "sync" })
		await _until(0.75 + 0.25 * k)


func _finish(stem: String, sections: Array) -> void:
	_mark("record_stop")
	_rec.set_recording_active(false)
	_rec_sfx.set_recording_active(false)
	var wav := _rec.get_recording()
	var sfx := _rec_sfx.get_recording()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var wav_path := out_dir.path_join(stem + ".wav")
	var err := wav.save_to_wav(wav_path) if wav else ERR_CANT_CREATE
	if sfx:
		sfx.save_to_wav(out_dir.path_join(stem + "_sfx.wav"))
	var log := {
		"record_start_usec": _t0, "mix_rate": AudioServer.get_mix_rate(), "output_latency": AudioServer.get_output_latency(),
		"sections": sections, "marks": _marks, "sfx": BWSfx.events, "markers": BWUnitAudio.events,
		"music": _music_log(), "voice": BWVoice.events, "fps": Engine.get_frames_per_second(),
		"wav_seconds": wav.get_length() if wav else 0.0,
	}
	var f := FileAccess.open(out_dir.path_join(stem + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(log, " "))
	f.close()
	print("[audio-capture] wrote %s (%s), %.1f s at %d Hz" % [wav_path, error_string(err), wav.get_length() if wav else 0.0, AudioServer.get_mix_rate()])
	get_tree().quit(0 if err == OK else 1)


## D242: the drop-2 run. Real screens where the hook watches a screen
## (results, rooms), real panels for the shop and the cursed piece, a real
## picker; the jackpot, victory and defeat stings by their BWMusic call.
func _run_drop2() -> void:
	await _begin()
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	for k in 1:                                   # fight 2; the results below make it 3 (D208: the first room choice)
		var e := run.enemies_for(run.fight)
		for x in e:
			x.hp = 0
		run.after_fight(true, run.squad.slice(0, 3), e, e, [])

	await _until(1.5)
	await _swap(BWTitleScreen.new())
	BWMusic.play("title")
	_mark("title")

	await _until(10.0)                            # the hall's cue, under a results screen that levelled the squad
	var e3 := run.enemies_for(run.fight)
	for x in e3:
		x.hp = 0
	var rs := BWResultsScreen.new()
	rs.run = run
	rs.report = run.after_fight(true, run.squad.slice(0, 3), e3, e3, [])
	await _swap(rs)
	BWMusic.play("rest")
	_mark("rest")

	await _until(19.0)
	var rooms := BWRoomScreen.new()
	rooms.run = run
	await _swap(rooms)
	BWMusic.play("rooms")
	_mark("rooms")
	await _until(24.0)
	var hard := 0
	for i in rooms.rooms.size():
		if str(rooms.rooms[i].kind) == BWRooms.HARD:
			hard = i
	rooms.choose(hard)
	_mark("room_hard")

	await _until(28.0)
	var blank := Control.new()
	await _swap(blank)
	BWMusic.play("prebattle")
	_mark("prebattle")
	await _until(32.0)
	var u: BWUnit = run.squad[0]
	var req := { "kind": "perk", "element": u.element, "rank": 2 }
	var picker := BWPicker.new(u, req, "capture")
	blank.add_child(picker)
	_mark("picker_open")
	await _until(36.0)
	picker.queue_free()
	_mark("picker_close")

	await _until(38.0)
	var shop := BWShopPanel.new(run)
	blank.add_child(shop)
	await get_tree().process_frame
	shop.changed.emit()                           # a trade / scroll went through
	_mark("shop_purchase")
	await _until(42.0)
	var gear := BWGearPanel.new(run)
	blank.add_child(gear)
	await get_tree().process_frame
	var curse := ""
	for r in BWData.table("enchantments"):
		if BWEffects.cursed(r):
			curse = str(r.id)
			break
	var it: Dictionary = (u.equipment.get("head", { "slot": "head", "tier": "E", "stats": {} }) as Dictionary).duplicate()
	it["enchant"] = curse
	u.equipment["head"] = it
	gear.changed.emit()                           # a cursed piece put on
	_mark("cursed_equip")

	await _until(48.0)
	await _swap(Control.new())
	BWMusic.play("tutorial")
	_mark("tutorial")

	await _until(57.0)
	BWMusic.play("combat")
	_mark("combat")
	await _until(62.0)
	BWMusic.set_intensity(2)
	_mark("intensity_2")

	await _until(67.0)
	BWMusic.play("boss")
	_mark("boss")

	await _until(75.0)
	BWMusic.sting("jackpot")
	_mark("jackpot")
	await _until(79.0)
	BWMusic.sting("victory")
	_mark("victory")
	await _until(83.0)
	BWMusic.sting("defeat")
	_mark("defeat")

	await _until(87.0)
	_finish("capture_drop2", SECTIONS_DROP2)


## D394: the placeholder run. The short pick reveal through a real picker
## (the director's hook, faded when it closes), then every ph_* sound's
## first variation over the combat bed, 1.6 s apart (the loops for 3 s,
## then stopped), at its in-game mix level (2D: the file and mix, not the
## 3D distance). tools/audio/analyse_placeholders.py finds each one.
const PH_ORDER := ["ph_swap_holster", "ph_swap_draw", "ph_proc_onkill", "ph_proc_heal", "ph_proc_pity", "ph_immune",
	"ph_obelisk_push", "ph_obelisk_pull", "ph_colossus_step", "ph_colossus_thrust", "ph_blank_step", "ph_fan_knives",
	"ph_cast_fire", "ph_cast_water", "ph_cast_ice", "ph_cast_thunder", "ph_cast_wind", "ph_cast_light", "ph_cast_dark",
	"ph_horde_shuffle", "ph_being_hum"]

func _run_placeholders() -> void:
	await _begin()
	var ids := BWData.table("roster").slice(0, 6).map(func(r): return str(r.id))
	var run := BWRun.start(ids, 99)
	var blank := Control.new()
	await _swap(blank)
	BWMusic.play("rest")
	_mark("rest")
	await _until(4.0)
	var u: BWUnit = run.squad[0]
	var picker := BWPicker.new(u, { "kind": "perk", "element": u.element, "rank": 2 }, "capture")
	blank.add_child(picker)
	_mark("picker_open")
	await _until(8.0)
	picker.queue_free()
	_mark("picker_close")
	await _until(9.0)
	BWMusic.play("combat")
	_mark("combat")
	var t := 12.0
	for n in PH_ORDER:
		await _until(t)
		if BWSfx.info(n).get("loop", false):
			var p := BWSfx.play(n, null, { "variant": 1, "stack": true, "tag": "ph", "loop": true })
			_mark(n)
			await _until(t + 3.0)
			BWSfx.loop_stop(p, 0.15)
			t += 4.0
		else:
			BWSfx.play(n, null, { "variant": 1, "stack": true, "tag": "ph" })
			_mark(n)
			t += 1.6
	await _until(t + 1.0)
	_finish("capture_ph", [["sync", 0.0], ["rest", 1.5], ["combat", 9.0], ["end", t + 1.0]])


## BWMusic's log, made JSON-safe (decks are objects).
func _music_log() -> Array:
	var out: Array = []
	for e in BWMusic.events:
		var c := {}
		for k in e:
			var v: Variant = e[k]
			c[k] = v if typeof(v) in [TYPE_STRING, TYPE_FLOAT, TYPE_INT, TYPE_BOOL] else str(v)
		out.append(c)
	return out
