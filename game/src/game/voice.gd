class_name BWVoice
## Plays a bark clip at the speaker's voice pitch (roster `voice_pitch`), so
## twelve recordings become twenty voices (brief: "pitch modulated character
## sounds"). Barks go to the Voice bus, which ducks the music a little
## (BWAudio: a compressor on Music sidechained by Voice).
##
## Phase 6 (measured, design/audio/AUDIO.md): the recordings carry 0.4-0.9 s
## of silence before the voice and sit 25 dB apart in level. CLIPS holds each
## one's start (10% of peak, minus 50 ms) and a gain to about -20 dBFS RMS
## over the voiced part, so a bark speaks on cue and at an even level.
## Replacing a recording: drop the new WAV over the old name and re-measure
## (tools/audio/README in AUDIO.md), or set its row to [0.0, 0.0].

## clip -> [start seconds, gain dB]
const CLIPS := {
	"dying": [0.465, -2.5],
	"hey": [0.737, 6.6],
	"hiyah": [0.834, -5.9],
	"hmm": [0.928, 6.3],
	"laugh": [0.533, -0.6],
	"mmhmm": [0.490, 6.5],
	"no": [0.581, 16.5],
	"oof": [0.720, -2.6],
	"oogh": [0.806, -0.2],
	"ouch_grunt": [0.435, 4.6],
	"yah": [0.543, -2.1],
	"yeah": [0.412, 0.7],
}
const BUS := "Voice"

static var log_enabled := false
static var events: Array = []


static func key(clip: String) -> String:
	return clip.to_lower().replace(" ", "_")


static func say(parent: Node, clip: String, pitch: float, db: float = -4.0) -> AudioStreamPlayer:
	var path := BWBarks.clip_path(clip)
	if parent == null or not parent.is_inside_tree() or not ResourceLoader.exists(path):
		return null
	var row: Array = CLIPS.get(key(clip), [0.0, 0.0])
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.volume_db = db + float(row[1])
	p.bus = BUS
	parent.add_child(p)
	p.play(float(row[0]))
	p.finished.connect(p.queue_free)
	if log_enabled:
		events.append({ "clip": key(clip), "pitch": p.pitch_scale, "usec": Time.get_ticks_usec(), "frame": Engine.get_process_frames() })
	return p


## A short effort sound (hit grunts, strike shouts): the same clip table,
## a little quieter than a line of dialogue, cut after `max_s`.
static func grunt(parent: Node, clip: String, pitch: float, db: float = -7.0, max_s: float = 0.7) -> AudioStreamPlayer:
	var p := say(parent, clip, pitch, db)
	if p:
		var tw := p.create_tween()
		tw.tween_interval(maxf(max_s / maxf(p.pitch_scale, 0.1) - 0.12, 0.05))
		tw.tween_property(p, "volume_db", -60.0, 0.12)
		tw.tween_callback(p.queue_free)
	return p
