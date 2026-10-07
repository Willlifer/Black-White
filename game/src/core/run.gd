class_name BWRun
extends RefCounted
## One run of the game, as pure state + rules: the chosen six, inventory,
## the fight ladder, loot, downtime, the shop, trust. No nodes. Saves to a
## plain Dictionary (to_dict / from_dict) so a run survives a restart.
##
## Brief structure: pick 6 of 20 → (pre-battle: pick 3 → fight → downtime)
## × 10 → the boss. Calls on unspecified numbers are D35–D41.

const FIGHTS := 10
const BOSS_FIGHT := 11
const SQUAD := 6
## The default units a side fields (the 3v3 maps). D319: a map's own
## `deploy_count` (BWBoard) decides: 3, or 6 on a big map; see deploy_for().
const DEPLOY := 3
## D145 (supersedes D118's fixed order): fight 4 is always the Obelisks (D140,
## an objective fight: break a stone), the Giant stays on the arena, and the
## other nine slots (fights 1-3, 5-10) take MAP_POOL in a seeded shuffle from
## the run's seed: nine maps for nine slots, so none repeat. The order is kept
## in `map_order` and saved, so a loaded run plays the same maps.
const OBJECTIVE_FIGHT := 4
const OBJECTIVE_MAP := "obelisks"
## D256: fight 7 is always the Twins (BWTwins) on their round court: no room
## choice, no weather, the boss music; a win gives every squad unit a pick.
const TWINS_FIGHT := 7
const TWINS_MAP := "court"
## D325/D327: the fixed 6v6 fights (no room choice). Fight 5 is always Split
## Front; fights 8 and 10 play two of SIX_MODES, seeded per run, no repeat
## (six_modes_for). Fight 9 stays a 3v3 room choice. A mode whose map isn't
## shipped yet plays MODE_PLACEHOLDER (Commons, a plain 6v6 wipe-out).
const SPLIT_FIGHT := 5
const SIX_FIGHTS := [8, 10]
const SIX_MODES := ["defend", "storm", "horde"]
const MODE_MAPS := { "splitfront": "splitfront", "horde": "horde", "defend": "keep", "storm": "stronghold" }
const MODE_NAMES := { "splitfront": "Split Front", "horde": "Stop the Horde", "defend": "Defend the Castle", "storm": "Storm the Castle" }
const MODE_PLACEHOLDER := "commons"
## D334: a mode fight pays this many drops on a win (a horde's head count would flood the bag).
const MODE_DROPS := 5
const MAP_POOL := ["arena", "paintball", "bridge", "lake", "chapel", "ravine", "catacombs", "tinderbox", "forge"]
## Every battle map (the pool plus the objective map).
const MAPS := ["arena", "paintball", "bridge", "lake", "obelisks", "chapel", "ravine", "catacombs", "tinderbox", "forge"]
## D145: the shuffled pool for the nine plain slots, in slot order (fights 1-3, 5-10).
var map_order: Array = []
## D186-D188 rooms (BWRooms): the unplayed maps, front first (seeded from
## map_order; the unchosen room's map goes to the back); the current fight's
## offer { fight, rooms: [standard, hard], chosen }; and per fight played
## ("n" -> { kind, map }).
var map_queue: Array = []
var room_offer := {}
var room_log := {}
const TIERS := ["E", "D", "C", "B", "A"]
const TIER_RANGE := { "E": [0, 3], "D": [1, 6], "C": [2, 9], "B": [3, 12], "A": [4, 15] }
const ARMOR_SLOTS := ["head", "chest", "legs"]
const SLOTS := ["head", "chest", "legs", "main_hand"]
## D180: the slot boxes a unit has: the four worn slots plus the carried weapon.
const GEAR_SLOTS := ["head", "chest", "legs", "main_hand", "second"]
const LEARN_BATTLES := 2          # brief: learn an item's ability after wearing it 2 battles
const SHOP_STOCK := 5
## D203: the stock per visit: one of each armour slot and two weapons, at the
## current tier (traded 1-for-1 as before).
const SHOP_SLOTS := ["head", "chest", "legs", "main_hand", "main_hand"]
## D203: the featured imbuement scrolls, one per element, re-rolled after every
## battle. Each holds one element row. D236 (author, playtest 1): scrolls are
## free; using one spends it until the next battle's re-roll.
const SCROLL_COST := 0

## D127 downtime (replaces D37/D85's eight actions): each unit takes one of
## three choices a day. The screen shows only the names (author: no effect
## text); the rules are BWRun.downtime().
const DOWNTIME_CHOICES := ["specialize", "branch_out", "wander"]
const CHOICE_NAMES := { "specialize": "Specialize", "branch_out": "Branch out", "wander": "Wander" }
const SPECIALIZE_POINTS := 5      # half a rank (POINTS_PER_RANK 10) in the element and the weapon class
const SPECIALIZE_ROLL := 0.5      # each: a free pick, else a find
const BRANCH_POINTS := 10         # a full rank
## D129 Wander: nine effects, each rolled on its own at WANDER_ROLL.
const WANDER_ROLL := 0.20
## D179: "stat" (+1 to a random stat, for good) replaces the old +50 XP.
const WANDER_EFFECTS := ["stat", "element", "weapon", "find_weapon", "find_armour", "recruit",
	"status_immunity", "element_brace", "stat_buff"]
const WANDER_STAT_POINT := 1      # the "stat" effect and the consolation: +1, permanent
## All nine missed, then this roll is the jackpot: 0.8^9 x 0.05 = about 0.67%
## a wander (author 2026-10-05). D177 (replaces +5000 XP and the rogue): the
## nine effects are rolled again at WANDER_JACKPOT_ROLL each (one recruit a
## day still); if that misses everything too, the consolation (+1 to a random
## stat, D179; it was +100 XP).
const WANDER_JACKPOT_EXTRA_ROLL := 0.05
const WANDER_JACKPOT_ROLL := 0.30
const WANDER_STAT_BUFF := 10
## D175: a day offers each unit DOWNTIME_OFFER of the three choices, drawn per
## unit per day from the run seed (day_choices), so it is stable all day.
const DOWNTIME_OFFER := 2
const IMMUNE_STATUSES := ["staggered", "blinded", "pinned", "drenched", "scorched", "shrouded"]
const SHRUG := { "staggered": "staggers", "blinded": "blinding", "pinned": "pins", "drenched": "drenching",
	"scorched": "scorching", "shrouded": "shrouding" }
## D129: set by a wanderer's recruit; later wanderers that day skip the roll.
var recruited_today := false
## D176: the day's Branch out cards per unit id, rolled when first asked
## (branch_preview) and kept for that day, so what the hall shows is what
## Branch out gives. Not saved: a reload re-derives the same roll.
var _branch_cards := {}
var _branch_day := -1

## Save format. 1: the first; 2 (D92): adds each unit's picks (perks,
## known_skills, skill_ranks, skill_loadout, skill_picks). from_dict
## migrates a 1 by auto-resolving what its ranks already owe. 3 (D121): adds
## `stats`; an older save starts them empty, its earlier fights "untracked".
## 4 (D132): units add bonus_perks, bonus_skills, rogue, next_immune,
## next_brace, fight_buff, focus_element (defaults when older); the weapon class is
## re-read from the main hand. Day plans were never saved, so nothing of the
## old eight actions carries over. 5 (D150): the renamed, rolled roster —
## adds `roster_seed` and `roster` (the 20 rolled rows); older saves name
## characters that no longer exist and are refused (can_load), never migrated.
## 6 (D184): units may carry a second weapon (equipment "second") and C+
## weapons an elemental `imbue`; a v5 save loads as is (no second weapon, no
## imbues: both read as absent).
## 7 (D189): the rooms: `map_queue`, `room_offer` (the two rooms on offer,
## so a save mid-choice shows the same two) and `room_log`; an older save
## derives them from map_order (fights already played took their D145 slot).
## 8 (D203): the shop's seven imbuement `scrolls`; an older save rolls them.
## 9 (D206): an imbue carries an element enchantment (`imbue_enchant`); older
## imbued weapons roll one on load.
## 10 (D247): the consolidation (D243-D246): merged enchantment and ability
## ids map to the row they joined, Warded takes the old resist row's element
## (`ward`), and pure cuts re-roll within their old family and tier
## (migrate_v10).
## 11 (D283): the Element Overhaul re-cut. Units save `keystones`; the 14
## held enchantment rows left for perks and sets re-roll within their element
## (migrate_v11); removed perks map to the perk they joined (PERK_MERGED).
const SAVE_VERSION := 11
const OLDEST_LOADABLE := 5

var rng := RandomNumberGenerator.new()
var seed_value := 0
var squad: Array = []             # BWUnit; the chosen six plus recruits
var inventory: Array = []         # loose items (not equipped)
var fight := 1                    # the next fight to play, 1..11
var day := 1
var trust := {}                   # "a|b" (sorted ids) -> points
var last_enemies: Array = []      # unit dicts from the last fight, for recruiting
var shop: Array = []
var scrolls: Array = []           # D203: { uid, kind: "scroll", element, enchant, tier, sold }
## D234: loose items set aside to throw away. Out of the inventory (so the
## shop never offers them), back with untrash_item, deleted by empty_trash
## when a battle starts. Saved, so a reload keeps the pile.
var trash: Array = []
var learned := {}                 # unit id -> [ability ids]
var ability_ranks := {}           # unit id -> { ability id: rank }
var equipped_ability := {}        # unit id -> { type: ability id }
## D121: the run's tallies, added to in after_fight (BWBattleStats):
## { won, lost, untracked (fights before save v3), units: { id: { fights,
## kos, damage, taken, mvp } }, best: { text, score, fight } }.
var stats := new_stats()
var _uid := 0
## D150: this run's roster roll (BWRosterGen.roll): the seed (never shown)
## and the 20 rows the squad, the enemies (enemies_for) and recruits come from.
var roster_seed := -1
var roster_rows: Array = []


# ---------------------------------------------------------------- setup

## `p_roster` / `p_roster_seed`: the roster screen's roll (D150); empty =
## BWData's active roster (the default seed in tests, tools and sims).
static func start(chosen_ids: Array, p_seed: int, p_roster: Array = [], p_roster_seed: int = -1) -> BWRun:
	var r := BWRun.new()
	r.seed_value = p_seed
	r.rng.seed = p_seed
	r.roster_rows = (p_roster if not p_roster.is_empty() else BWData.table("roster")).duplicate(true)
	r.roster_seed = p_roster_seed if not p_roster.is_empty() else BWData.roster_seed
	r.map_order = shuffled_maps(p_seed)          # D145
	r.map_queue = r.map_order.duplicate()        # D187
	for id in chosen_ids:
		var u := BWUnit.from_roster(r.roster_row(id))
		r.seed_unit(u)                   # D174
		r.auto_first_perk(u)             # D233: no run-start picker
		r.squad.append(u)
		r.learned[u.id] = []
		r.ability_ranks[u.id] = {}
		r.equipped_ability[u.id] = {}
		# Everyone starts holding their signature weapon at tier E (D35).
		var w := r.make_item(u.weapon_model, "E")
		u.equipment["main_hand"] = w
	r.inventory.append_array(r.starting_kit())
	r.restock_shop()
	return r


const STARTING_KIT := 5

## Author 2026-10-04: "give the player like 5 equipment pieces to start with."
## Five random tier-E armour pieces, at least one head, one chest and one legs
## piece (so every slot has something to hand out in the hall before fight 1),
## no duplicates. Deterministic from the run seed.
func starting_kit() -> Array:
	var by_slot := { "head": [], "chest": [], "legs": [] }
	for row in BWData.table("equipment"):
		if by_slot.has(str(row.slot)):
			by_slot[str(row.slot)].append(str(row.id))
	var picks: Array = []
	for slot in ["head", "chest", "legs"]:
		var pool: Array = by_slot[slot]
		picks.append(pool[rng.randi() % pool.size()])
	var rest: Array = by_slot.head + by_slot.chest + by_slot.legs
	while picks.size() < STARTING_KIT:
		var id: String = rest[rng.randi() % rest.size()]
		if not id in picks:
			picks.append(id)
	return picks.map(func(id): return make_item(id, "E"))


func unit(id: String) -> BWUnit:
	for u in squad:
		if u.id == id:
			return u
	return null


func tier_for(n: int) -> String:
	return TIERS[clampi((n - 1) / 2, 0, TIERS.size() - 1)]


## D319 (tools and tests only, never saved): every fight plays this map
## ("" = the run's own maps). `campaign_sim` MAP=commons uses it for 6v6.
var force_map := ""
## D327 (tools only, never saved): fight n -> the 6v6 mode it plays instead of
## the run's own draw (campaign_sim SIX=1 plays each mode at fights 8 and 10).
var mode_override := {}


## D319: the units the squad fields in fight n: the map's deploy_count (3, or
## 6 on a big map), capped by the squad's size (fewer owned: field them all).
## The enemy side fields the map's count (BWRooms draws it, as many as the
## roster outside the squad can spare).
func deploy_for(n: int) -> int:
	var c := deploy_count_of(map_for(n))
	return mini(c, squad.size()) if not squad.is_empty() else c


static var _deploy_counts := {}


## D319: a map's deploy_count (read once per map name, then cached).
static func deploy_count_of(map_name: String) -> int:
	if not _deploy_counts.has(map_name):
		var path := "res://maps/%s.json" % map_name
		_deploy_counts[map_name] = BWBoard.load_file(path).deploy_count if FileAccess.file_exists(path) else DEPLOY
	return int(_deploy_counts[map_name])


func map_for(n: int) -> String:
	if force_map != "":
		return force_map
	if n >= BOSS_FIGHT:
		return "arena"
	if mode_for(n) != "":
		return mode_map(mode_for(n))               # D327: the fixed 6v6 fights
	if n == OBJECTIVE_FIGHT:
		return OBJECTIVE_MAP
	if n == TWINS_FIGHT:
		return TWINS_MAP
	if map_order.is_empty():
		map_order = shuffled_maps(seed_value)
		if map_queue.is_empty() and room_log.is_empty():
			map_queue = map_order.duplicate()
	# D187: the chosen room's map (the Standard room's until a choice; later
	# fights: as if every room from here on were Standard).
	return BWRooms.projected_map(self, n)


## D145: MAP_POOL in a Fisher-Yates shuffle on its own rng seeded from the run
## seed (the run's own rng is untouched, so loot and downtime rolls don't move).
static func shuffled_maps(p_seed: int) -> Array:
	var out: Array = MAP_POOL.duplicate()
	var mrng := RandomNumberGenerator.new()
	mrng.seed = hash("maps|%d" % p_seed)
	for i in range(out.size() - 1, 0, -1):
		var j := mrng.randi() % (i + 1)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


## D140: fight n's objective, from its map ({} = a plain fight). The battle
## reads the same field itself (BWBoard.objective -> BWBattle.setup), so this
## is for the screens: the pre-battle note, the results line.
func objective_for(n: int) -> Dictionary:
	return BWBoard.load_file("res://maps/%s.json" % map_for(n)).objective


## D327: fight n's fixed 6v6 mode ("" = none): Split Front at SPLIT_FIGHT,
## the run's seeded pair at SIX_FIGHTS.
func mode_for(n: int) -> String:
	if mode_override.has(n):
		return str(mode_override[n])               # tools only (campaign_sim SIX=1)
	if n == SPLIT_FIGHT:
		return "splitfront"
	var i := SIX_FIGHTS.find(n)
	return str(six_modes_for(seed_value)[i]) if i >= 0 else ""


## D325: two of SIX_MODES for fights 8 and 10, no repeat, from the run seed
## on its own rng (loot and maps don't move).
static func six_modes_for(p_seed: int) -> Array:
	var pool: Array = SIX_MODES.duplicate()
	var mrng := RandomNumberGenerator.new()
	mrng.seed = hash("sixes|%d" % p_seed)
	var a: String = pool.pop_at(mrng.randi() % pool.size())
	var b: String = pool[mrng.randi() % pool.size()]
	return [a, b]


## The map a mode plays on (MODE_PLACEHOLDER until the mode's map ships).
static func mode_map(mode: String) -> String:
	var m := str(MODE_MAPS.get(mode, MODE_PLACEHOLDER))
	return m if FileAccess.file_exists("res://maps/%s.json" % m) else MODE_PLACEHOLDER


## A fight with no room choice and no map off the queue: the Obelisks, the
## Twins, the 6v6 modes (D327).
static func is_fixed(n: int) -> bool:
	return n == OBJECTIVE_FIGHT or n == TWINS_FIGHT or n == SPLIT_FIGHT or n in SIX_FIGHTS


## D256: the current fight is the Twins.
func is_twins() -> bool:
	return fight == TWINS_FIGHT


func is_boss() -> bool:
	return fight >= BOSS_FIGHT


func is_over() -> bool:
	return fight > BOSS_FIGHT


# ---------------------------------------------------------------- items

## Roll a fresh item: stats within the tier band on each stat line, plus one
## built-in enchantment the base item allows.
func make_item(base_id: String, tier: String, enchant_id: String = "?") -> Dictionary:
	var base := BWData.row("equipment", base_id)
	if base.is_empty():
		return {}
	_uid += 1
	var band: Array = TIER_RANGE[tier]
	var stats := {}
	for s in BWData.list(base.stat_lines):
		stats[s] = rng.randi_range(band[0], band[1])
	var item := {
		"uid": "it%d" % _uid, "base": base_id, "slot": str(base.slot), "weight": str(base.weight),
		"tier": tier, "stats": stats, "enchant": "", "worn": {},
	}
	item.enchant = _roll_enchant(base_id, tier) if enchant_id == "?" else enchant_id
	if item.enchant == BWEffects.WARDED:
		item["ward"] = roll_ward(seed_value, str(item.uid))     # D243: own rng, the run's stream unmoved
	# D182: a C, B or A weapon also rolls an elemental imbue (its own rng off
	# the item's uid, so the run's rng stream and every older roll are unchanged).
	if str(base.slot) == "main_hand" and TIERS.find(tier) >= TIERS.find(IMBUE_TIER):
		item["imbue"] = roll_imbue(seed_value, str(item.uid))
		item["imbue_enchant"] = roll_imbue_enchant(seed_value, str(item.uid), str(item.imbue), tier)   # D206
	return item


## D182: weapons of this tier and up carry an elemental imbue as well as their enchantment.
const IMBUE_TIER := "C"


## D182: the imbue for a fresh weapon: one of the seven elements, from the
## run seed and the item's uid alone.
## D206: the imbue's element enchantment: one of that element's rows unlocked
## at the item's tier (D200 weights), from its own rng (run seed, uid).
static func roll_imbue_enchant(p_seed: int, uid: String, element: String, tier: String) -> String:
	var pool: Array = []
	for e in BWData.table("enchantments"):
		var w := ench_weight(e, tier)
		if w > 0 and of_element(e, element):
			pool.append([str(e.id), w])
	var r := RandomNumberGenerator.new()
	r.seed = hash("imbue_ench|%d|%s" % [p_seed, uid])
	return _weighted(pool, r)


## D247 save v10 (the D243-D246 consolidation). Merged enchantment ids -> the
## row they joined; the four old resist rows -> Warded of their element
## (Stubborn: a rolled one).
const ENCH_MERGED := {
	"smouldering": "kindled", "umbral": "abyssal", "hallowed": "dawning", "deepwater": "brimming",
	"frozen": "glacial", "lingering": "gusting", "jolting": "arcing", "sapping": "conductor",
	"fireproof": "warded", "grounded": "warded", "windbreak": "warded", "nightforged": "warded", "stubborn": "warded",
	"resonance": "conducting", "serrated": "keen", "piercing_strikes": "longshot", "channelling": "cleaving",
	"hooking": "impact", "stampede": "jousting", "parry_shield": "guarding",
	"wake_fire": "wake", "wake_water": "wake", "wake_dark": "wake", "wake_light": "wake",
	"tag_team": "pursuit", "inspiring": "feast", "graze": "steady_hand", "rerouted": "steady_hand",
	"shieldwall": "lockstep", "evasive_roll": "disengage", "lifeline": "bodyguard", "rally_cry": "sheltering",
}
const WARD_FROM := { "fireproof": "fire", "grounded": "thunder", "windbreak": "wind", "nightforged": "dark" }
## Pure cuts (and rows folded into abilities): [family, tier] they re-roll in.
const ENCH_CUT := {
	"whistling": ["elemental", "E"], "hearth_fire": ["recovery", "E"], "hearth_water": ["recovery", "E"],
	"hearth_dark": ["recovery", "E"], "hearth_light": ["recovery", "E"], "second_breath": ["recovery", "E"],
	"high_ground": ["momentum", "D"], "vengeance": ["defensive", "C"], "fury": ["defensive", "E"],
	"banner": ["team", "C"], "relay": ["team", "D"], "tending": ["team", "C"],
}
## D283 save v11: the 14 element rows the consolidation held back (D246) left
## enchantments for perks (Tidewalker, Forge, Overloading, Permafrost, Cold
## Snap, Nightfall, Beacon, Shattering, Wading) and sets (Blazing, Riptide,
## Shrouded, Sunlit, Rimed): id -> [element, tier] they re-roll within.
const ENCH_HELD := {
	"tidewalker": ["water", "D"], "forge": ["fire", "D"], "overload": ["thunder", "C"],
	"permafrost": ["ice", "C"], "cold_snap": ["ice", "C"], "nightfall": ["dark", "C"],
	"beacon": ["light", "C"], "shattering": ["ice", "E"], "wading": ["water", "E"],
	"blazing": ["fire", "E"], "riptide": ["water", "E"], "shrouded": ["dark", "E"],
	"sunlit": ["light", "E"], "rimed": ["ice", "E"],
}
## D283 (D281's re-cut, 35 -> 28 perks): a removed perk -> the perk it joined
## ("" = gone: Frost Ward became the Ice set's 3-piece; the pick is owed again).
const PERK_MERGED := {
	"water_flow": "water_guard", "fire_coal": "fire_rush", "thunder_grounded": "thunder_rod",
	"wind_gust": "wind_force", "wind_slip": "wind_tail", "dark_cover": "dark_night",
	"light_guard": "light_sanct", "ice_ward": "",
}


## D283: a unit's perks after the re-cut: merged ids map to their target,
## duplicates collapse, gone ones drop (the ladder then owes the pick again).
static func migrate_perks_v11(perks: Array) -> Array:
	var out: Array = []
	for id in perks:
		var to := str(PERK_MERGED.get(str(id), str(id)))
		if to != "" and not BWData.row("perks", to).is_empty() and not to in out:
			out.append(to)
	return out


## D283: items carrying a held row re-roll within its element: the same
## element at its old tier, else anything of that element the item's tier
## unlocks, else the v10 family re-roll. An imbue's enchantment re-rolls in
## its imbue's element.
static func migrate_v11(items: Array, p_seed: int) -> void:
	for it in items:
		if not it is Dictionary:
			continue
		var uid := str(it.get("uid", ""))
		var ench := str(it.get("enchant", ""))
		if ench != "" and BWData.row("enchantments", ench).is_empty():
			var et: Array = ENCH_HELD.get(ench, ["", "E"])
			it["enchant"] = _reroll_held(str(it.get("base", "")), str(et[0]), str(et[1]), str(it.get("tier", "E")), p_seed, uid)
			if it.enchant == "":
				it["enchant"] = _reroll_cut(str(it.get("base", "")), "elemental", str(et[1]), str(it.get("tier", "E")), p_seed, uid)
			if it.enchant == BWEffects.WARDED:
				it["ward"] = str(et[0]) if str(et[0]) != "" else roll_ward(p_seed, uid)
		var imb := str(it.get("imbue_enchant", ""))
		if imb != "" and BWData.row("enchantments", imb).is_empty():
			it["imbue_enchant"] = roll_imbue_enchant(p_seed, uid, str(it.get("imbue", "")), str(it.get("tier", "C")))


static func _reroll_held(base: String, element: String, tier: String, item_tier: String, p_seed: int, uid: String) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = hash("v11|%d|%s" % [p_seed, uid])
	for pass_i in 3:                      # its tier; anything the item's tier unlocks; any tier (keep the colour)
		var pool: Array = []
		for e in BWData.table("enchantments"):
			if not base in BWData.list(e.applies_to) or str(e.element) != element or element == "":
				continue
			if (pass_i == 0 and str(e.tier) == tier) or (pass_i == 1 and ench_weight(e, item_tier) > 0) or pass_i == 2:
				pool.append([str(e.id), 1])
		if not pool.is_empty():
			return _weighted(pool, r)
	if element != "" and base in BWData.list(BWData.row("enchantments", BWEffects.WARDED).get("applies_to", "")):
		return BWEffects.WARDED                   # no row of its element fits the base: Warded of it keeps the colour
	return ""


## Merged ability ids -> the ability they joined (D245).
const ABILITY_MERGED := {
	"enrage": "bloodied", "light_footed": "second_wind", "ward": "iron_wall", "brace": "iron_wall",
	"tumble": "poise", "encore": "crowd_pleaser", "ring_guard": "guardian", "grace": "mana_veil",
	"keep_warm": "mana_veil", "heads_up": "scouts_lead", "fletchers_eye": "deadeye", "rooted": "unbowed",
	"arena_born": "flair", "supple": "acrobat", "flutter": "leap_ready", "woven_rings": "bastion",
	"shoulder_check": "bastion", "steel_under_cloth": "crosstrained", "nimble_strength": "crosstrained",
	"insight": "crosstrained", "visor": "hardened", "drift": "sure_stride",
}


static func migrate_v10(items: Array, p_seed: int) -> void:
	for it in items:
		if not it is Dictionary:
			continue
		var uid := str(it.get("uid", ""))
		var ench := str(it.get("enchant", ""))
		if ench != "" and BWData.row("enchantments", ench).is_empty():
			if ENCH_MERGED.has(ench):
				it["enchant"] = str(ENCH_MERGED[ench])
				if it.enchant == BWEffects.WARDED:
					it["ward"] = str(WARD_FROM.get(ench, roll_ward(p_seed, uid)))
			else:
				var ft: Array = ENCH_CUT.get(ench, ["", str(it.get("tier", "E"))])
				it["enchant"] = _reroll_cut(str(it.get("base", "")), str(ft[0]), str(ft[1]), str(it.get("tier", "E")), p_seed, uid)
				if it.enchant == BWEffects.WARDED:
					it["ward"] = roll_ward(p_seed, uid)
		var imb := str(it.get("imbue_enchant", ""))
		if imb != "" and BWData.row("enchantments", imb).is_empty():
			var to := str(ENCH_MERGED.get(imb, ""))
			if to != "" and of_element(BWData.row("enchantments", to), str(it.get("imbue", ""))):
				it["imbue_enchant"] = to
			else:
				it["imbue_enchant"] = roll_imbue_enchant(p_seed, uid, str(it.get("imbue", "")), str(it.get("tier", "C")))


## A cut row's replacement on `base`: its old family at its old tier, else that
## family at anything the item's tier unlocks, else any row the item could roll.
static func _reroll_cut(base: String, family: String, tier: String, item_tier: String, p_seed: int, uid: String) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = hash("v10|%d|%s" % [p_seed, uid])
	for pass_i in 3:
		var pool: Array = []
		for e in BWData.table("enchantments"):
			if not base in BWData.list(e.applies_to):
				continue
			var ok := false
			match pass_i:
				0: ok = str(e.family) == family and str(e.tier) == tier
				1: ok = str(e.family) == family and ench_weight(e, item_tier) > 0
				2: ok = ench_weight(e, item_tier) > 0
			if ok:
				pool.append([str(e.id), 1])
		if not pool.is_empty():
			return _weighted(pool, r)
	return ""


## D247: learned, ranks and the equipped choice follow merged abilities (a
## merged pair keeps the higher rank; duplicates collapse).
func migrate_abilities_v10() -> void:
	for id in learned:
		var out: Array = []
		for ab in learned[id]:
			var to := str(ABILITY_MERGED.get(str(ab), str(ab)))
			if not BWData.row("abilities", to).is_empty() and not to in out:
				out.append(to)
		learned[id] = out
	for id in ability_ranks:
		var ranks := {}
		for ab in ability_ranks[id]:
			var to := str(ABILITY_MERGED.get(str(ab), str(ab)))
			ranks[to] = maxi(int(ranks.get(to, 0)), int(ability_ranks[id][ab]))
		ability_ranks[id] = ranks
	for id in equipped_ability:
		var eq: Dictionary = equipped_ability[id]
		for type in eq.keys():
			eq[type] = str(ABILITY_MERGED.get(str(eq[type]), str(eq[type])))


## D206 save v9: weapons imbued before the imbue carried an enchantment get one.
static func migrate_imbues(items: Array, p_seed: int) -> void:
	for it in items:
		if it is Dictionary and str(it.get("imbue", "")) != "" and str(it.get("imbue_enchant", "")) == "":
			it["imbue_enchant"] = roll_imbue_enchant(p_seed, str(it.get("uid", "")), str(it.imbue), str(it.get("tier", "C")))


## D243: does an enchantment row belong to `element`'s pool (scrolls, imbues,
## attuned armour)? Its element column, or Warded, which takes any element.
static func of_element(row: Dictionary, element: String) -> bool:
	return str(row.get("element", "")) == element or str(row.get("id", "")) == BWEffects.WARDED


## D243: a Warded drop's element, from the run seed and the item's uid alone.
static func roll_ward(p_seed: int, uid: String) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = hash("ward|%d|%s" % [p_seed, uid])
	return BWFormulas.ELEMENTS[r.randi() % BWFormulas.ELEMENTS.size()]


static func roll_imbue(p_seed: int, uid: String) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = hash("imbue|%d|%s" % [p_seed, uid])
	return BWFormulas.ELEMENTS[r.randi() % BWFormulas.ELEMENTS.size()]


func random_item(tier: String) -> Dictionary:
	var all := BWData.table("equipment")
	return make_item(str(all[rng.randi() % all.size()].id), tier)


## D200: tiers only unlock families. A row rolls from its own `tier` up; at
## its own tier (D and up) it weighs double, so new rows show up. Cursed rows
## weigh the same as everything else (D201).
static func ench_weight(row: Dictionary, tier: String) -> int:
	var t := TIERS.find(str(row.get("tier", "E")))
	var ti := TIERS.find(tier)
	if t < 0 or t > ti:
		return 0
	return 2 if t == ti and t > 0 else 1


## A weighted pick from [[id, weight]] with one draw of `r`.
static func _weighted(pool: Array, r: RandomNumberGenerator) -> String:
	var total := 0
	for p in pool:
		total += int(p[1])
	if total <= 0:
		return ""
	var k := r.randi() % total
	for p in pool:
		k -= int(p[1])
		if k < 0:
			return str(p[0])
	return str(pool.back()[0])


func _roll_enchant(base_id: String, tier: String = "E") -> String:
	var pool: Array = []
	for e in BWData.table("enchantments"):
		var w := ench_weight(e, tier)
		if w > 0 and base_id in BWData.list(e.applies_to):
			pool.append([str(e.id), w])
	return _weighted(pool, rng)


static func item_name(item: Dictionary) -> String:
	var base := BWData.row("equipment", item.get("base", ""))
	var plain := str(base.get("name", item.get("base", "?")))
	var ench := BWData.row("enchantments", item.get("enchant", ""))
	var imb := str(item.get("imbue", ""))
	if imb != "":
		plain = "%s %s" % [imb.capitalize(), plain]      # D182: "Keen Fire Dagger", "Fire Flamberge of Cleaving"
	var named := plain
	if not ench.is_empty():
		named = str(ench.name_pattern).replace("{item}", plain)
		if str(ench.id) == BWEffects.WARDED and str(item.get("ward", "")) != "":
			named = named.replace("Warded", "%s-Warded" % str(item.ward).capitalize())   # D243
		if BWEffects.cursed(ench):
			named += " " + CURSE_MARK             # D201: a cursed row shows its mark
	return "%s [%s]" % [named, item.get("tier", "E")]


## D201: the curse mark in names (the tile and the card draw their own).
const CURSE_MARK := "†"


## The item's colour element: an armour enchantment's element, or a
## weapon's imbue (D182).
static func item_element(item: Dictionary) -> String:
	var imb := str(item.get("imbue", ""))
	if imb != "":
		return imb
	if str(item.get("enchant", "")) == BWEffects.WARDED:
		return str(item.get("ward", ""))                 # D243: its ward is its colour
	return str(BWData.row("enchantments", item.get("enchant", "")).get("element", ""))


## D180 (author, supersedes the brief's expertise gate): anyone can equip
## anything. Expertise still sets hit chance and the class's skill picks.
func can_equip(_u: BWUnit, item: Dictionary) -> bool:
	return not item.is_empty()


## Equip a loose item. A weapon goes to the main hand, or with `slot`
## "second" (D180) to the carried slot; what was there goes to the inventory.
func equip(u: BWUnit, item: Dictionary, slot: String = "") -> bool:
	if not can_equip(u, item) or not item in inventory:
		return false
	var to := str(item.slot) if slot == "" else slot
	if to == BWUnit.SECOND and str(item.slot) != "main_hand":
		return false
	if to != BWUnit.SECOND and to != str(item.slot):
		return false
	inventory.erase(item)
	var old: Dictionary = u.equipment.get(to, {})
	if not old.is_empty():
		inventory.append(old)
	u.equipment[to] = item
	if to == "main_hand":
		u.weapon_class = item.weight
		u.weapon_model = item.base
	return true


## D180: swap the active and the carried weapon outside a battle (the gear panel).
func swap_weapons(u: BWUnit) -> bool:
	return u.swap_weapons()


func unequip(u: BWUnit, slot: String) -> void:
	if slot == "main_hand":
		return              # never empty-handed (the carried weapon comes off freely)
	var old: Dictionary = u.equipment.get(slot, {})
	if not old.is_empty():
		u.equipment.erase(slot)
		inventory.append(old)


## D203: one head, one chest, one legs piece and two weapons at the current
## tier, then the seven scrolls re-rolled.
func restock_shop() -> void:
	shop.clear()
	var tier := tier_for(fight)
	for slot in SHOP_SLOTS:
		var bases: Array = BWData.table("equipment").filter(func(r): return str(r.slot) == slot)
		shop.append(make_item(str(bases[rng.randi() % bases.size()].id), tier))
	roll_scrolls()


## D203: the seven featured scrolls for this visit: per element, one of its
## element rows unlocked at the shop's tier (D200 weights), from its own rng
## (run seed, fight, element), so the run's own rolls don't move.
func roll_scrolls() -> void:
	scrolls.clear()
	var tier := tier_for(fight)
	for el in BWFormulas.ELEMENTS:
		var pool: Array = []
		for e in BWData.table("enchantments"):
			var w := ench_weight(e, tier)
			if w > 0 and of_element(e, el):
				pool.append([str(e.id), w])
		var r := RandomNumberGenerator.new()
		r.seed = hash("scroll|%d|%d|%s" % [seed_value, fight, el])
		scrolls.append({ "uid": "scroll_%s_%d" % [el, fight], "kind": "scroll", "element": el,
			"enchant": _weighted(pool, r), "tier": tier, "sold": false })


## D203/D236: may `scroll` be used on `target` (an item the run owns: loose,
## or worn by the squad)? Free since D236: no payment.
func can_use_scroll(scroll: Dictionary, target: Dictionary) -> bool:
	if not scroll in scrolls or scroll.get("sold", false) or str(scroll.get("enchant", "")) == "":
		return false
	if target.is_empty():
		return false
	return target in inventory or owner_of(target) != null


## The squad unit wearing or carrying `item`, or null.
func owner_of(item: Dictionary) -> BWUnit:
	for u in squad:
		for slot in GEAR_SLOTS:
			if u.equipment.get(slot, {}) == item:
				return u
	return null


## D203/D236: use the scroll on `target`, free. The scroll is spent until the
## next battle's re-roll (restock_shop).
func use_scroll(scroll: Dictionary, target: Dictionary) -> bool:
	if not can_use_scroll(scroll, target):
		return false
	apply_scroll(scroll, target)
	scroll["sold"] = true
	return true


## D203: what a scroll does to an item. Armour: its enchantment is overwritten
## with the scroll's row. A weapon (D206): its imbue becomes the scroll's element
## AND its row (the imbue's enchantment), replacing any old imbue, at any tier
## (an E/D weapon gains one); the weapon's own enchantment stays (D38).
## Supersedes D203's element-only weapon call.
static func apply_scroll(scroll: Dictionary, item: Dictionary) -> void:
	if str(item.get("slot", "")) == "main_hand":
		item["imbue"] = str(scroll.element)          # D206: the element and its enchantment, together
		item["imbue_enchant"] = str(scroll.enchant)
	else:
		item["enchant"] = str(scroll.enchant)
		if item.enchant == BWEffects.WARDED:
			item["ward"] = str(scroll.element)       # D243: a Warded scroll wards its own element
		else:
			item.erase("ward")


# ---------------------------------------------------------------- trash (D234)

## Set a loose item aside to be thrown away when the next battle starts.
func trash_item(it: Dictionary) -> bool:
	if it.is_empty() or not it in inventory:
		return false
	inventory.erase(it)
	trash.append(it)
	return true


## Take a set-aside item back into the inventory.
func untrash_item(it: Dictionary) -> bool:
	if not it in trash:
		return false
	trash.erase(it)
	inventory.append(it)
	return true


## The battle starts: the pile is gone. Returns how many were thrown away.
func empty_trash() -> int:
	var n := trash.size()
	trash.clear()
	return n


## 1-for-1 trade: give an inventory item, take a shop item. (D202: re-imbue,
## D38/D183, is gone; the shop's scrolls replace it.)
func trade(give: Dictionary, take: Dictionary) -> bool:
	if not give in inventory or not take in shop:
		return false
	inventory.erase(give)
	shop.erase(take)
	inventory.append(take)
	shop.append(give)
	return true


# ---------------------------------------------------------------- abilities

## Fill each unit's BWUnit.abilities from equipped_ability (one per type:
## reactive, supportive, passive), then re-read its effects. Call it on the
## deployed units right before BWBattle.setup().
## Rule: a unit that has learned abilities of a type but has none of that type
## equipped (or an equipped id it no longer knows) auto-equips the first one it
## learned of that type, and the choice is saved. Returns those auto-equips as
## [{unit, type, ability}] for the UI to mention. Units outside the run (the
## enemies) get no abilities.
func prepare_for_battle(units: Array) -> Array:
	var auto: Array = []
	for u in units:
		u.abilities = {}
		if not learned.has(u.id):
			u.refresh_effects()
			continue
		var eq: Dictionary = equipped_ability.get(u.id, {})
		for type in BWEffects.TYPES:
			var id := str(eq.get(type, ""))
			if id != "" and (not id in learned[u.id] or ability_type(id) != type):
				id = ""
			if id == "":
				for ab in learned[u.id]:
					if ability_type(ab) == type:
						id = ab
						break
				if id != "":
					auto.append({ "unit": u.id, "type": type, "ability": id })
			if id == "":
				eq.erase(type)
				continue
			eq[type] = id
			u.abilities[type] = { "id": id, "rank": int(ability_ranks.get(u.id, {}).get(id, 1)) }
		equipped_ability[u.id] = eq
		u.refresh_effects()
	return auto


static func ability_type(ability_id: String) -> String:
	return str(BWData.row("abilities", ability_id).get("type", ""))


## Equip a learned ability into its type's slot (replacing that type's).
func equip_ability(u: BWUnit, ability_id: String) -> bool:
	if not ability_id in learned.get(u.id, []):
		return false
	var type := ability_type(ability_id)
	if type == "":
		return false
	if not equipped_ability.has(u.id):
		equipped_ability[u.id] = {}
	equipped_ability[u.id][type] = ability_id
	return true


# ---------------------------------------------------------------- fights

## D99 enemy scaling (the author kept losing): enemies are set behind the
## player's progress. Fight N builds its enemies at the stage of fight
## N - lag (floored at fight 1): gear tier, levels, and the ranks their perk
## and skill picks come from (ENEMY_RANKS by that tier).
## D133: the lag, a base-stat multiplier and perks on/off are per fight, in
## ENEMY_CURVE (the knobs are data). Fights 1-2 are a gentle start (no perks,
## 90% base stats), the lag then shrinks from 2 to 1 to 0 so the late fights
## bite. The Giant is not on the curve (author: "if we win, we win").
const ENEMY_STAGE_LAG := 2        # the D99 lag; fights past the table use it
## Fight n -> [stage lag, base-stat multiplier, perks on, armour pieces].
## Index 0 = fight 1. D139: armour pieces (head / chest / legs, random slots,
## random bases and enchants at the stage's tier) ramp 0, 1, 2, then all 3.
## D179 re-tune (a level per WON fight, no XP: the squad is ~1-2 levels lower
## than under XP, and a loss no longer levels it): multipliers down from
## D139's 0.9, 1.5, 2.1, 2.2, 2.1, 1.6, 1.8, 1.7, 1.6, 1.75; "mixed", 24
## runs: wins 70 70 78 41 70 70 66 58 54 62 %, the Giant 87 %.
## D194 re-tune (a level after every fight, LEVEL_ON_LOSS; enemy level =
## its stage, BWRooms.LEVELS_PER_STAGE 1; enemies carry a second weapon from
## fight 3, D193): see DECISIONS D194 for the measured table.
## D308 re-tune with the whole Element Overhaul on (keystones and sets both
## sides, weather, the Twins, rooms): fights 1, 3, 5, 6, 8, 10 harder (the
## last measurement had 5-10 at ~92%); fight 7 is the Twins (BWTwins knobs).
const ENEMY_CURVE := [
	[0, 0.97, false, 0], [0, 1.05, false, 1],                     # 1-2: gentle start (fight 1 under full strength), no perks
	[2, 1.95, true, 2], [2, 0.7, true, 3], [2, 1.35, true, 3],    # 3-5: two fights behind (4: the obelisks; the stones set its pace, not this)
	[1, 1.15, true, 3], [1, 1.1, true, 3], [1, 1.1, true, 3],     # 6-8: one behind
	[0, 1.0, true, 3], [0, 1.03, true, 3],                        # 9-10: level with you
]
## D193: enemies carry a second weapon (a random other class) from this fight.
const ENEMY_SECOND_FROM := 3
## Gear tier -> [affinity rank in the unit's own element, expertise rank in
## its weapon]. Expertise also matches the tier, so the weapon is legal.
const ENEMY_RANKS := { "E": [1, 0], "D": [1, 1], "C": [2, 2], "B": [2, 3], "A": [3, 4] }


## Tuning only (tools/campaign_sim_local.gd, env CURVE): replaces ENEMY_CURVE
## while non-empty. The game never sets it.
static var curve_override: Array = []


## D133: fight n's row of ENEMY_CURVE as { lag, mult, perks, armor }.
static func enemy_curve(n: int) -> Dictionary:
	var table: Array = curve_override if not curve_override.is_empty() else ENEMY_CURVE
	if n >= 1 and n <= table.size():
		var row: Array = table[n - 1]
		return { "lag": int(row[0]), "mult": float(row[1]), "perks": bool(row[2]),
			"armor": int(row[3]) if row.size() > 3 else ARMOR_SLOTS.size() }
	return { "lag": ENEMY_STAGE_LAG, "mult": 1.0, "perks": true, "armor": ARMOR_SLOTS.size() }


## The stage fight n's enemies are built at (D99, D133).
static func enemy_stage(n: int) -> int:
	return maxi(1, n - int(enemy_curve(n).lag))


## D133: scale u's base stats (before gear) by `mult`, HP following CON.
## Base stats are small integers (1-6 at fight 1), so rounding each one would
## leave most untouched; instead the base-stat TOTAL is scaled and the points
## are taken from (or, mult > 1, given to) the highest stat first, one at a
## time (ties in STATS order), never below 1. 90% of 26 points = 23: three
## points off the unit's best stats.
static func scale_stats(u: BWUnit, mult: float) -> void:
	var total := 0
	for k in BWUnit.STATS:
		total += int(u.stats[k])
	var delta := roundi(total * mult) - total
	for i in absi(delta):
		var best := ""
		for k in BWUnit.STATS:
			if delta < 0 and int(u.stats[k]) <= 1:
				continue
			if best == "" or int(u.stats[k]) > int(u.stats[best]):
				best = k
		if best == "":
			break
		u.stats[best] = int(u.stats[best]) + signi(delta)
	u.hp = u.max_hp()


## The enemy squad for fight n: three roster characters not in your squad,
## built at enemy_stage(n) (ENEMY_CURVE, D133): levelled, base stats scaled, geared at that stage's tier, ranked by
## ENEMY_RANKS and auto-picked (BWPicks.auto_resolve: perks, then improve /
## learn skills, data order, no rng). The boss is its own thing.
func enemies_for(n: int, room: Dictionary = {}) -> Array:
	var out := _enemies_for(n, room)
	BWKeystones.arm_enemies(out, n, room)          # D279: enemy keystones by stage
	if str(BWRooms.room_for(self, n).get("mode", "") if room.is_empty() else room.get("mode", "")) == "horde":
		BWKeystones.arm_enemies(out.filter(func(u): return u.encounter == ""), n, {})   # D331: the elites are a normal squad
	return out


func _enemies_for(n: int, room: Dictionary = {}) -> Array:
	# D186: a room's squad (`room` from BWRooms; empty = fight n's chosen room,
	# the Standard one until a choice is made)
	if room.is_empty() and n < BOSS_FIGHT:
		room = BWRooms.room_for(self, n)
	if n == TWINS_FIGHT:
		return BWTwins.build(self, n)                  # D256: the mid-run boss
	if str(room.get("mode", "")) == "horde":
		return BWHordeMode.build(self, n)              # D331: the waves
	if str(room.get("mode", "")) == "defend":
		return BWCastleDefend.build(self, n)           # D341: raiders and their waves
	if str(room.get("mode", "")) == "storm":
		return BWCastleStorm.build(self, n)            # D341: guards, the Warden, reinforcements
	if str(room.get("encounter", "")) != "":
		return BWEncounters.build(self, n, str(room.encounter))   # D208: a special encounter
	var build := BWRooms.enemy_build(n, str(room.get("kind", BWRooms.STANDARD)))
	var erng := RandomNumberGenerator.new()
	erng.seed = seed_value * 7919 + n + (104729 if room.get("kind", "") == BWRooms.HARD else 0)
	if n >= BOSS_FIGHT:
		var boss := make_boss()
		seed_unit(boss)                  # D174
		BWPicks.auto_resolve(boss)
		return [boss]
	var out: Array = []
	var stage := int(build.stage)        # D188: a Hard room builds further on
	var curve := build
	var tier := tier_for(stage)
	var ranks: Array = ENEMY_RANKS[tier]
	for id in room.enemies:
		var row: Dictionary = roster_row(str(id))
		var u := BWUnit.from_roster(row)
		u.id = "%s_f%d" % [u.id, n]
		seed_unit(u)                     # D174: its two-card picks, from the run seed
		var levels := int(build.levels)
		BWProgression.level_up(u, levels)          # D179: levels, not XP
		scale_stats(u, float(curve.mult) * (BWSplitFront.ENEMY_MULT if str(room.get("mode", "")) == "splitfront" else 1.0))   # D334
		var save := rng.state
		rng.seed = erng.randi()
		u.equipment["main_hand"] = make_item(u.weapon_model, tier)
		# D139: curve.armor pieces in random slots, random bases, the stage's tier.
		var slots: Array = ARMOR_SLOTS.duplicate()
		for k in mini(int(curve.armor), slots.size()):
			var slot: String = slots.pop_at(erng.randi() % slots.size())
			var bases: Array = BWData.table("equipment").filter(func(r): return r.slot == slot)
			var a: Dictionary = bases[erng.randi() % bases.size()]
			u.equipment[slot] = make_item(str(a.id), tier)
		# D193: from fight ENEMY_SECOND_FROM a carried weapon of a random
		# other class at the same tier (and the same expertise), for the AI's swap (D181).
		var wc2 := ""
		if n >= ENEMY_SECOND_FROM:
			var others: Array = weapon_classes().filter(func(c): return c != u.weapon_class)
			wc2 = str(others[erng.randi() % others.size()])
			var models: Array = BWData.table("equipment").filter(func(r): return str(r.slot) == "main_hand" and str(r.weight) == wc2)
			if not models.is_empty():
				u.equipment[BWUnit.SECOND] = make_item(str(models[erng.randi() % models.size()].id), tier)
			else:
				wc2 = ""
		rng.state = save
		if u.element != "":
			u.affinity[u.element] = maxi(int(u.affinity.get(u.element, 0)), int(ranks[0]) * BWUnit.POINTS_PER_RANK)
		u.expertise[u.weapon_class] = int(ranks[1]) * BWUnit.POINTS_PER_RANK
		if wc2 != "":
			u.expertise[wc2] = int(ranks[1]) * BWUnit.POINTS_PER_RANK
		BWPicks.auto_resolve(u)          # D90/D99: perks and skills from those ranks, the AI's way
		if not curve.perks:
			u.perks.clear()              # D133: no perk picks this fight (skills stand)
			u.refresh_effects()
		out.append(u)
	return out


## Brief: "a giant guy, ~500 HP and 50 in every other stat. Players are meant
## to die here." size 2: it covers its centre and the 6 hexes around it.
## BWBattle.setup() places it on an enemy spawn its ring fits, or the nearest
## hex that fits; tiles affect it at its centre only (E15).
func make_boss() -> BWUnit:
	var row := { "id": "boss", "name": "The Giant", "weapon_class": "axe", "weapon_model": "anchor",
		"element": "dark", "friendliness": "unfriendly" }
	for s in BWUnit.STATS:
		row[s] = 50
	var b := BWUnit.from_roster(row)
	b.size = 2
	b.fixed_hp = 500         # D138: the brief's 500, exempt from the D137 HP formula
	b.hp = b.max_hp()
	return b


## After a fight: loot, ability learning, trust, recruits, advance.
## `deployed` are the squad units that fought; `defeated` the enemy units KO'd.
## D140: `objectives` (the battle's obelisks) join the summary's tally only:
## damage on a stone counts as dealt; they are not loot and not recruits.
func after_fight(won: bool, deployed: Array, defeated: Array, enemies: Array, history: Array, objectives: Array = []) -> Dictionary:
	var report := { "won": won, "loot": [], "learned": [], "fight": fight }
	if not objectives.is_empty():
		report["objective"] = objectives.map(func(o): return { "id": o.id, "name": o.name, "hp": o.hp, "max": o.max_hp(), "broken": not o.alive() })
	report["stats"] = BWBattleStats.tally(history, deployed + enemies + objectives)
	record_stats(won, report.stats, deployed)
	var room := BWRooms.close_fight(self)          # D186-D188: log the room, move the map queue on
	report["room"] = str(room.get("kind", BWRooms.STANDARD))
	report["map"] = str(room.get("map", ""))
	if room.has("encounter"):
		report["encounter"] = str(room.encounter)
	if str(room.get("mode", "")) != "":
		report["mode"] = str(room.mode)                # D327: the 6v6 mode, named on the results
	if str(room.get("weather", "")) != "":
		report["weather"] = str(room.weather)          # D249
	if won:
		var hard: bool = report.room == BWRooms.HARD
		var enc: bool = room.has("encounter")         # D208: an encounter pays as a three-enemy Hard room
		var drops := (DEPLOY if enc else defeated.size()) + (BWRooms.HARD_EXTRA_DROPS if hard else 0)
		if report.has("mode"):
			drops = MODE_DROPS                         # D334
		if hard and str(room.get("weather", "")) != "":
			drops += BWWeather.HARD_EXTRA_DROPS        # D249: a Hard room in weather pays one more
		for i in drops:
			var item := random_item(BWRooms.loot_tier(self, report.room))   # D188: Hard pays a tier up
			inventory.append(item)
			report.loot.append(item)
	for u in deployed:
		for slot in SLOTS:
			var item: Dictionary = u.equipment.get(slot, {})
			if item.is_empty():
				continue
			item.worn[u.id] = int(item.worn.get(u.id, 0)) + 1
			if item.worn[u.id] == LEARN_BATTLES:
				for ab in BWData.list(BWData.row("equipment", item.base).get("ability_id", "")):
					if not ab in learned[u.id]:
						learned[u.id].append(ab)
						ability_ranks[u.id][ab] = 1
						report.learned.append({ "unit": u.id, "ability": ab })
	# Trust (design/BARKS.md): +1 per fight together, +2 per KO save.
	for i in deployed.size():
		for j in range(i + 1, deployed.size()):
			add_trust(deployed[i].id, deployed[j].id, 1)
	last_enemies = enemies.filter(func(e): return e.encounter == "").map(func(e): return e.to_dict())   # D208: encounter bodies don't join
	# D179/D194: every fight, won or lost, levels every squad unit, deployed or benched (no XP).
	if won and fight == TWINS_FIGHT:
		report["twins_reward"] = BWTwins.reward(self)  # D258: a pick each (two cards, D174)
	report["levels"] = {}
	if won or BWProgression.LEVEL_ON_LOSS:
		for u in squad:
			var ev: Array = BWProgression.level_up(u, 1)
			report.levels[u.id] = ev[0].gains
	# Author 2026-10-04 (supersedes D39): a lost fight doesn't end the run. You
	# keep the growth, get no spoils, and move on to the next fight.
	# The Giant is still the end either way.
	if won or fight < BOSS_FIGHT:
		fight += 1
		restock_shop()
	return report


static func new_stats() -> Dictionary:
	return { "won": 0, "lost": 0, "untracked": 0, "units": {}, "best": {} }


## D121: fold one battle's summary into the run's tallies.
func record_stats(won: bool, bs: Dictionary, deployed: Array) -> void:
	stats[("won" if won else "lost")] = int(stats.get("won" if won else "lost", 0)) + 1
	for u in deployed:
		var s: Dictionary = stats.units.get(u.id, { "fights": 0, "kos": 0, "damage": 0, "taken": 0, "mvp": 0 })
		var b: Dictionary = bs.get("units", {}).get(u.id, {})
		s.fights = int(s.fights) + 1
		s.kos = int(s.kos) + int(b.get("kos", 0))
		s.damage = int(s.damage) + int(b.get("dealt_total", 0))
		s.taken = int(s.taken) + int(b.get("taken", 0))
		if bs.get("mvp", "") == u.id:
			s.mvp = int(s.mvp) + 1
		stats.units[u.id] = s
	for h in bs.get("highlights", []):
		if stats.best.is_empty() or float(h.score) > float(stats.best.score):
			stats.best = { "text": h.text, "score": float(h.score), "fight": fight }


func add_trust(a: String, b: String, pts: int) -> void:
	var k := trust_key(a, b)
	trust[k] = int(trust.get(k, 0)) + pts


static func trust_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func trust_stage(a: String, b: String) -> String:
	var p := int(trust.get(trust_key(a, b), 0))
	return "trusted" if p >= 8 else ("acquainted" if p >= 3 else "strangers")


# ---------------------------------------------------------------- downtime (D127-D131)

## D127: the day. Each unit takes one of three choices (the screen shows the
## names only). Returns one report per unit, in the first person, for the
## per-unit result cards:
##   { unit, name, choice, ok, headline, text (= headline), lines: [{ text,
##     element, item }], items: [found items], successes: [wander effects],
##     jackpot, levels }
##   Branch out also carries `options` ([{ element, weapon }], one or two:
##   the day's branch_preview, D176) and `pending` until branch_pick()
##   applies one. `option` >= 0 = the card the player took in the hall
##   (D176: chosen before the day, applied at once); else `auto` = the first,
##   at once (the AI's and the sim's way); else it waits for branch_pick.
## This doesn't police day_choices (D175): the screen and the sims offer
## only the day's two.
func downtime(u: BWUnit, choice: String, auto: bool = true, option: int = -1) -> Dictionary:
	var rep := { "unit": u.id, "name": u.name, "choice": choice, "ok": true, "headline": "",
		"lines": [], "items": [], "successes": [], "jackpot": false, "levels": 0 }
	var lv := u.level
	match choice:
		"specialize": _specialize(u, rep)
		"branch_out":
			_branch_out(u, rep)
			if rep.get("pending", false) and (option >= 0 or auto):
				branch_pick(u, rep, clampi(option, 0, rep.options.size() - 1))
		"wander": _wander(u, rep)
		_:
			rep.ok = false
			rep.headline = "I didn't know what to do with %s." % choice
	rep.levels = u.level - lv
	rep["text"] = rep.headline
	return rep


## Run a day: every [unit id, choice] (or [unit id, "branch_out", card
## index], D176) in order. Returns the reports. `auto` false leaves a Branch
## out without a card index for the player (branch_pick).
func progress_day(plan: Array, auto: bool = true) -> Array:
	var out: Array = []
	recruited_today = false
	for p in plan:
		var u := unit(str(p[0]))
		if u:
			out.append(downtime(u, str(p[1]), auto, int(p[2]) if p.size() > 2 else -1))
	day += 1
	return out


## D174: a unit's pick salt, from the run seed and its id (never saved).
## D233 (author, playtest 1: "autopick it at random and skip the selection
## phase"): a unit's first perk, rank 1 in its own element, is drawn at random
## from all of that element's perks, from its own rng (the run seed + the unit
## id), so the run's rng stream doesn't move. Later picks keep the two cards.
## Returns the perk id, or "" when the unit already has one (or can't).
func auto_first_perk(u: BWUnit) -> String:
	var el := str(u.element)
	if el == "" or not BWPicks.owned(u, el).is_empty() or BWPicks.allowance(u, el) < 1:
		return ""
	var pool: Array = BWPicks.perks_of(el)
	if pool.is_empty():
		return ""
	var r := RandomNumberGenerator.new()
	r.seed = hash("first_perk|%d|%s" % [seed_value, u.id])
	var id := str(pool[r.randi() % pool.size()].id)
	u.perks.append(id)
	return id


## D233: the unit's first perk in its own element (what the hall shows), or "".
static func first_perk(u: BWUnit) -> String:
	var own: Array = BWPicks.owned(u, str(u.element))
	return str(own[0]) if not own.is_empty() else ""


func seed_unit(u: BWUnit) -> void:
	u.pick_seed = hash("picks|%d|%s" % [seed_value, u.id])


## D175: the day's DOWNTIME_OFFER choices for `u` (DOWNTIME_CHOICES order),
## drawn from the run seed, the day and the unit id: stable all day, fresh
## each day, reproducible.
func day_choices(u: BWUnit) -> Array:
	var drop := absi(hash("day|%d|%d|%s" % [seed_value, day, u.id])) % DOWNTIME_CHOICES.size()
	var out: Array = DOWNTIME_CHOICES.duplicate()
	out.remove_at(drop)
	return out


## D176: the Branch out cards `u` would get today ([{ element, weapon }], one
## or two; empty = nothing new left). Rolled once a day per unit on its own
## rng (run seed, day, unit id; the run's rng is untouched), then kept, so
## the hall can show them before the player commits and Branch out gives
## exactly those.
func branch_preview(u: BWUnit) -> Array:
	if _branch_day != day:
		_branch_cards = {}
		_branch_day = day
	if not _branch_cards.has(u.id):
		var brng := RandomNumberGenerator.new()
		brng.seed = hash("branch|%d|%d|%s" % [seed_value, day, u.id])
		_branch_cards[u.id] = branch_options(u, brng)
	return (_branch_cards[u.id] as Array).duplicate(true)


## Specialize: +half a rank in the unit's focus element (D132) and its weapon
## class; 50% a free skill pick in the class (else a weapon of that class),
## 50% a free perk pick in the element (else armour attuned to it).
func _specialize(u: BWUnit, rep: Dictionary) -> void:
	var el := u.focus()                          # D132: the focus element (native by default)
	var wc := u.weapon_class
	var gained: Array = []
	if el != "":
		var before := u.affinity_rank(el)
		u.affinity[el] = int(u.affinity.get(el, 0)) + SPECIALIZE_POINTS
		gained.append("%s affinity" % el)
		_line(rep, "+half a level in %s affinity%s" % [el,
			"  (now rank %d)" % u.affinity_rank(el) if u.affinity_rank(el) > before else ""], el)
	var letter := u.expertise_letter(wc)
	u.expertise[wc] = int(u.expertise.get(wc, 0)) + SPECIALIZE_POINTS
	gained.append("%s expertise" % class_name_of(wc))
	_line(rep, "+half a level in %s expertise%s" % [class_name_of(wc),
		"  (now %s)" % u.expertise_letter(wc) if u.expertise_letter(wc) != letter else ""])
	if rng.randf() < SPECIALIZE_ROLL and grant_skill_pick(u, wc):
		gained.append("%s %s skill point" % [_a(class_name_of(wc)), class_name_of(wc)])
		_line(rep, "A free %s skill point" % class_name_of(wc))
	else:
		var w := _find_weapon(rep, wc, tier_for(fight))
		if not w.is_empty():
			gained.append(item_name(w))
			_line(rep, "New equipment: " + item_name(w), item_element(w), w)
	if el != "" and rng.randf() < SPECIALIZE_ROLL and grant_perk_pick(u, el):
		gained.append("%s %s perk point" % [_a(el), el])
		_line(rep, "A free %s perk point" % el, el)
	elif el != "":
		var a := _find_armour(rep, el, tier_for(fight))
		if not a.is_empty():
			gained.append(item_name(a))
			_line(rep, "New equipment: " + item_name(a), el, a)
	rep.headline = "I specialized and gained %s, feeling confident." % _and(gained)


## Branch out (D128): up to two options, each a pairing of a new element
## (one at rank 0) and a new weapon class (another one still at E), for the
## player to pick from on the result card. Nothing left at all: +1 to a
## random stat (D179; was +50 XP) and a line saying so.
func _branch_out(u: BWUnit, rep: Dictionary) -> void:
	rep["options"] = branch_preview(u)           # D176: the cards the hall showed
	if rep.options.is_empty():
		var s := _stat_point(u)
		rep.headline = "I branched out, but there was nothing new left to try. The practice did me good (+1 %s)." % s.to_upper()
		return
	rep["pending"] = true
	rep.headline = "I branched out. Which way should I go?"


## The day's Branch out options: [{ element, weapon }], two distinct
## pairings where the unit has room for two, else one ("" = that half has
## nothing left). Rolled on `roll` (branch_preview's day rng), else the run's.
func branch_options(u: BWUnit, roll: RandomNumberGenerator = null) -> Array:
	var els: Array = BWFormulas.ELEMENTS.filter(func(e): return u.affinity_rank(e) == 0)
	var wcs: Array = weapon_classes().filter(func(c): return c != u.weapon_class and u.expertise_rank(c) == 0)
	_shuffle(els, roll)
	_shuffle(wcs, roll)
	var out: Array = []
	for k in mini(2, maxi(els.size(), wcs.size())):
		out.append({ "element": els[mini(k, els.size() - 1)] if not els.is_empty() else "",
			"weapon": wcs[mini(k, wcs.size() - 1)] if not wcs.is_empty() else "" })
	return out


## Apply the Branch out option the player took: a full rank in its element
## and its class (each owes its first pick through the normal flow), a weapon
## of that class and armour attuned to that element (this fight's tier).
## False if `rep` has nothing pending or `i` is out of range.
func branch_pick(u: BWUnit, rep: Dictionary, i: int) -> bool:
	if not rep.get("pending", false) or i < 0 or i >= rep.options.size():
		return false
	var lv := u.level
	var opt: Dictionary = rep.options[i]
	var new_el := str(opt.element)
	var new_wc := str(opt.weapon)
	rep.pending = false
	rep["picked"] = i
	if new_el != "":
		u.affinity[new_el] = int(u.affinity.get(new_el, 0)) + BRANCH_POINTS
		_line(rep, "A full level in %s affinity  (rank %d)" % [new_el, u.affinity_rank(new_el)], new_el)
	if new_wc != "":
		u.expertise[new_wc] = int(u.expertise.get(new_wc, 0)) + BRANCH_POINTS
		_line(rep, "A full level in %s expertise  (now %s)" % [class_name_of(new_wc), u.expertise_letter(new_wc)])
		# D192: the find is the fight's tier. Expertise no longer gates
		# equipping (D180), so it isn't capped at the new letter.
		var w := _find_weapon(rep, new_wc, tier_for(fight))
		if not w.is_empty():
			_line(rep, "New equipment: " + item_name(w), item_element(w), w)
	if new_el != "":
		var a := _find_armour(rep, new_el, tier_for(fight))
		if not a.is_empty():
			_line(rep, "New equipment: " + item_name(a), new_el, a)
	var can: Array = []
	if new_el != "":
		can.append(new_el)
	if new_wc != "":
		can.append("the " + class_name_of(new_wc))
	rep.headline = "I branched out and now can use %s." % " and ".join(can)
	rep["text"] = rep.headline
	rep.levels = int(rep.get("levels", 0)) + u.level - lv
	return true


func _shuffle(a: Array, roll: RandomNumberGenerator = null) -> void:
	var g := roll if roll != null else rng
	for i in range(a.size() - 1, 0, -1):
		var j := g.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## Wander: each of WANDER_EFFECTS rolled on its own at WANDER_ROLL (one that
## can't happen counts as a miss). All nine missed: the consolation, +1 to a
## random stat (D179), unless WANDER_JACKPOT_EXTRA_ROLL lands (D177,
## replacing D129's +5000 XP and the rogue): the nine are rolled again at
## WANDER_JACKPOT_ROLL each (one recruit a day still); if those all miss
## too, the consolation.
func _wander(u: BWUnit, rep: Dictionary) -> void:
	_wander_rolls(u, rep, WANDER_ROLL)
	if not rep.successes.is_empty():
		rep.headline = "I wandered off for the day. Here's what happened:"
		return
	if rng.randf() < WANDER_JACKPOT_EXTRA_ROLL:
		rep.jackpot = true
		_wander_rolls(u, rep, WANDER_JACKPOT_ROLL)
		if not rep.successes.is_empty():
			rep.headline = "I wandered and ran into a being of unlimited benevolence…"
			return
		var s0 := _stat_point(u)
		rep.headline = "I wandered and ran into a being of unlimited benevolence… it just smiled. I feel a little stronger for it (+1 %s)" \
			% s0.to_upper()
		return
	var s := _stat_point(u)
	rep.headline = "I wandered. Nothing happened, but the walk did me good (+1 %s)" % s.to_upper()


## D179: +WANDER_STAT_POINT to a random base stat, for good. Returns the stat.
func _stat_point(u: BWUnit) -> String:
	var s: String = BWUnit.STATS[rng.randi() % BWUnit.STATS.size()]
	u.stats[s] = mini(int(u.stats.get(s, 0)) + WANDER_STAT_POINT, BWUnit.STAT_CAP)
	return s


## Each of WANDER_EFFECTS rolled on its own at `chance`; the hits go into
## rep.successes (and their lines). The recruit is skipped once someone has
## recruited today (D129: a skipped roll is a miss).
func _wander_rolls(u: BWUnit, rep: Dictionary, chance: float) -> void:
	for eff in WANDER_EFFECTS:
		if eff == "recruit" and recruited_today:
			continue
		if rng.randf() < chance and _wander_effect(u, str(eff), rep):
			rep.successes.append(eff)


## One wander effect. False when it can't happen (a missed roll).
func _wander_effect(u: BWUnit, eff: String, rep: Dictionary) -> bool:
	match eff:
		"stat":                                  # D179: was +50 XP
			var s := _stat_point(u)
			_line(rep, "The road toughened me up.  (+%d %s, for good)" % [WANDER_STAT_POINT, s.to_upper()])
		"element":
			var els: Array = BWFormulas.ELEMENTS.filter(func(e): return u.affinity_rank(e) < BWUnit.MAX_AFFINITY_RANK)
			if els.is_empty():
				return false
			var el: String = els[rng.randi() % els.size()]
			u.affinity[el] = int(u.affinity.get(el, 0)) + BRANCH_POINTS
			_line(rep, "Something out there taught me %s.  (a full level: rank %d)" % [el, u.affinity_rank(el)], el)
		"weapon":
			var wcs: Array = weapon_classes().filter(func(c): return u.expertise_rank(c) < BWUnit.EXPERTISE_RANKS.size() - 1)
			if wcs.is_empty():
				return false
			var wc: String = wcs[rng.randi() % wcs.size()]
			u.expertise[wc] = int(u.expertise.get(wc, 0)) + BRANCH_POINTS
			_line(rep, "I picked up a few tricks with the %s.  (a full level: %s)" % [class_name_of(wc), u.expertise_letter(wc)])
		"find_weapon", "find_armour":
			var t := tier_index(fight)
			var up := rng.randf() < 0.5 and t < TIERS.size() - 1
			var tier: String = TIERS[t + 1 if up else t]
			var weapon := eff == "find_weapon"
			var pool: Array = BWData.table("equipment").filter(func(r): return (str(r.slot) == "main_hand") == weapon)
			var it := make_item(str(pool[rng.randi() % pool.size()].id), tier)
			inventory.append(it)
			rep.items.append(it)
			var fmt := "I found something lying in the grass: %s%s" if weapon else "Someone left this by the road: %s%s"
			_line(rep, fmt % [item_name(it), "  (a tier up!)" if up else ""], item_element(it), it)
		"recruit":
			var nu := recruit()
			if nu == null:
				return false
			recruited_today = true
			_line(rep, "I ran into %s from the last fight. They're with us now." % nu.name)
		"status_immunity":
			var left: Array = IMMUNE_STATUSES.filter(func(s): return not s in u.next_immune)
			if left.is_empty():
				return false
			var st: String = left[rng.randi() % left.size()]
			u.next_immune.append(st)
			_line(rep, "I'll shrug off %s for the next fight." % SHRUG.get(st, st))
		"element_brace":
			var left: Array = BWFormulas.ELEMENTS.filter(func(e): return not e in u.next_brace)
			if left.is_empty():
				return false
			var el: String = left[rng.randi() % left.size()]
			u.next_brace.append(el)
			_line(rep, "I'm braced against %s for the next fight.  (-%d%% %s damage, no %s statuses)" % [
				el, roundi((1.0 - BWUnit.BRACE_TAKEN) * 100), el, el], el)
		"stat_buff":
			var s: String = BWUnit.STATS[rng.randi() % BWUnit.STATS.size()]
			u.fight_buff[s] = int(u.fight_buff.get(s, 0)) + WANDER_STAT_BUFF
			_line(rep, "I feel sharp.  (+%d %s for the next battle)" % [WANDER_STAT_BUFF, s.to_upper()])
		_:
			return false
	return true


## D128: a free weapon-skill pick in `wc` on top of what the letters grant.
## False (nothing granted) when there would be nothing left to choose.
func grant_skill_pick(u: BWUnit, wc: String) -> bool:
	if BWPicks.skill_choices(u, wc).size() <= BWPicks.skill_picks_owed(u, wc):
		return false
	u.bonus_skills[wc] = int(u.bonus_skills.get(wc, 0)) + 1
	return true


## D128: a free perk pick in `el` that doesn't move the rank. False when the
## unit already has (or is already owed) every perk of the element.
func grant_perk_pick(u: BWUnit, el: String) -> bool:
	if BWPicks.allowance(u, el) >= BWPicks.perks_of(el).size():     # D277: the ladder caps at 4
		return false
	u.bonus_perks[el] = int(u.bonus_perks.get(el, 0)) + 1
	return true


## A past enemy (the first of the last fight's, or `id`) joins the squad, with
## a pair of tier-E fists for the inventory (D76). Null if nobody is left, or
## the roster can't spare one (can_recruit).
func recruit(id: String = "") -> BWUnit:
	var pick: Dictionary = {}
	for e in last_enemies:
		if id == "" or e.id == id:
			pick = e
			break
	if pick.is_empty() or not can_recruit():
		return null
	last_enemies.erase(pick)
	var base_id := str(pick.id).split("_f")[0]
	var nu := BWUnit.from_roster(roster_row(base_id))
	nu.equipment["main_hand"] = make_item(nu.weapon_model, tier_for(fight))
	# D179: joins at the squad's level (the highest in it), grown from its
	# roster stats the way a squad unit grows (not the enemy's scaled sheet).
	BWProgression.level_up(nu, squad_level() - nu.level)
	var fists: Array = BWData.table("equipment").filter(func(row): return str(row.weight) == "fists")
	if not fists.is_empty():
		inventory.append(make_item(str(fists[rng.randi() % fists.size()].id), "E"))
	seed_unit(nu)                        # D174
	auto_first_perk(nu)                  # D233
	squad.append(nu)
	learned[nu.id] = []
	ability_ranks[nu.id] = {}
	equipped_ability[nu.id] = {}
	return nu


## Room for one more recruit: the enemies of later fights are roster
## characters outside the squad, so DEPLOY of them must stay outside.
func can_recruit() -> bool:
	var outside := roster_rows.filter(func(r): return unit(str(r.id)) == null).size()
	return outside > DEPLOY


## A weapon of class `wc` (a random model of it, random enchantment), into the inventory.
func _find_weapon(rep: Dictionary, wc: String, tier: String) -> Dictionary:
	var models: Array = BWData.table("equipment").filter(func(r): return str(r.slot) == "main_hand" and str(r.weight) == wc)
	if models.is_empty():
		return {}
	var w := make_item(str(models[rng.randi() % models.size()].id), tier)
	inventory.append(w)
	rep.items.append(w)
	return w


## An armour piece attuned to `el` (a random enchantment of the element on a
## random piece it applies to), into the inventory.
func _find_armour(rep: Dictionary, el: String, tier: String) -> Dictionary:
	var pairs: Array = []
	for e in BWData.table("enchantments"):
		if not of_element(e, el) or ench_weight(e, tier) <= 0:
			continue
		for b in BWData.list(e.applies_to):
			if str(BWData.row("equipment", b).get("slot", "main_hand")) != "main_hand":
				pairs.append([str(b), str(e.id)])
	if pairs.is_empty():
		return {}
	var p: Array = pairs[rng.randi() % pairs.size()]
	var a := make_item(p[0], tier, p[1])
	if a.enchant == BWEffects.WARDED:
		a["ward"] = el                               # D243
	inventory.append(a)
	rep.items.append(a)
	return a


## D179: the squad's level, the highest among its units (all equal unless an
## old save brought different levels in).
func squad_level() -> int:
	var lv := 1
	for u in squad:
		lv = maxi(lv, u.level)
	return lv


func _line(rep: Dictionary, text: String, element: String = "", item: Dictionary = {}) -> void:
	rep.lines.append({ "text": text, "element": element, "item": item })


## "a" or "an" for a word.
static func _a(word: String) -> String:
	return "an" if word.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a"


## "a and b", "a, b, and c".
static func _and(parts: Array) -> String:
	if parts.size() <= 2:
		return " and ".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + ", and " + str(parts.back())


static func weapon_classes() -> Array:
	return BWData.table("weapons").map(func(r): return str(r.id))


## A weapon class's display name, lower case ("sword", "daggers").
static func class_name_of(wc: String) -> String:
	return str(BWData.row("weapons", wc).get("name", wc)).to_lower()


## JSON brings ints back as floats: { k: int }.
static func _ints(d: Variant) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k in d:
			out[str(k)] = int(d[k])
	return out


static func tier_index(n: int) -> int:
	return clampi((n - 1) / 2, 0, TIERS.size() - 1)


# ---------------------------------------------------------------- picks (D90)

## Every squad unit's next owed pick: [[unit, request], ...] in squad order.
## The screens ask these at once (run start, after the day's results); none
## may be carried into the next screen.
func pending_picks() -> Array:
	var out: Array = []
	for u in squad:
		var req := BWPicks.next_request(u)
		if not req.is_empty():
			out.append([u, req])
	return out


# ---------------------------------------------------------------- save

func to_dict() -> Dictionary:
	var sq: Array = []
	for u in squad:
		var d: Dictionary = u.to_dict()
		d["equipment"] = u.equipment.duplicate(true)
		sq.append(d)
	return {
		# seed and rng state as strings: JSON numbers are doubles and would truncate them
		"version": SAVE_VERSION, "seed": str(seed_value), "rng_state": str(rng.state), "fight": fight, "day": day,
		"squad": sq, "inventory": inventory.duplicate(true), "trash": trash.duplicate(true), "trust": trust.duplicate(),
		"last_enemies": last_enemies.duplicate(true), "shop": shop.duplicate(true), "scrolls": scrolls.duplicate(true),
		"learned": learned.duplicate(true), "ability_ranks": ability_ranks.duplicate(true),
		"equipped_ability": equipped_ability.duplicate(true), "uid": _uid,
		"stats": stats.duplicate(true),
		"map_order": (map_order if not map_order.is_empty() else shuffled_maps(seed_value)).duplicate(),   # D145
		"map_queue": map_queue.duplicate(), "room_offer": room_offer.duplicate(true), "room_log": room_log.duplicate(true),   # D189
		"roster_seed": str(roster_seed), "roster": roster_rows.duplicate(true),
	}


## D150: a save this build can load (version 5+: the renamed, rolled roster).
static func can_load(d: Variant) -> bool:
	return d is Dictionary and int(d.get("version", 1)) >= OLDEST_LOADABLE and d.has("roster")


## A row of this run's roster by id ({} when unknown).
func roster_row(id: String) -> Dictionary:
	return BWRosterGen.row_by_id(roster_rows, id)


static func from_dict(d: Dictionary) -> BWRun:
	var r := BWRun.new()
	var version := int(d.get("version", 1))
	r.seed_value = str(d.seed).to_int()
	# D150: the rolled rows come back as they were (JSON floats -> ints for the stats)
	r.roster_seed = str(d.get("roster_seed", "-1")).to_int()
	r.roster_rows = []
	for row in d.get("roster", BWData.table("roster")):
		var rr: Dictionary = Dictionary(row).duplicate()
		for k in BWUnit.STATS + ["seat"]:
			if rr.has(k):
				rr[k] = int(rr[k])
		r.roster_rows.append(rr)
	r.rng.seed = r.seed_value
	r.rng.state = str(d.rng_state).to_int()
	# D145: the saved map order (an older save: the same shuffle from its seed)
	r.map_order = Array(d.get("map_order", [])).map(func(m): return str(m))
	if r.map_order.size() != MAP_POOL.size():
		r.map_order = shuffled_maps(r.seed_value)
	r.fight = int(d.fight)
	r.day = int(d.day)
	BWRooms.load_state(r, d)                     # D189: the map queue, the offer, the log (v6-: migrated)
	for ud in d.squad:
		var u := BWUnit.from_roster(r.roster_row(str(ud.id)))
		u.element = str(ud.get("element", u.element))
		u.name = ud.name
		u.weapon_class = ud.weapon_class
		u.weapon_model = ud.weapon_model
		u.stats = ud.stats.duplicate()
		u.level = int(ud.level)
		# D179: no XP; an old save's "xp" is ignored, its level kept
		u.affinity = ud.affinity.duplicate()
		u.expertise = ud.expertise.duplicate()
		u.equipment = ud.equipment.duplicate(true)
		# D90/D91 picks (save version 2)
		u.perks = Array(ud.get("perks", [])).duplicate()
		u.keystones = Array(ud.get("keystones", [])).map(func(x): return str(x))   # D277 (v11)
		BWKeystones.enforce_cap(u)                    # D302: never more than 2
		if version < 11:
			u.perks = migrate_perks_v11(u.perks)          # D283: the 4-per-element re-cut
		u.known_skills = Array(ud.get("known_skills", [])).duplicate()
		u.skill_ranks = _ints(ud.get("skill_ranks", {}))
		u.skill_picks = _ints(ud.get("skill_picks", {}))
		u.skill_loadout = Dictionary(ud.get("skill_loadout", {})).duplicate(true)
		# D132 save v4: the downtime outcomes that last (defaults when older)
		u.bonus_perks = _ints(ud.get("bonus_perks", {}))
		u.bonus_skills = _ints(ud.get("bonus_skills", {}))
		# D177: the rogue is gone; an old save's "rogue" flag is dropped here
		r.seed_unit(u)                   # D174: derived, never saved
		u.next_immune = Array(ud.get("next_immune", [])).map(func(x): return str(x))
		u.next_brace = Array(ud.get("next_brace", [])).map(func(x): return str(x))
		u.fight_buff = _ints(ud.get("fight_buff", {}))
		u.focus_element = str(ud.get("focus_element", ""))
		u.sync_weapon()                  # D131: the class follows the main hand
		if version < 2:
			# Migration 1 → 2: the save predates picks. Whatever the ranks
			# already owe is picked the AI's way (BWPicks.auto_choice), so the
			# run resumes with nothing banked.
			BWPicks.auto_resolve(u)
		u.hp = u.max_hp()
		r.squad.append(u)
	r.inventory = d.inventory.duplicate(true)
	r.trash = Array(d.get("trash", [])).duplicate(true)     # D234 (older saves: none)
	migrate_imbues(r.inventory, r.seed_value)              # D206 (save v9)
	for u in r.squad:
		migrate_imbues(u.equipment.values(), r.seed_value)
	if version < 10:                                       # D247 (save v10)
		for list in [r.inventory, r.trash]:
			migrate_v10(list, r.seed_value)
		for u in r.squad:
			migrate_v10(u.equipment.values(), r.seed_value)
	if version < 11:                                       # D283 (save v11)
		for list in [r.inventory, r.trash]:
			migrate_v11(list, r.seed_value)
		for u in r.squad:
			migrate_v11(u.equipment.values(), r.seed_value)
	r.trust = d.trust.duplicate()
	r.last_enemies = d.last_enemies.duplicate(true)
	r.shop = d.shop.duplicate(true)
	migrate_imbues(r.shop, r.seed_value)                   # D206
	r.scrolls = Array(d.get("scrolls", [])).duplicate(true)      # D203 (save v8)
	if version < 11:
		if version < 10:
			migrate_v10(r.shop, r.seed_value)              # D247
		migrate_v11(r.shop, r.seed_value)                  # D283
		for sc in r.scrolls:
			if BWData.row("enchantments", str(sc.get("enchant", ""))).is_empty():
				r.scrolls = []                             # a scroll of a gone row: re-roll the seven
				break
	if r.scrolls.size() != BWFormulas.ELEMENTS.size():
		r.roll_scrolls()
	r.learned = d.learned.duplicate(true)
	r.ability_ranks = d.ability_ranks.duplicate(true)
	r.equipped_ability = d.equipped_ability.duplicate(true)
	if version < 10:
		r.migrate_abilities_v10()                          # D247
	r._uid = int(d.uid)
	r.stats = _load_stats(d.get("stats", {}), version, r.fight)
	return r


## D121 save v3: JSON brings the counts back as floats; a v1/v2 save has no
## stats, so its finished fights are counted as untracked.
static func _load_stats(d: Variant, version: int, fight_now: int) -> Dictionary:
	var s := new_stats()
	if version < 3 or not d is Dictionary:
		s.untracked = maxi(0, fight_now - 1)
		return s
	for k in ["won", "lost", "untracked"]:
		s[k] = int(d.get(k, 0))
	for id in Dictionary(d.get("units", {})):
		s.units[str(id)] = _ints(d.units[id])
	var b: Dictionary = d.get("best", {})
	if not b.is_empty():
		s.best = { "text": str(b.get("text", "")), "score": float(b.get("score", 0)), "fight": int(b.get("fight", 0)) }
	return s
