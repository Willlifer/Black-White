# Black | White roster

20 seats, filled from **47 identities**: the 20 core characters below and a rolling
**pool** of 27 (D379). No story, no lead, no personality lines (D153): element and weapon are the
personality. **Identity is fixed** (`game/data/roster.csv`); **weapon, element and clothes are
rolled** each new game, and again whenever the player presses Randomize [R] on the select screen
(`BWRosterGen.roll(identities, seed)`, D150). The seed is stored in the run, never shown.

## The rolling pool (D379)

The author: "I never expected roster to be limiting… On randomize, they can replace some of the
back row units." The roster screen still shows 20 seats:

- **Front row (seats 1-10):** always the core ten.
- **Back row (seats 11-20):** 3-5 seats (seeded, `BWRosterGen.POOL_MIN`/`POOL_MAX`) go to pool
  identities, at the game's start and on every **Randomize [R]**. A locked core character
  (Rem) keeps the seat. The swap has its own seeded stream (`BWRosterGen.seated`), so the kits
  per seat roll exactly as before; the incoming character takes the seat's number.
- **Enemies** draw from **every identity outside the squad**: the seats plus the **reserve**
  (`BWRun.reserve_rows`: the unseated identities, each rolled on its own stream,
  `BWRosterGen.reserve`). A 6v6 always has 6; if a squad ever recruited nearly everyone, the
  draw adds duplicates with their own roll (`"<id>~2"`, `BWRun.roster_row`).
  `can_recruit` keeps a full side of 6 outside.
- **Saves** keep both the seated rows and the reserve (a save without a reserve re-rolls it
  from `roster_seed`).
- Tests, tools and sims roll the core twenty (`roll(identities, seed)` without the pool);
  only the roster screen passes `BWData.pool_identities()`.

### The pool (data/roster.csv, `pool` = 1)

The 17 pre-D149 names (the first roster, as `design/FORECAST-L1.txt` lists it, minus
Alexandra, Aureli and Will, who stayed) and the author's 10 new ones. Gender per the D149
rule: historically gendered names follow it, the rest are ambiguous.

| Name | G | Friendliness | Hair | Voice | Lock | From |
|---|---|---|---|---|---|---|
| Bartholomew | m | friendly | buzzed | 0.78 | | pre-D149 |
| Kyla | f | unfriendly | long_ponytail | 1.18 | | pre-D149 |
| Picassa | f | neutral | ringlets | 1.22 | | pre-D149 |
| Thaddeus | m | unfriendly | long_hair | 0.80 | | pre-D149 |
| Leopold | m | neutral | mullet | 0.92 | | pre-D149 |
| Gus | m | friendly | buzzed | 0.76 | | pre-D149 |
| Henrietta | f | neutral | long_hair | 1.06 | | pre-D149 |
| Marguerite | f | unfriendly | ringlets | 1.12 | | pre-D149 |
| Zoe | f | friendly | short_mohawk | 1.26 | | pre-D149 |
| Pip | a | friendly | ringlets | 1.12 | | pre-D149 |
| Ottilie | f | neutral | bob | 1.28 | | pre-D149 |
| Nova | a | unfriendly | bob | 1.04 | | pre-D149 |
| Rory | a | friendly | mullet | 0.98 | | pre-D149 |
| Montgomery | m | unfriendly | high_and_tight | 0.86 | | pre-D149 |
| Jet | a | unfriendly | high_and_tight | 1.08 | | pre-D149 |
| Hugo | m | neutral | ponytail | 0.88 | | pre-D149 |
| Ambrose | m | neutral | waterfall | 0.96 | | pre-D149 |
| Picasso | m | friendly | mullet | 0.94 | | author |
| Irelia | a | unfriendly | ponytail | 1.06 | | author |
| Despacito | a | friendly | buzzed | 1.00 | | author |
| Quinn | a | neutral | ponytail | 1.02 | | author |
| Shyvana | f | unfriendly | long_ponytail | 1.14 | **fire** | author |
| Cain | m | unfriendly | high_and_tight | 0.82 | | author |
| Abel | m | friendly | short_mohawk | 1.00 | | author |
| Lyn | a | neutral | long_ponytail | 1.10 | | author |
| Micaiah | a | neutral | waterfall | 0.98 | | author |
| Mushu | a | friendly | short_mohawk | 1.10 | | author |

Calls (Claude, D379; overturn freely): m = the historically male names (Bartholomew,
Thaddeus, Leopold, Gus, Montgomery, Hugo, Ambrose, Picasso, Cain, Abel); f = the historically
female ones (Kyla, Picassa, Henrietta, Marguerite, Zoe, Ottilie) and Shyvana (the author);
ambiguous: Pip, Nova, Rory, Jet, Despacito, Quinn, Irelia, Lyn, Mushu, and Micaiah (a male
prophet and a queen mother share it). Picasso and Picassa are both kept (the author named
Picasso; Picassa was the old roster's). Hair: all 10 styles, 2-3 each, a few outliers (Zoe's
mohawk, Thaddeus's long hair, Ambrose's waterfall). Friendliness 9 / 9 / 9; voices m 0.76-0.94,
f 1.06-1.28, a 0.98-1.12. The art docs' old examples (Pip, Hugo, Kyla in ANIMATION.md) now
name pool members (L-10).

## Identity (fixed)

The 20 core seats (`pool` = 0). Seat order is front row left→right, then rear row
left→right. G: f / m / a (ambiguous).

| Seat | Name | G | Friendliness | Hair | Voice | Lock |
|---|---|---|---|---|---|---|
| 1 | Aureli | f | neutral | waterfall | 1.20 | **light** |
| 2 | Della | f | unfriendly | long_ponytail | 1.16 | |
| 3 | Jericho | m | neutral | short_mohawk | 0.86 | |
| 4 | Will | m | friendly | high_and_tight | 1.02 | |
| 5 | Gail | f | friendly | long_ponytail | 1.10 | |
| 6 | Kira | f | neutral | ringlets | 1.24 | |
| 7 | Demeter | a | unfriendly | ponytail | 1.00 | |
| 8 | Stryker | m | friendly | mullet | 0.84 | |
| 9 | Burt | m | friendly | buzzed | 0.75 | |
| 10 | Rui | f | unfriendly | bob | 1.30 | |
| 11 | Bob | m | friendly | high_and_tight | 0.78 | |
| 12 | Sala | f | unfriendly | long_hair | 1.14 | |
| 13 | Rem | f | friendly | bob | 1.28 | **ice** |
| 14 | Wilona | f | neutral | long_ponytail | 1.08 | |
| 15 | Lionel | m | friendly | buzzed | 0.82 | |
| 16 | Dragtol | a | neutral | mullet | 0.90 | |
| 17 | Apollyon | a | unfriendly | waterfall | 0.94 | |
| 18 | Kai | a | unfriendly | short_mohawk | 1.12 | |
| 19 | Alexandra | f | unfriendly | long_hair | 1.04 | |
| 20 | Opus | a | neutral | ponytail | 0.96 | |

Hair colour is not here: it follows element and affinity rank (D146).

### Calls I made (review and overturn freely)

1. **Gender.** f = the nine the author marked. m = the historically male names: Jericho, Will,
   Stryker, Burt, Bob, Lionel. **Ambiguous:** Demeter (a goddess, so the name leans female, but
   the author left it unmarked and offered it as ambiguous), Dragtol, Apollyon (an angel), Kai, Opus.
   Split: f 9, m 6, a 5. `gender` only steers clothing pools.
2. **Hair.** All 10 archetypes used (counts below). Alexandra
   keeps long_hair. Outliers: none after the author swapped Gail and Lionel (2026-10-05). Ambiguous characters get
   ambiguous styles: ponytail (Demeter, Opus), mullet (Dragtol), waterfall (Apollyon),
   short_mohawk (Kai). The old seat→hair mapping is kept where it fit (seats 5, 6, 9, 10, 13, 14,
   16, 17, 18) and moved where a same-style pair would have drawn the same mesh variant
   (`BWHair.variant_for(id)`; `test_hair` requires the two wearers of a style to differ).
   Counts: long_ponytail 3, ringlets 1, the other eight 2 each.
3. **Friendliness and voice** reuse the old seat's (Aureli, Will and Alexandra keep their own),
   so the bark mix is unchanged: unfriendly 7, neutral 6, friendly 7. Voices: m 0.75–1.02,
   f 1.04–1.30, a 0.90–1.12.

## Rolled facets (BWRosterGen)

- **Weapon:** a class from a deck (each of the 7 twice, 6 more at random, so every class is
  always held), then a model of that class (a shuffled cycle: a class held three times shows three
  models). Nobody starts with fists (D76).
- **Element:** the lock (Aureli light, Rem ice), else from a deck (each element twice, 4 more at random).
- **Stats:** the class profile below, then one point moved between two stats and, a third of the
  time, one other stat ±1. Each stat stays within ±1 of the profile and 1–6; the total within ±1.
- **Clothes:** top and bottom weighted by gender (`BWRosterGen.POOLS`; f / m lean their usual way
  with low weights on the other side's pieces, a leans hoodie / sweater / sweatpants), then a
  coverage pass so **all 7 tops and all 7 bottoms appear in every roll**. Shade from a deck of
  7 dark / 7 mid / 6 light.

### Stat profiles (D151)

con / str / dex / wil / def / res / spd

| Class | Profile | Total | Lean |
|---|---|---|---|
| sword | 4/5/4/2/4/3/4 | 26 | balanced duelist, STR |
| axe | 6/6/2/1/5/3/2 | 25 | STR/CON/DEF, slow |
| lance | 5/5/3/2/5/3/3 | 26 | CON/STR/DEF |
| daggers | 3/2/6/2/2/3/6 | 24 | DEX/SPD, fragile |
| bow | 3/3/6/2/3/3/5 | 25 | DEX/SPD |
| pistols | 3/4/6/1/3/3/4 | 24 | DEX/STR |
| staff | 3/1/3/6/2/6/4 | 25 | WIL/RES |

## Seeds

- Play: a random seed per roster screen; Randomize draws a new one.
- `-- --seed N` fixes it; the self-test, probes and shot tools use seed 1 (`BWRosterGen.DEFAULT_SEED`).
- `BWData.table("roster")` is the active roll; `BWData.identities()` the csv.
- Tests that need one particular kit use `BWRosterKits` (`game/tests/roster_kits.gd`): the
  pre-D150 kits frozen on the same seats under the new names.
- Renders: `design/art/roster_rand_seed1.png`, `roster_rand_seed2.png`, `roster_rand_hover.png`.
