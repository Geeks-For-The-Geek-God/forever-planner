## Forever Planner 0.5.2: the route follows you

`/reload` is enough for this one (if you haven't restarted the game since 0.5.0, restart once).

**Noticing completed quests**
- A step now finishes as soon as its quests are done. Trainer, flight-path and hearth visits no longer hold it; they show as a "Don't forget" line until you visit (opening the trainer or flight master ticks them).
- A turn-in is caught even if the game's turn-in event is missed: when a quest leaves your log, the addon asks the game whether it was completed.
- The Druid route now matches its quests by quest ID as well as by title, so a title that differs slightly from the game still ticks (303 of 327 titles mapped).

**Following you off the route**
- **Abandoned quests:** drop a quest and the route stops waiting for it (its objectives and turn-in no longer hold any step). Pick it up again and it's back.
- **Quests you didn't take:** when a step that gives a quest is skipped, that quest's later steps don't hold you either.
- **Moving on:** if you finish two of the next four steps while you're away from an unfinished one (another map, about 150 yards off, or 4+ levels past it), that step is skipped by itself and the chat says so. Steps with a quest still in your log are never skipped this way. Only steps you finish while playing count, not old quest history.
- `/fp undo` brings back the last steps skipped this way (and they won't be skipped by themselves again). Skip on one of them in the Route tab does the same. `/fp follow` turns automatic skipping off or on.
