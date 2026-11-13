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

-- Depth-first search of the window for a visible frame showing the talent's icon.
-- Prefers buttons (the clickable talent) over plain frames.
local function FindByIcon(root, icon)
  if icon == nil then return nil end
  local best
  local function walk(f, depth)
    if depth > 9 or not Visible(f) then return end
    if f.GetRegions then
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
  if info then
    where = ("\n%s tree, row %s, column %s"):format(info.tabName or ("tree " .. info.tab), tostring(info.tier or "?"), tostring(info.column or "?"))
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
  local b = FindNamedButton(frameName, info) or FindByIcon(frame, info.icon)
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
  self:Print(("Talents: version %s, API points %s, worked-out points %s, ranks read: %s"):format(
    self.version, tostring(raw), tostring(self:UnspentTalentPoints()), self.talentRanks and "yes" or "no"))
  local nxt = self:NextTalentInfo()
  if nxt then
    local i = nxt.info
    self:Print(("Next pick: %s; %s"):format(nxt.text, i and ("tree %s (%s), row %s, column %s, icon %s"):format(
      tostring(i.tab), tostring(i.tabName), tostring(i.tier), tostring(i.column), tostring(i.icon)) or "not found in the talent list"))
  end
  local names = {}
  for _, f in ipairs(self.talentWindows) do names[#names + 1] = (NameOf(f) or "?") .. (Visible(f) and " (open)" or "") end
  self:Print("Talent windows: " .. (#names > 0 and table.concat(names, ", ") or "none found"))
  local frame = OpenTalentFrame()
  if frame and nxt and nxt.info then
    local b = FindByIcon(frame, nxt.info.icon)
    self:Print("Icon match on the open window: " .. (b and (NameOf(b) or "unnamed frame") or "none"))
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
