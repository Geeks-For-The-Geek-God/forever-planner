# 0.6.3: "Craft now" backups on the gear panel.
import os, sys
from lupa.lua51 import LuaRuntime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness

S = os.path.dirname(os.path.abspath(__file__)); A = os.path.join(S, "..", "ForeverPlanner") + "/"
fails = []
def check(c, m):
    print(("PASS " if c else "FAIL ") + m)
    if not c: fails.append(m)

lua = LuaRuntime(unpack_returned_tuples=True)
def load(p):
    lua.eval("function(src,n) local f,e=loadstring(src,n); if not f then error(e) end; return f end")(open(p, encoding="utf-8").read(), p)()
load(os.path.join(S, "wowstub.lua"))
lua.execute("""
PLAYER_CLASS, PLAYER_CLASS_NAME, PLAYER_RACE, PLAYER_FACTION, PLAYER_LEVEL = "WARLOCK", "Warlock", "Troll", "Horde", 15
EQUIPPED = {}
C_QuestLog = { GetQuestObjectives = function() return {} end }
HOOKS = {}
local cf = CreateFrame("Frame", "CharacterFrame")
cf.HookScript = function(self, ev, fn) HOOKS[ev] = HOOKS[ev] or {}; table.insert(HOOKS[ev], fn) end
cf.GetFrameStrata = function() return "MEDIUM" end
function FireHook(ev) for _, fn in ipairs(HOOKS[ev] or {}) do fn() end end
GameTooltip = { SetInventoryItem = function() end, AddLine = function() end, Show = function() end,
  SetOwner = function() end, SetItemByID = function() end, Hide = function() end }
function hooksecurefunc(t, name, fn) local o = t[name]; t[name] = function(...) local r = o(...); fn(...); return r end end
SKILL = {}   -- skill line ID -> rank
STATS = {}   -- item link -> client stats
C_SkillInfo = { GetSkillLineInfoByID = function(id) if SKILL[id] then return { rank = SKILL[id], maxRank = 150 } end return { rank = 0, maxRank = 0 } end }
C_Item = { GetItemIconByID = function(id) return "icon" .. id end, GetItemQualityByID = function() return 2 end,
  GetItemStats = function(link) return STATS[link] or {} end }
function GetInventoryItemID(_, slot) local l = EQUIPPED[slot]; return l and tonumber(l:match("item:(%d+)")) end
""")
for f in harness.toc_files(routes=True):
    load(A + f)
run = lua.execute
run('FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD"); FlushTimers()')
run('ForeverPlanner:ApplySetup("affliction", false, true); FlushTimers()')

def rows():
    return run("""local FP = ForeverPlanner; local rows, skills, why = FP:CraftNow()
      local out = {} for _, c in ipairs(rows) do out[#out+1] = c.slot .. '|' .. c.rec[1] .. '|' .. c.state end
      return table.concat(out, ';'), why or ''""")

r, why = rows()
check(r == "" and why == "noprof", "no gear profession: nothing offered (%s)" % why)
check(run("local n=0 for _ in pairs(ForeverPlanner.craftPlans) do n=n+1 end return n") == 3, "only this class's craft lists kept after login")

run("SKILL[197] = 80")   # Tailoring 80
r, why = rows()
print("   ", r)
check("Chest|Filigreed Shadow Gown|check" in r, "Tailoring 80: Filigreed Shadow Gown offered, recipe not yet known")
check("Legs|Simple Kilt|check" in r, "best kilt at your skill offered")
check("Legs|Colorful Kilt|skill" in r, "next recipe worth skilling for (Colorful Kilt at 120)")
check("Shadow Sash" not in r, "items above your level are left out")
check("Back|Pearl-clasped Cloak|skill" in r, "10 points away shows as 'points to go'")

# the profession window lists the recipes you know
run("""C_TradeSkillUI = { GetAllRecipeIDs = function() return { 1257379, 2402 } end,
  GetRecipeInfo = function(id) if id == 1257379 or id == 2402 then return { learned = true } end return nil end,
  GetBaseProfessionInfo = function() return { professionName = "Tailoring" } end }""")
run('FireEvent("TRADE_SKILL_SHOW"); FlushTimers()')
r, _ = rows()
check("Chest|Filigreed Shadow Gown|now" in r, "known recipe: 'craft it'")
check("Hands|Shadow Gloves|recipe" in r, "recipe missing from your window: 'learn recipe'")
check("Back|Woolen Cape|now" in r, "Woolen Cape known: craft it")

# older clients: the trade skill window's own list (item links), and a collapsed header means "not the full list"
run("""C_TradeSkillUI = nil; ForeverPlanner.char.recipes = {}; ForeverPlanner.char.recipesSeen = {}
  TS = { {"Tailoring", "header", nil, true}, {"Shadow Gloves", "optimal", 253919}, {"Simple Kilt", "easy", 10047} }
  function GetTradeSkillLine() return "Tailoring" end
  function GetNumTradeSkills() return #TS end
  function GetTradeSkillInfo(i) local t = TS[i]; return t[1], t[2], 0, t[4] end
  function GetTradeSkillItemLink(i) local t = TS[i]; return t[3] and ("|Hitem:" .. t[3] .. ":0|h[" .. t[1] .. "]|h") end""")
run('FireEvent("TRADE_SKILL_UPDATE"); FlushTimers()')
r, _ = rows()
print("   ", r)
check("Hands|Shadow Gloves|now" in r and "Chest|Filigreed Shadow Gown|recipe" in r, "classic trade skill list read by item")
run("""ForeverPlanner.char.recipesSeen = {}; TS[1][4] = false; FireEvent("TRADE_SKILL_UPDATE"); FlushTimers()""")
r, _ = rows()
check("Chest|Filigreed Shadow Gown|check" in r, "collapsed header: missing recipes stay 'recipe?', not 'learn'")
run("""TS[1][4] = true; FireEvent("TRADE_SKILL_UPDATE"); FlushTimers()
  ForeverPlanner.char.recipes[1257379] = true""")

# wearing something better: no backup for that slot
run('EQUIPPED[5] = "|cff1eff00|Hitem:999001:0|h[Robe of Plenty]|h|r"; STATS[EQUIPPED[5]] = { ITEM_MOD_INTELLECT_SHORT = 40, ITEM_MOD_STAMINA_SHORT = 40 }')
run('FireEvent("PLAYER_EQUIPMENT_CHANGED")')
r, _ = rows()
check("Filigreed Shadow Gown" not in r, "a better chest worn: no chest backup")
run('STATS[EQUIPPED[5]] = { ITEM_MOD_STAMINA_SHORT = 2 }')
r, _ = rows()
check("Chest|Filigreed Shadow Gown|now" in r, "a weak chest worn: the gown is still a backup")

# the panel: tab label counts, rows, badge on plan rows
run('FireHook("OnShow"); FlushTimers()')
label = run("return ForeverPlannerGearPanel.tabCraft.label.text")
check("Craft now" in label and "(" in label, "tab shows how many you can craft: " + label)
badge = run("""for _, r in ipairs(ForeverPlannerGearPanel.rows) do if r.shown and r.backup and r.badge.shown then return r.sl.slot end end""")
check(badge is not None, "plan rows get an anvil where a backup exists (%s)" % badge)
run("ForeverPlannerGearPanel.tabCraft.scripts.OnClick()")
check(run("return ForeverPlanner.char.gearTab") == "craft", "clicking the tab switches to Craft now")
first = run("local r = ForeverPlannerGearPanel.rows[1]; return r.shown and (r.name.text .. ' || ' .. r.info.text .. ' || ' .. r.step.text)")
print("   first craft row:", first)
check(first and "Tailoring" in first, "craft rows show the item, profession and skill")
check("Tailoring 80" in run("return ForeverPlannerGearPanel.band.text"), "your gear professions shown at the top")
check(run("return ForeverPlannerGearPanel.prev.shown") is False, "no band arrows on the craft tab")
run("ForeverPlannerGearPanel.tabPlan.scripts.OnClick()")
check(run("return ForeverPlannerGearPanel.prev.shown") is True, "back to the plan tab")

print("FAILURES:", len(fails))
sys.exit(1 if fails else 0)
