import os, sys
from lupa.lua51 import LuaRuntime
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
-- Three trees like Classic: Balance, Feral Combat, Restoration (tab, index, tier, column, icon)
TREES = {
  { name = "Balance", talents = { { "Improved Wrath", 0, 1, 1, "icon_wrath" } } },
  { name = "Feral Combat", talents = {
      { "Ferocity", 5, 1, 2, "icon_ferocity" }, { "Feral Instinct", 0, 3, 1, "icon_instinct" },
      { "Feral Swiftness", 2, 2, 1, "icon_swift" }, { "Feral Charge", 1, 3, 3, "icon_charge" },
      { "Thick Hide", 0, 2, 3, "icon_hide" } } },
  { name = "Restoration", talents = { { "Furor", 3, 1, 3, "icon_furor" }, { "Heart of the Wild", 0, 6, 2, "icon_hotw" } } },
}
function GetNumTalentTabs() return #TREES end
function GetTalentTabInfo(tab) return TREES[tab].name end
function GetNumTalents(tab) return #TREES[tab].talents end
function GetTalentInfo(tab, i) local t = TREES[tab].talents[i]; return t[1], t[5], t[3], t[4], t[2], 5 end
PLAYER_LEVEL = 21; TALENT_POINTS = 1
local mt = getmetatable(CreateFrame("Frame"))
mt.CreateAnimationGroup = function(self)
  local ag = setmetatable({ scripts = {}, events = {}, playing = false }, mt)
  ag.CreateAnimation = function() return setmetatable({ scripts = {}, events = {} }, mt) end
  ag.Play = function(s) s.playing = true end
  ag.Stop = function(s) s.playing = false end
  ag.IsPlaying = function(s) return s.playing end
  return ag
end
mt.GetID = function(self) return self.id end
mt.SetParent = function(self, p) self.parent = p end
mt.GetWidth = function() return 37 end
mt.GetName = function(self) return self.name end
SELECTED = 1
function PanelTemplates_GetSelectedTab() return SELECTED end
""")
for f in ["Core.lua", "Data/Druid.lua", "UI.lua"]: load(A + f)
lua.execute("""
FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN")
-- Classic's Blizzard talent screen: buttons TalentFrameTalent1..n for the shown tree, plus 3 tabs
TalentFrame = CreateFrame("Frame", "TalentFrame"); TalentFrame.shown = false
for t = 1, 3 do CreateFrame("Button", "TalentFrameTab" .. t) end
function ShowTree(tab)
  SELECTED = tab
  for i = 1, 6 do local b = _G["TalentFrameTalent" .. i]; if b then b.shown = false end end
  for i, t in ipairs(TREES[tab].talents) do
    local b = _G["TalentFrameTalent" .. i] or CreateFrame("Button", "TalentFrameTalent" .. i)
    b.id = i; b.shown = true
    local ic = _G["TalentFrameTalent" .. i .. "IconTexture"] or CreateFrame("Frame", "TalentFrameTalent" .. i .. "IconTexture")
    ic.GetTexture = function() return t[5] end
  end
end
function Tick() ForeverPlanner.talentWatcher.scripts.OnUpdate(nil, 0.3) end
ForeverPlanner:FindTalentWindows()
""")
def glow_parent():
    return lua.execute("""
local function up(fn, name) local i = 1 while true do local n, v = debug.getupvalue(fn, i) if not n then return nil end if n == name then return v end i = i + 1 end end
local g, tg, h = up(ForeverPlanner.UpdateTalentGlow, "glow"), up(ForeverPlanner.UpdateTalentGlow, "tabGlow"), up(ForeverPlanner.UpdateTalentGlow, "hint")
return g and g.shown and g.parent and g.parent.name, tg and tg.shown and tg.parent and tg.parent.name, h and h.shown and h.text.text
""")

nxt = lua.execute("local n = ForeverPlanner:NextTalentInfo(); return n.text, n.info and n.info.tab, n.info and n.info.tier")
check(nxt[0] == "Feral Instinct 1" and nxt[1] == 2, "next pick is Feral Instinct 1 in tree 2: %s" % (nxt,))

lua.execute("ShowTree(1); TalentFrame.shown = true; Tick()")
g, tg, h = glow_parent()
print("   hint:", h); print("   glow:", g, "tab glow:", tg)
check(not g and tg == "TalentFrameTab2", "on the Balance tree: the Feral tab glows, no talent glows")
check(h and "Spend your point" in h and "Feral Combat tree, row 3, column 1" in h, "hint says what and where")

lua.execute("ShowTree(2); Tick()")
g, tg, h = glow_parent()
check(g == "TalentFrameTalent2" and not tg, "on the Feral tree: Feral Instinct's button glows (%s)" % g)

lua.execute("TREES[2].talents[2][2] = 1; TALENT_POINTS = 0; FireEvent('CHARACTER_POINTS_CHANGED'); Tick()")
g, tg, h = glow_parent()
check(not g and not tg and h and "Next pick (level" in h, "after spending: glow off, hint shows the next pick: %s" % h)

lua.execute("TalentFrame.shown = false; Tick()")
g, tg, h = glow_parent()
check(not g and not h, "closing the talent screen hides everything")

lua.execute("TALENT_POINTS = 1; PLAYER_LEVEL = 22; TalentFrame.shown = true; ShowTree(2); SlashCmdList['FOREVERPLANNER']('talentglow'); Tick()")
g, tg, h = glow_parent()
check(not g and not h, "/fp talentglow turns it off")
lua.execute("SlashCmdList['FOREVERPLANNER']('talentglow'); Tick()")
g, tg, h = glow_parent()
check(g == "TalentFrameTalent2", "and back on (Feral Instinct 2 next)")

# Fallback points when the client has no point API
lua.execute("UnitCharacterPoints = nil; ForeverPlanner:ScanTalents()")
pts = lua.execute("return ForeverPlanner:UnspentTalentPoints()")
check(pts == 22 - 9 - 12, "fallback unspent points from level and spent ranks: %s" % pts)

# ---------- Forever's three-tree window: unnamed nested buttons, found by icon ----------
lua.execute("""
TalentFrame.shown = false; Tick()
TREES[2].talents[2][2] = 0; TALENT_POINTS = 1; PLAYER_LEVEL = 21; ForeverPlanner:ScanTalents()
local function obj(kind, name, parent)
  local o = { kind = kind, name = name, parent = parent, shown = true, kids = {}, regs = {} }
  o.IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end
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
ALLFRAMES = {}; UIParent.shown = true
Window = obj("Frame", "ForeverTalentsWindow", UIParent); Window.shown = false
table.insert(ALLFRAMES, Window)
for t, tree in ipairs(TREES) do
  local col = obj("Frame", nil, Window)
  local inner = obj("Frame", nil, col)
  for i, tal in ipairs(tree.talents) do
    local b = obj("Button", nil, inner); b.tal = tal[1]
    local ic = obj("Texture", nil, b); ic.GetTexture = function() return tal[5] end
    obj("Texture", nil, b).GetTexture = function() return "border" end
  end
end
function EnumerateFrames(prev)
  if prev == nil then return ALLFRAMES[1] end
  for i, f in ipairs(ALLFRAMES) do if f == prev then return ALLFRAMES[i + 1] end end
end
ForeverPlanner:FindTalentWindows()
Window.shown = true; Tick()
""")
r = lua.execute("""
local function up(fn, name) local i = 1 while true do local n, v = debug.getupvalue(fn, i) if not n then return nil end if n == name then return v end i = i + 1 end end
local g = up(ForeverPlanner.UpdateTalentGlow, "glow")
local h = up(ForeverPlanner.UpdateTalentGlow, "hint")
return g.shown and g.parent and g.parent.tal, h.shown and h.text.text, #ForeverPlanner.talentWindows
""")
print("   modern hint:", r[1])
check(r[0] == "Feral Instinct", "Forever-style window: Feral Instinct's unnamed button glows (%s)" % r[0])
check(r[2] >= 1, "the window was found by name scan")
lua.execute("SlashCmdList['FOREVERPLANNER']('talentdebug')")
dbg = [l for l in G.OUT.values()][-4:]
for l in dbg: print("   ", l)
check(any("Button on" in l and "not found" not in l for l in dbg), "/fp talentdebug reports the match")
print("FAILURES:", len(fails))
sys.exit(1 if fails else 0)
