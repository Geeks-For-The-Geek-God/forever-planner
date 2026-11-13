# 0.5: plans for every character, built from the shared levelling routes.
import os, sys
from lupa.lua51 import LuaRuntime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness

S = os.path.dirname(os.path.abspath(__file__)); A = os.path.join(S, "..", "ForeverPlanner") + "/"
fails = []
def check(c, m):
    print(("PASS " if c else "FAIL ") + m)
    if not c: fails.append(m)

def session(setup_lua=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    def load(p):
        lua.eval("function(src,n) local f,e=loadstring(src,n); if not f then error(e) end; return f end")(open(p, encoding="utf-8").read(), p)()
    load(os.path.join(S, "wowstub.lua"))
    lua.execute("""
    OBJECTIVES = {}   -- quest id -> { true/false per objective }
    C_QuestLog = { GetQuestObjectives = function(id)
      local o = OBJECTIVES[id]; if not o then return {} end
      local t = {} for i, v in ipairs(o) do t[i] = { finished = v } end return t end }
    BIND = "Valley of Trials"
    function GetBindLocation() return BIND end
    ZONE, SUBZONE = "Durotar", "Valley of Trials"
    function GetZoneText() return ZONE end
    function GetSubZoneText() return SUBZONE end
    function GetItemCount(id) return (BAGS and BAGS[id]) or 0 end
    function GetMoney() return MONEY or 0 end
    """)
    lua.execute(setup_lua)
    for f in harness.toc_files(routes=True):
        load(A + f)
    return lua

# ---------------------------------------------------------------- data checks
lua = session()
res = lua.execute("""
local FP = ForeverPlanner
local errs, nseg, nsteps = {}, 0, 0
local KNOWN = { a=1, t=1, c=1, o=1, l=1, g=1, z=1, b=1, tr=1, fp=1, tk=1, h=1, i=1 }
local function scan(seg)
  local ok, steps = pcall(seg.fn)
  if not ok or type(steps) ~= "table" then errs[#errs+1] = "steps fail " .. seg.id; return end
  for i, st in ipairs(steps) do
    nsteps = nsteps + 1
    if type(st.t) ~= "string" or type(st.lv) ~= "number" then errs[#errs+1] = seg.id .. ":" .. i .. " fields" end
    for _, g in ipairs(st.g or {}) do
      if not KNOWN[g[1]] then errs[#errs+1] = seg.id .. ":" .. i .. " kind " .. tostring(g[1]) end
      if g.x and (g.x < -5 or g.x > 105 or g.y < -5 or g.y > 105) then errs[#errs+1] = seg.id .. ":" .. i .. " coords " .. g.x .. "," .. g.y end
      if (g[1] == "a" or g[1] == "t" or g[1] == "c" or g[1] == "o") and not FP.QT[g[2]] then errs[#errs+1] = seg.id .. " no title " .. g[2] end
      if g[1] == "o" and not g.i then errs[#errs+1] = seg.id .. " objective without index" end
    end
  end
end
for _, seg in pairs(FP.segments) do nseg = nseg + 1; scan(seg) end
for _, seg in pairs(FP.sides) do nseg = nseg + 1; scan(seg) end
local nt = 0
for cls, b in pairs(FP.talentBuilds) do
  nt = nt + 1
  for _, bd in ipairs(b.builds) do
    local n = 0
    for lvl = 10, 60 do if bd.talents[lvl] then n = n + 1 end end
    if n ~= 51 then errs[#errs+1] = cls .. " " .. bd.key .. " has " .. n .. " picks" end
  end
end
return table.concat(errs, "; "), nseg, nsteps, nt
""")
errs, nseg, nsteps, nt = res
check(errs == "", "route and talent data valid: " + errs[:500])
check(nseg >= 150, "segments and class guides loaded (%d)" % nseg)
check(nt == 9, "talent builds for all nine classes")
print("   segments:", nseg, "steps:", nsteps)

# Every race/class pair in Forever reaches level 60 on its faction's road.
combos = lua.execute("""
local FP = ForeverPlanner
local out = {}
local pairs_ = {
  Horde = { Orc = {"WARRIOR","HUNTER","ROGUE","SHAMAN","WARLOCK","MAGE"}, Troll = {"WARRIOR","HUNTER","ROGUE","PRIEST","SHAMAN","MAGE","WARLOCK"},
            Tauren = {"WARRIOR","HUNTER","SHAMAN","DRUID","PALADIN"}, Scourge = {"WARRIOR","ROGUE","PRIEST","MAGE","WARLOCK","PALADIN"},
            Skyborne = {"WARRIOR","HUNTER","ROGUE","PRIEST","SHAMAN","MAGE","DRUID"} },
  Alliance = { Human = {"WARRIOR","PALADIN","ROGUE","PRIEST","MAGE","WARLOCK","HUNTER"}, Dwarf = {"WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","SHAMAN"},
            Gnome = {"WARRIOR","ROGUE","MAGE","WARLOCK","PRIEST"}, NightElf = {"WARRIOR","HUNTER","ROGUE","PRIEST","DRUID"},
            Skyborne = {"WARRIOR","HUNTER","ROGUE","PRIEST","SHAMAN","MAGE","DRUID"} },
}
local bad = {}
local n = 0
for fac, races in pairs(pairs_) do
  for race, classes in pairs(races) do
    for _, cls in ipairs(classes) do
      FP.class, FP.race, FP.faction = cls, race, fac
      FP.char = { doneIds = {}, setup = nil }
      local ok, err = pcall(FP.BuildPlan, FP)
      n = n + 1
      if not ok then bad[#bad+1] = fac .. " " .. race .. " " .. cls .. ": " .. tostring(err)
      else
        local r = FP.plan.route
        local last = r[#r]
        local chain = FP.plan.routeChain
        if #r < 300 then bad[#bad+1] = race .. " " .. cls .. " only " .. #r .. " steps" end
        if not last or last.lvl < 58 then bad[#bad+1] = race .. " " .. cls .. " ends at " .. tostring(last and last.lvl) end
        if not next(FP.plan.talents) then bad[#bad+1] = cls .. " no talents" end
        local keys = {}
        for _, s in ipairs(r) do if keys[s.key] then bad[#bad+1] = "dup key " .. s.key end; keys[s.key] = true end
      end
    end
  end
end
return table.concat(bad, "; "), n
""")
check(combos[0] == "", "every race/class pair gets a route to 60 and talents (%d pairs) %s" % (combos[1], combos[0][:400]))

# Every class file's macros fit in 255 characters and cover their levels without overlaps.
mres = lua.execute("""
local FP = ForeverPlanner
local bad, n = {}, 0
for cls, c in pairs(FP.classes) do
  local lists = {}
  if c.plan then lists[#lists+1] = c.plan.macros end
  for _, s in pairs(c.specs or {}) do lists[#lists+1] = s.macros end
  for _, list in ipairs(lists) do
    local seen = {}
    for _, m in ipairs(list or {}) do
      n = n + 1
      if #m.text > 255 then bad[#bad+1] = cls .. " " .. m.name .. " " .. #m.text end
      if m.text:sub(1, 12) ~= "#showtooltip" then bad[#bad+1] = cls .. " " .. m.name .. " no #showtooltip" end
      for l = m.from, m.to do
        local k = m.name .. l
        if seen[k] then bad[#bad+1] = cls .. " " .. m.name .. " overlaps at " .. l end
        seen[k] = true
      end
    end
  end
end
return table.concat(bad, "; "), n
""")
check(mres[0] == "", "class macros: %d checked, all <= 255 chars, no overlaps %s" % (mres[1], mres[0]))

# ---------------------------------------------------------------- a new Troll Warlock
lua = session("""
PLAYER_CLASS, PLAYER_CLASS_NAME, PLAYER_RACE, PLAYER_FACTION, PLAYER_LEVEL = "WARLOCK", "Warlock", "Troll", "Horde", 1
""")
run = lua.execute
run('FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD"); FlushTimers()')
FP = lua.globals().ForeverPlanner
check(lua.globals().ForeverPlannerSetup is not None and lua.globals().ForeverPlannerSetup.shown, "setup window opens on first login")
check(run("return ForeverPlanner.plan.routeChain[1]") == "Durotar", "Troll starts in Durotar")
check(run("return ForeverPlanner.plan.routeChain[2]") == "Silverpine Forest", "then Silverpine Forest")
check(run("return ForeverPlanner.plan.talents[10]") == "Improved Corruption 1", "Affliction talents by default (10: Improved Corruption)")
specs = run("local t={} for _,c in ipairs(ForeverPlanner:SpecChoices()) do t[#t+1]=c.key..(c.recommended and '*' or '') end return table.concat(t,',')")
check(specs.startswith("affliction*") and "demonology" in specs and "destruction" in specs, "spec choices offered, recommended first: " + specs)
run('ForeverPlanner:ApplySetup("demonology", false)')
check(run("return ForeverPlanner.plan.talents[10]") == "Demonic Embrace 1", "picking Demonology switches talents")
run('ForeverPlanner:ApplySetup("affliction", false)')
check(run("return ForeverPlanner.char.setup.spec") == "affliction", "setup saved per character")
check(run("local t={} for _,m in ipairs(ForeverPlanner:CurrentMacros()) do t[#t+1]=m.name end return table.concat(t,',')") == "ATTACK,DOTS,DRAIN,PET,SELF",
      "Warlock macro set: ATTACK, DOTS, DRAIN, PET, SELF")
check(run("return ForeverPlanner.plan.gear and #ForeverPlanner.plan.gear") == 5, "Warlock gear brackets")
check(run("return ForeverPlanner.plan.training[8]") == "Bane of Agony, Fear", "trainer notes")

cur = lambda: run("local s = ForeverPlanner.plan.route[ForeverPlanner.current]; return s and s.title")
check(cur() == "Kaltunk", "step 1: Kaltunk")
check(run("for _,o in ipairs(ForeverPlanner.plan.route[1].q) do if o.id == 1485 then return true end end return false"), "Warlock sees Vile Familiars (1485)")
check(not run("for _,s in ipairs(ForeverPlanner.plan.route) do for _,o in ipairs(s.q) do if o.k=='a' and o.id == 792 then return true end end end return false"),
      "Warlock doesn't get the other classes' Vile Familiars (792)")
check(run("for _,s in ipairs(ForeverPlanner.plan.route) do if s.title == 'Druid trainer' then return true end end return false") is False,
      "other classes' trainer steps left out")
check("Accept Your Place in the World" in (run("return (ForeverPlanner:NextAction(ForeverPlanner.plan.route[ForeverPlanner.current]))") or ""), "Next: accept the first quest")

# Quests are matched by ID
run("""
QUESTLOG = { { title = "Cutting Teeth", id = 788 }, { title = "Wayward Weapons", id = 97279 }, { title = "Vile Familiars", id = 1485 } }
COMPLETED[4641] = true
FireEvent("QUEST_TURNED_IN", 4641); FireEvent("QUEST_ACCEPTED"); FlushTimers()
""")
check(cur() == "Training weapons and boars", "accepting and turning in moves to step 2: " + str(cur()))
run("""
OBJECTIVES[788] = { true }; OBJECTIVES[97279] = { true }
FireEvent("QUEST_LOG_UPDATE"); FlushTimers()
""")
check(cur() == "Training weapons and boars" and "The Den" in run("return (ForeverPlanner:NextAction(ForeverPlanner.plan.route[ForeverPlanner.current]))"),
      "objectives done: Next says go to the Den")
run('COMPLETED[788] = true; FireEvent("QUEST_TURNED_IN", 788); FireEvent("QUEST_LOG_UPDATE"); FlushTimers()')
check(cur() == "The Den", "handing in at the Den passes the 'go to the Den' point: " + str(cur()))
# The Den: trainer visit + hand-ins; the trainer goal is ticked by opening the trainer window
run("""
QUESTLOG = { { title = "Vile Familiars", id = 1485 }, { title = "Sting of the Scorpid", id = 789 }, { title = "Galgar's Cactus Apple Surprise", id = 4402 } }
for _, id in ipairs({97279, 98575}) do COMPLETED[id] = true; FireEvent("QUEST_TURNED_IN", id) end
FireEvent("QUEST_LOG_UPDATE"); FlushTimers()
""")
check(cur() == "The Den", "quests done but trainer not visited: still on the Den")
check("class trainer" in (run("return (ForeverPlanner:NextAction(ForeverPlanner.plan.route[ForeverPlanner.current]))") or ""), "Next: visit your class trainer")
run('FireEvent("TRAINER_SHOW"); FlushTimers()')
check(cur() == "Hana'zua", "trainer window ticks it: on to Hana'zua: " + str(cur()))

# A soft-only step is passed once a later step shows progress
idx_class = run("for i,s in ipairs(ForeverPlanner.plan.route) do if s.title=='Class trainer' then return i end end")
run("""
QUESTLOG = { { title = "Vile Familiars", id = 1485, complete = true }, { title = "Sting of the Scorpid", id = 789, complete = true },
  { title = "Galgar's Cactus Apple Surprise", id = 4402, complete = true }, { title = "Lieutenant's Insignia", id = 804 } }
OBJECTIVES[1485] = { true }; OBJECTIVES[789] = { true }; OBJECTIVES[4402] = { true }; OBJECTIVES[790] = { true }
COMPLETED[790] = true; FireEvent("QUEST_TURNED_IN", 790)
COMPLETED[4402] = true; FireEvent("QUEST_TURNED_IN", 4402)
FireEvent("QUEST_LOG_UPDATE"); FlushTimers()
""")
check(cur() == "Class trainer", "level-2 trainer step comes up: " + str(cur()))
run('COMPLETED[804] = true; FireEvent("QUEST_TURNED_IN", 804); FireEvent("QUEST_LOG_UPDATE"); FlushTimers()')
check(run("return ForeverPlanner.status[%d]" % idx_class) == "done", "trainer step passed after progress on the next step")

# Places: a 'go here' step ticks when you stand there
gi = run("for i,s in ipairs(ForeverPlanner.plan.route) do if s.title=='Burning Blade Coven' then return i end end")
run("ForeverPlanner.view = nil; for i = 1, %d - 1 do ForeverPlanner.char.manual[ForeverPlanner.plan.route[i].key] = true end; ForeverPlanner:Refresh(false)" % gi)
check(cur() == "Burning Blade Coven", "goto step current")
run("""
C_Map = { GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function() return { x = PX, y = PY } end }
PX, PY = 0.30, 0.30
ForeverPlanner:CheckLive()
""")
check(cur() == "Burning Blade Coven", "far away: not ticked")
run("PX, PY = 0.4505, 0.5602; ForeverPlanner:CheckLive()")
check(cur() == "Thazz'ril's Pick", "standing at the cave mouth ticks it: " + str(cur()))
check(run("return ForeverPlanner.char.ticks[ForeverPlanner.plan.route[%d].key .. '#1']" % gi) is True, "tick remembered for the character")

# Waypoint follows the first open goal
way = run("local m,x,y,l = ForeverPlanner:StepTarget(ForeverPlanner.plan.route[ForeverPlanner.current]); return m..' '..x..' '..y")
check(way == "1411 43.7 53.8", "waypoint at the pick: " + way)

# Level goals and conditions
li = run("""for i,s in ipairs(ForeverPlanner.plan.route) do for _,o in ipairs(s.q) do if o.k=='l' and not o.fr then return i end end end""")
lv = run("for _,o in ipairs(ForeverPlanner.plan.route[%d].q) do if o.k=='l' then return o.id end end" % li)
run("PLAYER_LEVEL = %d - 1" % lv)
check(not run("for idx,o in ipairs(ForeverPlanner.plan.route[%d].q) do if o.k=='l' then return ForeverPlanner:ObjDone(o) end end" % li), "level goal open below the level")
run("PLAYER_LEVEL = %d" % lv)
check(run("for idx,o in ipairs(ForeverPlanner.plan.route[%d].q) do if o.k=='l' then return ForeverPlanner:ObjDone(o) end end" % li), "level goal done at the level")
check(run("return ForeverPlanner:CondTrue({k='level', op='>=', n=5})") is True and run("return ForeverPlanner:CondTrue({k='level', op='<', n=5})") is False,
      "level conditions")
check(run("return ForeverPlanner:CondTrue({k='group', q=92706})") is False, "group quests off by default")
run("ForeverPlanner.char.setup.group = true")
check(run("return ForeverPlanner:CondTrue({k='group', q=92706})") is True, "group quests on when chosen")
check(run("return ForeverPlanner:CondTrue({k='turnedin', neg=true, q=4641})") is False, "!turnedin")
check(run("return ForeverPlanner:CondTrue({k='onquest', q={1485}})") is True, "onquest")

# Steps with a false condition are passed when the route reaches them, and stay passed
run("""
ForeverPlanner.plan.route[ForeverPlanner.current + 0].w = { { k = "level", op = "<", n = 2 } }
ForeverPlanner:Refresh(false)
""")
check(run("return ForeverPlanner.status[ForeverPlanner.current - 1]") in ("na", "done"), "condition false: step marked not needed")

# Class quests: Felhunter at 30
run("PLAYER_LEVEL = 30")
ready = run("local t={} for _,s in ipairs(ForeverPlanner:SideReady()) do t[#t+1]=s.id end return table.concat(t,',')")
check("class/warlock/felhunter-horde" in ready, "Felhunter class quest offered at 30: " + ready)
check("alliance" not in ready and "druid" not in ready, "only Horde Warlock class quests")
before = run("return #ForeverPlanner.plan.route")
curkey = run("return ForeverPlanner.plan.route[ForeverPlanner.current].key")
run('ForeverPlanner:StartSide("class/warlock/felhunter-horde")')
check(run("return #ForeverPlanner.plan.route") > before, "class quest steps added to the route")
check(run("return ForeverPlanner.plan.route[ForeverPlanner.current].sec").startswith("Class quest: Felhunter"), "current step is the class quest")
check(run("for i,s in ipairs(ForeverPlanner.plan.route) do if s.key=='%s' then return ForeverPlanner.plan.route[i-1].seg end end" % curkey) == "class/warlock/felhunter-horde",
      "inserted just before the step you were on")
check("felhunter" not in run("local t={} for _,s in ipairs(ForeverPlanner:SideReady()) do t[#t+1]=s.id end return table.concat(t,',')"), "no longer offered once started")

# ---------------------------------------------------------------- the existing Tauren Druid (0.4 -> 0.5)
lua = session("""
PLAYER_LEVEL = 22
ForeverPlannerDB = { titles = {}, lastVersion = "0.4.3" }
ForeverPlannerChar = { doneIds = { [1] = "Her Name Is Olgra" }, manual = {}, skip = {} }
QUESTLOG = { { title = "Her Name Is Olgra", id = 860 } }
""")
run = lua.execute
for qid, t in [(747, "The Hunt Begins"), (743, "Dangers of the Windfury"), (750, "The Hunt Continues"), (761, "Swoop Hunting")]:
    run('COMPLETED[%d] = true; QUESTIE_NAMES[%d] = "%s"' % (qid, qid, t))
run('FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD"); FlushTimers()')
check(run("return ForeverPlanner.plan.routeChain[1]") == "Mulgore", "Tauren Druid: Mulgore first for a new character")
check(run("return ForeverPlanner.plan.route[#ForeverPlanner.plan.route].key") == "55.11", "then the Druid's own route to 60")
check(run("return ForeverPlanner.plan.talents[20]") == lua.eval("ForeverPlanner.classes.DRUID.plan.talents[20]"), "Druid keeps its own talents")
run('ForeverPlanner:ApplySetup("feral", false)')
c = run("local s = ForeverPlanner.plan.route[ForeverPlanner.current]; return s.key")
check(":" not in c, "existing Druid: caught up past the starting zones to the Druid route (step %s)" % c)
check(run("return ForeverPlanner.char.lastCatchup and #ForeverPlanner.char.lastCatchup > 50"), "catchup can be undone")

print("FAILURES:", len(fails))
sys.exit(1 if fails else 0)
