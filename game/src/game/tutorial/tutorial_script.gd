class_name BWTutorialScript
extends RefCounted
## D223-D226: the tutorial's fight as data. One fixed squad, three fixed
## enemies, a small handcrafted map (maps/tutorial/yard.json, outside the run's
## map pool) and a fixed battle seed, so every roll comes out the same.
##
## STEPS is the script: one prompt each (max two short sentences), the unit
## whose turn it is, what to highlight and what the step waits for. The live
## tutorial (BWTutorial) shows them; the probe (BWTutorialProbe) plays them
## with synthetic input; `dry_run()` plays the same actions on the rules alone
## (tests/test_tutorial.gd), with the same turn-passing rule as the screen.
##
## Step keys:
##   lesson  1..10 (0 = the opening card)
##   text    the prompt; glossary terms link themselves (BWGlossary.markup)
##   actor   whose turn it must be ("" = no change); `fresh`: a new turn
##   wait    next | move | undo | forecast | aim | act | hover | over | results | pick | card
##   act     the action the step expects: {kind: move|undo|attack|skill|swap, ...}
##   hl      what to point at: {hex}, {hexes}, {unit}, {ui: forecast|confirm|order|menu|swap|odds|skill|hit_row}
##   stage   a staging hook BWTutorial runs first (rear, fire_at_f, worn, ...)

const MAP := "res://maps/tutorial/yard.json"
const SEED := 3
const RUN_SEED := 4242
## D419: the battle rng at the "worn" stage (lesson 9), so the Surge hits all three.
const WORN_SEED := 1

## The yard's landmarks (odd-r offset, as the map JSON's q/r).
const A_START := Vector2i(2, 6)
const FRONT := Vector2i(3, 3)          # Della's spot: in front of Burt
const F_HEX := Vector2i(2, 2)          # the fire tile (lesson 4)
const C0 := Vector2i(4, 2)             # the bare hex between the three enemies (fuse, detonation, Surge)
const SEEDED := [Vector2i(4, 1), Vector2i(6, 4), Vector2i(1, 4)]   # water 2, light 1, dark 2

## D468: the wind lesson (a staff Saturate, Wind) is gone: one staff can't hold
## five elements under the 3-element cap (D417); wind is named in lesson 6.
## D579 (author, 2026-10-11: "a revamp on the tutorial ... with all the new
## fixings, focus on the combat loop"): every step can carry a `touch` text for
## the mobile layout (the pad: commands, the cursor, A / B / X; D574-D578), and
## a new lesson 5, Reactions at 3: Surge stacks the fire to 3 (Saturate's
## cooldown is per element, so a second fire Saturate waits), then fresh fire on it
## Overheats (the ring burns and takes fire, which puts Burt on fire for
## Thread the Needle), with water's Runneth Over and light's Glinting named.
const LESSONS := ["Practice fight", "Moving", "Attacking", "Turn order", "Painting", "Reactions at 3", "Operators",
	"Skills and weapons", "Statuses", "Facing", "Winning", "Between fights"]
## The lesson the fight is won in (BWTutorial's skip rule).
const WIN_LESSON := 10

## Identity comes from data/roster.csv; the kits are fixed here (the roster
## roll never touches the tutorial).
const KITS := {
	"della": { "weapon_class": "sword", "weapon_model": "flamberge", "element": "fire", "con": 4, "str": 5, "dex": 4, "wil": 2, "def": 4, "res": 3, "spd": 4, "top": "tank_top", "bottom": "tight_pants", "clothing_shade": "dark" },
	"jericho": { "weapon_class": "staff", "weapon_model": "moon_staff", "element": "thunder", "con": 3, "str": 1, "dex": 3, "wil": 6, "def": 2, "res": 6, "spd": 5, "top": "sweater_scarf", "bottom": "sweatpants", "clothing_shade": "light" },
	"gail": { "weapon_class": "bow", "weapon_model": "recurve_bow", "element": "wind", "con": 3, "str": 3, "dex": 5, "wil": 3, "def": 3, "res": 3, "spd": 5, "top": "tshirt", "bottom": "shorts", "clothing_shade": "mid" },
	"burt": { "weapon_class": "axe", "weapon_model": "double_axe", "element": "fire", "con": 5, "str": 6, "dex": 3, "wil": 1, "def": 4, "res": 3, "spd": 3, "top": "tank_top", "bottom": "shorts", "clothing_shade": "dark" },
	"rui": { "weapon_class": "lance", "weapon_model": "halberd", "element": "dark", "con": 5, "str": 5, "dex": 2, "wil": 3, "def": 5, "res": 4, "spd": 2, "top": "sweater", "bottom": "tight_pants", "clothing_shade": "mid" },
	"bob": { "weapon_class": "lance", "weapon_model": "lance", "element": "water", "con": 4, "str": 3, "dex": 3, "wil": 5, "def": 3, "res": 4, "spd": 3, "top": "crop_hoodie", "bottom": "sweatpants", "clothing_shade": "light" },
}
const SQUAD := ["della", "jericho", "gail"]
const FOES := ["burt", "rui", "bob"]


## The prompt for the layout in use (D579): `touch` on mobile, else `text`.
static func say(s: Dictionary, touch: bool) -> String:
	return str(s.get("touch", s.text)) if touch else str(s.text)


static func steps() -> Array:
	return [
		# ---- 0. the opening card
		{ "id": "intro", "lesson": 0, "wait": "next",
			"text": "A practice fight with fixed rolls; the enemies hold still. The loop: paint the ground, build it up, then cash it in with a reaction." },
		{ "id": "controls", "lesson": 0, "wait": "next",
			"text": "Click to move and attack, Enter confirms, Esc backs out. Hover anything to read it.",
			"touch": "The stick moves the cursor, A confirms, B backs out. X explains whatever the cursor is on." },
		# ---- 1. moving
		{ "id": "rim", "lesson": 1, "actor": "della", "fresh": true, "wait": "next", "hl": { "unit": "della" },
			"text": "It's Della's turn. The rimmed hexes show how far she can move.",
			"touch": "It's Della's turn, so her commands open: Move, Act, Wait. The rim shows how far she can go." },
		{ "id": "move", "lesson": 1, "actor": "della", "wait": "move", "act": { "kind": "move", "hex": FRONT }, "hl": { "hex": FRONT },
			"text": "Click the marked hex to move there.",
			"touch": "Choose Move, put the cursor on the marked hex and press A." },
		{ "id": "undo", "lesson": 1, "actor": "della", "wait": "undo", "act": { "kind": "undo" }, "hl": { "unit": "della" },
			"text": "Changed your mind? Press Esc to undo a move, as long as you haven't acted yet.",
			"touch": "Changed your mind? Choose Undo move, as long as you haven't acted yet." },
		{ "id": "move2", "lesson": 1, "actor": "della", "wait": "move", "act": { "kind": "move", "hex": FRONT }, "hl": { "hex": FRONT },
			"text": "Move back in front of Burt.",
			"touch": "Move back in front of Burt: Move, then the marked hex." },
		# ---- 2. attacking
		{ "id": "pick_foe", "lesson": 2, "stage": "front", "actor": "della", "wait": "forecast", "act": { "kind": "attack", "target": "burt" }, "hl": { "unit": "burt" },
			"text": "Enemies in reach pulse. Click Burt to open the forecast.",
			"touch": "Enemies in reach pulse. Choose Act, then Attack; put the cursor on Burt and press A." },
		{ "id": "forecast", "lesson": 2, "actor": "della", "wait": "next", "hl": { "ui": "forecast" },
			"text": "Hit chance first, then glance (less damage) and crit (more). Hover any number to see its formula.",
			"touch": "The forecast in one line: damage, hit chance and crit, then his HP after the blow." },
		{ "id": "confirm", "lesson": 2, "actor": "della", "wait": "act", "act": { "kind": "attack", "target": "burt" }, "hl": { "ui": "confirm" },
			"text": "Press Enter to attack. The strip at the bottom shows the odds, then lights what the dice rolled.",
			"touch": "Press A again to attack. B would back out instead." },
		# ---- 3. turn order
		{ "id": "order", "lesson": 3, "wait": "next", "hl": { "ui": "order" },
			"text": "This bar is the turn order: faster units act first. The big portrait is the one acting now." },
		# ---- 4. painting
		{ "id": "saturate", "lesson": 4, "actor": "jericho", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "saturate", "element": "fire", "hex": F_HEX }, "hl": { "ui": "skill" },
			"text": "Jericho's staff paints the ground. Open Saturate in his menu and pick Fire.",
			"touch": "Jericho's staff paints the ground. Choose Act, then Saturate, Fire." },
		{ "id": "paint", "lesson": 4, "actor": "jericho", "wait": "act", "act": { "kind": "skill", "key": "saturate", "element": "fire", "hex": F_HEX }, "hl": { "hex": F_HEX },
			"text": "Click the marked hex. Saturate pours two steps: the ground there is painted fire 2.",
			"touch": "Cursor on the marked hex, then A. Saturate pours two steps: the ground there is painted fire 2." },
		{ "id": "tile_hover", "lesson": 4, "wait": "hover", "hex": F_HEX, "hl": { "hex": F_HEX },
			"text": "Hover the fire to read the tile. Whoever starts a turn on fire takes damage.",
			"touch": "Press B for a free cursor, put it on the fire and press X to read it. Starting a turn on fire burns." },
		{ "id": "seeded", "lesson": 4, "wait": "next", "hl": { "hexes": SEEDED },
			"text": "The map seeded these three. Water slows you, light heals but makes you easier to hit, dark hides you." },
		# ---- 5. reactions at 3 (D579)
		{ "id": "build_aim", "lesson": 5, "actor": "jericho", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "surge", "element": "fire", "hex": F_HEX }, "hl": { "ui": "skill" },
			"text": "Each element stacks up to 3. Pick Surge, Fire: it pours a step over a hex and the ring around it.",
			"touch": "Each element stacks up to 3. Choose Act, Surge, Fire: it pours a step over a hex and the ring around it." },
		{ "id": "build", "lesson": 5, "actor": "jericho", "wait": "act", "act": { "kind": "skill", "key": "surge", "element": "fire", "hex": F_HEX }, "hl": { "hex": F_HEX },
			"text": "Click the fire, then press Enter: fire 3 there, as high as it goes.",
			"touch": "Cursor on the fire, then A twice: fire 3 there, as high as it goes." },
		{ "id": "overheat_aim", "lesson": 5, "stage": "fire3", "actor": "jericho", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "saturate", "element": "fire", "hex": F_HEX }, "hl": { "ui": "skill" },
			"text": "More of an element on a 3 is a reaction. Pick Saturate, Fire once more.",
			"touch": "More of an element on a 3 is a reaction. Choose Act, Saturate, Fire once more." },
		{ "id": "overheat", "lesson": 5, "actor": "jericho", "wait": "act", "act": { "kind": "skill", "key": "saturate", "element": "fire", "hex": F_HEX }, "hl": { "hex": F_HEX },
			"text": "Click it. Fire on fire 3 Overheats: it burns everyone beside it and spreads fire onto them.",
			"touch": "Cursor on it, then A. Fire on fire 3 Overheats: it burns everyone beside it and spreads fire onto them." },
		{ "id": "others", "lesson": 5, "wait": "next", "hl": { "unit": "burt" },
			"text": "Burt stands in fire now. Water and light react at 3 too (Runneth Over drenches, Glinting blinds); the tile card names them.",
			"touch": "Burt stands in fire now. Water and light react at 3 too (Runneth Over drenches, Glinting blinds); X on a tile names them." },
		# ---- 6. operators
		{ "id": "fuse_aim", "lesson": 6, "actor": "jericho", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "saturate", "element": "thunder", "hex": C0 }, "hl": { "ui": "skill" },
			"text": "Thunder, ice and wind are operators: they cash in what the ground holds. Pick Saturate, Thunder.",
			"touch": "Thunder, ice and wind are operators: they cash in what the ground holds. Choose Act, Saturate, Thunder." },
		{ "id": "fuse", "lesson": 6, "actor": "jericho", "wait": "act", "act": { "kind": "skill", "key": "saturate", "element": "thunder", "hex": C0 }, "hl": { "hex": C0 },
			"text": "Click the bare hex between the three. Thunder on bare ground arms a fuse.",
			"touch": "Cursor on the bare hex between the three, then A. Thunder on bare ground arms a fuse." },
		{ "id": "det_aim", "lesson": 6, "actor": "jericho", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "saturate", "element": "fire", "hex": C0 }, "hl": { "ui": "skill" },
			"text": "Any other element landing on a fuse ignites it, even ice or wind. Pick Saturate, Fire.",
			"touch": "Any other element landing on a fuse ignites it, even ice or wind. Choose Act, Saturate, Fire." },
		{ "id": "preview", "lesson": 6, "actor": "jericho", "wait": "hover", "hex": C0, "hl": { "hex": C0, "preview": true },
			"text": "Hover the fuse first. The blast preview tags every unit the blast would hurt, red for your own side.",
			"touch": "Put the cursor on the fuse first. The blast preview tags every unit it would hurt, red for your own side." },
		{ "id": "detonate", "lesson": 6, "actor": "jericho", "wait": "act", "act": { "kind": "skill", "key": "saturate", "element": "fire", "hex": C0 }, "hl": { "hex": C0, "preview": true },
			"text": "Della is in the splash, but it's worth it. Click to detonate.",
			"touch": "Della is in the splash, but it's worth it. Press A, then A again to detonate." },
		{ "id": "glaze_aim", "lesson": 6, "actor": "jericho", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "bolt", "element": "ice", "target": "bob" }, "hl": { "ui": "skill" },
			"text": "Ice glazes a charged tile and freezes it in place. Pick Bolt, Ice, for Bob in the water.",
			"touch": "Ice glazes a charged tile and freezes it in place. Choose Act, Bolt, Ice, for Bob in the water." },
		{ "id": "glaze", "lesson": 6, "actor": "jericho", "wait": "act", "act": { "kind": "skill", "key": "bolt", "element": "ice", "target": "bob" }, "hl": { "unit": "bob" },
			"text": "Click Bob, then press Enter.",
			"touch": "Cursor on Bob, then A twice." },
		{ "id": "shatter_foe", "lesson": 6, "actor": "gail", "fresh": true, "wait": "forecast", "act": { "kind": "attack", "target": "bob" }, "hl": { "unit": "bob" },
			"text": "Gail's turn. Click Bob: his tile is glazed now.",
			"touch": "Gail's turn: Act, Attack, cursor on Bob, then A. His tile is glazed now." },
		{ "id": "shatter", "lesson": 6, "actor": "gail", "wait": "act", "act": { "kind": "attack", "target": "bob" }, "hl": { "ui": "notes" },
			"text": "On glaze Bob is Unsteady (-10 avoid, -15 glance) and every blow gets Shatter, +15%. Press Enter to shoot.",
			"touch": "On glaze Bob is Unsteady (-10 avoid, -15 glance) and every blow gets Shatter, +15%. Press A to shoot." },
		{ "id": "spark_aim", "lesson": 6, "actor": "jericho", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "bolt", "element": "thunder", "target": "rui" }, "hl": { "ui": "skill" },
			"text": "Spark: a thunder hit on a unit standing on bare ground deals +10%. Pick Bolt, Thunder, for Rui.",
			"touch": "Spark: a thunder hit on a unit standing on bare ground deals +10%. Choose Act, Bolt, Thunder, for Rui." },
		{ "id": "spark", "lesson": 6, "actor": "jericho", "wait": "act", "act": { "kind": "skill", "key": "bolt", "element": "thunder", "target": "rui" }, "hl": { "unit": "rui" },
			"text": "Click Rui and press Enter. The bolt leaves a fuse under him too.",
			"touch": "Cursor on Rui, then A twice. The bolt leaves a fuse under him too." },
		{ "id": "chain_foe", "lesson": 6, "actor": "gail", "fresh": true, "wait": "forecast", "act": { "kind": "attack", "target": "rui" }, "hl": { "unit": "rui" },
			"text": "Rui stands on a fuse, so he's conductive. Click him.",
			"touch": "Rui stands on a fuse, so he's conductive. Act, Attack, cursor on Rui, then A." },
		{ "id": "chain", "lesson": 6, "actor": "gail", "wait": "act", "act": { "kind": "attack", "target": "rui" }, "hl": { "ui": "notes" },
			"text": "Half of what he takes arcs to his nearest ally: the forecast names who. Press Enter.",
			"touch": "Half of what he takes arcs to his nearest ally: the forecast names who. Press A." },
		# ---- 7. skills, cooldowns, the second weapon
		{ "id": "skill_tip", "lesson": 7, "stage": "thread", "actor": "della", "fresh": true, "wait": "next", "hl": { "ui": "skill", "key": "thread_needle" },
			"text": "Skills are stronger moves than Attack. Hover one to see its range and cooldown.",
			"touch": "Skills are stronger moves than Attack. In the Act list, X on a skill shows its range and cooldown." },
		{ "id": "skill_aim", "lesson": 7, "actor": "della", "wait": "aim", "act": { "kind": "skill", "key": "thread_needle", "element": "fire", "target": "burt" }, "hl": { "ui": "skill" },
			"text": "Pick Thread the Needle: it strikes a foe standing on fire, and the Overheat left fire under Burt.",
			"touch": "Choose Thread the Needle: it strikes a foe standing on fire, and the Overheat left fire under Burt." },
		{ "id": "skill_use", "lesson": 7, "actor": "della", "wait": "act", "act": { "kind": "skill", "key": "thread_needle", "element": "fire", "target": "burt" }, "hl": { "unit": "burt" },
			"text": "Click Burt, then press Enter.",
			"touch": "Cursor on Burt, then A twice." },
		{ "id": "cooldown", "lesson": 7, "actor": "della", "fresh": true, "wait": "next", "hl": { "ui": "menu" },
			"text": "Thread the Needle's cooldown is 2, so it's missing from the menu until it's ready again.",
			"touch": "Thread the Needle's cooldown is 2, so it's missing from the Act list until it's ready again." },
		{ "id": "swap", "lesson": 7, "actor": "della", "wait": "act", "act": { "kind": "swap" }, "hl": { "ui": "swap" },
			"text": "Della carries a second weapon. Swap weapon is free: draw her bow.",
			"touch": "Della carries a second weapon. Swap weapon, in the Act list, is free: draw her bow." },
		{ "id": "swapped", "lesson": 7, "actor": "della", "wait": "next", "hl": { "ui": "menu" },
			"text": "Range, damage and skills follow the weapon in hand. You can swap back any time." },
		# ---- 8. statuses
		{ "id": "whip_aim", "lesson": 8, "stage": "bow", "actor": "della", "wait": "aim", "act": { "kind": "skill", "key": "pinning_shot", "element": "fire", "target": "burt" }, "hl": { "ui": "skill" },
			"text": "Statuses change what a unit can do. Pick Pinning Shot.",
			"touch": "Statuses change what a unit can do. Choose Act, Pinning Shot." },
		{ "id": "whip", "lesson": 8, "actor": "della", "wait": "act", "act": { "kind": "skill", "key": "pinning_shot", "element": "fire", "target": "burt" }, "hl": { "unit": "burt" },
			"text": "Click Burt and press Enter. He'll be Pinned: 2 less move.",
			"touch": "Cursor on Burt, then A twice. He'll be Pinned: 2 less move." },
		{ "id": "pin_aim", "lesson": 8, "actor": "gail", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "pinning_shot", "element": "wind", "target": "rui" }, "hl": { "ui": "skill" },
			"text": "Gail has one too. Pin Rui: pick Pinning Shot.",
			"touch": "Gail has one too. Pin Rui: Act, Pinning Shot." },
		{ "id": "pin", "lesson": 8, "actor": "gail", "wait": "act", "act": { "kind": "skill", "key": "pinning_shot", "element": "wind", "target": "rui" }, "hl": { "unit": "rui" },
			"text": "Click Rui and press Enter.",
			"touch": "Cursor on Rui, then A twice." },
		{ "id": "blinded", "lesson": 8, "actor": "gail", "wait": "next", "hl": { "unit": "rui" },
			"text": "Also: Staggered (no skills next turn) and Blinded (no crits, targets within 2). Hover a status icon over a unit for its rule.",
			"touch": "Also: Staggered (no skills next turn) and Blinded (no crits, targets within 2). X on a unit lists its statuses." },
		# ---- 9. facing
		{ "id": "facing", "lesson": 9, "actor": "della", "fresh": true, "wait": "next", "hl": { "unit": "burt" },
			"text": "Units face their last foe. A blow from behind gets +15 hit; one from the front may glance." },
		{ "id": "rear_move", "lesson": 9, "stage": "rear", "actor": "della", "wait": "move", "act": { "kind": "move", "hex": "rear" }, "hl": { "hex": "rear" },
			"text": "Move Della behind Burt.",
			"touch": "Move Della behind Burt: Move, then the marked hex." },
		{ "id": "rear_foe", "lesson": 9, "actor": "della", "wait": "forecast", "act": { "kind": "attack", "target": "burt" }, "hl": { "unit": "burt" },
			"text": "Now click Burt.",
			"touch": "Now Act, Attack, cursor on Burt, then A." },
		{ "id": "rear", "lesson": 9, "actor": "della", "wait": "act", "act": { "kind": "attack", "target": "burt" }, "hl": { "ui": "hit_row" },
			"text": "Hover Hit chance to find \"Rear attack +15 hit\". Then press Enter.",
			"touch": "The hit chance already counts the +15 from behind. Press A." },
		# ---- 10. winning
		{ "id": "worn", "lesson": 10, "stage": "worn", "actor": "jericho", "fresh": true, "wait": "aim", "act": { "kind": "skill", "key": "surge", "element": "thunder", "hex": C0 }, "hl": { "ui": "skill" },
			"text": "They're worn down now. Pick Surge, Thunder: it bursts over a hex and everything beside it.",
			"touch": "They're worn down now. Choose Act, Surge, Thunder: it bursts over a hex and everything beside it." },
		{ "id": "finish", "lesson": 10, "actor": "jericho", "wait": "act", "act": { "kind": "skill", "key": "surge", "element": "thunder", "hex": C0 }, "hl": { "hex": C0, "preview": true },
			"text": "Click the hex between them: the thunder also detonates the painted ground there. Press Enter to win.",
			"touch": "Cursor on the hex between them: the thunder also detonates the painted ground there. A twice to win." },
		{ "id": "won", "lesson": 10, "wait": "over",
			"text": "Knock out whoever is left: any attack or skill will do." },
		{ "id": "results", "lesson": 10, "wait": "results", "hl": { "ui": "level_up" },
			"text": "The summary shows who did what. Every fight, won or lost, gives every unit one level." },
		{ "id": "perk", "lesson": 10, "wait": "pick", "pick": { "unit": "della", "kind": "perk", "element": "fire" },
			"text": "Element ranks earn perks; ranks 3 and 6 a gold keystone (a rule-breaker and a title), two elements at 4 a duo. Pick a card.",
			"touch": "Element ranks earn perks; ranks 3 and 6 a gold keystone (a rule-breaker and a title), two elements at 4 a duo. Tap a card." },
		{ "id": "skill_pick", "lesson": 10, "wait": "pick", "pick": { "unit": "della", "kind": "skill", "weapon": "sword" },
			"text": "Ranks with a weapon earn skill picks: improve a skill you have or learn a new one.",
			"touch": "Weapon ranks earn skill picks: improve a skill you have or learn a new one. Tap a card." },
		# ---- 11. the closing card
		{ "id": "closing", "lesson": 11, "wait": "card",
			"text": "That's a fight. Between fights there's more to choose." },
	]


static func lesson_name(n: int) -> String:
	return LESSONS[clampi(n, 0, LESSONS.size() - 1)]


## The first step index of a lesson (or the end).
static func lesson_start(all: Array, lesson: int) -> int:
	for i in all.size():
		if int(all[i].get("lesson", 0)) >= lesson:
			return i
	return all.size()


# ---------------------------------------------------------------- the cast

static func row(id: String) -> Dictionary:
	var r := {}
	for i in BWData.identities():
		if str(i.id) == id:
			r = Dictionary(i).duplicate()
	r["id"] = id
	if not r.has("name"):
		r["name"] = id.capitalize()
	r.merge(KITS.get(id, {}), true)
	return r


## The tutorial's own run: never saved, never the player's. The squad's kits,
## loadouts and the elements Jericho can lay are fixed here.
static func make_run() -> BWRun:
	var rows: Array = SQUAD.map(func(id): return row(id))
	var run := BWRun.start(SQUAD, RUN_SEED, rows, 0)
	for u in run.squad:
		u.equipment["main_hand"] = run.make_item(u.weapon_model, "E", "")   # no enchantment: plain numbers
		match u.id:
			"della":
				u.perks = ["fire_rush"]     # D284: fixed (the drawn one was Coal Engine, now inside Heat Rush; a 4-perk draw gave Wildfire)
				u.equipment[BWUnit.SECOND] = run.make_item("shortbow", "E", "")   # D419: was the m1911 (pistols benched)
				_learn(u, "sword", ["thread_needle", "striketwice"])   # D438: was Heart Seeker
				_learn(u, "bow", ["pinning_shot", "arcing_shot"])
			"jericho":                  # D468: thunder by nature + fire + ice = the 3-element cap (D417)
				for el in ["fire", "ice"]:
					u.affinity[el] = BWUnit.POINTS_PER_RANK
				_learn(u, "staff", ["bolt", "saturate", "surge"])
			"gail":
				_learn(u, "bow", ["pinning_shot", "arcing_shot"])
		u.sync_weapon()
		# D271/D407: the lessons' wind skills move nobody (they predate wind
		# shaping): Hold, as the old Becalm mode did. A wind basic pushes 1.
		u.wind_shapes = { "saturate": { "opt": "hold", "rel": 0 }, "pinning_shot": { "opt": "hold", "rel": 0 },
			"surge": { "opt": "hold", "rel": 0 }, "arcing_shot": { "opt": "hold", "rel": 0 } }
	return run


static func _learn(u: BWUnit, wc: String, keys: Array) -> void:
	for k in keys:
		if not k in u.known_skills and not k in BWSkillRegistry.starter(wc):
			u.known_skills.append(k)
	u.skill_loadout[wc] = keys.duplicate()


static func make_enemies() -> Array:
	return FOES.map(func(id): return BWUnit.from_roster(row(id)))


# ---------------------------------------------------------------- the rules side

## The turn-passing rule the screen uses (BWCombatScreen.turn_hook): every
## turn that isn't `want`'s is passed at once (enemies always: they hold).
static func passes(u: BWUnit, want: BWUnit) -> bool:
	return u.team != "player" or (want != null and u != want)


## After an action: keep the turn with the actor while it can still do
## something, else let the turn order run to the next player unit.
static func keep_actor(b: BWBattle, u: BWUnit) -> bool:
	return u != null and u.alive() and (not u.acted or b.can_move(u) or not u.follow_up.is_empty())


## Where "behind Burt" is: the hex straight back from his facing (else the
## nearest free hex on that side) that Della can reach.
static func rear_hex(b: BWBattle, della: BWUnit, foe: BWUnit) -> Vector2i:
	if foe.facing < 0:
		return FRONT
	var back := (foe.facing + 3) % 6
	var reach := b.reachable(della)
	var best := Vector2i(-1, -1)
	var best_d := 99
	for h in reach:
		if not reach[h].stop or h == della.pos or b.unit_at(h) != null:
			continue
		if BWHex.direction_index(foe.pos, h) != back:
			continue
		var d := BWHex.distance(foe.pos, h)
		var hot := 0
		for p in BWBoard.path_to(reach, h):
			if p != della.pos and b.tiles.crossing_pct(p) > 0:
				hot += 5                       # a cool path: no fire underfoot on the way
		var score := d + hot
		if score < best_d:
			best_d = score
			best = h
	return best


## D579: the lessons after the Overheat still need Burt standing (he burns
## in its fire every round): his HP is kept up to `share` of his max.
static func _sturdy(u: BWUnit, share: float) -> void:
	if u != null and u.alive():
		u.hp = maxi(u.hp, roundi(u.max_hp() * share))


## Play the whole script on the rules alone (no views): the same actions in
## the same order, the same staging and the same turn passing as the live
## tutorial. Returns { battle, run, log: [step id, outcome], ok }.
static func dry_run(seed_value: int = SEED) -> Dictionary:
	var run := make_run()
	var enemies := make_enemies()
	var b := BWBattle.new(BWBoard.load_file(MAP), seed_value)
	b.setup(run.squad.duplicate(), enemies)
	var st := { "want": null }
	var by := func(id: String) -> BWUnit: return b._unit(id)
	var settle := func() -> void:
		var guard := 0
		while not b.over and guard < 200:
			guard += 1
			var u := b.current()
			if u == null:
				break
			if passes(u, st.want):
				b.end_turn()
				continue
			if u.team == "player" and u.acted and u.follow_up.is_empty() and not b.can_move(u):
				b.end_turn()
				continue
			break
	var log: Array = []
	var rear := Vector2i(-1, -1)
	settle.call()
	for s in steps():
		var actor_id := str(s.get("actor", ""))
		if actor_id != "":
			var a: BWUnit = by.call(actor_id)
			give_turn(b, a, bool(s.get("fresh", false)), st, settle)
		var stage := str(s.get("stage", ""))
		if stage != "":
			var r := stage_rules(b, stage, run)
			if r.has("rear"):
				rear = r.rear
			settle.call()
		var w := str(s.get("wait", ""))
		if not w in ["move", "undo", "act"]:
			continue
		var act: Dictionary = s.get("act", {})
		var u := b.current()
		var before := b.history.size()
		match str(act.get("kind", "")):
			"move":
				var to: Variant = act.hex
				if str(to) == "rear":
					to = rear
				b.move(u, to)
			"undo":
				b.undo_move(u)
			"attack":
				b.attack(u, by.call(str(act.target)))
			"skill":
				var hex: Vector2i = act.hex if act.has("hex") else (by.call(str(act.target)) as BWUnit).pos
				b.use_skill(u, str(act.key), str(act.element), hex)
			"swap":
				b.swap_weapon(u)
		var evs: Array = b.history.slice(before)
		log.append([str(s.id), evs.map(func(e): return str(e.type))])
		if w == "act" and not keep_actor(b, u):
			st.want = null
		settle.call()
	return { "battle": b, "run": run, "log": log }


## Hand the turn to `u`: end the current player's turn (when it isn't `u`, or
## when a fresh turn is wanted and `u` has already moved or acted) and pass
## everyone else. `settle` runs the turn loop (the screen's _after_events).
static func give_turn(b: BWBattle, u: BWUnit, fresh: bool, st: Dictionary, settle: Callable) -> void:
	if b.over or u == null or not u.alive():
		return
	st.want = u
	var cur := b.current()
	if cur == u and not (fresh and (u.acted or u.moved)):
		return
	if cur != null and cur.team == "player":
		b.end_turn()
	settle.call()


## Staging on the rules (the live tutorial plays the events it emits).
## front: Della stands in front of Burt (after a skipped lesson); fire3 (D579):
## the fire tile is back at 3 before the Overheat; fire_at_f:
## the fire tile is back if it decayed; bow: Della holds her bow (D419: was pistols);
## worn: the enemies are down to a sliver; rear: where "behind Burt" is.
static func stage_rules(b: BWBattle, stage: String, run: BWRun) -> Dictionary:
	var della := b._unit("della")
	var burt := b._unit("burt")
	match stage:
		"front":
			if della.pos != FRONT and b.unit_at(FRONT) == null:
				b.place_unit(della, FRONT)
		"thread":                                   # D438: Thread the Needle wants Burt on fire
			if della.pos != FRONT and b.unit_at(FRONT) == null:
				b.place_unit(della, FRONT)
			var bu := b._unit("burt")
			_sturdy(bu, 0.75)                          # D579: the Overheat's fire burns him every round now
			if bu != null and bu.alive() and not b.tiles.carries(bu.pos, "fire"):
				var da := della.attuned
				b.paint([bu.pos], "fire", della, 1, false)
				della.attuned = da
		"fire3":                                    # D579: the Overheat needs fire 3 there before the cast (it decays a step a round)
			if b.tiles.intensity(F_HEX, "fire") < 3:
				var j3 := b._unit("jericho")
				var att3 := j3.attuned
				b.paint([F_HEX], "fire", j3, 3 - maxi(0, b.tiles.intensity(F_HEX, "fire")), false)
				j3.attuned = att3
		"fire_at_f":
			if b.tiles.intensity(F_HEX, "fire") < 1:
				var j := b._unit("jericho")
				var att := j.attuned
				b.paint([F_HEX], "fire", j, 2, false)
				j.attuned = att
		"bow":
			_sturdy(burt, 0.5)                         # D579: he has the pin and the rear attack still to take
			if della.weapon_class != "bow" and b.current() == della:
				b.swap_weapon(della)
		"worn":
			for e in b.side("enemy"):
				if e.alive():
					e.hp = mini(e.hp, 4)
			# D419: the finale's rolls no longer hang on every earlier lesson's
			# (the bow lesson moved the stream): a fixed stream where the Surge lands
			b.rng.seed = WORN_SEED
		"rear":
			if burt != null and burt.alive():
				return { "rear": rear_hex(b, della, burt) }
	return {}
