# EasyPing — WoW: Forever addon

Open a ping wheel by clicking the left mouse button three times (or twice) on the same spot, for
**WoW: Forever** (Classic+ beta). Same environment/conventions as `Interface\AddOns\MageFood\CLAUDE.md`:
Retail API, TOC `## Interface: 16001`, English-only in-addon text, explanations to the user in Chinese,
edit files directly, user tests with `/reload`. Version stays 0.0.1 during development; history in git.

## Files
- `EasyPing.toc`, `EasyPing.lua` (all logic), `## SavedVariables: EasyPingDB`

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
- Click counting on GLOBAL_MOUSE_DOWN (LeftButton): clicks count when they are within db.interval (0.4 s)
  and 16 screen px of the previous one, and the cursor is on the world (`GetMouseFoci()[1]` nil or
  WorldFrame) or on a unit frame (a frame in the focus's parent chain with a "unit" attribute). Any other
  button or UI click resets. db.clicks (3; `/easyping clicks 2|3`) clicks open the wheel.
- Target decided when the wheel opens: unit frame -> its unit token; world unit (UnitExists("mouseover"))
  -> a stable token with the same GUID (target, focus, party/raid/pet, boss, arena, nameplate1-40), else a
  contextual `/ping <n>` (hit test where the wheel button is: may miss small units); nothing -> `@cursor`.
  `@cursor` pings where the cursor is when the button is clicked, i.e. a wheel-radius (34 px) away from the
  click point; the white dot marks the click point.
- Wheel: `EasyPingWheel` (DIALOG strata) at the cursor, buttons `EasyPingButton<i>` (SecureActionButtonTemplate,
  LeftButtonUp/RightButtonUp, useOnKeyDown false, type1 macro) placed clockwise from the top at db.radius;
  left click pings and closes (OnClick post-hook), right click just closes, clicking elsewhere or 6 s closes.
- `/easyping`: clicks 2|3, interval <s>, size <px> (radius = size + 6), test, debug (prints the chosen target).

## Open items
- Not yet tested in game: whether `/ping` works from macrotext (Comms Wheel uses real macros), whether
  `@cursor` pings land where expected, atlas names, GetMouseFoci on the world.
