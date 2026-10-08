Black | White
=============

A black-and-white stick-figure hex tactics game. Pick 6 of 20, fight 10
battles with downtime between, then face the Giant.

RUN
  Double-click BlackWhite-<date>.exe. It is one file: put it anywhere.
  Windows may warn about an unknown publisher (the exe isn't signed):
  "More info" -> "Run anyway".
  Needs a GPU with Vulkan (most cards from 2016 on).

TITLE SCREEN
  Any key: new run    C: continue your run    T: tutorial    S: settings

CONTROLS (combat)
  Left click     move inside the rim, attack a pulsing enemy, or pick a
                 skill from the menu beside the unit and aim it
  Enter          confirm          Esc   back out one step / undo the move /
                                        pause menu (settings, codex, quit)
  T              end the turn
  Wind skills    on the confirm box, the mouse side or the arrow keys pick
                 the shaping (part left / right, draw in, burst out, hold);
                 Tab or the wheel cycles it
  Left-drag      orbit the camera    Right/middle-drag or arrows: pan
  Wheel          zoom    Q / E: rotate 60 degrees    Space: recentre
  Hold Space or right mouse: fast-forward playback
  F              cutscene speed (Default / Fast / Minimal)
  Hover any dotted-underlined word for its meaning.

CONTROLS (gear panel)
  O: optimize everyone's gear (preview, Apply / Cancel, one Undo)
  U: unequip everyone's armour and second weapon (main hands stay)

THE GAME IN ONE SCREEN
  Paint the ground, then cash it in. Skills and imbued attacks paint
  elements on the hexes: fire burns, water slows, light heals but exposes,
  dark hides. Fire meeting water douses both.
  Thunder, ice and wind are operators. Thunder detonates a painted hex;
  on bare ground it arms a fuse that ANY other element ignites. Ice glazes
  a painted hex: a unit standing on glaze is Unsteady (less avoid and
  glance) and every blow on it Shatters for extra damage. Wind lays a gale
  that copies whatever lands on it to the six hexes around; a wind basic
  attack pushes its target 1.
  Ranged blows lose 10% while an enemy stands within 2 of the shooter
  (Pressured).
  A unit holds at most 3 elements. Element ranks earn perks (now and then
  a duo perk of two elements); ranks 3 and 6 earn a keystone, a rule-
  breaker that also gives a title ("Will, the Lava Walker").
  Weapons: sword, axe, lance, daggers, bow, staff. Each has its own move,
  reach and skills; a unit can carry a second weapon and swap for free.
  The Codex (Esc in a fight) has every number.

FULLSCREEN
  F11 or Alt+Enter toggles fullscreen (remembered).

SAVES
  The run autosaves. Saves and settings live in
    %APPDATA%\Godot\app_userdata\Black - White\
  (run.json = the current run, settings.cfg = settings).
  Delete that folder to start completely fresh.
