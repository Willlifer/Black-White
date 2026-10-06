# Audio needs: systems added after Phase 6

These are the sounds and cues the new systems currently lack or borrow.
Drop WAVs into `Black White\Audio Drops\`, named as listed, and I'll wire,
trim and level them. Any length is fine; I'll measure the onsets the same
way the barks were measured.

**Format:** WAV, 44.1 or 48 kHz, mono is fine for SFX. Music loops should
start and end on the bar so they loop cleanly; send stems if you have them,
as with the original loops.

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
