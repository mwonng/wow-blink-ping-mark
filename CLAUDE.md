# BlinkPingMark — WoW: Forever addon

Open a ping wheel by clicking the left mouse button three times (or twice) on the same spot, for
**WoW: Forever** (Classic+ beta). Same environment/conventions as `Interface\AddOns\MageFood\CLAUDE.md`:
Retail API, TOC `## Interface: 16001`, English-only in-addon text, explanations to the user in Chinese,
edit files directly, user tests with `/reload`. Version stays 0.0.1 during development; history in git.

## Files
- `BlinkPingMark.toc`, `BlinkPingMark.lua` (all logic), `## SavedVariables: BlinkPingMarkDB`
- `README.md` — user-facing description (keep it in step with the panel and slash commands)

## How pings can be sent at all (researched 2026-10-07, wow-ui-source branch `forever`, 1.60.1)
- `C_Ping.TogglePingListener`, `C_Ping.SendMacroPing` and everything in `C_PingSecure` are protected:
  addons cannot open Blizzard's wheel or send a ping from insecure code. `RunBinding("TOGGLEPINGLISTENER")`
  is protected too (bindings in Blizzard_PingUI/Bindings.xml: TOGGLEPINGLISTENER, PINGATTACK, PINGWARNING,
  PINGONMYWAY, PINGASSIST, TOGGLEPINGTARGET).
- The only addon path is the secure `/ping` macro command on a SecureActionButton
  (Blizzard_ChatFrameBase/Mainline/SlashCommandsOverrides.lua): `/ping [@unit] <type>`, type = number
  1 Attack, 2 Warning, 3 OnMyWay, 4 Assist, 5 AlertNotThreat, 6 AlertThreat (or the localized name).
  Blizzard_PingUI/Blizzard_PingManager.lua `SendMacroPing` resolves the target:
  `@cursor` = world point under the cursor, ignoring units and UI; `@<unit>` = that unit's GUID;
  no target = contextual (pingable UI frame under the cursor, else world hit test at the cursor).
- Wheel icons: atlas `"Ping_Wheel_Icon_" .. uiTextureKitID` from `C_Ping.GetDefaultPingOptions()`
  (sorted by orderIndex); text label fallback when the atlas is missing.
- Secure buttons cannot be shown, moved or given new macrotext in combat, so the wheel is out-of-combat
  only (UIErrorsFrame message in combat). If combat starts while it is open, Close() sets alpha 0 and hides
  on PLAYER_REGEN_ENABLED. Escape closes it through UISpecialFrames (Blizzard's secure code).

## Behavior
- Click counting on GLOBAL_MOUSE_DOWN: db.button (ping) or the other button (mark); clicks count when they
  are within db.interval (0.4 s) and 16 screen px of the previous one; the run's first click must be on the
  world (`GetMouseFoci()[1]` nil or WorldFrame) or on a unit frame (a frame in the focus's parent chain with
  a "unit" attribute; marks: unit frames only). db.clicks (3; `/bpm clicks 2|3`) clicks open the wheel.
- Target decided when the wheel opens: unit frame -> its unit token; world unit (UnitExists("mouseover"))
  -> a stable token with the same GUID (target, focus, party/raid/pet, boss, arena, nameplate1-40), else a
  contextual `/ping <n>` (hit test where the wheel button is: may miss small units); nothing -> `@cursor`.
- Wheel: `BlinkPingMarkWheel` (DIALOG strata, mouse-enabled: a click on it that is not on a wedge cancels) at the
  cursor, drawn with the game's radial wheel atlases (Blizzard_SharedXML/Blizzard_RadialWheel.lua, forever
  branch): Radial_Wheel_BG, Radial_Wheel_Frame_Count_<n>, Radial_Wheel_Select_Pointer (rotated to the cursor),
  Radial_Wheel_Select_Wedge_Count_<n> (rotated to the wedge, 100 px out = wedge frame 80 + 20), Radial_Wheel_Select_Close +
  Radial_Wheel_Icon_Close in the middle, Ping_Wheel_Icon_<kit> 80 px out, labels outside the icons; "_Small"
  variants (40/10 px, no labels) with db.small. Plain color shapes if the atlases are missing.
  Wedges start at the top and go counterclockwise, like Blizzard's. Selection by the cursor's angle and
  distance from the center every frame (UpdateSelection): distance² <= 500 (150 small) = Cancel,
  > 128 px (64) = nothing; only the picked wedge's secure button (`BlinkPingMarkButton<i>`, SecureActionButtonTemplate
  covering the whole wheel, LeftButtonUp/RightButtonUp, useOnKeyDown false, type1 macro) has the mouse enabled,
  so the click area is the real sector.
- Where a ping lands is where the cursor is when the secure button is clicked (the client hit-tests the
  cursor; nothing lets an addon pass a point), so a ground ping cannot be sent from a wedge 80 px out.
  Two modes decided per open (wheel.sendOnWedge): target is a unit token (frame / world unit) or db.quick ->
  a wedge click sends at once; target is the ground (@cursor / contextual) -> hovering a wedge arms it
  (highlight stays, `armed`), the middle becomes the secure button `BlinkPingMarkSend` (dead-zone size, macrotext
  copied from the armed wedge, armed icon instead of the X, hint text under the wheel) and clicking it sends
  at the wheel's middle = where it opened. Wheel OnMouseDown: the other mouse button closes; with the ground
  target a click on a sector only arms; the middle with nothing armed and the ring's outside close.
  A click outside the wheel (any button, GLOBAL_MOUSE_DOWN + IsMouseOver), Escape or 6 s close it.
  Panel "Send on wedge click" = db.quick (ground pings then land under the cursor).
- Mark wheel (db.mark, default on): the OTHER mouse button (MarkButton()), same click count, on a unit frame
  only, opens `BlinkPingMarkMarkWheel`: the same radial look with 8 raid target icons
  (Interface\TargetingFrame\UI-RaidTargetingIcons, 4x4 cells, Star Circle Diamond Triangle Moon Square
  Cross Skull from the top counterclockwise; Radial_Wheel_Frame/Select_Wedge_Count_8 when those atlases
  exist, else no frame art and a plain glow). SetRaidTarget is not protected: an ordinary frame, works in
  combat; the unit's current icon is drawn bigger with a green label and clicking it again clears it.
  The right button's mouse-up opens Blizzard's unit menu, so the click run closes it
  (Menu.GetManager():CloseMenus(), CloseDropDownMenus) on every click after the first and for 0.3 s after
  the wheel opens.
- Click runs: the first click decides what is under the cursor (firstKind/firstUnit; later clicks may land
  on the menu the first one opened); a run restarts on another button, a pause > interval or a move > 16 px.
- Settings panel (Options -> AddOns -> BlinkPingMark; canvas category like PolyChat, own check buttons with tooltips,
  radio rows = check buttons where exactly one is on): description paragraph, "Open the wheel with" (triple /
  double click; left / right mouse button, db.button = "LeftButton"/"RightButton"; "Small wheel" = db.small), "Marking" (db.mark), "Active in" check boxes
  db.zones[world|city|dungeon|raid|battleground|arena]. ZoneKind(): IsInInstance type party/scenario -> dungeon,
  raid, pvp -> battleground, arena; else Classic capital uiMapIDs (1453-1458) or GetZonePVPInfo "sanctuary" ->
  city; else world. Checked (Allowed()) when a click run starts and when the mark wheel opens, together
  with db.groupOnly (default on): neither wheel opens while not in a group (panel "Only in a group",
  `/bpm group`).
- `/bpm` opens the panel; `clicks 2|3`, `button left|right`, `interval <s>`, `small`, `quick`, `mark`, `group`,
  `test`, `debug` (prints the chosen target) still work.

## Verified in game (2026-10-07)
- `/ping` works from macrotext on a secure button; `@cursor` pings land exactly under the cursor at the click
  (which is why ground pings are sent from the middle); the Radial_Wheel and Ping_Wheel_Icon atlases exist in
  Forever and look like the game's wheel; the triple click opens the wheel on the world.

## Open items
- Not yet confirmed: the 8-wedge atlases (Radial_Wheel_Frame_Count_8 / Select_Wedge_Count_8) for the mark
  wheel, and that the unit menu is closed cleanly on right-button runs.
