-- Forever Planner: Priest class file.
-- Until this class has its own plan, a Priest gets the shared levelling route for its race and the
-- levelling talent builds in Data/Talents.lua (ForeverDB, via Polestar). Discipline is recommended
-- because the Priest brief levels Discipline to 39 (Shadow from 40). The Priest chat in the
-- WoW Forever project fills this file in: specs with talents, macros, trainer notes and gear.
-- Format: claude/addon/README.md in the project, "Class files".
local FP = ForeverPlanner

FP:RegisterClass({ class = "PRIEST", recommended = "discipline" })
