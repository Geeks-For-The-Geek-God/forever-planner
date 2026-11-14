# 0.6.1: the gear plan beside the character window.
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
-- character window and its slot buttons; HookScript keeps the hooks so the test can fire them
HOOKS = {}
local function hookable(name)
  local f = CreateFrame("Frame", name)
  f.HookScript = function(self, ev, fn) HOOKS[name .. ev] = HOOKS[name .. ev] or {}; table.insert(HOOKS[name .. ev], fn) end
  f.GetFrameStrata = function() return "MEDIUM" end
  return f
end
hookable("CharacterFrame")
for _, n in ipairs({ "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot", "CharacterChestSlot",
  "CharacterWristSlot", "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot", "CharacterFinger0Slot",
  "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot", "CharacterMainHandSlot", "CharacterSecondaryHandSlot",
  "CharacterRangedSlot" }) do CreateFrame("Button", n) end
function FireHook(name) for _, fn in ipairs(HOOKS[name] or {}) do fn() end end
TT = { lines = {} }
GameTooltip = { SetInventoryItem = function() end, AddLine = function(self, t) table.insert(TT.lines, t) end, Show = function() end,
  SetOwner = function() end, SetItemByID = function() end, Hide = function() end }
POSTHOOKS = {}
function hooksecurefunc(t, name, fn)
  local orig = t[name]
  t[name] = function(...) local r = orig(...); fn(...); return r end
end
C_Item = { GetItemIconByID = function(id) return "icon" .. id end, GetItemQualityByID = function() return 3 end }
ITEM_QUALITY_COLORS = { [3] = { r = 0, g = 0.44, b = 0.87 } }
""")
for f in harness.toc_files(routes=True):
    load(A + f)
run = lua.execute
run('FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD"); FlushTimers()')
run('ForeverPlanner:ApplySetup("affliction", false, true); FlushTimers()')
check(lua.globals().ForeverPlannerGearPanel is not None, "gear panel built beside the character window")
check(lua.globals().ForeverPlannerGearToggle is not None, "toggle button on the character window")
run('ForeverPlannerGearPanel:Hide(); FireHook("CharacterFrameOnShow")')
check(run("return ForeverPlannerGearPanel:IsShown()") is True, "opening the character window shows the gear plan")
band = run("return ForeverPlannerGearPanel.band.text")
check(band.startswith("Levels 10-19") and "you're here" in band, "shows the band you're in: " + band)
n = run("local n=0 for _,r in ipairs(ForeverPlannerGearPanel.rows) do if r.shown and r.sl then n=n+1 end end return n")
slots = run("local FP=ForeverPlanner; return #FP:GearBracket().slots")
check(n == slots and n > 5, "one row per planned slot (%d)" % n)
first = run("local r = ForeverPlannerGearPanel.rows[1]; return r.sl.slot .. '|' .. r.name.text .. '|' .. tostring(r.icon.tex)")
print("   first row:", first)
check(run("""local order = {} for _, r in ipairs(ForeverPlannerGearPanel.rows) do if r.shown and r.sl then order[#order+1] = r.sl.slot end end
  return order[1] ~= 'Ranged' and order[#order] ~= 'Head'"""), "rows in character-window order (head first, ranged last)")
info = run("for _, r in ipairs(ForeverPlannerGearPanel.rows) do if r.shown and r.sl and r.sl.step then return r.info.text .. ' || ' .. r.step.text end end")
check(info and "step" in info and "Q: " not in info, "row says where it comes from (short) and the step on the right: " + str(info))

# equip a planned item: the row ticks and the count goes up
name = run("return ForeverPlannerGearPanel.rows[1].sl.best")
inv = run("local FP=ForeverPlanner; return FP.SLOT_IDS[ForeverPlannerGearPanel.rows[1].sl.slot][1]")
run('EQUIPPED[%d] = "|cff0070dd|Hitem:1:0|h[%s]|h|r"; FireEvent("PLAYER_EQUIPMENT_CHANGED")' % (inv, name.replace('"', '\\"')))
print("   ", run("return ForeverPlannerGearPanel.rows[1].info.text"), run("return ForeverPlannerGearPanel.rows[1].sl.best"), run("return EQUIPPED[2]"))
check("Wearing it" in run("return ForeverPlannerGearPanel.rows[1].info.text"), "equipped pick shows 'Wearing it'")
check(run("return ForeverPlannerGearPanel.count.text").startswith("Wearing 1 of"), "count of planned items on: " + run("return ForeverPlannerGearPanel.count.text"))

# clicking a row sets a waypoint to its step and shows it on the tracker
k = run("for i, r in ipairs(ForeverPlannerGearPanel.rows) do if r.shown and r.sl and r.sl.step and r.state.which ~= 'worn' then return i end end")
run("OUT = {}; local r = ForeverPlannerGearPanel.rows[%d]; r.scripts.OnClick(r)" % k)
check(run("return ForeverPlanner.view ~= nil"), "row click shows its step on the tracker")
check("waypoint set" in run("return OUT[#OUT] or ''"), "row click says where: " + run("return OUT[#OUT] or ''"))

# paging bands
run("ForeverPlannerGearPanel.next.scripts.OnClick()")
check(run("return ForeverPlannerGearPanel.band.text").startswith("Levels 20-29"), "> pages to the next band")
run("ForeverPlannerGearPanel.prev.scripts.OnClick()")
check(run("return ForeverPlannerGearPanel.band.text").startswith("Levels 10-19"), "< pages back")

# slot tooltips name the plan's pick
run("TT.lines = {}; GameTooltip:SetInventoryItem('player', %d)" % inv)
check(any("plan's pick" in str(l) for l in run("return TT.lines").values()), "character slot tooltip: 'is your plan's pick'")

# closing the panel remembers it
run("ForeverPlanner.char.gearPanel = false; ForeverPlannerGearPanel:Hide(); FireHook('CharacterFrameOnShow')")
check(run("return ForeverPlannerGearPanel:IsShown()") is False, "closed panel stays closed next time")
run('SlashCmdList["FOREVERPLANNER"]("gear")')
check(run("return ForeverPlannerGearPanel:IsShown()") is True, "/fp gear opens it again")

print("FAILURES:", len(fails))
sys.exit(1 if fails else 0)
