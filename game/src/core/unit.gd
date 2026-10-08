class_name BWUnit
extends RefCounted
## A combatant's persistent sheet plus its in-battle state. No nodes: the
## presentation layer reads this, never the other way round.

const STATS := ["con", "str", "dex", "wil", "def", "res", "spd"]
const STAT_CAP := 1000
const BASE_MOVE := 4                 # D17; D359: the fallback, a class's own `move` (weapons.csv) wins
const EXPERTISE_RANKS := ["E", "D", "C", "B", "A"]
const POINTS_PER_RANK := 10          # affinity (brief) and expertise (D21)
const MAX_AFFINITY_RANK := 10
## D417 (author: "Reduce max elements attuned to 3"): a unit holds affinity
## (points > 0) in at most this many elements. Gains in a further element are
## dropped (BWUnit.add_affinity); offers never show a 4th (BWRun).
const MAX_ELEMENTS := 3

var id := ""
var name := ""
var team := "player"                 # "player" | "enemy"
var friendliness := "neutral"
var element := ""                    # starting affinity, also hair colour
var weapon_class := ""
var weapon_model := ""
var stats := {}                      # base stats, before equipment
var level := 1                       # D179/D194: +1 per fight, won or lost (BWRun.after_fight); there is no XP
var affinity := {}                   # element -> points (rank = points / 10)
var expertise := {}                  # weapon class -> points (rank index = points / 10)
var equipment := {}                  # slot -> item Dictionary (later phases)
var cosmetics := {}                  # hair_style, top, bottom, shade, voice_pitch, ...

# --- picks (D89/D90): element perks and weapon-skill picks, BWPicks rules ---
var perks: Array = []                # perk ids (data/perks.csv), in the order taken
## D277: keystone ids (data/keystones.csv, BWKeystones), in the order taken; at most 2.
var keystones: Array = []
## D279: keystones this unit may hold at most (-1 = BWKeystones.MAX_PER_UNIT).
## Enemies get theirs by stage (BWKeystones.arm_enemies), not by rank. Never saved.
var keystone_cap := -1
var known_skills: Array = []         # skills learned beyond the weapons' starting kits
var skill_ranks := {}                # skill key -> rank (2 = improved; absent = 1)
var skill_loadout := {}              # weapon class -> [keys] equipped (absent = the starter kit)
var skill_picks := {}                # weapon class -> expertise picks already made
## D128: free picks from Specialize, beyond what the ranks grant (the rank
## itself doesn't move): element -> extra perk picks, class -> extra skill picks.
var bonus_perks := {}
var bonus_skills := {}
## D174: salts which two options a pick offers (BWPicks.offer). BWRun sets it
## from the run seed and the unit id (BWRun.seed_unit), so it is never saved:
## a load derives the same value and the same two cards.
var pick_seed := 0

# --- downtime outcomes that last (D129, D130; save v4) ---
## (D177 removed the rogue: Wander's jackpot no longer takes control away; a
## save's old "rogue" flag is ignored on load.)
## D130 Wander: statuses it shrugs off in its NEXT battle; begin_battle()
## moves them into `immune_statuses` (that battle only) and clears it.
var next_immune: Array = []
var immune_statuses: Array = []
## D130 Wander's brace: elements it is braced against for its NEXT battle;
## begin_battle() moves them into `braced` (that battle only) and clears it.
## Braced: BRACE_TAKEN of the element's damage, none of its statuses.
var next_brace: Array = []
var braced: Array = []
const BRACE_TAKEN := 0.25            # -75%
## Wander: stat -> bonus for the unit's next battle; moved into battle_mods
## (and cleared) by begin_battle().
var fight_buff := {}
## D132: the element Specialize trains. "" = the native element. Settable in
## the gear panel to any element with affinity > 0.
var focus_element := ""

# --- battle state, reset by begin_battle() ---
var hp := 0
var pos := Vector2i(-1, -1)
var moved := false
var acted := false
var cooldowns := {}                  # skill id -> turns left
var battle_mods := {}                # stat -> bonus for this battle (reactive abilities)
var size := 1                        # hex radius + 1; the boss is 2 (7 hexes)
## D138: > 0 = max HP is this, not the D137 formula (the Giant's 500).
var fixed_hp := 0
## D208: a special-encounter unit (BWEncounters): "grunt" (the Horde),
## "colossus", "blank" (immune to elements, x2 from melee), "being" (immune
## to physical damage); "" = an ordinary unit. Never saved (enemies only).
var encounter := ""
## D347: a GROUP TURN key ("" = a normal turn). Every living unit sharing a
## key takes its turn together, in one slot of the speed order where the
## fastest of them stands (BWTurnQueue.build, BWBattle group turns). Never saved.
var group_turn := ""
var attuned := ""                    # last element used this battle (ELEMENTS §7.1)
var follow_up: Array = []            # while non-empty: the only actions allowed ("basic" or skill keys)
var follow_up_element := ""          # element of the skill that granted the follow-up
var follow_up_used := false          # one follow-up per turn (V8 grant_follow_up)
var riposte := {}                    # { element } while the guard is up
var loaded := ""                     # pistols: element seated by Reload
var quick_shot_ready := false        # pistols: Quick Shot available (once per reload; twice unmoved, D87)
## D87 short statuses: name -> { turns, armed, label, value, source }. A
## status lasts until the end of the holder's next turn (BWBattle arms it at
## that turn's start and drops it at that turn's end). staggered / blinded
## (-hit on its attacks), drenched (-1 move, thunder hits on it +20%),
## scorched (attacks on it +10%), shrouded (4% dark drain at its turn start),
## swift (+1 move, Ley Line).
var statuses := {}
## D87: heading (0-5, BWHex.CUBE_DIRS) the unit last faced: its last step,
## or the last thing it struck. -1 = unknown. Daggerleap reads its back.
var facing := -1
## D365: a wind SKILL's shaping, per skill key: { opt, rel } (BWWindShape),
## the last one chosen; remembered, not in the save. (D407: the D269 per-unit
## wind mode is gone; a wind basic just pushes 1.)
var wind_shapes := {}
## D97 engine hooks for weapon skills (BWSkillDef.zone / overwatch):
## zone = { hexes: [Vector2i], skill } — enemy movement entering one of these
## hexes stops there; overwatch = { radius, skill } — the first enemy attack
## on an ally within `radius` draws this unit's basic attack. Both expire at
## the holder's next turn.
var zone := {}
var overwatch := {}
## D98: skills learned mid-fight while the loadout was full. Usable for the
## rest of this battle only (over the cap); cleared when a battle starts or ends.
var overcap: Array = []

# --- effects (BWEffects; design/EQUIPMENT.md) ---
var abilities := {}                  # type -> { id, rank }; BWRun.prepare_for_battle fills it
var effects: Array = []              # cached BWEffects records; refresh_effects()
var fx := {}                         # per-battle effect state (guard, imbued, trigger caps ...)
## FX hook: the battle's situational bonus (stand_on_bonus, aura_mod) as
## Callable(unit, key) -> int. Unset outside a battle.
var fx_hook: Callable


static func from_roster(row: Dictionary) -> BWUnit:
	var u := BWUnit.new()
	u.id = str(row.get("id", ""))
	u.name = str(row.get("name", u.id))
	u.friendliness = str(row.get("friendliness", "neutral"))
	u.element = str(row.get("element", ""))
	u.weapon_class = str(row.get("weapon_class", ""))
	u.weapon_model = str(row.get("weapon_model", u.weapon_class))
	for s in STATS:
		u.stats[s] = int(row.get(s, 1))
	# Starting affinity is rank 1 in your own element (D22).
	if u.element != "":
		u.affinity[u.element] = POINTS_PER_RANK
	for k in ["gender", "seat", "hair_style", "top", "bottom", "clothing_shade", "voice_pitch"]:   # D153: no tagline
		if row.has(k):
			u.cosmetics[k] = row[k]
	u.hp = u.max_hp()
	return u


func stat(key: String) -> int:
	var v: int = stats.get(key, 0) + battle_mods.get(key, 0)
	for slot in equipment:
		if slot != SECOND:                         # D180: the carried weapon adds nothing until drawn
			v += int(equipment[slot].get("stats", {}).get(key, 0))
	v += BWEffects.share(self, key)                # FX hook: stat_share
	if fx_hook.is_valid():
		v += int(fx_hook.call(self, key))          # FX hook: stand_on_bonus, aura_mod
	else:
		v += int(BWEffects.self_aura(self, key))   # outside a battle: own passives only
	return clampi(v, 0, STAT_CAP)


func max_hp() -> int:
	if fixed_hp > 0:
		return fixed_hp
	var hp_max := BWFormulas.hp_value(stat("con"), level)    # D137
	if str(fx.get("lev", "")) == "leviathos":
		hp_max *= 2                                      # D451 Leviathos: double max HP for the battle
	return hp_max


func speed() -> int:
	return stat("spd") + int(weapon().get("speed_mod", 0))


func move_range() -> int:
	if statuses.has("becalmed"):                   # D270: Becalmed, move 0 (it can still act)
		return 0
	var m := BWWeaponMove.base_move(BWWeaponMove.move_class(self))   # D359: the weapon drawn at turn start
	if fx_hook.is_valid():
		m += int(fx_hook.call(self, "move"))       # FX hook: aura_mod move (Leap Ready, Flutter)
	else:
		m += int(BWEffects.self_aura(self, "move"))
		m += BWEnchant.move_mod(self)              # D363: a cursed row's move cost (Leaden) on the sheet too, as in battle
	if statuses.has("swift"):                      # D87: Ley Line
		m += 1
	if statuses.has("drenched"):                   # D87: Saturate water to 3
		m -= 1
	if statuses.has("pinned"):                     # D94
		m -= BWSkills.PINNED_MOVE
	return maxi(m, 1)


## D93: the named terms behind move_range() beyond the base and the weapon
## ([label, value]): turn-start perks, after-action perks, statuses. What the
## Move hover (BWFormulas.move) lists.
func move_notes() -> Array:
	var out: Array = []
	for n in fx.get("move_notes", []):
		out.append(n)
	var cm := BWEnchant.move_mod(self)              # D363: name a cursed row's move cost (Leaden -2)
	if cm != 0:
		out.append(["%s (cursed)" % str(BWEnchant._drawback(self, "move").get("name", "Leaden")), cm])
	if int(fx.get("extra_move", 0)) != 0:
		out.append(["after-action move", int(fx.extra_move)])
	if statuses.has("swift"):
		out.append(["Swift", 1])
	if statuses.has("drenched"):
		out.append(["Drenched", -1])
	if statuses.has("pinned"):
		out.append(["Pinned", -BWSkills.PINNED_MOVE])
	return out


## The hexes this unit covers: its centre, plus the ring for the boss (size 2).
func footprint(at: Vector2i = Vector2i(-9999, -9999)) -> Array[Vector2i]:
	return BWHex.area(pos if at == Vector2i(-9999, -9999) else at, maxi(size, 1) - 1)


## Re-read enchantments and equipped abilities into `effects`.
func refresh_effects() -> void:
	effects = BWEffects.collect(self)


func weapon() -> Dictionary:
	return BWData.row("weapons", weapon_class)


## D417: the elements this unit is attuned to (affinity points > 0), native first.
func attuned_elements() -> Array:
	return focus_options()


## D417: can `el` gain affinity? Yes if the unit already has it, or has room
## for another element (MAX_ELEMENTS).
func can_attune(el: String) -> bool:
	if el == "":
		return false
	return int(affinity.get(el, 0)) > 0 or attuned_elements().size() < MAX_ELEMENTS


## D417: the one way affinity grows. False (nothing added) when `el` would be
## an element past MAX_ELEMENTS.
func add_affinity(el: String, points: int) -> bool:
	if points <= 0 or not can_attune(el):
		return false
	affinity[el] = int(affinity.get(el, 0)) + points
	return true


## D417 save migration: a unit attuned to more than MAX_ELEMENTS keeps the
## MAX_ELEMENTS with the most affinity points (ties: native, then the focus,
## then element order); the native element is always kept (it's the hair), in
## place of the lowest of the rest. Each dropped element: its points are
## cleared and HALF of them (rounded down) go to the kept focus element (else
## native); its perks and keystones are removed, and anything the new ranks
## owe is asked through the normal pick flow. Returns { dropped: [el],
## moved: points, to: el } (dropped empty = nothing to do).
func enforce_element_cap() -> Dictionary:
	var have: Array = attuned_elements()
	if have.size() <= MAX_ELEMENTS:
		return { "dropped": [], "moved": 0, "to": "" }
	var order := func(a, b2) -> bool:
		var pa := int(affinity.get(a, 0))
		var pb := int(affinity.get(b2, 0))
		if pa != pb:
			return pa > pb
		for pref in [element, focus_element]:
			if a == pref or b2 == pref:
				return a == pref
		return BWFormulas.ELEMENTS.find(a) < BWFormulas.ELEMENTS.find(b2)
	have.sort_custom(order)
	var keep: Array = have.slice(0, MAX_ELEMENTS)
	if element != "" and not element in keep:
		keep[MAX_ELEMENTS - 1] = element
	var dropped: Array = have.filter(func(e): return not e in keep)
	var to := focus_element if focus_element in keep else element
	if to == "":
		to = str(keep[0])
	var moved := 0
	for el in dropped:
		moved += int(affinity.get(el, 0)) / 2
		affinity.erase(el)
		perks = perks.filter(func(id): return str(BWData.row("perks", str(id)).get("element", "")) != el)
		keystones = keystones.filter(func(id): return str(BWData.row("keystones", str(id)).get("element", "")) != el)
		bonus_perks.erase(el)
	if moved > 0:
		affinity[to] = int(affinity.get(to, 0)) + moved
	if not focus_element in keep:
		focus_element = ""
	return { "dropped": dropped, "moved": moved, "to": to }


func affinity_rank(el: String) -> int:
	return mini(int(affinity.get(el, 0)) / POINTS_PER_RANK, MAX_AFFINITY_RANK)


func expertise_rank(wc: String) -> int:
	return mini(int(expertise.get(wc, 0)) / POINTS_PER_RANK, EXPERTISE_RANKS.size() - 1)


func expertise_letter(wc: String) -> String:
	return EXPERTISE_RANKS[expertise_rank(wc)]


func alive() -> bool:
	return hp > 0


func begin_battle() -> void:
	fx_hook = Callable()
	fx = {}
	refresh_effects()
	hp = max_hp()
	moved = false
	acted = false
	cooldowns.clear()
	battle_mods.clear()
	for k in fight_buff:                          # D130: Wander's buff is spent on this battle
		battle_mods[k] = int(battle_mods.get(k, 0)) + int(fight_buff[k])
	fight_buff = {}
	braced = next_brace.duplicate()               # D130: the brace lasts this battle only
	next_brace = []
	immune_statuses = next_immune.duplicate()     # D130: so does the status immunity
	next_immune = []
	attuned = element
	follow_up = []
	follow_up_element = ""
	follow_up_used = false
	riposte = {}
	loaded = ""
	quick_shot_ready = false
	statuses = {}
	facing = -1
	zone = {}
	overwatch = {}
	overcap = []


# ---------------------------------------------------------------- skills (D89)

const LOADOUT_MAX := 3               # skills equipped per weapon class
const LOADOUT_CAPS := { "staff": 4 }  # D98: the staff equips 4


## Has this unit improved skill `key` (rank 2)?
func skill_upgraded(key: String) -> bool:
	return int(skill_ranks.get(key, 1)) >= 2


## Every skill this unit knows for a weapon class: the class's starting kit,
## plus whatever it learned (pool order).
func known(wc: String) -> Array:
	var out: Array = BWSkillRegistry.starter(wc)
	for k in BWSkillRegistry.pool(wc):
		if k in known_skills and not k in out:
			out.append(k)
	return out


## The skills equipped for a weapon class: the saved loadout, else the
## starter kit. Follow-up halves are not listed (BWSkillRegistry.expand).
func loadout(wc: String) -> Array:
	var out: Array
	if skill_loadout.has(wc):
		var kn := known(wc)
		out = (skill_loadout[wc] as Array).filter(func(k): return k in kn)
	else:
		out = BWSkillRegistry.starter(wc)
	return out.slice(0, loadout_cap(wc))   # D98: camp loadouts never exceed the cap


## The skills a unit fights with this battle: the loadout plus `overcap`
## (learned mid-fight while full, D98).
func fight_loadout(wc: String) -> Array:
	var out := loadout(wc)
	for k in overcap:
		if k in known(wc) and not k in out:
			out.append(k)
	return out


## How many skills a class's loadout holds in camp / pre-battle: 3, the
## staff 4 (D98). A skill learned mid-fight past the cap is usable for that
## battle only (`overcap`).
static func loadout_cap(wc: String) -> int:
	return int(LOADOUT_CAPS.get(wc, LOADOUT_MAX))


## Equip or unequip one known skill for a class. Returns false when it is
## unknown, or the loadout is full (or would be empty).
func set_equipped(wc: String, key: String, on: bool) -> bool:
	if not key in known(wc):
		return false
	var cur: Array = loadout(wc).duplicate()
	if on:
		if key in cur:
			return true
		if cur.size() >= loadout_cap(wc):
			return false
		cur.append(key)
	else:
		if not key in cur:
			return true
		if cur.size() <= 1:
			return false
		cur.erase(key)
	skill_loadout[wc] = cur
	return true


func has_status(key: String) -> bool:
	return statuses.has(key)


## D130: the one brace check. A braced unit takes BRACE_TAKEN of `el`'s
## damage (blows of that element, its ground: standing, crossing, eruptions;
## detonations and chain arcs are thunder) and none of its statuses.
func braced_against(el: String) -> bool:
	return el != "" and el in braced


## D132: the element Specialize trains: the chosen focus while the unit still
## has affinity in it, else its native element.
func focus() -> String:
	if focus_element != "" and int(affinity.get(focus_element, 0)) > 0:
		return focus_element
	return element


## Elements the focus can be set to: those with affinity > 0 (native first).
func focus_options() -> Array:
	var out: Array = [element] if element != "" else []
	for el in BWFormulas.ELEMENTS:
		if el != element and int(affinity.get(el, 0)) > 0:
			out.append(el)
	return out


## D130: a status this unit can't take this battle (Wander, the fight after).
func immune_to_status(key: String) -> bool:
	return key in immune_statuses


## D131: the weapon class follows the main hand (an equipped weapon of
## another class switches it; skills and expertise are kept per class).
func sync_weapon() -> void:
	var mh: Dictionary = equipment.get("main_hand", {})
	if not mh.is_empty() and str(mh.get("weight", "")) != "":
		weapon_class = str(mh.weight)
		weapon_model = str(mh.get("base", weapon_model))


# ---------------------------------------------------------------- D180-D182: two weapons

## D180: the equipment key of the carried (sheathed) weapon. Its item keeps
## slot "main_hand" (what kind of item it is); only the active weapon in
## "main_hand" counts for stats, enchantments, range, skills.
const SECOND := "second"


## The carried weapon ({} = none).
func second_weapon() -> Dictionary:
	return equipment.get(SECOND, {})


## D181: draw the carried weapon and sheathe the active one (the two items
## trade places). The class, model, effects and skills follow the main hand;
## cooldowns are per skill key, so they carry over. False with nothing carried.
func swap_weapons() -> bool:
	var other: Dictionary = equipment.get(SECOND, {})
	if other.is_empty():
		return false
	var cur: Dictionary = equipment.get("main_hand", {})
	equipment["main_hand"] = other
	if cur.is_empty():
		equipment.erase(SECOND)
	else:
		equipment[SECOND] = cur
	sync_weapon()
	refresh_effects()
	return true


## D182: the element the active weapon is imbued with ("" = none).
func imbue() -> String:
	return str(equipment.get("main_hand", {}).get("imbue", ""))


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "team": team, "friendliness": friendliness,
		"element": element, "weapon_class": weapon_class, "weapon_model": weapon_model,
		"stats": stats.duplicate(), "level": level,
		"affinity": affinity.duplicate(), "expertise": expertise.duplicate(),
		"cosmetics": cosmetics.duplicate(),
		"perks": perks.duplicate(), "keystones": keystones.duplicate(), "known_skills": known_skills.duplicate(),
		"skill_ranks": skill_ranks.duplicate(), "skill_loadout": skill_loadout.duplicate(true),
		"skill_picks": skill_picks.duplicate(),
		"bonus_perks": bonus_perks.duplicate(), "bonus_skills": bonus_skills.duplicate(),
		"next_immune": next_immune.duplicate(),
		"next_brace": next_brace.duplicate(), "fight_buff": fight_buff.duplicate(),
		"focus_element": focus_element,
	}
