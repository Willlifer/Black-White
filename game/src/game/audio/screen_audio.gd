class_name BWScreenAudio
extends Node
## The moments of the title, roster and downtime screens, watched rather
## than called (the screens stay audio-free; BWAudioDirector attaches this):
##   title     "press any button" -> confirm
##   roster    the highlight moves -> hover tick; a pick -> pick; an unpick ->
##             cancel; begin -> confirm (the button does that)
##   downtime  the day starts progressing -> the progress swell
##   results / loading   any key continues -> confirm (no button, D75)
##   roster    a portrait-slot click unpicks -> cancel (via _chosen, as above)
##   prebattle the selection moves -> hover tick; a unit ticked -> pick, unticked
##             -> cancel; a placement drag lifts -> click; a drop lands -> pick
## Reads the screens' own state each frame; a renamed field just goes quiet.

var screen: Node
var _sel: Variant = null
var _chosen := -1
var _input_on := true
var _dragging := false
var _drops := 0


func _ready() -> void:
	screen = get_parent()
	if screen is BWTitleScreen and screen.has_signal("done"):
		screen.connect("done", func(_c): BWSfx.ui("ui_confirm", { "tag": "title" }))
	# Results and the loading screen have no buttons (D75): their "any key"
	# is the confirm the old Continue button made.
	if (screen is BWResultsScreen or screen is BWLoadingScreen) and screen.has_signal("done"):
		screen.connect("done", func(): BWSfx.ui("ui_confirm", { "tag": "continue" }))
	_sel = screen.get("_sel")
	var ch: Variant = screen.get("_chosen")
	if ch == null:
		ch = screen.get("_deployed")
	_chosen = (ch as Array).size() if ch is Array else -1
	_input_on = screen.is_processing_unhandled_input()


func _process(_delta: float) -> void:
	if screen is BWRosterScreen:
		var s: Variant = screen.get("_sel")
		if s != null and s != _sel:
			_sel = s
			BWSfx.ui("ui_hover", { "tag": "roster_browse" })
		var ch: Variant = screen.get("_chosen")
		if ch is Array:
			var n := (ch as Array).size()
			if _chosen >= 0 and n > _chosen:
				BWSfx.ui("ui_pick", { "tag": "roster_pick" })
			elif _chosen >= 0 and n < _chosen:
				BWSfx.ui("ui_cancel", { "tag": "roster_unpick" })
			_chosen = n
	elif screen is BWPrebattleScreen:
		var s: Variant = screen.get("_sel")
		if s != null and s != _sel:
			if _sel != null:
				BWSfx.ui("ui_hover", { "tag": "prebattle_select" })
			_sel = s
		var dep: Variant = screen.get("_deployed")
		if dep is Array:
			var n := (dep as Array).size()
			if _chosen >= 0 and n > _chosen:
				BWSfx.ui("ui_pick", { "tag": "prebattle_deploy" })
			elif _chosen >= 0 and n < _chosen:
				BWSfx.ui("ui_cancel", { "tag": "prebattle_bench" })
			_chosen = n
		var d: Variant = screen.get("_drag")
		var lifted: bool = d is Dictionary and not (d as Dictionary).is_empty() and bool((d as Dictionary).get("active", false))
		if lifted and not _dragging:
			BWSfx.ui("ui_click", { "tag": "prebattle_lift" })
		_dragging = lifted
		var drops: Variant = screen.get("_drop_count")
		if drops is int:
			if drops > _drops:
				BWSfx.ui("ui_pick", { "tag": "prebattle_drop" })
			_drops = drops
	elif screen is BWDowntimeScreen:
		var on := screen.is_processing_unhandled_input()
		var go: Variant = screen.get("_go")
		if _input_on and not on and go is BaseButton and (go as BaseButton).disabled:
			BWSfx.ui("progress_day", { "tag": "progress_day" })
		_input_on = on
