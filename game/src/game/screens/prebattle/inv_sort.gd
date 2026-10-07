class_name BWInvSort
extends RefCounted
## D235 (author, playtest 1: "allow sorting by element"): the inventory
## grids' sort order, shared by the gear panel and the shop. Pure; the choice
## is a static, so it holds for the session (not saved).
##
##   newest    the latest item first (its uid)
##   element   the element order (BWFormulas.ELEMENTS), plain items last
##   slot      head, chest, legs, weapons
##   tier      A first, E last
## Ties fall through to slot, then tier (best first), then newest, so every
## order is stable and reproducible.

const MODES := ["newest", "element", "slot", "tier"]
const LABELS := { "newest": "Newest", "element": "Element", "slot": "Slot", "tier": "Tier" }

static var mode := "newest"


static func set_mode(m: String) -> void:
	if m in MODES:
		mode = m


## A sorted copy of `items` (the array itself is untouched).
static func sorted(items: Array, m: String = "") -> Array:
	var by := m if m in MODES else mode
	var out := items.duplicate()
	out.sort_custom(func(a, b): return _less(a, b, by))
	return out


static func _less(a: Dictionary, b: Dictionary, by: String) -> bool:
	var ka := key(a, by)
	var kb := key(b, by)
	for i in ka.size():
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false


## The item's sort key under `by`: an array compared left to right.
static func key(it: Dictionary, by: String) -> Array:
	var el := BWRun.item_element(it)
	var ei := BWFormulas.ELEMENTS.find(el)
	var elem := ei if ei >= 0 else BWFormulas.ELEMENTS.size()      # plain last
	var sl := BWRun.SLOTS.find(str(it.get("slot", "")))
	var slot := sl if sl >= 0 else BWRun.SLOTS.size()
	var tier := -BWRun.TIERS.find(str(it.get("tier", "E")))       # best first
	var newest := -uid_n(it)
	match by:
		"element": return [elem, slot, tier, newest]
		"slot": return [slot, elem, tier, newest]
		"tier": return [tier, slot, elem, newest]
	return [newest]


static func uid_n(it: Dictionary) -> int:
	return str(it.get("uid", "")).trim_prefix("it").to_int()
