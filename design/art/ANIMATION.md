# Animation (Phase 4: the clip matrix)

> **Names (D379, L-10):** this doc predates the D149 rename, so some examples
> name pre-D149 characters (Pip, Hugo, Kyla). Since D379 those are members of
> the rolling roster pool (design/ROSTER.md), so the names still exist in the
> game; their quoted taglines are gone (D153), and their kits are rolled now,
> not the ones described here.

The style bar (Alexandra: idle, walk, strike, stricken) was approved at
Gate 4 (D62). This phase builds the full matrix to the same standard:
**every weapon style has a clip for every pose**, and the combat cutscene,
the moves and the reactions run on the clips' markers. Static key poses
remain only as a safety fallback.

| File | What | Edit? |
|---|---|---|
| `game/src/game/character/anim_clips.gd` | `BWAnimClips`: the core. Clip builder, curves, the rolling foot, gait and footstep feet, bake passes, sets, `actions_for`, `personality`, and the four approved style-bar clips (heavy idle, walk, strike, stricken) | **yes, source** |
| `.../anim_carry.gd` | `BWAnimCarry`: per-style hand data. Which hand holds the weapon, the guard corrections, the locomotion carries, static-key hand holds | **yes, source** |
| `.../anim_idle.gd` | `BWAnimIdle`: idle, idle_bouncy, idle_fidget, idle_weapon, idle_look, wounded, cheer, cheer_jump, cheer_cool | **yes, source** |
| `.../anim_loco.gd` | `BWAnimLoco`: walk, walk_calm, walk_heavy, run, run_heavy, run_start, run_stop(_r), limp, turn_l/_r | **yes, source** |
| `.../anim_action.gd` | `BWAnimAction`: strike (per style), strike_axe, cast, channel | **yes, source** |
| `.../anim_react.gd` | `BWAnimReact`: stricken, block, fumble, dodge, kneel, fall | **yes, source** |
| `.../anim_stricken.gd` | `BWAnimStricken`: the five hit variants (flinch, shrug, stumble, knockback, rage) per style | **yes, source** |
| `.../anim_handling.gd` | `BWAnimHandling`: weapon handling (D80): holds, their transitions, the handling actions, per style | **yes, source** |
| `.../anim_skill.gd` | `BWAnimSkill` (D221): brace, leap, strike_thrust / _sweep / _throw(_l) / _hook / _grapple / _hundred, and the skill pose routes (war_cry, aim, reload, tumble, land) | **yes, source** |
| `.../anim_alt.gd` | `BWAnimAlt` (D510-D519): the alternate clips (smash, smash_flip, sweep_under, throw_under, thrust_2h, lunge, flourish, backstab, shot_jump, cast_tempest) and their pose routes | **yes, source** |
| `game/src/game/combat/backstab.gd` | `BWBackstab` (D517): the backstab's S-curve slither round to the target's back and home (view only) | yes |
| `.../anim_encounter.gd` | `BWAnimEncounter` (D219-D220): walk_colossus, stomp_colossus, strike_colossus, the Horde's jab; the runtime layer is `BWAnimator._encounter_layer` | **yes, source** |
| `game/src/game/combat/clip_route.gd` | `BWClipRoute` (D221): which clip an action plays (cast vs strike, setup poses, multi-blow clips, status poses); D510: the alternates table and `pick()`; `tools/anim_audit.gd` prints the table | yes |
| `game/src/game/combat/reaction_pick.gd` | `BWReactionPick`: which reaction a blow gets (the table below) | yes |
| `game/src/game/combat/projectile_flight.gd` | `BWProjectileFlight`: arrow / bullet / bolt in flight, stick, muzzle flash | yes |
| `game/tools/build_anims.gd` | bakes every set to `art/animations/<style>.res` (9 sets incl. fists, about 400 ms each) | yes |
| `game/art/animations/<style>.res` | the baked `AnimationLibrary` per style | generated, don't hand-edit |
| `.../animator.gd` | `BWAnimator`: state machine, personality, idle rotation, move planning, turns, blending, foot lock, inertia, hair, smear | yes |
| `.../character_pose.gd` | solver; `frame_of()` (frame transforms for blends), weapon floor clearance | yes |
| `.../character.gd` | builds the animator for every weapon; root motion; authored turns drive the rig yaw | yes |
| `game/shaders/smear.gdshader` | the smear crescent | yes |
| `game/src/game/combat/unit_view.gd`, `combat_screen.gd` | integration (below) | yes |
| `game/tests/test_animation.gd` | 14 tests (below) | yes |
| `game/tools/anim_preview.gd`, `anim_gif.py` | contact sheets, review strips, lineup GIFs, showcases | yes |

## Rebuild and review

```
godot --headless --path game -s res://tools/build_anims.gd            # bake all 8 sets
godot --headless --path game --import
godot --headless --path game -- --self-test                           # test_animation checks the bakes are current
godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only sheets [--style s]
godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only strip --style s --clip c [--out dir]
godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only gifs [--clip c] --frames <dir>
godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only showcase [--style s] --frames <dir>
godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only stricken [--style one] --frames <dir>   # variants GIF + strip
godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only shots --frames <dir>       # bow / pistol GIFs + projectiles.png
godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only idle_calm --frames <dir>   # D65 idle review
godot --path game --resolution 1600x900 -s res://tools/anim_preview.gd -- --only handling [--style s] --frames <dir>   # D80 handling
godot --path game --resolution 1280x720 -- --screen roster --shot <dir> --every 0.0667 --count 330   # the roster, live (anim_roster_idles)
python game/tools/anim_gif.py <frames dir> design/art 30 0.75      # lineups (0.8 for showcases)
```

## Pipeline

The approved pipeline is unchanged. Clips are keyed in **pose space** in
GDScript and baked to an `AnimationLibrary` of 33 value tracks
(`pose:<channel>`, 60 Hz, linear). `BWAnimator` samples them and the
solver writes the bones, so feet stay planted, fists stay on grips, and
skirts narrow stances in every clip. Authoring is per channel with
`key(ch, f, v, mode)` and `pose(f, {...})`. The modes are `a` (Catmull-Rom),
`f` (flat), `l` (linear) and `s` (stepped). See the header of
`anim_clips.gd`.

**Channels added for the matrix:**
- `hand_l_aim` and `hand_l_edge`: the bow's left hand and the second dagger.
- `hand_r_grip`: the bow string hand.
- `turn`: the turn-in-place progress.
- `plant` (D80): 0..1, ground the weapon (the solver tilts it onto the floor).

**One library per weapon style**, which is the `BWCharacterPose.style_for`
key: one, heavy, polearm, spear, staff, pair, bow, pistol, fists. Every weapon of a
style shares the clips, and the solver puts the fists on each weapon's own
grip. Class variants live inside a set and are chosen by
`BWAnimClips.actions_for(set, class)`:
- the `axe` class in `one` and `heavy` uses `strike_axe`.
- the heavy axes also use `walk_heavy` and `run_heavy`.

**fists: static fallback, clips pending (D76).** The `fists` style (class
`fists`: hand_wraps, brass_knuckles, gauntlets) has **no clip set yet**:
`BWAnimClips.set_for` returns "" for it, so `BWCharacter.animator` is null
and every pose plays the static key from `BWCharacterPose` (style `fists`,
chain `fists -> default`). `hold_hand` is `both`, like `pair`: both hands
are weapon hands, each on its own socket (the left wears the mirrored piece).
Keys are written with `BWCharacterPose._fist(side, pos, punch, back, pole)`:
`punch` is where the knuckles drive, `back` where the back of the hand
faces; it solves the socket aim/edge from `FIST_KNUCKLE_R` / `FIST_BACK_R`
(the hand's rest axes in socket space, shared with `build_weapons.py
fist_frame()`). The standard pose names are all authored:

| pose | fists key |
|---|---|
| idle | boxer's guard, fists up at the shoulders, left leads |
| windup | rear fist cocked at the jaw |
| strike | the cross: right arm long, palm down; left fist back at the chin |
| cast | Palm Burst: heel of the right hand driven out, fingers up |
| hit | guard knocked back into the face |
| kneel | on a knee, right fist on the thigh, left still up |
| dodge | slipping, guard tight |
| block | high guard, forearms up, knuckles to the sky |
| fumble | guard blown open |
| fall | arms flung out |
| cheer | right fist pumped to the sky |

For the animation lane: add `fists` to `SETS`, give `BWAnimCarry` its hands
(`weapon_hand` "both", `free_hand` "", the guard from the idle key above),
and author the clips with the standard names; the static keys stay the hold
layer. Skills that want their own beats: Flurry (3 strikes; strikes 2-3
arrive as `attack` events with `strike`/`strikes`), Uppercut (rising blow,
then a `knockback` move and maybe a `slam` event), Palm Burst (the cast key).

**How the matrix is authored without 200 hand-made clips:**
- Bodies and feet are shared choreography, keyed once. Hands come per style
  from `BWAnimCarry` (carries, guards) or from the reviewed static keys
  (`key_hands`: block, kneel, fall, ...).
- Melee strikes reuse the approved flamberge strike's body and feet:
  - The beats are **retimed** per style through its beat table.
  - The twist is scaled (thrusts twist less than cuts).
  - Each style keys its own root-frame hands.
- Gaits are procedural feet (`gait_foot`, periodic) or **footstep plans**
  (`plant_foot`, one-shots). A planted foot's ground point is fixed in the
  world against an authored root curve, so starts and stops have real,
  non-sliding steps.
- One-shots start and end on the set's guard (`at_base`). The documented
  exceptions are below.

## Clip table (every set has every row)

Frames are at 24 fps. Markers are seconds in `meta.bw.markers` and Animation
markers. `pose` is meta only.

| Clip | Frames | Loop | Markers | What |
|---|---|---|---|---|
| `idle` | 60 | yes | | Home idle. The heavy set keeps the **approved clip**: the same keys, with its aims re-expressed relative to the new guard (below). Other sets use the same body (two weight shifts against two breaths, the look-off) and their own weapon "hup" |
| `idle_bouncy` | 16 | yes | | Up on the toes, two bounces. **Retired as a home idle (D65)**; kept in the library, played by no one |
| `idle_fidget` | 48 | no | | Variant: sinks onto a hip, the right foot shuffles out and back, a shoulder roll, a neck stretch, a shake-out |
| `idle_weapon` | 54 | no | | Variant, per style. **one:** wrist twirl, then sights along the edge. **heavy:** heave onto the shoulder and two bounces. **polearm:** blade check, the shaft turned in the fingers. **spear:** sights a throw, then tips it back up (D520: a flip put the 2.6 m lance through the floor). **staff:** overhead spin, 1.5 turns. **pair:** both daggers flipped, then a cross-guard. **bow:** two string plucks, head cocked. **pistol:** two spins on the finger, then a muzzle check |
| `idle_look` | 56 | no | | Variant: up on the toes with a visor hand, looks off left, sweeps right (chest 40%, hips 15%), down with a squash |
| `wounded` | 40 | yes | | Idle below 35% HP: hunched over the right side, the right heel up, hand pressed to the side, hard breathing, a wince on f26 |
| `walk` | 16 | yes | | 1 hex per cycle (2.598 u/s). Heavy keeps the approved clip; others carry their own weapon |
| `walk_calm` | 16 | yes | | Half the bounce, less twist, upright. Stoic and dreamy characters; velocity-matched swing |
| `walk_heavy` | 20 | yes | | Heavy axes: shouldered in both fists, stance 0.58, lower and heavier, the chest 2 f behind the hips (2.078 u/s) |
| `run` | 10 | yes | | **1 hex per cycle in 0.417 s (4.157 u/s, D62).** Stance 0.36 (a flight phase each step), 0.37 rad lean, bent-arm pump, sink on the down, stretch on the push. The weapon is trailed or carried per style |
| `run_heavy` | 10 | yes | | Heavy axes: the run with the weapon shouldered, less bounce and twist |
| `run_start` | 14 | no | (`root_s`) | From a standstill: sink, lean back, throw the weight forward, a short right step, drive off the left. Ends **exactly on run frame 0**. The root accelerates from f3 |
| `run_stop` / `run_stop_r` | 18 | no | (`root_s`, `root_end`) | Entered on the left (frame 0) or right (frame 5) contact. A heel-first braking step, sink and lean back while the head, hair and weapon carry on forward, the back foot steps up, a bob through the guard. The root stops at f9 |
| `limp` | 20 | yes | | Wounded move: the good leg holds 0.62 of the cycle, the hurt right leg 0.38 with a stiff knee; lurch and wince (2.078 u/s) |
| `turn_l` / `turn_r` | 16 | no | | Turn in place: the head leads, the hips and chest follow, the turning-side foot steps first. `turn` (0..1, with a 3% overshoot) drives the rig's yaw |
| `strike` | 30–42 | no | melee: coil, launch, land, **hit**, hop_start, hop_end, recovered; bow and pistol: coil, **release**, **hit**, recovered | Per style, below |
| `strike_axe` | 36 / 46 | no | as melee | one and heavy, axe class: overhead chop. The heavy version waits longer in the coil and lands lower |
| `cast` | 36 | no | coil 9, **release** 12, **hit** 13, recovered 30 | Staff spells and elemental skills. **Staff:** raised high at the right, laid back, then thrust at the target. **Others:** the free hand gathers at the chest and thrusts open, and the weapon is drawn back. The left foot steps out on the release |
| `channel` | 24 | yes | | The cast's coil held alive: a breath, the casting hand (staff head) circling twice. Frame 0 = cast@coil exactly |
| `stricken` | 32 | no | **impact** 0, catch 8, recovered 24 | Clean hit. Heavy keeps the approved clip; others share its body (shove, step back, annoyed head-shake) with their own hands. Now the plain "hit" of the **cocky** only (below) |
| `stricken_flinch` | 16 | no | **impact** 0, catch 5, recovered 12 | Mild and quick: head turns away and ducks, chest twists off, the free forearm snaps up by the face, a heel peel, up again with a small overshoot |
| `stricken_shrug` | 30 | no | **impact** 0, catch 5, recovered 25 | Takes it (a short step back), looks down at the spot, a palm-up shrug with the shoulders up, dusts it off and flicks it away, a neck roll, chin up |
| `stricken_stumble` | 44 | no | **impact** 0, catch 18, recovered 38 | Nearly falls: right foot back, left foot back onto the heel, teeters toes-up with the free arm windmilling forward twice (the weapon held out at the side), lunges forward onto the left foot to catch it, steadies hunched, walks back in |
| `stricken_knockback` | 48 | no | **impact** 0, slide_end 12, catch 14, recovered 42 | The big one: thrown back half a hex (`meta.travel` 0.84) and **skids** on both feet (contacts forced off f0.5-12.5, so the foot lock lets the soles slide), braking low with the front toes up; a glare; three steps home. The unit's root never moves |
| `stricken_rage` | 52 | no | **impact** 0, catch 8, **shout** 16, recovered 46 | Takes it, hunches and fumes (a tremble on ones), then rears up into the shout: up on the toes, chest out, head back, arms flared down and behind (style-specific flare aims), a shake through the hold, comes down glaring and steps back in |
| `block` | 26 | no | **impact** 4, recovered 20 | Glance or resist: a 1 f dip, the static block key snapped up, shoved back a step with the hands riding the chest, hit-stop, push back, lower |
| `fumble` | 34 | no | **impact** 3, catch 10, recovered 27 | A cutscene's normal hit: the block comes up late and is knocked wide (the static fumble key), spin, stagger step, re-grip |
| `dodge` | 30 | no | launch 2, **impact** 5, land 6, hop_start 16, hop_end 19, recovered 25 | A miss: a dip, a hop away (the game moves the root by `meta.shift` on launch..land), a crouch, a cocky head tilt, a hop home |
| `kneel` | 46 | no | **impact** 0, down 8, rise 28, recovered 40 | Crit or KO blow: recoil, the knees go, the right knee down on f8, two heavy breaths, pushes up off the front foot |
| `fall` | 40 | no, **held** | **impact** 0, **grounded** 16, still 26 | KO: catch step back, stagger, knees go, onto the seat, then the back; the legs kick, a bounce, the head lolls. `hold_end`: it stays on the floor |
| `cheer` | 24 | yes | | Victory: the weapon hoisted (the static cheer key), pumping on the toes, chin up |
| `cheer_jump` | 20 | yes | | Victory: crouch, a jump with a fist pump (both feet off f5–f11), a squash landing |
| `cheer_cool` | 48 | yes | | Victory: the weapon on the shoulder (style equivalent), hand on the hip, two slow nods |

**Strikes per style.** Melee timings are retimed from the approved
flamberge strike.

| Set (weapons) | Strike | Frames | coil / launch / land / hit | engage |
|---|---|---|---|---|
| one (sword, scimitar) | one-handed forehand cut, high right to low left; the free arm reaches in the coil and is flung back | 36 | 7 / 9 / 11 / 12 | 1.0 |
| one, axe class (hatchet) | `strike_axe`: one-handed overhead chop, the free hand countering | 36 | 7 / 9 / 11 / 12 | 1.05 |
| heavy (flamberge) | the **approved** two-handed diagonal cut | 40 | 8 / 10 / 13 / 14 | 1.2 |
| heavy, axe class (double axe, warhammer, anchor) | `strike_axe`: big overhead chop, long held coil, low landing | 46 | 12 / 14 / 17 / 18 | 1.25 |
| polearm (halberd, glaive, naginata: two hands, a forearm guard) | two-handed thrust: the shaft drops level on the line (head leads), drawn to the rear hip, driven straight in, a quarter twist on the hit | 42 | 9 / 11 / 14 / 15 | 1.6 |
| spear (lance, javelin, trident: one hand + shield, D520) | overhand stab from the shoulder; the shield arm holds its guard | 35 | 7 / 9 / 11 / 12 | 1.5 |
| staff (staff, moon staff) | melee: both hands, over the top and down on the target | 42 | 9 / 11 / 14 / 15 | 1.4 |
| pair (daggers) | low flurry: right cross-cut on `hit`, left stab on `hit2` (f17.5) | 32 | 5 / 7 / 9 / 10 | 0.9 |
| bow | **D164, `anim_bow.gd`**: side-on step; nock (the string hand meets the string); push-pull draw (bow arm extends, the string hand pulls along the arrow to the anchor under the jaw, shoulders open, legs sink; the string bends to the hand in two segments); coil; **release** 14: the hand flies back past the ear, the bow rolls forward in the open hand, recoil; follow-through held. Skill variants: `shot_quick` (Retreating, no hold), `shot_aimed` (long hold with an aim tremble that settles on a breath), `shot_sky` (Arcing, 50 deg, leaning back), `shot_volley` (Rain: 4 arrows, release..release4), `shot_fan` (Split: bow canted, 3 arrows) | 36 | nock 6, coil 12, release 14, hit 15 | - |
| pistol | half side-on, two-handed cup grip on the line (coil 8), **release** 9: muzzle kicks up and back, chest and head snap back with a squash, ridden down onto the line, a smug hold | 30 | coil 8, release 9, hit 10 | - |

## State machine

```
           idle (home loop: idle | idle_bouncy, per personality, at its rate)
            |  every 4-14 s standing (seeded per character): a variant one-shot
            |  (idle_weapon | idle_look | idle_fidget, in its own order) -> back to idle
            |  a snap of the view's yaw > 0.5 rad while standing: turn_l | turn_r
            v
  run --(from a standstill)--> run_start --(f14, run frame 0)--> run (rate: plan) --run_stop--> run_stop | run_stop_r -> idle
  walk (1 hex, careful) <-> idle                              (the stop picks the foot that is down)
  windup = strike held at coil --strike--> strike continues -> idle
  channel (loop) --cast--> cast from its coil -> idle
  any --hit | fumble | block | dodge | kneel | stricken_*--> reaction -> idle
       ("hit" = the character's own stricken; the cutscene names a variant)
  any --fall--> fall, HELD on the floor
  wounded (HP < 35%): idle -> wounded, walk | run -> limp (no start / stop)
  any other pose name: the static key pose (the safety fallback)
```

- `idle()` during a one-shot is deferred: one-shots end on the guard.
  Variants are one-shots but **never block**: `is_busy()` is false and any
  request cuts in.
- **Blends** use `BWAnimator.BLENDS` (from>to, with wildcards) and the gap
  rule: never faster than 2.4 u/s of pose difference, capped at 0.35 s.
  - Reactions cut in in 0.05–0.06 s.
  - The start hands to the run in 0.05 s.
  - Variants fade in over 0.3 s.
- **Hands keyed in different frames** (the root frame for aimed actions, the
  chest frame for everything else) are converted into the incoming frame
  **of the mixed body** before mixing. `BWCharacterPose.frame_of` does the
  conversion. Converting into the target's own frame instead made the
  outgoing hand jump by the two chests' difference. The pop test caught it
  at 0.25 u/frame.
- Feet step through blends (lifted arcs, staggered), as in the style bar.

### Idle personality: the picking rule

`BWAnimClips.personality(id, tagline)` is deterministic. It scores the
tagline against five vibes:

| Vibe | Tagline cues |
|---|---|
| bouncy | fast, overconfident, first in, race, loud, happy, waves, shoots first, loves |
| stoic | waste of breath, never flinches, half asleep, disapproves, harder than |
| dreamy | hums, daydream, masterpiece |
| fussy | counts, rulebook, apologizes, dramatic, sneers |
| cocky (the default) | expects to win, says so, never sorry |

Each vibe sets the following:

| Vibe | Home idle | Rate | Rotation interval | Variant order (then rotated by `hash(id)`) | Walk | Cheer |
|---|---|---|---|---|---|---|
| bouncy | `idle_bouncy` | 1.12 | 4–7 s | weapon, fidget, look | walk | cheer_jump |
| stoic | idle | 0.86 | 9–14 s | look, fidget | walk_calm | cheer_cool |
| dreamy | idle | 0.92 | 6–10 s | look, weapon, fidget | walk_calm | by hash |
| fussy | idle | 1.04 | 4.5–8 s | fidget, weapon, look | walk | by hash |
| cocky | idle | 1.00 | 6–10 s | weapon, look, fidget | walk | cheer_cool |

- The rate also varies ±3% by hash, so two units of the same vibe don't
  breathe in sync.
- The variant timer is a RandomNumberGenerator seeded with
  `hash(id + "|idle")`.
- Examples:
  - Pip ("Tiny and fast and wildly overconfident") is bouncy, so `idle_bouncy`.
  - Alexandra ("Expects to win and says so") is cocky, so the reference
    `idle`.
  - Hugo ("Half asleep and never flinches") is stoic.
  - Aureli ("Hums through every fight") is dreamy.

### Hit-reaction variety: the picking rule

The cutscene (`_cutscene`, `_quick_hit`) asks `BWReactionPick.pick(unit,
result, {ko, melee, hp_after, salt})` for every defender. It is
deterministic: the same blow on the same unit picks the same reaction. The
seeded jitter (each weight x 0.75..1.25, seeded by the unit, the damage, the
HP left, the attacker and the strike index) keeps a fight from feeling
scripted. The pick is the highest jittered weight.

| Blow | Base weights |
|---|---|
| miss | dodge |
| KO blow | kneel (the `ko` event's fall follows) |
| resisted | block |
| glance | block 1.0 (melee) / 0.5 (ranged), shrug 0.8, flinch 0.8 |
| small: under 8% of max HP | flinch 1.0, shrug 1.0 |
| mid: 8-22% (s = 0..1 across the band) | fumble 1.0 (melee only), rage 0.45, flinch 0.15 + 0.8(1-s), shrug 0.2 + 0.7(1-s), stumble 0.2 + 0.5s, knockback 0.1 + 0.6s |
| big: a crit or over 22% | knockback 1.0, stumble 0.85, kneel 0.5 (crit only), rage 0.35 |
| HP left under 35% (not glance or KO) | x stumble 2.4, knockback 1.2, flinch 0.5, shrug 0.4, rage 0.8 |

| Temperament | Multipliers |
|---|---|
| unfriendly | rage 2.2, shrug 1.6, flinch 0.6 |
| friendly | flinch 1.4, stumble 1.2, rage 0.25 |
| stoic ("never flinches") | shrug 2.0, flinch 0.3, rage 0.6 |
| cocky | shrug 1.5, rage 1.3 |
| bouncy | flinch 1.6, stumble 1.2 |
| fussy (dramatic) | stumble 1.4, flinch 1.3 |
| dreamy | stumble 1.3, flinch 1.1 |
| small and fast (spd 5+, or "tiny" / "fast" in the tagline) | flinch 1.35, knockback 1.3 |
| heavy (a two-handed sword or axe) | knockback 0.7, shrug 1.3 |

The fumble block and the block keep their old jobs (a normal melee hit and
a glance / resist). The plain `"hit"` pose (shoves, tools, no context) plays
`personality().hit`: cocky `stricken` (the approved head-shake, now only
theirs), stoic `stricken_shrug`, bouncy and fussy `stricken_flinch`, dreamy
`stricken_stumble`.

**For the audio lane:** `BWCombatScreen.reaction_chosen(unit_id, reaction,
info)` fires as each reaction starts (`info` = tier, why, damage, crit,
glance); `BWUnitView.last_reaction` holds it too; and `BWAnimator.marker`
emits `(clip, marker)` with the variant's clip name: `impact` on every
variant, `shout` on the rage, `slide_end` on the knockback, `nock` and
`release` on the bow strike.

Measured in three autoplay fights (early-game damage is mostly 8-17% of max
HP): flinch 47, dodge 31, stumble 24, shrug 18, block 14, kneel 14, fumble
10, rage 8, knockback 1. The knockback belongs to big blows, which are rare
until the later fights.

### Calm idles (D65)

The author: "the most bouncy thing I have ever seen". Every standing clip
(idle, idle_bouncy, idle_fidget, idle_look, idle_weapon, wounded) now bakes
at 22% of its authored motion (`BWAnimIdle.CALM_LOOP` / `CALM_VARIANT`,
`BWAnimClips._pass_calm`). Loops scale about their own average pose, so the
approved idle keeps its posture and shape (chin up, the hip sit, the
"hup"), only small; one-shot variants scale about the guard they start and
end on. Everyone's home idle is `idle`; rates are 0.85-1.0; the variant
intervals roughly doubled (bouncy 8-14 s ... stoic 18-28 s). The authored
keys are unchanged, so the factor is one constant to retune.

### Weapon handling (D80)

The author on the roster: "the weapons seem incredibly stiff. Definitely
have units swap between holding the weapon at their sides, to placing them
over their shoulder, to testing their heft. Admiring them." The D65 calm
was also shrinking the weapon trick (`idle_weapon`) to 22%. Now the **body
stays calm and the weapon moves at full size** (`Clip.calm_hands = false`;
`idle_weapon` is a handling action).

Source: `anim_handling.gd` (`BWAnimHandling`). Scheduler: `BWAnimator`
(`_change_hold`, `_do_action`, `handle()`).

**Holds** (sustained; loop = the calm idle body at the hold's posture, the
weapon resting in the hold; authored `hold_<h>_in` / `hold_<h>_out`):

| Style | side | shoulder | ground | other |
|---|---|---|---|---|
| one | blade down, tip forward | on the right shoulder, free hand on the hip | | |
| heavy | one hand on the hilt, tip resting on the floor (planted) | the shouldered carry, laid back | both fists stacked on the hilt, blade planted ahead (swords only: axes skip it, their mid-haft grip stood the haft end in the face) | |
| polearm, spear, staff | trailed low, head forward-up | at the slope / on the shoulder | staff: butt-down, both hands, leaning in (the arm's reach sets it) | |
| pair | daggers hanging, points down | | | **reverse**: the icepick grip (flip in/out = a 1.5-turn spin, left a beat after right) |
| bow | lowered, top limb tipped forward | slung on the left shoulder | | |
| pistol | arm hanging, muzzle down | laid back on the shoulder, muzzle behind | | |
| fists | hands down, loose | on the hips | | |

**Actions** (one-shots that start and end on their hold, `meta.from/to`):
`act_heft(_side)` (lift, two bounces of the weapon with the tip a frame
late, tilt both ways), `act_admire(_side)` (up beside the face, a half turn
to see both flats, held out level and sighted along, the free hand wipes
it hilt to tip; daggers scrape one on the other), `idle_weapon` (the trick),
`act_settle` (shoulder: lifted off, dropped back, a bounce), `act_lean`
(ground: weight onto it, fingers drum), `act_spin_reverse` (daggers), and
per style `act_sight` (bow: nocks an arrow — `meta.arrow` window, no
release, no twang — half-draws, sights, lets down), `act_check` / `act_blow`
(pistol), `act_twirl` (staff: tilted twirl so the long end clears the floor,
then `meta.sparkle` lights the aura). At the guard, `idle_look` /
`idle_fidget` join the pool as "body".

**Cadence** (`BWAnimClips.handling(vibe)`):

| Vibe | hold change | action | likes |
|---|---|---|---|
| bouncy | 8–13 s | 5–9 s | shoulder, reverse grip, tricks |
| stoic | 14–22 s | 11–18 s | ground, guard, lean |
| dreamy | 10–16 s | 7–12 s | side, admire |
| fussy | 9–15 s | 3.5–7 s | guard, admire, heft |
| cocky | 9–14 s | 6–10 s | shoulder, tricks |

`BWUnitView.showcase = true` (the roster, one line in `roster_screen.gd`)
multiplies hold intervals by 0.5 and action intervals by 0.45.

**Leaving a hold** (any request but `idle`, a turn, going wounded): the hold
resets to the guard and the new layer gets a **hand-only fade**
(`halpha`, 0.24–0.45 s from the hand gap, aim turns counted at 0.45 u/rad)
on top of its normal body blend. Markers and the clip clock are untouched,
so the cutscene's coil / launch / hit timing is the same from any hold; the
hands simply arrive at the strike's own path by the coil (tested: the
dagger's blade matches the strike-alone aim within 0.995 by the coil). A
reversed dagger's way back is this fade: one fast flip to forward. Plant
lets go at 5x the hand rate, before the aim swings far.

**Planting** (`plant` channel, `BWCharacterPose._plant`): the weapon tilts
about the grip, in the plane of its own lean, by the smallest angle (max
0.6 rad) that rests its lowest end on the floor, then nudges the grip
(-2..+12 cm). So the 2 m flamberge and a short hatchet both touch down from
one authored hold.

### Fists (D76, D80)

The full matrix, like every set. `strike` is the **jab** (lead hand, the
twist reversed so the left shoulder turns in). Skills as their own clips
with melee markers: `strike_flurry` (left, right, left: `hit`, `hit2`,
`hit3`, the chest rocking into each), `strike_uppercut` (sinks, drives up
through the toes, `leg_stretch`), `strike_palm` (heel of the hand at chest
height), plus `cast` = the palm burst as a cast (`release`) and `channel`.
Run: fists pumping close; walk: a bobbing guard; the trick shadowboxes and
tugs the wraps; cheer_cool: fists on hips. Reactions damp the weapon-hand
offsets (the guard is already at the chin, near full reach) and blend in
over >= 0.18 s. Pose names `flurry` / `uppercut` / `palm_burst` (and
`windup_<skill>`) exist; **`BWUnitView.skill = <skill key or name>`** makes
the next `windup` / `strike` play them. **Pending (combat lane):** one line
in `combat_screen._cutscene`, e.g. `a.skill = skill_name` before the
windup; until then fists skills play the jab.

### Skill clips: spin and pistol whip (D102)

A skill def's `clip` ("spin", "pistol_whip") reaches the rig through
`BWUnitView.skill`: the cutscene sets it before the windup, and
`windup` / `strike` play `windup_<clip>` / `<clip>` when the set has them
(`BWAnimClips.actions_for`), else the class strike. Both carry the melee
markers (coil, launch, land, hit, hop_start, hop_end, recovered), no
`release`, so the cutscene dashes and hops them like any strike.

| Clip | Sets | Frames | coil / launch / land / hit | What |
|---|---|---|---|---|
| `strike_spin` | one, pair | 40 | 9 / 11 / 18 / 19 | A leaping 360° cut. Sinks and winds right (blade back-right, head on the target), compresses, leaves both feet and turns a full circle counter-clockwise with the blade held out flat (the smear draws the arc), the head spotting ahead; lands on f18 skidding through the last of the turn, the arm whips the blade across the front on the hit; hit-stop, chest overshoot left, follow-through low-left, hop home. Daggers: the left blade rides the opposite side |
| `strike_pistol_whip` | pistol | 32 | 7 / 9 / 11 / 12 | Close backhand with the butt: the gun comes up and flips butt-first by the left shoulder (chest wound left), hop in, a backhanded clubbing arc high-left to front-right with the butt leading, the gun rebounds off the blow (f15) and carries on low right, flipped back to a low aim, hop home |

**The whole-body turn.** Pose space can't turn the body a full circle (the
legs would wind up), so the spin stores its turn as a curve in the clip's
meta (`spin_yaw`, radians CCW from above, at `spin_hz` = 60 Hz).
`BWAnimator.spin_yaw()` reads it at the layer's own time (the topmost layer
with one; a spin covered mid-turn fades its yaw with that layer's weight),
and `BWCharacter._track_motion` adds it to the rig's yaw. The curve is 0
until launch and exactly TAU from the hit on, so the feet are only ever
turned while airborne or skidding (`skid` 17-19.5 forces the contacts off
while the landing pivots), the foot lock never twists, and the hand-over to
the next clip (TAU → 0) is invisible. Anything that samples the clip
without `BWCharacter` (tests, `_sample`) sees the un-turned pose.
`test_skill_clips` checks the markers, the curve (0 → TAU, monotonic), the
hook and the fallback. Review: `design/art/present_spin_one.png`,
`present_spin_pair.png`, `present_pistol_whip.png`.

### Move planning (D62)

`BWAnimator.plan_move(distance, hexes)`, reached as `BWUnitView.plan_move`,
returns the gait, the duration, `stop_at` and `s(t)` (the distance along the
path).

- **2+ hexes: run.**
  - The root follows the start's authored root curve, cruises at the run
    speed, then follows the stop's root curve. The start's and stop's feet
    were planted against those curves, so they don't slide.
  - The run's rate is set so that a whole number of steps fits the cruise,
    so the stop begins on a contact. The foot lock absorbs the 5–10% stride
    mismatch (the author accepts some slide, D62).
  - Measured: 2 hexes in 1.4 s (0.69 s/hex), 3 hexes in 1.8 s (0.60 s/hex),
    8 hexes at 0.48 s/hex (approaching the run's 0.42).
- **1 hex: walk**, on the style bar's trapezoid.
- **HP < 35%: limp**, on the trapezoid at the limp's speed.

## Integration (the `BWUnitView` public API is unchanged; additions only)

**Additions:**
- pose names `walk`, `run`, `run_stop`, `channel` (through `pose_named`)
- `plan_move`, `begin_move`, `lead_to_impact(pose)`, `clip_meta_of(pose)`,
  `weapon_tip()`
- `refresh()` now also sets wounded (below 35% HP)
- the channel pose lights the aura

**Moves** (`combat_screen._animate_walk`): every unit has clips now, so
every move follows the plan. The tween follows `s(t)` along the path and
requests `run_stop` at `stop_at`. Corners still turn on the rig's s-curve.

**Cutscene** (`_cutscene`):
- **Cast:** staff spells, and elemental skills used at range. Skills
  channel for 0.55 s first. The bolt launches from `weapon_tip()` on
  `release`.
- **Strike:** windup held to coil + 0.1 s, then strike.
  - Melee dashes on launch..land and hops home on hop_start..hop_end.
  - Bows and pistols fire on `release`.
  - Reach attacks at range send a bolt on `hit`, as before.
- **Reactions:** each defender's reaction (dodge, block, kneel, fumble, by
  result) **starts early by its own `impact` marker**, so its impact frame
  meets the blow. Melee impact is the attacker's `hit`; a projectile's
  impact is its arrival. The block is up and the dodge already moving when
  the blow lands.
  - The dodger's root moves by the clip's `shift` only while airborne.
  - Damage numbers float at impact.
- **Quick hits and counters:** the same marker sync, with projectiles on
  `release`.
- **KO:** `fall` plays to `grounded` and holds 0.5 s before the existing
  fade-out.
- `_projectile` returns its flight time, and every wait is a timer, never a
  signal, so a missing clip can't hang the combat.

## Runtime layers (on top of the clips)

The style bar's foot lock, inertia, turn banking, hair springs and scarf are
unchanged, except for the following:

- **Authored turns.** On a snap of the view's yaw (more than 0.5 rad, root
  nearly still, standing in idle) `BWCharacter` starts `turn_l`/`turn_r`
  and drives the rig's visual yaw from the clip's `turn` channel instead of
  the s-curve spring. The planted foot pivots under the lock; lifted feet
  land facing the new way. Any other request ends it, and the spring takes
  over from there.
- **Weapon floor clearance** (`BWCharacterPose._clear_floor`). If a weapon
  end (the tip and the pommel or butt, a bow's limb tips, a pistol's muzzle
  and grip) would go under 3 cm, the grip is **lifted** by the shortfall and
  the arms follow by IK.
  - A lift is continuous and always solvable. Rotating about the grip could
    not clear a shaft that was low at both ends, and it jumped (the pop test
    caught it).
  - Clips keep their own weapons up: the test bounds the lift at 8 cm
    outside the fall.
- **Hair gravity.** When the head tips far from upright (kneel, fall, deep
  lean), the long-hair spring target falls toward the floor and lies along
  the back (the clamp uses the chest's normal) instead of following the head
  like a flag. Upright, nothing changes.
- **Hair rotation extraction** uses a tolerant quaternion conversion. The
  head's squash scale skews the parent basis slightly, and Godot's strict
  cast logged errors in autoplay.
- **Smear crescent.** It is one band per sample from the hilt end (UV.x 0)
  to the tip path (1), with UV.y as age. The shader cuts a crescent: full
  width at the blade, tapering to the tip path at the tail (0.09 s), solid
  white with an ink inner edge and outer edge. The clip's `smear` fades it
  as a whole. This replaces the soft gradient fan.

## Tests (`test_animation.gd`, 23; `test_projectiles.gd`, 3)

Added for D80: `handling_holds_and_actions` (every style's holds, in/out,
actions with their from/to holds; stoic slower than fussy; 60 s standing
changes holds and handles the weapon, the showcase more, never blocking),
`dagger_grip_round_trip` (reverse persists through idle and its actions; a
windup flips it forward and the blade matches the strike's own by the coil;
the flip back lands on the guard), `handling_no_pops` (every hold's
transitions and actions, step < 0.1 u/frame; from every hold and mid-action
into 13 combat poses, the no-pops measure), `fists_clips` (markers, Flurry
hit < hit2 < hit3, the `skill` hook). Extended: loops and handovers (handling
clips start and end on their holds), the face test (hold loops stand too),
`idles_are_calm` (hold loops at idle bounds; handling one-shots bound the
root bob to 3 cm, not the weapon). Fists rep: Kyla in hand wraps.

Added this pass: `markers` covers the variants (impact on f0, catch,
recovered; rage `shout`, knockback `slide_end`, bow `nock`);
`no_pops_any_pair` requests all five variants from every pose (15 x 20 per
style); `stricken_variants` (knockback travel 0.84 and the skid unlocks the
feet, rage rears up on its shout, lengths, every character's plain hit in
character, a variant fires its markers and hands back to idle);
`reaction_pick` (the table: misses, KOs, resists, tiny / big / glance / low
HP buckets over the whole roster, every variant reachable, unfriendly rage
more than friendly, Hugo shrugs); `bow_draw` (arrow on the string, its nock
in the hand, through the rest, the string bent, gone on release, the
hand-over transform, the string straight after its buzz); `idles_are_calm`
(D65 bounds on the root bob and hand travel of every standing clip).
`test_projectiles.gd`: models, sidecar, hull, +Z flight axis, weapons.json
`projectile` and bow `string`, the bend API, and stepped flights (arrow arc,
alignment, stick, shrink; bullet straight and fast with a flash; bolt aura
and spin; a miss flies past).

| Test | What it checks |
|---|---|
| `saved_libraries_match_source` | All 8 bakes equal a fresh bake. |
| `every_style_has_every_clip` | 27 required clips per set. Every pose name resolves to a real clip for both classes. Every roster character plays a clip for every pose. |
| `markers` | Present and in order for strikes (melee and shot), casts, every reaction (`impact`), the dodge's airborne windows, and the fall's grounded + `hold_end`. `hit`/`release` are real Animation markers. |
| `loops_and_handovers` | Every loop's last frame equals its first. One-shots start and end on the guard; the exceptions are the start's end, the stop's start and the fall's end. run_start's end = run f0; run_stop(_r)'s start = run f0/f5; channel f0 = cast at coil. |
| `feet_and_floor` | No sole under the floor in any clip of any set. |
| `gaits_dont_slide` | Every gait and start/stop: the stance ground point moves with the root (< 3 mm per 60 Hz frame; the limp's hurt-foot scuff < 6 mm). |
| `weapons_clear_the_floor` | All 33 weapons through every clip of their set: ends above the floor, and floor lifts < 8 cm outside the fall. |
| `blade_off_the_face` | All 33 weapons through idle, idle_bouncy, wounded, idle_fidget and idle_look, from 9 cameras (azimuth -90..90, 18° down): no weapon point nearer the camera than the head covers the face disc (0.32 m). |
| `state_machine` | Holds, releases, reactions, the held fall, start → run → stop → idle, channel → cast at coil, wounded swaps, and the axe variants. |
| `personality_and_idle_rotation` | Vibes, determinism, the roster spans 4+ vibes, 20 s of standing rotates 2+ variants, variants never block. |
| `no_pops_any_pair` | 8 styles × 15 × 15 requests mid-clip. Each blended joint step is compared with the outgoing and the incoming clip played alone. A pop is a sudden excess (> 0.1 u and 1.8× the previous step) or any step > 0.35 u. |
| `foot_lock_and_turn_in_world` | Walk and run locks hold in the world (< 4 mm). A left/right snap plays turn_l/turn_r and finishes with the clip. A 0.6 s hitch stays finite. |
| `move_plan` | Run for 3 hexes: arrives, monotonic, stop before arrival, s/hex. 8 hexes < 0.5 s/hex. 1 hex walks; wounded limps. |
| `fallback_and_view_api` | The view API, an unknown pose falls back to a static key, `BWCharacter.animate = false`. |

`test_character.test_blend_reaches_key` now builds its character with
`animate = false`: it tests the static poser, which every weapon used to
reach directly.

## Review renders (Godot renderer, the game's shaders)

| File | What |
|---|---|
| `anim_<style>_sheet_<1..6>.png` (48) | **Every clip of every style**: a row per clip, every 2nd frame, 3/4 and side rows, path dots (head, fist, tip, other hand), floor and contact bars. |
| `anim_<clip>.gif` (30) | **All eight styles side by side** doing that clip, 30 fps, cutscene-like angle. Covers every clip name, including strike_axe (one/heavy), walk_heavy and run_heavy (heavy). |
| `anim_showcase_<style>.gif` (8) | The combat choreography per style: run 3 hexes (start, run, stop), windup, strike (dash and hop home, or a shot/bolt on release), the opponent's reaction synced to the impact, both settle, an idle variant. The reactions vary: one → fumble, heavy → kneel, polearm → block, spear → dodge, staff (cast) → hit, pair → fumble, bow → hit, pistol → dodge. |
| `anim_<style>_<clip>_strip.png` | Big review strips on demand (`--only strip`), not committed in bulk. |
| `anim_stricken_variants.gif` / `_strip.png` | The five hit variants side by side (heavy: Alexandra, pair: Pip); the strip is the one set, every 2nd frame with path dots. |
| `anim_bow_shot.gif` / `anim_pistol_shot.gif` | Draw with the nocked arrow and bent string, release, flight, the arrow sticks and rides the knockback; the pistol's muzzle flash and tracer. |
| `projectiles.png` | Arrow, bullet and bolt in fire, ice and thunder. |
| `anim_idle_calm.gif` | D65: eight characters in their calm home idle, variants rotating, 10 s. (Predates D80.) |
| `anim_handling_<style>.gif` (9) | D80: one character per style, two cameras: every guard action, every hold in, its actions, out; then from a hold straight into windup / strike (the hands lead back) and a hit. Fists also show Flurry, Uppercut, Palm Burst and a run. |
| `anim_roster_idles.gif` | D80: the real roster screen (showcase on), 22 s: the twenty change holds and handle their weapons. |

## Style rules (learned in the style bar, extended by the matrix)

1. **Key pose space, never bones.** Use the root frame for aimed actions and
   the chest frame for carried and passive hands.
2. **Timing on ones at 24 fps; contrast is the point.** Anticipation is
   about a third of the action; the action itself is 2–3 frames with a
   smear; hold 2 f on impact, then overshoot.
3. **Order of breaking:** head, then hips → chest → hands → tip. The head
   leads intent and trails force.
4. **Squash and stretch stays mild:** torso ±5%, head ±6%, limbs 5–8% at
   full reach only.
5. **Every airborne window is a marker pair.** Grounded root motion matches
   the clip's stride or its authored root curve.
6. **Contacts are law.**
   - Gaits are procedural.
   - One-shot moves use footstep plans.
   - New gaits use velocity-matched swings (`match_v`), so a foot never
     skids at toe-off or touchdown. The approved walk keeps its min-jerk
     swing.
7. **One-shots start and end on the set's guard.** Hand-overs (start → run,
   run → stop, channel → cast) are equal frames, tested.
8. **Blades lead with the edge.**
   - Run `edge_lead` on every swing.
   - Tips and butts stay off the floor: the clip first, and the solver's
     lift as a net.
   - **Standing, nothing covers the face from any front-half camera
     (tested).** A blade raised to the side always covers the face from
     the side camera, so guards are low or leaned back behind the head
     plane.
9. **Personality lives in the holds, the home idle, the rate, the variant
   order and the cheer**, picked from the tagline.
10. **Reactions are timed from their impact.** Every reaction has an
    `impact` marker; the cutscene starts it early so the blow meets it.

## Decisions I made (this phase)

1. **One library per weapon style**, not per weapon. Classes are variants
   inside a set: the axes' chop and shouldered gaits.
2. **The flamberge guard changed** (the open issue "blade across the face").
   The raised, leaned-out guard still covered the face on the idle's "hup"
   from the side cameras, and any raised blade to her right does. The guard
   is now low and ready: fists at the right hip, the blade out to her right
   and forward, tip at chest height.
   - The approved idle's motion is kept exactly: its aims are now turns
     relative to the guard.
   - The upright shafts (polearm, staff, spear) lean back past the head
     plane.
   - The one-handed blade points forward-right at chest height.
   - **This changes the look of the approved idle; the author should
     confirm it** (logged as D63).
3. **Run start and stop are authored with planted footsteps** against root
   curves stored in the clip (`meta.root_s`, 60 Hz). The move planner
   follows those curves exactly.
4. **The stop is chosen by the foot that is down** (run_stop / run_stop_r),
   and the planned run's rate makes a whole number of steps fit the cruise.
5. **Reactions start early by their impact marker.** A block or a dodge
   that starts when the blow lands is late.
6. **Weapon floor clearance is a solver lift**, bounded by a test so clips
   don't rely on it.
7. **The KO fall holds on the floor** (`hold_end`). The existing squash
   fade-out still removes the unit, half a second after `grounded`.
8. **The UI probe's replay wait went from 10 s to 60 s** (`ui_probe.gd`
   `_wait_ready`). It timed out because a whole enemy phase (three turns of
   runs and cutscenes) now takes longer than the old 0.18 s hops; the
   probe's checks are unchanged.

## Review iterations (this phase)

1. **Tests first.**
   - The slide test found:
     - the limp's hurt foot touching down while still swinging, fixed by a
       steeper heel and a velocity-matched swing.
     - walk_calm skidding at toe-off, fixed by a velocity-matched swing.
     - the start's right foot leaving the plan early, fixed by blending
       only after lift-off.
   - The floor test found the kneel's propped shafts, a pistol muzzle in
     the kneel, the stop's bow limb, a javelin flip going the wrong way, and
     the axe follow-through. All were fixed in the clips; the lift is now a
     net only.
2. **Pops.** The pop test (comparing against the clips alone) found the
   frame-conversion bug (0.25 u/frame), the rotation clamp jumping, and a
   staff release authored in one frame (0.37 u).
3. **Strips.**
   - The kneel hair streamed like a flag on the held kneel: hair gravity.
   - The staff guard and the halberd stood across the face from 3/4: they
     now lean back past the head plane.
   - The static dodge, hit and fall keys stood blades in front of the face:
     the reactions tip them out.
   - The stop snapped the blade from trailing to the guard in 2 frames: it
     now swings over 5 frames with follow-through.
   - The run was too upright: the lean went from 0.27 to 0.37 rad, the
     head counters, and the arm pump is bigger.
   - The look-around was stiff: up on the toes with a visor hand, a squash
     on landing.
   - The staff cast raised the staff straight through the face: it now
     rises at her right, laid back.
4. **Lineups.** The smear read as a soft fan: it is now a crescent.
5. **In the game.** Autoplay logged engine errors from the hair's
   quaternion cast (the head's squash scale): fixed with a tolerant
   conversion.

## NOT done yet (honest list)

- **D80 handling:** fists' skill clips need the combat lane's one-line
  `a.skill = skill_name` in `_cutscene` (until then they jab). The jabs
  read small from the 3/4 camera (a jab only travels ~25 cm past a high
  guard); the side-on cutscene camera shows them better. Heavy axes have no
  ground hold. The planted staff relies on the arm's reach (no `plant`),
  its butt lands within ~6 cm. The bow's shoulder sling reads as a yoke from
  the front camera. Hand-lead fades are hands only; the 4-layer cap can drop
  a hold loop under a fading layer in a pile-up of requests (not seen).

- **Every clip in every style is credible, but not every clip has had a
  dedicated polish pass.**
  - Polished: the run, start and stop; the idles; every strike; the staff
    cast; the kneel, fall and dodge.
  - Generic and lighter: block, fumble and stricken for the non-heavy
    styles (shared body, style hands), the cheers, wounded and limp, and
    idle_fidget.
- **Cheers raise weapons overhead**, and some pommels and butts cross the
  head from the front (cheer and idle_weapon are not in the face test).
- ~~The non-heavy stricken reuses Alexandra's annoyed head-shake for
  everyone.~~ Fixed: the head-shake is the cocky's plain hit only; the
  cutscene picks one of five variants by context.
- The variants are authored once and share their bodies across styles
  (hands per style). The pair has no free arm, so its windmill and flare
  read smaller. The stumble's flamberge can still graze the face for a few
  frames from the 3/4 camera at the top of the windmill.
- The knockback's travel is faked in the clip; a unit standing directly
  behind will be overlapped for half a second.
- **Run start and stop are authored with the light carry.** For the heavy
  axes the weapon blends from the light carry into the shouldered run over
  0.1 s, a visible but smooth swap.
- The paired daggers' second blade now smears too (a second trail in the
  same swoosh mesh). Pair `hit2` is still not used by the cutscene; damage
  lands on `hit`.
- ~~Arrows are not modelled; the draw hand floats behind an undrawn
  string.~~ Fixed: arrows, bullets and bolts are modelled
  (`WEAPON_MODELS.md`, "Projectiles"), an arrow is nocked from `nock` to
  `release`, and the string bends to the hand (two segments; the bow limbs
  don't flex).
- **The turn clip** works for snap turns while standing. Corner turns during
  runs still use the rig's s-curve and banking, not authored crossover
  steps.
- **No camera or time-scale hit-stop**, and no audio on markers.
- **Short moves are slower than 0.4 s/hex** because of the start and stop:
  2 hexes take 1.4 s and 3 hexes 0.6 s/hex. If tactics pacing feels
  slow, shorten the start (14 f) and stop (18 f).
- The scarf spring is still untuned (`ScarfSway` defaults).
- There is no LOD or visibility gating for the animator.


## Bow shots and arrows (D164-D166)

- **Clips:** `game/src/game/character/anim_bow.gd` (`BWAnimBow`). One draw cycle (`_cycle`, `_body`, `_feet`, `_settle`) keyed in the root frame, reused by every variant. `hand_r_grip` is the solver's pull onto the string's nock point: 1 only at the nock, 0 through the draw (the keyed hand IS the draw, the string follows it). `meta.arrows` lists the nock..release windows (seconds); `meta.fan` = 3 for Split Arrow. The defs name the clips (`clip`: shot_aimed, shot_quick, shot_fan, shot_sky, shot_volley).
- **On the string:** `BWCharacter._update_bow` shows the arrow(s) inside each window; `nock_element` tints the fletching (the combat sets it from the skill's element; plain white when the shot carries none). `nocked_arrows()` hands every loosed arrow's transform to the flights.
- **Flights:** `game/src/game/combat/vfx_ranged.gd` (`BWRangedVFX`), one node, one `_process`, a POOL of 96 arrows prewarmed when a bow is on the field. Flat shots (34 u/s, faint trail) stick in the chest and ride the bone; misses fly past and skitter behind; Split fans three; Energized pierces through and on into the ground; Pinning sticks at the feet while the target is Pinned; Dualthrow spins the dagger end over end. Stuck arrows fade after 1.5 s.
- **Arcing Shot / Rain of Arrows** are played whole by `play_area` (camera by tier, callout, clip, arrows, impacts, numbers). Arcing: one arrow on a tall arc to the centre; the blast hexes light from the centre out, a white star, ink debris, a shake. Rain: the volley leaves the bow skyward (one per release marker), a shadow (`shaders/volley_shadow.gdshader`) sweeps over the 19 hexes, 2-4 arrows per hex land over ~1 s (0.3 s while hold-to-skip), each target's number pops on its hex's first strike.
- **Review:** `godot --path . --resolution 1600x900 -s res://tools/ranged_preview.gd` (→ `design/art/ranged_bow_sheet.png`); `SHOTS=<dir> MODE=flat|miss|aimed|arcing|rain|split|pierce|pin|throw godot --path . --script res://tools/ranged_shots.gd` then `python tools/ranged_strip.py <dir>/<mode>_frames design/art/ranged_<mode> 12` (→ `ranged_flat|arcing|rain.png/.gif`); `MODE=perf` prints Rain's frame times.


## Encounters and the fit sweep (D219-D222)

The full table and its reasons: `design/art/ANIMATION-AUDIT.md`.

- **Colossus** (polearm set, D219): `walk_colossus` (32 f, stance 0.62, lift
  0.16, a step every 0.67 s; the body drops onto each plant; `step` /
  `step_r` markers shake the camera through `BWCombatScreen._footfalls`),
  `stomp_colossus` on arrival (`stomp` shakes harder), `strike_colossus`
  (64 f: coil 22 held by the windup, launch 26, land 30, hit 31, a held
  follow-through to 46, engage 99 so no dash, no bolt). It never runs; its
  gait rate divides by `BWAnimator.body_scale` (2.6). The line thrust's later
  strikes join the first cutscene (`_take_line`).
- **Runtime layer** (`BWAnimator._encounter_layer`, any set, D220): grunts
  hunch and shuffle at their own pace and jab (`strike_jab`,
  `strike_axe_jab`: `BWAnimEncounter.jab` retimes the class strike to 22 f,
  the wind-up at 60%); Blanks hold the guard still with head snaps on a
  shared clock and walk with only their legs; Beings hover (contacts off),
  glide (`plan_move` gait "glide"), flicker (`BWCharacter._update_flicker`)
  and cast every attack.
- **Skills** (D221): the defs' `clip` names the pose; `BWAnimSkill.actions`
  maps it per style. Setup beats play their pose (`brace`, `war_cry` = the
  rage from `catch`, `aim` = the strike held at its coil, `reload` =
  `act_check`, `tumble` = the dodge); a staff channels and casts at the tile.
  A weapon skill at range strikes (the bolt leaves on the hit). Flurry's and
  Hundred Fists' later strikes land on `hit2..` (`_take_strikes`). A charge
  rides in on its held coil; `idle` takes over from a held coil.
- **Poses** (D222): any clip name is a pose (`BWAnimator._act`); Staggered
  plays the stumble, Blinded the flinch.
- Review: `godot --path . --resolution 1600x900 --script
  res://tools/anim2_shots.gd [-- --only colossus_walk|colossus_thrust|being|horde|blank|jab]`
  (-> `design/art/anim2_*.png`); skill strips through `anim_preview.gd --only strip`.


## Alternates (D510-D521)

The author liked the strikes and asked for more variety: a blow can play an
**alternate clip** instead of its usual one. Source: `anim_alt.gd`
(`BWAnimAlt`); route: `BWClipRoute.pick` (`clip_route.gd`); the combat
screen asks through `_alt_pose` in the cutscene, the quick hit and a
charge's held coil (so the dash's windup and the strike agree).

**The table is data** (`BWClipRoute.ALTERNATES`, tune freely):
`"<set>|<weapon class>|<base pose>" -> { pose: weight }`. The base pose is
the def's clip, or `strike` for basic attacks, counters and skills with no
clip. `""` is the usual clip. Weights are relative.

| Key | Weights (share) |
|---|---|
| heavy, sword (flamberge, katana) | strike 1, smash 0.75, smash_flip 0.25 (half / 3⁄8 / 1⁄8) |
| heavy and one, axe | chop 1, sweep_under 1, smash 0.75, smash_flip 0.25 (a third each; the flip a quarter of smashes) |
| polearm, lance (halberd, glaive, naginata) | thrust 1, smash 0.75, smash_flip 0.25 |
| one, sword, basic | cut 1, thrust_2h 0.5, lunge 0.5 |
| one, sword, "thrust" skills | thrust, thrust_2h, lunge: a third each |
| spear, lance (lance, javelin, trident) | stab 1, lunge 1 (every stab, basic or skill) |
| pair, daggers | strike 1, flourish 1 |
| bow | shot 1, shot_jump 1 |

Rules in `pick()`, in order: a dagger blow from behind (the attack event's
`behind`, from `BWBattle.behind`) or Assassinate plays `backstab`; only
single-target blows take alternates; `MELEE_ONLY` poses (smash, sweep,
flourish, backstab) need arm's length; **a crit always plays
`smash_flip`** where the table offers it; then the weighted roll.
**Determinism:** the roll is `BWClipRoute.roll(salt_of(blow))`, a hash of the
blow (attacker, target, damage, hit, crit, HP left, strike index). It never
touches the battle's RNG (view only), so replays and tests see the same clip.

| Clip | Sets | Frames | Markers | What |
|---|---|---|---|---|
| `strike_smash` | heavy, polearm, one | 46 | coil 9, launch 11, land = **hit** 19, hop 32-35, recovered 42 | Both hands on the haft, crouch, jump with the weapon thrown back over the head, slammed down on the landing into a one-legged crouch, rear leg stretched out behind |
| `strike_smash_flip` | same | 50 | land = hit 22, hop 35-38 | The same with a forward somersault (`meta.flip_pitch` 0 → TAU, about `flip_pivot` 1.55 m: `BWCharacter._rig_turn`, like `spin_yaw`); the weapon is held level across the chest through the turn so no end points into the floor |
| `strike_sweep_under` | one, heavy | 40 | coil 9, launch 11, land 13, hit 13.5, hop 26-29 | One hand, sunk on the back foot, the axe hanging down-back behind the rear leg (the coil); down past the floor (a tilted plane for long axes) and up through the target to ~120°. Earthsplitter's clip |
| `strike_throw_under` | one, heavy | 42 | coil 8, **release** 11, hit 12, draw 20 | The underhand toss; `meta.toss` hides the held axe from release to draw (`BWCharacter._update_toss`); a fresh axe drawn over the shoulder. Axe Throw's clip (the flight: `BWRangedVFX._throw_blade`, lobbed, end over end) |
| `strike_thrust_2h` | one | 40 | the reference strike's | Both fists close at the hip, the blade level, driven straight in |
| `strike_lunge` | one, spear | 42 | coil 7, launch 9, land 11.5, hit 17, hop 30-33 | Fencing lunge: en garde side-on, a hop in, the long step (front knee over the foot, rear leg straight), the point a touch above level, the off arm flung back (the lance's shield arm too) |
| `strike_flourish` | pair | 40 | coil 8, launch 10, hit 15, land 18, hop 27-30 | Crouched, arms crossed; a jump up and forward slashing out and up until both blades are over the head. Self-detonate plays it in place (`SETUP_BY_SKILL`, hold 0.83 s) |
| `strike_backstab` | pair | 44 | coil 6, launch 8, land 16, hit 19, slide_back 26, slide_home 33 | Low and coiled; `BWBackstab.slide` moves the root on an S round to the target's back (launch..land, the feet skid) and home (slide_back..slide_home); the target keeps its back turned |
| `shot_jump` | bow | 46 | nock 6, launch 11, coil 15, **release** 17, land 22 | Nock on the ground, spring up drawing, loose at the apex (the arrow leaves the string there), land |
| `cast_tempest` | staff | 54 | coil 9, **release** 26 | The cast's gather; she floats up and turns once (`spin_yaw`) with the staff high, looses at the top, settles. Tempest's clip (`"tempest"`; `BWUnitView` maps `cast` → `cast_<skill>`) |

**The lance class's off hand (D520).** The lance, javelin and trident
(`BWCharacterPose.SHIELD_SPEARS`, by id) use the **spear** set, one-handed
with a shield; the halberd, glaive and naginata keep the two-handed
**polearm** set (a small forearm guard). The bake replaces the spear set's
off hand in every clip (`BWAnimClips._pass_shield`): forearm across the
chest, the shield facing out; `shield_hand(raise)` turns the off-hand socket
from the shield's mount data (`weapons.json` "shields") so the face looks
out and the top up, and `BWCharacterPose.shield_arm` holds that socket like
a grip. `SHIELD_CLIPS` raise it in block, brace and fumble (the spear stays
low: the shield blocks) and let it swing in the falls; a clip keys its own
with `Clip.shield(frame, raise, weight)` (the lunge: weight 0, the arm swings
back). Aimed clips carry it with the chest's turn. The Colossus keeps the
polearm set.

Review: `godot --path . --resolution 1600x900 -s res://tools/anim_preview.gd
-- --only clipgif --style s --clip a,b [--rep id] [--name n] --frames <dir>`
(one character from the cutscene's side and from her left), then
`python tools/anim_gif.py <dir> <out> 30`. Committed review GIFs:
`design/art/anim510_*.gif`. Tests: `test_anim_alternates.gd`.

Known limits: the preview doesn't run the backstab's slither or the thrown
axe's flight (combat only; see the in-combat capture). Legs hang fairly
straight in the jump shot and the flourish's air time. The Colossus still
gets the lance's kite shield model from the weapon lane (its hands are both
on the shaft).
