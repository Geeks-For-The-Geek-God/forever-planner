# 0.6.5: the Priest plan from its brief (Discipline wand to 39, respec into Shadow at 40).
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
PLAYER_CLASS, PLAYER_CLASS_NAME, PLAYER_RACE, PLAYER_FACTION, PLAYER_LEVEL = "PRIEST", "Priest", "Scourge", "Horde", 24
C_QuestLog = { GetQuestObjectives = function() return {} end }
""")
for f in harness.toc_files(routes=True):
    load(A + f)
run = lua.execute
run('FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD"); FlushTimers()')
run('ForeverPlanner:ApplySetup("discipline", false, true); FlushTimers()')

FP = "local FP = ForeverPlanner; "
check(run(FP + "return FP.plan.name").startswith("Discipline wand to 39, Shadow from 40"), "Priest gets the brief's plan by default")
def ranks(t):
    run(FP + "FP.talentAPI = 'traits'; FP.talentRanks = {" + ",".join('[FP.Norm("%s")]=%d' % kv for kv in t.items()) + "}; FP.talentSpent = 0")
ranks({"Wand Specialization": 2, "Spirit Tap": 5, "Twin Disciplines": 5, "Holy Precision": 1, "Mental Strength": 1})
lvl, txt = run(FP + "return FP:NextTalent()")
check(txt == "Mental Strength 2", "level 24 on the brief's build: next pick Mental Strength 2 (%s)" % txt)
check(run(FP + "return FP:NeedsRespec()") is False, "no respec prompt before 40")
check("Penance" in run(FP + "return FP:TalentPhase().talents[35]"), "Penance at 35 in the wand phase")
m = run(FP + "for _, m in ipairs(FP:CurrentMacros()) do if m.name == 'ATTACK' then return m.text end end")
check("Shoot" in m and "Penance" not in m, "ATTACK at 24 is the wand sequence")
check(run(FP + "local n=0 for _ in pairs(FP.plan.training) do n=n+1 end return n") >= 10, "trainer reminders")
check(run(FP + "return FP.plan.stopgaps and #FP.plan.stopgaps") == 8, "wand path as stopgaps")

# level 40: talents are still Discipline -> respec prompt, then Shadow
run(FP + "PLAYER_LEVEL = 40")
ranks({"Wand Specialization": 2, "Spirit Tap": 5, "Twin Disciplines": 5, "Holy Precision": 1, "Mental Strength": 2,
       "Inner Focus": 1, "Meditation": 3, "Mental Agility": 3, "Improved Power Word: Shield": 3, "Penance": 1,
       "Improved Shadow Word: Pain": 2, "Soul Warding": 1, "Renewed Hope": 1})
check(run(FP + "return FP:NeedsRespec()") is True, "at 40 with Discipline points: time to respec")
run(FP + "OUT = {}; FP:OnLevelUp(40)")
check(any("respec" in str(l) for l in run("return OUT").values()), "level-up message says to respec")
ranks({})
lvl, txt = run(FP + "return FP:NextTalent()")
check(txt == "Shadow Focus 1" and run(FP + "return FP:TalentLevelLabel(%d)" % lvl) == 40, "after the respec: Shadow Focus 1, shown at 40")
check(run(FP + "return FP:NeedsRespec()") is False, "no prompt once reset")
m = run(FP + "for _, m in ipairs(FP:CurrentMacros()) do if m.name == 'ATTACK' then return m.text end end")
check("Mind Flay" in m and len(m) <= 255, "ATTACK at 40 is the Shadow loop (%d chars)" % len(m))

# gear: Discipline bands to 39, Shadow from 40
check(run(FP + "return FP:GearSpecAt(45)") == "shadow" and run(FP + "return FP:GearSpecAt(30)") == "discipline", "gear spec switches at 40")
same = run(FP + """local b = FP:BiSBands(); local s = FP.bisPlans['PRIEST:shadow:Horde']; local d = FP.bisPlans['PRIEST:discipline:Horde']
  return b[1] == d[1] and b[4] == s[4]""")
check(same, "gear route: Discipline picks below 40, Shadow picks from 40")

# the other spec: Shadow from 10, no phases
run('ForeverPlanner:ApplySetup("shadow", false, true); FlushTimers()')
check(run(FP + "return FP.plan.talentPhases == nil and FP.plan.talents[20]") == "Mind Flay", "Shadow from 10: Mind Flay at 20")
check(run(FP + "return FP.plan.talentNotes[40] ~= nil"), "Shadow talent notes shown")

print("FAILURES:", len(fails))
sys.exit(1 if fails else 0)
