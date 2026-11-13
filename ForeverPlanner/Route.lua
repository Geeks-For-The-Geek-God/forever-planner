-- Forever Planner: plans for every character.
-- Builds this character's plan from the levelling segments (Data/Routes), the class file
-- (Data/Classes/<Class>.lua) and the talent builds (Data/Talents.lua), and works out the
-- route goals the quest log can't see (places, trainers, flight paths, levels).
-- Reads game state and shows advice only.

local FP = ForeverPlanner
local Norm = FP.Norm

FP.segments = {}      -- id -> segment header (+ fn that returns its steps)
FP.sides = {}         -- id -> class quest side guide
FP.QT = {}            -- quest ID -> title (from the route data)
FP.MAPNAME = {}       -- uiMapID -> zone name
FP.talentBuilds = {}  -- class token -> builds
FP.classes = {}       -- class token -> class file data

------------------------------------------------------------------------
-- Registration (called by the data files)
------------------------------------------------------------------------
local R = {}
function FP:RouteData() return R end
function R:Titles(t) for id, title in pairs(t) do if not FP.QT[id] then FP.QT[id] = title end end end
function R:Zones(t) for id, name in pairs(t) do FP.MAPNAME[id] = name end end
function R:Segment(head, fn)
  head.fn = fn
  if head.classes then FP.sides[head.id] = head else FP.segments[head.id] = head end
end

function FP:RegisterTalentBuilds(b) self.talentBuilds[b.class] = b end

-- Class files: FP:RegisterClass({ class = "WARLOCK", recommended = "affliction",
--   specs = { affliction = { name = "...", talents = {...}?, macros = {...}, gear = {...}, ... } } })
function FP:RegisterClass(c)
  local old = self.classes[c.class] or {}
  for k, v in pairs(c) do old[k] = v end
  self.classes[c.class] = old
end

-- Older class files register one finished plan (the Druid's own route from level 20).
function FP:RegisterPlan(plan)
  local c = self.classes[plan.class] or { class = plan.class }
  c.plan = plan
  self.classes[plan.class] = c
end

local function Steps(seg)
  if not seg.steps then
    local ok, s = pcall(seg.fn)
    seg.steps = (ok and type(s) == "table") and s or {}
  end
  return seg.steps
end

------------------------------------------------------------------------
-- Who is playing
------------------------------------------------------------------------
local RACE_ALIAS = { scourge = "undead" }
local function NormRace(r) r = type(r) == "string" and r:lower() or ""; return RACE_ALIAS[r] or r end

function FP:ReadIdentity()
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  self.class = self:Readable(class)
  self.race = self:Readable(race)
  self.faction = self:Readable(faction)
end

local function ListMatches(list, value, norm)
  if type(list) ~= "table" or #list == 0 then return true end
  norm = norm or function(v) return type(v) == "string" and v:lower() or "" end
  value = norm(value)
  local positives, hit = false, false
  for _, e in ipairs(list) do
    local neg = e:sub(1, 1) == "!"
    if neg then e = e:sub(2) end
    e = norm(e)
    if neg then
      if e == value then return false end
    else
      positives = true
      if e == value then hit = true end
    end
  end
  return hit or not positives
end

-- A goal's or step's filter: { c = classes, r = races, fa = factions }.
function FP:Matches(f)
  if not f then return true end
  return ListMatches(f.c, self.class) and ListMatches(f.r, self.race, NormRace) and ListMatches(f.fa, self.faction)
end

------------------------------------------------------------------------
-- Building the plan
------------------------------------------------------------------------
function FP:StartSegment()
  local best
  for _, seg in pairs(self.segments) do
    if seg.faction == self.faction and seg.min <= 1 and seg.races and ListMatches(seg.races, self.race, NormRace) then
      if not best or seg.id < best.id then best = seg end
    end
  end
  return best
end

-- The chain of segments from the starting zone, stopping before one that starts at or above `limit`.
function FP:SegmentChain(limit)
  local list, seen = {}, {}
  local seg = self:StartSegment()
  while seg and not seen[seg.id] do
    if limit and seg.min >= limit then break end
    seen[seg.id] = true
    list[#list + 1] = seg
    seg = seg.next and self.segments[seg.next]
  end
  return list
end

local function GoalCoords(g)
  if g.m and g.x and g.y then return g.m, g.x, g.y end
end

-- Turns one route-data step into the engine's step shape.
local function MakeStep(seg, i, st, prefix)
  local step = {
    key = (prefix or "") .. seg.id .. ":" .. i, sec = ("%s (%d-%d)"):format(seg.title or seg.id, seg.min, seg.max),
    lvl = st.lv, title = st.t ~= "" and st.t or (seg.title or "Step"), note = st.n, w = st.w,
    along = st.al, label = st.lb, seg = seg.id, q = {},
  }
  for _, g in ipairs(st.g or {}) do
    if FP:Matches(g.f) then
      local o = { k = g[1], id = g[2], i = g.i, txt = g.txt, note = g.n2, m = g.m, x = g.x, y = g.y,
        n = g.n, fr = g.fr, at = g.at, opt = g.opt, grp = g.grp, ml = g.ml }
      if (o.k == "a" or o.k == "t" or o.k == "c" or o.k == "o") and o.id and o.id ~= 0 then
        o.q = FP.QT[o.id] or o.txt or ("Quest " .. o.id)
      end
      step.q[#step.q + 1] = o
      if not step.map then
        local m, x, y = GoalCoords(o)
        if m then step.map, step.x, step.y = m, x, y end
      end
    end
  end
  return step
end

function FP:SegmentSteps(seg, prefix)
  local out = {}
  for i, st in ipairs(Steps(seg)) do
    if self:Matches(st.f) then
      local had = st.g and #st.g > 0
      local step = MakeStep(seg, i, st, prefix)
      if not had or #step.q > 0 then out[#out + 1] = step end
    end
  end
  return out
end

function FP:CurrentSpec()
  local setup = self.char and self.char.setup
  local cls = self.classes[self.class] or {}
  local builds = self.talentBuilds[self.class]
  local spec = setup and setup.spec
  if spec then return spec end
  if cls.recommended then return cls.recommended end
  if cls.plan and cls.plan.spec then return cls.plan.spec end
  return builds and builds.builds[1] and builds.builds[1].key or nil
end

-- Every spec this character can pick, recommended first.
function FP:SpecChoices()
  local out, seen = {}, {}
  local cls = self.classes[self.class] or {}
  local builds = self.talentBuilds[self.class]
  local rec = cls.recommended or (cls.plan and cls.plan.spec) or (builds and builds.builds[1] and builds.builds[1].key)
  local function add(key, name, desc)
    if seen[key] then return end
    seen[key] = true
    local e = { key = key, name = name, desc = desc, recommended = (key == rec) }
    if e.recommended then table.insert(out, 1, e) else out[#out + 1] = e end
  end
  if cls.plan and cls.plan.spec then add(cls.plan.spec, cls.plan.name, "Your plan from your class chat: route, talents, macros and gear.") end
  for key, s in pairs(cls.specs or {}) do add(key, s.name or key, s.desc) end
  for _, b in ipairs(builds and builds.builds or {}) do
    local first
    for lvl = 10, 60 do if b.notes and b.notes[lvl] then first = b.notes[lvl]; break end end
    add(b.key, b.spec .. " (" .. b.split .. ")", first)
  end
  return out
end

-- Assembles self.plan for this character.
function FP:BuildPlan()
  local cls = self.classes[self.class] or {}
  local builds = self.talentBuilds[self.class]
  local specKey = self:CurrentSpec()
  local legacy = cls.plan and (not cls.plan.spec or cls.plan.spec == specKey) and cls.plan or nil
  local spec = (cls.specs and cls.specs[specKey]) or {}
  local build
  for _, b in ipairs(builds and builds.builds or {}) do if b.key == specKey then build = b end end
  local plan = { class = self.class, spec = specKey }
  local function pick(k) return (legacy and legacy[k]) or spec[k] or cls[k] end
  plan.talents = pick("talents") or (build and build.talents) or {}
  plan.talentNotes = (not legacy and not spec.talents and build) and build.notes or nil
  plan.talentNote = pick("talentNote") or (build and ("%s build %s, from %s (%s)."):format(build.spec, build.split,
    builds.source or "ForeverDB", builds.checkedOn or "")) or nil
  for _, k in ipairs({ "macros", "training", "gear", "stopgaps", "sets", "macroNote" }) do plan[k] = pick(k) end
  plan.macros = plan.macros or {}

  -- Route: levelling segments from the starting zone, then the class file's own route if it has one.
  local route, chain = {}, self:SegmentChain(legacy and legacy.routeFromLevel)
  local names = {}
  for _, seg in ipairs(chain) do
    names[#names + 1] = seg.title
    for _, s in ipairs(self:SegmentSteps(seg)) do route[#route + 1] = s end
  end
  if legacy and legacy.route then
    plan.preludeEnd, plan.routeFrom = #route, legacy.routeFromLevel
    for _, s in ipairs(legacy.route) do route[#route + 1] = s end
    names[#names + 1] = legacy.routeName or "your class route"
  end
  -- Class quests you chose to do, placed before the step you were on when you started them.
  local det = self.char and self.char.detours or {}
  for sideId, anchor in pairs(det) do
    local side = self.sides[sideId]
    if side then
      local at = #route + 1
      for i, s in ipairs(route) do if s.key == anchor then at = i; break end end
      local steps = self:SegmentSteps(side, "side:")
      for k, s in ipairs(steps) do s.sec = "Class quest: " .. (side.title or sideId); table.insert(route, at + k - 1, s) end
    end
  end
  for i, s in ipairs(route) do s.num = i end
  plan.route = route
  plan.routeChain = names

  local specName = (legacy and legacy.name) or spec.name or (build and build.spec) or ""
  plan.name = legacy and legacy.name or ((specName ~= "" and (specName .. " ") or "") .. (self.className or self.class or ""))
  plan.routeName = legacy and legacy.routeName or ("Levelling route: " .. table.concat(names, " > "))
  plan.routeUrl = legacy and legacy.routeUrl
  self.plan = plan
  self.stepIdx = nil
  return plan
end

-- Route data for the other faction is never used by this character; let it be freed.
function FP:FreeOtherFaction()
  for _, seg in pairs(self.segments) do
    if seg.faction ~= self.faction then seg.fn = nil; seg.steps = nil end
  end
  for _, side in pairs(self.sides) do
    if not self:SideMatches(side) then side.fn = nil; side.steps = nil end
  end
end

------------------------------------------------------------------------
-- Class quest side guides (pets, forms, class items)
------------------------------------------------------------------------
function FP:SideMatches(side)
  if side.faction and side.faction ~= self.faction then return false end
  if side.races and not ListMatches(side.races, self.race, NormRace) then return false end
  return ListMatches(side.classes, self.class)
end

function FP:SideDone(side)
  local any = false
  if not side.fn and not side.steps then return false end
  for _, st in ipairs(Steps(side)) do
    for _, g in ipairs(st.g or {}) do
      if g[1] == "t" and self:Matches(g.f) then
        any = true
        if not self.char.doneIds[g[2]] then return false end
      end
    end
  end
  return any
end

-- Side guides for your level that you haven't done, started or dismissed.
function FP:SideReady()
  local out = {}
  if not self.char then return out end
  local lvl = self:PlayerLevel()
  for id, side in pairs(self.sides) do
    if self:SideMatches(side) and lvl >= side.min and lvl <= side.max + 6
        and not (self.char.detours and self.char.detours[id]) and not (self.char.sideDismissed and self.char.sideDismissed[id])
        and not self:SideDone(side) then
      out[#out + 1] = side
    end
  end
  table.sort(out, function(a, b) if a.min ~= b.min then return a.min < b.min end return a.id < b.id end)
  return out
end

function FP:StartSide(id)
  local side = self.sides[id]
  if not side then return end
  local route = self.plan.route
  local cur = self.current and route[self.current]
  self.char.detours = self.char.detours or {}
  self.char.detours[id] = cur and cur.key or "end"
  self:BuildPlan()
  self.view = nil
  self:Refresh(false)
  self:Print(("Class quest added before your current step: %s. It's now on your tracker."):format(side.title))
  local s = self.current and self.plan.route[self.current]
  if s and self.char.autoWay then self:SetWaypoint(s, true) end
end

function FP:DismissSide(id)
  self.char.sideDismissed = self.char.sideDismissed or {}
  self.char.sideDismissed[id] = true
  if self.UpdateUI then self:UpdateUI() end
end

------------------------------------------------------------------------
-- Conditions on steps ("when"): checked when the route reaches the step
------------------------------------------------------------------------
local function Cmp(a, op, b)
  if op == "<" then return a < b elseif op == "<=" then return a <= b
  elseif op == ">" then return a > b else return a >= b end
end

function FP:LevelProgress()
  local lvl = self:PlayerLevel()
  local xp = self:Readable(UnitXP and UnitXP("player")) or 0
  local max = self:Readable(UnitXPMax and UnitXPMax("player")) or 0
  if type(xp) == "number" and type(max) == "number" and max > 0 then return lvl + xp / max end
  return lvl
end

function FP:SkillRank(name)
  if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
  local want = Norm(name)
  local rank
  pcall(function()
    for i = 1, GetNumSkillLines() do
      local n, header, _, r = GetSkillLineInfo(i)
      if not header and Norm(n) == want then rank = r; return end
    end
  end)
  return rank or 0
end

function FP:KnowsSpell(id)
  if not id then return false end
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, r = pcall(C_SpellBook.IsSpellKnown, id); if ok and r then return true end
  end
  if IsPlayerSpell then local ok, r = pcall(IsPlayerSpell, id); if ok and r then return true end end
  if IsSpellKnown then local ok, r = pcall(IsSpellKnown, id); if ok and r then return true end end
  return false
end

local function Ids(q) if type(q) == "table" then return q end return { q } end

function FP:CondTrue(c)
  local k, r = c.k, true
  if k == "level" then
    local lv = c.frac and self:LevelProgress() or self:PlayerLevel()
    return Cmp(lv, c.op, (c.n or 0) + (c.frac or 0))
  elseif k == "money" then
    r = Cmp(self:Readable(GetMoney and GetMoney()) or 0, c.op, c.n or 0)
  elseif k == "onquest" then
    r = false
    for _, id in ipairs(Ids(c.q)) do if self.logById[id] then r = true end end
  elseif k == "complete" then
    local L = self.logById[Ids(c.q)[1]]
    r = (L and L.complete) and true or false
  elseif k == "turnedin" then
    r = self.char.doneIds[Ids(c.q)[1]] and true or false
  elseif k == "available" then
    local id = Ids(c.q)[1]
    r = not self.char.doneIds[id] and not self.logById[id] and self:PlayerLevel() >= (c.minLevel or 1)
    for _, p in ipairs(c.pre or {}) do if not self.char.doneIds[p] then r = false end end
  elseif k == "has" then
    r = ((GetItemCount and GetItemCount(c.item)) or 0) >= (c.n or 1)
  elseif k == "knows" then
    r = self:KnowsSpell(c.spell)
  elseif k == "skill" then
    r = (self:SkillRank(c.name) or 0) >= (c.n or 1)
  elseif k == "zone" then
    r = (GetZoneText and GetZoneText() == c.name) or (GetSubZoneText and GetSubZoneText() == c.name) or false
  elseif k == "bound" then
    r = (GetBindLocation and GetBindLocation() == c.name) or false
  elseif k == "group" then
    local q = Ids(c.q)[1]
    local pick = self.char.groupQuests and self.char.groupQuests[q]
    if pick == nil then pick = self.char.setup and self.char.setup.group end
    r = pick and true or false
  elseif k == "dungeon" then
    r = (self.char.setup and self.char.setup.dungeons) and true or false
  elseif k == "done" then
    r = false
    for i, s in ipairs(self.plan.route) do
      if s.label == c.label and self.status[i] == "done" then r = true end
    end
  elseif k == "cooldown" then
    r = false
  end
  if c.neg then r = not r end
  return r
end

function FP:StepApplies(step)
  if not step.w then return true end
  for _, c in ipairs(step.w) do
    local ok, r = pcall(self.CondTrue, self, c)
    if ok and not r then return false end
  end
  return true
end

------------------------------------------------------------------------
-- Goals the quest log can't see: checked live on the step you're on, then remembered
------------------------------------------------------------------------
FP.HARD = { a = true, t = true, c = true, o = true, l = true }
FP.SOFT = { g = true, z = true, b = true, tr = true, fp = true, tk = true, h = true }

function FP:PlayerPos()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  map = ok and self:Readable(map)
  if not map then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not ok2 or not pos then return nil end
  local x, y
  if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
  x, y = self:Readable(x), self:Readable(y)
  if not x or not y or (x == 0 and y == 0) then return nil end
  return map, x * 100, y * 100
end

-- Yards per 1% of the map, from the client's own map bounds when it has them.
function FP:MapScale(map)
  self.mapScale = self.mapScale or {}
  if self.mapScale[map] ~= nil then return self.mapScale[map] or nil end
  local scale = false
  if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
    pcall(function()
      local _, a = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0, 0))
      local _, b = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(1, 1))
      local ax, ay = a:GetXY(); local bx, by = b:GetXY()
      scale = { math.abs(by - ay) / 100, math.abs(bx - ax) / 100 }
    end)
  end
  self.mapScale[map] = scale
  return scale or nil
end

function FP:Near(m, x, y, yards)
  local map, px, py = self:PlayerPos()
  if not map or map ~= m then return false end
  local s = self:MapScale(map)
  local dx, dy = px - x, py - y
  if s then return math.sqrt((dx * s[1]) ^ 2 + (dy * s[2]) ^ 2) <= (yards or 20) end
  return math.sqrt(dx * dx + dy * dy) <= 1.5
end

local function PlaceKey(s) return (Norm(s):gsub("^the ", "")) end

function FP:PlaceIs(name)
  if not name or name == "" then return false end
  local want = PlaceKey(name)
  for _, fn in ipairs({ GetSubZoneText, GetZoneText, GetMinimapZoneText, GetRealZoneText }) do
    if fn then
      local ok, v = pcall(fn)
      if ok and type(v) == "string" and v ~= "" and PlaceKey(v) == want then return true end
    end
  end
  return false
end

local function TickKey(step, idx) return step.key .. "#" .. idx end

function FP:Ticked(step, idx) return self.char.ticks[TickKey(step, idx)] and true or false end

function FP:Tick(step, idx)
  local k = TickKey(step, idx)
  if not self.char.ticks[k] then self.char.ticks[k] = true; return true end
end

-- Live check of a place/item goal on the current step; true ticks it for good.
function FP:LiveCheck(o)
  if o.k == "g" then return self:Near(o.m, o.x, o.y, 25)
  elseif o.k == "z" then return self:PlaceIs(o.at)
  elseif o.k == "b" then return GetBindLocation and PlaceKey(GetBindLocation() or "") == PlaceKey(o.at or "") or false
  elseif o.k == "h" then return ((GetItemCount and GetItemCount(o.id)) or 0) >= (o.n or 1)
  end
  return false
end

-- Checks the current step's place goals (called every second while it has any).
function FP:CheckLive()
  local route = self.plan and self.plan.route
  local s = route and self.current and route[self.current]
  if not s then return end
  local changed = false
  for idx, o in ipairs(s.q) do
    if (o.k == "g" or o.k == "z" or o.k == "b" or o.k == "h") and not self:Ticked(s, idx) and self:LiveCheck(o) then
      if self:Tick(s, idx) then changed = true end
    end
  end
  if changed then self:Refresh(true) end
end

function FP:HasLiveGoals(s)
  if not s then return false end
  for idx, o in ipairs(s.q) do
    if (o.k == "g" or o.k == "z" or o.k == "b" or o.k == "h") and not self:Ticked(s, idx) then return true end
  end
  return false
end

-- An NPC window opened (trainer, flight master, gossip): tick matching goals on the current step.
function FP:OnNpcWindow(kind)
  local route = self.plan and self.plan.route
  local s = route and self.current and route[self.current]
  if not s then return end
  local npcID
  local guid = UnitGUID and self:Readable(UnitGUID("npc"))
  if type(guid) == "string" then npcID = tonumber(select(6, strsplit("-", guid)) or "") end
  local changed = false
  for idx, o in ipairs(s.q) do
    local hit = (kind == "trainer" and o.k == "tr") or (kind == "taxi" and o.k == "fp")
      or (o.k == "tk" and npcID and o.id == npcID)
    if hit and self:Tick(s, idx) then changed = true end
  end
  if changed then self:Refresh(true) end
end

------------------------------------------------------------------------
-- First login: the one-time setup
------------------------------------------------------------------------
function FP:ApplySetup(spec, group)
  local first = self.char.setup == nil
  local old = self.char.setup and self.char.setup.spec
  self.char.setup = { spec = spec or self:CurrentSpec(), group = group and true or false, version = 1 }
  self:BuildPlan()
  if first or old ~= self.char.setup.spec then self.char.needCatchup = true end
  self:ScanTalents()
  self:Refresh(false)
  if self.char.needCatchup and self.historyDone and self.historyImported then self:AutoCatchup() end
  self:Print(("Plan set: %s. %d route steps. /fp setup changes it."):format(self.plan.name, #self.plan.route))
end

-- After the setup (or a plan change), skip the steps behind your real progress, once.
function FP:AutoCatchup()
  self.char.needCatchup = nil
  if self:PlayerLevel() <= 1 and not next(self.char.doneIds) then return end
  self:Refresh(false)
  local anchor, keys = self:CatchupPlan()
  if anchor and keys and #keys > 0 then
    for _, k in ipairs(keys) do self.char.skip[k] = true end
    self.char.lastCatchup = keys
    self.view = nil
    self:Refresh(false)
    local cur = self.current and self.plan.route[self.current]
    self:Print(("Caught up with your quest history: %d earlier steps skipped (/fp catchup undo brings them back). You're on step %d: %s.")
      :format(#keys, cur and cur.num or 0, cur and cur.title or "end of route"))
  end
end
