-- Forever Planner: core engine.
-- Reads game state and shows advice. It never casts, targets or moves for you.

ForeverPlanner = ForeverPlanner or {}
local FP = ForeverPlanner
FP.version = "0.6.4"
-- Shown once after an update (newest first). Keep each line short.
FP.news = {
  "The gear panel now sits clear of the character window's side tabs, the Show/Hide button is below the character window, and the header no longer cuts off your spec name.",
  "Craft now: a new tab on the gear panel (press C) lists gear your professions can make right now that beats what you're wearing, as a backup until you get the plan's pick, plus the next recipe worth skilling up for. An anvil on a plan row means there's a backup for that slot.",
  "Tidier gear panel: one clean row per slot, short sources, the step on the right, and only slots with an upgrade to get are marked on the character window.",
  "Gear plan beside your character window: press C to see your planned item for every slot, with icons, where it comes from and whether you have it. Click one for a waypoint.",
  "Best-in-slot gear routes: your route now takes in the quests, quest chains and dungeons that give your spec's best gear at every level, and the Gear tab lists every pick with where it comes from (quest, boss drop or craft).",
  "Class quests you already have (Cure Poison, pets, forms) are no longer offered on the tracker.",
  "The route now follows you: a step finishes as soon as its quests are done, abandoned quests stop holding it up, and steps you've moved on from are skipped by themselves (/fp undo brings them back).",
  "Classes without their own plan yet now start on the spec their levelling guide recommends (Priest: Discipline, as in your Priest brief).",
  "Every character now gets a plan on first login: a levelling route from its starting zone to 60 (Polestar's routes), talents for your spec, and class quests. A short setup window asks your spec once.",
  "Talents: now read from Forever's own talent system, so the next pick glows on the talent window and the tracker sees your points.",
  "The route now runs to level 60 (steps 114-153, then 40-60 hubs and dungeons), with gear for 40-49, 50-59 and 60.",
  "Updates now install themselves (Windows updater). After an update, /reload.",
  "0.3.0: gear linked to route steps, Still need list, loot and quest-reward prompts.",
}
FP.log = {}          -- normalised title -> { title, id, complete }
FP.logById = {}      -- quest ID -> { title, complete, objs = { [n] = finished } }
FP.doneCount = {}    -- normalised title -> number of times turned in
FP.idTitle = {}      -- quest ID -> title (seen this session)
FP.status = {}       -- route index -> "open" | "done" | "skipped"
FP.current = nil     -- route index of the step you're on
FP.view = nil        -- route index being browsed (nil = follow current)
FP.talentRanks = nil -- talent name (normalised) -> rank, when the API allows

-- uiMapIDs from the Classic Era client; Forever is built on it (check if a waypoint lands in the wrong zone).
FP.MAP = {
  Durotar=1411, Mulgore=1412, Barrens=1413, Alterac=1416, Arathi=1417, Badlands=1418,
  Tirisfal=1420, Silverpine=1421, Hillsbrad=1424, DunMorogh=1426, LochModan=1432,
  Stranglethorn=1434, Wetlands=1437, Ashenvale=1440, ThousandNeedles=1441, Stonetalon=1442,
  Desolace=1443, Feralas=1444, Dustwallow=1445, Tanaris=1446, Moonglade=1450,
  Orgrimmar=1454, ThunderBluff=1456, Undercity=1458,
  Hinterlands=1425, BurningSteppes=1428, SwampOfSorrows=1435, Azshara=1447, Felwood=1448, UnGoro=1449,
  Silithus=1451, Winterspring=1452, WesternPlaguelands=1422, EasternPlaguelands=1423,
}
FP.ZONE = {
  Durotar="Durotar", Mulgore="Mulgore", Barrens="The Barrens", Alterac="Alterac Mountains",
  Arathi="Arathi Highlands", Badlands="Badlands", Tirisfal="Tirisfal Glades", Silverpine="Silverpine Forest",
  Hillsbrad="Hillsbrad Foothills", DunMorogh="Dun Morogh", LochModan="Loch Modan", Stranglethorn="Stranglethorn Vale",
  Wetlands="Wetlands", Ashenvale="Ashenvale", ThousandNeedles="Thousand Needles", Stonetalon="Stonetalon Mountains",
  Desolace="Desolace", Feralas="Feralas", Dustwallow="Dustwallow Marsh", Tanaris="Tanaris", Moonglade="Moonglade",
  Orgrimmar="Orgrimmar", ThunderBluff="Thunder Bluff", Undercity="Undercity",
  Hinterlands="The Hinterlands", BurningSteppes="Burning Steppes", SwampOfSorrows="Swamp of Sorrows", Azshara="Azshara",
  Felwood="Felwood", UnGoro="Un'Goro Crater", Silithus="Silithus", Winterspring="Winterspring",
  WesternPlaguelands="Western Plaguelands", EasternPlaguelands="Eastern Plaguelands",
  Riverglades="Riverglades", -- Forever zone: no map ID known yet, so waypoints there print coordinates instead
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function Norm(s)
  if type(s) ~= "string" then return "" end
  s = s:lower()
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("%p", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return s
end
FP.Norm = Norm

local function mk(kind)
  return function(title, extra)
    local o = { k = kind, q = title }
    if extra == true then o.opt = true elseif type(extra) == "number" then o.n = extra end
    return o
  end
end
FP.A, FP.T, FP.C = mk("a"), mk("t"), mk("c")

function FP:Print(msg)
  local frame = DEFAULT_CHAT_FRAME
  if frame and frame.AddMessage then frame:AddMessage("|cff33ff99Forever Planner:|r " .. tostring(msg)) end
end

local function safe(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

-- Forever's client can hand addons "secret" values in combat; comparing one throws, so read through this.
function FP:Readable(v)
  if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
  return v
end

function FP:PlayerLevel()
  local lvl = UnitLevel and self:Readable(UnitLevel("player"))
  if type(lvl) == "number" and lvl > 0 then self.lastLevel = lvl; return lvl end
  return self.lastLevel or 1
end

------------------------------------------------------------------------
-- Quest log and quest history
------------------------------------------------------------------------
local function Objectives(id, logIndex)
  local objs
  if id and C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, id)
    if ok and type(list) == "table" then
      objs = {}
      for n, ob in ipairs(list) do objs[n] = ob.finished and true or false end
      if #list > 0 then return objs end
    end
  end
  if logIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    pcall(function()
      objs = {}
      for n = 1, (GetNumQuestLeaderBoards(logIndex) or 0) do
        local _, _, finished = GetQuestLogLeaderBoard(n, logIndex)
        objs[n] = finished and true or false
      end
    end)
  end
  return objs
end

function FP:ScanLog()
  local log, byId = {}, {}
  local function add(title, id, complete, logIndex)
    if type(title) ~= "string" or title == "" then return end
    local e = { title = title, id = id, complete = complete and true or false }
    log[Norm(title)] = e
    if id then
      e.objs = Objectives(id, logIndex)
      byId[id] = e
      self.idTitle[id] = title
      if self.db then self.db.titles[id] = title end
    end
  end
  local ok = false
  if GetNumQuestLogEntries and GetQuestLogTitle then
    ok = pcall(function()
      local num = GetNumQuestLogEntries() or 0
      for i = 1, num do
        local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
        if title and not isHeader then add(title, questID, isComplete == 1 or isComplete == true, i) end
      end
    end)
  end
  if not ok and C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    pcall(function()
      local num = C_QuestLog.GetNumQuestLogEntries() or 0
      for i = 1, num do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
          local done = info.isComplete
          if done == nil and info.questID and C_QuestLog.IsComplete then done = C_QuestLog.IsComplete(info.questID) end
          add(info.title, info.questID, done, i)
        end
      end
    end)
  end
  local prev = self.logById
  self.log, self.logById = log, byId
  if self.char then
    if self.logScanned and prev then
      for id, e in pairs(prev) do
        if not byId[id] then self:QuestLeftLog(id, e.title) end
      end
    end
    for id in pairs(byId) do self.char.abandoned[id] = nil end
  end
  self.logScanned = true
end

function FP:QuestFlaggedDone(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, r = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    if ok and r then return true end
  end
  if IsQuestFlaggedCompleted then
    local ok, r = pcall(IsQuestFlaggedCompleted, id)
    if ok and r then return true end
  end
  return false
end

-- A quest left your log: turned in (even if the turn-in event was missed) or abandoned.
function FP:QuestLeftLog(id, title)
  if self.char.doneIds[id] then return end
  local function check()
    if self.char.doneIds[id] or self.logById[id] then return end
    if self:QuestFlaggedDone(id) then
      self.char.doneIds[id] = title or true
      self:Recount()
    else
      self.char.abandoned[id] = title or true
      if self.plan and self.plan.questSteps and self.plan.questSteps[id] then
        self:Print(("Abandoned %s: the route won't wait for it. Pick it up again and it comes back."):format(title or ("quest " .. id)))
      end
    end
    self:Refresh(true)
  end
  if C_Timer and C_Timer.After then C_Timer.After(1.5, check) else check() end
end

function FP:Recount()
  local c = {}
  for _, title in pairs(self.char.doneIds) do
    if type(title) == "string" then
      local k = Norm(title)
      c[k] = (c[k] or 0) + 1
    end
  end
  for title, n in pairs(self.char.doneExtra) do
    local k = Norm(title)
    c[k] = (c[k] or 0) + n
  end
  self.doneCount = c
end

function FP:QuestieTitle(id)
  if self.questieDB == nil then
    self.questieDB = false
    if QuestieLoader and QuestieLoader.ImportModule then
      local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
      if ok and type(m) == "table" then self.questieDB = m end
    end
    if not self.questieDB and type(QuestieDB) == "table" then self.questieDB = QuestieDB end
  end
  local db = self.questieDB
  if not db then return nil end
  if type(db.QueryQuestSingle) == "function" then
    local ok, name = pcall(db.QueryQuestSingle, id, "name")
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  if type(db.GetQuest) == "function" then
    local ok, q = pcall(db.GetQuest, db, id)
    if ok and type(q) == "table" and type(q.name) == "string" then return q.name end
  end
  return nil
end

function FP:TitleForID(id)
  local t = self.idTitle[id] or (self.db and self.db.titles[id])
  if t then return t end
  if C_QuestLog then
    local ok, r = safe(C_QuestLog.GetTitleForQuestID, id)
    if ok and type(r) == "string" and r ~= "" then t = r end
    if not t then
      ok, r = safe(C_QuestLog.GetQuestInfo, id)
      if ok and type(r) == "string" and r ~= "" then t = r end
    end
  end
  if not t then t = self:QuestieTitle(id) end
  if t and self.db then self.db.titles[id] = t end
  return t
end

-- Reads every quest this character has ever turned in, so steps done before
-- the addon was installed tick themselves off.
function FP:ImportHistory(verbose)
  self.questieDB = nil
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, t = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(t) == "table" then for _, id in ipairs(t) do ids[#ids + 1] = id end end
  end
  if #ids == 0 and GetQuestsCompleted then
    local ok, t = pcall(GetQuestsCompleted)
    if ok and type(t) == "table" then for id, v in pairs(t) do if v then ids[#ids + 1] = id end end end
  end
  local added, unknown = 0, 0
  for _, id in ipairs(ids) do
    local have = self.char.doneIds[id]
    if type(have) ~= "string" then
      local title = self:TitleForID(id) or FP.QT[id]
      if title then self.char.doneIds[id] = title; added = added + 1
      else self.char.doneIds[id] = true; if have == nil then unknown = unknown + 1 end end
    end
  end
  self.historyImported = true
  self:Recount()
  if verbose then
    self:Print(("Quest history: %d completed quests found, %d newly matched, %d without a name."):format(#ids, added, unknown))
    if unknown > 0 and not self.questieDB then
      self:Print("Questie isn't loaded, so some old quests have no name. Route steps match quest IDs, so only title-matched steps are affected.")
    end
  end
  return #ids, added, unknown
end

------------------------------------------------------------------------
-- Route state
------------------------------------------------------------------------
-- o: one goal of a step. Quest goals with an ID are matched by ID; older plans match by title.
-- step/idx are given for goals the quest log can't see (places, trainers), which are ticked once seen.
function FP:ObjDone(o, step, idx)
  local k = o.k
  if o.id and o.id ~= 0 and (k == "a" or k == "t" or k == "c" or k == "o") then
    local r
    if self.char.doneIds[o.id] ~= nil then return true end
    local L = self.logById[o.id]
    if k == "t" then r = false
    elseif k == "a" then r = L ~= nil
    elseif k == "c" then r = (L and L.complete) and true or false
    else r = (L and (L.complete or (L.objs and L.objs[o.i or 1]))) and true or false end
    -- goals from a title-based plan also still match by title
    if r or not o.byTitle then return r end
  end
  if k == "l" then
    if o.fr then return self:LevelProgress() >= (o.id or 0) + o.fr end
    return self:PlayerLevel() >= (o.id or 0)
  end
  if k == "i" then return true end
  if FP.SOFT[k] then return (step and idx and self:Ticked(step, idx)) or false end
  -- Title-matched goals (plans written before quest IDs)
  local key = Norm(o.q)
  local n = o.n or 1
  local done = self.doneCount[key] or 0
  local inLog = self.log[key]
  if k == "t" then
    return done >= n
  elseif k == "a" then
    return done >= n or (inLog ~= nil and done >= n - 1)
  else
    return done >= n or (inLog ~= nil and inLog.complete and done >= n - 1)
  end
end

local function IsHard(o) return o.k == "a" or o.k == "t" or o.k == "c" or o.k == "o" or o.k == "l" end
FP.IsHard = IsHard

-- A quest you won't be doing: you abandoned it, or every route step that picks it up was skipped
-- (by you, by the route following you, or because its condition didn't apply). Its other goals stop holding the route.
function FP:QuestDropped(id)
  if not id or id == 0 or not self.char then return false end
  local cache = self.dropCache
  if cache and cache[id] ~= nil then return cache[id] end
  local r = false
  if not self.char.doneIds[id] and not self.logById[id] then
    if self.char.abandoned[id] then
      r = true
    else
      local acc = self.plan and self.plan.accepts and self.plan.accepts[id]
      if acc then
        r = true
        for _, i in ipairs(acc) do
          local key = self.plan.route[i].key
          if not (self.char.skip[key] or self.char.autoSkip[key] or self.char.na[key]) then r = false; break end
        end
      end
    end
  end
  if cache then cache[id] = r end
  return r
end

function FP:GoalDropped(o)
  return o.id and o.id ~= 0 and (o.k == "a" or o.k == "t" or o.k == "c" or o.k == "o") and self:QuestDropped(o.id) or false
end

-- Required quest goals of a step: how many, and how many are done. Also: how many quest goals it had
-- before dropped quests were taken out.
function FP:StepCounts(step)
  local req, reqDone, all = 0, 0, 0
  for idx, o in ipairs(step.q or {}) do
    if not o.opt and IsHard(o) then
      all = all + 1
      if not self:GoalDropped(o) then
        req = req + 1
        if self:ObjDone(o, step, idx) then reqDone = reqDone + 1 end
      end
    end
  end
  return req, reqDone, all
end

-- Place, trainer and flight-path goals still open on a step (they hold it until seen,
-- or until you make progress on a later step).
function FP:SoftOpen(step)
  local n = 0
  for idx, o in ipairs(step.q or {}) do
    if not o.opt and FP.SOFT[o.k] and not self:ObjDone(o, step, idx) then
      -- a "go here" point is passed once a later goal of the same step is done
      local passed = false
      if o.k == "g" then
        for j = idx + 1, #step.q do
          local p = step.q[j]
          if IsHard(p) and self:ObjDone(p, step, j) then passed = true; break end
        end
      end
      if not passed then n = n + 1 end
    end
  end
  return n
end

local function AnyHardDone(self, step)
  for idx, o in ipairs(step.q or {}) do
    if IsHard(o) and o.k ~= "l" and self:ObjDone(o, step, idx) then return true end
  end
  return false
end
FP.AnyHardDone = AnyHardDone

-- Status of every step: "done", "skipped", "na" (its condition was false when the route got there),
-- "along" (done on the way, never the current step) or "open". The current step is the first open one.
function FP:ComputeSteps()
  local route = self.plan and self.plan.route
  if not route then return end
  local na = self.char.na
  local raw = {}
  local laterProgress = false
  self.dropCache = {}
  self.leftBehind = {}
  for i = #route, 1, -1 do
    local s = route[i]
    local req, reqDone, all = self:StepCounts(s)
    local st
    if self.char.skip[s.key] then st = "skipped"
    elseif self.char.manual[s.key] then st = "done"
    elseif self.char.autoSkip[s.key] and not self:StepInLog(s) then st = "skipped"; self.leftBehind[i] = true
    elseif reqDone == req then
      if req > 0 then
        st = "done"                      -- its quest work is done: places and trainers don't hold it
      elseif all > 0 then
        st = "skipped"                   -- every quest on it was dropped
      else
        local soft = self:SoftOpen(s)
        local hasGoals = false
        for _, o in ipairs(s.q or {}) do if FP.SOFT[o.k] and not o.opt then hasGoals = true end end
        if soft == 0 and hasGoals then st = "done"
        elseif laterProgress then st = "done"
        else st = "open" end
      end
    else st = "open" end
    raw[i] = st
    if not s.along and (st == "done" or AnyHardDone(self, s)) then laterProgress = true end
  end
  local cur
  for i = 1, #route do
    local s = route[i]
    local st = raw[i]
    if st == "open" then
      if na[s.key] then st = "na"
      elseif s.along then st = "along"
      elseif s.w then
        if not cur and not self:StepApplies(s) then na[s.key] = true; st = "na"
        elseif cur and not self:StepApplies(s) then st = "na" end
      end
    end
    self.status[i] = st
    if st == "open" and not cur then cur = i end
  end
  self.current = cur
end

function FP:ObjText(o)
  local k = o.k
  local name = o.q or o.txt or "?"
  local text
  if k == "a" then text = "Accept " .. name
  elseif k == "t" then text = "Turn in " .. name
  elseif k == "c" then text = "Finish " .. name
  elseif k == "o" then text = (o.txt or "Objective") .. " |cff9d9d9d(" .. name .. ")|r"
  else text = o.txt or name end
  if o.n and o.n > 1 and not o.id then text = text .. " (part " .. o.n .. ")" end
  if o.grp then text = text .. " |cffff8040(group)|r" end
  if o.opt then text = text .. " |cff999999(optional)|r" end
  return text
end

function FP:NextAction(step)
  if not step then return nil end
  for pass = 1, 2 do
    for idx, o in ipairs(step.q or {}) do
      if o.k ~= "i" and (pass == 1) == (not o.opt) and not self:ObjDone(o, step, idx) and not self:GoalDropped(o) then
        if not (o.k == "g" and self:SoftOpen(step) == 0) then return self:ObjText(o), o end
      end
    end
  end
  return nil
end

function FP:ViewIndex()
  return self.view or self.current
end

function FP:Refresh(fromEvent)
  if not self.plan then return end
  local before = self.current
  self:ScanLog()
  self:ComputeSteps()
  self:NoteProgress(fromEvent)
  if fromEvent and self:FollowPlayer() then self:ComputeSteps() end
  self:FollowTarget()
  if fromEvent and before and self.current ~= before then
    local route = self.plan.route
    if self.current and self.current > before then
      self.view = nil
      local s = route[self.current]
      local zone = self:ZoneName(s.map)
      self:Print(("Step done. Next: |cffffd100%s|r%s"):format(s.title, zone and (" (" .. zone .. ")") or ""))
      if PlaySound then pcall(PlaySound, 878) end -- quest log open sound
      if self.char.autoWay then self:SetWaypoint(s, true) end
    elseif not self.current then
      self:Print("You've reached the end of the route in this plan version. The next data update adds more.")
    end
  end
  if self.UpdateUI then self:UpdateUI() end
end

-- Moves the waypoint along as goals of the current step get done (auto waypoints on).
function FP:FollowTarget()
  if not (self.char and self.char.autoWay and self.current and not self.view) then return end
  local s = self.plan.route[self.current]
  local m, x, y, label = self:StepTarget(s)
  if not m then return end
  local at = s.key .. label .. x .. y
  if self.followAt ~= at then
    self.followAt = at
    if self.followReady then self:SetWaypoint(s, true) end
  end
end

-- Remembers which steps you finish while playing (as opposed to ones already done in your quest
-- history when you logged in); only those count as "you've moved on".
function FP:NoteProgress(fromEvent)
  local route = self.plan.route
  local prev = self.prevStatus
  local now = {}
  for i, s in ipairs(route) do
    local st = self.status[i]
    now[s.key] = st
    if fromEvent and prev and st == "done" and prev[s.key] and prev[s.key] ~= "done" and not self.char.manual[s.key] then
      self.char.progressed[s.key] = true
    end
  end
  self.prevStatus = now
end

-- Away from a step: on another map, more than ~150 yards from where it sends you, or 4+ levels above it.
function FP:AwayFrom(s, map, px, py, lvl)
  if (s.lvl or 0) + 4 <= lvl then return true end
  local m, x, y = self:StepTarget(s)
  local mapID = self:MapID(m)
  if not (mapID and x and y and map) then return false end
  if mapID ~= map then return true end
  local sc = self:MapScale(map)
  local dx, dy = px - x, py - y
  if sc then return math.sqrt((dx * sc[1]) ^ 2 + (dy * sc[2]) ^ 2) > 150 end
  return math.sqrt(dx * dx + dy * dy) > 8
end

-- Following you off the route: an unfinished step you've moved past (at least two of the next four
-- steps finished, none of its quests in your log, and you're away from it) is skipped on its own.
-- /fp undo brings the last batch back. Returns true if anything changed.
function FP:FollowPlayer()
  if self.char.follow == false or not self.current then return false end
  local route = self.plan.route
  local prog = self.char.progressed
  local far
  for i = #route, self.current + 1, -1 do
    if self.status[i] == "done" and prog[route[i].key] then far = i; break end
  end
  if not far then return false end
  local lvl = self:PlayerLevel()
  local map, px, py = self:PlayerPos()
  local left = {}
  for i = self.current, far - 1 do
    local st = self.status[i]
    if st == "open" then
      local s = route[i]
      local _, _, all = self:StepCounts(s)
      if all > 0 and not self.char.keep[s.key] and not self:StepInLog(s) then
        local doneAfter, seen = 0, 0
        for j = i + 1, #route do
          local t = route[j]
          local tst = self.status[j]
          if tst ~= "na" and tst ~= "along" and not t.along then
            local _, _, tall = self:StepCounts(t)
            if tall > 0 then
              seen = seen + 1
              if tst == "done" and prog[t.key] then doneAfter = doneAfter + 1 end
              if seen >= 4 then break end
            end
          end
        end
        if doneAfter >= 2 and (map or (s.lvl or 0) + 4 <= lvl) and self:AwayFrom(s, map, px, py, lvl) then
          left[#left + 1] = s
        end
      end
    end
  end
  if #left == 0 then return false end
  local names, keys = {}, {}
  for _, s in ipairs(left) do
    self.char.autoSkip[s.key] = true
    keys[#keys + 1] = s.key
    if #names < 4 then names[#names + 1] = ("%s %s"):format(s.num or s.key, s.title) end
  end
  self.char.lastAuto = keys
  self:Print(("You've moved on, so the route has too: skipped %s%s. /fp undo brings %s back.")
    :format(table.concat(names, ", "), #left > 4 and (" and %d more"):format(#left - 4) or "", #left > 1 and "them" or "it"))
  return true
end

function FP:UndoFollow()
  local keys = self.char.lastAuto
  if not keys or #keys == 0 then self:Print("Nothing to undo."); return end
  for _, k in ipairs(keys) do self.char.autoSkip[k] = nil; self.char.keep[k] = true end
  self.char.lastAuto = nil
  self.view = nil
  self:Refresh(false)
  self:Print(("Brought back %d step%s. The route won't skip %s again on its own."):format(#keys, #keys > 1 and "s" or "", #keys > 1 and "them" or "it"))
end

-- Trainer, flight-path and hearth goals left open on the last few finished steps.
function FP:Reminders()
  local out = {}
  local route = self.plan and self.plan.route
  if not (route and self.current) then return out end
  for i = math.max(1, self.current - 6), self.current - 1 do
    local s = route[i]
    if self.status[i] == "done" and not self.char.manual[s.key] then
      for idx, o in ipairs(s.q or {}) do
        if (o.k == "tr" or o.k == "fp" or o.k == "b") and not o.opt and not self:ObjDone(o, s, idx) then
          out[#out + 1] = { step = s, idx = idx, goal = o }
        end
      end
    end
  end
  return out
end

function FP:QueueRefresh()
  if self.refreshQueued then return end
  if C_Timer and C_Timer.After then
    self.refreshQueued = true
    C_Timer.After(0.3, function() self.refreshQueued = false; self:Refresh(true) end)
  else
    self:Refresh(true)
  end
end

function FP:ToggleManual(i)
  local s = self.plan and self.plan.route[i]
  if not s then return end
  if self.status[i] == "done" and not self.char.manual[s.key] and not self.char.skip[s.key] then
    self:Print("That step is already done from your quest log.")
    return
  end
  self.char.manual[s.key] = (not self.char.manual[s.key]) or nil
  self.char.skip[s.key] = nil
  if self.char.manual[s.key] and self.view == i then self.view = nil end
  self:Refresh(true)
end

function FP:ToggleSkip(i)
  local s = self.plan and self.plan.route[i]
  if not s then return end
  if self.char.autoSkip[s.key] then
    self.char.autoSkip[s.key] = nil
    self.char.keep[s.key] = true
  else
    self.char.skip[s.key] = (not self.char.skip[s.key]) or nil
  end
  self.char.manual[s.key] = nil
  if self.char.skip[s.key] and self.view == i then self.view = nil end
  self:Refresh(true)
end

-- True if one of the step's required quests is in your quest log right now.
function FP:StepInLog(step)
  for _, o in ipairs(step.q or {}) do
    if not o.opt and IsHard(o) and o.k ~= "l" then
      if o.id and o.id ~= 0 and self.logById[o.id] then return true end
      if (not o.id or o.id == 0 or o.byTitle) and o.q and self.log[Norm(o.q)] then return true end
    end
  end
  return false
end

-- Works out what /fp catchup would do. The anchor is the furthest step your real
-- quest progress has finished (Done marks don't count), ignoring steps more than
-- 2 levels above you so an out-of-order quest can't pull you too far ahead.
function FP:CatchupPlan()
  local route = self.plan.route
  local maxLvl = self:PlayerLevel() + 2
  local anchor
  for i = #route, 1, -1 do
    local s = route[i]
    local req, reqDone = self:StepCounts(s)
    if req > 0 and reqDone == req and (s.lvl or 0) <= maxLvl then anchor = i; break end
  end
  -- A class route that starts at a level you've reached: the shared starting-zone steps before it are behind you.
  local p = self.plan
  if p.preludeEnd and p.preludeEnd > 0 and p.routeFrom and self:PlayerLevel() >= p.routeFrom - 1 then
    if not anchor or anchor <= p.preludeEnd then anchor = p.preludeEnd + 1 end
  end
  if not anchor then return nil end
  local keys, kept = {}, {}
  local preludeAll = p.preludeEnd and p.routeFrom and self:PlayerLevel() >= p.routeFrom - 1
  for i = 1, anchor - 1 do
    local s = route[i]
    if self.status[i] == "open" or self.status[i] == "along" then
      if self:StepInLog(s) and not (preludeAll and i <= p.preludeEnd) then kept[#kept + 1] = tostring(s.num or s.key) else keys[#keys + 1] = s.key end
    end
  end
  return anchor, keys, kept
end

function FP:Catchup(arg)
  local route = self.plan.route
  if arg == "undo" then
    local last = self.char.lastCatchup
    if not last or #last == 0 then self:Print("Nothing to undo."); return end
    for _, k in ipairs(last) do self.char.skip[k] = nil end
    self:Print(("Catchup undone: %d steps are back on the route."):format(#last))
    self.char.lastCatchup = nil
    self.view = nil
    self:Refresh(false)
    return
  end
  self:Refresh(false)
  local anchor, keys, kept = self:CatchupPlan()
  if not anchor then
    self:Print("No finished step on the route yet, so there's nothing to catch up.")
    return
  end
  local a = route[anchor]
  if #keys == 0 then
    self:Print(("You're already caught up to step %s (%s)."):format(a.num or a.key, a.title))
    if #kept > 0 then self:Print("Still in your quest log, so kept: steps " .. table.concat(kept, ", ") .. ".") end
    return
  end
  local nums = {}
  for _, k in ipairs(keys) do local i = self:StepIndex(k); nums[#nums + 1] = tostring(i and route[i].num or k) end
  if #nums > 40 then nums = { nums[1] .. "-" .. nums[#nums] } end
  local list = table.concat(nums, ", ")
  if arg ~= "confirm" then
    self:Print(("Your furthest finished step is %s (%s). Catchup would skip %d unfinished steps before it: %s."):format(a.num or a.key, a.title, #keys, list))
    if #kept > 0 then self:Print("Kept because their quests are in your log: steps " .. table.concat(kept, ", ") .. ".") end
    self:Print("Type |cffffd100/fp catchup confirm|r to do it, or /fp catchup undo afterwards to reverse it.")
    return
  end
  for _, k in ipairs(keys) do self.char.skip[k] = true end
  self.char.lastCatchup = keys
  self.view = nil
  self:Refresh(false)
  self:Print(("Skipped %d steps before step %s: %s. They stay in the Route tab; Skip again on any of them to bring it back."):format(#keys, a.num or a.key, list))
  local cur = self.current and route[self.current]
  if cur then self:Print(("You're now on step %s: %s."):format(cur.num or cur.key, cur.title)) end
end

function FP:Browse(delta)
  local route = self.plan and self.plan.route
  if not route then return end
  local i = (self:ViewIndex() or #route) + delta
  if i < 1 then i = 1 elseif i > #route then i = #route end
  self.view = (i ~= self.current) and i or nil
  if self.UpdateUI then self:UpdateUI() end
end

function FP:GotoKey(key)
  local route = self.plan and self.plan.route
  if not route then return end
  for i, s in ipairs(route) do
    if s.key == key or tostring(s.num) == key then
      self.view = (i ~= self.current) and i or nil
      if self.UpdateUI then self:UpdateUI() end
      return true
    end
  end
  return false
end

------------------------------------------------------------------------
-- Waypoints: TomTom if installed, else the map's own pin, else chat
------------------------------------------------------------------------
function FP:MapID(map)
  if type(map) == "number" then return map end
  return map and FP.MAP[map]
end

function FP:ZoneName(map)
  if not map then return nil end
  if type(map) == "number" then
    if FP.MAPNAME[map] then return FP.MAPNAME[map] end
    if C_Map and C_Map.GetMapInfo then
      local ok, info = pcall(C_Map.GetMapInfo, map)
      if ok and info and info.name then return info.name end
    end
    return "map " .. map
  end
  return FP.ZONE[map] or map
end

-- Where the step sends you now: the first unfinished goal that has a place, else the step's own spot.
function FP:StepTarget(step)
  for idx, o in ipairs(step.q or {}) do
    if o.m and o.x and o.k ~= "i" and not self:ObjDone(o, step, idx) then
      return o.m, o.x, o.y, (o.k == "g" and o.txt) or step.title
    end
  end
  return step.map, step.x, step.y, step.title
end

function FP:SetWaypoint(step, quiet)
  if not step then return end
  local map, sx, sy, label = self:StepTarget(step)
  if not (map and sx and sy) then
    if not quiet then self:Print("This step has no coordinates. Questie's map markers show the quest givers.") end
    return
  end
  local mapID = self:MapID(map)
  local zone = self:ZoneName(map)
  local x, y = sx / 100, sy / 100
  if mapID and TomTom and TomTom.AddWaypoint then
    if self.tomtomUid and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, self.tomtomUid) end
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y,
      { title = label, persistent = false, minimap = true, world = true, from = "Forever Planner" })
    if ok then self.tomtomUid = uid; self.wayAt = step.key .. label; return true end
  end
  if mapID and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    if ok then
      self.wayAt = step.key .. label
      if not quiet then self:Print(("Map pin set: %s, %s %.1f, %.1f."):format(label, zone, sx, sy)) end
      return true
    end
  end
  if not quiet then self:Print(("%s: %s %.1f, %.1f"):format(label, zone, sx, sy)) end
end

------------------------------------------------------------------------
-- Talents, training, macros, gear
------------------------------------------------------------------------
function FP:ParseTalent(text)
  local t = text:gsub("%s*%b()", "")
  local name, rank = t:match("^(.-)%s+(%d+)$")
  if not name then name, rank = t, 1 end
  return name, tonumber(rank)
end

-- Modern talent system (C_Traits), which Forever's talent window (PlayerSpellsFrame) runs on.
local function TraitsCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
end

local function SpellNameIcon(spellID)
  if not spellID then return nil end
  local name, icon
  if C_Spell then
    name = TraitsCall(C_Spell.GetSpellName, spellID)
    icon = TraitsCall(C_Spell.GetSpellTexture, spellID)
  end
  if not name and GetSpellInfo then
    local ok, n, _, ic = pcall(GetSpellInfo, spellID)
    if ok then name = n; icon = icon or ic end
  end
  if not icon and GetSpellTexture then icon = TraitsCall(GetSpellTexture, spellID) end
  return name, icon
end

function FP:ScanTraits()
  if not (C_ClassTalents and C_Traits) then return false end
  local configID = TraitsCall(C_ClassTalents.GetActiveConfigID)
  if not configID then return false end
  local config = TraitsCall(C_Traits.GetConfigInfo, configID)
  local treeIDs = config and config.treeIDs
  if type(treeIDs) ~= "table" or #treeIDs == 0 then return false end
  local ranks, where, spent, unspent, seenCurrency, nodes = {}, {}, 0, nil, {}, 0
  for treeIndex, treeID in ipairs(treeIDs) do
    for _, c in ipairs(TraitsCall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false) or {}) do
      local id = c.traitCurrencyID or (#seenCurrency + 1)
      if not seenCurrency[id] and type(c.quantity) == "number" then
        seenCurrency[id] = true
        unspent = (unspent or 0) + c.quantity
      end
    end
    for _, nodeID in ipairs(TraitsCall(C_Traits.GetTreeNodes, treeID) or {}) do
      local node = TraitsCall(C_Traits.GetNodeInfo, configID, nodeID)
      if node and node.isVisible ~= false then
        nodes = nodes + 1
        local rank = node.ranksPurchased or node.currentRank or 0
        local entryIDs = node.entryIDs or {}
        local entryID = (node.activeEntry and node.activeEntry.entryID) or entryIDs[1]
        local entry = entryID and TraitsCall(C_Traits.GetEntryInfo, configID, entryID)
        local def = entry and entry.definitionID and TraitsCall(C_Traits.GetDefinitionInfo, entry.definitionID)
        local name, icon = SpellNameIcon(def and (def.overriddenSpellID or def.spellID))
        name = (def and def.overrideName and def.overrideName ~= "" and def.overrideName) or name
        icon = (def and def.overrideIcon) or icon
        if type(name) == "string" then
          local key = Norm(name)
          ranks[key] = math.max(ranks[key] or 0, rank)
          spent = spent + rank
          local subTree = node.subTreeID and TraitsCall(C_Traits.GetSubTreeInfo, configID, node.subTreeID)
          where[key] = { nodeID = nodeID, icon = icon, rank = rank, maxRank = node.maxRanks,
            tab = treeIndex, tabName = subTree and subTree.name or nil, posX = node.posX, posY = node.posY }
        end
      end
    end
  end
  if nodes == 0 then return false end
  self.talentAPI = "traits"
  self.talentRanks, self.talentWhere, self.talentSpent, self.traitsUnspent = ranks, where, spent, unspent
  self.traitsInfo = { configID = configID, trees = #treeIDs, nodes = nodes }
  return true
end

function FP:ScanTalents()
  self.traitsUnspent = nil
  if self:ScanTraits() then return end
  local ranks, where = {}, {}
  local found, spent = false, 0
  if GetNumTalentTabs and GetNumTalents and GetTalentInfo then
    pcall(function()
      for tab = 1, (GetNumTalentTabs() or 0) do
        local tabName = GetTalentTabInfo and select(1, GetTalentTabInfo(tab)) or nil
        for i = 1, (GetNumTalents(tab) or 0) do
          local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, i)
          if type(name) == "string" and type(rank) == "number" then
            ranks[Norm(name)] = rank; found = true; spent = spent + rank
            where[Norm(name)] = { tab = tab, index = i, tier = tier, column = column, icon = icon,
              rank = rank, maxRank = maxRank, tabName = type(tabName) == "string" and tabName or nil }
          end
        end
      end
    end)
  end
  self.talentAPI = found and "classic" or "none"
  self.talentRanks = found and ranks or nil
  self.talentWhere = found and where or nil
  self.talentSpent = found and spent or nil
end

function FP:NextTalentInfo()
  local level, text = self:NextTalent()
  if not level then return nil end
  local name, rank = self:ParseTalent(text)
  local info = self.talentWhere and self.talentWhere[Norm(name)]
  return { level = level, text = text, name = name, rank = rank, info = info }
end

function FP:UnspentTalentPoints()
  if self.talentAPI == "traits" and type(self.traitsUnspent) == "number" then return self.traitsUnspent end
  if UnitCharacterPoints then
    local ok, n = pcall(UnitCharacterPoints, "player")
    if ok and type(n) == "number" then return n end
  end
  if GetUnspentTalentPoints then
    local ok, n = pcall(GetUnspentTalentPoints)
    if ok and type(n) == "number" then return n end
  end
  -- Fallback: one point per level from 10, minus what's spent (Legacy "Talented" may add more).
  if self.talentSpent then return math.max(0, self:PlayerLevel() - 9 - self.talentSpent) end
  return nil
end

-- Returns the level and text of the next talent pick you haven't taken.
function FP:NextTalent()
  local t = self.plan and self.plan.talents
  if not t then return nil end
  local lvl = self:PlayerLevel()
  for level = 1, 60 do
    local text = t[level]
    if text then
      local taken
      if self.talentRanks then
        local name, rank = self:ParseTalent(text)
        taken = (self.talentRanks[Norm(name)] or 0) >= rank
      else
        taken = level < lvl
      end
      if not taken then return level, text end
    end
  end
  return nil
end

function FP:MacroFor(name, level)
  for _, m in ipairs(self.plan.macros or {}) do
    if m.name == name and level >= m.from and level <= m.to then return m end
  end
end

function FP:CurrentMacros()
  local out, seen = {}, {}
  local lvl = self:PlayerLevel()
  for _, m in ipairs(self.plan.macros or {}) do
    if not seen[m.name] then
      seen[m.name] = true
      out[#out + 1] = self:MacroFor(m.name, lvl) or m
    end
  end
  return out
end

function FP:WriteMacro(m)
  if InCombatLockdown and InCombatLockdown() then
    self:Print("Can't change macros in combat. Try again after the fight.")
    return
  end
  if #m.text > 255 then self:Print(m.name .. " is over 255 characters; not written."); return end
  local idx = GetMacroIndexByName and GetMacroIndexByName(m.name)
  if idx and idx > 0 then
    local ok = pcall(EditMacro, idx, m.name, nil, m.text)
    if ok then self:Print(("Updated macro %s (%d characters). Anything already on your bars keeps working."):format(m.name, #m.text))
    else self:Print("The game refused the macro edit. Copy the text from the box instead.") end
    return
  end
  local ok = pcall(CreateMacro, m.name, "INV_MISC_QUESTIONMARK", m.text, true)
  if not ok then ok = pcall(CreateMacro, m.name, 134400, m.text, true) end
  if ok then
    self:Print(("Created character macro %s (%d characters). Drag it from the macro window (/macro) to %s."):format(m.name, #m.text, m.bar or "your bar"))
  else
    self:Print("Couldn't create the macro (are your 18 character macro slots full?). Copy the text from the box instead.")
  end
end

local function LinkName(link)
  return type(link) == "string" and link:match("%[(.-)%]") or nil
end

-- Inventory slot IDs for the slot names used in plan.gear.
FP.SLOT_IDS = {
  Head = { 1 }, Neck = { 2 }, Shoulder = { 3 }, Back = { 15 }, Chest = { 5 }, Wrist = { 9 },
  Hands = { 10 }, Waist = { 6 }, Legs = { 7 }, Feet = { 8 }, Ring = { 11, 12 }, Trinket = { 13, 14 },
  Weapon = { 16, 17 }, MainHand = { 16 }, OffHand = { 17 }, Idol = { 18 }, Wand = { 18 }, Ranged = { 18 },
}

function FP:ScanItems()
  local eq, bag, bySlot = {}, {}, {}
  if GetInventoryItemLink then
    for slot = 1, 19 do
      local n = LinkName(GetInventoryItemLink("player", slot))
      if n then eq[Norm(n)] = true; bySlot[slot] = n end
    end
  end
  self.slotItem = bySlot
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  if numSlots and getLink then
    for b = 0, 4 do
      local ok, count = pcall(numSlots, b)
      for s = 1, (ok and count or 0) do
        local ok2, link = pcall(getLink, b, s)
        local n = ok2 and LinkName(link)
        if n then bag[Norm(n)] = true end
      end
    end
  end
  local before, wasWorn = self.bags, self.equipped
  self.equipped, self.bags = eq, bag
  if before and self.plan and self.char then self:LootCheck(before, wasWorn or {}) end
end

------------------------------------------------------------------------
-- Gear plan: where each item comes from, what you still need, prompts
------------------------------------------------------------------------
function FP:StepIndex(key)
  if not key or not self.plan then return nil end
  if not self.stepIdx then
    self.stepIdx = {}
    for i, s in ipairs(self.plan.route) do self.stepIdx[s.key] = i end
  end
  return self.stepIdx[key]
end

-- Every planned item for brackets you haven't outlevelled, plus stopgaps.
function FP:GearItems()
  local out = {}
  local lvl = self:PlayerLevel()
  for _, g in ipairs(self.plan.gear or {}) do
    if g.to >= lvl then
      for _, s in ipairs(g.slots) do
        out[#out + 1] = { name = s.best, slot = s.slot, src = s.src, step = s.step, role = "best", entry = s, bracket = g }
        if s.alt then
          out[#out + 1] = { name = s.alt, slot = s.slot, src = s.altsrc, step = s.altstep, role = "alt", entry = s, bracket = g }
        end
      end
    end
  end
  for _, s in ipairs(self.plan.stopgaps or {}) do
    out[#out + 1] = { name = s.name, slot = s.slot, src = s.src, step = s.step, role = "stopgap" }
  end
  return out
end

local ROLE_RANK = { best = 1, alt = 2, stopgap = 3 }

-- The most useful plan role for an item name, or nil if it isn't in the plan.
function FP:PlannedItem(name)
  if not name then return nil end
  local k, found = Norm(name), nil
  for _, it in ipairs(self:GearItems()) do
    if Norm(it.name) == k and (not found or ROLE_RANK[it.role] < ROLE_RANK[found.role]) then found = it end
  end
  return found
end

-- Should this item still be fetched / worn? Fallbacks stop mattering once the best piece is on.
function FP:ItemWanted(it)
  if self:ItemState(it.name) == "equipped" then return false end
  if it.role == "alt" and self:ItemState(it.entry.best) == "equipped" then return false end
  return true
end

function FP:GearHere(key)
  local out, seen = {}, {}
  if not key then return out end
  for _, it in ipairs(self:GearItems()) do
    if it.step == key and not seen[it.name] and self:ItemWanted(it) then
      seen[it.name] = true
      out[#out + 1] = it
    end
  end
  table.sort(out, function(a, b) return ROLE_RANK[a.role] < ROLE_RANK[b.role] end)
  return out
end

-- What's still missing in your level band, in the order the route reaches it.
function FP:UpgradePath()
  local g = self:GearBracket()
  local list = {}
  if not g then return list, 0, 0 end
  local worn, total = 0, #g.slots
  for _, s in ipairs(g.slots) do
    if self:ItemState(s.best) == "equipped" then
      worn = worn + 1
    else
      list[#list + 1] = { name = s.best, slot = s.slot, src = s.src, step = s.step, role = "best", idx = self:StepIndex(s.step) }
      if s.alt and not s.step and s.altstep and self:ItemState(s.alt) ~= "equipped" then
        list[#list + 1] = { name = s.alt, slot = s.slot, src = s.altsrc, step = s.altstep, role = "alt", idx = self:StepIndex(s.altstep) }
      end
    end
  end
  table.sort(list, function(a, b)
    local ai, bi = a.idx or 100000, b.idx or 100000
    if ai ~= bi then return ai < bi end
    return a.slot < b.slot
  end)
  return list, worn, total
end

function FP:SlotNow(slot)
  local names = {}
  for _, id in ipairs(FP.SLOT_IDS[slot] or {}) do
    if self.slotItem and self.slotItem[id] then names[#names + 1] = self.slotItem[id] end
  end
  return #names > 0 and table.concat(names, " + ") or "empty"
end

function FP:ShowStep(key, way)
  local i = self:StepIndex(key)
  if not i then return end
  self.view = (i ~= self.current) and i or nil
  if way then self:SetWaypoint(self.plan.route[i], true) end
  if self.UpdateUI then self:UpdateUI() end
end

local function Alert(msg)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.82, 0) end
end

-- A planned item just arrived in your bags.
function FP:LootCheck(before, wasWorn)
  self.char.lootSeen = self.char.lootSeen or {}
  for k in pairs(self.bags) do
    if not before[k] and not wasWorn[k] and not self.char.lootSeen[k] then
      local it = self:PlannedItem(k)
      if it and self:ItemWanted(it) then
        self.char.lootSeen[k] = true
        local msg
        if it.role == "best" then
          msg = ("%s is in your bags: equip it (%s, your plan's best)."):format(it.name, it.slot)
        elseif it.role == "alt" then
          msg = ("%s is in your bags: equip it (%s fallback until %s)."):format(it.name, it.slot, it.entry.best)
        else
          msg = ("%s is a stopgap for %s: equip it if it beats %s."):format(it.name, it.slot, self:SlotNow(it.slot))
        end
        self:Print(msg)
        Alert(msg)
      end
    end
  end
end

-- The quest reward window is open: name the reward your plan wants.
function FP:RewardAdvice()
  if not self.plan or not GetQuestItemInfo then return end
  local pick
  local nChoice = (GetNumQuestChoices and GetNumQuestChoices()) or 0
  for i = 1, nChoice do
    local ok, name = pcall(GetQuestItemInfo, "choice", i)
    local it = ok and self:PlannedItem(name)
    if it and self:ItemWanted(it) and (not pick or ROLE_RANK[it.role] < ROLE_RANK[pick.role]) then pick = it end
  end
  if pick then
    local why = (pick.role == "best" and "your plan's best") or (pick.role == "alt" and "plan fallback")
      or ("stopgap; check it beats " .. self:SlotNow(pick.slot))
    local msg = ("Reward pick: take %s (%s, %s)."):format(pick.name, pick.slot, why)
    self:Print(msg); Alert(msg)
  end
  local nFixed = (GetNumQuestRewards and GetNumQuestRewards()) or 0
  for i = 1, nFixed do
    local ok, name = pcall(GetQuestItemInfo, "reward", i)
    local it = ok and self:PlannedItem(name)
    if it and self:ItemWanted(it) then
      self:Print(("This quest gives %s: equip it (%s)."):format(it.name, it.slot))
    end
  end
end

function FP:ItemState(name)
  if not name then return nil end
  local k = Norm(name)
  if self.equipped and self.equipped[k] then return "equipped" end
  if self.bags and self.bags[k] then return "bags" end
  return "missing"
end

function FP:GearBracket(level)
  level = level or self:PlayerLevel()
  for _, g in ipairs(self.plan.gear or {}) do
    if level >= g.from and level <= g.to then return g end
  end
  return (self.plan.gear or {})[1]
end

------------------------------------------------------------------------
-- Craft now: gear your professions can make today that beats what you're wearing, as a backup
-- until you get the plan's pick. Reads your profession skill, and the recipes you know (from the
-- client, else from your profession window the first time you open it).
------------------------------------------------------------------------
local SKILL_LINES = { Alchemy = 171, Blacksmithing = 164, Enchanting = 333, Engineering = 202, Leatherworking = 165,
  Tailoring = 197, Jewelcrafting = 755, Mining = 186, Herbalism = 182, Skinning = 393, Cooking = 185,
  ["First Aid"] = 129, Fishing = 356 }
FP.GEAR_PROFESSIONS = { "Leatherworking", "Tailoring", "Blacksmithing", "Engineering", "Enchanting" }
local LINE_NAME = {}
for name, id in pairs(SKILL_LINES) do LINE_NAME[id] = name end
local function ProfName(s)
  if type(s) == "number" then return LINE_NAME[s] end
  if type(s) ~= "string" then return nil end
  local l = s:lower()
  for name in pairs(SKILL_LINES) do if name:lower() == l then return name end end
  return nil
end
FP.ProfName = ProfName

-- Your professions -> { Leatherworking = 135, ... }
function FP:ProfessionSkills()
  local out = {}
  local function put(name, rank, maxRank)
    name = ProfName(self:Readable(name))
    rank, maxRank = tonumber(self:Readable(rank)), tonumber(self:Readable(maxRank))
    if name and rank and (rank > 0 or (maxRank or 0) > 0) then out[name] = math.max(out[name] or 0, rank) end
  end
  local S = C_SkillInfo
  if S and S.GetSkillLineInfoByID then
    for name, id in pairs(SKILL_LINES) do
      local ok, info = pcall(S.GetSkillLineInfoByID, id)
      if ok and type(info) == "table" and not info.isHeader then put(name, info.rank, info.maxRank) end
    end
  end
  if S and S.GetNumSkillLines and S.GetSkillLineInfo then
    local ok, n = pcall(S.GetNumSkillLines)
    for i = 1, (ok and tonumber(n) or 0) do
      local ok2, info = pcall(S.GetSkillLineInfo, i)
      if ok2 and type(info) == "table" and not info.isHeader then put(info.skillID or info.name, info.rank, info.maxRank) end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    local ok, n = pcall(GetNumSkillLines)
    for i = 1, (ok and tonumber(n) or 0) do
      local ok2, name, header, _, rank, _, _, maxRank = pcall(GetSkillLineInfo, i)
      if ok2 and not header then put(name, rank, maxRank) end
    end
  end
  if GetProfessions and GetProfessionInfo then
    local profs = { pcall(GetProfessions) }
    for i = 2, 6 do
      if profs[i] then
        local ok, name, _, rank, maxRank, _, _, line = pcall(GetProfessionInfo, profs[i])
        if ok then put(line and LINE_NAME[line] or name, rank, maxRank) end
      end
    end
  end
  return out
end

-- Remember the recipes you know when a profession window opens (yours, not a linked one).
function FP:ScanRecipes()
  local char = self.char
  if not char then return end
  char.recipes = char.recipes or {}
  char.recipesSeen = char.recipesSeen or {}
  local T, prof, complete = C_TradeSkillUI, nil, false
  if T and T.GetAllRecipeIDs and T.GetRecipeInfo then
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
      if T[name] then local ok, v = pcall(T[name]); if ok and v then return end end
    end
    local ok, info = pcall(T.GetBaseProfessionInfo or function() end)
    if ok and type(info) == "table" then prof = ProfName(info.professionName) or ProfName(info.professionID) end
    local ok2, ids = pcall(T.GetAllRecipeIDs)
    if ok2 and type(ids) == "table" then
      complete = #ids > 0
      for _, id in ipairs(ids) do
        local ok3, r = pcall(T.GetRecipeInfo, id)
        if ok3 and type(r) == "table" and r.learned then char.recipes[id] = true end
      end
    end
  elseif GetNumTradeSkills and GetTradeSkillInfo then
    if IsTradeSkillLinked then local ok, v = pcall(IsTradeSkillLinked); if ok and v then return end end
    if GetTradeSkillLine then local ok, name = pcall(GetTradeSkillLine); if ok then prof = ProfName(name) end end
    local ok, n = pcall(GetNumTradeSkills)
    complete = ok and (tonumber(n) or 0) > 0
    for i = 1, (ok and tonumber(n) or 0) do
      local ok2, _, kind, _, expanded = pcall(GetTradeSkillInfo, i)
      if ok2 and kind == "header" and expanded == false then complete = false end   -- a collapsed header hides recipes
      if ok2 and kind and kind ~= "header" and GetTradeSkillItemLink then
        local ok3, link = pcall(GetTradeSkillItemLink, i)
        local id = ok3 and type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then char.recipes["i" .. id] = true end
      end
    end
  end
  if prof and complete then char.recipesSeen[prof] = true end
end

-- true (you know it), false (your profession window didn't list it), nil (can't tell yet).
function FP:RecipeKnown(itemID, rec)
  local char = self.char or {}
  local spell, prof = rec[4], rec[2]
  local known = char.recipes or {}
  if known[spell] or known["i" .. itemID] then return true end
  if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
    local ok, r = pcall(C_TradeSkillUI.GetRecipeInfo, spell)
    if ok and type(r) == "table" and r.learned then return true end
  end
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, spell)
    if ok and v then return true end
  end
  if char.recipesSeen and char.recipesSeen[prof] then return false end
  return nil
end

-- Score an item you're wearing with the spec's weights (Forever's own stats from the client).
local CLIENT_STATS = {
  ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
  ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor",
  ITEM_MOD_HEALTH_SHORT = "health", ITEM_MOD_MANA_SHORT = "mana", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
  ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
  ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
  ITEM_MOD_HEALTH_REGEN_SHORT = "hp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5",
  ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
  ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
  ITEM_MOD_CRIT_SPELL_RATING_SHORT = "spellCrit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "spellHit",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
  ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block", ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue",
}
local function LinkID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end

function FP:WornScore(inv, w, known)
  local link = GetInventoryItemLink and self:Readable(GetInventoryItemLink("player", inv))
  if not link then return 0, nil end
  local id, name = LinkID(link), link:match("%[(.-)%]")
  if id and known and known[id] then return known[id], name end
  local get = (C_Item and C_Item.GetItemStats) or GetItemStats
  local ok, t = false, nil
  if get then ok, t = pcall(get, link) end
  if not (ok and type(t) == "table") then return nil, name end   -- can't tell: don't suggest over it
  local s = 0
  for k, v in pairs(t) do
    local key = CLIENT_STATS[k]
    v = tonumber(self:Readable(v))
    if key and v then
      if key == "dps" then
        key = (inv == 18) and "rdps" or "dps"
        if inv == 17 then v = v * 0.5 end
      end
      s = s + (w[key] or 0) * v
    end
  end
  return s, name
end

local function TwoHanded(inv)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", inv)
  if not link or not (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant) then return false end
  local ok, _, _, _, loc = pcall(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant, link)
  return ok and loc == "INVTYPE_2HWEAPON"
end

local CRAFT_SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Ring",
  "Trinket", "TwoHand", "MainHand", "OffHand", "Ranged" }
local CRAFT_INV = { TwoHand = { 16, 17 } }
local CRAFT_GAIN, CRAFT_MIN = 1.05, 0.5   -- a backup must beat what you wear by 5% and half a point
local NEXT_RANGE = 50                     -- recipes more than this many skill points away aren't mentioned

local function BandFor(bands, lvl)
  if not bands then return nil end
  local pick = bands[1]
  for _, b in ipairs(bands) do if lvl >= b[1] then pick = b end end
  return pick
end

-- -> rows { slot, id, rec, state = "now" | "check" | "recipe" | "skill" | "bags", have, gain, worn }, skills, why
function FP:CraftNow()
  local skills = self:ProfessionSkills()
  local spec = self:CurrentSpec()
  local key = (self.class or "") .. ":" .. (spec or "")
  local cp, ws = self.craftPlans and self.craftPlans[key], self.specWeights and self.specWeights[key]
  if not (cp and ws) then return {}, skills, "nodata" end
  local any = false
  for _, p in ipairs(self.GEAR_PROFESSIONS) do if skills[p] then any = true end end
  if not any then return {}, skills, "noprof" end
  local lvl = self:PlayerLevel()
  local band, wband = BandFor(cp, lvl), BandFor(ws, lvl)
  local w = wband and wband[3] or {}
  local lists = band and band[3] or {}
  -- the plan for this level: skip slots where you already wear its pick; follow its weapon choice
  local g = self.plan and self.plan.gear and self:GearBracket(lvl)
  local planned, wornPick = {}, {}
  for _, sl in ipairs(g and g.slots or {}) do
    local s = sl.slot == "Weapon" and "TwoHand" or sl.slot
    planned[s] = true
    if self:ItemState(sl.best) == "equipped" then wornPick[s] = (wornPick[s] or 0) + 1 end
  end
  local usesTwoHand = planned.TwoHand or (not planned.MainHand and TwoHanded(16))
  local rows = {}
  for _, slot in ipairs(CRAFT_SLOTS) do
    local flat = lists[slot]
    local skip = (slot == "TwoHand" and not usesTwoHand) or ((slot == "MainHand" or slot == "OffHand") and usesTwoHand)
      or (slot == "OffHand" and TwoHanded(16))
    local need = (slot == "Ring" or slot == "Trinket") and 2 or 1
    if flat and not skip and (wornPick[slot] or 0) < need then
      local scores = {}
      for i = 1, #flat, 2 do scores[flat[i]] = flat[i + 1] end
      -- what you're wearing there (the weaker ring or trinket; a two-hander against both hands)
      local invs = CRAFT_INV[slot] or self.SLOT_IDS[slot] or {}
      local worn, wornName, wornIds = nil, nil, {}
      if slot == "TwoHand" then
        local a, an = self:WornScore(16, w, scores)
        local b = self:WornScore(17, w, scores)
        worn, wornName = a and b and (a + b) or nil, an
      else
        for _, inv in ipairs(invs) do
          local s, n = self:WornScore(inv, w, scores)
          local id = GetInventoryItemID and GetInventoryItemID("player", inv)
          if id then wornIds[id] = true end
          if s == nil then worn = nil; wornName = n; break end
          if worn == nil or s < worn then worn, wornName = s, n end
        end
      end
      if worn then
        local nowPick, later = nil, {}
        for i = 1, #flat, 2 do   -- best first
          local id, sc = flat[i], flat[i + 1]
          local rec = self.bisCrafts[id]
          local have = rec and skills[rec[2]]
          if rec and have and not wornIds[id] and (rec[5] or 1) <= lvl and sc > worn * CRAFT_GAIN + CRAFT_MIN then
            local row = { slot = slot, id = id, rec = rec, have = have, score = sc, worn = wornName, gain = sc - worn }
            if have >= rec[3] then
              if self:ItemState(rec[1]) == "bags" then row.state = "bags"
              else
                local k = self:RecipeKnown(id, rec)
                row.state = (k == true and "now") or (k == nil and "check") or "recipe"
              end
              -- the best one you can make; one you'd still have to learn only if there's nothing else
              if not nowPick or (nowPick.state == "recipe" and row.state ~= "recipe") then nowPick = row end
            elseif rec[3] - have <= NEXT_RANGE then
              row.state = "skill"
              later[#later + 1] = row
            end
          end
        end
        -- the nearest recipe (fewest skill points away) that beats the best you can make now
        local nextPick
        for _, row in ipairs(later) do
          if (not nowPick or row.score > nowPick.score)
              and (not nextPick or row.rec[3] < nextPick.rec[3] or (row.rec[3] == nextPick.rec[3] and row.score > nextPick.score)) then
            nextPick = row
          end
        end
        if nowPick then rows[#rows + 1] = nowPick end
        if nextPick then rows[#rows + 1] = nextPick end
      end
    end
  end
  return rows, skills
end

function FP:OnLevelUp(level)
  local p = self.plan
  if not p then return end
  if p.talents and p.talents[level] then
    self:Print(("Level %d talent: |cffffd100%s|r"):format(level, p.talents[level]))
  end
  if p.training and p.training[level] then
    self:Print(("New at the trainer: %s"):format(p.training[level]))
  elseif level % 2 == 0 then
    self:Print("New ranks may be waiting at your class trainer.")
  end
  for _, m in ipairs(p.macros or {}) do
    if m.from == level and m.from > 1 then
      local prev = self:MacroFor(m.name, level - 1)
      if prev and prev ~= m then
        self:Print(("Macro |cffffd100%s|r has a new version from level %d. Open /fp, Macros tab, to update it."):format(m.name, level))
      end
    end
  end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
FP.eventFrame = ev

local function InitSaved()
  ForeverPlannerDB = ForeverPlannerDB or {}
  ForeverPlannerDB.titles = ForeverPlannerDB.titles or {}
  ForeverPlannerChar = ForeverPlannerChar or {}
  local c = ForeverPlannerChar
  c.doneIds = c.doneIds or {}
  c.doneExtra = c.doneExtra or {}
  c.manual = c.manual or {}
  c.skip = c.skip or {}
  c.ticks = c.ticks or {}   -- place/trainer goals seen: "stepkey#n" -> true
  c.na = c.na or {}         -- steps whose condition didn't apply when the route reached them
  c.abandoned = c.abandoned or {}  -- quest ID -> title, for quests you dropped from your log
  c.autoSkip = c.autoSkip or {}    -- steps the route passed because you moved on without them
  c.keep = c.keep or {}            -- steps you brought back: never skipped on their own again
  c.progressed = c.progressed or {}  -- steps you finished while playing (not from old quest history)
  if c.autoWay == nil then c.autoWay = true end
  if c.trackerShown == nil then c.trackerShown = true end
  FP.db, FP.char = ForeverPlannerDB, c
end

local function StartLiveTicker()
  if FP.liveTicker or not (C_Timer and C_Timer.NewTicker) then return end
  local n = 0
  FP.liveTicker = C_Timer.NewTicker(1, function()
    local s = FP.plan and FP.current and FP.plan.route[FP.current]
    if s and FP:HasLiveGoals(s) then pcall(FP.CheckLive, FP) end
    n = n + 1
    -- every 10 s: check whether you've moved on from a step you left behind
    if n % 10 == 0 and FP.plan and FP.char.follow ~= false and not (InCombatLockdown and InCombatLockdown()) then
      FP:QueueRefresh()
    end
  end)
end

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == "ForeverPlanner" then InitSaved() end
  elseif event == "PLAYER_LOGIN" then
    if not FP.char then InitSaved() end
    FP:ReadIdentity()
    FP.className = UnitClass and UnitClass("player")
    if FP.char.setup == nil then FP.char.needCatchup = true end
    FP:BuildPlan()
    FP:FreeOtherFaction()
    FP:Recount()
    FP:ScanItems()
    FP:ScanTalents()
    if FP.BuildUI then FP:BuildUI() end
    FP:Refresh(false)
    FP.followReady = true
    StartLiveTicker()
    if FP.plan then
      FP:Print(("Plan loaded: %s, %d route steps. /fp opens it."):format(FP.plan.name, #FP.plan.route))
    end
    if FP.char.setup == nil and FP.ShowSetup then FP:ShowSetup() end
    local last = FP.db.lastVersion
    if last ~= FP.version then
      local from = last or (next(FP.char.doneIds) and "an earlier version")
      if from then
        FP:Print(("Updated %s -> %s."):format(from, FP.version))
        if FP.news[1] then FP:Print("New: " .. FP.news[1]) end
      end
      FP.db.lastVersion = FP.version
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not FP.historyDone and FP.plan then
      FP.historyDone = true
      local function run()
        FP:ImportHistory(true)
        FP:Refresh(false)
        if FP.char.needCatchup and FP.char.setup then FP:AutoCatchup() end
      end
      if C_Timer and C_Timer.After then C_Timer.After(6, run) else run() end
    end
  elseif event == "QUEST_COMPLETE" then
    if GetTitleText then FP.lastCompleteTitle = GetTitleText() end
    pcall(FP.RewardAdvice, FP)
  elseif event == "QUEST_TURNED_IN" then
    local id = ...
    if id and FP.char then
      local title = FP.idTitle[id] or FP:TitleForID(id) or FP.QT[id] or FP.lastCompleteTitle
      FP.char.doneIds[id] = title or true
      FP:Recount()
    end
    FP:QueueRefresh()
  elseif event == "QUEST_ACCEPTED" or event == "QUEST_LOG_UPDATE" or event == "QUEST_REMOVED" then
    FP:QueueRefresh()
  elseif event == "PLAYER_LEVEL_UP" then
    local level = ...
    FP.lastLevel = FP:Readable(level) or FP.lastLevel
    FP:OnLevelUp(level)
    FP:QueueRefresh()
  elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED"
      or event == "TRAIT_NODE_CHANGED" or event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" then
    FP:ScanTalents()
    if FP.UpdateTalentGlow then FP:UpdateTalentGlow() end
    FP:QueueRefresh()
  elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" or event == "UNIT_INVENTORY_CHANGED" then
    FP:ScanItems()
    if FP.plan then pcall(FP.CheckLive, FP) end
    if FP.UpdateUI then FP:UpdateUI() end
  elseif event == "TRAINER_SHOW" then
    FP:OnNpcWindow("trainer")
  elseif event == "TAXIMAP_OPENED" then
    FP:OnNpcWindow("taxi")
  elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" or event == "QUEST_DETAIL" or event == "MERCHANT_SHOW"
      or event == "QUEST_PROGRESS" then
    FP:OnNpcWindow("talk")
  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS"
      or event == "HEARTHSTONE_BOUND" or event == "PLAYER_MONEY" then
    if FP.plan then pcall(FP.CheckLive, FP) end
  end
end)

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_COMPLETE", "QUEST_TURNED_IN",
  "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED",
  "PLAYER_TALENT_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED",
  "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAINER_SHOW", "TAXIMAP_OPENED",
  "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "MERCHANT_SHOW", "ZONE_CHANGED",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "HEARTHSTONE_BOUND", "PLAYER_MONEY" }) do
  pcall(ev.RegisterEvent, ev, e) -- an event this client doesn't have is skipped, not an error
end

------------------------------------------------------------------------
-- Slash commands and key bindings
------------------------------------------------------------------------
function ForeverPlanner_ToggleMain() if FP.ToggleMain then FP:ToggleMain() end end
function ForeverPlanner_ToggleTracker() if FP.ToggleTracker then FP:ToggleTracker() end end
function ForeverPlanner_StepDone() local i = FP:ViewIndex(); if i then FP:ToggleManual(i) end end
function ForeverPlanner_Waypoint() local i = FP:ViewIndex(); if i and FP.plan then FP:SetWaypoint(FP.plan.route[i]) end end

BINDING_HEADER_FOREVERPLANNER = "Forever Planner"
BINDING_NAME_FOREVERPLANNER_TOGGLE = "Open or close the plan window"
BINDING_NAME_FOREVERPLANNER_TRACKER = "Show or hide the step tracker"
BINDING_NAME_FOREVERPLANNER_DONE = "Mark the shown step done"
BINDING_NAME_FOREVERPLANNER_WAY = "Waypoint to the shown step"

local HELP = {
  "/fp - open the plan window",
  "/fp tracker - show or hide the step tracker",
  "/fp done | skip - mark the shown step done or skipped (again to undo)",
  "/fp next | prev | now - browse steps; now returns to your current step",
  "/fp goto <step> - show a step by its number, e.g. /fp goto 44",
  "/fp way - waypoint to the shown step",
  "/fp autoway - turn automatic waypoints on or off",
  "/fp check - list the shown step's quests and what the addon sees",
  "/fp sync - re-read your quest history",
  "/fp catchup - preview skipping unfinished steps behind your furthest progress; confirm to apply, undo to reverse",
  "/fp lock - lock or unlock the tracker position",
  "/fp talentglow - turn the talent screen highlight on or off",
  "/fp talentdebug - show what the addon sees on the talent screen",
  "/fp setup - choose your spec and options again",
  "/fp gear - open your character window with the gear plan beside it (it opens there by itself)",
  "/fp undo - bring back the steps the route skipped when you moved on",
  "/fp follow - turn that automatic skipping off or on",
  "/fp side - class quests ready for your level; /fp side <n> adds one to your route",
  "/fp reset confirm - clear this character's route progress",
}

SLASH_FOREVERPLANNER1 = "/fp"
SLASH_FOREVERPLANNER2 = "/foreverplanner"
SlashCmdList["FOREVERPLANNER"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if not FP.plan and cmd ~= "help" then
    FP:Print("Your plan isn't ready yet; try again in a moment.")
    return
  end
  if cmd == "" then FP:ToggleMain()
  elseif cmd == "tracker" then FP:ToggleTracker()
  elseif cmd == "done" then ForeverPlanner_StepDone()
  elseif cmd == "skip" then local i = FP:ViewIndex(); if i then FP:ToggleSkip(i) end
  elseif cmd == "next" then FP:Browse(1)
  elseif cmd == "prev" then FP:Browse(-1)
  elseif cmd == "now" then FP.view = nil; FP:UpdateUI()
  elseif cmd == "goto" then if not FP:GotoKey(arg) then FP:Print("No step " .. arg .. ".") end
  elseif cmd == "way" then ForeverPlanner_Waypoint()
  elseif cmd == "autoway" then
    FP.char.autoWay = not FP.char.autoWay
    FP:Print("Automatic waypoints " .. (FP.char.autoWay and "on." or "off."))
  elseif cmd == "talentdebug" then
    FP:TalentDebug()
  elseif cmd == "talentglow" then
    FP.char.talentGlow = (FP.char.talentGlow == false)
    FP:Print("Talent screen highlight " .. (FP.char.talentGlow and "on." or "off."))
    if FP.UpdateTalentGlow then FP:UpdateTalentGlow() end
  elseif cmd == "lock" then
    FP.char.locked = not FP.char.locked
    FP:Print("Tracker " .. (FP.char.locked and "locked." or "unlocked: drag it to move."))
  elseif cmd == "sync" then FP:ImportHistory(true); FP:Refresh(false)
  elseif cmd == "setup" then if FP.ShowSetup then FP:ShowSetup() end
  elseif cmd == "undo" then FP:UndoFollow()
  elseif cmd == "gear" then if FP.ShowGearPanel then FP:ShowGearPanel() end
  elseif cmd == "geardebug" then if FP.GearDebug then FP:GearDebug() end
  elseif cmd == "follow" then
    FP.char.follow = (FP.char.follow == false)
    FP:Print(FP.char.follow and "The route follows you: steps you move on from are skipped on their own." or
      "The route no longer skips steps on its own. Use Skip or /fp catchup.")
    FP:Refresh(false)
  elseif cmd == "side" then
    local list = FP:SideReady()
    local n = tonumber(arg)
    if n and list[n] then FP:StartSide(list[n].id); return end
    if #list == 0 then FP:Print("No class quests waiting for your level."); return end
    for k, side in ipairs(list) do
      FP:Print(("%d. %s (levels %d-%d): %s"):format(k, side.title, side.min, side.max, side.why or ""))
    end
    FP:Print("Type /fp side <number> to add one before your current step.")
  elseif cmd == "catchup" then FP:Catchup(arg)
  elseif cmd == "check" then
    local i = FP:ViewIndex()
    local s = i and FP.plan.route[i]
    if not s then FP:Print("No step shown."); return end
    FP:Print(("Step %s: %s (%s)"):format(s.num or s.key, s.title, FP.status[i] or "?"))
    for idx, o in ipairs(s.q or {}) do
      local state = FP:ObjDone(o, s, idx) and "|cff00ff00done|r" or "|cffff8000open|r"
      local extra = ""
      if o.id and o.id ~= 0 and (o.k == "a" or o.k == "t" or o.k == "c" or o.k == "o") then
        local L = FP.logById[o.id]
        extra = (" - quest %d, in log: %s, turned in: %s"):format(o.id, L and (L.complete and "yes, complete" or "yes") or "no",
          FP.char.doneIds[o.id] and "yes" or "no")
      elseif o.q and not o.id then
        local k = Norm(o.q)
        local inLog = FP.log[k]
        extra = (" - in log: %s, turned in: %d"):format(inLog and (inLog.complete and "yes, complete" or "yes") or "no", FP.doneCount[k] or 0)
      end
      FP:Print(("  %s %s%s"):format(state, FP:ObjText(o), extra))
    end
  elseif cmd == "reset" and arg == "confirm" then
    wipe(FP.char.manual); wipe(FP.char.skip); wipe(FP.char.ticks); wipe(FP.char.na)
    wipe(FP.char.autoSkip); wipe(FP.char.keep); wipe(FP.char.abandoned); wipe(FP.char.progressed)
    FP.view = nil
    FP:Refresh(false)
    FP:Print("Route progress cleared. Quest history still counts.")
  else
    for _, line in ipairs(HELP) do FP:Print(line) end
  end
end
