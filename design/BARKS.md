# Barks

Data: `game/data/barks.csv`, 425 lines. This file covers how the game picks
lines, what's covered, and what I decided along the way. If this file and
`SCHEMA.md` disagree, `SCHEMA.md` wins.

## Columns

| Column | Values |
|---|---|
| `id` | `event[_action]_speaker_trust[_to_toward]_NN`, e.g. `ally_ko_unf_tru_to_fri_01` |
| `event` | `ally_attacking ally_ko healing_received downtime_advice` (core), plus `self_ko crit_landed dodged enemy_ko battle_start battle_won level_up recruited` |
| `action` | Only for `downtime_advice`: `ask`, or one of `specialize branch_out wander` (D127; the eight old actions' lines were removed, and the `ask` lines that named them). Blank otherwise. |
| `speaker_friendliness` | `unfriendly neutral friendly` (the one talking) |
| `toward_friendliness` | `unfriendly neutral friendly any` (the other party) |
| `trust` | `strangers acquainted trusted` |
| `line` | The text. Placeholders below. |
| `voice_clip` | Clip name in `Audio Barks/` without `.wav`, pitch-shifted by the speaker's `voice_pitch` from `roster.csv` |

Placeholders: `{ally}` = the other squad unit's name, `{element}` = the
speaker's element for `train_element`, `{weapon}` = the speaker's weapon class
for `train_weapon`. I didn't need `{speaker}` or `{target}`; the game
should still substitute all five. Capitalise `{element}` / `{weapon}` when they start
the line.

## Who speaks, per event

| Event | Fires when | Speaker | `{ally}` / toward | Chance |
|---|---|---|---|---|
| `ally_attacking` | A unit confirms an attack | One deployed squadmate that isn't attacking (weighted pick, below) | The attacker | 25% |
| `ally_ko` | A squad unit hits 0 HP | The deployed squadmate with the highest trust toward them (random tie-break) | The downed unit | 100% |
| `self_ko` | A squad unit hits 0 HP | The downed unit, before `ally_ko` | `any` | 100% |
| `healing_received` | A squad unit gains HP from a light heal | The healed unit | The healer (who cast it or charged the tile) | 60% |
| `crit_landed` | A squad attack crits | The attacker | `any` | 50% |
| `dodged` | A squad unit avoids an attack | The dodger | `any` | 35% |
| `enemy_ko` | A squad unit knocks out an enemy | The one who landed the KO | `any` | 40% |
| `battle_start` | Fight begins, after placement | One random deployed unit | `any` | 100% |
| `battle_won` | Victory screen | One random surviving unit | `any` | 100% |
| `level_up` | Level gained (shown on the results screen) | The unit | `any` | 100%, one per unit per screen |
| `recruited` | A recruit joins (downtime `recruit` resolves) | The new recruit | `any`, always `strangers` | 100% |
| `downtime_advice` / `ask` | Player selects a unit with no actions locked | That unit | `any` | 100%, once per unit per day |
| `downtime_advice` / action | Player picks a choice (D127) | That unit | `any` | 100% for the first pick, 50% when changing it |

Enemies don't bark. Only the player's squad does.

**Weighted pick for `ally_attacking`:** each candidate squadmate gets weight
1 / 2 / 3 for strangers / acquainted / trusted with the attacker. People who
trust you are the ones who cheer.

## Picking the line

1. **Trust.** For pair events (`ally_attacking`, `ally_ko`,
   `healing_received`) use the pair's trust stage. For solo events
   (everything else) use the speaker's **squad trust**: the median of their
   pair trust with the other five units in the chosen six.
2. **toward_friendliness.** For pair events, the other unit's
   friendliness tag from `roster.csv`. Solo events always use `any`.
3. **Pool.** Rows matching `event` (+ `action`), `speaker_friendliness`,
   `trust`, with `toward_friendliness` equal to the other party's tag
   **or** `any`. Pair-specific rows get weight 3, `any` rows weight 1. The
   pair rows hold the jokes, so they should come up often while still leaving
   room for the rest.
4. **No repeats.** Draw from a shuffle bag per pool. A line doesn't
   repeat for that pool until the bag is empty. Persist the bags across the run.
5. **Fallback.** If a pool is empty, try the trust stage one step closer to
   `strangers`, then skip the bark. Every cell is filled today, so this only
   protects against future edits.

## Cooldowns

- **One bark per action.** An attack resolution can trigger several
  events. Play the highest-priority one only:
  `self_ko > ally_ko > enemy_ko > crit_landed > healing_received > dodged > ally_attacking`.
  (`self_ko` and `ally_ko` are the exception: both play, self first, then the witness.)
- **Per unit:** a unit that barked can't bark again for 2 turns of the turn order,
  except for KO events.
- **Global:** at least 3 seconds between combat barks. Drop a bark rather than queue it.
- **Cinematic:** barks play as the attack cutscene fades back in, not
  during the zoom. Speech bubble above the speaker, 2.5 s, plus the voice clip.
- **Downtime:** `ask` once per unit per day. Reacting to an action that was
  unlocked and re-locked doesn't repeat the line.

## Trust advances

Trust is tracked **per pair** (symmetric), as points:

| Gain | Points |
|---|---|
| Both deployed in the same fight (finished, win or lose) | +1 |
| **KO save**: A knocks out an enemy that damaged B since B's last turn, while B is at or below 50% HP | +2 |
| A heals B | +1 (once per fight per pair) |
| Both in the chosen six through a downtime day, even if not deployed | +0 (being in the squad isn't fighting together) |

Stages: **strangers** 0–2, **acquainted** 3–7, **trusted** 8+.

With 3 deployed from 6 over 10 fights, a pair that's often deployed together
reaches acquainted around fight 3 and trusted around fight 7 if they save each
other a few times. Pairs the player never deploys together stay strangers,
and that's the point. Recruits start at 0 with everyone.

**Optional slower thaw for unfriendly units:** if unfriendly units feel like
they warm up too fast, give them +2 on both thresholds when *either*
member of the pair is unfriendly (acquainted at 5, trusted at 10). Tune at Gate 2.

## Coverage matrix

Line counts per speaker × trust. `n (m)` = n total, of which m are `any`;
the rest are pair-specific.

| Event | unf str | unf acq | unf tru | neu str | neu acq | neu tru | fri str | fri acq | fri tru | Total |
|---|---|---|---|---|---|---|---|---|---|---|
| ally_attacking | 9 (6) | 6 (5) | 8 (5) | 7 (5) | 5 | 6 (5) | 8 (5) | 5 | 8 (5) | 62 |
| ally_ko | 7 (5) | 5 | 8 (5) | 5 | 6 (5) | 6 (5) | 7 (5) | 5 | 6 (5) | 55 |
| healing_received | 7 (5) | 6 (5) | 7 (5) | 6 (5) | 5 | 5 | 7 (5) | 5 | 7 (5) | 55 |
| downtime_advice | 13 | 13 | 12 | 14 | 12 | 12 | 12 | 13 | 14 | 115 |
| self_ko | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 18 |
| crit_landed | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 18 |
| dodged | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 18 |
| enemy_ko | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 18 |
| battle_start | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 18 |
| battle_won | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 18 |
| level_up | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 18 |
| recruited | 4 | – | – | 4 | – | – | 4 | – | – | 12 |
| **Total** | | | | | | | | | | **425** |

**downtime_advice breakdown:** each speaker × trust cell has 4 `ask` lines
(36 total) and at least 1 reaction per action (8 actions × 9 cells = 72),
with 7 cells getting a second line (79 reactions total). Per speaker over all
trust stages: `ask` 12, `train_element` 4, `train_weapon` 3–4,
`train_ability` 3–4, `search_equipment` 3–4, `improve_equipment` 3,
`enchant_equipment` 3, `rest` 3, `recruit` 3.

**Pair-specific lines (37)** sit where the pairing is the joke: unfriendly↔friendly
at strangers and trusted (the cold/warm clash, then the thaw),
unfriendly→unfriendly at trusted (two grumps admitting it), neutral→friendly
(the dry one gets hugged), and neutral→unfriendly.

**Voice clips used:** Mmhmm 93, Hmm 88, Yeah 65, Laugh 53, No 43, Hey 24,
Yah 19, Dying 18, Hiyah 15, Oof 5, Oogh 2. **Ouch grunt is unused.** It
belongs on hit reactions, which have no text bark. Play it on any
non-lethal hit with no bark attached.

## The arc, by voice

- **Unfriendly:** strangers dismiss you ("Didn't ask."), acquainted give
  grudging credit ("Adequate."), trusted show warmth they deny
  ("Thanks. I mean it. Moving on.").
- **Neutral:** strangers report facts ("Attack initiated."), acquainted
  comment dryly ("Reliable. Like a bus."), trusted are warm but still dry
  ("You're my favorite light source.").
- **Friendly:** strangers are too eager and don't know your name
  ("Go, uh... you! Go you!"), acquainted have learned it ("Go {ally}! I know
  your name now!"), trusted talk in shorthand ("Thing! Do the thing!").

## Ten favourites

1. "Imagine I'm nodding." (neutral, trusted, ally_attacking)
2. "Go, uh... you! Go you!" (friendly, strangers, ally_attacking)
3. "No! I was going to learn your name!" (friendly, strangers, ally_ko)
4. "Reliable. Like a bus." (neutral, acquainted, ally_attacking)
5. "Stop glowing at me." (unfriendly → friendly, strangers, healing_received)
6. "I'll put that on your tab. You have a tab." (neutral, acquainted, healing_received)
7. "Recruiting the enemy. Bold hiring policy." (neutral, strangers, downtime / recruit)
8. "I'm naming my move! It's called 'Move'!" (friendly, strangers, downtime / train_ability)
9. "Statistically, that should have hit." (neutral, acquainted, dodged)
10. "Get up. Nobody beats you but me." (unfriendly → unfriendly, trusted, ally_ko)

## Decisions I made

1. **Ally Attacking is voiced by a bystander,** not the attacker. The
   attacker gets `crit_landed` and `enemy_ko` instead. That keeps the event
   about how units see *each other*, which is where trust shows.
2. **Rest healing has no `healing_received` bark.** D10 says rest heals,
   but nobody does the healing, and the lines talk to a healer. Rest is voiced
   by `downtime_advice` / `rest`. A light tile charged by an enemy or
   by nobody also gets no bark.
3. **`action = ask`** marks the "what should I do?" lines. I added it
   because the brief asks for both asking and reacting.
4. **Downtime and solo events use squad trust** (median of pair trust
   with the other five) since there's no single other party.
5. **`recruited` is strangers-only** and spoken by the recruit. The
   squad's side of recruiting is the `downtime_advice` / `recruit` reaction.
6. **Trust is per pair and symmetric.** Unfriendly units don't have a
   separate one-way thaw. That's done in the writing, plus the optional
   threshold bump above.
7. **No damage-taken bark.** It would fire too often and drown the
   other barks. Ouch grunt covers it with no text.
8. **Enemies are silent.** The brief's barks are about the squad.
9. **Few names.** `{ally}` shows up from acquainted on and is
   rare at strangers, so names show the arc.
10. **No lore, no places, no elements by name** except through `{element}`.
    Lines work for any of the 20 roster units.
11. **4 lines run past 9 words** (all ≤ 11). I kept them because
    the joke needs the second sentence.

## Schema gaps (for SCHEMA.md's owner)

- `barks.csv` adds two values SCHEMA.md doesn't list: the
  `toward_friendliness` value `any`, and the `action` column with its ids.
  SCHEMA.md should get a "Barks" section that freezes the event ids and
  downtime action ids, which the downtime UI needs too.
- Downtime action ids aren't defined anywhere yet. I used
  `train_element train_weapon train_ability search_equipment improve_equipment enchant_equipment rest recruit`.
  The downtime lane should use the same ones.
- Trust stage names are in SCHEMA.md, but how trust advances isn't. The
  proposal above needs a ruling.
- `voice_clip` names match the files in `Audio Barks/` minus `.wav`;
  one has a space (`Ouch grunt`).
