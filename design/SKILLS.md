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
| Striketwice *(starter)* | 2 | adjacent foe | 11 ×2 | The Second Cut may go to any adjacent foe. Same foe twice: can't glance, Staggers. Same element: floods the ring. Opposite elements: steam / eclipse / storm on the hex | **+** If both cuts land, a third cut hits the weakest adjacent foe at 50% |
| Riposte *(starter)* | 3 | self, free | 10 (answer) | Guard: the first blow to land is halved and answered on your ring; a landed answer refunds 1 cd | **+** Answers the first two blows, both halved |
| Heart Seeker | 2 | adjacent foe | 10 | +25 crit | — |
| Triumph | once | adjacent foe | 12 ×1.5 | A KO with it: +25% STR for the rest of the battle | — |
| Whirlwind Blade | 3 | ring around you | 9 each | Paints the ring 1 step of the element you choose (any with affinity) · clip `spin` | — |
| Lunge | 2 | heading, line 3 | 11 | Dash straight; strike the first foe in the way. An ally or rock just stops you (no heading offered). Running: fire burns | — |
| Elemental Truth | 4 | adjacent foe | 10 ×1.5 | The element twice on the target hex: axis +2 steps; thunder detonates, then re-arms; ice glazes 4 cycles (bare ground: stasis); wind's gale copies last 2 cycles | — |

## Axe — slow, heavy, breaks lines

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Cleave *(starter)* | 2 | heading, 3-hex arc | 13 | +10% to everyone per foe beyond the first; the element already there carries the swing a ring further | **+** +15% per extra foe |
| Charge *(starter)* | 2 | heading, run 7 | basic follow-up | **D414:** pushes one foe along ahead of you; where it can't go on (rock, a unit, a pillar) the run stops behind it and it slams for 8% (it and what it hits); the map edge just stops it. Paints the walk. **High ground (D362):** from 1+ level above the first hex, reach +1 and the shove carries 1 hex further | **+** Reach 8, slam 12% |
| Reckless Swing | 1 | adjacent foe | 14 | You are Scorched (attacks on you +10%) through your next turn | — |
| Hook | 2 | foe within 3 | 9 | Pulls it straight in until it's next to you (secondary) | — |
| Sunder | 3 | adjacent foe, then a fissure | 13 (60% on the fissure) | **D415:** the blow ignores 30% DEF and can't glance; the ground then splits from you through the target, 5 hexes: every hex takes the element (like Ley Line), every other foe on it is hit at 60%. Rock and pillars stop it | — |
| Earthsplitter | 4 | heading, line 3 | 11 each | **D416:** no paint; each foe on the line is heaved 1 hex back along it (secondary); jagged rock stops the split | — |
| War Cry | 4 | self (uses the action) | — | +20% STR for your next 2 turns | — |

## Lance — reach, lines, holding ground

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Tridentpierce *(starter)* | 2 | heading, 2 + sides | 10 | A foe right behind the first in line is pierced +20% | **+** The pierce carries on to a third foe in line |
| Vault *(starter; D105 rework)* | 2 | foe 2–3 away | weapon basic | One click: pole-vault over anything (units, rock, height) to the free hex beside it nearest you, paint the takeoff hex, and strike at once with the basic attack +25% momentum. No follow-up menu. **High ground (D362):** +1 range onto a foe 1+ level below | **+** Range 4, momentum +35% |
| Guardrush *(drafted as Skewer)* | 2 | foe within reach 2 | 12 | Shove it back 1; blocked by rock or a unit: slam 8% (it and what it hits) | — |
| Sweep | 3 | heading, the 3 front hexes adjacent to you | 9 each | Each foe shoved 1 straight away from you (slam 8% if blocked); paints the arc. The crowd-spacing tool (Tridentpierce pierces a line) | — |
| Set Spear | 3 | self, free | — | Until your next turn every hex within your reach is a zone: an enemy entering one stops there and can't path past. No strike | — |
| Phalanx | 4 | self + adjacent allies | — | −15% damage taken until each one's next turn; you can't be displaced until yours | — |
| Dragoon Dive | once | leap ≤ 4 | 13 to the landing ring | Paints the landing ring. **High ground (D362):** onto a hex 1+ level below, reach 5 and the ring radius 2 | — |

## Bow — distance, height, picking targets

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Arcing Shot *(starter)* | 2 | hex within 6, radius 1 | 10 | From 2+ levels above the target the blast is a radius wider | **+** Needs only 1 level |
| Energized Shot *(starter)* | 2 | foe within 6 | 12 | Lays the trail; punches through to the next foe within 3 past it at 60% | **+** Pierce 80%, reaches 5 |
| Aimed Shot | 2 | foe within 8 | 13 | +20 hit; +10 crit if you haven't moved | — |
| Split Arrow | 2 | foe within 5 + both side headings | 12 at 60% each | Three arrows, each rolled; a side arrow takes the first foe on its heading | — |
| Retreating Shot | 2 | foe within 5 | 10 | Then +2 move (a second move if you'd moved, else on top of yours) | — |
| Pinning Shot | 3 | foe within 6 | 10 | Pinned (−2 move), secondary | — |
| Rain of Arrows | once | hex within 6, radius 2 | 9 each | Paints all 19 hexes | — |

**Passive pick (D372): HighGrounder.** Offered in the bow's expertise picks
like a skill to learn, but a passive: it takes no skill slot. While a bow is
drawn the jump doubles, 2 → 4 (ELEMENTS.md §6.6). Shown on the unit card once
owned; enemy bows may roll it.

## Staff — depth, rewriting the ground (spells)

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Surge *(starter)* | 2 | hex within 4, radius 1 | 9 | The centre takes +30% | **+** Centre +50% |
| Saturate *(starter)* | 2 | hex within 4 | 13 | Pours 2 steps; pushing an axis to 3 marks the foe (Scorched / Drenched / Blinded / Shrouded) | **+** The mark also lands when the pour ends at 2 |
| Ley Line *(starter)* | 2 | heading, line 4 | basic follow-up | Allies on the line are Swift (+1 move) | **+** Length 6 |
| Siphon *(starter)* | 2 | hex within 4 | basic follow-up | Strips the hex; heals you 4% per step | **+** 6% per step, to an ally on the hex (else you) |
| Bolt | 1 | foe within 4 | 10 | +20% if its hex already carries the element you cast | — |
| Transfer | 3 | a charged hex within 4 | basic follow-up | Lifts the whole charge or marker onto an empty hex within 4 (automatic: under a foe if it hurts, under the most hurt ally if it helps); the tile becomes yours | **+** Spreads onto the destination and its ring |
| Inversion | 3 | a charged hex within 4 | basic follow-up | Flips the axes (fire 3 ↔ water 3, dark ↔ light); fuse ↔ gale; stasis and glaze stay | **+** The hex and its ring flip |
| Aegis | 4 | an ally within 4 (not you) | — | −20% damage taken until the end of its next turn | — |
| Tempest | once | hex within 4, radius 2 | 9 each | Paints all 19 hexes | — |

## Daggers — speed, angles, finishing

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Consume *(starter)* | 2 | adjacent foe on your element | 14 + 2/point | Eats the tile; heals 5% per point eaten | **+** 7% per point |
| Daggerleap *(starter)* | 2 | leap 3 (or any tile with the element) | 8 to the ring | Foes you land behind take +50%. **High ground (D362):** onto a hex 1+ level below, reach 4 and the landing ring radius 2 | **+** Backstab +75% |
| Dualthrow *(starter)* | 2 | foe within 4 | 9, then the Second Dagger | Lays the trail; the Second Dagger bounces to a foe within 2 at 75% | **+** Bounces twice: 75%, then 50% |
| Tumble | 1 | self, free | — | After you attack this turn, +2 move (set before: waits for the attack) | — |
| Manipulate *(drafted as Twist the Knife)* | 2 | adjacent foe | 9 | +10% per status on it, +10% if it stands on charge, up to +60% | — |
| Hamstring | 3 | adjacent foe | 8 | Pinned (−2 move), secondary | — |
| Fan of Knives | 3 | ring around you | 8 each | Paints the ring · clip `spin` | — |
| Assassinate | once | adjacent foe, from behind only | 12 | Can't glance, +25 crit, backstab +50% | — |

## Pistols — rounds, tempo, close range

| Skill | cd | Shape | Power | Hook | Improve rider |
|---|---|---|---|---|---|
| Reload *(starter)* | — | self | — | Seat a round: readies Quick Shot, the next shot lays a trail; your own element +10% | **+** Seats two rounds (two trailed shots) |
| Quick Shot *(starter)* | — | foe in range, free | basic | Once per reload; twice if you haven't moved | **+** Three times if unmoved |
| Point Blank | 2 | adjacent foe | 13 | +20%, and it's shoved back 1 (no slam). Plain lead | — |
| Pistol Whip | 2 | adjacent foe | 9 | Staggered; Quick Shot ready again · clip `pistol_whip` | — |
| Flash Round | 3 | foe within 5 | 8 | Blinded; lays the seated round's trail | — |
| Covering Fire | 3 | self (uses the action), radius 3 | — | Overwatch: the first foe to attack an ally within 3 before your next turn draws your basic shot | — |
| Empty the Chamber | once | self: up to 4 foes within 5 | 12 at 35% a shot | 4 shots, nearest first, spare shots go round again; each rolled; the seated round trails every shot | — |

## Fists — combos, shoves, pouring

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
- **Guards** (Phalanx, Aegis, Brace) ride the FX `guard` (a labelled `dmg`
  forecast modifier). The strongest holds; they don't stack. A guard drops
  when its holder's turn starts; Aegis puts its own back up for that turn and
  takes it down at that turn's end.
- **Timed effects** (War Cry's STR, Riposte+'s second guard, Tumble's wait,
  Reload+'s spare round, Phalanx's no-displace) listen to `BWBattle.event`.
- **Displacement**: shoves and slams share Guardrush's helpers (the Charge
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
attacks) and Vault (its strike's forecast from the landing). Free guards set
last in its turn: Riposte (a foe within 3), Brace (within 2), Set Spear (a
foe that could walk into reach). It never uses War Cry, Phalanx, Covering
Fire, Aegis, Tumble, Transfer, Inversion, Ley Line or Siphon.

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
