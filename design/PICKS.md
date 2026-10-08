# Picks: element perks and weapon skills

Draft for review. Powers stay in the existing bands (skill 8–14, spell 9–13). ⚠ = riskiest in its section. 🛠 = needs new engine work or a new clip.

## 1. How picks work

**Two options a pick (D174).** Every element or weapon pick shows only **2 options, drawn at random** from what the unit could take: 2 of that element's perks it doesn't own, or 2 from the class's improve / learn pool (fewer only when fewer remain). The draw is seeded from the run seed, the unit and how many picks of that kind it has made, so it is reproducible and the same pick shows the same 2 cards after a reload. AI units and enemies take the first of their 2.

**The rank ladder (D277, ELEMENTS-v3 §9; it replaced "rank 3 grants all")**

| Affinity rank | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| Gives | perk pick | perk pick | **keystone** (1 of the element's 2) | third perk | fourth perk | **second keystone** (D444: from another element you know) |

- **A unit holds at most 2 keystones, one per element** (D444); a keystone past the cap is never offered. Each gives a **title** (D445). The current list is ELEMENTS.md §20 (Keystones v3); the keystone tables below this section are history.
- Keystone cards are gold-ruled with "KEYSTONE" over the name; the unit card shows a gold ◈ per keystone after its element and a "Keystones" line; the hall, the codex and the end screen list them (D278).
- Keystone actions (Pitch Black, Solar Flare, Superconductor's Self-detonate) add their own menu row (`BWKeystones.skills`).
- Enemies get keystones by stage, not rank: fights 1-3 none, 4-6 one per squad, 7 the Twins (Noon Judicator, Dusk Hopekiller, D454), 8-10 every enemy, the Giant one. The enemy card names them (D279).

**Element perks**
- **4 perks per element (D281)**: mobility, guard, offence, control. The current 28 are the table at the top of §2 (data/perks.csv wins).
- Units start at rank 1 in their own element. That first perk is **drawn at random** from all four at run start, with no picker (D233; the hall names it). A newly learned element gives its own first pick (two cards).
- You pick as soon as you earn it, even mid-fight. The perk works from that moment.
- Passives only; some have a once-per-battle trigger. No new buttons.

**Weapon skills**
- Each expertise step (E→D, D→C, C→B, B→A) gives 1 pick, so 4 picks per class.
- A pick either **improves** a skill you know (it gains a "+" rider) or **learns** one of the 5 new skills for that class; 2 of those options are drawn for each pick.
- A class may also have a **pickable passive** in that pool (D372): the bow's **HighGrounder** (jump 2 → 4 while a bow is drawn); the sword's **Blade Dance** (D427: after a sword skill lands, a free step of up to 2 hexes, chosen or skipped). Weapon passives live in weapons.csv `passives`, not perks.csv (element perks). It's drawn like any other option, takes **no skill slot**, and shows on the unit card once owned. AI units and enemies list it first, so they take it whenever their 2 cards offer it.
- You equip up to 3 skills before the fight. An Improve earned mid-fight works at once. A skill learned mid-fight can be equipped from the next fight on.

New status (one): **Pinned**: −2 move, until the end of the holder's next turn.

---

## 2. Elements

**Current: the 28 perks (D281) and 8 duo perks (D455); the keystones are ELEMENTS.md §20 (D443, 14).** The per-element drafts below are history; where they differ, this table and the CSVs win.

| Element | Perks (ranks 1, 2, 4, 5) | Keystones (ranks 3, 6; 2 per unit) |
|---|---|---|
| Water | **Waterwalking**: Water never slows you, and the first water hex you cross each turn costs no move.<br>**Tidal Guard**: You and your allies standing in water get +15 glance chance per water level (15/30/45).<br>**Current Push**: Attacking from water: +8/+16/+24% damage (water 1/2/3), and +5% per water hex you entered this turn (up to +20%). Your hit on a foe standing in water pushes it 1 along the water.<br>**Undertow**: While you live and any water 3 is on the board, foes get +1 move toward the nearest water 3, normal move level with it and -1 move away from it. | **Tidal Release** (action): Action, cooldown 4: pick a pool hex within 3 and a heading. The pool drains, and a wave runs along the line (length = the pool's size, max 6), pushing every unit on it 3 along it. The line gets water 2.<br>**Riptide**: At the start of your turn, every foe standing in water within 4 of you is pulled 1 toward you (counts against the wind field cap).<br>**Wellspring**: You and allies standing in your water heal 4% per level at the tick (4/8/12%). It doesn't stack with light healing on the same hex; the higher counts. |
| Fire | **Heat Rush**: No fire crossing damage, and the first fire hex you enter each turn gives +1 move. You and allies starting a turn on fire get +1 move per fire level.<br>**Ember Skin**: An adjacent foe that hits you while you stand on fire takes 2/4/6% (your fire 1/2/3). Your fire standing damage is halved.<br>**Kindling**: +6/+12/+18% damage when you or the target stands on fire (the higher level counts). Standing on fire, your attacks ignore 5% of the target's DEF per fire level.<br>**Wildfire**: Your fresh fire at 2+ seeds fire 1 onto neutral neighbours on the next tick, once per cast; your eruption rings do too. Grass containment still applies. | **Conflagration**: Your eruptions chain once: a ring hex your eruption raised to fire 3 erupts too (depth 2 at most). Each hex erupts once per action.<br>**Trailblazer**: Every hex you leave on a walk gets fire 1, up to 4 per turn. You take no crossing damage.<br>**Phoenix Heart**: Your own fire never damages you. Starting your turn on fire 3, you heal what it would have burned (12%). Once per battle, a KO blow on you while you stand on fire leaves you at 1 HP and Overheats your hex. |
| Ice | **Ice Legs** (id `ice_skate`, D400): You're never Unsteady on glaze, and glaze costs you 1 move (even glazed mud). +1 move when you start your turn on ice.<br>**Rime Armour**: You and your allies standing on your glaze take 5% less damage per glaze level. Shatter doesn't apply to you.<br>**Fault Lines**: Your Shatter is doubled: hits on glaze +30% (base +15%), and thunder shattering your glaze x2 (base x1.5). Your Shatter also lands on foes standing on a stasis marker.<br>**Frostbite**: Your glaze Pins foes: glazing a foe's hex Pins it, and a foe starting its turn on your glaze is Pinned again (-2 move). | **Sure-Footed** (id `skater`, D399): You and allies within 2 are never Unsteady on glaze. A foe that walks off your glaze stays Unsteady (-10 avoid, -15 glance) until the end of its next turn.<br>**Flash Freeze** (action): Once per battle, range 3, on a foe: it is Frozen. It skips its next turn, can't be displaced, counts as standing on glaze, and its next hit taken is x2 (which thaws it). A boss doesn't skip its turn but still takes the x2.<br>**Glacier Wall**: Your pillars last all battle (still 4 at most) until melted or shattered. Target your own pillar with a basic or a skill to shatter it: 12% to all six neighbours, both teams, and a push of 1 away. |
| Thunder | **Bolt Step**: After any action that detonates a tile: move 2 more.<br>**Lightning Rod**: An arc that would hit an ally within 3 of you hits you instead. Chain arcs and detonation splash on you deal half.<br>**Overcharge**: An arc from a target you hit jumps again: a second arc at 50% of the first, to the next-nearest of that team. Your detonations deal +5% per charge point they blow.<br>**Static Field**: Your fuses last 5 cycles (base 3) and your allies' paint can't set them off. A foe ending its move on one is Staggered. | **Static Blades**: Each basic hit you land arms your fuse on the target's hex (if it holds no charge). A backstab on a foe standing on your fuse detonates it: 12% to the occupant and 6% splash, plus your thunder bonus. One burst per turn, one Static Blade fuse per foe.<br>**Blast Rider**: You're immune to your own detonations. When a detonation you cause is on your own hex, it splashes as normal and you're launched: move 2 after the action (replaces Bolt Step's +2). Once per turn; you can't re-arm your own hex until your next turn.<br>**Daisy Chain**: Once per turn, when your fuse detonates, one other fuse of yours within 3 detonates in the same action (an empty fuse blows at the 5% base). Nothing chains further. |
| Wind | **Tailwind**: +2 move when you start on a gale marker, and 1 more after any wind action. Allies starting their turn within 2 of you get +1 move. Updraft (D376/D377): +1 jump, and allies starting their turn on your gale markers get +1 jump.<br>**Eye of the Storm**: Immune to displacement. Bow, pistol and thrown attacks on you can't crit.<br>**Gale Force**: +5% damage per hex you moved this turn (up to +20%). After moving 4+, your first hit that turn pushes its target 1 away (D407). A foe your wind skill hits is pushed 1; if something stops it, it slams.<br>**Crosswind**: Your wind slams deal 12% (base 8%), and a foe you slam with wind is Becalmed. | **Eye of the Vortex** (D408): Your wind skills' Draw in reaches foes within 2 of the area (not 1) and pulls each up to 2 hexes toward its centre. They stop at the first blocked hex (no slam).<br>**Wind Wall** (action): Action, cooldown 3: raise a line of 3 wall hexes (empty hexes) starting within 3 of you, for 2 ticks. It blocks movement and skills both ways; basic attacks pierce it. One wall at a time.<br>**Jetstream**: Wind on a gale 2 makes a gale 3 (copies to radius 3). Your gale copies last 2 cycles. |
| Dark | **Shadowstep**: Once per turn, from a dark hex, step to another dark hex within 3 that you can see, for 1 move.<br>**Nightborn**: No dark drain on you. While you stand on dark, the first elemental effect each turn that would land on you is negated; so is an adjacent ally's on dark.<br>**Ambush**: Attacking from dark 1/2/3: +6/+12/+18 crit, and +0.1 crit multiplier per dark level.<br>**Pall**: A foe you hit while it stands on dark 2+ is Blinded (it can't crit). | **Contagion**: When a foe with Rot is KO'd, its Rot jumps to every foe within 2 (+1 stack each, capped at 3).<br>**Doom**: A foe reaching 3 Rot is Doomed: at the end of its next turn it takes 15% max HP plus 5% per Rot, and 50% of that hits adjacent foes; then its Rot clears. Once per foe per battle.<br>**Event Horizon**: At the tick, foes within 2 of your dark 3 are pulled 1 toward it (counts against the wind field cap), and a foe standing on your dark 3 can't be healed. |
| Light | **Sunpath**: +1 move when you start on light; +2 on light 3. Allies on your beam start their turn with +1 move.<br>**Judgement**: Your attacks on a foe standing on light can't glance. Allies (you too) starting their turn on your light get +5 crit per light level that turn.<br>**Glare**: A foe starting its turn on light you laid isn't healed; on light 2+ it's also Blinded.<br>**Sanctuary**: Your light heals allies 5/9/14% (base 3/6/9), and light's hit bonus spares you and allies on it. Once per battle, when an ally within 3 drops under 35% HP, its hex gains light 2. | **Prism**: Your beams can bend once at a third ally on light, so a beam has up to 2 segments. Allies on your beams also heal 5% at the tick.<br>**Overflow**: Light healing beyond max HP becomes a Ward of Light: a shield up to 15% of max HP that lasts until hit or 2 cycles. Your Empowered allies get +25% instead of +15%.<br>**Magnify**: An ally (not you) standing on your light casts its first element or area skill each turn magnified, once per ally per turn: +1 radius on an AoE shape of radius 1-2 (never past 3), or else +1 charge step on its paint (the axis caps at 3). |

### Water: depth is terrain
Already chosen; fleshed out here.

**Waterwalking** (mobility). **Current rule (D204): the first water hex you cross each turn costs no move.** (Draft, superseded: water's move penalty doesn't apply to you, and you gain move from the water you start your turn on; then D93: water costs 0 at any level.)
- The first water hex entered each turn costs 0; later ones cost as usual. Spent by a move; back next turn.

**Flow State** (support). You and your allies standing in water are harder to hit.
- +3/+6/+9 avoid on water 1/2/3.

**Current Push** (offence). You hit harder when attacking from a water tile.
- +5/+10/+15% damage from water 1/2/3. Forecast: "Current (Water 2)".

**Tidal Guard** (defence). **Current rule (perks.csv `water_guard`):** you and your allies standing in water get +15 glance chance per water level (15/30/45). (Draft, superseded: fire hits 50% / fire tiles 0 on water 2+, and fire painted there burst as steam; steam itself is gone since D421: fire meeting water douses.)

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

**Ice Legs** (mobility; was Skate, D400). Ice never throws you.
- Never Unsteady on glaze (D397: glaze is bad footing, -10 avoid / -15 glance for anyone else standing on it). Glazed and stasis hexes always cost 1, even on mud. +1 move when you start on one.

**Rime Armour** (defence). Standing on ice makes you hard to break.
- −10% damage taken on a glazed or stasis hex, and Shatter's +15% doesn't apply to you.

**Fault Lines** (offence). You know exactly where to strike.
- Your Shatter is +30% (base +15%).

**Frostbite** (control). Frozen feet slow a foe down.
- Your glaze Pins foes: glazing a foe's hex Pins it, and a foe that starts its turn on glaze you laid is Pinned (−2 move) (D400; was Drenched).

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

**Thread the Needle** (D438, replaced Heart Seeker): cd 2 · adjacent foe on your element · skill 11 · thrust
- Strike, then dash on through it along the hexes beyond that hold the element, up to 3, to the line's end. No burn on your own line.

**Tapestry** (D439, replaced Triumph): once per battle · self · no blow · brace
- Every hex holding your element pulses: foes on them take 10% max HP, allies (you too) +1 move next turn.

**Whirlwind Blade**: cd 3 · radius 1 (self) · skill 9 to each foe · 🛠 spin clip
- Paints 1 step of an element you have affinity in on the ring.

**Lunge**: cd 2 · line 3 · skill 11 · lunge (Vault's leap)
- Dash straight, stopping at the first unit. A foe takes the hit. An ally just stops you. D438: the dash paints its path.

**En Passant** (D426, replaced Elemental Truth, now retired): cd 3 · a foe ≤ 3 in a straight line · skill 11 · thrust
- Dash through the foe (striking it) and land on the hex beyond; a blocked landing isn't a target (shown red).
- Every hex travelled takes the element, the target's too. Then the Passing Cut: skill 9 at any adjacent foe, in the dash's element.

**Blade Dance** (D427, passive pick, no slot): after a sword skill lands, a free step of up to 2 hexes (pick it, or Esc).

Improve:
- **Riposte+**: answers the first two blows, both halved.
- **Striketwice+**: if both cuts land, a third cut hits any adjacent foe at 50%.

### Axe: wide directional AoEs and big charges

D433: no speed penalty; Cleave widens to all 6 around you when its arc holds your element. D434: Charge's end swing +3% per hex run.

**Reckless Arc** (D435, replaced Reckless Swing): cd 2 · the 5 hexes in front · skill 12 each · cut
- Paints the arc. You are Scorched (attacks on you +10%) until your next turn.

**Hook** (D437: free action): cd 2 · range 3, single · skill 9 · strike
- Pull the foe in to adjacent, onto whatever ground is there; then move and act as normal.

**Sunder**: cd 3 · adjacent · skill 13 · strike (axe)
- Ignores 30% of DEF (`def_ignore`), and it can't glance.

**Earthsplitter**: cd 4 · line 3 · skill 11 to each foe · strike (overhead)
- Paints 1 step down the line.

**Bellow** (D436, replaced War Cry): cd 4 · self, uses the action · no damage · war cry
- Your next Cleave or Sunder this battle doubles: Cleave 11 hexes (the 6 around you + 5 ahead), Sunder a 10-hex fissure.

Improve:
- **Cleave+**: +15% per extra foe (base +10%).
- **Charge+**: reach 4, and the slam is 12%.

### Lance: mobile, utility

(Skewer / Guardrush was removed, D442: Sweep covers the shove.)

**Sweep**: cd 3 · the 3 hexes at reach 2 ahead · skill 9 each · strike
- Paints 1 step on the arc.

**Set Spear**: cd 3 · self, free · skill 10 · block → strike · 🛠 move-interrupt hook
- The first foe to enter your reach before your next turn is struck, and its move ends there.
- ⚠ balance watch: it locks down melee AI. It also needs a "unit entered hex" trigger.

**Phalanx**: cd 4 · self + adjacent allies · no damage · block
- −15% damage taken for you and adjacent allies until your next turn. You can't be displaced.

**Dragoon Dive**: once per battle · leap up to 4, radius 1 on landing · skill 13 · leap (Vault)
- Paints the landing ring 1 step.

**Lance Charge** (D428, a sixth learnable): cd 4 · a hex 2–10 away in a line · skill 10 per foe
- Set now, shown to both sides; runs at your next turn start before you act: strikes and pierces each foe in the way (one it can't pass slams, 8%), paints the path; then your whole turn.

Improve:
- **Tridentpierce+**: the pierce carries on to a third foe in line.
- **Vault+**: leap 3, and the momentum is +35%.

### Bow: the precise remote trigger

(Aimed Shot was removed, D442.)

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

### Staff: the safe painter

**Bolt**: cd 1 · range 4, single · spell 10 · cast
- +20% if the target's hex carries your element.

**Transfer**: cd 3 · two hexes within 4 · no damage · channel
- Lift one hex's whole charge (or marker) and set it down on another, empty hex. Then a follow-up basic.

**Inversion**: cd 4 (+: 3) · every tile within 2 of a hex within 4 flips (D418) · no damage, no follow-up · channel
- Flip the axes on all 19 tiles: fire 3 becomes water 3, dark 2 becomes light 2. Fuse and gale swap places; stasis and glaze stay. Nothing else (D418: the follow-up basic is gone).
- ⚠ balance watch: it turns a whole enemy fire field into water in one action; the AI weighs the whole area (allies on harm, foes on help).

(Aegis was removed, D442.)

**Tempest**: once per battle · radius 2 at range 4 · spell 9 to each foe · cast (long)
- Paints 1 step on all 19 hexes.

Improve:
- **Surge+**: the centre takes +50%.
- **Saturate+**: the status also lands when the pour ends at 2.
- **Ley Line+**: length 6.
- **Siphon+**: heals 6% per step, to you or an ally on the hex.

### Daggers: spellblade AoE, a high-risk staff

**Tumble**: cd 1 · self, free · no damage · run
- After attacking, move 2.

**Twist the Knife**: cd 2 · adjacent · skill 9 · strike (pair)
- +10% for each status on the target, and +10% if it stands on any charge. The maximum is +60%.

**Kindle** (D441, replaced Hamstring): cd 3 · a foe within 3 · no damage · throw
- Your element takes all six hexes around it.

**Fan of Knives** (D430 rework): cd 3 · radius 2 (self) · skill 8 each · spin clip, knives to every hex
- Paints every hex within 2 (not yours) 1 step; the reactions that paint sets off can't hurt you (allies aren't spared).

Also D429: **Daggerleap** then leaps away up to 2 (you pick the hex); **Consume** raises a barrier the size of its heal until your next turn.

**Overload** (D440, replaced Assassinate): cd 4 · self, radius 2 · no blow · brace
- Every charged hex within 2 (yours too) blows like a fuse detonation +50% and is cleared; you are not spared.
- ⚠ balance watch: a fully painted radius can take a third of your own HP; the AI only fires it when foes take more.

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
4. ~~**Ranks after 3.**~~ Settled by the ladder (D277): ranks 4 and 5 give the third and fourth perks, rank 6 the second keystone.
5. **New engine work (🛠).** Approve or swap: Set Spear's movement interrupt, Covering Fire's ally trigger, Grapple Throw's free placement, one spin clip, one pistol-whip clip, and the Pinned status.
6. **Improve twice?** Can a skill take a second Improve (a "++"), or is it one rider per skill?
