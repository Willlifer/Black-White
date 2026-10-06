extends RefCounted
## D171: the Esc stack (BWEsc). Pure: plain objects stand in for windows.


class Win:
	extends RefCounted
	var open := true
	var nudged := 0
	func close() -> void:
		open = false
	func nudge() -> void:
		nudged += 1


func _fresh() -> void:
	BWEsc.clear()
	BWEsc.log_closed.clear()


func test_esc_closes_newest_first(t) -> void:
	_fresh()
	var tip := Win.new()
	var codex := Win.new()
	BWEsc.push(tip, tip.close, { "name": "tooltip", "hover": true })
	BWEsc.push(codex, codex.close, { "name": "codex" })
	t.eq(BWEsc.size(), 2, "two windows on the stack")
	t.eq(BWEsc.top_name(), "codex", "the newest is on top")
	t.eq(BWEsc.escape(), "closed:codex", "Esc closes the newest")
	t.ok(not codex.open and tip.open, "only the codex closed")
	t.eq(BWEsc.escape(), "closed:tooltip", "Esc again closes the tooltip")
	t.ok(not tip.open, "the tooltip closed")
	t.eq(BWEsc.escape(), "", "an empty stack falls through to the screen's own Esc")
	t.eq(BWEsc.log_closed, ["codex", "tooltip"], "closed in order")
	_fresh()


func test_mandatory_pick_only_nudges(t) -> void:
	_fresh()
	var pause := Win.new()
	var pick := Win.new()
	BWEsc.push(pause, pause.close, { "name": "pause" })
	BWEsc.push(pick, Callable(), { "name": "picker", "mandatory": true, "nudge": pick.nudge })
	t.eq(BWEsc.escape(), "nudged:picker", "Esc on an owed pick nudges")
	t.eq(BWEsc.escape(), "nudged:picker", "and keeps nudging")
	t.eq(pick.nudged, 2, "the nudge ran each time")
	t.ok(pause.open, "nothing under the pick closes")
	t.eq(BWEsc.size(), 2, "the pick stays on the stack")
	var tip := Win.new()
	BWEsc.push(tip, tip.close, { "name": "tooltip", "hover": true })
	t.eq(BWEsc.escape(), "closed:tooltip", "a tooltip over the pick still closes")
	BWEsc.remove(pick)
	t.eq(BWEsc.escape(), "closed:pause", "once picked, Esc reaches the pause menu")
	_fresh()


func test_push_again_moves_to_top_and_remove(t) -> void:
	_fresh()
	var a := Win.new()
	var b := Win.new()
	BWEsc.push(a, a.close, { "name": "a" })
	BWEsc.push(b, b.close, { "name": "b" })
	BWEsc.push(a, a.close, { "name": "a" })
	t.eq(BWEsc.names(), ["b", "a"], "re-pushing moves an entry to the top, once")
	BWEsc.remove(a)
	t.eq(BWEsc.names(), ["b"], "remove takes it out")
	t.ok(a.open, "remove doesn't call close")
	_fresh()


func test_hovers_close_together_and_dead_entries_drop(t) -> void:
	_fresh()
	var panel := Win.new()
	var card := Win.new()
	var tip := Win.new()
	BWEsc.push(panel, panel.close, { "name": "shop" })
	BWEsc.push(card, card.close, { "name": "unit card", "hover": true })
	BWEsc.push(tip, tip.close, { "name": "tooltip", "hover": true })
	t.eq(BWEsc.close_hovers(), 2, "the mouse leaving closes every hover card and tooltip")
	t.ok(not card.open and not tip.open and panel.open, "panels stay")
	t.eq(BWEsc.names(), ["shop"], "only the panel is left")
	var gone := Win.new()
	BWEsc.push(gone, gone.close, { "name": "gone" })
	gone = null                                  # freed (RefCounted)
	t.eq(BWEsc.names(), ["shop"], "a freed window drops off the stack")
	var n := Node.new()                          # a node registers once it is in the tree
	BWEsc.push(n, Callable(), { "name": "orphan" })
	t.eq(BWEsc.names(), ["shop"], "a node outside the tree never blocks Esc")
	n.free()
	_fresh()


func test_damage_tag_has_one_sign(t) -> void:
	t.eq(BWBlastPreview.damage_text(96, false), "−96", "exact damage: a minus")
	t.eq(BWBlastPreview.damage_text(96, true), "≈96", "an expected value: ≈ instead of the minus, never ~−96")


## D172: display names start with a capital (sentence case), ids don't change.
func test_display_labels(t) -> void:
	t.eq(BWText.weapon("sword"), "Sword", "a weapon class reads Sword")
	t.eq(BWText.weapon("daggers"), "Daggers", "Daggers")
	t.eq(BWText.label("unfriendly"), "Unfriendly", "friendliness")
	t.eq(BWText.label("water 2"), "Water 2", "an element with a level")
	t.eq(BWText.label("high_and_tight"), "High and tight", "sentence case, not title case")
	t.eq(BWText.label("Fan of Knives"), "Fan of Knives", "a proper name is left alone")
	t.eq("%s (%s)" % [BWText.weapon("lance"), "E"], "Lance (E)", "the unit card's weapon line")
