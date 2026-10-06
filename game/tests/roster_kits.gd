class_name BWRosterKits
extends RefCounted
## D150 test fixtures: since the roster's weapons, elements, stats and clothes
## are rolled (BWRosterGen), tests and review tools that need one particular
## kit (a flamberge, a moon staff, baggy sweatpants ...) take it from here:
## the pre-D150 roster's kits, frozen, on the same seats under the new names
## (seat 1's old kit on seat 1's new character, and so on). Identity
## (name, hair, voice, seat) still comes from roster.csv.
##
##   BWRosterKits.unit("della")   # the old seat-2 kit: flamberge, fire, tank_top ...

const KITS := {
	"aureli": { "weapon_class": "axe", "weapon_model": "anchor", "element": "water", "con": 6, "str": 6, "dex": 2, "wil": 1, "def": 6, "res": 3, "spd": 2, "top": "sweater", "bottom": "baggy_sweatpants", "clothing_shade": "dark", "friendliness": "friendly" },
	"della": { "weapon_class": "sword", "weapon_model": "flamberge", "element": "fire", "con": 4, "str": 5, "dex": 4, "wil": 2, "def": 4, "res": 3, "spd": 4, "top": "tank_top", "bottom": "tight_pants", "clothing_shade": "dark", "friendliness": "unfriendly" },
	"jericho": { "weapon_class": "staff", "weapon_model": "moon_staff", "element": "light", "con": 3, "str": 1, "dex": 3, "wil": 6, "def": 2, "res": 6, "spd": 5, "top": "sweater_scarf", "bottom": "sweatpants", "clothing_shade": "light", "friendliness": "neutral" },
	"will": { "weapon_class": "daggers", "weapon_model": "jagged_dagger", "element": "thunder", "con": 3, "str": 2, "dex": 6, "wil": 2, "def": 2, "res": 3, "spd": 6, "top": "crop_hoodie", "bottom": "ripped_tight_pants", "clothing_shade": "mid", "friendliness": "unfriendly" },
	"gail": { "weapon_class": "bow", "weapon_model": "recurve_bow", "element": "wind", "con": 3, "str": 3, "dex": 5, "wil": 3, "def": 3, "res": 3, "spd": 5, "top": "tshirt", "bottom": "shorts", "clothing_shade": "mid", "friendliness": "friendly" },
	"kira": { "weapon_class": "staff", "weapon_model": "staff", "element": "dark", "con": 3, "str": 2, "dex": 4, "wil": 6, "def": 1, "res": 4, "spd": 5, "top": "crop_top", "bottom": "tight_shorts", "clothing_shade": "light", "friendliness": "neutral" },
	"demeter": { "weapon_class": "axe", "weapon_model": "warhammer", "element": "ice", "con": 6, "str": 6, "dex": 1, "wil": 2, "def": 6, "res": 4, "spd": 1, "top": "tank_top", "bottom": "baggy_sweatpants", "clothing_shade": "dark", "friendliness": "unfriendly" },
	"stryker": { "weapon_class": "sword", "weapon_model": "sword", "element": "light", "con": 4, "str": 4, "dex": 4, "wil": 4, "def": 4, "res": 4, "spd": 4, "top": "sweater", "bottom": "tight_pants", "clothing_shade": "mid", "friendliness": "friendly" },
	"burt": { "weapon_class": "axe", "weapon_model": "double_axe", "element": "fire", "con": 5, "str": 6, "dex": 3, "wil": 1, "def": 4, "res": 3, "spd": 3, "top": "tank_top", "bottom": "shorts", "clothing_shade": "dark", "friendliness": "friendly" },
	"rui": { "weapon_class": "lance", "weapon_model": "halberd", "element": "dark", "con": 5, "str": 5, "dex": 2, "wil": 3, "def": 5, "res": 4, "spd": 2, "top": "sweater", "bottom": "tight_pants", "clothing_shade": "mid", "friendliness": "unfriendly" },
	"bob": { "weapon_class": "lance", "weapon_model": "lance", "element": "water", "con": 4, "str": 3, "dex": 3, "wil": 5, "def": 3, "res": 4, "spd": 3, "top": "crop_hoodie", "bottom": "sweatpants", "clothing_shade": "light", "friendliness": "friendly" },
	"sala": { "weapon_class": "pistols", "weapon_model": "m1911", "element": "thunder", "con": 2, "str": 3, "dex": 6, "wil": 1, "def": 3, "res": 3, "spd": 6, "top": "crop_top", "bottom": "short_shorts", "clothing_shade": "mid", "friendliness": "unfriendly" },
	"rem": { "weapon_class": "daggers", "weapon_model": "dagger", "element": "wind", "con": 2, "str": 2, "dex": 5, "wil": 3, "def": 2, "res": 4, "spd": 6, "top": "hoodie", "bottom": "tight_shorts", "clothing_shade": "light", "friendliness": "friendly" },
	"wilona": { "weapon_class": "bow", "weapon_model": "compound_bow", "element": "ice", "con": 3, "str": 2, "dex": 6, "wil": 3, "def": 3, "res": 4, "spd": 4, "top": "sweater_scarf", "bottom": "tight_pants", "clothing_shade": "light", "friendliness": "neutral" },
	"lionel": { "weapon_class": "pistols", "weapon_model": "flintlock", "element": "fire", "con": 3, "str": 2, "dex": 4, "wil": 5, "def": 2, "res": 4, "spd": 5, "top": "tshirt", "bottom": "short_shorts", "clothing_shade": "light", "friendliness": "friendly" },
	"dragtol": { "weapon_class": "lance", "weapon_model": "javelin", "element": "wind", "con": 4, "str": 5, "dex": 4, "wil": 1, "def": 3, "res": 2, "spd": 6, "top": "crop_top", "bottom": "short_shorts", "clothing_shade": "mid", "friendliness": "neutral" },
	"apollyon": { "weapon_class": "sword", "weapon_model": "scimitar", "element": "dark", "con": 4, "str": 5, "dex": 5, "wil": 2, "def": 3, "res": 3, "spd": 4, "top": "sweater_scarf", "bottom": "tight_pants", "clothing_shade": "dark", "friendliness": "unfriendly" },
	"kai": { "weapon_class": "axe", "weapon_model": "hatchet", "element": "thunder", "con": 3, "str": 3, "dex": 5, "wil": 2, "def": 2, "res": 3, "spd": 6, "top": "hoodie", "bottom": "ripped_tight_pants", "clothing_shade": "dark", "friendliness": "unfriendly" },
	"alexandra": { "weapon_class": "lance", "weapon_model": "glaive", "element": "ice", "con": 5, "str": 4, "dex": 3, "wil": 3, "def": 5, "res": 5, "spd": 2, "top": "hoodie", "bottom": "sweatpants", "clothing_shade": "mid", "friendliness": "neutral" },
	"opus": { "weapon_class": "bow", "weapon_model": "shortbow", "element": "light", "con": 5, "str": 5, "dex": 3, "wil": 1, "def": 4, "res": 3, "spd": 4, "top": "tshirt", "bottom": "baggy_sweatpants", "clothing_shade": "dark", "friendliness": "neutral" },
}


## The identity row with the frozen kit on top.
static func row(id: String) -> Dictionary:
	var r: Dictionary = BWData.row("roster", id).duplicate()
	if r.is_empty():
		for i in BWData.identities():
			if str(i.id) == id:
				r = Dictionary(i).duplicate()
	r.merge(KITS.get(id, {}), true)
	return r


static func unit(id: String) -> BWUnit:
	return BWUnit.from_roster(row(id))


## All 20, in seat order (the old fixed roster, new names).
static func rows() -> Array:
	return BWData.identities().map(func(i): return row(str(i.id)))
