# Changelog

## Unreleased

- CurseForge automatic packaging (`.pkgmeta`): every pushed tag is packaged by CurseForge itself, with
  `CHANGELOG.md` as the changelog, once the repository's webhook is set up (see README, Releasing).

## 0.1.3 — 2026-10-08

- Ping wheel: the same move for every target. Move the cursor onto a wedge to choose the ping, then
  click the wheel's middle to send it, for units as well as for the ground. "Send on wedge click" keeps
  the old one-click way.
- Ping wheel: opens on NPCs and other units in the world again. Their identities are secret values in
  this client; the unit is now found through the target, its nameplate or an allowed comparison instead
  of a GUID match, which raised an error.
- Mark wheel: opens on a unit in the world, not only on unit frames, when the game knows the unit by a
  token (your target, a nameplate, a group member).
- Mark wheel: the middle removes the unit's icon.
- Mark wheel: a unit that already has an icon no longer errors when the wheel opens (its icon index can
  be a secret value).
- Tests: the offline stub has secret values, with cases for NPCs on both wheels.

## 0.1.2 — 2026-10-08

- Releases: the zip has a top-level `BlinkPingMark` folder, as CurseForge requires; the Release workflow
  attaches it to tagged GitHub releases.

## 0.1.1 — 2026-10-07

- Raid icons go through the `/tm` macro command on secure buttons: `SetRaidTarget` is protected in
  WoW: Forever and raised a forbidden-action error. The mark wheel is therefore out of combat only,
  like the ping wheel.
- "Only in a group" applies to the mark wheel only; pings open solo too.
- Offline tests (lupa + a WoW API stub).

## 0.1.0 — 2026-10-07

- First release: triple-click (or double-click) ping wheel drawn with the game's radial wheel art,
  ground pings sent from the wheel's middle, unit pings on unit frames and world units, the mark wheel
  on the other mouse button, settings panel (clicks, mouse button, small wheel, where the wheels work,
  only in a group), addon icon.
