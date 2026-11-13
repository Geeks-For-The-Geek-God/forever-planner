# Weekly maintenance (for the scheduled Claude run)

This is the checklist the weekly "Forever Planner weekly update" task follows. It runs unattended, so:
make only safe, mechanical changes; never publish untested code; and write up anything that needs judgement
instead of acting on it.

## Sources
- **Plan data:** `ForeverPlanner/Data/<Class>.lua`, generated from each class's brief and route doc.
  `data-sources.json` records which route doc and revision each data file was built from.
- **Druid route doc:** Claude Doc https://claude.ai/artifact/KmG3TGZi9Lv2GUFknRDd45
  (doc id `97f27ded-3db4-4ca2-9054-ee33bc937702`). Read it with the Claude Docs tools: export the tab as
  markdown; the export result carries the doc's current `rev`.
- **Project docs** (claude.ai Project "WoW Forever", if this session has the Projects tool):
  `claude/03-patch-log.md`, `claude/01-wow-forever-reference.md`, `claude/classes/<class>.md`,
  `claude/addon/README.md`.
- **Game changes:** the Warcraft Tavern Forever blue tracker and Blizzard's WoW Forever hotfix notes.
  Search the web for posts dated after the newest entry in the patch log.

## Steps
1. **Patch check.** Find Blizzard posts, hotfixes and tuning newer than the newest patch-log entry. If there
   are any, append them to `claude/03-patch-log.md` (dated, with sources). If the Projects tool isn't
   available, put them in the summary instead.
2. **Impact on the plans.** For each class with a data file, check whether a change touches a talent,
   spell, macro command, quest or item in its plan.
   - **Safe to change:** a renamed spell, talent or quest; a quest's level; a corrected item name;
     a macro line that must change for a renamed spell (keep it at 255 characters or fewer).
   - **Judgement call (don't change, write up):** reworked talents, new best-in-slot items, removed abilities,
     anything that changes the build or rotation. List it in the summary with what you'd suggest.
3. **Route doc changes.** Compare the route doc's current `rev` with `data-sources.json`. If it changed,
   regenerate the affected parts of the data file (route steps, gear tables, stopgaps) to match the doc,
   keeping step keys stable where steps didn't move, then update `rev` in `data-sources.json`.
   Format rules: `claude/addon/README.md` in the project and the existing data file.
4. **Test.** `pip install lupa==2.8 && python tests/run_all.py`. If anything fails and you can't fix it
   safely, publish nothing and report the failure.
5. **Release (only if something in `ForeverPlanner/` changed).**
   - Bump the patch version (0.4.0 -> 0.4.1) in both `ForeverPlanner/ForeverPlanner.toc` (`## Version:`)
     and `ForeverPlanner/Core.lua` (`FP.version`).
   - Add one short line at the top of `FP.news` in Core.lua saying what changed.
   - Rewrite `CHANGELOG-latest.md` for this version.
   - Commit and push to `main`. The Release workflow tests again and publishes `vX.Y.Z`; the Windows updater
     installs it within 3 hours. Check the run succeeded (`gh api repos/{owner}/{repo}/actions/runs`).
   - Don't push tags, and don't use GraphQL (`gh release list` etc.): both are blocked from Claude sessions.
     Use `gh api` REST calls.
6. **Project notes.** If the release changed a class's plan, add a dated line to that class brief's change log.
7. **Summary.** End with a short report: game changes found, what changed in the addon (and the version
   published, if any), and anything waiting for the user's decision. If nothing changed, say so in one line.

## Never
- Change a build, rotation or gear priority on judgement alone.
- Publish with failing tests, or edit the release workflow to get past a failure.
- Add a new file to `ForeverPlanner/` in a weekly run (a new file needs a game restart, not just /reload);
  write it up instead.
