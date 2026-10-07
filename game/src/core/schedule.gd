class_name BWSchedule
extends RefCounted
## D353 (supersedes D325's fixed 6v6 fights): the run's schedule as data.
## Fight n -> the cards it offers, in card order. One card = no choice (no
## room screen); two = a choice (BWRooms rolls the cards, BWRoomScreen shows
## them). Card slots:
##   single    one 3v3 battle, the map queue's front map, the Standard squad
##   standard  a 3v3 Standard room (a queue map)
##   hard      a 3v3 Hard room, or a special encounter in its place (D208)
##   obelisks  the Obelisks (D140), a boss card
##   twins     the Twins (D256), a boss card, built at the fight's values (D355)
##   split     a Split Front map: card 0 one map, card 1 the other (D354)
##   six       a 6v6 drawn from SIX_POOL, avoiding modes already played (D356)
##   giant     the Giant
## Hard and encounters stay on 3v3 cards; weather tags fall on 3v3 cards and
## the Split Front and Horde cards, never on a castle or a boss (D357).
## Pure data and rules, no nodes.

const SINGLE := "single"
const STANDARD := "standard"
const HARD := "hard"
const OBELISKS := "obelisks"
const TWINS := "twins"
const SPLIT := "split"
const SIX := "six"
const GIANT := "giant"

const TABLE := {
	1: [SINGLE],
	2: [SINGLE],
	3: [STANDARD, HARD],
	4: [OBELISKS, TWINS],
	5: [SPLIT, SPLIT],
	6: [STANDARD, HARD],
	7: [STANDARD, SIX],
	8: [SIX, SIX],
	9: [STANDARD, SIX],
	10: [SIX, SIX],
	11: [GIANT],
}

## The 3v3 slots: they take a map off the queue (D187).
const QUEUE_SLOTS := [SINGLE, STANDARD, HARD]

## D354/D356: the 6v6 pool, one entry per map. Both Split Front maps, the two
## castles, the Horde.
const SIX_POOL := [
	{ "mode": "splitfront", "map": "splitfront" },
	{ "mode": "splitfront", "map": "fords" },
	{ "mode": "defend", "map": "keep" },
	{ "mode": "storm", "map": "stronghold" },
	{ "mode": "horde", "map": "horde" },
]
## The two Split Front maps, card 0 and card 1 at a SPLIT fight.
const SPLIT_MAPS := ["splitfront", "fords"]
## D357: the 6v6 modes that take a weather tag (the castles don't).
const WEATHER_MODES := ["splitfront", "horde"]

## Boss cards: the card's title and its description (the room screen).
const BOSS_TITLES := { OBELISKS: "The Obelisks", TWINS: "The Twins" }
const BOSS_LINES := {
	OBELISKS: ["Break either stone to win.",
		"The White Lantern shrugs off half the ranged blows and pushes everyone away; the Black Well shrugs off half the melee and pulls everyone in."],
	TWINS: ["Noon paints light and Dusk paints dark; each heals on its own colour and a beam joins them.",
		"Under half HP the colours swap; down one and the other rages. Paint the other colour, break the beam with thunder."],
}


## Fight n's slots ([] past the Giant).
static func slots(n: int) -> Array:
	return TABLE.get(n, [])


## Fight n offers a choice (two cards or more).
static func has_choice(n: int) -> bool:
	return slots(n).size() >= 2


## Fight n can play a map off the 3v3 queue (an opener or a 3v3 card).
static func queued(n: int) -> bool:
	return slots(n).any(func(s): return s in QUEUE_SLOTS)


## How many 3v3 queue maps fight n's offer shows.
static func queue_cards(n: int) -> int:
	return slots(n).filter(func(s): return s in QUEUE_SLOTS).size()


## Fight n offers a 6v6 card (a Split Front or the pool).
static func offers_six(n: int) -> bool:
	return slots(n).any(func(s): return s in [SPLIT, SIX])


## The pool entry for `map` ({} = not a 6v6 map).
static func pool_entry(map: String) -> Dictionary:
	for e in SIX_POOL:
		if str(e.map) == map:
			return e
	return {}


## D356: one 6v6 card for fight n, card i: from SIX_POOL, never a map already
## in `taken` (this offer's other cards); first a mode not yet `played_modes`
## and a map not yet `played_maps`, then a map not yet played, then anything
## left. Seeded per run, fight and card (its own rng).
static func draw_six(seed_value: int, n: int, i: int, played_modes: Array, played_maps: Array, taken: Array) -> Dictionary:
	var open: Array = SIX_POOL.filter(func(e): return not str(e.map) in taken and _ships(str(e.map)))
	var tiers := [
		open.filter(func(e): return not str(e.mode) in played_modes and not str(e.map) in played_maps),
		open.filter(func(e): return not str(e.map) in played_maps),
		open,
	]
	var r := RandomNumberGenerator.new()
	r.seed = hash("six|%d|%d|%d" % [seed_value, n, i])
	for tier in tiers:
		if not (tier as Array).is_empty():
			return (tier[r.randi() % tier.size()] as Dictionary).duplicate()
	return {}


## D354: the divider elements of a Split Front offer, card by card: distinct
## when two Split Front cards share an offer. Seeded per run and fight.
static func dividers(seed_value: int, n: int, count: int) -> Array:
	var pool: Array = BWSplitFront.ELEMENTS.duplicate()
	var r := RandomNumberGenerator.new()
	r.seed = hash("dividers|%d|%d" % [seed_value, n])
	var out: Array = []
	for k in count:
		if pool.is_empty():
			pool = BWSplitFront.ELEMENTS.duplicate()
		out.append(pool.pop_at(r.randi() % pool.size()))
	return out


## The goal line on a 6v6 card.
static func goal_line(card: Dictionary) -> String:
	match str(card.get("mode", "")):
		"splitfront":
			var el := str(card.get("divider", ""))
			return "Two fronts, one wall: three of your six in each arena. Defeat every enemy." + \
				(" Divider: %s." % BWSplitFront.NAMES[el] if el in BWSplitFront.NAMES else "")
		"horde":
			return "Hold out against %d waves of the horde." % BWHordeMode.WAVES.size()
		"defend":
			return "Hold the iron gate for %d rounds." % BWCastleDefend.ROUNDS
		"storm":
			return "Break the wooden gate, then the throne (or down the Warden)."
	return ""


static func _ships(map: String) -> bool:
	return FileAccess.file_exists("res://maps/%s.json" % map)
