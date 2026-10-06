class_name BWText
extends RefCounted
## D172: display names. Data ids stay lowercase ("sword", "high_and_tight");
## everything a player reads starts with a capital. One helper, so a label
## never shows a raw id:
##     BWText.label("unfriendly")   -> "Unfriendly"
##     BWText.label("water 2")      -> "Water 2"
##     BWText.weapon("daggers")     -> "Daggers"  (weapons.csv's name when it has one)


## An id as display text: underscores to spaces, the first letter capital,
## the rest left alone ("high_and_tight" -> "High and tight").
static func label(id: Variant) -> String:
	var s := str(id).replace("_", " ").strip_edges()
	if s == "":
		return s
	return s.left(1).to_upper() + s.substr(1)


## A weapon class ("sword", "daggers") as the player reads it.
static func weapon(wc: Variant) -> String:
	var k := str(wc)
	if k != "" and BWData.has_table("weapons"):
		var n := str(BWData.row("weapons", k).get("name", ""))
		if n != "":
			return label(n)
	return label(k)


## D218: a weapon model's display name, or "" when the model is the class
## itself (a plain "Sword", a "Dagger" of the daggers), so a card says "Sword (E)", never "Sword · Sword (E)".
static func model_name(model: Variant, wc: Variant) -> String:
	var m := str(model)
	if m == "":
		return ""
	var n := m
	if BWData.has_table("equipment"):
		n = str(BWData.row("equipment", m).get("name", m))
	var shown := label(n)
	var a := shown.to_lower().trim_suffix("s")          # "Dagger" is the "Daggers" class too
	if a == str(wc).to_lower().trim_suffix("s") or a == weapon(wc).to_lower().trim_suffix("s") or m == str(wc):
		return ""
	return shown
