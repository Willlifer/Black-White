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
const DEPLOY := 3
## D145 (supersedes D118's fixed order): fight 4 is always the Obelisks (D140,
## an objective fight: break a stone), the Giant stays on the arena, and the
## other nine slots (fights 1-3, 5-10) take MAP_POOL in a seeded shuffle from
## the run's seed: nine maps for nine slots, so none repeat. The order is kept
## in `map_order` and saved, so a loaded run plays the same maps.
const OBJECTIVE_FIGHT := 4
const OBJECTIVE_MAP := "obelisks"
const MAP_POOL := ["arena", "paintball", "bridge", "lake", "chapel", "ravine", "catacombs", "tinderbox", "forge"]
## Every battle map (the pool plus the objective map).
const MAPS := ["arena", "paintball", "bridge", "lake", "obelisks", "chapel", "ravine", "catacombs", "tinderbox", "forge"]
## D145: the shuffled pool for the nine plain slots, in slot order (fights 1-3, 5-10).
var map_order: Array = []
const TIERS := ["E", "D", "C", "B", "A"]
const TIER_RANGE := { "E": [0, 3], "D": [1, 6], "C": [2, 9], "B": [3, 12], "A": [4, 15] }
const ARMOR_SLOTS := ["head", "chest", "legs"]
const SLOTS := ["head", "chest", "legs", "main_hand"]
const LEARN_BATTLES := 2          # brief: learn an item's ability after wearing it 2 battles
const SHOP_STOCK := 5

## D127 downtime (replaces D37/D85's eight actions): each unit takes one of
## three choices a day. The screen shows only the names (author: no effect
## text); the rules are BWRun.downtime().
const DOWNTIME_CHOICES := ["specialize", "branch_out", "wander"]
const CHOICE_NAMES := { "specialize": "Specialize", "branch_out": "Branch out", "wander": "Wander" }
const DAY_XP := 50                # every choice
const SPECIALIZE_POINTS := 5      # half a rank (POINTS_PER_RANK 10) in the element and the weapon class
const SPECIALIZE_ROLL := 0.5      # each: a free pick, else a find
const BRANCH_POINTS := 10         # a full rank
## D129 Wander: nine effects, each rolled on its own at WANDER_ROLL.
const WANDER_ROLL := 0.20
const WANDER_EFFECTS := ["xp", "element", "weapon", "find_weapon", "find_armour", "recruit",
	"status_immunity", "element_brace", "stat_buff"]
const WANDER_XP := 50             # the "xp" effect
const WANDER_CONSOLATION_XP := 100   # all nine missed (and no jackpot)
## All nine missed, then this roll: +5000 XP and the unit goes rogue for good.
## 0.8^9 x 0.05 = about 0.67% a wander (author 2026-10-05).
const WANDER_JACKPOT_EXTRA_ROLL := 0.05
const WANDER_JACKPOT_XP := 5000
const WANDER_STAT_BUFF := 10
const IMMUNE_STATUSES := ["staggered", "blinded", "pinned", "drenched", "scorched", "shrouded"]
const SHRUG := { "staggered": "staggers", "blinded": "blinding", "pinned": "pins", "drenched": "drenching",
	"scorched": "scorching", "shrouded": "shrouding" }
## D129: set by a wanderer's recruit; later wanderers that day skip the roll.
var recruited_today := false

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
const SAVE_VERSION := 5
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
	for id in chosen_ids:
		var u := BWUnit.from_roster(r.roster_row(id))
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


func map_for(n: int) -> String:
	if n >= BOSS_FIGHT:
		return "arena"
	if n == OBJECTIVE_FIGHT:
		return OBJECTIVE_MAP
	if map_order.is_empty():
		map_order = shuffled_maps(seed_value)
	var slot := (n - 1) if n < OBJECTIVE_FIGHT else (n - 2)     # fights 1-3 -> 0-2, 5-10 -> 3-8
	return str(map_order[slot % map_order.size()])


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
	item.enchant = _roll_enchant(base_id) if enchant_id == "?" else enchant_id
	return item


func random_item(tier: String) -> Dictionary:
	var all := BWData.table("equipment")
	return make_item(str(all[rng.randi() % all.size()].id), tier)


func _roll_enchant(base_id: String) -> String:
	var pool: Array = []
	for e in BWData.table("enchantments"):
		if base_id in BWData.list(e.applies_to):
			pool.append(str(e.id))
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else ""


static func item_name(item: Dictionary) -> String:
	var base := BWData.row("equipment", item.get("base", ""))
	var plain := str(base.get("name", item.get("base", "?")))
	var ench := BWData.row("enchantments", item.get("enchant", ""))
	var named := plain
	if not ench.is_empty():
		named = str(ench.name_pattern).replace("{item}", plain)
	return "%s [%s]" % [named, item.get("tier", "E")]


static func item_element(item: Dictionary) -> String:
	return str(BWData.row("enchantments", item.get("enchant", "")).get("element", ""))


## Brief: equipping a weapon needs that weapon class's expertise at the
## item's rank or better. Armour has no requirement.
func can_equip(u: BWUnit, item: Dictionary) -> bool:
	if item.slot != "main_hand":
		return true
	return u.expertise_rank(item.weight) >= TIERS.find(item.tier)


func equip(u: BWUnit, item: Dictionary) -> bool:
	if not can_equip(u, item) or not item in inventory:
		return false
	inventory.erase(item)
	var old: Dictionary = u.equipment.get(item.slot, {})
	if not old.is_empty():
		inventory.append(old)
	u.equipment[item.slot] = item
	if item.slot == "main_hand":
		u.weapon_class = item.weight
		u.weapon_model = item.base
	return true


func unequip(u: BWUnit, slot: String) -> void:
	if slot == "main_hand":
		return              # never empty-handed
	var old: Dictionary = u.equipment.get(slot, {})
	if not old.is_empty():
		u.equipment.erase(slot)
		inventory.append(old)


func restock_shop() -> void:
	shop.clear()
	for i in SHOP_STOCK:
		shop.append(random_item(tier_for(fight)))


## 1-for-1 trade: give an inventory item, take a shop item.
func trade(give: Dictionary, take: Dictionary) -> bool:
	if not give in inventory or not take in shop:
		return false
	inventory.erase(give)
	shop.erase(take)
	inventory.append(take)
	shop.append(give)
	return true


## Read-only: would reimbue(from, to) succeed? (Same rule; for the UI.)
static func can_reimbue(from: Dictionary, to: Dictionary) -> bool:
	var ench := BWData.row("enchantments", from.get("enchant", ""))
	if ench.is_empty() or from == to or from.is_empty() or to.is_empty():
		return false
	return (from.slot != "main_hand" and to.slot != "main_hand") or to.base in BWData.list(ench.applies_to)


## Disenchant `from` and apply its enchantment to `to` (D38: armour
## enchantments move between armour; weapon ones only to items they list).
func reimbue(from: Dictionary, to: Dictionary) -> bool:
	var ench := BWData.row("enchantments", from.get("enchant", ""))
	if ench.is_empty() or from == to:
		return false
	var ok: bool = (from.slot != "main_hand" and to.slot != "main_hand") or to.base in BWData.list(ench.applies_to)
	if not ok:
		return false
	to.enchant = from.enchant
	from.enchant = ""
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
const ENEMY_CURVE := [
	[0, 0.9, false, 0], [0, 1.5, false, 1],                       # 1-2: gentle start, no perks
	[2, 2.1, true, 2], [2, 2.2, true, 3], [2, 2.1, true, 3],      # 3-5: two fights behind (4: generic; the obelisk map tunes its own)
	[1, 1.6, true, 3], [1, 1.8, true, 3], [1, 1.7, true, 3],      # 6-8: one behind
	[0, 1.6, true, 3], [0, 1.75, true, 3],                        # 9-10: level with you
]
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
func enemies_for(n: int) -> Array:
	var erng := RandomNumberGenerator.new()
	erng.seed = seed_value * 7919 + n
	if n >= BOSS_FIGHT:
		var boss := make_boss()
		BWPicks.auto_resolve(boss)
		return [boss]
	var pool: Array = []
	for row in roster_rows:
		if unit(str(row.id)) == null:
			pool.append(row)
	var out: Array = []
	var stage := enemy_stage(n)
	var curve := enemy_curve(n)
	var tier := tier_for(stage)
	var ranks: Array = ENEMY_RANKS[tier]
	for i in DEPLOY:
		var row: Dictionary = pool.pop_at(erng.randi() % pool.size())
		var u := BWUnit.from_roster(row)
		u.id = "%s_f%d" % [u.id, n]
		var levels := (stage - 1) * 2 / 3
		BWProgression.add_xp(u, levels * BWProgression.XP_PER_LEVEL)
		scale_stats(u, float(curve.mult))
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
		rng.state = save
		if u.element != "":
			u.affinity[u.element] = maxi(int(u.affinity.get(u.element, 0)), int(ranks[0]) * BWUnit.POINTS_PER_RANK)
		u.expertise[u.weapon_class] = int(ranks[1]) * BWUnit.POINTS_PER_RANK
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
	if won:
		for e in defeated:
			var item := random_item(tier_for(fight))
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
	last_enemies = enemies.map(func(e): return e.to_dict())
	# Author 2026-10-04 (supersedes D39): a lost fight doesn't end the run. You
	# keep the XP and growth, get no spoils, and move on to the next fight.
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
##   Branch out also carries `options` ([{ element, weapon }], one or two)
##   and `pending` until branch_pick() applies the one the player took
##   (`auto` = the first, at once: the AI's and the sim's way).
func downtime(u: BWUnit, choice: String, auto: bool = true) -> Dictionary:
	var rep := { "unit": u.id, "name": u.name, "choice": choice, "ok": true, "headline": "",
		"lines": [], "items": [], "successes": [], "jackpot": false, "levels": 0 }
	var lv := u.level
	match choice:
		"specialize": _specialize(u, rep)
		"branch_out":
			_branch_out(u, rep)
			if auto and rep.get("pending", false):
				branch_pick(u, rep, 0)
		"wander": _wander(u, rep)
		_:
			rep.ok = false
			rep.headline = "I didn't know what to do with %s." % choice
	rep.levels = u.level - lv
	rep["text"] = rep.headline
	return rep


## Run a day: every [unit id, choice] in order. Returns the reports.
## `auto` false leaves Branch out's options for the player (branch_pick).
func progress_day(plan: Array, auto: bool = true) -> Array:
	var out: Array = []
	recruited_today = false
	for p in plan:
		var u := unit(str(p[0]))
		if u:
			out.append(downtime(u, str(p[1]), auto))
	day += 1
	return out


## Specialize: +half a rank in the unit's focus element (D132) and its weapon
## class; 50% a free skill pick in the class (else a weapon of that class),
## 50% a free perk pick in the element (else armour attuned to it); +50 XP.
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
	gained.append("%d experience" % DAY_XP)
	_xp(u, rep, DAY_XP)
	rep.headline = "I specialized and gained %s, feeling confident." % _and(gained)


## Branch out (D128): up to two options, each a pairing of a new element
## (one at rank 0) and a new weapon class (another one still at E), for the
## player to pick from on the result card. Nothing left at all: +50 XP and a
## line saying so.
func _branch_out(u: BWUnit, rep: Dictionary) -> void:
	rep["options"] = branch_options(u)
	if rep.options.is_empty():
		_xp(u, rep, DAY_XP)
		rep.headline = "I branched out, but there was nothing new left to try."
		return
	rep["pending"] = true
	rep.headline = "I branched out. Which way should I go?"


## The day's Branch out options: [{ element, weapon }], two distinct
## pairings where the unit has room for two, else one ("" = that half has
## nothing left). Rolled on the run's rng.
func branch_options(u: BWUnit) -> Array:
	var els: Array = BWFormulas.ELEMENTS.filter(func(e): return u.affinity_rank(e) == 0)
	var wcs: Array = weapon_classes().filter(func(c): return c != u.weapon_class and u.expertise_rank(c) == 0)
	_shuffle(els)
	_shuffle(wcs)
	var out: Array = []
	for k in mini(2, maxi(els.size(), wcs.size())):
		out.append({ "element": els[mini(k, els.size() - 1)] if not els.is_empty() else "",
			"weapon": wcs[mini(k, wcs.size() - 1)] if not wcs.is_empty() else "" })
	return out


## Apply the Branch out option the player took: a full rank in its element
## and its class (each owes its first pick through the normal flow), a weapon
## of that class and armour attuned to that element (this fight's tier), +50
## XP. False if `rep` has nothing pending or `i` is out of range.
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
		# The find must be wieldable with the expertise just gained: the
		# fight's tier, capped at the unit's new letter in that class.
		var cap := TIERS.find(u.expertise_letter(new_wc))
		var wt: String = TIERS[mini(TIERS.find(tier_for(fight)), maxi(cap, 0))]
		var w := _find_weapon(rep, new_wc, wt)
		if not w.is_empty():
			_line(rep, "New equipment: " + item_name(w), item_element(w), w)
	if new_el != "":
		var a := _find_armour(rep, new_el, tier_for(fight))
		if not a.is_empty():
			_line(rep, "New equipment: " + item_name(a), new_el, a)
	_xp(u, rep, DAY_XP)
	var can: Array = []
	if new_el != "":
		can.append(new_el)
	if new_wc != "":
		can.append("the " + class_name_of(new_wc))
	rep.headline = "I branched out and now can use %s." % " and ".join(can)
	rep["text"] = rep.headline
	rep.levels = int(rep.get("levels", 0)) + u.level - lv
	return true


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## Wander: +50 XP, then each of WANDER_EFFECTS rolled on its own at
## WANDER_ROLL (one that can't happen counts as a miss). All nine missed:
## +100 XP, unless WANDER_JACKPOT_EXTRA_ROLL lands: +5000 XP instead, and the
## unit goes rogue for good (D129).
func _wander(u: BWUnit, rep: Dictionary) -> void:
	_xp(u, rep, DAY_XP)
	for eff in WANDER_EFFECTS:
		if eff == "recruit" and recruited_today:
			continue                             # D129: one recruit a day, squad-wide; a skipped roll is a miss
		if rng.randf() < WANDER_ROLL and _wander_effect(u, str(eff), rep):
			rep.successes.append(eff)
	if not rep.successes.is_empty():
		rep.headline = "I wandered off for the day. Here's what happened:"
		return
	if rng.randf() < WANDER_JACKPOT_EXTRA_ROLL:
		var lv := u.level
		BWProgression.add_xp(u, WANDER_JACKPOT_XP)
		u.rogue = true
		rep.jackpot = true
		rep.lines = []
		rep.headline = "I wandered and ran into a being of unlimited benevolence"
		_line(rep, "+%d levels" % (u.level - lv))
		_line(rep, "+ no longer fear god")
		return
	_xp(u, rep, WANDER_CONSOLATION_XP, false)
	rep.headline = "I wandered. Nothing happened, but the walk did me good (+%d XP)" % WANDER_CONSOLATION_XP


## One wander effect. False when it can't happen (a missed roll).
func _wander_effect(u: BWUnit, eff: String, rep: Dictionary) -> bool:
	match eff:
		"xp":
			_xp(u, rep, WANDER_XP, false)
			_line(rep, "I learned something on the road.  (+%d more XP)" % WANDER_XP)
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
	if u.affinity_rank(el) >= BWPicks.ALL_RANK or BWPicks.allowance(u, el) >= BWPicks.perks_of(el).size():
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
	nu.level = int(pick.level)
	nu.stats = Dictionary(pick.stats).duplicate()
	nu.equipment["main_hand"] = make_item(nu.weapon_model, tier_for(fight))
	var fists: Array = BWData.table("equipment").filter(func(row): return str(row.weight) == "fists")
	if not fists.is_empty():
		inventory.append(make_item(str(fists[rng.randi() % fists.size()].id), "E"))
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
		if str(e.element) != el:
			continue
		for b in BWData.list(e.applies_to):
			if str(BWData.row("equipment", b).get("slot", "main_hand")) != "main_hand":
				pairs.append([str(b), str(e.id)])
	if pairs.is_empty():
		return {}
	var p: Array = pairs[rng.randi() % pairs.size()]
	var a := make_item(p[0], tier, p[1])
	inventory.append(a)
	rep.items.append(a)
	return a


func _xp(u: BWUnit, rep: Dictionary, amount: int, line: bool = true) -> void:
	var lv := u.level
	BWProgression.add_xp(u, amount)
	if line:
		_line(rep, "+%d XP%s" % [amount, "  (now level %d)" % u.level if u.level > lv else ""])


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
		"squad": sq, "inventory": inventory.duplicate(true), "trust": trust.duplicate(),
		"last_enemies": last_enemies.duplicate(true), "shop": shop.duplicate(true),
		"learned": learned.duplicate(true), "ability_ranks": ability_ranks.duplicate(true),
		"equipped_ability": equipped_ability.duplicate(true), "uid": _uid,
		"stats": stats.duplicate(true),
		"map_order": (map_order if not map_order.is_empty() else shuffled_maps(seed_value)).duplicate(),   # D145
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
	for ud in d.squad:
		var u := BWUnit.from_roster(r.roster_row(str(ud.id)))
		u.element = str(ud.get("element", u.element))
		u.name = ud.name
		u.weapon_class = ud.weapon_class
		u.weapon_model = ud.weapon_model
		u.stats = ud.stats.duplicate()
		u.level = int(ud.level)
		u.xp = int(ud.xp)
		u.affinity = ud.affinity.duplicate()
		u.expertise = ud.expertise.duplicate()
		u.equipment = ud.equipment.duplicate(true)
		# D90/D91 picks (save version 2)
		u.perks = Array(ud.get("perks", [])).duplicate()
		u.known_skills = Array(ud.get("known_skills", [])).duplicate()
		u.skill_ranks = _ints(ud.get("skill_ranks", {}))
		u.skill_picks = _ints(ud.get("skill_picks", {}))
		u.skill_loadout = Dictionary(ud.get("skill_loadout", {})).duplicate(true)
		# D132 save v4: the downtime outcomes that last (defaults when older)
		u.bonus_perks = _ints(ud.get("bonus_perks", {}))
		u.bonus_skills = _ints(ud.get("bonus_skills", {}))
		u.rogue = bool(ud.get("rogue", false))
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
	r.trust = d.trust.duplicate()
	r.last_enemies = d.last_enemies.duplicate(true)
	r.shop = d.shop.duplicate(true)
	r.learned = d.learned.duplicate(true)
	r.ability_ranks = d.ability_ranks.duplicate(true)
	r.equipped_ability = d.equipped_ability.duplicate(true)
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
