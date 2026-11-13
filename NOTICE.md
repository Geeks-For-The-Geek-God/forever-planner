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

## Everything else
The engine, interface, Druid and Warlock class plans, updater and tests are Forever Planner's own,
Copyright (C) 2026 The Forever Planner authors, GPL-3.0.
