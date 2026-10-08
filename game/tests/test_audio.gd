extends RefCounted
## Phase 6 audio (design/audio/AUDIO.md): every sound the code asks for
## exists, the music layers are equal-length sample-aligned loops, the bus
## layout, the cue tables, and no WAV we ship clips. Reads the WAV files
## themselves (RIFF), not just Godot's imports.

const SRC_DIRS := ["res://src/game/", "res://src/game/audio/", "res://src/game/combat/", "res://src/game/screens/"]
const SFX_PREFIXES := ["swing_", "hit_", "bow_", "arrow_", "pistol_", "flintlock_", "cast_", "bolt_", "channel_",
	"elem_", "heal", "tile_", "step_", "ko_", "ui_", "sting_", "progress_", "shop_", "ph_"]
const ELEMENTS := ["fire", "water", "ice", "thunder", "wind", "dark", "light"]
const CEIL := 0.8913          # -1 dBFS


## Minimal RIFF reader: { rate, channels, bits, frames, data_offset, ok }.
static func wav_info(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 44:
		return { "ok": false }
	if f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return { "ok": false }
	f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		return { "ok": false }
	var out := { "ok": false }
	while f.get_position() + 8 <= f.get_length():
		var id := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		var at := f.get_position()
		if id == "fmt ":
			f.get_16()
			out.channels = f.get_16()
			out.rate = f.get_32()
			f.get_32()
			f.get_16()
			out.bits = f.get_16()
		elif id == "data":
			out.data_offset = at
			out.data_size = size
			out.frames = size / maxi(1, int(out.get("channels", 1)) * int(out.get("bits", 16)) / 8)
			out.ok = out.has("rate")
		f.seek(at + size + (size & 1))
	return out


## Peak |sample| (0..1) of a 16-bit PCM WAV, every sample.
static func wav_peak(path: String) -> float:
	var info := wav_info(path)
	if not info.ok or int(info.bits) != 16:
		return 99.0
	var f := FileAccess.open(path, FileAccess.READ)
	f.seek(int(info.data_offset))
	var buf := f.get_buffer(int(info.data_size))
	if buf.size() % 4 != 0:                                            # an odd count of mono samples
		buf.resize(buf.size() + 4 - buf.size() % 4)
	var ints := buf.to_int32_array()     # two 16-bit samples per int
	var m := 0
	for v in ints:
		var lo := v & 0xFFFF
		if lo >= 32768:
			lo -= 65536
		var hi := v >> 16
		m = maxi(m, maxi(absi(lo), absi(hi)))
	return m / 32768.0


static func _first_last(path: String) -> Array:
	var info := wav_info(path)
	var f := FileAccess.open(path, FileAccess.READ)
	var fb := int(info.channels) * 2
	f.seek(int(info.data_offset))
	var a := f.get_buffer(fb)
	f.seek(int(info.data_offset) + int(info.data_size) - fb)
	var b := f.get_buffer(fb)
	return [a.decode_s16(0) / 32768.0, b.decode_s16(0) / 32768.0]


static func _sources() -> Array:
	var out: Array = []
	for d in SRC_DIRS:
		for fn in DirAccess.get_files_at(d):
			if fn.ends_with(".gd"):
				out.append(d + fn)
	return out


## Every SFX name written as a string literal in the game's scripts.
static func referenced_sfx() -> Dictionary:
	var names := {}
	var re := RegEx.new()
	re.compile("\"([a-z_]+)\"")
	for path in _sources():
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			var s := m.get_string(1)
			for p in SFX_PREFIXES:
				if s.begins_with(p) and not s.ends_with("_"):
					names[s] = path.get_file()
	for e in ELEMENTS:
		names["elem_" + e] = "unit_audio.gd (\"elem_\" + element)"
	return names


func test_every_referenced_sfx_exists(c) -> void:
	var refs := referenced_sfx()
	var manifest: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(BWSfx.MANIFEST)) as Dictionary).get("sounds", {})
	c.ok(manifest.size() >= 39, "manifest lists the sound set (%d)" % manifest.size())
	var checked := 0
	for n in refs:
		if not manifest.has(n):
			if n.begins_with("hit_") or n.begins_with("ui_") or n.begins_with("elem_") or BWSfx.MIX.has(n):
				c.ok(false, "%s (used in %s) is in sfx.json" % [n, refs[n]])
			continue
		var count := int(manifest[n].variants)
		c.ok(count >= 2 or int(manifest[n].get("drop", 0)) > 0 or bool(manifest[n].get("placeholder", false)), "%s has 2+ variations, or is an author drop / a placeholder loop (%d)" % [n, count])
		for v in range(1, count + 1):
			var p := BWSfx.path_of(n, v)
			c.ok(FileAccess.file_exists(p), "file %s" % p)
			c.ok(ResourceLoader.exists(p), "imported %s" % p)
			checked += 1
	for n in BWSfx.MIX:
		c.ok(manifest.has(n), "mixed sound %s exists" % n)
	for n in manifest:
		# a C alternate (D412) mixes like the sound it stands in for
		c.ok(BWSfx.MIX.has(str(manifest[n].get("alt_of", n))), "sound %s has a mix level" % n)
	c.ok(checked >= 80, "checked %d variation files" % checked)


func test_sfx_files_are_clean(c) -> void:
	var manifest: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(BWSfx.MANIFEST)) as Dictionary).get("sounds", {})
	for n in manifest:
		for v in range(1, int(manifest[n].variants) + 1):
			var p := ProjectSettings.globalize_path(BWSfx.path_of(n, v))
			var info := wav_info(p)
			c.ok(info.ok and int(info.rate) == 44100 and int(info.bits) == 16, "%s_%d is 44.1 kHz 16-bit" % [n, v])
			var pk := wav_peak(p)
			c.ok(pk <= CEIL, "%s_%d peak %.3f <= -1 dBFS" % [n, v, pk])
			var lv: Dictionary = (manifest[n].levels as Array)[v - 1]
			c.ok(absf(float(lv.loudness) - float((JSON.parse_string(FileAccess.get_file_as_string(BWSfx.MANIFEST)) as Dictionary).target_loudness)) <= 1.5,
				"%s_%d loudness %.1f near target" % [n, v, float(lv.loudness)])
	var loop := ProjectSettings.globalize_path(BWSfx.path_of("channel_loop", 1))
	var fl := _first_last(loop)
	c.ok(absf(fl[0] - fl[1]) < 0.02, "channel loop meets itself (%.4f)" % absf(fl[0] - fl[1]))


func test_music_layers_are_aligned_loops(c) -> void:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BWMusic.MANIFEST))
	c.ok(info is Dictionary and info.has("sets"), "layers.json")
	for set_name in BWMusic.SETS:
		var want := int(BWMusic.SET_SAMPLES[set_name])
		c.eq(int(info.sets[set_name].samples), want, "%s: layers.json length = BWMusic.SET_SAMPLES" % set_name)
		if set_name in BWMusic.FREE:
			c.ok(bool(info.sets[set_name].get("free", false)), "%s: a free-tempo phrase loop (D239)" % set_name)
			c.eq((BWMusic.SETS[set_name] as Array).size(), 1, "%s: one layer" % set_name)
		else:
			var bpm := 120.0 * 705600.0 / want
			c.near(float(info.sets[set_name].bpm), bpm, 0.01, "%s bpm" % set_name)
		var lengths := {}
		for layer in BWMusic.SETS[set_name]:
			var res_path := BWMusic.layer_path(set_name, layer)
			var p := ProjectSettings.globalize_path(res_path)
			var w := wav_info(p)
			c.ok(w.ok, "%s/%s is a WAV" % [set_name, layer])
			if not w.ok:
				continue
			c.eq(int(w.rate), 44100, "%s/%s rate" % [set_name, layer])
			c.eq(int(w.channels), 2, "%s/%s stereo" % [set_name, layer])
			c.eq(int(w.frames), want, "%s/%s is exactly 8 bars (%d samples)" % [set_name, layer, want])
			lengths[layer] = int(w.frames)
			var st: AudioStream = load(res_path)
			c.near(st.get_length(), want / 44100.0, 0.001, "%s/%s imports at the same length" % [set_name, layer])
			var fl := _first_last(p)
			c.ok(absf(fl[0] - fl[1]) < 0.06, "%s/%s seam step %.4f" % [set_name, layer, absf(fl[0] - fl[1])])
			var pk := wav_peak(p)
			c.ok(pk <= CEIL, "%s/%s peak %.3f <= -1 dBFS" % [set_name, layer, pk])
		var vals := lengths.values()
		c.ok(not vals.is_empty() and vals.all(func(x): return x == vals[0]), "%s: all layers the same length (sample-aligned)" % set_name)
	# the tempo sets keep the 8-bar grid: boss is a +8..12% lift, slow is slower
	var boss_up := float(BWMusic.SET_SAMPLES.main) / float(BWMusic.SET_SAMPLES.boss) - 1.0
	c.ok(boss_up >= 0.08 and boss_up <= 0.12, "boss tempo +%.1f%%" % (boss_up * 100))
	c.ok(BWMusic.SET_SAMPLES.slow > BWMusic.SET_SAMPLES.main, "roster/rest set is slower")


func test_bus_layout(c) -> void:
	BWAudio.ensure_buses()
	BWAudio.ensure_buses()                 # idempotent
	for b in BWAudio.BUSES:
		c.ok(AudioServer.get_bus_index(b) >= 0, "bus %s" % b)
	c.eq(AudioServer.get_bus_index("Master"), 0, "Master is bus 0")
	for b in BWAudio.SEND:
		var i := AudioServer.get_bus_index(b)
		c.eq(str(AudioServer.get_bus_send(i)), str(BWAudio.SEND[b]), "%s sends to %s" % [b, BWAudio.SEND[b]])
		c.ok(AudioServer.get_bus_index(BWAudio.SEND[b]) < i, "%s sends left" % b)
	var lim := BWAudio.effect("Master", "AudioEffectHardLimiter") as AudioEffectHardLimiter
	c.ok(lim != null and lim.ceiling_db <= -0.99, "Master limiter at -1 dB")
	var comp := BWAudio.effect("Music", "AudioEffectCompressor") as AudioEffectCompressor
	c.ok(comp != null and str(comp.sidechain) == "Voice", "Music ducks under Voice (sidechain)")
	c.ok(BWAudio.effect("Music", "AudioEffectAmplify") != null, "Music has the sting duck")
	c.ok(BWAudio.effect("MusicStretch", "AudioEffectPitchShift") != null, "MusicStretch has the tempo compensation")
	var n := 0
	for k in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, k) is AudioEffectHardLimiter:
			n += 1
	c.eq(n, 1, "one limiter after two ensures")
	# per-bus volume setting
	var before := BWAudio.get_volume("SFX")
	BWAudio.set_volume("SFX", 0.5)
	c.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), float(BWAudio.BASE_DB.SFX) + linear_to_db(0.5), 0.01, "SFX at 0.5")
	BWAudio.set_volume("SFX", 0.0)
	c.ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "volume 0 mutes")
	BWAudio.set_volume("SFX", before)
	c.near(BWAudio.get_volume("SFX"), before, 0.0001, "restored")


func test_cue_tables(c) -> void:
	for cue in ["title", "roster", "prebattle", "rest", "rooms", "tutorial", "combat", "boss"]:
		c.ok(BWMusic.CUES.has(cue), "cue %s" % cue)
	for cue in BWMusic.CUES:
		var set_name := str(BWMusic.CUES[cue].set)
		c.ok(BWMusic.SETS.has(set_name), "%s uses a real set" % cue)
		for l in BWMusic.CUES[cue].mix:
			c.ok(l in BWMusic.SETS[set_name], "%s: layer %s is in set %s" % [cue, l, set_name])
		var mix := BWMusic.cue_mix(cue)
		c.eq(mix.size(), (BWMusic.SETS[set_name] as Array).size(), "%s: a level for every layer" % cue)
		var on := 0
		for l in mix:
			c.ok(float(mix[l]) <= BWMusic.MAX_DB and float(mix[l]) >= BWMusic.OFF_DB, "%s/%s in range" % [cue, l])
			if float(mix[l]) > 0.0:
				c.ok(set_name in BWMusic.FREE or l in ["low_beat", "kick"], "%s/%s: only a drop-2 solo layer is pushed above 0 dB" % [cue, l])
			if float(mix[l]) > BWMusic.OFF_DB:
				on += 1
		c.ok(on >= 1, "%s plays something" % cue)
	# D239: the author's drop 2 takes the title, the hall, the tutorial, the rooms and the pre-battle
	c.eq(str(BWMusic.CUES.title.set), "arpeggio", "title: MainTheme Arpeggio")
	c.eq(str(BWMusic.CUES.rest.set), "chillin", "rest (the hall): chillin main theme")
	c.eq(str(BWMusic.CUES.tutorial.set), "moderato", "tutorial: moderato main loopish")
	c.eq(str(BWMusic.CUES.rooms.set), "rooms", "rooms: Music Rooms")
	for l in BWMusic.cue_mix("prebattle"):
		c.ok((float(BWMusic.cue_mix("prebattle")[l]) > BWMusic.OFF_DB) == (l in ["low_beat", "kick"]),
			"prebattle: only Low Beat and the kick (its C/E bass clashes with the loop's F# bars): %s" % l)
	c.ok(float(BWMusic.cue_mix("combat", 2).kick) > BWMusic.OFF_DB and float(BWMusic.cue_mix("combat", 1).kick) <= BWMusic.OFF_DB, "combat: the kick joins at intensity 2")
	c.ok(float(BWMusic.cue_mix("boss").kick) > BWMusic.OFF_DB, "boss: the kick")
	c.eq(str(BWMusic.CUES.roster.set), "slow", "roster: slowed")
	c.ok(float(BWMusic.cue_mix("prebattle").drums) <= BWMusic.OFF_DB, "no drumline before the fight")
	c.eq(float(BWMusic.cue_mix("combat").drums), 0.0, "combat: the drums come in")
	c.eq(str(BWMusic.CUES.combat.set), "battle", "combat: the slower 108 BPM set (author 10/4)")
	c.eq(str(BWMusic.CUES.boss.set), "boss", "boss: the +10% set")
	var boss_on := BWMusic.cue_mix("boss").values().filter(func(v): return v > BWMusic.OFF_DB).size()
	c.ok(boss_on >= 5, "boss: nearly every layer (%d)" % boss_on)
	# combat intensity only ever adds energy
	var steps: Array = BWMusic.CUES.combat.intensity
	c.eq(steps.size(), 3, "three combat intensities")
	for k in range(1, 3):
		var a := BWMusic.cue_mix("combat", k - 1)
		var b := BWMusic.cue_mix("combat", k)
		for l in a:
			c.ok(float(b[l]) >= float(a[l]), "intensity %d -> %d: %s does not drop" % [k - 1, k, l])
	c.ok(BWMusic.runtime_rate("boss") > 1.08 and BWMusic.runtime_rate("slow") < 0.9, "runtime tempo rates")
	for k in BWMusic.STINGS:
		c.ok(BWSfx.variants(BWMusic.STINGS[k]) >= 1, "sting %s exists" % k)
	for k in ["victory", "defeat", "level_up", "pick", "room_hard", "jackpot", "cursed"]:
		c.ok(BWMusic.STINGS.has(k), "sting %s is mapped (D240)" % k)


## D239-D241: the author's drop 2. Stings start on cue (no leading silence),
## carry a body length for the duck, and the screen hooks read their state.
func test_drop2(c) -> void:
	var manifest: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(BWSfx.MANIFEST)) as Dictionary).get("sounds", {})
	var drops := 0
	for n in manifest:
		if int(manifest[n].get("drop", 0)) != 2 or manifest[n].has("cut_of") or manifest[n].has("alt_of"):
			continue
		drops += 1
		var lv: Dictionary = (manifest[n].levels as Array)[0]
		c.ok(float(lv.get("body_s", 0.0)) > 0.5 and float(lv.body_s) <= float(lv.seconds), "%s: body %.2f s of %.2f" % [n, float(lv.get("body_s", 0.0)), float(lv.seconds)])
		var p := ProjectSettings.globalize_path(BWSfx.path_of(n, 1))
		c.ok(head_peak(p, 0.03) > 0.01, "%s: sound within 30 ms of the start (lead trimmed)" % n)
		c.eq(str(manifest[n].bus), "UI", "%s on the UI bus" % n)
	c.eq(drops, 6, "six drop-2 one-shots")
	for k in BWMusic.FREE:
		c.ok(not BWMusic.CUES.values().filter(func(q): return str(q.set) == k).is_empty(), "%s is used by a cue" % k)
	# results: one sting when anyone levelled, none otherwise
	c.ok(BWScreenAudio.leveled({ "levels": { "a": { "str": 1 }, "b": {} } }), "a level-up report stings")
	c.ok(not BWScreenAudio.leveled({ "levels": { "a": {} } }), "no gains, no sting")
	c.ok(not BWScreenAudio.leveled(null), "no report, no sting")
	# the cursed count the gear and shop hooks compare
	var curse := ""
	for r in BWData.table("enchantments"):
		if BWEffects.cursed(r):
			curse = str(r.id)
			break
	c.ok(curse != "", "a cursed enchantment exists in the data")
	var run := BWRun.start(BWData.table("roster").slice(0, 6).map(func(r): return str(r.id)), 7)
	var before := BWAudioDirector.worn_cursed(run)
	var u: BWUnit = run.squad[0]
	var it: Dictionary = (u.equipment.get("head", { "slot": "head", "tier": "E", "stats": {} }) as Dictionary).duplicate()
	var was_cursed := str(it.get("enchant", "")) != "" and BWEffects.cursed(str(it.enchant))
	it["enchant"] = curse
	u.equipment["head"] = it
	c.eq(BWAudioDirector.worn_cursed(run), before + (0 if was_cursed else 1), "a cursed piece put on counts")
	c.eq(BWAudioDirector.worn_cursed(null), 0, "no run, no count")


## D392/D393: the short pick reveal and the ph_* placeholders for AUDIO-NEEDS'
## "still missing" list: present, levelled, trimmed, looped cleanly, and wired.
const PLACEHOLDERS := ["ph_swap_holster", "ph_swap_draw", "ph_proc_onkill", "ph_proc_heal", "ph_proc_pity", "ph_immune",
	"ph_obelisk_push", "ph_obelisk_pull", "ph_colossus_step", "ph_colossus_thrust", "ph_horde_shuffle", "ph_being_hum",
	"ph_blank_step", "ph_cast_fire", "ph_cast_water", "ph_cast_ice", "ph_cast_thunder", "ph_cast_wind", "ph_cast_light",
	"ph_cast_dark", "ph_fan_knives"]

func test_placeholders(c) -> void:
	var manifest: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(BWSfx.MANIFEST)) as Dictionary).get("sounds", {})
	for n in PLACEHOLDERS:
		c.ok(manifest.has(n) and bool(manifest[n].get("placeholder", false)), "%s is in sfx.json, marked a placeholder" % n)
		c.ok(BWSfx.MIX.has(n), "%s has a mix level" % n)
		if not manifest.has(n):
			continue
		for v in range(1, int(manifest[n].variants) + 1):
			var p := ProjectSettings.globalize_path(BWSfx.path_of(n, v))
			if bool(manifest[n].loop):
				var fl := _first_last(p)
				c.ok(absf(fl[0] - fl[1]) < 0.05, "%s_%d loop meets itself (%.4f)" % [n, v, absf(fl[0] - fl[1])])
			else:
				# the inward swells (pull, dark collapse) rise from quiet by design: sound, not silence, at the head
				var floor := 0.0005 if n in ["ph_obelisk_pull", "ph_cast_dark"] else 0.01
				c.ok(head_peak(p, 0.03) > floor, "%s_%d: onset trimmed" % [n, v])
	for n in manifest:
		if str(n).begins_with("ph_"):
			c.ok(str(manifest[n].get("alt_of", n)) in PLACEHOLDERS, "%s is a listed placeholder" % n)
	# the pick cards get the short cut, the long take stays mapped
	c.eq(str(BWMusic.STINGS.pick), "sting_pick_short", "pick cards: the short pick reveal (D392)")
	c.eq(str(BWMusic.STINGS.pick_long), "sting_pick_reveal", "the 7 s pick reveal stays mapped")
	var lv: Dictionary = (manifest.sting_pick_short.levels as Array)[0]
	c.ok(float(lv.seconds) <= 2.5 and float(lv.seconds) >= 1.5, "short pick reveal %.2f s (<= 2.5)" % float(lv.seconds))
	# the stings are the author's files (retuned to A, D412), not cuts
	for k in ["victory", "defeat", "jackpot", "cursed", "level_up", "room_hard", "shop"]:
		c.ok(not manifest[BWMusic.STINGS[k]].has("cut_of") and int(manifest[BWMusic.STINGS[k]].get("drop", 0)) == 2, "sting %s is the author's file" % k)
	# hooks
	c.eq(BWCombatAudio.proc_kind("Death Knell: 10% burst around X"), "onkill", "Death Knell -> on-kill")
	c.eq(BWCombatAudio.proc_kind("Relentless: attack again"), "onkill", "Relentless -> on-kill")
	c.eq(BWCombatAudio.proc_kind("Fire spreads"), "onkill", "Wake of Ash -> on-kill")
	c.eq(BWCombatAudio.proc_kind("Graze: 3"), "pity", "Graze -> pity")
	c.eq(BWCombatAudio.proc_kind("Steady Hand: next attack can't miss"), "pity", "Steady Hand -> pity")
	c.eq(BWCombatAudio.proc_kind("Follow-Through: next strike x2"), "pity", "Follow-Through -> pity")
	c.eq(BWCombatAudio.proc_kind("Bulwark: 9 → 6"), "", "other enchant text -> no proc sound")
	var caster := BWUnit.new()
	caster.element = "fire"
	c.eq(BWCombatAudio.big_cast_element({ "skill": "flash_freeze", "element": "", "hexes": [] }, caster), "ice", "Flash Freeze: a big ice cast")
	c.eq(BWCombatAudio.big_cast_element({ "skill": "lunge", "element": "fire", "hexes": [Vector2i(0, 0)] }, caster), "", "a sword lunge is no cast")
	for e in BWCombatAudio.ELEMENTS:
		c.ok(manifest.has("ph_cast_" + e), "a big-cast release for %s" % e)
	for src in ["res://src/game/combat/combat_screen.gd", "res://src/game/audio/unit_audio.gd"]:
		var t := FileAccess.get_file_as_string(src)
		c.ok(t.contains("ph_"), "%s plays placeholders" % src.get_file())


## Peak |sample| over the first `sec` seconds of a 16-bit WAV.
static func head_peak(path: String, sec: float) -> float:
	var info := wav_info(path)
	if not info.ok:
		return 0.0
	var f := FileAccess.open(path, FileAccess.READ)
	f.seek(int(info.data_offset))
	var n := int(sec * int(info.rate)) * int(info.channels)
	var b := f.get_buffer(n * 2)
	var m := 0.0
	for i in range(0, b.size() - 1, 2):
		m = maxf(m, absf(b.decode_s16(i) / 32768.0))
	return m


func test_barks_and_hooks(c) -> void:
	# every bark clip the data uses has an onset/gain row, and the file
	var clips := {}
	for row in BWData.table("barks"):
		clips[BWVoice.key(str(row.voice_clip))] = true
	for k in BWUnitAudio.HIT_GRUNTS:
		clips[k] = true
	for k in BWUnitAudio.STRIKE_SHOUTS:
		clips[k] = true
	for v in BWUnitAudio.VARIANT_BARKS:
		for k in BWUnitAudio.VARIANT_BARKS[v].clips:
			clips[k] = true
	for k in clips:
		c.ok(BWVoice.CLIPS.has(k), "bark %s has a start/gain row" % k)
		c.ok(ResourceLoader.exists(BWBarks.clip_path(k)), "bark file %s" % k)
		if BWVoice.CLIPS.has(k):
			var st: AudioStream = load(BWBarks.clip_path(k))
			c.ok(float(BWVoice.CLIPS[k][0]) < st.get_length() - 0.2, "%s starts inside the clip" % k)
	# the reactions lane's variants all have a voice
	var rp: Variant = load("res://src/game/combat/reaction_pick.gd") if ResourceLoader.exists("res://src/game/combat/reaction_pick.gd") else null
	if rp != null and "VARIANTS" in (rp as GDScript).get_script_constant_map():
		for v in (rp as GDScript).get_script_constant_map().VARIANTS:
			c.ok(BWUnitAudio.VARIANT_BARKS.has(v), "reaction %s has a bark" % v)
	else:
		c.ok(BWUnitAudio.VARIANT_BARKS.size() == 5, "variant table ready for the reactions lane")
	# button labels
	c.eq(BWAudioDirector.press_sound("Begin battle"), "ui_confirm", "Begin -> confirm")
	c.eq(BWAudioDirector.press_sound("Back"), "ui_cancel", "Back -> cancel")
	c.eq(BWAudioDirector.press_sound("Shield"), "ui_click", "other -> click")
	c.eq(BWAudioDirector.press_sound(null), "ui_click", "no label -> click")


## D411: the sting duck (the author, 2026-10-08: "fade the existing track
## out, play the jingle, then fade it in"). The pure state machine first.
static func _duck() -> BWMusic.Duck:
	var dk := BWMusic.Duck.new()
	dk.fade_out = BWMusic.DUCK_OUT
	dk.fade_in = BWMusic.DUCK_IN
	dk.floor_db = BWMusic.DUCK_FLOOR_DB
	return dk


## Step `dk` for `secs` at 10 ms; the dB after each step.
static func _run(dk: BWMusic.Duck, secs: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in int(round(secs / 0.01)):
		out.append(dk.step(0.01))
	return out


func test_sting_duck(c) -> void:
	c.ok(BWMusic.DUCK_OUT >= 0.25 and BWMusic.DUCK_OUT <= 0.4, "fades out in 0.25-0.4 s (%.2f)" % BWMusic.DUCK_OUT)
	c.ok(BWMusic.DUCK_IN >= 0.8 and BWMusic.DUCK_IN <= 1.2, "fades back in over 0.8-1.2 s (%.2f)" % BWMusic.DUCK_IN)
	var floor := BWMusic.DUCK_FLOOR_DB
	# one sting: out, held, back in, restored exactly
	var dk := _duck()
	c.eq(dk.step(0.016), 0.0, "idle: the music at full level")
	dk.begin(2.0)
	var a := _run(dk, BWMusic.DUCK_OUT + 0.02)
	c.ok(a[a.size() - 1] <= floor + 0.01, "out within DUCK_OUT (%.1f dB)" % a[a.size() - 1])
	var mono := true
	for i in range(1, a.size()):
		mono = mono and a[i] <= a[i - 1] + 0.0001
	c.ok(mono, "the fade out only falls")
	var b := _run(dk, 2.0 - BWMusic.DUCK_OUT - 0.05)
	c.ok(Array(b).all(func(v): return v <= floor + 0.01), "held out for the sting's hold")
	var r := _run(dk, BWMusic.DUCK_IN + 0.1)
	mono = true
	for i in range(1, r.size()):
		mono = mono and r[i] >= r[i - 1] - 0.0001
	c.ok(mono, "the fade in only rises")
	c.eq(dk.state, BWMusic.Duck.IDLE, "back to idle")
	c.eq(dk.level_db(), 0.0, "restored to exactly 0 dB")
	c.ok(Array(a + b + r).all(func(v): return v <= 0.0), "never above the music's own level")
	# overlap during the hold: the duck extends, no rise in between
	dk = _duck()
	dk.begin(2.0)
	var o1 := _run(dk, 1.0)
	dk.begin(2.0)
	var o2 := _run(dk, 1.95)
	c.ok(Array(o2).all(func(v): return v <= floor + 0.01), "a second sting while held: still out until its own hold ends")
	var o3 := _run(dk, BWMusic.DUCK_IN + 0.1)
	c.eq(o3[o3.size() - 1], 0.0, "then back in, fully")
	# overlap during the fade in: turns around from where it is (no jump up, no stutter)
	dk = _duck()
	dk.begin(1.0)
	_run(dk, 1.0 + BWMusic.DUCK_IN * 0.5)
	var mid := dk.level_db()
	c.ok(mid > floor and mid < 0.0, "half way back in (%.1f dB)" % mid)
	dk.begin(1.0)
	var t := _run(dk, BWMusic.DUCK_OUT)
	c.ok(t[0] <= mid + 0.0001, "a sting during the fade in: no step up (%.1f -> %.1f)" % [mid, t[0]])
	mono = true
	for i in range(1, t.size()):
		mono = mono and t[i] <= t[i - 1] + 0.0001
	c.ok(mono and t[t.size() - 1] <= floor + 0.01, "it falls straight back out")
	_run(dk, 1.0 + BWMusic.DUCK_IN + 0.1)
	c.eq(dk.level_db(), 0.0, "and recovers")
	# release (a picker closed): back in early, never stuck
	dk = _duck()
	dk.begin(6.0)
	_run(dk, 0.5)
	dk.release(0.4)
	_run(dk, 0.4 + BWMusic.DUCK_IN + 0.05)
	c.eq(dk.state, BWMusic.Duck.IDLE, "released: back in long before the 6 s hold")
	dk.release(0.0)
	c.eq(dk.state, BWMusic.Duck.IDLE, "a release with nothing ducked does nothing")
	# a very short sting: comes back before it was fully out, smoothly
	dk = _duck()
	dk.begin(0.1)
	var s1 := _run(dk, 0.1 + BWMusic.DUCK_IN)
	c.ok(Array(s1).min() > floor, "a 0.1 s sting only dips (%.1f dB)" % Array(s1).min())
	c.eq(dk.level_db(), 0.0, "and is back")
	# every sting in the manifest has a hold: past its body, within its file
	for k in BWMusic.STINGS:
		var n: String = BWMusic.STINGS[k]
		var lv: Dictionary = (BWSfx.info(n).levels as Array)[0]
		var h := BWMusic.sting_hold(n)
		c.ok(h >= float(lv.body_s) and h <= float(lv.seconds), "%s: hold %.2f s (body %.2f, file %.2f)" % [k, h, float(lv.body_s), float(lv.seconds)])
	c.ok(BWMusic.STINGS.has("shop"), "the shop purchase is a sting (it ducks, D411)")


## D411 on a real BWMusic in the tree: the bus Amplify follows the duck; a
## screen change mid-duck starts the new track on the Music bus, under the
## same duck, and nothing is left silent (a gone sting releases it; leaving
## the tree resets the bus).
func test_sting_duck_in_tree(c) -> void:
	BWAudio.ensure_buses()
	var amp := BWAudio.effect("Music", "AudioEffectAmplify") as AudioEffectAmplify
	c.ok(amp != null, "the Music bus has its Amplify")
	if amp == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var m := BWMusic.new()
	tree.root.add_child(m)
	m.set_process(false)
	m.lead = 0.0                                     # start stings at once (no timer in a synchronous test)
	c.eq(amp.volume_db, 0.0, "a fresh BWMusic starts the bus at 0 dB")
	m._play("rest")
	var rest_deck: BWMusic.Deck = m._active
	var live := AudioStreamPlayer.new()              # stands in for the sting's player (headless: no audio out)
	m.add_child(live)
	m._sting("level_up")
	m._sting_player = live
	for i in 40:
		m._step_duck(0.01)
	c.ok(amp.volume_db <= BWMusic.DUCK_FLOOR_DB + 0.01, "the bus is out under the sting (%.1f dB)" % amp.volume_db)
	# the screen changes mid-duck: the new track starts under the same duck
	m._play("rooms")
	var target: BWMusic.Deck = m._deck("rooms", 1.0)
	m._switch(target, BWMusic.cue_mix("rooms"))
	c.ok(m._active == target and m._active != rest_deck, "the rooms track took over")
	c.eq(str(target.player.bus), "Music", "the new track plays through the ducked bus")
	c.ok(m.duck.active() and m.duck.state != BWMusic.Duck.UP, "the cue change leaves the duck alone")
	var hold := BWMusic.sting_hold("sting_level_up")
	for i in int(hold * 100) + int(BWMusic.DUCK_IN * 100) + 20:
		m._step_duck(0.01)
	c.eq(amp.volume_db, 0.0, "after the sting the new track is at full level")
	c.eq(m.duck.state, BWMusic.Duck.IDLE, "duck idle")
	# a sting whose player is gone can't hold the music out
	m._sting("room_hard")
	m._sting_player = null
	for i in int(BWMusic.DUCK_IN * 100) + 10:
		m._step_duck(0.01)
	c.eq(amp.volume_db, 0.0, "a sting that never played: the music is back within DUCK_IN")
	# a picker closing: the sting fades over 0.8 s and the music starts back half way through it
	var live2 := AudioStreamPlayer.new()
	m.add_child(live2)
	m._sting("pick")
	m._sting_player = live2
	for i in 50:
		m._step_duck(0.01)
	m._stop_sting(0.8, true)
	for i in 30:
		m._step_duck(0.01)
	c.ok(amp.volume_db <= BWMusic.DUCK_FLOOR_DB + 0.01, "the pick closed: still out while its fade starts")
	for i in 10 + int(BWMusic.DUCK_IN * 100) + 5:
		m._step_duck(0.01)
	c.eq(amp.volume_db, 0.0, "then back in, long before the sting's own hold")
	# leaving the tree mid-duck resets the bus
	m._sting("cursed")
	m._sting_player = live
	for i in 40:
		m._step_duck(0.01)
	c.ok(amp.volume_db < -1.0, "ducked again (%.1f dB)" % amp.volume_db)
	tree.root.remove_child(m)
	c.eq(amp.volume_db, 0.0, "BWMusic leaving the tree lifts the duck")
	m.free()


## D412: the stings, the short pick reveal and the procs cut from them play in
## A; the author's C originals ship beside them as <name>_c.
func test_stings_in_a(c) -> void:
	var manifest: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(BWSfx.MANIFEST)) as Dictionary).get("sounds", {})
	c.eq(BWSfx.STING_KEY, "A", "the stings play in A (the author, 2026-10-08)")
	var names := ["ph_proc_onkill", "ph_proc_heal", "ph_proc_pity"]
	for k in BWMusic.STINGS:
		if not BWMusic.STINGS[k] in names:
			names.append(BWMusic.STINGS[k])
	for n in names:
		c.ok(manifest.has(n) and str(manifest[n].get("key", "")) == "A", "%s is in A" % n)
		c.eq(BWSfx.resolve(n), n, "%s plays its A file" % n)
		var alt: String = n + "_c"
		c.ok(manifest.has(alt) and str(manifest[alt].get("alt_of", "")) == n and str(manifest[alt].get("key", "")) == "C", "%s: the C original is kept as %s" % [n, alt])
		if manifest.has(alt):
			c.eq(int(manifest[alt].variants), int(manifest[n].variants), "%s: same variations" % alt)
			for v in range(1, int(manifest[n].variants) + 1):
				c.ok(FileAccess.file_exists(BWSfx.path_of(alt, v)) and ResourceLoader.exists(BWSfx.path_of(alt, v)), "%s_%d imported" % [alt, v])
				# same length to within the trims (the shift keeps duration)
				var la := float((manifest[n].levels as Array)[v - 1].seconds)
				var lc := float((manifest[alt].levels as Array)[v - 1].seconds)
				c.ok(absf(la - lc) <= maxf(0.2, lc * 0.07), "%s_%d: %.2f s vs the original's %.2f s" % [n, v, la, lc])
		if int(manifest.get(n, {}).get("drop", 0)) == 2 and not manifest[n].has("cut_of"):
			c.eq(int((manifest[n].get("retune", {}) as Dictionary).get("semitones", 0)), -3, "%s: -3 semitones" % n)
