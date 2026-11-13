-- Forever Planner: core engine.
-- Reads game state and shows advice. It never casts, targets or moves for you.

ForeverPlanner = ForeverPlanner or {}
local FP = ForeverPlanner
FP.version = "0.3.0"
FP.plans = {}
FP.log = {}          -- normalised title -> { title, id, complete }
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
}
FP.ZONE = {
  Durotar="Durotar", Mulgore="Mulgore", Barrens="The Barrens", Alterac="Alterac Mountains",
  Arathi="Arathi Highlands", Badlands="Badlands", Tirisfal="Tirisfal Glades", Silverpine="Silverpine Forest",
  Hillsbrad="Hillsbrad Foothills", DunMorogh="Dun Morogh", LochModan="Loch Modan", Stranglethorn="Stranglethorn Vale",
  Wetlands="Wetlands", Ashenvale="Ashenvale", ThousandNeedles="Thousand Needles", Stonetalon="Stonetalon Mountains",
  Desolace="Desolace", Feralas="Feralas", Dustwallow="Dustwallow Marsh", Tanaris="Tanaris", Moonglade="Moonglade",
  Orgrimmar="Orgrimmar", ThunderBluff="Thunder Bluff", Undercity="Undercity",
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

function FP:RegisterPlan(plan)
  self.plans[plan.class] = plan
end

function FP:PlayerLevel()
  return (UnitLevel and UnitLevel("player")) or 1
end

------------------------------------------------------------------------
-- Quest log and quest history
------------------------------------------------------------------------
function FP:ScanLog()
  local log = {}
  local function add(title, id, complete)
    if type(title) ~= "string" or title == "" then return end
    log[Norm(title)] = { title = title, id = id, complete = complete and true or false }
    if id then
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
        if title and not isHeader then add(title, questID, isComplete == 1 or isComplete == true) end
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
          add(info.title, info.questID, done)
        end
      end
    end)
  end
  self.log = log
end

function FP:Recount()
  local c = {}
  for _, title in pairs(self.char.doneIds) do
    local k = Norm(title)
    c[k] = (c[k] or 0) + 1
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
    if not self.char.doneIds[id] then
      local title = self:TitleForID(id)
      if title then self.char.doneIds[id] = title; added = added + 1 else unknown = unknown + 1 end
    end
  end
  self:Recount()
  if verbose then
    self:Print(("Quest history: %d completed quests found, %d newly matched, %d without a name."):format(#ids, added, unknown))
    if unknown > 0 and not self.questieDB then
      self:Print("Questie isn't loaded, so some old quests couldn't be named. Use Done/Skip on those steps.")
    end
  end
  return #ids, added, unknown
end

------------------------------------------------------------------------
-- Route state
------------------------------------------------------------------------
function FP:ObjDone(o)
  local key = Norm(o.q)
  local n = o.n or 1
  local done = self.doneCount[key] or 0
  local inLog = self.log[key]
  if o.k == "t" then
    return done >= n
  elseif o.k == "a" then
    return done >= n or (inLog ~= nil and done >= n - 1)
  else
    return done >= n or (inLog ~= nil and inLog.complete and done >= n - 1)
  end
end

function FP:StepCounts(step)
  local req, reqDone = 0, 0
  for _, o in ipairs(step.q or {}) do
    if not o.opt then
      req = req + 1
      if self:ObjDone(o) then reqDone = reqDone + 1 end
    end
  end
  return req, reqDone
end

function FP:ComputeSteps()
  local route = self.plan and self.plan.route
  if not route then return end
  local laterDone = false
  for i = #route, 1, -1 do
    local s = route[i]
    local req, reqDone = self:StepCounts(s)
    local st
    if self.char.skip[s.key] then st = "skipped"
    elseif self.char.manual[s.key] then st = "done"
    elseif req > 0 and reqDone == req then st = "done"
    elseif req == 0 and laterDone then st = "done"
    else st = "open" end
    self.status[i] = st
    if st == "done" then laterDone = true end
  end
  local cur
  for i = 1, #route do
    if self.status[i] == "open" then cur = i; break end
  end
  self.current = cur
end

function FP:ObjText(o)
  local verb = (o.k == "a" and "Accept") or (o.k == "t" and "Turn in") or "Finish"
  local nth = (o.n and o.n > 1) and (" (part " .. o.n .. ")") or ""
  return verb .. " " .. o.q .. nth .. (o.opt and " |cff999999(optional)|r" or "")
end

function FP:NextAction(step)
  if not step then return nil end
  for pass = 1, 2 do
    for _, o in ipairs(step.q or {}) do
      if (pass == 1) == (not o.opt) and not self:ObjDone(o) then return self:ObjText(o) end
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
  if fromEvent and before and self.current ~= before then
    local route = self.plan.route
    if self.current and self.current > before then
      self.view = nil
      local s = route[self.current]
      self:Print(("Step done. Next: |cffffd100%s|r%s"):format(s.title, s.map and (" (" .. (FP.ZONE[s.map] or s.map) .. ")") or ""))
      if PlaySound then pcall(PlaySound, 878) end -- quest log open sound
      if self.char.autoWay then self:SetWaypoint(s, true) end
    elseif not self.current then
      self:Print("You've reached the end of the route in this plan version. The next data update adds more.")
    end
  end
  if self.UpdateUI then self:UpdateUI() end
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
  self.char.skip[s.key] = (not self.char.skip[s.key]) or nil
  self.char.manual[s.key] = nil
  if self.char.skip[s.key] and self.view == i then self.view = nil end
  self:Refresh(true)
end

-- True if one of the step's required quests is in your quest log right now.
function FP:StepInLog(step)
  for _, o in ipairs(step.q or {}) do
    if not o.opt and self.log[Norm(o.q)] then return true end
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
  if not anchor then return nil end
  local keys, kept = {}, {}
  for i = 1, anchor - 1 do
    local s = route[i]
    if self.status[i] == "open" then
      if self:StepInLog(s) then kept[#kept + 1] = s.key else keys[#keys + 1] = s.key end
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
    self:Print(("You're already caught up to step %s (%s)."):format(a.key, a.title))
    if #kept > 0 then self:Print("Still in your quest log, so kept: steps " .. table.concat(kept, ", ") .. ".") end
    return
  end
  local list = table.concat(keys, ", ")
  if arg ~= "confirm" then
    self:Print(("Your furthest finished step is %s (%s). Catchup would skip %d unfinished steps before it: %s."):format(a.key, a.title, #keys, list))
    if #kept > 0 then self:Print("Kept because their quests are in your log: steps " .. table.concat(kept, ", ") .. ".") end
    self:Print("Type |cffffd100/fp catchup confirm|r to do it, or /fp catchup undo afterwards to reverse it.")
    return
  end
  for _, k in ipairs(keys) do self.char.skip[k] = true end
  self.char.lastCatchup = keys
  self.view = nil
  self:Refresh(false)
  self:Print(("Skipped %d steps before step %s: %s. They stay in the Route tab; Skip again on any of them to bring it back."):format(#keys, a.key, list))
  local cur = self.current and route[self.current]
  if cur then self:Print(("You're now on step %s: %s."):format(cur.key, cur.title)) end
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
    if s.key == key then
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
function FP:SetWaypoint(step, quiet)
  if not step then return end
  if not (step.map and step.x and step.y) then
    if not quiet then self:Print("This step has no coordinates. Questie's map markers show the quest givers.") end
    return
  end
  local mapID = FP.MAP[step.map]
  local zone = FP.ZONE[step.map] or step.map
  local x, y = step.x / 100, step.y / 100
  if mapID and TomTom and TomTom.AddWaypoint then
    if self.tomtomUid and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, self.tomtomUid) end
    local ok, uid = pcall(TomTom.AddWaypoint, TomTom, mapID, x, y,
      { title = step.title, persistent = false, minimap = true, world = true, from = "Forever Planner" })
    if ok then self.tomtomUid = uid; return true end
  end
  if mapID and C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    if ok then
      if not quiet then self:Print(("Map pin set: %s, %s %d, %d."):format(step.title, zone, step.x, step.y)) end
      return true
    end
  end
  if not quiet then self:Print(("%s: %s %d, %d"):format(step.title, zone, step.x, step.y)) end
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

function FP:ScanTalents()
  local ranks = {}
  local found = false
  if GetNumTalentTabs and GetNumTalents and GetTalentInfo then
    pcall(function()
      for tab = 1, (GetNumTalentTabs() or 0) do
        for i = 1, (GetNumTalents(tab) or 0) do
          local name, _, _, _, rank = GetTalentInfo(tab, i)
          if type(name) == "string" and type(rank) == "number" then
            ranks[Norm(name)] = rank; found = true
          end
        end
      end
    end)
  end
  self.talentRanks = found and ranks or nil
end

function FP:UnspentTalentPoints()
  if UnitCharacterPoints then
    local ok, n = pcall(UnitCharacterPoints, "player")
    if ok and type(n) == "number" then return n end
  end
  if GetUnspentTalentPoints then
    local ok, n = pcall(GetUnspentTalentPoints)
    if ok and type(n) == "number" then return n end
  end
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
  Weapon = { 16, 17 }, Idol = { 18 },
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
  if c.autoWay == nil then c.autoWay = true end
  if c.trackerShown == nil then c.trackerShown = true end
  FP.db, FP.char = ForeverPlannerDB, c
end

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == "ForeverPlanner" then InitSaved() end
  elseif event == "PLAYER_LOGIN" then
    if not FP.char then InitSaved() end
    local _, class = UnitClass("player")
    FP.class = class
    FP.plan = FP.plans[class]
    FP:Recount()
    FP:ScanItems()
    FP:ScanTalents()
    if FP.BuildUI then FP:BuildUI() end
    FP:Refresh(false)
    if FP.plan then
      FP:Print(("Plan loaded: %s. /fp opens it."):format(FP.plan.name))
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not FP.historyDone and FP.plan then
      FP.historyDone = true
      local function run() FP:ImportHistory(true); FP:Refresh(false) end
      if C_Timer and C_Timer.After then C_Timer.After(6, run) else run() end
    end
  elseif event == "QUEST_COMPLETE" then
    if GetTitleText then FP.lastCompleteTitle = GetTitleText() end
    pcall(FP.RewardAdvice, FP)
  elseif event == "QUEST_TURNED_IN" then
    local id = ...
    if id and FP.char then
      local title = FP.idTitle[id] or FP:TitleForID(id) or FP.lastCompleteTitle
      if title then
        FP.char.doneIds[id] = title
        FP:Recount()
      end
    end
    FP:QueueRefresh()
  elseif event == "QUEST_ACCEPTED" or event == "QUEST_LOG_UPDATE" or event == "QUEST_REMOVED" then
    FP:QueueRefresh()
  elseif event == "PLAYER_LEVEL_UP" then
    local level = ...
    FP:OnLevelUp(level)
    FP:QueueRefresh()
  elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
    FP:ScanTalents()
    FP:QueueRefresh()
  elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE_DELAYED" or event == "UNIT_INVENTORY_CHANGED" then
    FP:ScanItems()
    if FP.UpdateUI then FP:UpdateUI() end
  end
end)

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_COMPLETE", "QUEST_TURNED_IN",
  "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED",
  "PLAYER_TALENT_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" }) do
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
  "/fp reset confirm - clear this character's route progress",
}

SLASH_FOREVERPLANNER1 = "/fp"
SLASH_FOREVERPLANNER2 = "/foreverplanner"
SlashCmdList["FOREVERPLANNER"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if not FP.plan and cmd ~= "help" then
    FP:Print(("No plan for your class (%s) yet. Plans are made in your project's class chat."):format(tostring(FP.class)))
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
  elseif cmd == "lock" then
    FP.char.locked = not FP.char.locked
    FP:Print("Tracker " .. (FP.char.locked and "locked." or "unlocked: drag it to move."))
  elseif cmd == "sync" then FP:ImportHistory(true); FP:Refresh(false)
  elseif cmd == "catchup" then FP:Catchup(arg)
  elseif cmd == "check" then
    local i = FP:ViewIndex()
    local s = i and FP.plan.route[i]
    if not s then FP:Print("No step shown."); return end
    FP:Print(("Step %s: %s"):format(s.key, s.title))
    for _, o in ipairs(s.q or {}) do
      local k = Norm(o.q)
      local inLog = FP.log[k]
      FP:Print(("  %s %s - in log: %s, turned in: %d"):format(FP:ObjDone(o) and "|cff00ff00done|r" or "|cffff8000open|r",
        FP:ObjText(o), inLog and (inLog.complete and "yes, complete" or "yes") or "no", FP.doneCount[k] or 0))
    end
  elseif cmd == "reset" and arg == "confirm" then
    wipe(FP.char.manual); wipe(FP.char.skip)
    FP.view = nil
    FP:Refresh(false)
    FP:Print("Route progress cleared. Quest history still counts.")
  else
    for _, line in ipairs(HELP) do FP:Print(line) end
  end
end
