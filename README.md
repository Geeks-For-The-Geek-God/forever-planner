# Forever Planner

A World of Warcraft: Forever addon (interface 16001) that gives every character a levelling plan from its first login: a quest-by-quest route from its race's starting zone to 60, talents for its spec, class quests, and (where a class plan exists) macros and gear. It tracks the route from your quest log and quest history, tells you what to do next and sets waypoints.

It reads game state and shows advice only. It never casts, targets or moves for you.

## Install
Download the latest `ForeverPlanner-x.y.z.zip` from [Releases](../../releases) and unzip it into `World of Warcraft\_forever_\Interface\AddOns`. Restart the game the first time; after that, `/reload` picks up updates.

## Automatic updates (Windows)
Download `ForeverPlanner-Updater.zip` from the latest release, unblock and extract it, and double-click `Install.cmd`. See `updater/README.txt`.

## Use
On a character's first login a small window asks for its spec (the recommended one is ticked) and whether to include group quests. Close it or press Start; `/fp setup` changes it later. `/fp` opens the plan window (Route, Talents, Macros, Gear). `/fp help` lists every command. Questie and TomTom are optional but recommended.

## Layout
- `ForeverPlanner/` — the addon. `Core.lua` (engine), `Route.lua` (building each character's plan), `UI.lua` (tracker, plan window, setup window).
  - `Data/Routes/` — levelling routes for both factions and class quest guides, converted from Polestar (`tools/convert_polestar.py`).
  - `Data/Talents.lua` — levelling talent builds for all nine classes (ForeverDB, via Polestar).
  - `Data/Classes/<Class>.lua` — one file per class: macros, trainer notes, gear, and optionally its own route (the Druid's from level 21).
- `tools/` — `convert_polestar.py` regenerates the route and talent data from a Polestar checkout.
- `updater/` — Windows updater: `Install.cmd` sets up a scheduled task that runs `Update-ForeverPlanner.ps1` every 3 hours.
- `MAINTAINING.md` — the weekly maintenance checklist; `data-sources.json` — which route doc revision each plan was built from.
- `tests/` — Lua 5.1 tests against a stubbed WoW API. Run `pip install lupa==2.8` then `python tests/run_all.py`.
- `.github/workflows/` — tests on every push; when the TOC version changes on `main`, the release workflow runs the tests, builds the zip and publishes release `vX.Y.Z`.

## Releasing
1. Bump `## Version:` in `ForeverPlanner/ForeverPlanner.toc` and `FP.version` in `Core.lua`.
2. Write the notes in `CHANGELOG-latest.md`.
3. Push to `main`. The release appears under Releases a minute or two later. (It can also be run by hand from the Actions tab.)

## Licence
GPL-3.0 (see `LICENSE`). The routes and talent builds come from [Polestar](https://github.com/fitzforge/polestar) (GPL-3.0); see `NOTICE.md`.
