# Audio needs: systems added after Phase 6

These are the sounds and cues the new systems currently lack or borrow.
Drop WAVs into `Black White\Audio Drops\`, named as listed, and I'll wire,
trim and level them. Any length is fine; I'll measure the onsets the same
way the barks were measured.

**Format:** WAV, 44.1 or 48 kHz, mono is fine for SFX. Music loops should
start and end on the bar so they loop cleanly; send stems if you have them,
as with the original loops.

## Status after drop 2 (2026-10-06, D239–D242)

Covered (details and measurements: AUDIO.md, "Drop 2"):
- [x] `music_rooms`: **Music Rooms** (a free-tempo phrase loop, not on the hall's tempo)
- [x] `music_tutorial`: **moderato main loopish**
- [x] `sting_level_up`: one per results screen (the whole squad levels every fight)
- [x] `sting_pick_reveal`: any picker; fades when the pick is taken
- [x] `sting_room_hard`
- [x] `sting_jackpot` and `sting_victory`: **very good event**
- [x] `sting_defeat` and `sfx_cursed_equip`: **cursed or bad**
- [x] `sfx_scroll_apply` and `sfx_trade`: **shop purchase** (`sfx_scroll_buy` is moot: scrolls are free, D236)
- Also used: **MainTheme Arpeggio** (title), **chillin main theme** (the hall),
  **Low Beat** + **no snare beat** (pre-battle; the kick also joins combat
  intensity 2 and the boss)

Still missing (short):
- `music_picks` (optional; the reveal sting covers the moment), `music_encounter` (optional)

## Key: the stings are in A now (2026-10-08, D412)

You asked for A ("I did notice some clashes between A and C"), so every
drop-2 sting, the short pick reveal and the three procs cut from them were
shifted −3 semitones (C major → A major, E minor → C# minor), length kept.
Your C files are kept as `<name>_c`, and `BWSfx.STING_KEY = "C"` brings
them back. New stings: A major / F# minor will sit with the loops. Details
are in AUDIO.md, "Stings retuned to A". The music also fades out under
every sting now and back in after it (D411).

## Placeholders in the game now: replace me (2026-10-07, D392–D393)

These all play, but they're ours: procedural, or cut from your drop-2 files,
the no-snare kick and the Low fish takes. Each one is named `ph_*` in
`game/audio/sfx/`. Send a WAV under the name on the left (any length) and
I'll trim it, level it and move the hook over. Details are in AUDIO.md,
"Drop 2 cuts + placeholders".

- [ ] **replace me**: `sfx_swap_holster` / `sfx_swap_draw` (now `ph_swap_holster`, `ph_swap_draw`)
- [ ] **replace me**: `sfx_proc_onkill` (now `ph_proc_onkill`: your "cursed or bad" hit (in A), a kick and a low bell)
- [ ] **replace me**: `sfx_proc_heal` (now `ph_proc_heal`: your level-up's first two notes (in A), an octave up)
- [ ] **replace me**: `sfx_proc_pity` (now `ph_proc_pity`: your shop purchase's first pluck (in A))
- [ ] **replace me**: `sfx_immune` (now `ph_immune`, a dull clank)
- [ ] **replace me**: `sfx_obelisk_push` / `sfx_obelisk_pull` (now `ph_obelisk_push`, `ph_obelisk_pull`)
- [ ] **replace me**: `sfx_colossus_step` / `sfx_colossus_thrust` (now `ph_colossus_step`, `ph_colossus_thrust`)
- [ ] **replace me**: `sfx_horde_shuffle` (now `ph_horde_shuffle`, a 3 s loop; send a loop that meets itself)
- [ ] **replace me**: `sfx_being_hum` (now `ph_being_hum`, a 4 s loop from your Low fish takes)
- [ ] **replace me**: `sfx_blank_step` (now `ph_blank_step`)
- [ ] **replace me**: `sfx_cast_fire|water|ice|thunder|wind|light|dark` (now `ph_cast_*`, the big-cast releases)
- [ ] **replace me**: `sfx_fan_knives`, Fan of Knives' whoosh (now `ph_fan_knives`; a new ask)
- [x] A shorter pick-reveal take: **cut from yours** (`sting_pick_short`, 2.27 s, faded out).
  A purpose-made 1–2 s take would still beat a cut. The 7 s one stays available.

Tonight's best order, by how often they're heard: the 7 cast releases, the
swap draw, on-kill and immune, then the encounter sounds.

## Music cues (loops)
- `music_rooms.wav`: the room-choice screen. A short, tense "choose your door" loop that can sit on top of the hall's tempo.
- `music_picks.wav` (optional): the perk and skill pick screen, a light reward sting or a short loop.
- `music_encounter.wav` (optional): one shared variant for special encounters (Horde, Colossus, Blanks, Beings), or one per encounter if you're inspired.
- `music_tutorial.wav` (optional): a calm version of the main loop.

## Stingers (one-shots, 1–3 s)
- `sting_level_up.wav`: a level up on the results screen, played once per unit.
- `sting_victory.wav` and `sting_defeat.wav`: the end of a fight, before the summary.
- `sting_pick_reveal.wav`: the two cards flip in on a perk or skill pick.
- `sting_room_hard.wav`: you choose a Hard room.
- `sting_jackpot.wav`: Wander's "being of unlimited benevolence" white-out.

## Shop and items
- `sfx_scroll_buy.wav`: buying an imbuement scroll (paper and a seal).
- `sfx_scroll_apply.wav`: applying a scroll to an item (a magical overwrite).
- `sfx_trade.wav`: an equipment trade.
- `sfx_cursed_equip.wav`: equipping a cursed item; it should feel like something's wrong.

## Combat
- `sfx_swap_holster.wav` and `sfx_swap_draw.wav`: the weapon swap (one sheathe, one draw).
- `sfx_proc_onkill.wav`: on-kill enchantments firing (Death Knell, Relentless, Wake of Ash).
- `sfx_proc_heal.wav`: lifesteal and recovery procs.
- `sfx_proc_pity.wav`: RNG forgiveness firing (Steady Hand, Follow-Through, Graze).
- `sfx_immune.wav`: a hit landing on an immune target (Blank or Elemental Being), a dull clank or a hollow whoosh.
- `sfx_obelisk_push.wav` and `sfx_obelisk_pull.wav`: the obelisk pulses (they currently borrow pitched SFX).
- `sfx_colossus_step.wav` and `sfx_colossus_thrust.wav`: heavy footfalls and the big spear lunge.
- `sfx_horde_shuffle.wav`: a crowd of feet, looped quietly while the Horde moves.
- `sfx_being_hum.wav`: an Elemental Being's idle hum, a quiet loop.
- `sfx_blank_step.wav`: an eerie, precise footstep.
- Element releases for big casts (they currently reuse the tile sounds): `sfx_cast_fire|water|ice|thunder|wind|light|dark.wav`.

## UI
- `ui_card_hover.wav`, `ui_card_pick.wav`: pick, room and Branch out cards.
- `ui_tutorial_step.wav`: the tutorial advances a step.
- `ui_kanji_toggle.wav` (optional): the accessibility toggle.

If you only make a few, start with: `music_rooms`, `sting_level_up`,
`sfx_swap_draw`, `sfx_proc_onkill`, `sfx_immune` and the 7 cast releases.
