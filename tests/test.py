import os, sys
import sys
from lupa.lua51 import LuaRuntime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness

import os
HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "ForeverPlanner") + "/"
SCRATCH = HERE
lua = LuaRuntime(unpack_returned_tuples=True)
G = lua.globals()

def run(code):
    return lua.execute(code)

def load(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    fn = lua.eval("function(src, name) local f, err = loadstring(src, name); if not f then error(err) end; return f end")(src, path)
    fn()

load(SCRATCH + "/wowstub.lua")
for f in harness.toc_files(routes=False):
    load(ADDON + f)

fails = []
def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond: fails.append(msg)

FP = G.ForeverPlanner
plan = FP.classes.DRUID.plan
check(plan is not None, "Druid plan registered")

# --- Data checks ---
res = run("""
local FP = ForeverPlanner; local p = FP.classes.DRUID.plan; local errs = {}; local keys = {}
for i, s in ipairs(p.route) do
  if keys[s.key] then errs[#errs+1] = 'duplicate key '..s.key end; keys[s.key] = true
  if s.map and not FP.MAP[s.map] and not FP.ZONE[s.map] then errs[#errs+1] = 'unknown map '..s.map..' at '..s.key end
  if (s.x and not s.y) or (s.y and not s.x) then errs[#errs+1] = 'half coords at '..s.key end
  if not s.title or not s.sec or not s.lvl then errs[#errs+1] = 'missing field at '..s.key end
  for _, o in ipairs(s.q or {}) do if type(o.q) ~= 'string' or o.q == '' then errs[#errs+1] = 'bad objective at '..s.key end end
end
local long = {}
for _, m in ipairs(p.macros) do if #m.text > 255 then long[#long+1] = m.name..' '..#m.text end end
local tlv = 0; for l in pairs(p.talents) do tlv = tlv + 1 end
return table.concat(errs, '; '), table.concat(long, '; '), #p.route, tlv
""")
errs, long, nsteps, ntal = res
check(errs == "", "route data valid " + errs)
check(long == "", "all macros <= 255 chars " + long)
print("   steps:", nsteps, "talent levels:", ntal)
for m in run("local t={} for _,m in ipairs(ForeverPlanner.classes.DRUID.plan.macros) do t[#t+1]=m.name..' '..m.from..'-'..m.to..': '..#m.text end return table.concat(t,'\\n')").split("\n"):
    print("   macro", m)

# --- Login ---
run("""
QUESTLOG = {
  { title = "Miner's Fortune", id = 101, complete = true },
  { title = "Jorn Skyseer", id = 102, complete = true },
  { title = "Report to Kadrak", id = 103, complete = true },
  { title = "Bruised Pride and Lion Hides", id = 104 },
  { title = "Vrang's Game", id = 105 },
}
FireEvent("ADDON_LOADED", "ForeverPlanner")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD")
FlushTimers()
""")
cur = lambda: run("local FP=ForeverPlanner; local s=FP.plan.route[FP.current]; return s and s.key")
check(cur() == "c1", "starts on c1 (Her Name Is Olgra not accepted), got %s" % cur())
check(G._G["ForeverPlannerTracker"].shown, "tracker shown")
print("   tracker head:", G._G["ForeverPlannerTracker"].head.text)

# Accept Olgra -> c2a
run("""table.insert(QUESTLOG, { title = "Her Name Is Olgra", id = 106 }); FireEvent("QUEST_ACCEPTED", 6, 106); FlushTimers()""")
check(cur() == "c2a", "accepting Olgra moves to c2a, got %s" % cur())

# Complete objectives of c2a (both complete in log) -> c2b
run("""for _, q in ipairs(QUESTLOG) do if q.id == 104 or q.id == 105 then q.complete = true end end FireEvent("QUEST_LOG_UPDATE"); FlushTimers()""")
check(cur() == "c2b", "completing Patriarchs/traps moves to c2b, got %s" % cur())

# Turn in both, accept Hermit Tanner -> c2c
run("""
LAST_TITLE = "Bruised Pride and Lion Hides"; FireEvent("QUEST_COMPLETE")
table.remove(QUESTLOG, 4); FireEvent("QUEST_TURNED_IN", 104)
LAST_TITLE = "Vrang's Game"; FireEvent("QUEST_COMPLETE")
table.remove(QUESTLOG, 4); FireEvent("QUEST_TURNED_IN", 105)
table.insert(QUESTLOG, { title = "The Hermit Tanner", id = 107 }); FireEvent("QUEST_ACCEPTED", 6, 107)
FlushTimers()
""")
check(cur() == "c2c", "turn-ins move to c2c, got %s" % cur())
check(G.WAYPOINT is not None and G.WAYPOINT[4] == "Walton (ridge over the Dry Hills)", "auto waypoint set via TomTom: %s" % (G.WAYPOINT and G.WAYPOINT[4]))

# History import: Questie names old quests
run("""
COMPLETED = { [201] = true, [202] = true, [203] = true }
QUESTIE_NAMES = { [201] = "The Hermit Tanner", [202] = "Unwelcome Guests", [203] = "Trouble in the Valley" }
ForeverPlanner:ImportHistory(true); ForeverPlanner:Refresh(true); FlushTimers()
""")
check(cur() == "c3", "history import completes c2c and c2d (Trouble in the Valley in history), now c3: %s" % cur())
# c2d needs Trouble in the Valley turned in; it was in history -> should actually skip to c3 since T done
# (Trouble in the Valley turned-in in history => c2d done too)

# Manual done + browse + skip
run("""
local FP = ForeverPlanner
FP:Browse(1); FP:Browse(1)
""")
check(run("return ForeverPlanner.view") is not None, "browsing sets a view")
run("ForeverPlanner.view = nil")
before = cur()
run("ForeverPlanner:ToggleSkip(ForeverPlanner.current)")
after = cur()
check(before != after, "skip advances (%s -> %s)" % (before, after))
run("ForeverPlanner:ToggleSkip(ForeverPlanner.view or 0)")

# Text-only steps auto-complete when a later step is done
res = run("""
local FP = ForeverPlanner; local r = FP.plan.route
local idx82, idx86
for i, s in ipairs(r) do if s.key == "82" then idx82 = i elseif s.key == "86" then idx86 = i end end
FP.char.manual[r[idx86].key] = true; FP:Refresh(false)
local st = FP.status[idx82]
FP.char.manual[r[idx86].key] = nil; FP:Refresh(false)
return st, FP.status[idx82]
""")
check(res[0] == "done" and res[1] == "open", "text-only step 82 counts done when a later step is done (%s, %s)" % res)

# Slash commands
for c in ["", "tracker", "tracker", "next", "prev", "now", "goto 44", "way", "autoway", "autoway", "check", "sync", "lock", "lock", "help", "done", "done", "reset confirm"]:
    try:
        run('SlashCmdList["FOREVERPLANNER"]("%s")' % c)
        ok = True
    except Exception as e:
        ok = False; print("   error:", e)
    check(ok, "/fp " + c)

# Tabs render
for t in ["route", "talents", "macros", "gear"]:
    try:
        run("""
local main = _G.ForeverPlannerMain; main.shown = true
""")
        # switch tab via the tab button scripts is awkward; call internal by toggling
        run("""
local FP = ForeverPlanner
-- find tab buttons: they're created with UIPanelButtonTemplate; simulate by setting upvalue through UpdateMain path
""")
        ok = True
    except Exception as e:
        ok = False; print(e)
# Use the debug library to set the local 'tab' upvalue in UI.lua
run("""
local FP = ForeverPlanner
local function setTab(v)
  local i = 1
  while true do
    local n = debug.getupvalue(FP.UpdateMain, i)
    if not n then break end
    if n == "tab" then debug.setupvalue(FP.UpdateMain, i, v) end
    i = i + 1
  end
end
TABOUT = {}
for _, t in ipairs({"route","talents","macros","gear"}) do
  setTab(t); FP:UpdateMain(true)
  TABOUT[t] = _G.ForeverPlannerMain.title.text
end
""")
for t in ["route", "talents", "macros", "gear"]:
    check(G.TABOUT[t] is not None, "tab %s renders: %s" % (t, G.TABOUT[t]))

# Gear state
res = run("local FP=ForeverPlanner; return FP:ItemState('Armor of the Fang'), FP:ItemState('Belt of the Fang'), FP:ItemState('Gloves of the Fang')")
check(tuple(res) == ("equipped", "bags", "missing"), "gear detection %s" % (res,))

# Talents: next pick should be Feral Swiftness 1 (level 18) since rank 0
res = run("return ForeverPlanner:NextTalent()")
check(res[0] == 18, "next talent from ranks = %s" % (res,))

# Macro write: create then edit
run("""
local FP = ForeverPlanner
local m = FP:MacroFor("THREAT", 21); FP:WriteMacro(m)
local m2 = FP:MacroFor("THREAT", 25); FP:WriteMacro(m2)
""")
check(G.MACROS[1].body.find("Lacerate") >= 0 and len(list(G.MACROS)) == 1, "THREAT macro created then updated in place")

# Level up message
run("PLAYER_LEVEL = 25; FireEvent('PLAYER_LEVEL_UP', 25); FlushTimers()")
msgs = [l for l in G.OUT.values()]
check(any("Lacerate" in m and "talent" in m for m in msgs), "level 25 prints the talent")
check(any("THREAT" in m and "new version" in m for m in msgs), "level 25 flags the THREAT macro update")

print("\n--- chat output (last 25) ---")
for m in msgs[-25:]:
    print("  ", m)
print("\nFAILURES:", len(fails))
for f in fails: print("  ", f)
sys.exit(1 if fails else 0)
