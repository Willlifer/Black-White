# Ledger

One row per tracked item. An item belongs here only if it passes all four tests:
1. It's discrete.
2. It has a state that can change.
3. Forgetting it costs something.
4. No test already guards it.

Bugs fixed in the same session never land here. A closed item moves to
**Settled** with its date; IDs never change.

**States:**

| State | Meaning |
|---|---|
| BLOCKED | Needs a decision; the decider is named. |
| OWED | Agreed work, not yet done. |
| AWAITING PLAY | A tuning question only play can answer. |
| WATCH | No work now; a named trigger turns it into work. |
| DEFERRED | Deliberately not now, with the reason. |

Last reviewed: 2026-10-06.

## Live

| ID | Item | State | Unblocked by / note |
|---|---|---|---|
| L-1 | Detonations hit very hard: a glazed water 3 + dark 3 blast is about 52% of the occupant's HP. The author: "explosions are very strong". | AWAITING PLAY | Play with the blast preview (D160) on. Then tune `5% + 4%/step`, the glaze ×1.5 and the water bonus, or leave it. |
| L-3 | Fight length: after D194 (enemy level = stage) the sim runs 6–7 rounds median from fight 3 on, the low end of the 6–9 target. After D137 the author said "the one-shot fest plays a lot better". | AWAITING PLAY | The author's feel after full runs. |
| L-5 | In the live portrait, a raised bow can cross the face. | WATCH | If the author notices it in play, tighten the framing or fade the weapon in the feed. |
| L-7 | The sim and enemy AI play weakly: no combos, damage spread across both obelisks, and a kiting archer on the ravine at fight 9. | DEFERRED | An AI pass after the rules settle. The campaign sim understates what a human can do. |
| L-8 | VFX polish: the Surge fire column hides behind its target, the spin trail is faint, Fan of Knives has no thrown blades, and the Hundred Fists review strip was rendered on a pistol unit. | OWED | A small VFX pass. |
| L-10 | Art docs `design/art/ANIMATION.md` and `CLOTHING.md` still use the pre-D149 roster names. | OWED | A doc pass. |
| L-11 | Always-Branch-out habits collapse late (29% at fight 10). | WATCH | Only if players hit it. Mixed habits are fine. |
| L-13 | Older animation nits: knockback rarely fires early, fist jabs read small, the bow sling yoke, the planted staff floats. The fit sweep (D219–D222, `design/art/ANIMATION-AUDIT.md`) fixed 37 of 41 mismatches; its 3 leftovers join this row: Empty the Chamber has one recoil under its 4-tracer sweep, Fan of Knives throws no knives (VFX, L-8), Haymaker plays the uppercut. | OWED | An animation pass. The sweep's new clips and the encounter motion await the author's eye in play (renders `design/art/anim2_*.png`). |
| L-14 | Animation wishlist from the hall: rest loop, rummage, greet/handshake, looping training strike, raise-item channel. | DEFERRED | Later polish. Held poses cover it now; the hall's Branch out reaction and the jackpot's cool cheer now play their clips (they fell back to idle, D222). |
| L-17 | Enchantments v2 balance (D196–D205): Relentless with Triumph, Undying vs the Giant, Bloodpact on multi-hit weapons, the 20% heal cap, free scrolls (D236: was 2 items; does a free re-roll of every element row each fight make imbues trivial?). | AWAITING PLAY | Full runs; the watch list is ENCHANTMENTS-v2.md §4. The AI never uses Bodyguard swaps on purpose (it may stumble into one). |
| L-15 | The loading screen is unused since the intro was removed (D84). | WATCH | L-6 no longer needs it: the shader pre-warm is an offscreen pass at boot (D232). Delete it, or reuse it if a slow load appears. |
| L-18 | Fight 4 (the Obelisks) wins 45% in the sim against a 70–80% target, and the curve multiplier doesn't move it (0.7–1.5 all gave 41–45%). | AWAITING PLAY | Play it. The sim's AI spreads damage over both stones (L-7); if players also find it hard, tune the stones (D155) or the fight's enemy count, not the curve. |
| L-19 | Re-tune the curve after the enchantment (D196–D205), shop and special-encounter (landed: D208–D214) lanes land. D194 is deliberately loose: Standard 66–95% per fight, Hard 4–50 points under. | OWED | `RUNS=24 POLICY=mixed ROOMS=standard SHADOW=1` campaign_sim with env CURVE / ELVL / HARD; targets in D194. |
| L-20 | Special encounters (D208–D213): the sim tuned each to roughly the paired Hard rate (D212), but early Beings (fight 3) and Horde/Colossus at fight 3–5 run low with the sim's weak AI, and nobody has played them. Watch: the Horde's 13-unit turns (pace), whether the Colossus's line thrust reads, whether players find the Being counter. | AWAITING PLAY | Play runs that meet each; knobs are `BWEncounters` *_MULT / *_HP, `RATE`. |
| L-21 | HP bars (D215–D218): black/white by half with pips, numbers on hover, the 50% pulse, the HUD clamp, compact item cards. | AWAITING PLAY | The author's read in a real fight: whether pips are busy on the 5 px turn-order bars, whether the pulse is noticeable. Renders: `design/art/hpbar_*.png`. Bars and labels now hide behind HUD panels (D230, `a11y_hpbar_*.png`). |
| L-23 | Playtest 1 fixes (D233–D237): the drawn first perk (no picker), the discard pile, sorting, free scrolls, no cutscene for ground actions that hurt nobody. | AWAITING PLAY | The author's next run. Renders: `design/art/playtest1_*.png`. Watch: whether the hall's perk label is enough of a "show", whether a free scroll every fight flattens gear choices (L-17). |

## Settled

| ID | Item | Closed | How |
|---|---|---|---|
| S-1 | The Giant's ground-damage cheese. | 2026-10-05 | The author: "If we win, then we win." No cap. |
| S-2 | Catacombs' tall pillars. | 2026-10-05 | The author keeps them; the middle became seeded dark (D134–D136). |
| S-3 | Old saves after the roster rename. | 2026-10-05 | Save v5 shows "from an older version" and starts fresh (D149–D154). |
| S-4 | Obelisk numbers. | 2026-10-05 | The author set 350 HP and 10 per pulse (D155). |
| S-5 | Wander odds. | 2026-10-06 | 20% rolls; all miss: +1 to a random stat, or on an extra 5% the nine rerolled at 30% (D177, D179). No rogue, no XP. |
| S-6 | What goes in the GitHub repo. | 2026-10-05 | A barebones export: code, data, maps, runtime audio and art, and the docs. No review renders, references or archive. |
| S-7 | L-16: Esc stack, stuck item tooltip, tag declutter, callout plate, weapon-type capitals | 2026-10-05 | D171–D173. The stuck card was `_unhover` keeping the last read when nothing was selected |
| S-8 | L-12: rogues from always-Wander. | 2026-10-06 | D177 removed the rogue: the jackpot now rerolls the nine effects at 30%. |
| S-9 | L-2: enemy stat multipliers up to ×2.3. | 2026-10-06 | D179 and D194: enemy level = its stage; the multipliers are now 0.7–1.7. |
| S-10 | L-9: ambiguous glossary links (Charge, light/dark grey, Covering Fire). | 2026-10-06 | D227: stop phrases and exact-case skill-name stops in BWGlossary; tested in `test_a11y_d227`. |
| S-11 | L-4: hair through full helms. | 2026-10-06 | D228: `hides_hair` per item in `equipment.csv`, every head piece checked; `a11y_helm.png`. |
| S-12 | L-22: the gear panel's skill rows ran off the bottom at 16:9. | 2026-10-06 | D229: a shorter paperdoll and slot column; `a11y_gear.png`. |
| S-13 | L-6: first-use shader hitch. | 2026-10-06 | D232: `BWShaderWarm` at boot; `tools/prewarm_probe.gd` measured worst first-use frame +26–29 ms cold → +2–3 ms warmed. |
