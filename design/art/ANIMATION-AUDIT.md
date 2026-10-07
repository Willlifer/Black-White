# Animation fit audit (D219–D222, 2026-10-06)

The author: "do a sweep and discern if there's any actions with animations
that don't fit the actions." Every action that plays a clip was checked: the
62 skills, basic attacks per weapon style, counters, reactions, statuses,
wards, encounter units, and the downtime hall.

Method: `tools/anim_audit.gd` (headless) uses every skill on a flat board
and prints the events the battle emits and the clip the combat screen
plays (`BWClipRoute`, the same routing the cutscene uses). "Current" is the
routing before this pass. Tests: `tests/test_anim_routes.gd` (every def's
clip resolves in each style of its class, the routing rules, the encounter
setup). Review sheets: `design/art/anim2_*.png`.

**Summary:** 41 mismatches. Of the 62 skills, 25 didn't fit and 8 only
half fit (~); outside the skills, 8 more (Staggered, Blinded, the four
encounter kinds with no motion of their own, the hall's fallback poses, and
the fists' small jab). **37 fixed** with 13 new clips, 4 re-routes to
existing clips and 5 routing rules; **4 left** as ~ with a reason (Empty the
Chamber, Fan of Knives, Haymaker, the fists' jab: L-13).

## Skills

| Skill (class) | Current clip | Fits? | Fix |
|---|---|---|---|
| Aegis (staff) | channel 0.35 s | ~ (no aim) | Faces the ally, channel, then a cast at it |
| Aimed Shot (bow) | shot_aimed | yes | — |
| Arcing Shot (bow) | shot_sky | yes | — |
| Assassinate (daggers) | pair strike | yes | — |
| Bolt (staff) | channel > cast | yes | — |
| **Brace** (fists) | channel (circling hand) | **no**: a self-guard played a cast gesture | `brace`: step out, low wide stance, high guard set |
| **Charge** (axe) | the whole strike during the slide, then the strike again | **no** (double swing) | Rides in on the strike's held coil; the cutscene releases it. An empty Charge no longer channels |
| **Cleave** (axe) | strike_axe (overhead chop) | **no**: a 3-tile sweep | `cut`: the diagonal cut |
| Consume (daggers) | pair strike | yes | — |
| **Covering Fire** (pistols) | channel | **no**: overwatch played a cast | `aim`: the shot's cupped aim on the line, held |
| **Daggerleap** (daggers) | strike's coil in the air, KO kneel on landing | **no**: a hit reaction as a landing | `leap`: crouch, spring, tucked, three-point landing |
| **Dragoon Dive** (lance) | windup, strike, KO kneel | **no** (landing) | Lands on the `leap` clip's landing |
| **Dualthrow** (daggers) | pair melee flurry in place, the blade flies on its hit | **no**: ranged skill playing melee | `strike_throw`: overhand throw, blade released on `release` |
| **Second Dagger** (daggers) | same | **no** | `strike_throw_l`: the other hand throws |
| **Earthsplitter** (axe) | free-hand cast at range | **no** | The overhead chop; the bolt runs out on the hit |
| Elemental Truth (sword) | strike | yes | — |
| **Empty the Chamber** (pistols) | one recoil under a 4-tracer sweep | **no** | `strike_chamber` (D389): fanning the hammer, four recoils swept right to left, a tracer on each |
| Energized Shot (bow) | strike (full draw) | yes | — |
| Fan of Knives (daggers) | spin | yes | The spin fits; the knives fly from it since D387 |
| Flash Round (pistols) | pistol shot | yes | (+ Blinded flinch, below) |
| **Flurry** (fists) | 3-punch clip, then a jab per later strike (5 punches) | **no** | Strikes 2–3 land on the clip's `hit2`/`hit3` in one cutscene |
| **Grapple Throw** (fists) | uppercut; the foe then *walks* to its tile | **no**: no grab | `strike_grapple`: reach, seize, heave over, slam; the foe flies on `throw` and lands on a knee |
| **Guardrush** (lance) | free-hand cast at reach 2 | **no** | The thrust; bolt on the hit |
| Hamstring (daggers) | pair low cut | yes | — |
| **Haymaker** (fists) | uppercut | **no** (a hook, not a rising blow) | `strike_haymaker` (D389): long wind-up, full-body hook, follow-through |
| **Heart Seeker** (sword) | forehand cut | **no**: "a precise thrust" | `strike_thrust` |
| **Hook** (axe) | free-hand cast at range 3 | **no** | `strike_hook`: sidearm cast on the line, then two hauls |
| **Hundred Fists** (fists) | the 3-punch flurry, then 5 jab replays | **no** | `strike_hundred`: six blows on `hit`..`hit6`, one cutscene |
| Inversion (staff) | channel 0.35 s | ~ (no aim) | Faces the tile, channel, cast at it |
| Ley Line (staff) | channel + line VFX | yes | — |
| **Lunge** (sword) | the cut during the dash, then the cut | **no** (double swing, a cut for a lunge) | Coil held on the dash, `strike_thrust` |
| Manipulate (daggers) | pair strike | yes | — |
| Palm Burst (fists) | strike_palm | yes | — |
| **Phalanx** (lance) | channel (the def's `block` was ignored by the setup beat) | **no**: not defensive | `brace`: the shaft levelled low, butt back, set |
| Pinning Shot (bow) | strike (draw) | yes | (Pinned: the arrow at the feet) |
| Pistol Whip (pistols) | strike_pistol_whip | yes | (+ Staggered stumble) |
| Point Blank (pistols) | pistol shot | yes | — |
| Quick Shot (pistols) | pistol shot | yes | — |
| Rain of Arrows (bow) | shot_volley | yes | — |
| Reckless Swing (axe) | strike_axe | yes | — |
| **Reload** (pistols) | channel | **no** | `reload`: the pistol's chamber check (handling clip) |
| Retreating Shot (bow) | shot_quick | yes | — |
| **Riposte** (sword) | channel | **no** | `brace` (the answer is the class strike, as before) |
| Saturate (staff) | channel > cast | yes | — |
| **Set Spear** (lance) | channel | **no** | `brace` (lances: the set spear) |
| **Shockwave Palm** (fists) | strike_palm adjacent; free-hand cast at reach | ~ | The palm strike at any reach; the shockwave bolt on the hit |
| Siphon (staff) | channel + draw VFX | yes | — |
| Split Arrow (bow) | shot_fan | yes | — |
| Striketwice / Second Cut (sword) | strike, strike | yes | (+ Staggered stumble) |
| Sunder (axe) | strike_axe | yes | — |
| Surge (staff) | channel > cast | yes | — |
| **Sweep** (lance) | the polearm thrust | **no**: a 3-tile sweep | `strike_sweep`: level swing across the front |
| Tempest (staff) | channel > cast | yes | — |
| Transfer (staff) | channel 0.35 s | ~ (no aim) | Faces the tile, channel, cast at it |
| **Tridentpierce** (lance) | free-hand cast at range 2 | **no** | The thrust; bolt on the hit |
| Triumph (sword) | strike, held gleam | yes | — |
| **Tumble** (daggers) | channel | **no** | `tumble`: the dodge hop and back |
| Uppercut (fists) | strike_uppercut | yes | — |
| **Vault** (lance) | strike's coil, KO kneel; then a channel on landing | **no** | `leap`, no channel (its strike follows) |
| **War Cry** (axe) | channel (the def's `cheer` was ignored) | **no**: no shout | `war_cry`: the rage's hunch and roar |
| Whirlwind Blade (sword) | strike_spin; flamberge: the plain cut | ~ (flamberge) | A flamberge spin (`strike_spin` in the heavy set) |

(Tridentpierce, Earthsplitter, Guardrush, Hook, Shockwave Palm, Transfer,
Inversion and Aegis are the ones named in the request; all are covered above.)

## Everything else

| Action | Current clip | Fits? | Fix |
|---|---|---|---|
| Basic attack: one, heavy, polearm, spear, staff, pair, bow, pistol | the style's strike / cast / shot | yes | — |
| Basic attack: fists | the jab | yes | D389: a wider arc, longer reach, a deeper lunge, an impact star |
| Second weapon swap | holster and draw (D191) | yes | — |
| Counters, Riposte answers, overwatch shots | the class strike / shot | yes | — |
| Reactions (dodge, block, fumble, kneel, five hit variants, fall) | BWReactionPick | yes | — |
| Knockback / push / pull / shove | slide on the plain hit | yes | — |
| **Staggered** | glyph only | **no** | The stumble as it lands |
| **Blinded** | glyph only | **no** | The flinch (forearm up by the face) |
| Pinned | the arrow at the feet + the blow's reaction | yes | — |
| Frost Ward, Aegis ward | ward shell / channel | yes | (Aegis: aimed cast, above) |
| **Horde** | the roster clips | **no own motion** | Hunched shuffle, own paces, a quick jab (D220) |
| **Colossus** | the polearm clips at 2.6x, run at a human cadence, a bolt for its thrust | **no** | Heavy walk with shakes, stomp, the committed line thrust (D219) |
| **Blanks** | the roster clips (bouncy) | **no** | Still guard, synced head snaps, legs-only walk (D220) |
| **Elemental Beings** | standing, stepping, melee strikes | **no** | Hover, glide, flicker, cast attacks (D220) |
| Hall: Specialize, recruit walk-ins, Wander | windup/strike/cast, walk | yes | — |
| **Hall: Branch out** reaction, jackpot | "stricken", "idle_look", "cheer_cool" fell back to idle | **no** | A clip's own name is a pose now (D222) |
| Hall holds and handling (D80) | holds / actions | yes | — |

## Counting

- Skills: 62 (Striketwice and its Second Cut share a row): 25 **no**, 8 ~, 29 yes.
  All 25 fixed; 5 of the 8 ~ fixed (Shockwave Palm, Whirlwind on a
  flamberge, Aegis, Inversion, Transfer); 3 left (reasons in the table).
- Other actions: 7 **no** (Staggered, Blinded, Horde, Colossus, Blanks,
  Beings, the hall's poses), all fixed; 1 ~ left (the fists' jab, L-13).

## What to look at

| File | Shows |
|---|---|
| `anim2_colossus_walk.png` | walk_colossus 3 hexes (side, 3/4), then the stomp |
| `anim2_colossus_thrust.png` | the coil hold, the lunge through three grunts, the held follow-through |
| `anim2_being.png` | three Beings hovering (flicker), a glide, the cast |
| `anim2_horde.png` | ten grunts starting one move together: out of step |
| `anim2_blank.png` | a Blank walking beside Stryker; standing head snaps |
| `anim2_jab.png` | the Horde jab against the class strike |
| `anim2_polearm_brace.png`, `anim2_fists_brace.png` | Set Spear / Phalanx, Brace |
| `anim2_pair_leap.png` | the leap |
| `anim2_one_strike_thrust.png`, `anim2_polearm_strike_sweep.png`, `anim2_pair_strike_throw.png`, `anim2_one_strike_hook.png`, `anim2_fists_strike_grapple.png`, `anim2_fists_strike_hundred.png` | the new skill strikes |

Known limits: the Blanks' faces are blank, so their head turns read mostly
through the tilt and the chest; the chibi arms keep the grapple's reach short
(the toss of the foe carries the throw); the leap is a jump for Vault too
(no pole plant).
