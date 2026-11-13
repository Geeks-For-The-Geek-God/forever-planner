# Forever Planner

A World of Warcraft: Forever addon (interface 16001) that walks you through your own levelling route: it tracks the route's quests from your quest log and quest history, tells you what to do next, sets waypoints, and shows your class plan's talents, macros and gear.

It reads game state and shows advice only. It never casts, targets or moves for you.

## Install
Download the latest `ForeverPlanner-x.y.z.zip` from [Releases](../../releases) and unzip it into `World of Warcraft\_forever_\Interface\AddOns`. Restart the game the first time; after that, `/reload` picks up updates.

## Automatic updates (Windows)
Download `ForeverPlanner-Updater.zip` from the latest release, unblock and extract it, and double-click `Install.cmd`. See `updater/README.txt`.

## Use
`/fp` opens the plan window (Route, Talents, Macros, Gear). `/fp help` lists every command. Questie and TomTom are optional but recommended.

## Layout
- `ForeverPlanner/` — the addon. `Core.lua` (engine), `UI.lua` (tracker and window), `Data/<Class>.lua` (one plan per class).
- `updater/` — Windows updater: `Install.cmd` sets up a scheduled task that runs `Update-ForeverPlanner.ps1` every 3 hours.
- `tests/` — Lua 5.1 tests against a stubbed WoW API. Run `pip install lupa==2.8` then `python tests/run_all.py`.
- `.github/workflows/` — tests on every push; when the TOC version changes on `main`, the release workflow runs the tests, builds the zip and publishes release `vX.Y.Z`.

## Releasing
1. Bump `## Version:` in `ForeverPlanner/ForeverPlanner.toc` and `FP.version` in `Core.lua`.
2. Write the notes in `CHANGELOG-latest.md`.
3. Push to `main`. The release appears under Releases a minute or two later. (It can also be run by hand from the Actions tab.)
