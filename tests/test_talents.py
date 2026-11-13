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
SELECTED = 1
function PanelTemplates_GetSelectedTab() return SELECTED end
""")
for f in ["Core.lua", "Data/Druid.lua", "UI.lua"]: load(A + f)
lua.execute("""
FireEvent("ADDON_LOADED","ForeverPlanner"); FireEvent("PLAYER_LOGIN")
-- The Blizzard talent screen: buttons TalentFrameTalent1..n for the shown tree, plus 3 tabs
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
print("FAILURES:", len(fails))
sys.exit(1 if fails else 0)
