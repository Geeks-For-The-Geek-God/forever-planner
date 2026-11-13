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
  if st == "done" then tag = tag .. " " .. OK elseif st == "skipped" then tag = tag .. GREY .. " skipped|r" end
  local zone = s.map and (FP.ZONE[s.map] or s.map) or ""
  local coord = (s.x and s.y) and (" %d, %d"):format(s.x, s.y) or ""
  tracker.head:SetText(("Step %s/%d  %s%s|r%s  lvl %d%s"):format(s.key, #route, WHITE, zone, coord, s.lvl or 0, tag))
  place(tracker.head)

  tracker.title:SetText(s.title)
  place(tracker.title, 3)

  local n = 0
  for _, o in ipairs(s.q or {}) do
    n = n + 1
    local fs = Line(n)
    local done = self:ObjDone(o)
    local text = self:ObjText(o)
    if done then
      fs:SetText(OK .. " " .. GREY .. text .. "|r")
    else
      local inLog = self.log[FP.Norm(o.q)]
      local icon = (inLog and inLog.complete) and WAIT or DOT
      fs:SetText(icon .. " " .. text)
    end
    place(fs, 2)
  end

  local nextText = self:NextAction(s)
  if nextText and not viewing then
    tracker.nextLine:SetText("Next: " .. WHITE .. nextText .. "|r")
    place(tracker.nextLine, 5)
  elseif (s.q == nil or #s.q == 0) and not viewing and st == "open" then
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

  if s.note and s.note ~= "" then
    tracker.note:SetText(s.note)
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
    local req, reqDone = FP:StepCounts(s)
    local count = req > 0 and ("  " .. GREY .. reqDone .. "/" .. req .. "|r") or ""
    local name = (i == vi) and (GOLD .. "> " .. s.title .. "|r") or ((st == "open") and s.title or (GREY .. s.title .. "|r"))
    list[#list + 1] = {
      text = ("%s  %s. %s  %s(%d)|r%s"):format(icon, s.key, name, GREY, s.lvl or 0, count),
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
    return ("  %s[step %s, lvl %d]|r%s"):format(GOLD, key, s.lvl or 0, passed)
  end
  local function goStep(key)
    if not FP:StepIndex(key) then return nil end
    return function() FP:ShowStep(key, true) end
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
-- Talent screen: glow on the next planned talent, a note saying what and where,
-- and a glow on the tree's tab when the pick is in another tree.
-- Purely visual: you still click the talent yourself.
------------------------------------------------------------------------
local TALENT_FRAMES = { "TalentFrame", "PlayerTalentFrame" }
local glow, tabGlow, hint, watcher

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
    if a then
      a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7)
    end
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

local function OpenTalentFrame()
  for _, name in ipairs(TALENT_FRAMES) do
    local f = _G[name]
    if f and f.IsShown and f:IsShown() then return f, name end
  end
end

local function SelectedTab(frame, name)
  if PanelTemplates_GetSelectedTab then
    local ok, t = pcall(PanelTemplates_GetSelectedTab, frame)
    if ok and type(t) == "number" then return t end
  end
  return frame.selectedTab or frame.currentSelectedTab
end

local function SameIcon(a, b)
  if a == nil or b == nil then return true end -- can't compare: trust the index
  return tostring(a):lower() == tostring(b):lower()
end

-- Finds the talent button for the pick on the currently shown tree, if any.
local function FindButton(frameName, info)
  for i = 1, 100 do
    local b = _G[frameName .. "Talent" .. i]
    if not b then break end
    if b.IsShown and b:IsShown() and b.GetID and b:GetID() == info.index then
      local icon = _G[frameName .. "Talent" .. i .. "IconTexture"]
      if SameIcon(icon and icon.GetTexture and icon:GetTexture(), info.icon) then return b end
    end
  end
end

function FP:UpdateTalentGlow()
  local frame, frameName = OpenTalentFrame()
  if not frame then HideGlow(glow); HideGlow(tabGlow); if hint then hint:Hide() end; return end
  if not (self.plan and self.char) or self.char.talentGlow == false then
    HideGlow(glow); HideGlow(tabGlow); if hint then hint:Hide() end; return
  end
  if not glow then glow = MakeGlow(frame); tabGlow = MakeGlow(frame) end
  if not hint then
    hint = CreateFrame("Frame", nil, frame)
    hint:SetSize(320, 34)
    Bg(hint, 0.75)
    hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint.text:SetPoint("TOPLEFT", 6, -4)
    hint.text:SetWidth(308)
    hint.text:SetJustifyH("LEFT")
  end
  hint:SetParent(frame)
  hint:ClearAllPoints()
  hint:SetPoint("BOTTOM", frame, "TOP", 0, 2)

  local pts = self:UnspentTalentPoints()
  local nxt = self:NextTalentInfo()
  if not nxt then
    hint.text:SetText(GOLD .. "Forever Planner:|r every planned talent is taken.")
    hint:Show(); HideGlow(glow); HideGlow(tabGlow)
    return
  end
  local info = nxt.info
  local where = ""
  if info then
    where = (" - %s tree, row %s, column %s"):format(info.tabName or ("tree " .. info.tab), tostring(info.tier or "?"), tostring(info.column or "?"))
  end
  local lead = (pts and pts > 0) and ("Spend your point: " .. WHITE .. nxt.text .. "|r") or ("Next pick (level " .. nxt.level .. "): " .. WHITE .. nxt.text .. "|r")
  hint.text:SetText(GOLD .. "Forever Planner|r  " .. lead .. where)
  hint:SetHeight(hint.text:GetStringHeight() + 10)
  hint:Show()

  HideGlow(glow); HideGlow(tabGlow)
  if not (info and pts and pts > 0) then return end
  local shownTab = SelectedTab(frame, frameName)
  if shownTab == nil or shownTab == info.tab then
    local b = FindButton(frameName, info)
    if b then ShowGlowOn(glow, b, (b.GetWidth and b:GetWidth() or 37) * 1.9) end
  end
  if shownTab ~= nil and shownTab ~= info.tab then
    local tabButton = _G[frameName .. "Tab" .. info.tab]
    if tabButton then ShowGlowOn(tabGlow, tabButton, (tabButton.GetWidth and tabButton:GetWidth() or 80) * 1.3) end
  end
end

-- Watch for the talent screen opening, switching tree or changing, without touching Blizzard's code.
watcher = CreateFrame("Frame")
local elapsed, wasOpen, lastKey = 0, false, nil
watcher:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + (dt or 0)
  if elapsed < 0.2 then return end
  elapsed = 0
  local frame, frameName = OpenTalentFrame()
  local key = frame and (frameName .. ":" .. tostring(SelectedTab(frame, frameName)) .. ":" .. tostring(FP:UnspentTalentPoints()) .. ":" .. tostring(FP.talentSpent))
  if (frame ~= nil) ~= wasOpen or key ~= lastKey then
    wasOpen, lastKey = frame ~= nil, key
    if frame then FP:ScanTalents() end
    FP:UpdateTalentGlow()
  end
end)
FP.talentWatcher = watcher
