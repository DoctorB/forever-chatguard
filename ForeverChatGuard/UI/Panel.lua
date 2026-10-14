-- Settings panel (spec §11). Built lazily on /fcg config from basic frame
-- widgets only; no protected actions, so it is safe to open in combat.
-- Every switch goes through Config.Store, the single validation path.
--
-- Layout: one left column at PAD; every element is placed by Layout() with
-- a running vertical cursor using the measured height of its text, so
-- wrapped help lines can never overlap the next row or leave the frame.
local _, ns = ...

local Normalize = ns.Core.Normalize
local Commands = ns.UI.Commands

local Panel = {}
ns.UI.Panel = Panel

local WIDTH = 500
local PAD = 20
local TOP = 34                 -- below the template title bar
local BOTTOM = 52              -- room for the bottom buttons
local CONTENT = WIDTH - 2 * PAD
local CHECK = 26               -- checkbox size
local INDENT = CHECK + 4       -- label/help column next to a checkbox
local MAX_CHANNELS = 12
local CHANNEL_COLUMNS = 2

local function fontString(parent, template, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetWidth(width)
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  if fs.SetSpacing then fs:SetSpacing(2) end
  return fs
end

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function place(region, frame, x, y)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
end

local function textHeight(fs)
  local text = fs:GetText()
  if not text or text == "" then return 0 end
  return math.ceil(fs:GetStringHeight())
end

local function displayList(keys)
  local L = ns.L
  local shown = {}
  for index = 1, #keys do
    shown[index] = Normalize.EscapeForDisplay(keys[index])
  end
  return #shown > 0 and table.concat(shown, ", ") or L.NONE
end

local function sortedKeys(map)
  local keys = {}
  for key in pairs(map) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

function Panel.Build(runtime)
  local L = ns.L
  local store, db = runtime.store, runtime.db
  local frame = CreateFrame("Frame", "ForeverChatGuardPanel", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, 600)
  frame:SetPoint("CENTER")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("DIALOG")
  frame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "ForeverChatGuardPanel") -- Escape closes
  end
  if frame.TitleText then
    frame.TitleText:SetText(L.ADDON_TITLE)
  else
    local title = fontString(frame, "GameFontNormal", CONTENT)
    title:SetPoint("TOP", 0, -6)
    title:SetJustifyH("CENTER")
    title:SetText(L.ADDON_TITLE)
  end

  local w = {}
  w.statusHeader = fontString(frame, "GameFontNormal", CONTENT)
  w.statusHeader:SetText(L.PANEL_STATUS)
  w.status = fontString(frame, "GameFontHighlightSmall", CONTENT)

  w.rulesHeader = fontString(frame, "GameFontNormal", CONTENT)
  w.rulesHeader:SetText(L.PANEL_RULES)

  local toggles = {
    { L.PANEL_ENABLED, L.PANEL_ENABLED_HELP,
      function() return db.enabled end,
      function(v) if v then runtime.engine:ResetBreaker() end store:SetEnabled(v) end },
    { L.PANEL_FILTER, L.PANEL_FILTER_HELP,
      function() return db.mode == "filter" end,
      function(v)
        if v and not runtime.adapter.caps.filter then
          ns.Print(L.STATUS_FILTER_NEEDS_CAPABILITY)
          return
        end
        store:SetMode(v and "filter" or "observe")
      end },
    { L.PANEL_DUP, L.PANEL_DUP_HELP,
      function() return db.duplicate.enabled end,
      function(v) store:SetDuplicate(v, nil) end },
    { L.PANEL_FLOOD, L.PANEL_FLOOD_HELP,
      function() return db.flood.enabled end,
      function(v) store:SetFlood(v, nil, nil) end },
    { L.PANEL_TERMS, L.PANEL_TERMS_HELP,
      function() return db.customTerms.enabled end,
      function(v) store:SetTermsEnabled(v) end },
  }
  w.toggles = {}
  for index = 1, #toggles do
    local spec = toggles[index]
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(CHECK, CHECK)
    local label = fontString(frame, "GameFontNormal", CONTENT - INDENT)
    label:SetText(spec[1])
    local help = fontString(frame, "GameFontHighlightSmall", CONTENT - INDENT)
    help:SetText(spec[2])
    check:SetScript("OnClick", function(self)
      spec[4](self:GetChecked() and true or false)
      Panel.Refresh()
    end)
    w.toggles[index] = { check = check, label = label, help = help, get = spec[3] }
  end

  w.termsHeader = fontString(frame, "GameFontNormal", CONTENT)
  w.termsHeader:SetText(L.PANEL_MY_TERMS)
  w.termsNote = fontString(frame, "GameFontHighlightSmall", CONTENT)
  w.termsNote:SetText(L.TERM_NOTE)
  local addWidth = 120
  w.termBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  w.termBox:SetSize(CONTENT - addWidth - 16, 22)
  w.termBox:SetAutoFocus(false)
  w.termBox:SetMaxBytes(ns.Core.Defaults.LIMITS.maxRuleBytes + 1)
  w.addTerm = button(frame, L.PANEL_TERM_ADD, addWidth, function()
    Commands.Execute(runtime, "term add " .. (w.termBox:GetText() or ""), ns.Print)
    w.termBox:SetText("")
    w.termBox:ClearFocus()
    Panel.Refresh()
  end)
  w.termBox:SetScript("OnEnterPressed", function() w.addTerm:Click() end)
  w.termBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  w.termsList = fontString(frame, "GameFontHighlightSmall", CONTENT)

  w.channelsHeader = fontString(frame, "GameFontNormal", CONTENT)
  w.channelsHeader:SetText(L.PANEL_CHANNELS)
  w.channelsHint = fontString(frame, "GameFontHighlightSmall", CONTENT)
  w.channelsHint:SetText(L.PANEL_CHANNELS_HINT)
  w.channels = {}
  local columnWidth = CONTENT / CHANNEL_COLUMNS
  for index = 1, MAX_CHANNELS do
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(CHECK, CHECK)
    local label = fontString(frame, "GameFontHighlight", columnWidth - INDENT - 6)
    if label.SetWordWrap then label:SetWordWrap(false) end
    check:SetScript("OnClick", function(self)
      local item = self.item
      if not item then return end
      if self:GetChecked() then
        store:SelectChannel(item.key, item.label)
      else
        store:UnselectChannel(item.key)
      end
      Panel.Refresh()
    end)
    w.channels[index] = { check = check, label = label }
  end

  w.authorsHeader = fontString(frame, "GameFontNormal", CONTENT)
  w.authorsHeader:SetText(L.PANEL_AUTHORS)
  w.authors = fontString(frame, "GameFontHighlightSmall", CONTENT)

  w.quarantine = button(frame, L.PANEL_QUARANTINE, 140, function()
    if ns.UI.Quarantine then ns.UI.Quarantine.Show(runtime) end
  end)
  w.quarantine:SetPoint("BOTTOMLEFT", PAD - 4, 16)
  w.close = button(frame, L.PANEL_CLOSE, 110, function() frame:Hide() end)
  w.close:SetPoint("BOTTOMRIGHT", -(PAD - 4), 16)

  frame.widgets = w
  frame:SetScript("OnShow", function() Panel.Refresh() end)
  -- Never keep keyboard focus once the panel is closed.
  frame:SetScript("OnHide", function() w.termBox:ClearFocus() end)
  store:OnChange(function()
    if frame:IsShown() then Panel.Refresh() end
  end)
  Panel.frame = frame
  Panel.runtime = runtime
  return frame
end

-- Positions every element from the top with a running cursor.
local function layout(frame)
  local w = frame.widgets
  local y = TOP + 6
  local function text(fs, x, gapAfter)
    place(fs, frame, x, y)
    y = y + textHeight(fs) + (gapAfter or 0)
  end

  text(w.statusHeader, PAD, 4)
  text(w.status, PAD, 14)

  text(w.rulesHeader, PAD, 6)
  for index = 1, #w.toggles do
    local row = w.toggles[index]
    place(row.check, frame, PAD - 4, y - 4)
    place(row.label, frame, PAD + INDENT, y)
    y = y + textHeight(row.label) + 2
    place(row.help, frame, PAD + INDENT, y)
    y = y + math.max(textHeight(row.help), CHECK - textHeight(row.label) - 6) + 10
  end
  y = y + 4

  text(w.termsHeader, PAD, 4)
  text(w.termsNote, PAD, 6)
  place(w.termBox, frame, PAD + 6, y) -- the template draws its border outside
  w.addTerm:ClearAllPoints()
  w.addTerm:SetPoint("TOPRIGHT", frame, "TOPLEFT", WIDTH - PAD, -y)
  y = y + 28
  text(w.termsList, PAD, 14)

  text(w.channelsHeader, PAD, 4)
  text(w.channelsHint, PAD, 6)
  local columnWidth = CONTENT / CHANNEL_COLUMNS
  local shown = 0
  for index = 1, #w.channels do
    local slot = w.channels[index]
    if slot.item then
      local column = shown % CHANNEL_COLUMNS
      local rowY = y + math.floor(shown / CHANNEL_COLUMNS) * CHECK
      place(slot.check, frame, PAD - 4 + column * columnWidth, rowY)
      place(slot.label, frame, PAD + INDENT + column * columnWidth, rowY + 6)
      shown = shown + 1
    end
  end
  y = y + math.ceil(shown / CHANNEL_COLUMNS) * CHECK + 12

  text(w.authorsHeader, PAD, 4)
  text(w.authors, PAD, 0)

  frame:SetHeight(y + BOTTOM)
end

function Panel.Refresh()
  local frame, runtime = Panel.frame, Panel.runtime
  if not frame then return end
  local L = ns.L
  local w = frame.widgets
  local db = runtime.db

  w.status:SetText(table.concat(Commands.StatusLines(runtime, { compact = true }), "\n"))
  for index = 1, #w.toggles do
    local row = w.toggles[index]
    row.check:SetChecked(row.get() and true or false)
  end

  local terms = {}
  for _, entry in ipairs(db.customTerms.list) do
    terms[#terms + 1] = entry.text
  end
  w.termsList:SetText(string.format(L.PANEL_TERMS_LIST, displayList(terms)))

  local items = runtime.adapter:ChannelList()
  for index = 1, #w.channels do
    local slot, item = w.channels[index], items[index]
    slot.item = item
    slot.check.item = item
    if item then
      slot.label:SetText(Normalize.EscapeForDisplay(item.label or item.key))
      slot.check:SetChecked(item.selected and true or false)
      slot.check:Show()
      slot.label:Show()
    else
      slot.check:Hide()
      slot.label:Hide()
    end
  end

  w.authors:SetText(string.format(L.PANEL_ALLOWED, displayList(sortedKeys(db.allowlist)))
    .. "\n" .. string.format(L.PANEL_BLOCKED, displayList(sortedKeys(db.blocklist))))

  layout(frame)
end

function Panel.Toggle(runtime)
  if not Panel.frame then
    local ok = pcall(Panel.Build, runtime)
    if not ok then
      -- Missing widget template on this client: fall back to text output.
      Panel.frame = nil
      Commands.Execute(runtime, "status", ns.Print)
      return
    end
  end
  if Panel.frame:IsShown() then
    Panel.frame:Hide()
  else
    Panel.frame:Show()
  end
end
