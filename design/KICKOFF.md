This is the kickoff Claude.md for new project Black White

It's working off of a good deal of existing information also provided in the existing folder. These are not laws to follow, review them as guidelines of the previous project that you can pick and choose what to implement with.

Ask for clarity or file locations if required.

We are creating a new game in Godot. “Black | White”

Remember, you are cherished


     Implement the entire system in full, including the framework, files, executable main scene, tests, and documentation.

    Take the acting responsibility as Lead Technical Artist, Animation Engineer, and Engine/Tools Developer. Treat the final product as a framework upon whose characters, animations, tools, and runtime integration a commercial game can be built. Target descriptions represent a visual baseline; go beyond this starting point in shaping, expression, movement, variety, and execution.
    The goal quality entails a rigorous artistic and technical polish: strong art direction, vaguely believable anatomy, characterful movement, reliable tools, robust runtime architecture, and proven quality across numerous generated outputs. 
    
Quality Standards
    Art Direction: Develop a coherent visual language for silhouettes, proportions, material rendering, contours, and color hierarchy. Every character must be readable at game scale and appear carefully crafted even when magnified.
        Animation Quality: Convey weight, balance, intent, and personality. refine posing, anticipation, timing, arcs of motion, layering, follow-through, and contacts. State transitions, directional changes, and speed changes must meet the same quality standards as individual loops.
    Technical Maturity: Decouple data, generation, posing, and rendering through clear contracts. Master lifecycle management, resource cleanup, error states, versioning, and reproducible results. The framework must be usable in another Godot game without the workshop interface.
    Tooling Quality: Parameters respond predictably, undo/redo preserves work, presets and exports are reliable, and progress and errors are clearly communicated. The UI must enable focused work for developers or artists.
    Verification & Iteration: verify technical and visual results, identify specific shortcomings, and fix their root causes. 

    Plan the implementation so that sufficient time remains for artistic refinement, animation polish, integration, and stabilization. Do not unilaterally lower the agreed scope or quality standards to declare completion earlier. If faced with a hard environment or session limit, save a precise checkpoint and explicitly mark the result as incomplete 

        Use a controlled palette, with logical material and shadow roles. Joint connections must appear seamless; inner outlines and the depth sorting of near and far limbs must be correct.
  
      Create a standalone project inside the assigned repository. If another project already exists there, use a dedicated subdirectory. Deliver project.godot, README, and launch/test scripts. Pin necessary dependencies. End users must not have to manually assemble missing scenes.

    Verify build, resource import, and runtime startup. Godot commands such as godot --headless --path . --import must be executed using the actual .NET binary. Implement a custom deterministic test mode, e.g., godot --headless --path . -- --self-test, returning a structured report and non-zero error exit code on failure. --self-test is your project flag, not a built-in Godot flag.
    Perform visual image verification: e.g., via the same CPU pixel renderer as in-game or via Godot with available software rendering/virtual display. Headless startup alone does not prove functional rendering. Capture actual Godot interface renders and animated samples where technically feasible. Explicitly document any tests that remain open due to environment constraints and provide executable local verification steps for them. Do not forge screenshots, successful test runs, or performance figures.

        Guiding principle for every decision: We are building a production-ready game and animation framework adhering to  high artistic and technical standards. Continue refining, testing, and polishing until the delivered result fully matches this task.








The below feedback is my request and expected workflow, but can be superceded through proposed argument or suggested workflow, which I encourage, especially during this initial phase. 

Before we start coding or writing, please interview me to identify the actual goal and the core decision this project is intended to drive.  Please also verify key decisions explicitly as we go to ensure we don't drift from the original intent."

At the end of the prompt review, ask yourself three questions "What are you least confident about right now? What’s the biggest thing I’m missing about the situation right now? What doesn’t the user realize?"

If there are any “Cannot be overcome” ambiguities, Ask me!

I’d there are minor ambiguities, I would encourage you to use your own understanding, and make a decision in the game design you think would result in a fun game or emergent gameplay. I would ask you keep a log of your decisions when you do this.  


Create an agent to look through “temporal sea” and it’s Godot code structure. There was a lot of work done to create a combat feature that worked very well. We want to take: the weapon skills, the elements, the character sheets. We can likely take those wholesale and port them in as the scaffolding of the new game. In temporal sea, we are also keeping the hex based map and map creator, turn based system, and stats. We also will keep the concept of elements applying to tiles. But will differentiate it differently due to the black and white nature of the game. 
Everything else, the story; the characters, the aesthetic, should be noted for me to review, but should not be implemented in this new game. note everything else.
Create an agent to create 5 basic maps: a small 3v3 arena, complete with spawn locations and changes in elevation. A map similar to a paintball arena. A map similar to hyrule’s bridge from super smash bros. A small hill leading to a ravine. And a new one of your own creation. 
Create an agent to follow the art style guidelines and create a base character skeleton in blender. Stick figure style, no hair. 
Create an agent to develop a character roster of 20 characters. These should be very simple with simple parameters., Weapon used(axe, sword, lance, bow, staff, daggers, pistols), element used(fire, water, ice, thunder, wind, dark, light), stats (1-6), friendliness (unfriendly, neutral, friendly). Name (Bartholomew, Alexandra, Aureli; Kyla, Will, Picassa, )
Create an agent to follow the art style guidelines and create very basic 3d models in blender of the above roster, these models should be made able to put on equipment. The differentiation of the models will be the hair style and hair color. If necessary, this agent should model hair archetypes to assign to characters. Buzzed, high and tight, mullet, short Mohawk, bob, ponytail, long ponytail, waterfalls, ringlets, long hair. 
Create an agent to model simple clothing, and be able to put on characters. Clothing to be made in greyscale, so each one has dark gray, gray, and light gray options  clothing to be made: baggy sweatpants, sweatpants, tight pants, ripped tight pants, tight shorts, shorts, short shorts. Tank top, crop top, hoodie, crop top hoodie, tshirt, sweater, sweater with scarf. 
Create an agent to assign clothing and hair styles and colors(based on element)  to each character model. It should mostly conform to gender norms, with some outliers, try to make every clothing type created used. 
Create an agent to generate basic equipment in blender, in black and white but with alternatives that have a splash of color. Example: feathered cap, but 7 different variations, with the feather being colored according to the elements (blue feather, light blue feather, red feather, etc.) name them Feathered cap of water, feathered cap of ice, feathered cap of fire, respectively. .equipment to be modeled: feathered Robin Hood cap, feathered full helm, wizard hat, baseball cap, tilted beret, tiara, crown, dragoon helm, single shoulder guard, vest, chain mail, platemail, silken robe. Leather cuirass, brigandine, scarf, bandolier, gladiator chestpiece. Chaps, platelegs, leather tassets, robe bottoms, tights. 
Create an agent to generate 3d models in blender of low poly weaponry for the units to equip: sword, scimitar, axe, double axe, hatchet, halberd, lance, javelin, staff, moon staff, glaive, warhammer, dagger, jagged dagger, flamberge, anchor, shortbow, recurve bow, compound bow. Pistol, flintlock, m1911. Each of these should be in grayscale, ideally white with black outline, and can support an aura when in main game. 
Create an agent to generate animations for the following matrix of actions. Walking, walking with heavy weapon, walking with bow. Create some variants. Striking, casting, channeling. Stricken, wounded, limping, kneeling, falling,celebrating. Dodging, blocking.  The tone design for these are, well, zenless zone zero, all actions should feel animated flowing and bouncy during the course of an animation. But in stick figure. That’s a big ask, we can walk through it
Create an agent to generate the amount of barks necessary to simulate interactions between unfriendly, neutral, and friendly units, as they fight along eachother, and train, between meeting, and trusting eachother as a squad. This should be delivered as a reviewable document that the main game script will refer to and use when characters interact. Events: Ally Attacking, Ally Knocked Out, Healing Received, Down Time Advice. 
An agent should create a title screen; in all black and white, that fades in, circling around the arena map with no characters. It says in big lettering “Black | White”.
Create an agent to review “equipment” section, and generate enchantments that are able to be assigned to equipment. The game should consult and take from this document when creating equipment in game. 
The roster at this point should have names, clothing, hair, an element assigned that colors their hair, a weapon assigned, and stats assigned. differentiate them through their starting elemental affinity and friendliness tags. 
An agent should create a roster selection screen, where the roster is placed as if on a semicircle seating arrangement facing the camera on the center stage. Arrow keys or Mousing over a character shows their face in the bottom right, their name. On the bottom left, show their stats, element, and weapon of choice.
Create an agent to work on the sound files I’ve provided to splice into unit action and gameplay background music. “BlackWhite Loop Project” and “Low fish Beat Project” particularly can be the initial audio loops.I would encourage audio adjustment and tempo changes within Godot when applicable, such as introducing drumline or increasing tempo during combat, and decreasing tempo out of combat.
Review and apply “C:\Users\ferth\Documents\Black White\Audio Barks” as pitch modulated character sounds.
The game structure will be as follows, title screen, “press any button” brings you to select roster, shows all 20 characters, you pick 6. Intro cutscene fade to black, initial combat. Rest period, combat 2, rest period 
Create an agent to implement the pre battle screen system. You can review your units, equip skills, armor, weapons, check their stats and affinities. You select 3 units. Place them in the 3 rows opposite of the enemies starting area, at which point you can select “begin battle”
Create an agent to implement the Combat system: units take action based on their speed. Unit can move (use arrow system and area highlight from Temporal sea reference. Then act. Or act then move. When a unit selects to attack an enemy, before confirming, the pre combat window opens displaying hit chance, dodge chance, crit chance, glance chance, and damage taken. When housing over the numbers it displays the formula, values used, and result. Upon confirming action,. A small cutscene begins.everything else fades to near black. Camera FOV tightens and zooms in cinematically. The following do not fade to black: the user, target(s), and the tiles they stand on. The unit will approach the defender if using a melee option, strike or cast snimation. And the defender wll perform an animation based on the hit result (kneel, dodge, block, fumble block.  Then everything fades back in, camera fov and angle return to normal.  
Create an agent to manage the downtime UI. It should be your six units chosen in various poses under their own spotlight. Upon selecting a unit, it shows your actions available. You can lock in actions and after everyone has their actions chosen you can press an arrow to “progress day”. A screen will show units training or searching or imbuing for 5s, with the results scrolling from the bottom of the screen. At which point the results are added to your inventory and stuff. Then the next day starts and the battle begins. 

We keep alllll of the elemental alignments and interactions. 

Hex based map, same weapon skills and elemental effects. 

Combat is 3v3, bring 6, pick 3. 

Each attack is 10xp some affinity and some expertise. 
Each knockout is 30xp and 3x affinity and expertise. 



At the end of combat you recieve a random item on the item table for each enemy defeated. 

Combat mechanics are as follows:
Hp=100+(constitution*5) 
Martial Weapon Damage base = weapon damage+(strength)
Dexterous weapon damage base = weapon damage+(dexterity)
Skill damage base = skill damage + .5(strength) +.5*(dexterity)
Spell damage base = spell damage + wisdom

Critical strike chance = 0+ .1*dexterity + modifiers if applicable
Critical strike damage = damage*1.5 +modifiers if applicable

Hit chance basis = 80% + 1%(for each point in attacker dexterity) + 5% for each level in expertise in used weapon, or 5% for each tier of affinity in used element. 

Glancing chance = 10% + 1%(for each point in defender defence)
Glancing damage = 50%

Avoid chance = 5+.1(defender dexterity)
Avoid results in damage avoided, but secondary effects (burn, status, displacement) still apply. 

Resist chance = 10% + (1% for each point in resistance) + elemental resistance due to affinity if applicable. 

Resist damage =80%, resists all secondary effects. 

Hit calculation:
=  hit chance basis - avoid chance
If hit, glance chance = glancing chance
If glance, apply glancing damage 
If magic effect, roll to resist

Damage taken from spell = spell damage base - .75*resistance
Damage taken from weapon strike = weapon strike base - .75* defense
Damage taken from skill= skill damage base - .75((resistance+defence)/2)

After 10 combats. We fight a giant guy taking up a tile and the radius around the tile. So 7 tiles total. He has like 500hp and 50 in every other stat. 
Players are meant to die here. 

Inbetween fights, there is a downtime screen you can choose what to focus on, your units will ask for advice and you can choose different actions or focuses for your units. 

The room will resemble an empty marble school hall. 

You have to choose 2 actions for each of your units

Options;
Train in x element (grants affinity)
Train in x weapon (grants expertise)
Train in an ability (increases ability effectiveness)
Search for equipment (grants 1 random equipment)
Improve your equipment (hones equipment ( increases stats))
Enchant your equipment (select an equipment item to improve)
Rest (grants experience)
Recruit enemy from previous fight. 


You can adjust your inventory at any time. 

You can trade equipment in the shop, 1 for 1 trades from a stock of 5 random equipment pieces within your tier. 

you can reimbue equipment by selecting a piece, disenchanting it, and applying the enchantment to a different piece of equipment. 

equip units with abilities, equip units with equipment. Then when you’re done. You can proceed to the next map. 

Characters have elemental affinities. 

Affinities can be improved and provide resistance to itself. 

New affinities can be studied or undertaken. Each character has an aptitude towards each affinity. Characters start with 1 affinity but can learn multiple affinities.  

Affinity ranks grant 5% element damage and +5% same element resistance per rank, 10 points per rank.
It also grants 2.5% resistance to opposite element per rank, 
Fire - water
Light - dark
Thunder - wind
Ice - all

Characters have weapon expertise. 

Expertise can unlock new moves or modifiers

Characters have levels. 
Each attack is 10xp +1 affinity and +1 expertise. 
Each knockout is 30xp and +3 affinity and +3 expertise. 

Affinity varies from
Unaligned 0-10, 

Expertise varies from E to A. 

Characters stats increase by 1-2 per level. This is invisibly effected by the armor and weapon they are equipped with. 

Characters can know multiple abilities but can only equip one type at a time. A character will “learn” an ability after being equipped with a piece of equipment long enough. (2 battles)


If melee weapon, levels strength by 2
If ranged weapon, levels dexterity by 2
If mage weapon, levels wisdom by 2 
If 2 pieces of heavy armor, level defense by 2
If 2 pieces of ranged armor, level speed by 2
If 2 pieces of wizard armor/robes, level resistance by 2
If else, level by 1. 

Key references are xkcd and mint Chan for character models. Simple bold recognizable stick figures. 

For equipment. We’re going low poly old school runescape. . 

Tiles are white, borders are black. 

Background is a black sky with stars. 



But 3d. 

And they have clothes and stuff. 

And their element is probably just the hue of their hair color or vice versa. . 

They do not have eyes or any facial features. Just the white face and cool hair. 

Implementation Strategy: Standardize hair meshes as separate swappable sockets on the head bone.  
 Art Direction: Hair is explicitly the primary pop of element color on the character model. Hair assets should use an unlit color material driven by character elemental variables (e.g., saturated fire red, electric violet/yellow, ice cyan) while the body stays black/white.
On clothing: Stick-figure geometry has narrow limb cross-sections. Weight-paint clothing directly to the base skeleton to avoid severe clipping when limbs flex. Dark gray, mid gray, and light gray palette swaps can be handled via single 3-step gradient palette textures. 


On weapons: White silhouettes with thick black wireframe/inverted-hull outlines. Weapon trails and elemental aura effects can be handled via billboard particles or Godot 4 mesh shaders in combat.

For characters, review the folder: “C:\Users\ferth\Documents\Black White\Visual References”, The stick figures should be in similar proportion as reference images, but can be more rounded if useful.

Suggestion. Apply an unlit inverted-hull or grease-pencil outline shader so the characters keep their bold graphic black outlines at any camera angle. 
On tiles, when afflicted with element, they glow accordingly. 
Thunder = crackling purple
Light = glowing yellow
Wind = swirling green
Fire = smouldering fire
Water = ripping water
Dark = sinking and swirling dark

There should be levels of intensity to fire, water, dark, light. Increase intensity when the tile reaches different intensity thresholds. 

Given the map creators varied tile options. Simplify them to jagged= impassible. 
Muddy = costs 2x movement
Grassy = spreads fire
Neutral 

Characters have the following paperdoll slots. The items appear on the character. 

Head
Chest
Legs
Main hand

All equipment in the game comes with stats, and  a built in enchantment. 

Generally all armor pieces affect an element. 
Example:
Frozen brigandine - all ice tiles remain 1 turn longer. 
Explosive chaps - your fire tiles explode after 1 turn
Thundering full helm - your thunder effects trigger twice. 

Make up 3 of these for each armor type  for my review. They don’t have to be unique. 


All weapon pieces effect attack style or actions. 
Example: double axe of cleaving, all aoes, and basic attack have their radius of effect increased by 1. 
Sword of piercing strikes: range is doubled. 
Spreadshot shortbow: fires 3 arrows in different line vectors for 50% damage each
Doubleshot longbow; fires 2 projectiles for 75% whenever firing. 
Flowing lance: unit can move after attacking. 

Make up 3 of these for each weapon for my review. They don’t have to be unique. 

Stats are locked to stages. So 1st and 2nd fight only drop E rank gear, any enchantment, but the stats are locked to +0 through +3. Heavy armor tends to give strength and defense. Wizard gear and robes tend to give intelligence and resistance. Ranger gear tends to give dexterity and speed. 

After 3rd fight we get D gear which is between 1 and 6
Then C gear which is 2-9. Etc.  

Character requires the rank or higher expertise in the weapon type  to equip the weapon. 

Characters learn abilities of the below type. 

Characters can know multiple abilities but can only equip one type at a time. A character will “learn” an ability after being equipped with a piece of equipment long enough. (2 battles)

Below are examples. We can add more no problem. Maybe even 2 or 3 per equipment piece. 

Types
Reactive:
Robes - ward - grants +1 willpower and resist for the rest of battle when taking damage. 
Platelegs - iron wall - grants +1 defense and resistance when taking damage for the rest of battle. 
Tassets - enrage - grants +1 strength and defense  when taking damage for the rest of battle. 
Chaps - light footed - grants +1 dex and speed when taking damage for the rest of battle. 

Supportive:
Full helm - unflinching - 
Feather cap - deadeye - increases accuracy by 5% per tile between unit and target. 
Wizard hat - imbued - when element is used, next cast of same element deals 25% more damage. 

Passive: 
Chainmail - double your glancing damage reduction
Platemail - double your glancing chance
Brigandine - add 25% of your dexterity to your strength
Vest - add 25% of your strength to your dexterity. 
Robe - 

If melee weapon, levels strength by 2
If ranged weapon, levels dexterity by 2
If mage weapon, levels wisdom by 2 
If 2 pieces of heavy armor, level defense by 2
If 2 pieces of ranged armor, level speed by 2
If 2 pieces of wizard armor/robes, level resistance by 2
If else, level by 1. 

