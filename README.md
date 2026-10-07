# BlinkPingMark

Ping and mark with a few quick mouse clicks. An addon for **WoW: Forever**.

Click the same spot three times (or twice) and a radial wheel opens there, drawn with the game's own
ping wheel art. One mouse button pings, the other puts raid target icons on units.

## Pinging

Triple-click the left mouse button (by default) to open the ping wheel: **Attack**, **Warning**,
**On my way**, **Assist**.

Move the cursor onto a wedge to choose the ping, then click the wheel's middle to send it:

- **On a unit frame** (your target, party or raid frames): the ping goes to that unit.
- **On a unit in the world**: the same, when the game knows the unit by a token (your target, a nameplate,
  a group member).
- **On the ground**: the ping lands where the wheel opened. (A ping can only be sent at the cursor, so the
  sending click has to happen on that spot; the middle is that spot.)

The right button, Escape, a click outside the wheel or six seconds of nothing close it. The middle with
nothing chosen is Cancel.

The ping wheel cannot open **in combat**: the game does not let addons show the buttons it needs then.
For pings in combat bind the game's own ping key (Key Bindings → Ping System) to a mouse button you
have spare, such as the middle button.

## Marking

Triple-click the **other** mouse button on a unit frame, or on a unit in the world, to open the marker wheel: Star, Circle, Diamond,
Triangle, Moon, Square, Cross, Skull. Click a wedge to put that icon on the unit; click the middle of the wheel
to remove the unit's icon (the icon it already has also removes it when clicked again). Like the ping wheel it opens out of combat only.

## Settings

`/bpm` (or Options → AddOns → BlinkPingMark):

- triple or double click, left or right mouse button for pings (marking takes the other button)
- the game's small wheel
- "Send on wedge click": send as soon as a wedge is clicked instead of returning to the middle. Faster,
  but a ground ping then lands under the cursor rather than where the wheel opened
- where the wheels work: open world, cities, dungeons, raids, battlegrounds, arenas; marking only in a group

Slash commands for the same things: `/bpm clicks 2|3`, `button left|right`, `interval <seconds>`,
`small`, `quick`, `mark`, `group`, `test` (opens the wheel at the cursor), `debug`.

## How it works, briefly

Addons may not call the ping API, so each wedge is a secure button running the game's `/ping` macro
command, which the client resolves itself (`/ping [@unit] 1`, `/ping [@cursor] 2`, ...). Raid icons go the
same way through the `/tm [@unit] <n>` macro command, because `SetRaidTarget` is protected in WoW: Forever.
Clicks are counted from the `GLOBAL_MOUSE_DOWN` event; a run of clicks restarts when the cursor moves, the
pause is too long or the other button is used.

## Development

The logic can be exercised outside the game: `tools/wow_stub.lua` stands in for the WoW API and
`tools/test.py` drives the addon through click runs, zone rules, wedge selection and the macros it builds.

```bash
pip install lupa
python tools/test.py
```

### Releasing

CurseForge needs a zip whose top-level folder is `BlinkPingMark` (matching `BlinkPingMark.toc`); GitHub's
own source archives are named after the repository and the tag, so they are rejected. Tag a version
(`git tag v0.1.2 && git push --tags`) and the Release workflow attaches `BlinkPingMark-0.1.2.zip` to the
GitHub release; or build it locally with `python tools/package.py` (into `dist/`) and upload that file.

## Support

If BlinkPingMark saves you some clicks, you can buy me a coffee:

[![Buy me a coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=mdotwang&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff)](https://buymeacoffee.com/mdotwang)
