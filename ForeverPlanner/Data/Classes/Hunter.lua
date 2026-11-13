-- Forever Planner: Hunter class file.
-- Until this class has its own plan, a Hunter gets the shared levelling route for its race and the
-- levelling talent builds in Data/Talents.lua (ForeverDB, via Polestar). The Hunter chat in the
-- WoW Forever project fills this file in: specs with talents, macros, trainer notes and gear.
-- Format: claude/addon/README.md in the project, "Class files".
local FP = ForeverPlanner

FP:RegisterClass({ class = "HUNTER", recommended = "beastmastery" })
