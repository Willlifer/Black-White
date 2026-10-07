# Picks: element perks and weapon skills

Draft for review. Powers stay in the existing bands (skill 8–14, spell 9–13). ⚠ = riskiest in its section. 🛠 = needs new engine work or a new clip.

## 1. How picks work

**Two options a pick (D174).** Every element or weapon pick shows only **2 options, drawn at random** from what the unit could take: 2 of that element's perks it doesn't own, or 2 from the class's improve / learn pool (fewer only when fewer remain). The draw is seeded from the run seed, the unit and how many picks of that kind it has made, so it is reproducible and the same pick shows the same 2 cards after a reload. AI units and enemies take the first of their 2. Rank 3 still grants all five perks.

**Element perks**
- 5 perks per element: mobility, defence, offence, control, support.
- Affinity rank 1 gives 1 pick, rank 2 a second pick (each from 2 drawn options), and rank 3 unlocks all five.
- Units start at rank 1 in their own element. That first perk is **drawn at random** from all five at run start, with no picker (D233; the hall names it). A newly learned element gives its own first pick (two cards).
- You pick as soon as you earn it, even mid-fight. The perk works from that moment.
- Passives only; some have a once-per-battle trigger. No new buttons.

**Weapon skills**
- Each expertise step (E→D, D→C, C→B, B→A) gives 1 pick, so 4 picks per class.
- A pick either **improves** a skill you know (it gains a "+" rider) or **learns** one of the 5 new skills for that class; 2 of those options are drawn for each pick.
- You equip up to 3 skills before the fight. An Improve earned mid-fight works at once. A skill learned mid-fight can be equipped from the next fight on.

New status (one): **Pinned**: −2 move, until the end of the holder's next turn.

---

## 2. Elements

### Water: depth is terrain
Already chosen; fleshed out here.

**Waterwalking** (mobility). **Current rule (D204): the first water hex you cross each turn costs no move.** (Draft, superseded: water's move penalty doesn't apply to you, and you gain move from the water you start your turn on; then D93: water costs 0 at any level.)
- The first water hex entered each turn costs 0; later ones cost as usual. Spent by a move; back next turn.

**Flow State** (support). You and your allies standing in water are harder to hit.
- +3/+6/+9 avoid on water 1/2/3.

**Current Push** (offence). You hit harder when attacking from a water tile.
- +5/+10/+15% damage from water 1/2/3. Forecast: "Current (Water 2)".

**Tidal Guard** (defence). While you or an ally stand in water 2+, fire barely touches you. Fire painted on that hex bursts as steam.
- Fire hits deal 50%, fire tiles deal 0. Fire paint still steps the water down 1, and foes on the ring take 8% (the steam number).
- ⚠ balance watch: it hard-counters a fire squad. Scope and strength are open question 3.

**Undertow** (control). A foe that ends its turn on water 3 is dragged 1 hex toward the deepest neighbouring water.
- Pull 1. It's displacement, so no crossing damage and no slam. If no neighbour holds water, there's no pull.

### Fire: it spreads, it punishes standing still

**Heat Rush** (mobility). Fire carries you forward.
- You take no fire crossing damage. The first fire hex you enter each turn gives +1 move.

**Ember Skin** (defence). Hitting you while you stand on fire burns the hitter.
- An adjacent foe that hits you takes 2/4/6% (fire tile damage, by your hex's fire level). Your own fire standing damage is halved.

**Kindling** (offence). Burning foes take more from you.
- +5/+10/+15% against a foe standing on fire 1/2/3.

**Wildfire** (control). Your fire spreads off grass too.
- Your fresh fire at 2+ seeds fire 1 onto neutral neighbours on the next tick, once per cast. The grass containment rules still apply (origin flips to "spread").
- ⚠ balance watch: whole maps start to burn.

**Controlled Burn** (support). Fire you laid never hurts your allies.
- Allies take 0 from your fire tiles, standing or crossing (gale copies keep you as the source).

### Ice: lock it, harden it, break it

**Skate** (mobility). Frozen ground is a rink.
- Glazed and stasis hexes always cost 1, even on mud. +1 move when you start on one.

**Rime Armour** (defence). Standing on ice makes you hard to break.
- −10% damage taken on a glazed or stasis hex, and Shatter's +15% doesn't apply to you.

**Fault Lines** (offence). You know exactly where to strike.
- Your Shatter is +30% (base +15%).

**Frostbite** (control). Frozen feet slow a foe down.
- A foe that starts its turn on glaze you laid is Drenched (−1 move; thunder hits on it +20%).

**Hoarfrost** (support). The cold steadies everyone nearby.
- Allies within 2 get +5 resist chance against every element. It stacks with ice rank.
- ⚠ balance watch: the support slot looks weak next to the others here. Raise it to +8 if nobody picks it.

### Thunder: arm it, set it off, chain it

**Bolt Step** (mobility). A detonation launches you.
- After any action that detonates a tile, move 2 more (`move_after_attack`).

**Grounded** (defence). The current passes you by.
- You are never conductive, and detonation splash deals you 0. A blast on your own hex still hurts.

**Overcharge** (offence). Your blasts run hotter.
- Detonations you cause count 1 extra charge point: +4% to the occupant, +2% splash, before the ×1.5 for shatter.
- ⚠ balance watch: it stacks with glaze and water into 40%+ blasts.

**Static Field** (control). Your fuses become traps.
- Fuses you arm last 5 cycles (base 3). A foe that ends its move on one is Staggered.

**Lightning Rod** (support). You take the arc for the team.
- An arc that would hit an ally within 3 of you comes to you instead, at 50%.

### Wind: gust, carry, shift

**Tailwind** (mobility). Wind is always at your back.
- +2 move when starting on a gale marker. After any wind action, move 1 more.

**Eye of the Storm** (defence). Arrows bend around you.
- Immune to displacement. Bow, pistol and thrown attacks on you get −15 hit.

**Gale Force** (offence). Momentum becomes damage.
- +5% per hex you moved this turn, up to +20% (`dmg_per_hex_moved_pct`).

**Gust** (control). Your wind hits shove.
- A foe hit by your wind skill is pushed 1 away. If something stops the push, it slams for 8% (the Charge slam number).
- ⚠ balance watch: it chains with Undertow and fire into the push lanes everyone fears.

**Slipstream** (support). Your team runs in your wake.
- Allies that start their turn within 2 of you get +1 move.

### Dark: conceal and wear down

**Shadowstep** (mobility). Shadows connect.
- Once per turn, from a dark hex, leap to another dark hex within 3 for 1 move, ignoring the path.
- ⚠ balance watch: crosses walls and rock. It may need line of sight.

**Nightborn** (defence). The dark feeds you instead of draining you.
- No dark drain on you (dark 3 or Shrouded). On dark, ranged attacks on you get another −10 hit.

**Ambush** (offence). Strike from cover.
- Attacking from dark 1/2/3: +5/+10/+15 crit.

**Pall** (control). Foes lose sight in your gloom.
- A foe you hit while it stands on dark 2+ is Blinded.

**Cover of Night** (support). Your shadow covers your friends.
- Attacks on allies adjacent to you get −7 hit (as if they stood on dark 1, stacking with the tile).

### Light: heal your own, expose theirs

**Sunpath** (mobility). Light lifts your step.
- +1 move when starting on light, +2 on light 3.

**Radiant Guard** (defence). Your own light no longer gives you away.
- Light's hit bonus doesn't apply to attacks on you. You still heal.
- ⚠ balance watch: it turns light from a trade into a pure buff for you. Watch light mono-squads.

**Judgement** (offence). Nowhere to hide in the light.
- Your attacks on a foe standing on light can't glance.

**Glare** (control). Your light refuses the enemy.
- A foe starting its turn on light you laid isn't healed. On light 2+ it's also Blinded.

**Sanctuary** (support). Your light mends more. Once per battle it answers an emergency.
- Your light heals allies 5/9/14% (base 3/6/9%). Once per battle, when an ally within 3 drops under 35% HP, its hex gains light 2.

---

## 3. Weapons

Format: **Name**, then cooldown · shape · power · clip, then what it does.

### Sword: the duelist who picks the moment
Author's five, with numbers refined.

**Heart Seeker**: cd 2 · adjacent · skill 10 · strike
- +25 crit on this strike.

**Triumph**: once per battle · adjacent · skill 12 ×1.5 · strike (held windup)
- If it KOs the foe, you get +25% STR for the rest of the battle.
- ⚠ balance watch: snowballs late, when STR is high. Consider a flat +4 STR instead.

**Whirlwind Blade**: cd 3 · radius 1 (self) · skill 9 to each foe · 🛠 spin clip
- Paints 1 step of an element you have affinity in on the ring.

**Lunge**: cd 2 · line 3 · skill 11 · lunge (Vault's leap)
- Dash straight, stopping at the first unit. A foe takes the hit. An ally just stops you.

**Elemental Truth**: cd 4 · adjacent · skill 10 ×1.5 · strike
- Applies the element twice to the target hex:
  - axis element: +2 steps
  - thunder: detonate, then re-arm a fuse (the foe stays conductive)
  - ice: glaze for 4 cycles
  - wind: gale copies last 2 cycles
- ⚠ balance watch: thunder's detonate-then-fuse feeds chain arcs every turn after.

Improve:
- **Riposte+**: answers the first two blows, both halved.
- **Striketwice+**: if both cuts land, a third cut hits any adjacent foe at 50%.

### Axe: slow, heavy, breaks lines

**Reckless Swing**: cd 1 · adjacent · skill 14 · strike
- You are Scorched (attacks on you +10%) until your next turn.

**Hook**: cd 2 · range 2, single · skill 9 · strike
- Pull the foe 1 to adjacent, onto whatever ground is there.

**Sunder**: cd 3 · adjacent · skill 13 · strike (axe)
- Ignores 30% of DEF (`def_ignore`), and it can't glance.

**Earthsplitter**: cd 4 · line 3 · skill 11 to each foe · strike (overhead)
- Paints 1 step down the line.

**War Cry**: once per battle · radius 2 (self) · no damage · cheer
- Foes in range are Staggered.
- ⚠ balance watch: −15 hit on up to 3 foes for a turn can swing a 3v3 outright.

Improve:
- **Cleave+**: +15% per extra foe (base +10%).
- **Charge+**: reach 4, and the slam is 12%.

### Lance: reach, lines, holding ground

**Skewer**: cd 2 · line 2 (reach) · skill 12 · strike (spear)
- The first foe is pushed 1 back. If something stops it, it slams for 8%.

**Sweep**: cd 3 · the 3 hexes at reach 2 ahead · skill 9 each · strike
- Paints 1 step on the arc.

**Set Spear**: cd 3 · self, free · skill 10 · block → strike · 🛠 move-interrupt hook
- The first foe to enter your reach before your next turn is struck, and its move ends there.
- ⚠ balance watch: it locks down melee AI. It also needs a "unit entered hex" trigger.

**Phalanx**: cd 4 · self + adjacent allies · no damage · block
- −15% damage taken for you and adjacent allies until your next turn. You can't be displaced.

**Dragoon Dive**: once per battle · leap up to 4, radius 1 on landing · skill 13 · leap (Vault)
- Paints the landing ring 1 step.

Improve:
- **Tridentpierce+**: the pierce carries on to a third foe in line.
- **Vault+**: leap 3, and the momentum is +35%.

### Bow: distance, height, picking targets

**Aimed Shot**: cd 2 · range 8, single · skill 13 · shot (held draw)
- +20 hit. +10 crit if you haven't moved.

**Split Arrow**: cd 2 · fan of 3 headings, range 5 · 60% each · shot
- Uses `multi_hit` with the fan pattern. Each arrow is rolled.

**Retreating Shot**: cd 2 · range 5, single · skill 10 · shot
- Then move 2 (`move_after_attack`).

**Pinning Shot**: cd 3 · range 6, single · skill 10 · shot
- The target is Pinned (the new status).

**Rain of Arrows**: once per battle · radius 2 at range 6 · skill 9 to each foe · shot (aimed up)
- Paints 1 step on all 19 hexes.
- ⚠ balance watch: painting 19 hexes reshapes the board. Maybe paint only the centre 7.

Improve:
- **Arcing Shot+**: the wider blast needs only 1 level of height.
- **Energized Shot+**: the pierce deals 80% and reaches 5.

### Staff: depth, rewriting the ground

**Bolt**: cd 1 · range 4, single · spell 10 · cast
- +20% if the target's hex carries your element.

**Transfer**: cd 3 · two hexes within 4 · no damage · channel
- Lift one hex's whole charge (or marker) and set it down on another, empty hex. Then a follow-up basic.

**Inversion**: cd 3 · one hex within 4 · no damage · channel
- Flip the axes: fire 3 becomes water 3, dark 2 becomes light 2. Fuse and gale swap places, and stasis stays. Then a follow-up basic.
- ⚠ balance watch: it turns an enemy's fire-3 trap into your water 3 for one action.

**Aegis**: cd 4 · one ally within 4 · no damage · cast
- The ally takes −20% damage until the end of its next turn (the `guard` key, given to an ally).

**Tempest**: once per battle · radius 2 at range 4 · spell 9 to each foe · cast (long)
- Paints 1 step on all 19 hexes.

Improve:
- **Surge+**: the centre takes +50%.
- **Saturate+**: the status also lands when the pour ends at 2.
- **Ley Line+**: length 6.
- **Siphon+**: heals 6% per step, to you or an ally on the hex.

### Daggers: speed, angles, finishing

**Tumble**: cd 1 · self, free · no damage · run
- After attacking, move 2.

**Twist the Knife**: cd 2 · adjacent · skill 9 · strike (pair)
- +10% for each status on the target, and +10% if it stands on any charge. The maximum is +60%.

**Hamstring**: cd 3 · adjacent · skill 8 · strike
- The target is Pinned.

**Fan of Knives**: cd 3 · radius 1 (self) · skill 8 each · 🛠 spin clip (shared with Whirlwind Blade)
- Paints the ring 1 step.

**Assassinate**: once per battle · adjacent, from behind only · skill 12 · strike
- Can't glance, +25 crit, and backstab +50%.
- ⚠ balance watch: it stacks to ~2.7× on a crit.; watch it vs the boss.

Improve:
- **Daggerleap+**: the backstab is +75%.
- **Dualthrow+**: the bounce goes twice (75%, then 50%).
- **Consume+**: heals 7% per point.

### Pistols: rounds, tempo, close range

**Point Blank**: cd 2 · adjacent · skill 13 · shot
- +20%, and the target is pushed 1.

**Pistol Whip**: cd 2 · adjacent · skill 9 · 🛠 new melee clip for the pistol set
- The target is Staggered, and Quick Shot is ready again.

**Flash Round**: cd 3 · range 5, single · skill 8 · shot
- The target is Blinded. It lays the loaded trail.

**Covering Fire**: cd 3 · self, radius 3 · weapon basic · shot · 🛠 "ally attacked" trigger
- The first foe to attack an ally within 3 before your next turn is shot.

**Empty the Chamber**: once per battle · up to 4 foes in range 5 · 4 shots at 35% of skill 12 · shot (fan loop)
- Each shot is rolled and lays the loaded trail.
- ⚠ balance watch: with a thunder round, 4 Sparks plus conduction is a lot of arcs.

Improve:
- **Quick Shot+**: fan three times if you haven't moved.
- **Reload+**: seats two rounds, so two trailed shots.

### Fists: combos, shoves, pouring

**Shockwave Palm**: cd 3 · line 3 · skill 9 each · strike_palm
- Pushes each foe 1 and paints 1 step on the line.

**Brace**: cd 3 · self, free · no damage · block
- −25% damage taken until your next turn, and your next Flurry gets +1 strike.

**Grapple Throw**: cd 3 · adjacent · skill 9 · strike_uppercut · 🛠 set-position displacement
- Throw the foe to any free hex next to you. +50% if it lands on charge you laid.

**Haymaker**: cd 4 · adjacent · skill 14 · strike_uppercut (held windup)
- +25 crit if you haven't moved.

**Hundred Fists**: once per battle · adjacent · 6 strikes at 30% of skill 12 · strike_flurry (looped)
- The last strike pours 2 steps.
- ⚠ balance watch: 6 crit rolls. Check it against Keen and Flair gear.

Improve:
- **Flurry+**: the last strike gets +30 crit (base +15).
- **Uppercut+**: the slam is +75%, and the slammed foe is Staggered.
- **Palm Burst+**: push 2 on a hex that already carried the element.

---

## 4. Open questions

1. **Loadout vs. kit.** Staff (4), daggers (3) and fists (3) already fill or overflow 3 slots. Does the staff drop one at the start? Do Reload and Quick Shot share one slot?
2. **Mid-fight picks for the enemy.** Do enemy units get perks and skills? If so, does the AI pick at once, or are they pre-set per encounter?
3. **Tidal Guard scope.** Should it cover you and allies or only you? Fire at 50% or fully immune, as you wrote?
4. **Ranks after 3.** Rank 3 unlocks all five perks. Do ranks 4 and up give anything element-wise, or only the existing damage and resist growth?
5. **New engine work (🛠).** Approve or swap: Set Spear's movement interrupt, Covering Fire's ally trigger, Grapple Throw's free placement, one spin clip, one pistol-whip clip, and the Pinned status.
6. **Improve twice?** Can a skill take a second Improve (a "++"), or is it one rider per skill?
