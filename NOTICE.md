# Notices

Forever Planner is licensed under the GNU General Public License, version 3 (see `LICENSE`).

## Polestar (levelling routes and talent builds)
- `ForeverPlanner/Data/Routes/Horde.lua`, `Alliance.lua` and `ClassQuests.lua` are converted from the compiled
  levelling and class guides of **Polestar** (https://github.com/fitzforge/polestar), Copyright (c) 2026 The
  Polestar authors, licensed GPL-3.0-only. Converted with `tools/convert_polestar.py`, which reads Polestar's
  guide files as data; the Polestar version and commit are in each file's header and in `data-sources.json`.
  Changes made in the conversion: steps and goals are rewritten into Forever Planner's own format, text
  placeholders are filled in, and Era-frame map coordinates are moved into the Forever client's map frame.
- `ForeverPlanner/Data/Talents.lua` is converted from Polestar's `talents/forever/*.json`, which follow
  ForeverDB's levelling builds (https://foreverdb.net) and were extended to level 60 by Polestar.
- Polestar's guide data names its own sources (CMaNGOS classic-db and others); that notice is copied
  unchanged to `ForeverPlanner/Data/Routes/LICENSE-DATA.txt`.

## Gear routes (`ForeverPlanner/Data/Routes/BiS.lua`)
Built by `tools/build_bis.py` from:
- Polestar Item Data (GPL-3.0): Classic Era item stats (Blizzard client tables) and Forever's own item stats and
  item sources (quest rewards, dungeon boss drops, crafts), the latter derived from **ForeverLevelingBiS** by
  Thunder (MIT, v0.12.0-beta, data 2026-10-13). Its MIT licence is copied to `ForeverPlanner/Data/Routes/LICENSE-GEAR.txt`.
- Polestar's stat weights per spec (`Gear/SpecData.lua`: Polestar's levelling weights blended with wowsims
  simulations, MIT, https://github.com/wowsims).
- Polestar's forever-db (quests, quest givers, objectives, prerequisites, spawns, names and map frames read from
  the Forever client; CC BY 4.0 / GPL-3.0, https://github.com/fitzforge/polestar/tree/main/forever-db).

## Everything else
The engine, interface, Druid and Warlock class plans, updater and tests are Forever Planner's own,
Copyright (C) 2026 The Forever Planner authors, GPL-3.0.
