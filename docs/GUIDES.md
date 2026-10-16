# Guides (tips and the first-game tour)

Short explanations of what a screen is for and what to do on it. Code: `app/Sources/UI/Guide/`.

* `GuideCenter.swift`: `GuideCatalog` holds every guide (id, title, steps of symbol + heading + a sentence or two); `GuideCenter` keeps what was seen (`f4.guides.seen`), whether tips are on (`f4.guides.enabled`) and the guide on screen. `autoShow(id)` shows a guide the first time its screen appears (tips on, not seen, nothing covering the screen, after a short pause); `show(id)` shows it on request.
* `GuideSheet.swift`: the sheet (steps, Back / Next / Got it, "Do not show tips"; a controller answers it). `RootView` presents it for the whole app.
* `GameTourView.swift`: the tour of the first game ever started. It comes BEFORE the game: `SessionController.start` holds the first start back (`tourGame`), `RootView` shows the tour as a full-screen cover, and `finishTour()` starts the game when it ends (after the cover has closed). Steps: the pencil and keyboard button on a picture of the game screen, the edge swipe, how touching the game works. (A first version drew the tour over the running game; touches answered late while the game was starting, so it moved here.)
* The question mark in the top bar (`AppShell.onHelp`) opens the guide of the section that is open; Settings, App, Tips and guides turns tips off, shows them all again or opens one by hand.
* Installs that already had the app before guides existed (setup seen/done, or the old menu hint shown) start with every guide marked seen.

To add a guide: add a `Guide` to `GuideCatalog` and to `all`, and call `GuideCenter.shared.autoShow("<id>")` where its screen appears (tabs are handled in `RootView`; the game page in `HomeScreen`).

## Drawings, buttons and the other guides (0.50.321)
* `GuideArt.swift`: a guide step can carry a small drawing of the screen it is about (`GuideArt`: home, add game, notices, stores, reports, settings, game page, add sources, game menu), laid out on a fixed 360x200 canvas with the relevant part ringed.
* A step can carry a `GuideAction` (add a game, open a store, open a settings page): the sheet shows its button, `RootView.runGuideAction` closes the sheet and goes there.
* Add a game: its own guide (`addgame`) opens over the Add a game sheet the first time (`.localGuide("addgame")`, a guide presented from inside the sheet it belongs to, because the app frame's guide sheet cannot appear over another sheet).
* The in-game menu: a tip at the top of the menu the first time it opens (`GuideCatalog.gameMenu`, `GameMenuPanel.menuTip`), dismissed with Got it.
* Settings, Tips and guides: every guide can be opened by hand, and the first-game tour can be played again without a game behind it (`GuideCenter.tourReplay`).
