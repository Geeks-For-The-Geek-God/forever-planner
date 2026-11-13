import os, sys
import sys
from lupa.lua51 import LuaRuntime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness
import os
S=os.path.dirname(os.path.abspath(__file__)); A=os.path.join(S, "..", "ForeverPlanner") + "/"
lua=LuaRuntime(unpack_returned_tuples=True); G=lua.globals()
def load(p):
    lua.eval("function(src,n) local f,e=loadstring(src,n); if not f then error(e) end; return f end")(open(p).read(),p)()
load(S+"/wowstub.lua")
for f in harness.toc_files(routes=False): load(A+f)
fails=[]
def check(c,m):
    print(("PASS " if c else "FAIL ")+m)
    if not c: fails.append(m)
run=lua.execute
run("""
UIErrorsFrame = { AddMessage = function(_, m) ALERT = m end }
REWARD_CHOICES = {}; REWARD_FIXED = {}
function GetNumQuestChoices() return #REWARD_CHOICES end
function GetNumQuestRewards() return #REWARD_FIXED end
function GetQuestItemInfo(kind, i) local t = kind == "choice" and REWARD_CHOICES or REWARD_FIXED; return t[i] end
PLAYER_LEVEL = 22
FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN")
""")
# data: every step key referenced by gear exists
bad=run("""local FP=ForeverPlanner; local bad={}
for _,g in ipairs(FP.plan.gear) do for _,s in ipairs(g.slots) do
  for _,k in ipairs({s.step or false, s.altstep or false}) do if k and not FP:StepIndex(k) then bad[#bad+1]=k end end end end
for _,s in ipairs(FP.plan.stopgaps) do if not FP:StepIndex(s.step) then bad[#bad+1]=s.step end end
return table.concat(bad,",")""")
check(bad=="", "every gear step key exists in the route "+bad)

# Wearing Armor + Leggings of the Fang, Belt in bags (stub defaults)
here=run("local t={} for _,it in ipairs(ForeverPlanner:GearHere('c5')) do t[#t+1]=it.name end return table.concat(t,'; ')")
print("   gear here c5:", here)
check("Armor of the Fang" not in here and "Belt of the Fang" in here and "Serpent's Shoulders" in here, "WC step lists only pieces not worn")
here41=run("local t={} for _,it in ipairs(ForeverPlanner:GearHere('41')) do t[#t+1]=it.name..'/'..it.role end return table.concat(t,'; ')")
print("   gear here 41:", here41)
check("Worgpelt Leggings" not in here41, "SFK fallback legs hidden because Leggings of the Fang (best) is worn")

path=run("local p,w,t=ForeverPlanner:UpgradePath(); local o={} for _,it in ipairs(p) do o[#o+1]=(it.step or '-')..':'..it.name end return table.concat(o,' | '), w, t")
print("   upgrade path:", path[0]); print("   worn", path[1], "of", path[2])
order=[x.split(":")[0] for x in path[0].split(" | ")]
check(order[0]=="c5" and order.index("26")<order.index("41"), "still-need list in route order (WC first, then library, then SFK); 2 best pieces worn")
check(order[-1]=="-", "items with no route step come last")

# Tracker gear line on c5
run("ForeverPlanner:GotoKey('c5')")
gt=G._G["ForeverPlannerTracker"].gear.text
print("   tracker:", gt)
check(gt and gt.startswith("Gear here:") and "more" in gt, "tracker shows gear here with +N more")

# Loot prompt: Gloves of the Fang drop; and unequipping Armor doesn't prompt
run("""ALERT=nil
table.insert(BAGS[0], "|cff1eff00|Hitem:4:0|h[Gloves of the Fang]|h|r"); FireEvent("BAG_UPDATE_DELAYED")""")
check(G.ALERT and "Gloves of the Fang is in your bags" in G.ALERT, "loot prompt for a planned drop: %s"%G.ALERT)
run("""ALERT=nil; FireEvent("BAG_UPDATE_DELAYED")""")
check(G.ALERT is None, "no repeat prompt")
run("""ALERT=nil; local a = EQUIPPED[5]; EQUIPPED[5]=nil; table.insert(BAGS[0], a); FireEvent("PLAYER_EQUIPMENT_CHANGED")""")
check(G.ALERT is None, "taking off a planned item doesn't prompt")
run("EQUIPPED[5]='|cff1eff00|Hitem:1:0|h[Armor of the Fang]|h|r'; table.remove(BAGS[0]); FireEvent('PLAYER_EQUIPMENT_CHANGED')")

# Reward advice
run("""ALERT=nil; REWARD_CHOICES = { "Some Cloth Robe", "Spare Part Bindings", "Big Axe" }
LAST_TITLE="Light's Justice"; FireEvent("QUEST_COMPLETE")""")
check(G.ALERT and "take Spare Part Bindings" in G.ALERT, "reward pick names the stopgap: %s"%G.ALERT)
run("""ALERT=nil; REWARD_CHOICES = { "Hammerbone", "Heat Resistant Mitts" }; FireEvent("QUEST_COMPLETE")""")
check(G.ALERT and "Hammerbone" in G.ALERT, "Hammerbone picked from Leaders of the Fang")
run("""ALERT=nil; REWARD_CHOICES = { "Random Thing" }; FireEvent("QUEST_COMPLETE")""")
check(G.ALERT is None, "no advice when nothing is planned")

# Gear tab renders and rows are clickable
run("""
local FP=ForeverPlanner
local i=1 while true do local n=debug.getupvalue(FP.UpdateMain,i) if not n then break end if n=="tab" then debug.setupvalue(FP.UpdateMain,i,"gear") end i=i+1 end
_G.ForeverPlannerMain.shown=true; FP:UpdateMain(true)
""")
rows=run("""local n,c=0,0 local i=1 while true do local nm,v=debug.getupvalue(ForeverPlanner.UpdateMain,i) if not nm then break end
  if nm=="rows" or nm=="Render" then end i=i+1 end
return ForeverPlannerMain.title.text""")
check(rows=="Forever Planner: Gear", "gear tab renders")
# click the first still-need row via the Render rows upvalue
clicked=run("""
local FP=ForeverPlanner
local function up(fn,name) local i=1 while true do local n,v=debug.getupvalue(fn,i) if not n then return nil end if n==name then return v end i=i+1 end end
local Render=up(FP.UpdateMain,"Render"); local rows=up(Render,"rows") or up(up(Render,"Row"),"rows")
for _,r in ipairs(rows) do local f=r.scripts.OnClick if f and r.shown then f(r) break end end
local s = FP.plan.route[FP:ViewIndex()]; return s.key, WAYPOINT and WAYPOINT[4]
""")
check(clicked[0]=="c5", "clicking the first still-need row shows step c5 and sets a waypoint: %s"%(clicked,))
print("FAILURES:",len(fails))
sys.exit(1 if fails else 0)
