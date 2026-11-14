## Forever Planner 0.6.0: best-in-slot gear routes

**Restart the game once after this update** (it adds a new file). `/reload` is enough after that.

- **Your route now goes where your best gear is.** For your class and spec, every item with a known source is scored with your spec's stat weights: quest rewards, dungeon boss drops and crafts. The best item for each slot is picked for each level band (10-19, 20-29, 30-39, 40-49, 50-59 and 60).
- **Quests:** a quest reward your levelling route already gets is linked to that step. If the route doesn't do the quest, its whole chain (every quest that opens it, with waypoints) is added where you reach its level.
- **Dungeons:** each dungeon with a boss drop or quest reward on your list is added at its level as a block: pick up its quests, run it (quest objectives plus the bosses that drop your items), then hand in.
- **Crafts:** crafted picks are listed with the profession and skill they need (or buy one on the Auction House), with the best quest or drop item as the second choice.
- **Where you see it:** the Gear tab lists your picks for each level band, each linked to its step (click one for a waypoint). The tracker shows "Gear here" on the step that gets one, and the quest reward window names the reward to take.
- **Setup:** a new "Include dungeons" option (on by default). `/fp setup` changes it.
- Your Druid's own Feral plan (route and gear) is unchanged.

Data: Polestar's item database (Forever item stats; sources from ForeverLevelingBiS, MIT, data 13 Oct) and stat weights, plus quest data from the Forever client. See NOTICE.md.
