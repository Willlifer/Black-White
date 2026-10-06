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

Last reviewed: 2026-10-05.

## Live

| ID | Item | State | Unblocked by / note |
|---|---|---|---|
| L-1 | Detonations hit very hard: a glazed water 3 + dark 3 blast is about 52% of the occupant's HP. The author: "explosions are very strong". | AWAITING PLAY | Play with the blast preview (D160) on. Then tune `5% + 4%/step`, the glaze ×1.5 and the water bonus, or leave it. |
| L-2 | The enemy stat multipliers run up to ×2.3 (`ENEMY_CURVE`, D133/D139) to keep up with squad growth. | WATCH | If the late fights feel like stat walls, add an enemy-only HP column and lower the multipliers (the measured options are in DECISIONS "Open"). |
| L-3 | Late fights run 5–6 rounds median against a 6–9 target. After D137 the author said "the one-shot fest plays a lot better". | AWAITING PLAY | The author's feel after full runs. |
| L-4 | Hair pokes through full helms (seen in the live portraits). | OWED | Full-cover headgear hides or tucks the hair: add a per-item `hides_hair` flag in the equipment data. |
| L-5 | In the live portrait, a raised bow can cross the face. | WATCH | If the author notices it in play, tighten the framing or fade the weapon in the feed. |
| L-6 | First-use shader compile hitch of about 50 ms (Rain of Arrows, Tempest, the first cast). | OWED | Pre-warm the VFX shaders and materials during the loading or pre-battle screen. |
| L-7 | The sim and enemy AI play weakly: no combos, damage spread across both obelisks, and a kiting archer on the ravine at fight 9. | DEFERRED | An AI pass after the rules settle. The campaign sim understates what a human can do. |
| L-8 | VFX polish: the Surge fire column hides behind its target, the spin trail is faint, Fan of Knives has no thrown blades, and the Hundred Fists review strip was rendered on a pistol unit. | OWED | A small VFX pass. |
| L-9 | Ambiguous glossary links: the axe skill "Charge" goes to the tile term, "light/dark gray" goes to the elements, Covering Fire goes to Overwatch. | OWED | Glossary alias rules (context or exact-phrase precedence). |
| L-10 | Art docs `design/art/ANIMATION.md` and `CLOTHING.md` still use the pre-D149 roster names. | OWED | A doc pass. |
| L-11 | Always-Branch-out habits collapse late (29% at fight 10). | WATCH | Only if players hit it. Mixed habits are fine. |
| L-12 | Always-Wander squads roll rogues often (13 in 24 sim runs), because six wanderers a day means about 54 wanders a run. | WATCH | If rogues feel common in real play, lower `WANDER_JACKPOT_EXTRA_ROLL`. |
| L-13 | Older animation nits: knockback rarely fires early, fist jabs read small, the bow sling yoke, the planted staff floats. | OWED | An animation pass. |
| L-14 | Animation wishlist from the hall: rest loop, rummage, greet/handshake, looping training strike, raise-item channel. | DEFERRED | Later polish. Held poses cover it now. |
| L-15 | The loading screen is unused since the intro was removed (D84). | WATCH | Reuse it for shader pre-warm (L-6) or delete it. |

## Settled

| ID | Item | Closed | How |
|---|---|---|---|
| S-1 | The Giant's ground-damage cheese. | 2026-10-05 | The author: "If we win, then we win." No cap. |
| S-2 | Catacombs' tall pillars. | 2026-10-05 | The author keeps them; the middle became seeded dark (D134–D136). |
| S-3 | Old saves after the roster rename. | 2026-10-05 | Save v5 shows "from an older version" and starts fresh (D149–D154). |
| S-4 | Obelisk numbers. | 2026-10-05 | The author set 350 HP and 10 per pulse (D155). |
| S-5 | Wander rogue odds. | 2026-10-05 | 20% rolls, +100 XP when all fail, jackpot only on an extra 5% roll (D127–D132). |
| S-6 | What goes in the GitHub repo. | 2026-10-05 | A barebones export: code, data, maps, runtime audio and art, and the docs. No review renders, references or archive. |
| S-7 | L-16: Esc stack, stuck item tooltip, tag declutter, callout plate, weapon-type capitals | 2026-10-05 | D171–D173. The stuck card was `_unhover` keeping the last read when nothing was selected |
