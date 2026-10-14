-- Settings panel (spec §11). Built lazily on /fcg config from basic frame
-- widgets only; no protected actions, so it is safe to open in combat.
-- Every switch goes through Config.Store, the single validation path.
-- Widget templates are client details: if one is missing the panel is not
-- built and /fcg status keeps working (integration not verified in game).
local _, ns = ...

local Normalize = ns.Core.Normalize
local Commands = ns.UI.Commands

local Panel = {}
ns.UI.Panel = Panel

local WIDTH, HEIGHT = 460, 520

local function label(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT")
  fs:SetWidth(WIDTH - 40)
  fs:SetText(text)
  return fs
end

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- Checkbox with its explanation underneath (text, not colour, carries state).
local function toggle(parent, anchor, text, help, getter, setter)
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
  local title = label(check, text, "GameFontNormal")
  title:SetPoint("LEFT", check, "RIGHT", 2, 0)
  title:SetWidth(WIDTH - 80)
  local note = label(parent, help)
  note:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 30, 2)
  note:SetWidth(WIDTH - 80)
  check:SetScript("OnClick", function(self)
    setter(self:GetChecked() and true or false)
    Panel.Refresh()
  end)
  check.Sync = function()
    check:SetChecked(getter())
  end
  return check, note
end

function Panel.Build(runtime)
  local L = ns.L
  local store, db = runtime.store, runtime.db
  local frame = CreateFrame("Frame", "ForeverChatGuardPanel", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("DIALOG")
  frame:Hide()
  if type(UISpecialFrames) == "table" then
    -- Escape closes the panel.
    table.insert(UISpecialFrames, "ForeverChatGuardPanel")
  end

  local title = label(frame, L.ADDON_TITLE, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -32)

  local status = label(frame, "")
  status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  frame.status = status

  local checks = {}
  local anchor = status
  local items = {
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
    { L.PANEL_TERMS, L.PANEL_TERMS_HELP .. " " .. L.TERM_NOTE,
      function() return db.customTerms.enabled end,
      function(v) store:SetTermsEnabled(v) end },
  }
  for index = 1, #items do
    local item = items[index]
    local check, note = toggle(frame, anchor, item[1], item[2], item[3], item[4])
    checks[#checks + 1] = check
    anchor = note
  end
  frame.checks = checks

  local termBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  termBox:SetSize(250, 22)
  termBox:SetAutoFocus(false)
  termBox:SetMaxBytes(ns.Core.Defaults.LIMITS.maxRuleBytes + 1)
  termBox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -24, -12)
  local addTerm = button(frame, L.PANEL_TERM_ADD, 140, function()
    Commands.Execute(runtime, "term add " .. (termBox:GetText() or ""), ns.Print)
    termBox:SetText("")
    termBox:ClearFocus()
    Panel.Refresh()
  end)
  addTerm:SetPoint("LEFT", termBox, "RIGHT", 10, 0)
  termBox:SetScript("OnEnterPressed", function() addTerm:Click() end)
  termBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local channelsTitle = label(frame, L.PANEL_CHANNELS, "GameFontNormal")
  channelsTitle:SetPoint("TOPLEFT", termBox, "BOTTOMLEFT", -4, -12)
  local channels = label(frame, "")
  channels:SetPoint("TOPLEFT", channelsTitle, "BOTTOMLEFT", 0, -4)
  frame.channels = channels

  local details = label(frame, "")
  details:SetPoint("TOPLEFT", channels, "BOTTOMLEFT", 0, -10)
  frame.details = details

  local quarantine = button(frame, L.PANEL_QUARANTINE, 140, function()
    if ns.UI.Quarantine then ns.UI.Quarantine.Show(runtime) end
  end)
  quarantine:SetPoint("BOTTOMLEFT", 16, 14)
  local close = button(frame, L.PANEL_CLOSE, 100, function() frame:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -16, 14)

  frame:SetScript("OnShow", function() Panel.Refresh() end)
  runtime.store:OnChange(function()
    if frame:IsShown() then Panel.Refresh() end
  end)
  Panel.frame = frame
  Panel.runtime = runtime
  return frame
end

function Panel.Refresh()
  local frame, runtime = Panel.frame, Panel.runtime
  if not frame then return end
  local L = ns.L
  frame.status:SetText(table.concat(Commands.StatusLines(runtime), "\n"))
  for index = 1, #frame.checks do
    frame.checks[index].Sync()
  end
  local lines = {}
  for index, item in ipairs(runtime.adapter:ChannelList()) do
    lines[#lines + 1] = string.format("%d: %s%s", index,
      Normalize.EscapeForDisplay(item.label or item.key), item.selected and " [x]" or "")
  end
  lines[#lines + 1] = "/fcg channel add <n>  /fcg channel remove <n>"
  frame.channels:SetText(table.concat(lines, "\n"))
  local terms = {}
  for _, entry in ipairs(runtime.db.customTerms.list) do
    terms[#terms + 1] = Normalize.EscapeForDisplay(entry.text)
  end
  local allow, block = {}, {}
  for key in pairs(runtime.db.allowlist) do allow[#allow + 1] = Normalize.EscapeForDisplay(key) end
  for key in pairs(runtime.db.blocklist) do block[#block + 1] = Normalize.EscapeForDisplay(key) end
  table.sort(allow)
  table.sort(block)
  frame.details:SetText(string.format("%s: %s\n%s: %s\n%s: %s",
    L.PANEL_TERMS, #terms > 0 and table.concat(terms, ", ") or L.NONE,
    L.LIST_ALLOW, #allow > 0 and table.concat(allow, ", ") or L.NONE,
    L.LIST_BLOCK, #block > 0 and table.concat(block, ", ") or L.NONE))
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
