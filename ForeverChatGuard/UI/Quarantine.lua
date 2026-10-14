-- Quarantine window (spec §4, §11): local, session-only, never re-sends text
-- to any chat channel. Chat text is rendered with every "|" escaped, so
-- colours, links and textures from other players are shown as plain text.
local _, ns = ...

local Commands = ns.UI.Commands

local Quarantine = {}
ns.UI.Quarantine = Quarantine

local ROWS = 8
local WIDTH = 640
local PAD = 20
local TOP = 34
local ROW_HEIGHT = 50
local BUTTON_WIDTH = 120
local TEXT_WIDTH = WIDTH - 2 * PAD - BUTTON_WIDTH - 16

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function build(runtime)
  local L = ns.L
  local frame = CreateFrame("Frame", "ForeverChatGuardQuarantine", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, TOP + 12 + ROWS * ROW_HEIGHT + 52)
  frame:SetPoint("CENTER", 40, -40)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("DIALOG")
  frame:Hide()
  if type(UISpecialFrames) == "table" then
    table.insert(UISpecialFrames, "ForeverChatGuardQuarantine")
  end
  if frame.TitleText then
    frame.TitleText:SetText(L.ADDON_TITLE .. " - " .. L.PANEL_QUARANTINE)
  end

  local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("TOP", 0, -(TOP + 40))
  empty:SetWidth(WIDTH - 2 * PAD)
  empty:SetText(L.QUARANTINE_EMPTY)
  frame.empty = empty

  frame.offset = 0
  frame.rows = {}
  for index = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 2 * PAD, ROW_HEIGHT - 4)
    row:SetPoint("TOPLEFT", PAD, -(TOP + 8 + (index - 1) * ROW_HEIGHT))
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT")
    text:SetWidth(TEXT_WIDTH)
    text:SetHeight(ROW_HEIGHT - 6)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    if text.SetWordWrap then text:SetWordWrap(true) end
    if text.SetMaxLines then text:SetMaxLines(3) end
    row.text = text
    local show = button(row, L.PANEL_SHOW_TEXT, BUTTON_WIDTH, function()
      if row.entry then
        Commands.Execute(runtime, "show " .. row.entry.seq, ns.Print)
      end
    end)
    show:SetPoint("TOPRIGHT", 0, 0)
    local allow = button(row, L.PANEL_ALLOW_AUTHOR, BUTTON_WIDTH, function()
      if row.entry then
        Commands.Execute(runtime, "allowentry " .. row.entry.seq, ns.Print)
        Quarantine.Refresh()
      end
    end)
    allow:SetPoint("TOPRIGHT", show, "BOTTOMRIGHT", 0, -2)
    frame.rows[index] = row
  end

  frame.prev = button(frame, L.PANEL_PREV, 110, function()
    frame.offset = math.max(0, frame.offset - ROWS)
    Quarantine.Refresh()
  end)
  frame.prev:SetPoint("BOTTOMLEFT", PAD - 4, 16)
  frame.next = button(frame, L.PANEL_NEXT, 110, function()
    frame.offset = frame.offset + ROWS
    Quarantine.Refresh()
  end)
  frame.next:SetPoint("LEFT", frame.prev, "RIGHT", 8, 0)
  local page = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page:SetWidth(180)
  page:SetJustifyH("LEFT")
  page:SetPoint("LEFT", frame.next, "RIGHT", 12, 0)
  frame.page = page
  local close = button(frame, L.PANEL_CLOSE, 110, function() frame:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -(PAD - 4), 16)

  frame:SetScript("OnShow", function() Quarantine.Refresh() end)
  Quarantine.frame, Quarantine.runtime = frame, runtime
  return frame
end

function Quarantine.Refresh()
  local frame, runtime = Quarantine.frame, Quarantine.runtime
  if not frame then return end
  local L = ns.L
  local entries = runtime.engine.quarantine:List(runtime.engine.clock())
  local total = #entries
  if frame.offset >= total then
    frame.offset = math.max(0, total - (total - 1) % ROWS - 1)
  end
  for index = 1, ROWS do
    local row = frame.rows[index]
    local entry = entries[frame.offset + index]
    row.entry = entry
    if entry then
      row.text:SetText(Commands.FormatEntry(entry, false))
      row:Show()
    else
      row:Hide()
    end
  end
  if total == 0 then
    frame.empty:Show()
    frame.page:SetText("")
  else
    frame.empty:Hide()
    frame.page:SetText(string.format(L.QUARANTINE_PAGE, frame.offset + 1,
      math.min(frame.offset + ROWS, total), total))
  end
  frame.prev:SetEnabled(frame.offset > 0)
  frame.next:SetEnabled(frame.offset + ROWS < total)
end

-- Returns true when the window could be shown on this client.
function Quarantine.Show(runtime)
  if not Quarantine.frame then
    local ok = pcall(build, runtime)
    if not ok then
      Quarantine.frame = nil
      return false
    end
  end
  Quarantine.frame:Show()
  Quarantine.Refresh()
  return true
end
