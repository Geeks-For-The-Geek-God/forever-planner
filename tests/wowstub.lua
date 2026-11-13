-- Minimal WoW API stub for testing Forever Planner outside the game.
OUT = {}
local function log(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end OUT[#OUT + 1] = table.concat(t, " ") end

wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) log("CHAT", (m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "#"))) end }
UIParent = {}
UISpecialFrames = {}
SlashCmdList = {}
ChatFontNormal = {}

local EVENT_FRAMES = {}
local Widget = {}
Widget.__index = function(t, k)
  local v = rawget(Widget, k)
  if v then return v end
  if type(k) == "string" and k:match("^%u") then return function() return nil end end -- any other method is a no-op
end
function Widget:SetScript(n, f) self.scripts[n] = f end
function Widget:GetScript(n) return self.scripts[n] end
function Widget:RegisterEvent(e) self.events[e] = true; EVENT_FRAMES[self] = true end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:GetStringHeight() local n = 1; local t = self.text or ""; n = n + math.floor(#t / 60); for _ in t:gmatch("\n") do n = n + 1 end; return 12 * n end
function Widget:SetHeight(h) self.h = h end
function Widget:GetHeight() return self.h or 100 end
function Widget:SetSize(w, h) self.w, self.h = w, h end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:SetShown(v) self.shown = v and true or false end
function Widget:IsShown() return self.shown end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:CreateFontString() return setmetatable({ scripts = {}, events = {} }, Widget) end
function Widget:CreateTexture() return setmetatable({ scripts = {}, events = {} }, Widget) end
function Widget:EnableMouse() end

function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ kind = kind, name = name, scripts = {}, events = {}, shown = true }, Widget)
  if name then _G[name] = f end
  return f
end

function FireEvent(e, ...)
  for f in pairs(EVENT_FRAMES) do
    if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end
  end
end

-- Timers run when FlushTimers() is called
TIMERS = {}
C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end }
function FlushTimers() local t = TIMERS; TIMERS = {}; for _, fn in ipairs(t) do fn() end end

-- Player
PLAYER_LEVEL = 21
function UnitLevel() return PLAYER_LEVEL end
function UnitClass() return "Druid", "DRUID" end
TALENT_POINTS = 1
function UnitCharacterPoints() return TALENT_POINTS end
InCombatLockdown = function() return false end
PlaySound = function() end

-- Quest log: list of { title=, id=, complete= }
QUESTLOG = {}
function GetNumQuestLogEntries() return #QUESTLOG, #QUESTLOG end
function GetQuestLogTitle(i)
  local q = QUESTLOG[i]
  if not q then return nil end
  return q.title, 20, 0, false, false, q.complete and 1 or nil, 0, q.id
end
COMPLETED = {}
function GetQuestsCompleted() local t = {} for id in pairs(COMPLETED) do t[id] = true end return t end
QUESTIE_NAMES = {}
QuestieLoader = { ImportModule = function(_, name)
  if name == "QuestieDB" then return { QueryQuestSingle = function(id, key) return QUESTIE_NAMES[id] end } end
end }
function GetTitleText() return LAST_TITLE end

-- Talents
TALENTS = { { "Ferocity", 5 }, { "Furor", 3 }, { "Feral Swiftness", 0 }, { "Feral Charge", 0 }, { "Feral Instinct", 0 } }
function GetNumTalentTabs() return 1 end
function GetNumTalents() return #TALENTS end
function GetTalentInfo(_, i) local t = TALENTS[i]; return t[1], "", 1, 1, t[2], 5 end

-- Items
EQUIPPED = { [5] = "|cff1eff00|Hitem:1:0|h[Armor of the Fang]|h|r", [7] = "|cff1eff00|Hitem:2:0|h[Leggings of the Fang]|h|r" }
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] end
BAGS = { [0] = { "|cff1eff00|Hitem:3:0|h[Belt of the Fang]|h|r" } }
C_Container = {
  GetContainerNumSlots = function(b) return BAGS[b] and #BAGS[b] or 0 end,
  GetContainerItemLink = function(b, s) return BAGS[b] and BAGS[b][s] end,
}

-- Macros
MACROS = {}
function GetMacroIndexByName(n) for i, m in ipairs(MACROS) do if m.name == n then return i end end return 0 end
function EditMacro(i, n, icon, body) MACROS[i].body = body end
function CreateMacro(n, icon, body, perChar) MACROS[#MACROS + 1] = { name = n, body = body } return #MACROS end

-- Waypoints
TomTom = { AddWaypoint = function(_, map, x, y, opts) WAYPOINT = { map, x, y, opts.title } return {} end, RemoveWaypoint = function() end }
