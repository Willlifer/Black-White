# Passives v2: fewer, bigger, set bonuses

**Status (2026-10-07, later):** the perks (4 per element, the held rows folded in) and the **element** sets of §3 are built (D281–D283, re-cut by ELEMENTS-v3 §10: the water 3-piece is Breakwater; the counts and UI as §3 says); family sets are not. Earlier: the non-element consolidation of §2 is in data and code (D243–D248): enchantments 139 → 97 (the 83 approved, plus 14 rows held for the element pass, listed in D246), abilities 46 → 25, save v10. The perks, the element sets, the family sets and the moves "into perks" / "→ set" wait for the element-identity rework. The "On kill (9 → 5)" line lists six survivors, so the total is 83, not 82.

**Draft for review.** Nothing else is in data or code yet. Where `PICKS.md` is stale, the CSVs win. There's no overlay and no board counters: everything new lives on the item card, in the forecast, and in the existing `enchant` float.

## 1. Diagnosis

- **Too many small always-on numbers.** A unit carries about 12 passives, mostly +5 avoid, +5 crit, +1 stat or −10%. No single one is felt.
- **Same effect, several sources.** "+5% per hex moved" is Gale Force, Stampeding *and* Jousting. Banner = Royal Presence, and Rooted = Unbowed.
- **No build decisions.** Rows don't add up to anything, so any item is about as good as any other.
- **Two rows break house rules:** Eye of the Storm (−15 hit) and Cover of Night (−7 hit).

## 2. Consolidation

A merged row keeps the **union of its sources' items and slots**, so no piece loses an ability or roll pool. "→ set" means it's folded into a set bonus (§3).

### Perks: 35 → 28 (4 per element)

Slots: **mobility / guard (defence + support) / offence / control**. Rank 1 and rank 2 are each a pick of 2; rank 3 grants all 4.

- **Water.** Waterwalking + Wading + Drift → **Waterwalking**: water never slows you, and the first water hex each turn gives +1 move. · Flow State + Tidal Guard → **Tidal Guard**: you and allies on water get +15 glance per level. · Current Push + Tidewalker → **Current Push**: +8% per level from water, and from water 3 your hit pushes 1. · **Undertow**.
- **Fire.** Heat Rush + Coal Engine → **Heat Rush**: no crossing damage, and you and allies starting on fire get +1 move per level. · **Ember Skin**. · Kindling + Forge → **Kindling**: +6% per level, and at fire 3 your hits can't glance. · **Wildfire**.
- **Ice.** **Skate**. · Rime Armour + Permafrost → **Rime Armour**: you and allies on your glaze take 15% less. · Fault Lines + Shattering → **Fault Lines**: your Shatter is ×2. · Frostbite + Cold Snap → **Frostbite**: glazing a foe's hex Pins it, and starting there Drenches it. *(Frost Ward → set.)*
- **Thunder.** **Bolt Step**. · Grounded + Lightning Rod → **Lightning Rod**: arcs at allies within 3 hit you instead, and arcs and splash deal you half. · Overcharge + Overloading → **Overcharge**: a second arc at 50%, and detonations +5% per charge point. · **Static Field**.
- **Wind.** Tailwind + Slipstream → **Tailwind**: +2 move starting on a gale, and allies starting within 2 of you get +1 move. · **Eye of the Storm**, fixed: immune to displacement, and ranged attacks on you can't crit. · Gale Force + Gust → **Gale Force**: after moving 4+ hexes, your next hit is +20% and shoves 1.
- **Dark.** **Shadowstep**. · Nightborn + Cover of Night → **Nightborn**: no dark drain, and you and adjacent allies on dark negate the first elemental effect each turn. · Ambush + Nightfall → **Ambush**: +6 crit per level, and your first attack from dark 3 each battle crits. · **Pall**.
- **Light.** **Sunpath**. · Sanctuary + Radiant Guard → **Sanctuary**: your light heals 5/9/14%, light's hit bonus spares you and allies on it, and the once-a-battle emergency light stays. · Judgement + Beacon → **Judgement**: foes on light can't glance, and allies starting on your light get +5 crit per level. · **Glare**.

### Enchantments: 139 → 82

**Elemental (52 → 26).**
- Kindled + Smouldering → **Kindled**. Abyssal + Umbral → **Abyssal**. Dawning + Hallowed → **Dawning**. Brimming + Deepwater → **Brimming**. Glacial + Frozen → **Glacial**. Gusting + Lingering → **Gusting**. Arcing + Jolting → **Arcing**. Conductor's + Sapping → **Conductor's**.
- Fireproof + Grounded + Windbreak + Nightforged + Stubborn → **Warded**. Its element is rolled on drop: 25% less from that element and its tiles, plus Advantage on resisting it.
- Blazing, Riptide, Shrouded, Sunlit and Rimed → set.
- Into perks: Tidewalker, Forge, Overloading, Permafrost, Cold Snap, Nightfall, Beacon, Shattering, Wading. Resonant → Conducting. Whistling is cut.
- **Kept (17):** Explosive, Emberstep, Tidal, Soaking, Geyser, Frostbitten (now "the first basic each turn glazes", no 50% roll), Thundering, Stormcaller's, Static, Howling, Windrider, Shadowtrail, Gloaming, Collapsing, Radiant, Gleaming, Flaring.

**Weapon (22 → 18).** Keen + Serrated → **Keen** (+10 crit, crits ×2). Longshot + Piercing → **Longshot**. Cleaving + Channelling → **Cleaving** (basic and AoE +1 ring). Impact + Hooking → **Forceful** (push *or* pull 1, your choice on the forecast). Jousting + Stampeding → **Jousting**. Conducting + Resonant → **Conducting** (+5% per charge level, up to +25%).

**On kill (9 → 5).** Wake ×4 → **Wake** (paints your attuned element). Pursuit + Tag Team → **Pursuit** (your KO, or one within 2: +2 move). Feasting + Inspiring → **Feasting** (you heal 15%; allies within 2 heal 8%). Relentless, Death Knell and Rallying stay.

**Recovery (9 → 2).** Hearthbound ×4 and Second Breath are cut (3–4% heals). Parrying → Guarding. Leeching and Mend-Linked stay.

**RNG (8 → 5).** Steady + Grazing + Rerouted → **Steady**: a miss still deals 25% and lays 1 step, and your next attack can't be avoided. Follow-Through, Pressing, Second Opinion and Second Chance stay.

**Momentum (8 → 6).** Shieldwall + Lockstep → **Lockstep**: per adjacent ally (up to 3), both of you take 5% less and deal 5% more. Disengaging + Evasive Roll → **Disengaging**: hit *or* missed in melee, step 1. High Ground → Dragoon's Descent. Kiting, Flanking, Lone Wolf and Planted stay.

**Defensive (8 → 5).** Vengeful → Heavy Is the Head. Furious → Bloodied. Last Stand, Thorned, Unshaken, Bulwark and Undying stay.

**Cursed (10 → 10).** All stay.

**Team (13 → 5).** Banner → Royal Presence. Bodyguard + Lifeline → **Bodyguard's** (swap for 1 move; once a battle, an auto-swap at 25%). Rally Cry + Sheltering → **Sheltering**. Relay and Tending are cut. Covering, Spotter's and Pincer stay.

### Abilities: 46 → 25

**Reactive (12 → 6): stacks become thresholds.**
- Enrage + Bloodied → **Bloodied**: the first time below 50%, +25% STR and +1 move.
- Light Footed + Second Wind → **Second Wind**: the first time below 50%, +2 SPD and +2 move.
- Ward + Iron Wall + Brace → **Iron Wall**: after the 3rd hit on you, take 20% less for the battle.
- Poise + Tumble → **Poise**: after an avoid, your next attack gets +25 crit.
- Encore + Crowd Pleaser → **Crowd Pleaser**: each KO gives +15% STR and DEF (up to 2).
- Heavy Is the Head + Vengeful → **Heavy Is the Head**: an ally's KO gives +20% WIL and RES, and your next attack is +50% and sure.

**Supportive (11 → 7).** Guardian + Ring Guard → **Guardian** (adjacent allies take 10% less). Mana Veil + Grace + Keep Warm → **Mana Veil** (adjacent allies get Advantage on element resists). Scout's Lead + Heads Up → **Scout's Lead** (allies within 2 get +1 move). Deadeye + Fletcher's Eye → **Deadeye** (+5 hit and +3 crit per hex of distance). Royal Presence, Unflinching and Imbued stay.

**Passive (23 → 12).**
- Unbowed + Rooted → **Unbowed**.
- Flair + Arena Born → **Flair**: your first attack each battle crits.
- Supple + Acrobat → **Acrobat**: the first attack on you each battle misses.
- Leap Ready + Flutter → **Leap Ready**.
- Bastion + Woven Rings + Shoulder Check → **Bastion**.
- Steel Under Cloth + Nimble Strength + Insight → **Crosstrained**: 25% of your 2nd-best stat adds to your best.
- Visor + Hardened → **Hardened**: crits and skills on you deal 15% less.
- Sure Stride + Drift → **Sure Stride**.
- Kept: Dragoon's Descent (now +8 crit per level), Attuned, Quick Draw, Ammo Belt.

## 3. Set bonuses

**What counts:** head, chest, legs, and the **drawn** weapon.

- An armour piece counts toward its row's **element** (its colour) *or* its **family**.
- The drawn weapon counts twice: its **imbue** toward that element, and its own enchantment toward its family. That's the weapon + armour synergy.
- The carried weapon counts for nothing (D180). A swap updates the count at once. A once-a-battle bonus that fired stays spent, and swapping doesn't re-arm it.
- Scrolls (D203) are how you chase a set, so sets add choice, not more rolls.
- There are 2-piece and 3-piece tiers only. A 4th piece adds nothing, so no set eats the whole kit.

### Element sets (each sleeps until the element is learned)

| Set | 2 pieces | 3 pieces |
|---|---|---|
| **Fire** | On fire: +10% STR per level. Free fire crossing. | **Flashpoint**: once a battle, at <50% your hex and ring go to fire 3 and you heal 20%. |
| **Water** | On water: +10% DEX per level. | **Riptide**: once a battle, an adjacent foe that hits you is swept 2 and Drenched. |
| **Ice** | On glaze: +20% DEF. Glazes last +1. | **Frost Ward**: each turn the nearest unwarded ally within 2 negates its next elemental effect. |
| **Thunder** | Detonations +10%. Arcs and splash deal you half. | **Stormfront**: your first detonation each turn arcs to every conductive foe. |
| **Wind** | +1 move. Your gales never push you. | **Slipstream**: after moving 4+ hexes, your attack can't be avoided. |
| **Dark** | On dark: +10% SPD per level. No drain. | **Vanish**: once a battle, on dark, a hit worth 25%+ of your HP misses, and you shift to dark within 3. |
| **Light** | On light: +10% WIL per level. Light heals +3%. | **Dawnward**: once a battle, an ally within 3 who would be KO'd stays at 1 HP on light 3. |

### Family sets

| Set | 2 pieces | 3 pieces |
|---|---|---|
| **Momentum** | +1 move. | Moving 4+ hexes: +25% on the attack, then step 1. |
| **Bulwark** (Defensive + Recovery) | Take 10% less. | Once a battle, at <25%, a 50% guard until your next turn. |
| **Hunter** (On kill) | A KO takes 1 turn off every skill cooldown. | After a KO, your next attack crits. |
| **Fortune** (RNG) | Once a battle, re-roll one of your own rolls after seeing it. | Also once a battle, re-roll a foe's roll against you. |
| **Company** (Team) | Allies starting their turn within 2 of you get +10% damage. | Once a battle, take an ally's KO blow for it, at 50%. |
| **Damned** (Cursed) | Curse costs are halved. | +20% damage and +10 crit below 50% HP. |

### On the card

One dim line under the passive, only on set items:

> Set: Fire 2/3 · next: Flashpoint

- Shop, loot and scroll cards show the count as if equipped: "Fire → 2/3".
- The gear panel shows one line of active sets.
- In battle, the 2-piece numbers are forecast lines ("Fire set: +4 STR"), and a 3-piece trigger floats once. Nothing goes on the board.

## 4. Identity

- **Water, the anchor:** it holds the shallows, glances blows, and drags foes into the deep.
- **Fire, the aggressor:** it feeds on its own blaze, and is most dangerous when it's burning down.
- **Ice, the warden:** it locks ground, shelters allies on its glaze, and shatters for the kill.
- **Thunder, the trap-setter:** it arms, waits and chains, and takes the arcs for the team.
- **Wind, the skirmisher:** speed is its damage. It can't be moved, and it can't miss after a long run.
- **Dark, the assassin:** it crits from cover, steps between shadows, and slips the killing blow.
- **Light, the medic-judge:** it heals its own, strips foes' glances, and denies one death a battle.

## 5. Open questions

1. **4 perks or 5?** *Rec: 4.* Each pick still offers 2 cards, and every survivor is meatier.
2. **Does a row count toward both its element and its family** (e.g. Pyre: fire *and* cursed)? *Rec: yes.* It rewards scroll planning.
3. **Fortune needs a re-roll prompt** (new UI). *Rec: approve it.* It's one yes/no after a miss or glance, auto-declined in autoplay, and it's pure randomness-with-agency.
4. **Old saves.** *Rec:* map merged ids to their target, re-roll pure cuts within the same family and tier, and bump the save version.
5. **3-piece balance.** *Rec: ship as written and run `campaign_sim`.* Watch Flashpoint, Dawnward and Stormfront.
