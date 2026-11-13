# Forever's talent window (PlayerSpellsFrame) on the modern C_Traits talent system.
import os, sys
from lupa.lua51 import LuaRuntime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness
S = os.path.dirname(os.path.abspath(__file__)); A = os.path.join(S, "..", "ForeverPlanner") + "/"
lua = LuaRuntime(unpack_returned_tuples=True); G = lua.globals()
def load(p):
    lua.eval("function(src,n) local f,e=loadstring(src,n); if not f then error(e) end; return f end")(open(p).read(), p)()
load(os.path.join(S, "wowstub.lua"))
fails = []
def check(c, m):
    print(("PASS " if c else "FAIL ") + m)
    if not c: fails.append(m)

lua.execute("""
GetNumTalentTabs, GetNumTalents, GetTalentInfo = nil, nil, nil   -- the old API is gone
function UnitCharacterPoints() return 0 end                        -- and reports nothing useful
PLAYER_LEVEL = 21
-- nodes: id -> { spell, name, icon, rank, max, tree }
NODES = {
  [101] = { 1, "Ferocity", 1001, 5, 5, 2 }, [102] = { 2, "Furor", 1002, 3, 5, 2 },
  [103] = { 3, "Feral Swiftness", 1003, 2, 2, 2 }, [104] = { 4, "Feral Charge", 1004, 1, 1, 2 },
  [105] = { 5, "Feral Instinct", 1005, 0, 3, 2 }, [106] = { 6, "Thick Hide", 1006, 0, 3, 2 },
  [201] = { 7, "Improved Wrath", 2001, 0, 5, 1 }, [301] = { 8, "Heart of the Wild", 3001, 0, 5, 3 },
}
UNSPENT = 1
C_ClassTalents = { GetActiveConfigID = function() return 77 end }
C_Traits = {
  GetConfigInfo = function(id) return { ID = id, treeIDs = { 900 } } end,
  GetTreeCurrencyInfo = function() return { { traitCurrencyID = 5, quantity = UNSPENT, spent = 11 } } end,
  GetTreeNodes = function() local t = {} for id in pairs(NODES) do t[#t + 1] = id end table.sort(t) return t end,
  GetNodeInfo = function(_, id) local n = NODES[id]; return { ID = id, isVisible = true, ranksPurchased = n[4], currentRank = n[4], maxRanks = n[5], entryIDs = { id * 10 } } end,
  GetEntryInfo = function(_, entryID) return { definitionID = entryID + 1 } end,
  GetDefinitionInfo = function(defID) local id = (defID - 1) / 10; return { spellID = NODES[id][1] + 5000 } end,
  GetSubTreeInfo = function() return nil end,
}
C_Spell = {
  GetSpellName = function(sid) for _, n in pairs(NODES) do if n[1] + 5000 == sid then return n[2] end end end,
  GetSpellTexture = function(sid) for _, n in pairs(NODES) do if n[1] + 5000 == sid then return n[3] end end end,
}
""")
for f in harness.toc_files(routes=False): load(A + f)
lua.execute("""
FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN")
UIParent.shown = true
local mt = getmetatable(CreateFrame("Frame"))
mt.CreateAnimationGroup = function(self)
  local ag = setmetatable({ scripts = {}, events = {}, playing = false }, mt)
  ag.CreateAnimation = function() return setmetatable({ scripts = {}, events = {} }, mt) end
  ag.Play = function(s) s.playing = true end; ag.Stop = function(s) s.playing = false end
  ag.IsPlaying = function(s) return s.playing end
  return ag
end
mt.SetParent = function(self, p) self.parent = p end
mt.GetWidth = function() return 40 end
mt.GetName = function(self) return self.name end
-- PlayerSpellsFrame with pooled, unnamed talent buttons (GetNodeID) and an icon texture each
local function obj(kind, name, parent)
  local o = { kind = kind, name = name, parent = parent, shown = true, kids = {}, regs = {} }
  o.IsVisible = function(s) local p = s while p and p ~= UIParent do if not p.shown then return false end p = p.parent end return true end
  o.IsShown = function(s) return s.shown end
  o.GetName = function(s) return s.name end
  o.GetParent = function(s) return s.parent end
  o.GetChildren = function(s) return unpack(s.kids) end
  o.GetRegions = function(s) return unpack(s.regs) end
  o.IsObjectType = function(s, t) return s.kind == t end
  o.GetWidth = function() return 40 end
  if parent and parent.kids then if kind == "Texture" then table.insert(parent.regs, o) else table.insert(parent.kids, o) end end
  return o
end
PlayerSpellsFrame = obj("Frame", "PlayerSpellsFrame", UIParent); PlayerSpellsFrame.shown = false
local talents = obj("Frame", nil, obj("Frame", nil, PlayerSpellsFrame))
for id, n in pairs(NODES) do
  local b = obj("Button", nil, talents); b.node = id; b.GetNodeID = function(s) return s.node end
  obj("Texture", nil, b).GetTexture = function() return n[3] end
end
EUI_TalentsRoute = obj("Frame", "EUI_TalentsRoute", UIParent)
function EnumerateFrames(prev) local l = { PlayerSpellsFrame, EUI_TalentsRoute } if prev == nil then return l[1] end for i, f in ipairs(l) do if f == prev then return l[i + 1] end end end
ForeverPlanner:FindTalentWindows()
function Tick() ForeverPlanner.talentWatcher.scripts.OnUpdate(nil, 0.3) end
""")
def state():
    return lua.execute("""
local function up(fn, name) local i = 1 while true do local n, v = debug.getupvalue(fn, i) if not n then return nil end if n == name then return v end i = i + 1 end end
local g, h = up(ForeverPlanner.UpdateTalentGlow, "glow"), up(ForeverPlanner.UpdateTalentGlow, "hint")
return g and g.shown and g.parent and g.parent.node, h and h.shown and h.text.text
""")
lua.execute("ForeverPlanner:ScanTalents()")
check(lua.execute("return ForeverPlanner.talentAPI") == "traits", "reads talents from C_Traits")
check(lua.execute("return ForeverPlanner:UnspentTalentPoints()") == 1, "unspent point comes from the talent currency, not UnitCharacterPoints")
nxt = lua.execute("local n = ForeverPlanner:NextTalentInfo(); return n.text, n.info and n.info.nodeID")
check(nxt[0] == "Feral Instinct 1" and nxt[1] == 105, "next pick Feral Instinct 1 on node 105: %s" % (nxt,))
lua.execute("PlayerSpellsFrame.shown = true; Tick()")
node, hint = state()
print("   hint:", hint)
check(node == 105, "Feral Instinct's button glows on PlayerSpellsFrame (node %s)" % node)
check(hint and "Spend your point" in hint, "note says to spend the point")
lua.execute("NODES[105][4] = 1; UNSPENT = 0; FireEvent('TRAIT_NODE_CHANGED'); Tick()")
node, hint = state()
check(not node and hint and "Next pick (level 22)" in hint, "after picking it (staged), glow off and next pick shown: %s" % hint)
lua.execute("SlashCmdList['FOREVERPLANNER']('talentdebug')")
for l in [l for l in G.OUT.values()][-4:]: print("   ", l)
print("FAILURES:", len(fails))
sys.exit(1 if fails else 0)
