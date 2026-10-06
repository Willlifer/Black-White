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
