class_name BWAudioDirector
extends Node
## Attaches sound to the game by listening, so no screen has to know about
## audio: it watches the scene tree (SceneTree.node_added) and
##   - every BaseButton: hover tick on mouse-over / focus, and on press a
##     confirm, cancel or plain click by its label
##   - every BWUnitView: a BWUnitAudio child (animation markers -> sound)
##   - every BWCombatScreen: a BWCombatAudio child (battle events -> sound)
##   - title, roster and downtime screens: a small watcher for their moments
##     (start, browse, pick, progress the day)
## One instance, under the root (BWAudio.ensure makes it).

const CONFIRM_WORDS: PackedStringArray = ["begin", "confirm", "lock", "progress", "continue", "start", "done", "ok",
	"yes", "next", "attack", "accept", "equip", "deploy", "trade", "buy", "proceed", "fight"]
const CANCEL_WORDS: PackedStringArray = ["back", "cancel", "clear", "undo", "close", "remove", "unequip", "wait", "end turn"]
const HOVER_GAP := 0.05

static var _inst: BWAudioDirector
var _last_hover := -1.0


static func ensure(_parent: Node = null) -> void:
	if _inst != null and is_instance_valid(_inst):
		return
	_inst = BWAudioDirector.new()
	_inst.name = "BWAudioDirector"
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child.call_deferred(_inst)


func _ready() -> void:
	get_tree().node_added.connect(_on_node)
	_scan(get_tree().root)


func _scan(n: Node) -> void:
	_on_node(n)
	for c in n.get_children():
		_scan(c)


func _on_node(n: Node) -> void:
	if n is BaseButton:
		_hook_button(n as BaseButton)
	elif n is BWUnitView:
		_attach(n, func(): return BWUnitAudio.new(), BWUnitAudio)
	elif n is BWCombatScreen:
		_attach(n, func(): return BWCombatAudio.new(), BWCombatAudio)
	elif n is BWTitleScreen or n is BWRosterScreen or n is BWDowntimeScreen or n is BWResultsScreen or n is BWLoadingScreen or n is BWPrebattleScreen:
		_attach(n, func(): return BWScreenAudio.new(), BWScreenAudio)


func _attach(n: Node, make: Callable, cls: Variant) -> void:
	if n.has_meta("bw_audio"):
		return
	n.set_meta("bw_audio", true)
	var add := func():
		if is_instance_valid(n) and n.is_inside_tree():
			var c: Node = make.call()
			c.name = "Audio"
			n.add_child(c)
	add.call_deferred()


func _hook_button(b: BaseButton) -> void:
	if b.has_meta("bw_audio"):
		return
	b.set_meta("bw_audio", true)
	b.mouse_entered.connect(_hover.bind(b))
	b.focus_entered.connect(_hover.bind(b))
	b.pressed.connect(_press.bind(b))


func _hover(b: BaseButton) -> void:
	if not is_instance_valid(b) or b.disabled or not b.is_visible_in_tree():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hover < HOVER_GAP:
		return
	_last_hover = now
	BWSfx.ui("ui_hover", { "tag": "hover" })


func _press(b: BaseButton) -> void:
	if not is_instance_valid(b):
		return
	_last_hover = Time.get_ticks_msec() / 1000.0          # a click's focus change isn't a hover
	BWSfx.ui(press_sound(b.get("text") if "text" in b else ""), { "tag": "press" })


## The sound a button makes by its label: confirm, cancel or a plain click.
static func press_sound(label: Variant) -> String:
	var t := str(label if label != null else "").to_lower()
	for w in CANCEL_WORDS:
		if t.contains(w):
			return "ui_cancel"
	for w in CONFIRM_WORDS:
		if t.contains(w):
			return "ui_confirm"
	return "ui_click"
