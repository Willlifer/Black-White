# Weather (D249–D254)

A **modifier tag** on rooms, not a room of its own (EXPANSION §2). It
multiplies what's already there: a Horde in a Gale is a new fight.

- **Code:** rules `game/src/core/weather.gd` (`BWWeather`), the view
  `game/src/game/combat/weather_view.gd` (`BWWeatherView`), the icon and room-card
  line `game/src/game/weather_icon.gd` (`BWWeatherIcon`).
- **Tests:** `game/tests/test_weather.gd`.
- **Renders:** `design/art/weather_<kind>.png` (`tools/weather_shots.gd`) and
  `weather_room.png` (`WEATHER=<kind> FIGHT=5 tools/room_shots.gd`).

## Offers (D249)

- About **25%** of rooms (`BWWeather.RATE`) from **fight 5** on are tagged, each
  room rolled on its own: `hash("weather|seed|fight|room")`. The run's own rng
  doesn't move.
- **Never** on a fight without a room choice, so never on the Obelisks
  (fight 4), the Twins (fight 7, D256) or the Giant. A room flagged `boss` is
  never tagged either.
- The kind is uniform over the five.
- It's stored on the room dict (`room.weather`), so saves, the room log and
  the results report carry it.
- **Room card:** under the title, the icon plus "WEATHER · <name>" and the
  one-line rule. The thumbnail shrinks 60 px to make room for it.
- **Pay:** a **Hard** room with weather gives **+1 drop** (5 at the Hard tier).
  A Standard room with weather pays as usual.

## The tick (D250)

The weather acts **once per cycle**, at the tick, after the tiles' own tick
(decay, grass spread, statics) and any eruptions. `BWWeather.tick` is the
battle's only hook. Each tick emits one `weather` event, which carries the
post-tick state for the plate and the telegraphs.

| Weather | Each tick |
|---|---|
| **Rain** | Bare ground becomes water 1. Fire steps down one (fire 1 goes out). Water 1 stays wet (timer refreshed). Deeper painted water stays. So every hex holds water, and every thunder hit gets its +10% conduction and every blast its +2%: "everything conducts". |
| **Ashfall** | Every unglazed hex at fire 2+ (any origin, including statics and seeds) seeds fire 1 onto each neighbour that can hold charge **except mud**. It follows the grass rule's way: fire 1+ is left alone, wet ground dries a step, markers and glazes are skipped. Seeds are fire 1, so they never spread. |
| **Eclipse** | Every hex steps one toward **dark 1** on the light/dark axis. Light steps down, bare ground turns dark 1, dark 2–3 eases to dark 1. Fire and water are kept. **Light standing heals ×2** (the forecast's ground report too). |
| **Blizzard** | The **4 marked hexes glaze** (2 cycles). Bare ground gets a stasis marker instead (ice on empty ground arms it). Then 4 new marks are picked for the next tick. The first 4 are picked when the fight starts. Marks go to charged hexes first (unglazed, a static is fair game), then bare ground, in seeded order. |
| **Gale** | Every unit is **pushed 1** along the heading. D143 rules: the unit farthest along the heading moves first. Rock or a unit in the way is a **slam** (5% max HP, credited to nobody). The map edge is open air (no slam). Immune displace (the Colossus, Planted, Eye of the Storm) holds. A push is not a move, so it deals no crossing damage. The heading **turns every 3 ticks** to a seeded heading, which is known in advance. |

**Determinism:** every pick is a hash of the fight seed and the tick. The
weather state is a plain Dictionary on the battle (`BWBattle.weather`), so
`clone()` copies it and `simulate()` never touches the real one. Same seed,
same fight, event for event (tested for all five).

## Static and seeded tiles (D251)

Statics (D115) and seeds (D134) are the map, so weather **never paints on a
static hex or an untouched seed**, nor on any authored permanent entry. In
practice:

- **Rain or Eclipse on a static:** nothing. A painted change on it still lasts
  until the tick, then the floor re-forms, rain or not.
- **A seed:** holds through any weather. Only play changes it.
- **As a source:** a static or seeded fire 2+ still drops ash on its ring under
  Ashfall. The ring's seeds are ordinary fire 1, and a seeded neighbour isn't lit.
- **Blizzard may glaze a static** (frozen in time, ELEMENTS §5.5; glazed
  static water is walkable). It never marks a seed.
- **Glazed hexes and markers:** rain and eclipse leave them alone. A propagated
  arrival never fires a marker (§5.3).

## Presentation (D252)

- **Plate** (top left, where the Obelisks' plate goes; the two never share a fight):
  - the icon, the name and the rule
  - the next tick ("after N more turns")
  - **Gale:** the heading arrow on the icon (it turns with the camera), the
    ticks until the wind turns, and a small arrow for the next heading
- **Particles:** one pooled MultiMesh (240 quads, one draw call) on the cast
  VFX's own `vfx_particle` shader.
  - Rain: grey-blue ink streaks.
  - Ashfall: grey flakes and a few embers.
  - Eclipse: rising dark motes and a radial edge vignette (a gradient texture,
    no shader).
  - Blizzard: snow motes and ice shards.
  - Gale: white streaks along the heading that surge on the gust.
- **Telegraphs** use the blast preview's hatching (D160):
  - Blizzard: ice hatching, an ink rim and a "GLAZE" tag on the 4 marks.
  - Ashfall: fire hatching on the hexes about to light (no tags: there are often a dozen).
  - Gale: an ink push arrow per unit, or a bar where the push slams. The
    arrows hide while events replay.
- **Pre-warm (D232):** `BWWeatherView.warm_catalog()` adds the particle node
  and the telegraph material to `BWShaderWarm`.
- **Glossary:** Weather, Rain, Ashfall, Eclipse (weather), Blizzard, Gale
  (weather). "Eclipse" and "Gale" were already terms (Striketwice's reaction,
  wind's marker).

## AI (D253)

`BWWeather.hazard_pct(b, u, hex)` is what the next tick costs a unit standing
there, in % max HP:

- a Blizzard mark: 6 (shatter exposure)
- a hex Ashfall will light: 4
- a Gale push from there that slams: 5, or lands on fire: that fire's stand damage

`BWAI._best_hex` subtracts it, as HP on attack hexes and at 0.3 per % on
approach hexes. That's enough to step off a mark or out of a slam lane
without giving up a hit.

## Balance (D254)

Run `RUNS=12 POLICY=mixed ROOMS=mixed WEATHER=1 campaign_sim`. Every choice
fight from 5 is replayed on a copy in its Standard room: once in clear sky and
once per weather, paired. The sim flags any weather that swings the win rate
by more than 15 points. Results are in LEDGER L-25.
