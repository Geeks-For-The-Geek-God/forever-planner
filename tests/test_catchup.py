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
# Level 30: every required quest of every step up to 75 is turned in, except steps 25c (Warsong Reports)
# and 54/58 (Betrayal from Within, Weapons of Choice); Weapons of Choice is still in the log.
run("""
PLAYER_LEVEL = 30
FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN")
local FP = ForeverPlanner; local id = 900000
local skipTitles = { ["The Warsong Reports"]=true, ["Betrayal from Within"]=true, ["Weapons of Choice"]=true }
for i, s in ipairs(FP.plan.route) do
  if s.key == "76" then break end
  for _, o in ipairs(s.q or {}) do
    if not skipTitles[o.q] then
      local have = FP.doneCount[FP.Norm(o.q)] or 0
      for n = have + 1, (o.n or 1) do id = id + 1; COMPLETED[id] = true; QUESTIE_NAMES[id] = o.q; FP.doneCount[FP.Norm(o.q)] = n end
    end
  end
end
-- far-ahead out-of-order quest (step 108, level 34) must not become the anchor
id = id + 1; COMPLETED[id] = true; QUESTIE_NAMES[id] = "Kodo Roundup"
QUESTLOG = { { title = "Weapons of Choice", id = 9001 } }
FP.doneCount = {}
FP:ImportHistory(false); FP:Refresh(false)
""")
cur=lambda: run("local FP=ForeverPlanner; local s=FP.current and FP.plan.route[FP.current]; return s and s.key")
check(cur()=="c3", "before catchup the tracker is back at 25c: %s"%cur())
run('SlashCmdList["FOREVERPLANNER"]("catchup")')
check(cur()=="c3", "preview changes nothing")
run('SlashCmdList["FOREVERPLANNER"]("catchup confirm")')
check(cur()=="51", "after confirm: 51/54/58 kept (Weapons of Choice in log), got %s"%cur())
check(run("return ForeverPlanner.char.skip['c3'] and ForeverPlanner.char.skip['25c'] and not ForeverPlanner.char.skip['54']") is True, "c3 and 25c skipped, 54 kept")
check(run("return ForeverPlanner.char.skip['108']") is None, "Kodo Roundup (34) didn't pull the anchor ahead")
run('SlashCmdList["FOREVERPLANNER"]("catchup undo")')
check(cur()=="c3" and run("return next(ForeverPlanner.char.skip)") is None, "undo restores everything: %s"%cur())
for l in list(G.OUT.values())[-12:]: print("  ", l)
print("FAILURES:",len(fails))
sys.exit(1 if fails else 0)
