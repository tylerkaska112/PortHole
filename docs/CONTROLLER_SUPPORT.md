# Controllers in Porthole

Two separate jobs: driving the app with a controller, and playing a game with one. (Madeira's own notes on the XInput and HID transport are in `vendor/Madeira/docs/CONTROLLERS.md`.)

## Driving the app

D-pad or left stick moves a glow between targets, A presses, B goes back, X is the secondary action (Play on a game tile), Y the tertiary one, LB/RB switch sections, Menu opens the quick actions.

* **Which item the D-pad goes to** (`FocusSpatial.swift`): an item is a candidate only when it lies *beyond* the current one in that direction, not merely when its centre is a little further along (that rule sent Down to a neighbouring tile
  whose centre was two points lower). Among candidates the nearest wins, sideways offset counting far less than distance along the way, and items lined up with the current one beat items that are not.
* **A remembered column** (`FocusScope.swift`): going Down through a wide row and back Up returns to the column you started in; a sideways move forgets it.
* **Focus survives redraws**: when the focused item disappears it is given 150 ms to come back (a redraw removes and re-adds views); if it does not, focus moves to the nearest remaining item instead of being dropped (which used to send the next
  press to the top-left item).
* **Repeat** (`NavRepeater.swift`): one step per push, then repeats while held, faster the longer it is held. D-pad and stick are tracked separately, the stick has hysteresis (pushed well past the edge to start, let well back to stop) and stays on its
  direction until the other axis clearly wins.
* **The pointer cannot steal focus**: a mouse resting over a view that scrolls underneath it reports a new hover every time the content moves; the pointer is ignored for 1.2 s after any controller input.
* A pad that announces itself before its profile exists is retried for a few seconds instead of never being wired.

Host tests: `app/Tests/Nav/run.sh` (layouts like the real screens, the repeat logic, focus recovery and the mode decision below).

Not reachable by a controller (system UI): the Certificate password and "Cannot run that" alerts, the Menu and Picker rows in the bind editor, the colour picker. Everything else is a focus target.

## Playing a game

By default the physical controller reaches the game as an Xbox pad (XInput). A game that never reads XInput sees nothing, and an Xbox pad it ignores does nothing. So the default is now **Automatic** (Game details > Controller):

* The engine counts how often the game asks for a controller (`winios_gamepad_read_count`, patch `0019`; XInput slots and the HID pad together, whether or not anything is connected).
* If a connected controller has not been read at all about 25 s into the run, it becomes **keyboard and mouse** (the game's binds, or the standard layout) and a note says so.
* If the game starts reading later, it becomes an Xbox pad again at once, and is not switched again that run.
* The result is kept with the game (`GameEngine.padAuto`), so the next run starts in keyboard and mouse without waiting, and goes back if the game reads.
* Choosing **Xbox controller**, **Keyboard and mouse** or **Xbox and DirectInput joystick** for a game turns Automatic off for it.

The log shows `[pad] automatic: ...` lines for each decision. A game that reads the controller by a path other than XInput (for example Windows.Gaming.Input, if Wine does not route it through the XInput query) would not be counted and would be switched after 25 s: set **Xbox controller** for it.

## The in-game menu from the controller (0.50.360)

* **Open / close:** hold Menu + View (Options + Create on a DualSense) for half a second (`PadChord`, `env.PORTHOLE_PAD_MENU` = `l3r3`, `home` or `off` changes it). The two buttons are kept from the game while both are down. A one-time note over the game (the first three sessions) says how.
* **While it is open** the game sees a neutral controller (`PadInput.setCaptured`: connected, nothing pressed; keys and mouse are released), `NavHub.gameMenuOpen` lets the app's navigation drive the menu although a game runs, and the buttons held when it closes (the B that closed it) stay hidden from the game until they are let go (`PadReleaseMask`).
* **Inside:** every row, tab, toggle, pill, chip, the opacity slider (Left/Right) and the look-speed steppers are focus targets in the menu's own `FocusScope`. A presses, B or Menu closes, LB / RB change the tab.
* Host tests: app/Tests/Nav/run.sh (chord, release mask, navigation). NOT verified on a device yet.
