# BlinkPingMark

Ping and mark with a few quick mouse clicks. An addon for **WoW: Forever**.

Click the same spot three times (or twice) and a radial wheel opens there, drawn with the game's own
ping wheel art. One mouse button pings, the other puts raid target icons on units.

## Pinging

Triple-click the left mouse button (by default) to open the ping wheel: **Attack**, **Warning**,
**On my way**, **Assist**.

- **On a unit frame** (your target, party or raid frames, nameplates' frames): click a wedge and the ping
  goes to that unit.
- **On a unit in the world**: the same, when the game knows the unit by a token (your target, a nameplate,
  a group member).
- **On the ground**: move the cursor onto a wedge, then click the wheel's middle. The ping lands where the
  wheel opened. (A ping can only be sent at the cursor, so the sending click has to happen on that spot.)

The right button, Escape, a click outside the wheel or six seconds of nothing close it. The middle with
nothing chosen is Cancel.

The ping wheel cannot open **in combat**: the game does not let addons show the buttons it needs then.
For pings in combat bind the game's own ping key (Key Bindings → Ping System) to a mouse button you
have spare, such as the middle button.

## Marking

Triple-click the **other** mouse button on a unit frame to open the marker wheel: Star, Circle, Diamond,
Triangle, Moon, Square, Cross, Skull. Click a wedge to put that icon on the unit; click the icon the unit
already has to remove it. Marking works in combat too.

## Settings

`/bpm` (or Options → AddOns → BlinkPingMark):

- triple or double click, left or right mouse button for pings (marking takes the other button)
- the game's small wheel
- "Send on wedge click": always send a ping as soon as a wedge is clicked. Faster, but a ground ping then
  lands under the cursor rather than where the wheel opened
- where the wheels work: open world, cities, dungeons, raids, battlegrounds, arenas, and only in a group

Slash commands for the same things: `/bpm clicks 2|3`, `button left|right`, `interval <seconds>`,
`small`, `quick`, `mark`, `group`, `test` (opens the wheel at the cursor), `debug`.

## How it works, briefly

Addons may not call the ping API, so each wedge is a secure button running the game's `/ping` macro
command, which the client resolves itself (`/ping [@unit] 1`, `/ping [@cursor] 2`, ...). Raid icons use
`SetRaidTarget`, which addons may call. Clicks are counted from the `GLOBAL_MOUSE_DOWN` event; a run of
clicks restarts when the cursor moves, the pause is too long or the other button is used.
