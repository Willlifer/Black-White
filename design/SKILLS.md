# Skills (D87, D103–D108)

Every weapon skill, final. Each class has its **starter kit** (`data/weapons.csv`
`skills`) and **five learnable skills** (an expertise pick: *learn*). An
*improve* pick gives a known skill its one **Improve rider** (`+`); only the
skills with a rider listed below change when improved. The row field `plus`
carries the rider's text for the pick screen.

Rules live in one file per skill, `src/core/skill_defs/<key>.gd` (D89). The
new skills keep their tuning numbers as constants in their own file; the
starter kit's numbers stay in `src/core/skills.gd`. Tests:
`tests/test_skills_pass.gd` (D87) and `tests/test_weapon_skills_*.gd` (D103–D108).

Columns: **cd** in the unit's own turns ("once" = once per battle). **Shape**
is what a click means. **Power** is skill power (spell power for the staff),
before the formula (power + ½STR + ½DEX; spells power + WIL). An elemental
skill lays its element on its shape unless the hook says otherwise.
*Free* = spends no action (set it before or after acting).

## Sword — the duelist who picks the moment

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Striketwice *(starter)* | 2 | adjacent foe | 11 ×2 | The Second Cut may go to any adjacent foe. Same foe twice: can't glance, Staggers. Same element: floods the ring. Opposite elements: douse (fire + water: foes on the ring Drenched, D422) / eclipse / storm on the hex | **+** If both cuts land, a third cut hits the weakest adjacent foe at 50% |
| Riposte *(starter)* | 3 | self, free | 10 (answer) | Guard: the first blow to land is halved and answered on your ring; a landed answer refunds 1 cd. **D425:** unanswered by your next turn, it releases: six 3-hex lines of its element run out from you (rock stops a line), painted like Ley Line; the standing guard shows the 18 hexes as dots | **+** Answers the first two blows, both halved |
| Thread the Needle *(D438; replaced Heart Seeker)* | 2 | adjacent foe standing on your element | 11 | Strike, then dash on through its hex along the hexes beyond it that hold that element, up to 3, to the line's end (a unit, rock or a hex without it stops you; nothing beyond: just the strike). Riding your own line never burns you · clip `thrust` | — |
| Tapestry *(D439; replaced Triumph)* | once | self (uses the action) | — | Every hex on the map holding your element pulses: foes on them take 10% of max HP (ground damage, resistance applies); allies on them, you too, are Swift (+1 move next turn). Nothing painted or consumed · clip `brace` | — |
| Whirlwind Blade | 3 | ring around you | 9 each | Paints the ring 1 step of the element you choose (any with affinity) · clip `spin` | — |
| Lunge | 2 | heading, line 3 | 11 | Dash straight; strike the first foe in the way. **D438:** the dashed-over hexes and the foe's take the element. An ally or rock just stops you (no heading offered). Running: fire burns | — |
| En Passant *(D426; replaced Elemental Truth)* | 3 | foe ≤ 3 in a straight line | 11, then the Passing Cut 9 | Dash through the foe, striking it, and land on the hex right beyond (rock, a unit, the edge or a steep climb there: not a target, the aim shows it red). Every hex travelled takes the element, the target's too. Then the **Passing Cut** (follow-up): a strike at any adjacent foe in the dash's element. A run: fire burns | — |

**Passive pick (D427): Blade Dance.** Offered in the sword's expertise picks like
HighGrounder (weapons.csv `passives`; not perks.csv, which holds element perks
only): after one of your sword skills lands (and grants no follow-up), one
free step of **up to 2 hexes** (the author: 2, not 1), walkable, not through
units. The board marks the hexes; click one, or Esc / any other action skips
it. The AI steps to the least dangerous one or skips.

**Retired (D426, D435-D442):** Elemental Truth, Heart Seeker, Triumph, Reckless Swing, War Cry, Guardrush, Aimed Shot, Aegis, Assassinate and Hamstring. Their defs stay (row `retired`: never offered, never usable) and a save maps each to its replacement (`BWSkillRegistry.RENAMED`; the pure removals to Sweep, Pinning Shot and Transfer).

**Elemental Truth** is retired (D426): the def stays for old saves, which map it
to En Passant (known, Improve, loadout slot); it is never offered.

## Axe — wide directional AoEs and big charges (D433: no speed penalty)

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Cleave *(starter)* | 2 | heading, 3-hex arc | 13 | +10% to everyone per foe beyond the first. **D433:** if any arc hex already holds your element, the swing widens to all 6 hexes around you | **+** +15% per extra foe |
| Charge *(starter)* | 2 | heading, run 7 | basic follow-up | **D434 Momentum:** +3% to the end swing per hex run (7: +21%, a named forecast line). **D414:** pushes one foe along ahead of you; where it can't go on (rock, a unit, a pillar) the run stops behind it and it slams for 8% (it and what it hits); the map edge just stops it. Paints the walk. **High ground (D362):** from 1+ level above the first hex, reach +1 and the shove carries 1 hex further | **+** Reach 8, slam 12% |
| Reckless Arc *(D435; replaced Reckless Swing)* | 2 | heading, the 5 hexes in front (all neighbours but the one behind) | 12 each | Paints the arc; you are Scorched (attacks on you +10%) through your next turn · clip `cut` | — |
| Hook | 2 | foe within 3, **free** | 9 | Pulls it straight in until it's next to you (secondary). **D437:** spends no action: hook, then move and act as normal | — |
| Sunder | 3 | adjacent foe, then a fissure | 13 (60% on the fissure) | **D415:** the blow ignores 30% DEF and can't glance; the ground then splits from you through the target, 5 hexes (10 after a Bellow): every hex takes the element (like Ley Line), every other foe on it is hit at 60%. Rock and pillars stop it | — |
| Earthsplitter | 4 | heading, line 3 | 11 each | **D416:** no paint; each foe on the line is heaved 1 hex back along it (secondary); jagged rock stops the split | — |
| Bellow *(D436; replaced War Cry)* | 4 | self (uses the action) | — | Your next Cleave or Sunder this battle doubles: Cleave hits the 6 around you + the 5 ring-2 hexes ahead (11); Sunder's fissure runs 10. Held until used (inked spikes at the feet, a card line) · clip `war_cry` | — |

## Lance — mobile, utility

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Tridentpierce *(starter)* | 2 | heading, 2 + sides | 10 | A foe right behind the first in line is pierced +20% | **+** The pierce carries on to a third foe in line |
| Vault *(starter; D105 rework)* | 2 | foe 2–3 away | weapon basic | One click: pole-vault over anything (units, rock, height) to the free hex beside it nearest you, paint the takeoff hex, and strike at once with the basic attack +25% momentum. No follow-up menu. **High ground (D362):** +1 range onto a foe 1+ level below | **+** Range 4, momentum +35% |
| Sweep | 3 | heading, the 3 front hexes adjacent to you | 9 each | Each foe shoved 1 straight away from you (slam 8% if blocked); paints the arc. The crowd-spacing tool (Tridentpierce pierces a line) | — |
| Set Spear | 3 | self, free | — | Until your next turn every hex within your reach is a zone: an enemy entering one stops there and can't path past. No strike | — |
| Phalanx | 4 | self + adjacent allies | — | −15% damage taken until each one's next turn; you can't be displaced until yours | — |
| Dragoon Dive | once | leap ≤ 4 | 13 to the landing ring | Paints the landing ring. **High ground (D362):** onto a hex 1+ level below, reach 5 and the ring radius 2 | — |
| Lance Charge *(D428, added: a sixth learnable)* | 4 | a hex 2–10 away in a straight line | 10 per foe | Uses the action; the line is set and shown to both sides (the AI steps off it). At the start of your next turn, before you act, you run it: each foe in the way is struck and **pierced** (you run on through when the next line hex is free); one you can't pass you stop in front of, and if rock or a unit stopped it, it slams (8%, it and the unit behind). An ally or rock stops you. The path (pierced hexes too) takes the element. Then move and act as normal | — |

## Bow — the precise remote trigger

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Arcing Shot *(starter)* | 2 | hex within 6, radius 1 | 10 | From 2+ levels above the target the blast is a radius wider | **+** Needs only 1 level |
| Energized Shot *(starter)* | 2 | foe within 6 | 12 | Lays the trail; punches through to the next foe within 3 past it at 60% | **+** Pierce 80%, reaches 5 |
| Split Arrow | 2 | foe within 5 + both side headings | 12 at 60% each | Three arrows, each rolled; a side arrow takes the first foe on its heading | — |
| Retreating Shot | 2 | foe within 5 | 10 | Then +2 move (a second move if you'd moved, else on top of yours) | — |
| Pinning Shot | 3 | foe within 6 | 10 | Pinned (−2 move), secondary | — |
| Rain of Arrows | once | hex within 6, radius 2 | 9 each | Paints all 19 hexes | — |

**Passive pick (D372): HighGrounder.** Offered in the bow's expertise picks
like a skill to learn, but a passive: it takes no skill slot. While a bow is
drawn the jump doubles, 2 → 4 (ELEMENTS.md §6.6). Shown on the unit card once
owned; enemy bows may roll it.

## Staff — the safe painter (spells)

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Surge *(starter)* | 2 | hex within 4, radius 1 | 9 | The centre takes +30% | **+** Centre +50% |
| Saturate *(starter)* | 2 | hex within 4 | 13 | Pours 2 steps; pushing an axis to 3 marks the foe (Scorched / Drenched / Blinded / Shrouded) | **+** The mark also lands when the pour ends at 2 |
| Ley Line *(starter)* | 2 | heading, line 4 | basic follow-up | Allies on the line are Swift (+1 move) | **+** Length 6 |
| Siphon *(starter)* | 2 | hex within 4 | basic follow-up | Strips the hex; heals you 4% per step | **+** 6% per step, to an ally on the hex (else you) |
| Bolt | 1 | foe within 4 | 10 | +20% if its hex already carries the element you cast | — |
| Transfer | 3 | a charged hex within 4 | basic follow-up | Lifts the whole charge or marker onto an empty hex within 4 (automatic: under a foe if it hurts, under the most hurt ally if it helps); the tile becomes yours | **+** Spreads onto the destination and its ring |
| Inversion | 4 | a hex within 4 (sight); radius 2, 19 hexes | — | D418: every tile in the area flips its axes (fire 3 ↔ water 3, dark ↔ light); fuse ↔ gale; stasis and glaze stay. Nothing else: no damage, no status, no follow-up. The preview rims the area and tags each swap | **+** Cooldown 3 |
| Tempest | once | hex within 4, radius 2 | 9 each | Paints all 19 hexes | — |

## Daggers — spellblade AoE, a high-risk staff

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Consume *(starter)* | 2 | adjacent foe on your element | 14 + 2/point | Eats the tile; heals 5% per point eaten. **D429:** and raises a **barrier** of the same size (the nominal heal, so full HP counts) that soaks any damage until your next turn | **+** 7% per point |
| Daggerleap *(starter)* | 2 | leap 3 (or any tile with the element), then a second pick | 8 to the ring | Foes you land behind take +50%. **D429 hit and run:** then leap away up to 2 hexes from the landing to the hex you pick (the landing = stay; the AI takes the safest). **High ground (D362):** onto a hex 1+ level below, reach 4 and the landing ring radius 2 | **+** Backstab +75% |
| Dualthrow *(starter)* | 2 | foe within 4 | 9, then the Second Dagger | Lays the trail; the Second Dagger bounces to a foe within 2 at 75% | **+** Bounces twice: 75%, then 50% |
| Tumble | 1 | self, free | — | After you attack this turn, +2 move (set before: waits for the attack) | — |
| Manipulate *(drafted as Twist the Knife)* | 2 | adjacent foe | 9 | +10% per status on it, +10% if it stands on charge, up to +60% | — |
| Kindle *(D441; replaced Hamstring)* | 3 | foe within 3 | — | Your element takes all six hexes around it (1 step; its own hex untouched). No damage · clip `throw` | — |
| Fan of Knives *(D430 rework)* | 3 | self, radius 2 | 8 each | Every foe within 2 is struck; every hex within 2 (not yours) takes the element. The reactions that paint sets off (detonations, shocks, overheats, overfreezes, arcs) **can't hurt you**; allies in it aren't spared · clip `spin`, knives to every hex | — |
| Overload *(D440; replaced Assassinate)* | 4 | self, radius 2 (uses the action) | — | Every charged hex within 2 (yours too: fire/water/light/dark steps or a fuse) blows like a fuse detonation (5% + 4% per step) **+50%** and is cleared: its hex in full, the ring at half, both teams, **you are not spared**. The preview lists every total · clip `brace` | — |

**Spellblade ideas (D432, not built; the author picks):** Dualthrow lays its
trail through the target on to the bounce victim; Manipulate counts the
tile's steps as statuses; Tumble paints the hexes it leaves (a Trailblazer-
lite); Assassinate sets off the target's tile (D440 went further: Overload). The kit already leans that
way: Consume (eat a tile, barrier), Fan of Knives (radius-2 paint, immune to
its own blasts), Daggerleap onto your own element anywhere.

## Pistols — rounds, tempo, close range — benched (D419)

*Benched (D419): kept for a return, never offered or rolled; saves convert pistols to bows (D420).*

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Reload *(starter)* | — | self | — | Seat a round: readies Quick Shot, the next shot lays a trail; your own element +10% | **+** Seats two rounds (two trailed shots) |
| Quick Shot *(starter)* | — | foe in range, free | basic | Once per reload; twice if you haven't moved | **+** Three times if unmoved |
| Point Blank | 2 | adjacent foe | 13 | +20%, and it's shoved back 1 (no slam). Plain lead | — |
| Pistol Whip | 2 | adjacent foe | 9 | Staggered; Quick Shot ready again · clip `pistol_whip` | — |
| Flash Round | 3 | foe within 5 | 8 | Blinded; lays the seated round's trail | — |
| Covering Fire | 3 | self (uses the action), radius 3 | — | Overwatch: the first foe to attack an ally within 3 before your next turn draws your basic shot | — |
| Empty the Chamber | once | self: up to 4 foes within 5 | 12 at 35% a shot | 4 shots, nearest first, spare shots go round again; each rolled; the seated round trails every shot | — |

## Fists — combos, shoves, pouring — benched (D419)

*Benched (D419): kept for a return, never offered or rolled; saves convert fists to daggers (D420).*

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Flurry *(starter)* | 2 | adjacent foe | 12, 3 × 45% | The last strike +15 crit | **+** Last strike +30 crit |
| Uppercut *(starter)* | 2 | adjacent foe | 12 | Knockback 1; slams +50% into rock or a unit | **+** Slam +75%, and the slammed foe is Staggered |
| Palm Burst *(starter)* | 2 | adjacent foe | 9 | Pours 2 steps; a hex already carrying it pushes the foe 1 | **+** Push 2 |
| Shockwave Palm | 3 | heading, line 3 | 9 each | Each foe shoved 1 along the line (far one first); paints the line | — |
| Brace | 3 | self, free | — | −25% damage taken until your next turn; your next Flurry +1 strike | — |
| Grapple Throw | 3 | adjacent foe | 9 | Thrown down on a free hex next to you (automatic: your own charge first, then the worst ground); +50% if it lands on charge you laid | — |
| Haymaker | 4 | adjacent foe | 14 | +25 crit if you haven't moved | — |
| Hundred Fists | once | adjacent foe | 12, 6 × 30% | Each blow rolled; the last pours 2 steps | — |

## Shared mechanics (inside the defs)

- **Once per battle**: the def's `cooldown()` sets every element's key to
  999 (the row says `once_per_battle: true`), so the skill leaves the menu
  for the rest of the fight; `begin_battle` clears it.
- **Guards** (Phalanx, Brace; Aegis retired) ride the FX `guard` (a labelled `dmg`
  forecast modifier). The strongest holds; they don't stack. A guard drops
  when its holder's turn starts; Aegis puts its own back up for that turn and
  takes it down at that turn's end.
- **Timed effects** (War Cry's STR, Riposte+'s second guard, Tumble's wait,
  Reload+'s spare round, Phalanx's no-displace) listen to `BWBattle.event`.
- **Displacement**: shoves and slams share Guardrush's helpers (the def is retired, D442; the helpers stay) (the Charge
  slam rule: rock or a unit slams, the edge is open air, an immune foe
  braces). Every shove, pull, throw and status from a skill is a secondary
  effect: it lands on an avoid, a resist stops it.
- **Engine hooks** (D97): Set Spear's zone, Covering Fire's overwatch and
  Grapple Throw's placement use `BWSkillDef.zone` / `overwatch` / `place`.

## Short statuses

Named in `BWSkills.STATUS`; each lasts until the end of its holder's next
turn (D94). Staggered: can't use skills on its next turn. Blinded: can't
crit and can only target units within 2. Pinned: −2 move. Scorched: attacks
on it +10%. Drenched: −1 move, thunder hits on it +20%. Shrouded: 4% dark
drain at its turn start. Swift: +1 move.

## AI

BWAI weighs every damaging skill through its forecast (riders included).
Overrides: Whirlwind Blade, Fan of Knives and Empty the Chamber (self-shaped
attacks), Vault (its strike's forecast from the landing) and En Passant (a
damaging skill with a follow-up; the AI then plays the Passing Cut). Lance
Charge is a support cast (`ai_support`: foes on a line), and every unit
keeps off a foe's set charge line. Blade Dance: the least dangerous step, or skip. Free guards set
last in its turn: Riposte (a foe within 3), Brace (within 2), Set Spear (a
foe that could walk into reach). It never uses Phalanx, Covering
Fire, Tumble, Transfer, Ley Line or Siphon. Kit pass 3 (D435-D441): Bellow
(a Cleave / Sunder in the kit, no foe in reach yet), Tapestry (two foes on the
element or a KO), Overload (only when the blasts hurt foes more than its side,
itself counted double) and Kindle (no blow in hand) are `ai_support` casts;
Hook is a free **opener** (`ai_opener`): the AI hooks a foe in, then plays its
turn. Charge's value counts its Momentum. Inversion (D418) scores
its whole radius-2 area through `ai_support`: harm flipped away from allies and
help flipped away from foes, minus the reverse.

## Presentation

The forecast box lists every rider as a ◆ line; the hint while aiming names
skill-level riders (shoves, slams, pulls, statuses, the Vault strike's odds).
Named riders float as tags under the damage number. Clips: Whirlwind Blade
and Fan of Knives `spin`, Pistol Whip `pistol_whip`; the view falls back to
the class strike while a clip is missing.

## UI needs (one-click stand-ins today)

The combat screen takes one click per skill. Three skills would want a
second pick; until then the def chooses:

1. **Transfer**: pick the source hex, then the destination (an empty hex
   within 4 of the caster). Today: `transfer.gd dest_for`.
2. **Grapple Throw**: pick the foe, then the landing (a free hex next to the
   thrower). Today: `grapple_throw.gd dest_for` (the AI keeps using it).
3. **Striketwice+**'s third cut: pick which adjacent foe. Today: the one
   with the least HP.

Whirlwind Blade's element is the existing element menu. Self-shaped skills
(Whirlwind Blade, Fan of Knives, Empty the Chamber, War Cry, Phalanx,
Covering Fire, Set Spear, Brace, Tumble) fire on the menu click with no
confirm window, like Riposte; a preview box for the damaging ones would help.
Vault resolves on the click too (its odds are in the hint).
