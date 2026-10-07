Black | White
=============

A black-and-white stick-figure hex tactics game. Pick 6 of 20, fight 10
battles with downtime between, then face the Giant.

RUN
  Unzip the whole folder anywhere, then double-click BlackWhite.exe.
  Keep BlackWhite.pck next to the .exe: the game needs both.
  Windows may warn about an unknown publisher (the exe isn't signed):
  "More info" -> "Run anyway".
  Needs a GPU with Vulkan (most cards from 2016 on).
  If it crashes or misbehaves, run BlackWhite.console.exe instead: it opens
  a console window with the error messages. Send those to us.

TITLE SCREEN
  Any key: new run    C: continue your run    T: tutorial    S: settings

CONTROLS (combat)
  Left click     move to a grey hex, attack a pulsing enemy, or pick a
                 skill from the menu beside the unit and aim it
  Enter          confirm          Esc   back out one step / undo the move /
                                        pause menu (settings, codex, quit)
  T              end the turn
  Left-drag      orbit the camera    Right/middle-drag or arrows: pan
  Wheel          zoom    Q / E: rotate 60 degrees    Space: recentre
  Hold Space or right mouse: fast-forward playback
  F              cutscene speed (Default / Fast / Minimal)
  Hover any dotted-underlined word for its meaning.

FULLSCREEN
  F11 or Alt+Enter toggles fullscreen (remembered).

SAVES
  The run autosaves. Saves and settings live in
    %APPDATA%\Godot\app_userdata\Black - White\
  (run.json = the current run, settings.cfg = settings).
  Delete that folder to start completely fresh.
