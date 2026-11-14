-- Forever Planner: tracker and plan window.
local FP = ForeverPlanner

local OK   = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local WAIT = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14:14|t"
local NO   = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"
local DOT  = "|cff808080-|r"
local GOLD, GREY, WHITE = "|cffffd100", "|cff9d9d9d", "|cffffffff"

local function Bg(f, a)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints()
  t:SetColorTexture(0, 0, 0, a or 0.6)
  return t
end

local function Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h or 20)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function SavePos(frame, key)
  local point, _, rel, x, y = frame:GetPoint()
  FP.char[key] = { point, rel, x, y }
end

local function RestorePos(frame, key, dp, dx, dy)
  frame:ClearAllPoints()
  local p = FP.char[key]
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else frame:SetPoint(dp, UIParent, dp, dx, dy) end
end

local function Movable(frame, key, lockable)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not (lockable and FP.char.locked) then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos(self, key) end)
end

------------------------------------------------------------------------
-- Tracker: the step you're on, its quests, and what to do next
------------------------------------------------------------------------
local tracker, lines = nil, {}
local WIDTH = 310

local function BuildTracker()
  tracker = CreateFrame("Frame", "ForeverPlannerTracker", UIParent)
  tracker:SetSize(WIDTH, 120)
  tracker:SetFrameStrata("MEDIUM")
  Bg(tracker, 0.55)
  Movable(tracker, "trackerPos", true)
  RestorePos(tracker, "trackerPos", "RIGHT", -40, 120)
  tracker:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then FP:ToggleMain() end end)

  tracker.head = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tracker.head:SetPoint("TOPLEFT", 8, -6)
  tracker.head:SetWidth(WIDTH - 16)
  tracker.head:SetJustifyH("LEFT")

  tracker.title = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  tracker.title:SetWidth(WIDTH - 16)
  tracker.title:SetJustifyH("LEFT")

  tracker.nextLine = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tracker.nextLine:SetWidth(WIDTH - 16)
  tracker.nextLine:SetJustifyH("LEFT")

  tracker.note = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tracker.note:SetWidth(WIDTH - 16)
  tracker.note:SetJustifyH("LEFT")
  tracker.note:SetTextColor(0.8, 0.8, 0.8)

  tracker.gear = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tracker.gear:SetWidth(WIDTH - 16)
  tracker.gear:SetJustifyH("LEFT")

  tracker.talent = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tracker.talent:SetWidth(WIDTH - 16)
  tracker.talent:SetJustifyH("LEFT")

  -- Class quest ready: left-click adds it to the route, right-click hides it.
  local side = CreateFrame("Button", nil, tracker)
  side:SetSize(WIDTH - 16, 14)
  side:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  side.text = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  side.text:SetPoint("TOPLEFT")
  side.text:SetWidth(WIDTH - 16)
  side.text:SetJustifyH("LEFT")
  side:SetScript("OnClick", function(self, btn)
    if not self.sideId then return end
    if btn == "RightButton" then FP:DismissSide(self.sideId) else FP:StartSide(self.sideId) end
  end)
  side:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.side) then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.side.title)
    if self.side.why then GameTooltip:AddLine(self.side.why, 1, 1, 1, true) end
    GameTooltip:AddLine("Left-click: add it to your route before the current step.", 0.6, 0.8, 1, true)
    GameTooltip:AddLine("Right-click: hide this suggestion.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  side:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  tracker.side = side

  local bar = CreateFrame("Frame", nil, tracker)
  bar:SetSize(WIDTH - 12, 20)
  bar:SetPoint("BOTTOMLEFT", 6, 5)
  tracker.bar = bar
  local specs = {
    { "<",    30, function() FP:Browse(-1) end },
    { ">",    30, function() FP:Browse(1) end },
    { "Now",  40, function() FP.view = nil; FP:UpdateUI() end },
    { "Done", 46, function() ForeverPlanner_StepDone() end },
    { "Skip", 44, function() local i = FP:ViewIndex(); if i then FP:ToggleSkip(i) end end },
    { "Way",  42, function() ForeverPlanner_Waypoint() end },
    { "Plan", 46, function() FP:ToggleMain() end },
  }
  local x = 0
  for _, s in ipairs(specs) do
    local b = Button(bar, s[1], s[2], 20, s[3])
    b:SetPoint("LEFT", bar, "LEFT", x, 0)
    x = x + s[2] + 2
  end
end

local function Line(i)
  if not lines[i] then
    local fs = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(WIDTH - 16)
    fs:SetJustifyH("LEFT")
    lines[i] = fs
  end
  return lines[i]
end

function FP:UpdateTracker()
  if not tracker then return end
  if not self.char.trackerShown then tracker:Hide(); return end
  tracker:Show()
  for _, fs in ipairs(lines) do fs:Hide() end

  local route = self.plan and self.plan.route
  local i = self:ViewIndex()
  local s = route and i and route[i]
  local y = -6
  local function place(fs, gap)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 8, y - (gap or 0))
    fs:Show()
    y = y - (gap or 0) - fs:GetStringHeight()
  end

  if not self.plan then
    tracker.head:SetText("Forever Planner")
    place(tracker.head)
    tracker.title:SetText("No plan for your class yet.")
    place(tracker.title, 4)
    tracker.nextLine:Hide(); tracker.note:Hide(); tracker.talent:Hide(); tracker.gear:Hide()
    tracker:SetHeight(-y + 32)
    return
  end
  if not s then
    tracker.head:SetText(GOLD .. "Forever Planner|r")
    place(tracker.head)
    tracker.title:SetText("Route finished for this plan version.")
    place(tracker.title, 4)
    tracker.nextLine:Hide(); tracker.note:Hide(); tracker.talent:Hide(); tracker.gear:Hide()
    tracker:SetHeight(-y + 32)
    return
  end

  local st = self.status[i]
  local viewing = (self.view ~= nil and self.view ~= self.current)
  local tag = viewing and (GREY .. " (browsing; Now to return)|r") or ""
  if st == "done" then tag = tag .. " " .. OK
  elseif st == "skipped" then tag = tag .. GREY .. ((self.leftBehind and self.leftBehind[i]) and " skipped (you moved on)|r" or " skipped|r")
  elseif st == "na" then tag = tag .. GREY .. " not needed|r" elseif st == "along" then tag = tag .. GREY .. " on the way|r" end
  local map, tx, ty = self:StepTarget(s)
  local zone = self:ZoneName(map) or ""
  local coord = (tx and ty) and (" %.0f, %.0f"):format(tx, ty) or ""
  tracker.head:SetText(("Step %s/%d  %s%s|r%s  lvl %d%s"):format(s.num or s.key, #route, WHITE, zone, coord, s.lvl or 0, tag))
  place(tracker.head)

  tracker.title:SetText(s.title)
  place(tracker.title, 3)

  -- Goals: all of them, or only the open ones when the step is long.
  local goals = s.q or {}
  local hideDone = #goals > 9
  local n, hidden = 0, 0
  for idx, o in ipairs(goals) do
    local done = self:ObjDone(o, s, idx)
    if o.k == "i" then
      if o.txt and n < 14 then
        n = n + 1
        local fs = Line(n)
        fs:SetText(GREY .. "  " .. o.txt .. "|r")
        place(fs, 2)
      end
    elseif self:GoalDropped(o) then
      if n < 14 then
        n = n + 1
        local fs = Line(n)
        fs:SetText(GREY .. "  " .. self:ObjText(o) .. " (not taken)|r")
        place(fs, 2)
      end
    elseif done and hideDone then
      hidden = hidden + 1
    elseif n < 14 then
      n = n + 1
      local fs = Line(n)
      local text = self:ObjText(o)
      if done then
        fs:SetText(OK .. " " .. GREY .. text .. "|r")
      else
        local inLog = (o.id and o.id ~= 0) and self.logById[o.id] or (o.q and not o.id and self.log[FP.Norm(o.q)])
        local icon = (inLog and inLog.complete) and WAIT or DOT
        fs:SetText(icon .. " " .. text)
      end
      place(fs, 2)
    end
  end
  if hidden > 0 then
    n = n + 1
    local fs = Line(n)
    fs:SetText(GREY .. ("  (%d done goals hidden)"):format(hidden) .. "|r")
    place(fs, 2)
  end

  -- Goals of "on the way" steps you are passing through.
  if not viewing and self.current then
    local shown = 0
    for j = self.current - 1, math.max(1, self.current - 25), -1 do
      local a = route[j]
      if self.status[j] == "along" then
        for idx, o in ipairs(a.q) do
          if shown < 3 and o.k ~= "i" and not o.opt and not self:ObjDone(o, a, idx) then
            shown = shown + 1
            n = n + 1
            local fs = Line(n)
            fs:SetText("|cff66ccffOn the way:|r " .. self:ObjText(o))
            place(fs, 2)
          end
        end
      end
    end
  end

  -- Trainer, flight path or hearth left open on the steps just finished
  if not viewing then
    for k, r in ipairs(self:Reminders()) do
      if k > 2 then break end
      n = n + 1
      local fs = Line(n)
      fs:SetText("|cffffd100Don't forget:|r " .. (r.goal.txt or ""))
      place(fs, 2)
    end
  end

  local nextText, nextGoal = self:NextAction(s)
  if nextText and not viewing then
    tracker.nextLine:SetText("Next: " .. WHITE .. nextText .. "|r")
    place(tracker.nextLine, 5)
  elseif (s.q == nil or #s.q == 0 or st == "open") and not viewing and st == "open" then
    tracker.nextLine:SetText("Next: " .. WHITE .. "do this, then press Done|r")
    place(tracker.nextLine, 5)
  else
    tracker.nextLine:Hide()
  end

  local gear = self:GearHere(s.key)
  if #gear > 0 then
    local parts = {}
    for k, it in ipairs(gear) do
      if k > 4 then parts[#parts + 1] = ("+%d more"):format(#gear - 4); break end
      local tag = (it.role == "stopgap") and (it.slot .. ", if better") or it.slot
      parts[#parts + 1] = ("%s%s|r (%s)"):format(WHITE, it.name, tag)
    end
    tracker.gear:SetText("Gear here: " .. table.concat(parts, ", "))
    place(tracker.gear, 5)
  else
    tracker.gear:Hide()
  end

  local note = s.note
  if nextGoal and nextGoal.note and not viewing then
    note = (note and note ~= "") and (nextGoal.note .. "\n" .. note) or nextGoal.note
  end
  if note and note ~= "" then
    tracker.note:SetText(note)
    place(tracker.note, 4)
  else
    tracker.note:Hide()
  end

  local pts = self:UnspentTalentPoints()
  local tl, tt = self:NextTalent()
  if pts and pts > 0 and tt then
    tracker.talent:SetText(("Talent point ready: %s%s|r"):format(WHITE, tt))
    place(tracker.talent, 5)
  else
    tracker.talent:Hide()
  end

  local ready = (not viewing) and self:SideReady() or {}
  local sd = ready[1]
  if sd then
    tracker.side.sideId, tracker.side.side = sd.id, sd
    tracker.side.text:SetText(("|cff66ccffClass quest ready:|r %s%s|r %s(click to add)|r"):format(WHITE, sd.title, GREY))
    tracker.side:SetHeight(tracker.side.text:GetStringHeight() + 2)
    tracker.side:ClearAllPoints()
    tracker.side:SetPoint("TOPLEFT", 8, y - 5)
    tracker.side:Show()
    y = y - 5 - tracker.side:GetHeight()
  else
    tracker.side:Hide()
  end

  tracker:SetHeight(-y + 32)
end

function FP:ToggleTracker()
  self.char.trackerShown = not self.char.trackerShown
  self:UpdateTracker()
end

------------------------------------------------------------------------
-- Plan window: Route, Talents, Macros, Gear
------------------------------------------------------------------------
local main, scroll, child, rows, macroBox
local tab = "route"
local selectedMacro

local function Row(i)
  rows = rows or {}
  local r = rows[i]
  if not r then
    r = CreateFrame("Button", nil, child)
    r:SetWidth(500)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT", 4, -2)
    r.text:SetWidth(492)
    r.text:SetJustifyH("LEFT")
    rows[i] = r
  end
  return r
end

local function Render(list)
  if rows then for _, r in ipairs(rows) do r:Hide() end end
  local y, focusY = 0, nil
  for i, item in ipairs(list) do
    local r = Row(i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    r.text:SetFontObject(item.header and "GameFontNormal" or "GameFontHighlightSmall")
    r.text:SetText(item.text)
    local h = r.text:GetStringHeight() + (item.header and 10 or 5)
    r:SetHeight(h)
    r:SetScript("OnClick", item.onClick)
    r:EnableMouse(item.onClick ~= nil)
    r:Show()
    if item.focus then focusY = y end
    y = y + h
  end
  child:SetHeight(math.max(y, 10))
  return focusY
end

local function RouteList()
  local list, lastSec = {}, nil
  local route = FP.plan.route
  local vi = FP:ViewIndex()
  for i, s in ipairs(route) do
    if s.sec ~= lastSec then
      list[#list + 1] = { header = true, text = GOLD .. s.sec .. "|r" }
      lastSec = s.sec
    end
    local st = FP.status[i]
    local icon = (st == "done" and OK) or (st == "skipped" and NO) or (i == FP.current and WAIT) or DOT
    if st == "na" or st == "along" then icon = GREY .. (st == "na" and "n/a" or "way") .. "|r" end
    local req, reqDone = FP:StepCounts(s)
    local count = req > 0 and ("  " .. GREY .. reqDone .. "/" .. req .. "|r") or ""
    local name = (i == vi) and (GOLD .. "> " .. s.title .. "|r") or ((st == "open") and s.title or (GREY .. s.title .. "|r"))
    list[#list + 1] = {
      text = ("%s  %s. %s  %s(%d)|r%s"):format(icon, s.num or s.key, name, GREY, s.lvl or 0, count),
      focus = (i == vi),
      onClick = function() FP.view = (i ~= FP.current) and i or nil; FP:UpdateUI() end,
    }
  end
  return list
end

local function TalentList()
  local p = FP.plan
  local list = { { header = true, text = GOLD .. p.name .. "|r" } }
  if p.talentNote then list[#list + 1] = { text = p.talentNote } end
  local pts = FP:UnspentTalentPoints()
  if pts then list[#list + 1] = { text = ("Unspent talent points: %s%d|r"):format(WHITE, pts) } end
  if not FP.talentRanks then
    list[#list + 1] = { text = GREY .. "Ticks are by level here (this client didn't report talent ranks).|r" }
  end
  local nextLvl = FP:NextTalent()
  for level = 1, 60 do
    local text = p.talents[level]
    if text then
      local name, rank = FP:ParseTalent(text)
      local taken
      if FP.talentRanks then taken = (FP.talentRanks[FP.Norm(name)] or 0) >= rank
      else taken = level < FP:PlayerLevel() end
      local icon = taken and OK or ((level == nextLvl) and WAIT or DOT)
      local t = (level == nextLvl) and (GOLD .. text .. "|r") or (taken and (GREY .. text .. "|r") or text)
      list[#list + 1] = { text = ("%s  %d: %s"):format(icon, level, t), focus = (level == nextLvl) }
      if p.talentNotes and p.talentNotes[level] then
        list[#list + 1] = { text = "      " .. GREY .. p.talentNotes[level] .. "|r" }
      end
    end
  end
  if p.training then
    list[#list + 1] = { header = true, text = GOLD .. "Trainer|r" }
    for level = 1, 60 do
      if p.training[level] then
        local icon = (level <= FP:PlayerLevel()) and OK or DOT
        list[#list + 1] = { text = ("%s  %d: %s"):format(icon, level, p.training[level]) }
      end
    end
  end
  return list
end

local function MacroList()
  local list = { { header = true, text = GOLD .. "Macros for your level|r" },
    { text = "Click a macro to show its text below. Write saves it into your character macros (out of combat); an existing macro of the same name is updated in place, so it stays on your bars." } }
  if #FP.plan.macros == 0 then
    list[#list + 1] = { text = GREY .. "No macros for this spec yet. They come from your class chat in the WoW Forever project, which publishes them with the next update.|r" }
  end
  if FP.plan.macroNote then list[#list + 1] = { text = FP.plan.macroNote } end
  local current = {}
  for _, m in ipairs(FP:CurrentMacros()) do current[m] = true end
  for _, m in ipairs(FP.plan.macros) do
    local mark = current[m] and OK or DOT
    local nameText = current[m] and (WHITE .. m.name .. "|r") or (GREY .. m.name .. "|r")
    local sel = (m == selectedMacro) and (GOLD .. " (shown)|r") or ""
    list[#list + 1] = {
      text = ("%s  %s  %s%d-%d|r, %d chars, %s%s\n      %s"):format(mark, nameText, GREY, m.from, m.to, #m.text, m.bar or "", sel, m.desc or ""),
      onClick = function() selectedMacro = m; FP:UpdateMain() end,
    }
  end
  return list
end

local function GearList()
  local p = FP.plan
  local list = {}
  local lvl = FP:PlayerLevel()
  list[#list + 1] = { text = GOLD .. "Easier view: press C. The gear plan opens beside your character window, with icons (or type /fp gear).|r" }
  local function stateIcon(name)
    local st = FP:ItemState(name)
    return (st == "equipped" and OK) or (st == "bags" and WAIT) or DOT
  end
  local function stepTag(key)
    local i = FP:StepIndex(key)
    if not i then return "" end
    local st = FP.status[i]
    local s = p.route[i]
    local passed = (st == "done" or st == "skipped") and (GREY .. ", step passed: rerun it or check the AH|r") or ""
    return ("  %s[step %s, lvl %d]|r%s"):format(GOLD, s.num or key, s.lvl or 0, passed)
  end
  local function goStep(key)
    if not FP:StepIndex(key) then return nil end
    return function() FP:ShowStep(key, true) end
  end

  if not p.gear or #p.gear == 0 then
    list[#list + 1] = { header = true, text = GOLD .. "Gear|r" }
    list[#list + 1] = { text = GREY .. "No gear plan for this spec yet. Gear lists come from your class chat in the WoW Forever project and arrive with the next update.|r" }
    return list
  end

  -- 1. What you still need, in route order
  local path, worn, total = FP:UpgradePath()
  local g = FP:GearBracket()
  list[#list + 1] = { header = true, text = ("%sStill need (levels %d-%d): best piece worn in %d of %d slots|r"):format(GOLD, g and g.from or 0, g and g.to or 0, worn, total) }
  if #path == 0 then
    list[#list + 1] = { text = OK .. "  Every slot has its best piece for this level band." }
  else
    list[#list + 1] = { text = GREY .. "In the order your route reaches them. Click one to see that step and set a waypoint.|r" }
    for _, it in ipairs(path) do
      local where = it.step and stepTag(it.step) or ("  " .. GREY .. "[not on the route: " .. (it.src or "?") .. "]|r")
      local label = it.role == "alt" and " (fallback)" or ""
      list[#list + 1] = {
        text = ("%s  %s%s|r: %s%s %s(%s)|r%s"):format(stateIcon(it.name), WHITE, it.slot, it.name, label, GREY, it.src or "", where),
        onClick = it.step and goStep(it.step) or nil,
      }
    end
  end

  -- 2. Full tables per level band, with what you wear now
  for _, gb in ipairs(p.gear or {}) do
    local now = (lvl >= gb.from and lvl <= gb.to)
    if gb.to >= lvl then
      list[#list + 1] = { header = true, text = GOLD .. gb.label .. (now and "  (your level)" or "") .. "|r" }
      local shown = {}
      for _, s in ipairs(gb.slots) do
        if not shown[s.slot] then
          shown[s.slot] = true
          list[#list + 1] = { text = ("%s%s|r  %snow: %s|r"):format(WHITE, s.slot, GREY, FP:SlotNow(s.slot)) }
        end
        list[#list + 1] = {
          text = ("      %s %s %s(%s)|r%s"):format(stateIcon(s.best), s.best, GREY, s.src or "", s.step and stepTag(s.step) or ""),
          onClick = goStep(s.step),
        }
        if s.alt then
          list[#list + 1] = {
            text = ("      %s or %s %s(%s)|r%s"):format(stateIcon(s.alt), s.alt, GREY, s.altsrc or "", s.altstep and stepTag(s.altstep) or ""),
            onClick = goStep(s.altstep),
          }
        end
      end
    end
  end

  -- 3. Stopgaps still ahead of you
  local gaps = {}
  for _, s in ipairs(p.stopgaps or {}) do
    local i = FP:StepIndex(s.step)
    if FP:ItemState(s.name) ~= "equipped" and i and FP.status[i] == "open" then gaps[#gaps + 1] = s end
  end
  if #gaps > 0 then
    list[#list + 1] = { header = true, text = GOLD .. "Stopgaps on the way (take if better than what you wear)|r" }
    for _, s in ipairs(gaps) do
      list[#list + 1] = {
        text = ("%s  %s%s|r: %s %s(%s)|r%s"):format(stateIcon(s.name), WHITE, s.slot, s.name, GREY, s.src or "", stepTag(s.step)),
        onClick = goStep(s.step),
      }
    end
  end

  for _, set in ipairs(p.sets or {}) do
    local have = 0
    for _, piece in ipairs(set.pieces) do if FP:ItemState(piece) == "equipped" then have = have + 1 end end
    list[#list + 1] = { header = true, text = ("%s%s: %d/%d worn|r"):format(GOLD, set.name, have, #set.pieces) }
    list[#list + 1] = { text = set.bonus }
  end
  list[#list + 1] = { text = GREY .. "Tick: worn. Hourglass: in your bags. Items are matched by exact name.|r" }
  return list
end

local function BuildMain()
  main = CreateFrame("Frame", "ForeverPlannerMain", UIParent)
  main:SetSize(540, 500)
  main:SetFrameStrata("HIGH")
  Bg(main, 0.85)
  Movable(main, "mainPos")
  RestorePos(main, "mainPos", "CENTER", 0, 40)
  main:Hide()
  if UISpecialFrames then table.insert(UISpecialFrames, "ForeverPlannerMain") end -- Escape closes it

  main.title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  main.title:SetPoint("TOPLEFT", 12, -10)
  main.title:SetText("Forever Planner")

  local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local tabs = { { "Route", "route" }, { "Talents", "talents" }, { "Macros", "macros" }, { "Gear", "gear" } }
  for k, t in ipairs(tabs) do
    local b = Button(main, t[1], 80, 22, function() tab = t[2]; FP:UpdateMain(true) end)
    b:SetPoint("TOPLEFT", 12 + (k - 1) * 84, -34)
  end

  scroll = CreateFrame("ScrollFrame", "ForeverPlannerScroll", main, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -64)
  child = CreateFrame("Frame", nil, scroll)
  child:SetSize(500, 10)
  scroll:SetScrollChild(child)

  -- Macro text box (Macros tab only)
  local box = CreateFrame("Frame", nil, main)
  box:SetPoint("BOTTOMLEFT", 12, 10)
  box:SetPoint("BOTTOMRIGHT", -12, 10)
  box:SetHeight(140)
  Bg(box, 0.5)
  macroBox = box
  local eb = CreateFrame("EditBox", nil, box)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(ChatFontNormal)
  eb:SetPoint("TOPLEFT", 6, -6)
  eb:SetPoint("TOPRIGHT", -6, -6)
  eb:SetHeight(100)
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  eb:SetScript("OnTextChanged", function(self, user)
    if user and selectedMacro then self:SetText(selectedMacro.text); self:HighlightText() end
  end)
  box.edit = eb
  box.info = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.info:SetPoint("BOTTOMLEFT", 6, 8)
  local write = Button(box, "Write to my macros", 150, 22, function() if selectedMacro then FP:WriteMacro(selectedMacro) end end)
  write:SetPoint("BOTTOMRIGHT", -6, 4)
end

function FP:UpdateMain(scrollToFocus)
  if not main or not main:IsShown() then return end
  if not self.plan then return end
  macroBox:SetShown(tab == "macros")
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", 12, -64)
  scroll:SetPoint("BOTTOMRIGHT", -32, (tab == "macros") and 160 or 12)

  local list
  if tab == "route" then
    main.title:SetText("Forever Planner: " .. (self.plan.routeName or "Route"))
    list = RouteList()
  elseif tab == "talents" then
    main.title:SetText("Forever Planner: Talents")
    list = TalentList()
  elseif tab == "macros" then
    main.title:SetText("Forever Planner: Macros")
    if not selectedMacro then selectedMacro = self:CurrentMacros()[1] end
    list = MacroList()
    if selectedMacro then
      macroBox.edit:SetText(selectedMacro.text)
      macroBox.info:SetText(("%s, levels %d-%d: %d/255 characters. Ctrl+A, Ctrl+C to copy."):format(selectedMacro.name, selectedMacro.from, selectedMacro.to, #selectedMacro.text))
    end
  else
    main.title:SetText("Forever Planner: Gear")
    list = GearList()
  end
  local focusY = Render(list)
  if scrollToFocus then
    local maxScroll = math.max(0, child:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(focusY and math.min(math.max(focusY - 60, 0), maxScroll) or 0)
  end
end

function FP:ToggleMain()
  if not main then return end
  if main:IsShown() then main:Hide() else main:Show(); self:UpdateMain(true) end
end

function FP:BuildUI()
  if tracker then return end
  BuildTracker()
  BuildMain()
end

function FP:UpdateUI()
  self:UpdateTracker()
  self:UpdateMain(false)
end

------------------------------------------------------------------------
-- Talent screen: glow on the next planned talent and a note saying what and where.
-- Works with Classic's one-tree-at-a-time window and with Forever's three-tree window:
-- the talent's button is found by its icon, so no frame names need to be known.
-- Purely visual: you still click the talent (and Apply Changes) yourself.
------------------------------------------------------------------------
local KNOWN_TALENT_FRAMES = { "TalentFrame", "PlayerTalentFrame", "PlayerSpellsFrame", "ClassTalentFrame" }
local glow, tabGlow, hint, watcher
FP.talentWindows = {}

local function MakeGlow(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetFrameStrata("DIALOG")
  local t = f:CreateTexture(nil, "OVERLAY")
  t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  t:SetBlendMode("ADD")
  t:SetVertexColor(1, 0.82, 0)
  t:SetPoint("CENTER")
  f.tex = t
  local ag = f.CreateAnimationGroup and f:CreateAnimationGroup()
  if ag then
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    if a then a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7) end
    f.anim = ag
  end
  f:Hide()
  return f
end

local function ShowGlowOn(g, target, size)
  g:SetParent(target)
  g:ClearAllPoints()
  g:SetAllPoints(target)
  g.tex:SetSize(size, size)
  g:Show()
  if g.anim and not g.anim:IsPlaying() then g.anim:Play() end
end

local function HideGlow(g)
  if g then
    if g.anim then g.anim:Stop() end
    g:Hide()
  end
end

local function Visible(f)
  if not f then return false end
  if f.IsVisible then local ok, v = pcall(f.IsVisible, f); if ok and v ~= nil then return v and true or false end end
  return f.IsShown and f:IsShown() and true or false
end

local function NameOf(f)
  if f and f.GetName then local ok, n = pcall(f.GetName, f); if ok and type(n) == "string" then return n end end
end

-- Remember every top-level frame that looks like a talent window.
function FP:FindTalentWindows()
  local list, seen = {}, {}
  local function add(f)
    if f and not seen[f] then seen[f] = true; list[#list + 1] = f end
  end
  for _, n in ipairs(KNOWN_TALENT_FRAMES) do add(_G[n]) end
  if EnumerateFrames then
    pcall(function()
      local f, count = EnumerateFrames(), 0
      while f and count < 30000 do
        count = count + 1
        local n = NameOf(f)
        if n and not n:find("^ForeverPlanner") and (n:find("Talent") or n:find("SpellsFrame")) then
          local p = f.GetParent and f:GetParent()
          if p == nil or p == UIParent then add(f) end
        end
        f = EnumerateFrames(f)
      end
    end)
  end
  self.talentWindows = list
  return list
end

local function OpenTalentFrame()
  for _, f in ipairs(FP.talentWindows) do
    if Visible(f) then return f, NameOf(f) end
  end
end

local function TexturesOf(region)
  local out = {}
  if region.GetTexture then
    local ok, t = pcall(region.GetTexture, region); if ok and t ~= nil then out[#out + 1] = t end
  end
  if region.GetTextureFileID then
    local ok, t = pcall(region.GetTextureFileID, region); if ok and t ~= nil then out[#out + 1] = t end
  end
  return out
end

local function IconMatches(region, icon)
  for _, t in ipairs(TexturesOf(region)) do
    if tostring(t):lower() == tostring(icon):lower() then return true end
  end
  return false
end

local function NodeOf(f)
  if f.GetNodeID then local ok, n = pcall(f.GetNodeID, f); if ok and n then return n end end
  return rawget(f, "nodeID")
end

-- Depth-first search of the window for the talent's button: by node ID (modern talent window),
-- else by its icon. Prefers buttons (the clickable talent) over plain frames.
local function FindByIcon(root, icon, nodeID)
  if icon == nil and nodeID == nil then return nil end
  local best
  local function walk(f, depth)
    if depth > 12 or not Visible(f) then return end
    if nodeID and NodeOf(f) == nodeID then best = f; return true end
    if icon ~= nil and f.GetRegions then
      for _, r in ipairs({ f:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and Visible(r) and IconMatches(r, icon) then
          local isButton = f.IsObjectType and f:IsObjectType("Button")
          if isButton then best = f; return true end
          best = best or f
        end
      end
    end
    if f.GetChildren then
      for _, c in ipairs({ f:GetChildren() }) do
        if walk(c, depth + 1) then return true end
      end
    end
  end
  walk(root, 0)
  return best
end

-- Classic's window: talent buttons are named <Frame>Talent<n> and their ID is the talent index.
local function FindNamedButton(frameName, info)
  if not frameName then return nil end
  for i = 1, 100 do
    local b = _G[frameName .. "Talent" .. i]
    if not b then break end
    if Visible(b) and b.GetID and b:GetID() == info.index then
      local icon = _G[frameName .. "Talent" .. i .. "IconTexture"]
      if not icon or info.icon == nil or IconMatches(icon, info.icon) then return b end
    end
  end
end

-- Classic's window: one tree shown, buttons named <Frame>Talent<n>, tabs <Frame>Tab<n>.
local function SelectedTab(frame)
  if PanelTemplates_GetSelectedTab then
    local ok, t = pcall(PanelTemplates_GetSelectedTab, frame)
    if ok and type(t) == "number" then return t end
  end
  return frame.selectedTab or frame.currentSelectedTab
end

local function ClassicTabButton(frameName, info)
  if not frameName or not _G[frameName .. "Talent1"] then return nil end -- not a Classic window
  local frame = _G[frameName]
  local shown = SelectedTab(frame)
  if shown ~= nil and shown ~= info.tab then return _G[frameName .. "Tab" .. info.tab] end
end

function FP:UpdateTalentGlow()
  local frame, frameName = OpenTalentFrame()
  if not frame or not (self.plan and self.char) or self.char.talentGlow == false then
    HideGlow(glow); HideGlow(tabGlow); if hint then hint:Hide() end; return
  end
  if not glow then glow = MakeGlow(frame); tabGlow = MakeGlow(frame) end
  if not hint then
    hint = CreateFrame("Frame", "ForeverPlannerTalentHint", frame)
    hint:SetSize(360, 34)
    if hint.SetClampedToScreen then hint:SetClampedToScreen(true) end
    hint:SetFrameStrata("DIALOG")
    Bg(hint, 0.8)
    hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint.text:SetPoint("TOPLEFT", 8, -6)
    hint.text:SetWidth(344)
    hint.text:SetJustifyH("LEFT")
  end
  hint:SetParent(frame)
  hint:ClearAllPoints()
  hint:SetPoint("TOP", frame, "BOTTOM", 0, -4)

  local pts = self:UnspentTalentPoints()
  local nxt = self:NextTalentInfo()
  HideGlow(glow); HideGlow(tabGlow)
  if not nxt then
    hint.text:SetText(GOLD .. "Forever Planner:|r every planned talent is taken.")
    hint:SetHeight(hint.text:GetStringHeight() + 12); hint:Show()
    return
  end
  local info = nxt.info
  local where = ""
  if info and info.tier then
    where = ("\n%s tree, row %s, column %s"):format(info.tabName or ("tree " .. tostring(info.tab)), tostring(info.tier), tostring(info.column or "?"))
  elseif info and info.tabName then
    where = "\n" .. info.tabName .. " tree"
  end
  local lead = (pts and pts > 0) and ("Spend your point: " .. WHITE .. nxt.text .. "|r") or ("Next pick (level " .. nxt.level .. "): " .. WHITE .. nxt.text .. "|r")
  hint.text:SetText(GOLD .. "Forever Planner|r  " .. lead .. where)
  hint:SetHeight(hint.text:GetStringHeight() + 12)
  hint:Show()

  self.talentGlowTarget = nil
  if not (info and pts and pts > 0) then return end
  local tabButton = ClassicTabButton(frameName, info)
  if tabButton then
    ShowGlowOn(tabGlow, tabButton, (tabButton.GetWidth and tabButton:GetWidth() or 80) * 1.3)
    self.talentGlowTarget = NameOf(tabButton) or "tab"
    return
  end
  local b = FindNamedButton(frameName, info) or FindByIcon(frame, nil, info.nodeID) or FindByIcon(frame, info.icon)
  if b then
    ShowGlowOn(glow, b, (b.GetWidth and b:GetWidth() or 37) * 1.9)
    self.talentGlowTarget = NameOf(b) or "talent button"
  end
end

-- What the addon sees, for when the highlight doesn't appear.
function FP:TalentDebug()
  self:ScanTalents()
  self:FindTalentWindows()
  local raw = UnitCharacterPoints and select(2, pcall(UnitCharacterPoints, "player"))
  local ti = self.traitsInfo
  self:Print(("Talents %s: system %s%s, points: game %s / traits %s / used %s, ranks read %s"):format(
    self.version, tostring(self.talentAPI),
    (self.talentAPI == "traits" and ti) and (" (config %s, %d trees, %d nodes)"):format(tostring(ti.configID), ti.trees, ti.nodes) or "",
    tostring(raw), tostring(self.traitsUnspent), tostring(self:UnspentTalentPoints()), self.talentRanks and "yes" or "no"))
  local nxt = self:NextTalentInfo()
  if nxt then
    local i = nxt.info
    self:Print(("Next pick: %s; %s"):format(nxt.text, i and ("found: node %s, icon %s, rank %s/%s, tree %s"):format(
      tostring(i.nodeID), tostring(i.icon), tostring(i.rank), tostring(i.maxRank), tostring(i.tabName or i.tab)) or "NOT found among your talents"))
  end
  local names = {}
  for _, f in ipairs(self.talentWindows) do if Visible(f) then names[#names + 1] = NameOf(f) or "?" end end
  self:Print("Open talent windows: " .. (#names > 0 and table.concat(names, ", ") or "none"))
  local frame, frameName = OpenTalentFrame()
  if frame and nxt and nxt.info then
    local how, b = "none"
    b = FindNamedButton(frameName, nxt.info); if b then how = "classic name" end
    if not b then b = FindByIcon(frame, nil, nxt.info.nodeID); if b then how = "node ID" end end
    if not b then b = FindByIcon(frame, nxt.info.icon); if b then how = "icon" end end
    self:Print(("Button on %s: %s (%s)"):format(tostring(frameName), b and (NameOf(b) or "unnamed") or "not found", how))
  elseif not frame then
    self:Print("Open your talent window (N) and run /fp talentdebug again.")
  end
end

-- Watch for the talent window opening or changing, without touching Blizzard's code.
watcher = CreateFrame("Frame")
local elapsed, wasOpen, lastKey, rescanAt = 0, false, nil, nil
watcher:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + (dt or 0)
  if elapsed < 0.2 then return end
  elapsed = 0
  if rescanAt and GetTime and GetTime() >= rescanAt then rescanAt = nil; FP:FindTalentWindows() end
  local frame, frameName = OpenTalentFrame()
  local key = frame and (tostring(frameName) .. ":" .. tostring(SelectedTab(frame)) .. ":" .. tostring(FP:UnspentTalentPoints()) .. ":" .. tostring(FP.talentSpent))
  if (frame ~= nil) ~= wasOpen or key ~= lastKey then
    wasOpen, lastKey = frame ~= nil, key
    if frame then FP:ScanTalents() end
    FP:UpdateTalentGlow()
  end
end)
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
  -- Talent windows are often created when their Blizzard addon loads: look again a moment later
  -- (many addons load at once at login, so this waits and scans once).
  rescanAt = (GetTime and GetTime() or 0) + 1
end)
FP.talentWatcher = watcher

------------------------------------------------------------------------
-- One-time setup window (first login of each character; /fp setup reopens it)
------------------------------------------------------------------------
local setup
local function BuildSetup()
  setup = CreateFrame("Frame", "ForeverPlannerSetup", UIParent)
  setup:SetSize(470, 300)
  setup:SetFrameStrata("DIALOG")
  setup:SetPoint("CENTER", 0, 60)
  Bg(setup, 0.92)
  setup:SetMovable(true)
  setup:EnableMouse(true)
  setup:RegisterForDrag("LeftButton")
  setup:SetScript("OnDragStart", setup.StartMoving)
  setup:SetScript("OnDragStop", setup.StopMovingOrSizing)
  setup:SetClampedToScreen(true)
  setup.title = setup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  setup.title:SetPoint("TOPLEFT", 14, -12)
  setup.intro = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  setup.intro:SetPoint("TOPLEFT", 14, -38)
  setup.intro:SetWidth(442)
  setup.intro:SetJustifyH("LEFT")
  setup.rows = {}
  setup.group = CreateFrame("CheckButton", nil, setup, "UICheckButtonTemplate")
  setup.group:SetSize(24, 24)
  setup.group.label = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  setup.group.label:SetPoint("LEFT", setup.group, "RIGHT", 2, 0)
  setup.group.label:SetWidth(400)
  setup.group.label:SetJustifyH("LEFT")
  setup.group.label:SetText("Include group quests (elites that need 2 or more players). Off: the route skips them.")
  setup.dungeons = CreateFrame("CheckButton", nil, setup, "UICheckButtonTemplate")
  setup.dungeons:SetSize(24, 24)
  setup.dungeons.label = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  setup.dungeons.label:SetPoint("LEFT", setup.dungeons, "RIGHT", 2, 0)
  setup.dungeons.label:SetWidth(400)
  setup.dungeons.label:SetJustifyH("LEFT")
  setup.dungeons.label:SetText("Include dungeons. On: the route runs the dungeons whose quests and bosses give your best gear.")
  setup.start = Button(setup, "Start", 120, 24, function()
    setup.applied = true
    FP:ApplySetup(setup.choice, setup.group:GetChecked(), setup.dungeons:GetChecked())
    setup:Hide()
  end)
  setup.start:SetPoint("BOTTOMRIGHT", -14, 12)
  setup.foot = setup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  setup.foot:SetPoint("BOTTOMLEFT", 14, 18)
  setup.foot:SetWidth(300)
  setup.foot:SetJustifyH("LEFT")
  setup.foot:SetText("Change this any time with /fp setup.")
  local close = CreateFrame("Button", nil, setup, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  setup:SetScript("OnHide", function()
    -- Closed without Start on the first login: keep the recommended choices.
    if not setup.applied and FP.char and FP.char.setup == nil then FP:ApplySetup(setup.choice, setup.group:GetChecked(), setup.dungeons:GetChecked()) end
  end)
  setup:Hide()
end

local function SetupRow(i)
  local r = setup.rows[i]
  if not r then
    r = CreateFrame("CheckButton", nil, setup, "UICheckButtonTemplate")
    r:SetSize(24, 24)
    r.label = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("TOPLEFT", r, "TOPRIGHT", 2, -4)
    r.label:SetWidth(410)
    r.label:SetJustifyH("LEFT")
    r.desc = setup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.desc:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -2)
    r.desc:SetWidth(410)
    r.desc:SetJustifyH("LEFT")
    r:SetScript("OnClick", function(self)
      setup.choice = self.key
      for _, other in ipairs(setup.rows) do other:SetChecked(other.key == self.key) end
    end)
    setup.rows[i] = r
  end
  return r
end

function FP:ShowSetup()
  if not setup then BuildSetup() end
  setup.applied = false
  local name = (UnitName and self:Readable(UnitName("player"))) or "you"
  local race = UnitRace and select(1, UnitRace("player")) or ""
  setup.title:SetText("Forever Planner: set up " .. tostring(name))
  local chain = self.plan and self.plan.routeChain or {}
  local short = {}
  for k, n in ipairs(chain) do if k <= 6 then short[#short + 1] = n end end
  if #chain > 6 then short[#short + 1] = ("... %d zones in all"):format(#chain) end
  setup.intro:SetText(("%s %s, level %d. Your route: %s (%d steps), with the quests, dungeons and crafts for your spec's best gear. It ticks itself off from your quests.\n\nPick your spec. Talents follow it; the Plan window shows each pick."):format(
    tostring(self:Readable(race) or ""), tostring(self.className or self.class or ""), self:PlayerLevel(), table.concat(short, " > "),
    self.plan and #self.plan.route or 0))
  local y = -38 - setup.intro:GetStringHeight() - 10
  for _, r in ipairs(setup.rows) do r:Hide(); r.label:Hide(); r.desc:Hide() end
  local choices = self:SpecChoices()
  setup.choice = self:CurrentSpec()
  for i, c in ipairs(choices) do
    local r = SetupRow(i)
    r.key = c.key
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 14, y)
    r.label:SetText(c.name .. (c.recommended and (GOLD .. "  (recommended)|r") or ""))
    r.desc:SetText(c.desc or "")
    r:SetChecked(c.key == setup.choice)
    r:Show(); r.label:Show(); r.desc:Show()
    y = y - 8 - r.label:GetStringHeight() - r.desc:GetStringHeight() - 4
  end
  setup.group:ClearAllPoints()
  setup.group:SetPoint("TOPLEFT", 14, y - 6)
  setup.group:SetChecked(self.char.setup and self.char.setup.group or false)
  y = y - 6 - 28
  setup.dungeons:ClearAllPoints()
  setup.dungeons:SetPoint("TOPLEFT", 14, y)
  setup.dungeons:SetChecked(not (self.char.setup and self.char.setup.dungeons == false))
  y = y - 28
  setup:SetHeight(-y + 50)
  setup:Show()
end

------------------------------------------------------------------------
-- Gear plan beside the character window (C): one row per slot for a level band, with the item's
-- icon, where it comes from and whether you have it. Click a row for a waypoint to the step that
-- gets it. The character window's own slots get a tick (your plan's pick is on) or an hourglass
-- (an upgrade is planned), and their tooltips name the planned item.
------------------------------------------------------------------------
local SLOT_ORDER = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
  "Ring", "Trinket", "Weapon", "MainHand", "OffHand", "Ranged", "Wand", "Idol" }
local SLOT_RANK = {}
for i, s in ipairs(SLOT_ORDER) do SLOT_RANK[s] = i end
local SLOT_LABEL = { MainHand = "Main hand", OffHand = "Off hand", Weapon = "Two-hand", Back = "Back" }
-- Character window slot buttons for each inventory slot ID
local SLOT_BUTTONS = {
  [1] = "CharacterHeadSlot", [2] = "CharacterNeckSlot", [3] = "CharacterShoulderSlot", [15] = "CharacterBackSlot",
  [5] = "CharacterChestSlot", [9] = "CharacterWristSlot", [10] = "CharacterHandsSlot", [6] = "CharacterWaistSlot",
  [7] = "CharacterLegsSlot", [8] = "CharacterFeetSlot", [11] = "CharacterFinger0Slot", [12] = "CharacterFinger1Slot",
  [13] = "CharacterTrinket0Slot", [14] = "CharacterTrinket1Slot", [16] = "CharacterMainHandSlot",
  [17] = "CharacterSecondaryHandSlot", [18] = "CharacterRangedSlot",
}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROWS = 18

local panel, toggleTab, markers = nil, nil, {}

local function ItemIcon(id, name)
  local icon
  if id then
    if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
    if not icon and GetItemIcon then icon = GetItemIcon(id) end
  end
  if not icon and name and GetItemInfo then icon = select(10, GetItemInfo(name)) end
  return icon or QUESTION
end

local function ItemColour(id, name)
  local q
  if id and C_Item and C_Item.GetItemQualityByID then q = C_Item.GetItemQualityByID(id) end
  if not q and GetItemInfo then q = select(3, GetItemInfo(id or name)) end
  if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
    local c = ITEM_QUALITY_COLORS[q]
    return c.r, c.g, c.b
  end
  if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
  return 1, 1, 1
end

local function SourceIcon(src)
  if not src then return "" end
  if src:find("^Q:") then return "|TInterface\\GossipFrame\\AvailableQuestIcon:12:12|t " end
  if src:find("^Craft:") then return "|TInterface\\Icons\\Trade_Tailoring:12:12|t " end
  return "|TInterface\\Icons\\INV_Misc_Bone_Skull_01:12:12|t "   -- boss drop
end

-- The band shown: the one you're in, unless you've paged to another.
local function PanelBand()
  local gear = FP.plan and FP.plan.gear
  if not gear or #gear == 0 then return nil end
  local idx = panel and panel.bandIdx
  if not idx then
    local lvl = FP:PlayerLevel()
    idx = 1
    for i, g in ipairs(gear) do if lvl >= g.from and lvl <= g.to then idx = i end end
    if lvl > gear[#gear].to then idx = #gear end
  end
  return gear[idx], idx, #gear
end

local function SortedSlots(g)
  local list = {}
  for i, sl in ipairs(g.slots) do list[#list + 1] = { sl = sl, i = i } end
  table.sort(list, function(a, b)
    local ra, rb = SLOT_RANK[a.sl.slot] or 99, SLOT_RANK[b.sl.slot] or 99
    if ra ~= rb then return ra < rb end
    return a.i < b.i
  end)
  return list
end

local function RowState(sl)
  local st = FP:ItemState(sl.best)
  if st == "equipped" then return "worn" end
  if st == "bags" then return "bags" end
  if sl.alt and FP:ItemState(sl.alt) == "equipped" then return "alt" end
  return "need"
end

local ROW_H, PANEL_W = 31, 300
local SHORT = { ["Wailing Caverns"] = "WC", ["The Deadmines"] = "Deadmines", ["Shadowfang Keep"] = "SFK", ["Blackfathom Deeps"] = "BFD",
  ["Razorfen Kraul"] = "RFK", ["Razorfen Downs"] = "RFD", ["Scarlet Monastery"] = "SM", ["Ragefire Chasm"] = "RFC",
  ["Blackrock Spire"] = "BRS", ["Blackrock Depths"] = "BRD", ["Excavation Site"] = "Excavation Site", ["Zul'Farrak"] = "ZF" }

-- A short "where from" for the row; the tooltip has the full text.
local function ShortSource(src)
  if not src then return "" end
  local s = src:gsub("^Q: ", ""):gsub(" %(or the Auction House%)", ""):gsub("^Craft: ", "")
  for long, short in pairs(SHORT) do s = s:gsub(long, short) end
  return s
end

local function Border(f)
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.35, 0.35, 0.35, 0.9)
    if side == "TOP" or side == "BOTTOM" then
      t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
    else
      t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
    end
  end
end

local function MakeRow(i)
  local r = CreateFrame("Button", nil, panel.body)
  r:SetSize(PANEL_W - 16, ROW_H - 2)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:RegisterForClicks("LeftButtonUp")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  r.stripe = r:CreateTexture(nil, "BACKGROUND")
  r.stripe:SetAllPoints()
  r.stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ROW_H - 6, ROW_H - 6)
  r.icon:SetPoint("LEFT", 2, 0)
  r.state = r:CreateTexture(nil, "OVERLAY")
  r.state:SetSize(13, 13)
  r.state:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 3, -2)
  r.step = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.step:SetPoint("TOPRIGHT", -2, -3)
  r.step:SetJustifyH("RIGHT")
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -1)
  r.name:SetPoint("RIGHT", r.step, "LEFT", -4, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.info = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  r.info:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 1)
  r.info:SetPoint("RIGHT", -2, 0)
  r.info:SetJustifyH("LEFT")
  r.info:SetWordWrap(false)
  r:SetScript("OnClick", function(self)
    local sl = self.sl
    if not sl then return end
    local key = (self.state.which == "need" or self.state.which == "alt") and (sl.step or sl.altstep) or sl.step
    if key and FP:StepIndex(key) then
      FP:ShowStep(key, true)
      if FP.char and not FP.char.trackerShown then FP:ToggleTracker() end
      local s = FP.plan.route[FP:StepIndex(key)]
      FP:Print(("%s: step %s, %s (waypoint set)."):format(sl.best, s.num or key, s.title))
    elseif sl.src then
      FP:Print(("%s: %s"):format(sl.best, sl.src))
    end
  end)
  r:SetScript("OnEnter", function(self)
    local sl = self.sl
    if not (sl and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = sl.id and pcall(GameTooltip.SetItemByID, GameTooltip, sl.id)
    if not ok then GameTooltip:AddLine(sl.best, 1, 1, 1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Forever Planner: " .. (SLOT_LABEL[sl.slot] or sl.slot), 1, 0.82, 0)
    if sl.src then GameTooltip:AddLine(sl.src, 1, 1, 1, true) end
    local i = sl.step and FP:StepIndex(sl.step)
    if i then GameTooltip:AddLine(("Route step %s (level %d): %s"):format(FP.plan.route[i].num or sl.step, FP.plan.route[i].lvl or 0, FP.plan.route[i].title), 0.7, 0.7, 0.7, true) end
    if sl.alt then
      GameTooltip:AddLine(("Second choice: %s"):format(sl.alt), 0.6, 0.8, 1, true)
      if sl.altsrc then GameTooltip:AddLine(sl.altsrc, 0.6, 0.6, 0.6, true) end
    end
    GameTooltip:AddLine("Now: " .. FP:SlotNow(sl.slot), 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine("Click: waypoint to the step that gets it.", 0.4, 0.8, 1)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  return r
end

local function BuildGearPanel()
  local parent = _G.CharacterFrame or UIParent
  panel = CreateFrame("Frame", "ForeverPlannerGearPanel", parent)
  panel:SetSize(PANEL_W, 120)
  Bg(panel, 0.88)
  Border(panel)
  if parent ~= UIParent then
    panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
    panel:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
  else
    panel:SetPoint("CENTER", 300, 0)
    Movable(panel, "gearPanelPos")
  end
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", 10, -8)
  panel.title:SetText("Gear plan")
  panel.spec = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.spec:SetPoint("LEFT", panel.title, "RIGHT", 6, 0)
  panel.spec:SetPoint("RIGHT", panel, "TOPRIGHT", -28, -16)
  panel.spec:SetJustifyH("LEFT")
  panel.spec:SetWordWrap(false)
  panel.prev = Button(panel, "<", 22, 18, function()
    local _, idx = PanelBand(); if idx and idx > 1 then panel.bandIdx = idx - 1; FP:UpdateGearPanel() end
  end)
  panel.prev:SetPoint("TOPLEFT", 8, -30)
  panel.next = Button(panel, ">", 22, 18, function()
    local _, idx, n = PanelBand(); if idx and idx < n then panel.bandIdx = idx + 1; FP:UpdateGearPanel() end
  end)
  panel.next:SetPoint("TOPRIGHT", -8, -30)
  -- band name between the arrows; the band's full note shows on hover
  local bandBtn = CreateFrame("Button", nil, panel)
  bandBtn:SetPoint("LEFT", panel.prev, "RIGHT", 4, 0)
  bandBtn:SetPoint("RIGHT", panel.next, "LEFT", -4, 0)
  bandBtn:SetHeight(18)
  panel.band = bandBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  panel.band:SetAllPoints()
  panel.band:SetJustifyH("CENTER")
  panel.band:SetWordWrap(false)
  bandBtn:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.note) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.note, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  bandBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  panel.bandBtn = bandBtn
  panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.count:SetPoint("TOP", 0, -52)
  panel.body = CreateFrame("Frame", nil, panel)
  panel.body:SetPoint("TOPLEFT", 8, -68)
  panel.body:SetSize(PANEL_W - 16, ROWS * ROW_H)
  panel.rows = {}
  for i = 1, ROWS do panel.rows[i] = MakeRow(i) end
  panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.empty:SetPoint("TOPLEFT", 10, -70)
  panel.empty:SetWidth(PANEL_W - 20)
  panel.empty:SetJustifyH("LEFT")
  panel.foot = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.foot:SetPoint("BOTTOM", 0, 7)
  panel.foot:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t wearing   |TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t to get   Click a row for a waypoint")
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() FP.char.gearPanel = false; panel:Hide(); FP:UpdateGearToggle(); FP:UpdateSlotMarkers() end)
  panel:Hide()

  if parent ~= UIParent then
    -- A small button on the character window turns the panel on and off.
    toggleTab = CreateFrame("Button", "ForeverPlannerGearToggle", parent, "UIPanelButtonTemplate")
    toggleTab:SetSize(110, 20)
    toggleTab:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 2)
    toggleTab:SetScript("OnClick", function()
      FP.char.gearPanel = not panel:IsShown()
      if FP.char.gearPanel then panel:Show(); FP:UpdateGearPanel() else panel:Hide() end
      FP:UpdateGearToggle()
      FP:UpdateSlotMarkers()
    end)
    parent:HookScript("OnShow", function()
      if FP.char and FP.char.gearPanel ~= false and FP.plan then panel.bandIdx = nil; panel:Show(); FP:UpdateGearPanel() end
      FP:UpdateGearToggle()
      FP:UpdateSlotMarkers()
    end)
    parent:HookScript("OnHide", function() panel:Hide() end)
  end
end

function FP:UpdateGearToggle()
  if toggleTab then toggleTab:SetText(panel:IsShown() and "Hide gear plan" or "Show gear plan") end
end

function FP:UpdateGearPanel()
  if not panel or not panel:IsShown() then return end
  local g, idx, n = PanelBand()
  panel.spec:SetText(self.plan and self.plan.name or "")
  for _, r in ipairs(panel.rows) do r:Hide(); r.sl = nil end
  if not g then
    panel.band:SetText("")
    panel.count:SetText("")
    panel.empty:SetText("No gear plan for this character yet.")
    panel.empty:Show()
    panel.prev:Hide(); panel.next:Hide()
    panel:SetHeight(110)
    return
  end
  panel.empty:Hide()
  panel.prev:Show(); panel.next:Show()
  panel.prev:SetEnabled(idx > 1)
  panel.next:SetEnabled(idx < n)
  local lvl = self:PlayerLevel()
  local here = lvl >= g.from and lvl <= g.to
  local short = (g.from == g.to) and ("Level " .. g.from) or ("Levels %d-%d"):format(g.from, g.to)
  panel.band:SetText(short .. (here and "  |cff00ff00you're here|r" or ""))
  panel.bandBtn.note = (g.label and g.label ~= short) and g.label or nil
  local worn, rows = 0, 0
  for k, e in ipairs(SortedSlots(g)) do
    local r = panel.rows[k]
    if not r then break end
    local sl = e.sl
    rows = k
    r.sl = sl
    r.icon:SetTexture(ItemIcon(sl.id, sl.best))
    local cr, cg, cb = ItemColour(sl.id, sl.best)
    r.name:SetText(sl.best)
    r.name:SetTextColor(cr, cg, cb)
    local st = RowState(sl)
    r.state.which = st
    local label = GREY .. (SLOT_LABEL[sl.slot] or sl.slot) .. "|r  "
    local i = sl.step and self:StepIndex(sl.step)
    if st == "worn" then
      worn = worn + 1
      r.state:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
      r.info:SetText(label .. "|cff00ff00Wearing it|r")
      r.step:SetText("")
      r.icon:SetDesaturated(false)
    else
      r.state:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
      if st == "bags" then
        r.info:SetText(label .. "|cffffd100In your bags: equip it|r")
        r.step:SetText("")
      else
        r.info:SetText(label .. (st == "alt" and "|cff9999ff2nd choice on.|r " or "") .. ShortSource(sl.src))
        r.step:SetText(i and ("step %s"):format(self.plan.route[i].num or sl.step) or "")
      end
      r.icon:SetDesaturated(st ~= "bags")
    end
    r:Show()
  end
  panel.count:SetText(("Wearing %d of %d planned items"):format(worn, #g.slots))
  panel:SetHeight(68 + rows * ROW_H + 24)
  self:UpdateSlotMarkers()
end

-- A small hourglass on the character window's slots where your plan has an upgrade for the band you're in.
function FP:UpdateSlotMarkers()
  if not (_G.CharacterFrame and self.plan and self.plan.gear) then return end
  local g = self:GearBracket()
  local want = {}
  if g then
    local used = {}
    for _, e in ipairs(SortedSlots(g)) do
      local ids = FP.SLOT_IDS[e.sl.slot] or {}
      local inv = ids[1]
      if #ids > 1 and e.sl.slot ~= "Weapon" then
        for _, id in ipairs(ids) do if not used[id] then inv = id; break end end
      end
      if inv then used[inv] = true; want[inv] = e.sl end
    end
  end
  for inv, bname in pairs(SLOT_BUTTONS) do
    local b = _G[bname]
    if b then
      local m = markers[inv]
      if not m then
        m = b:CreateTexture(nil, "OVERLAY", nil, 7)
        m:SetSize(13, 13)
        m:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        m:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        markers[inv] = m
      end
      local sl = want[inv]
      if sl and self.char.gearPanel ~= false and RowState(sl) ~= "worn" then m:Show() else m:Hide() end
    end
  end
end

-- Hovering a slot on the character window: name the planned item for it.
local tooltipHooked = false
local function HookSlotTooltips()
  if tooltipHooked or not (GameTooltip and hooksecurefunc) then return end
  tooltipHooked = true
  hooksecurefunc(GameTooltip, "SetInventoryItem", function(tt, unit, inv)
    if unit ~= "player" or not (FP.plan and FP.plan.gear) then return end
    local g = FP:GearBracket()
    if not g then return end
    local slotName
    for name, ids in pairs(FP.SLOT_IDS) do
      for _, id in ipairs(ids) do if id == inv then slotName = slotName or name end end
    end
    for _, sl in ipairs(g.slots) do
      local ids = FP.SLOT_IDS[sl.slot] or {}
      local match = false
      for _, id in ipairs(ids) do if id == inv then match = true end end
      if match then
        if FP:ItemState(sl.best) == "equipped" then
          tt:AddLine("Forever Planner: " .. sl.best .. " is your plan's pick", 0, 1, 0)
        else
          tt:AddLine("Forever Planner: plan wants " .. sl.best, 1, 0.82, 0)
          if sl.src then tt:AddLine(sl.src, 0.8, 0.8, 0.8, true) end
        end
        tt:Show()
        return
      end
    end
  end)
end

local gearEvents = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP" }) do
  gearEvents:RegisterEvent(e)
end
gearEvents:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if C_Timer and C_Timer.After then
      C_Timer.After(1, function() if not panel then BuildGearPanel() end HookSlotTooltips() end)
    else
      BuildGearPanel(); HookSlotTooltips()
    end
    return
  end
  if panel and panel:IsShown() then
    if event == "PLAYER_LEVEL_UP" then panel.bandIdx = nil end
    FP:UpdateGearPanel()
  elseif _G.CharacterFrame and _G.CharacterFrame:IsShown() then
    FP:UpdateSlotMarkers()
  end
end)

-- /fp gear: open the character window with the gear plan beside it.
function FP:ShowGearPanel()
  if not panel then BuildGearPanel() end
  self.char.gearPanel = true
  if _G.CharacterFrame then
    if not _G.CharacterFrame:IsShown() then
      if ToggleCharacter then ToggleCharacter("PaperDollFrame") else ShowUIPanel(_G.CharacterFrame) end
    end
  end
  panel.bandIdx = nil
  panel:Show()
  self:UpdateGearPanel()
  self:UpdateGearToggle()
end

function FP:GearDebug()
  self:Print(("Character window: %s. Gear panel: %s. Plan bands: %d."):format(_G.CharacterFrame and "found" or "not found",
    panel and (panel:IsShown() and "shown" or "hidden") or "not built", self.plan and self.plan.gear and #self.plan.gear or 0))
  local missing = {}
  for _, n in pairs(SLOT_BUTTONS) do if not _G[n] then missing[#missing + 1] = n end end
  self:Print(#missing == 0 and "All character slot buttons found." or ("Slot buttons not found: " .. table.concat(missing, ", ")))
end
