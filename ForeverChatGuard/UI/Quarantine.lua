-- Quarantine window (spec §4, §11): local, session-only, never re-sends text
-- to any chat channel. Chat text is rendered with every "|" escaped, so
-- colours, links and textures from other players are shown as plain text.
local _, ns = ...

local Commands = ns.UI.Commands

local Quarantine = {}
ns.UI.Quarantine = Quarantine

local ROWS, WIDTH = 8, 560

local function build(runtime)
  local L = ns.L
  local frame = CreateFrame("Frame", "ForeverChatGuardQuarantine", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, 120 + ROWS * 44)
  frame:SetPoint("CENTER", 40, -40)
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

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -32)
  title:SetText(L.PANEL_QUARANTINE)

  frame.offset = 0
  frame.rows = {}
  for index = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 32, 40)
    row:SetPoint("TOPLEFT", 16, -56 - (index - 1) * 44)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT")
    text:SetWidth(WIDTH - 200)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    row.text = text
    local show = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    show:SetSize(120, 18)
    show:SetPoint("TOPRIGHT", 0, 0)
    show:SetText(L.PANEL_SHOW_TEXT)
    show:SetScript("OnClick", function()
      if row.entry then
        Commands.Execute(runtime, "show " .. row.entry.seq, ns.Print)
      end
    end)
    local allow = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    allow:SetSize(120, 18)
    allow:SetPoint("TOPRIGHT", show, "BOTTOMRIGHT", 0, -2)
    allow:SetText(L.PANEL_ALLOW_AUTHOR)
    allow:SetScript("OnClick", function()
      if row.entry then
        Commands.Execute(runtime, "allowentry " .. row.entry.seq, ns.Print)
        Quarantine.Refresh()
      end
    end)
    frame.rows[index] = row
  end

  local prev = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  prev:SetSize(110, 22)
  prev:SetPoint("BOTTOMLEFT", 16, 14)
  prev:SetText(L.PANEL_PREV)
  prev:SetScript("OnClick", function()
    frame.offset = math.max(0, frame.offset - ROWS)
    Quarantine.Refresh()
  end)
  local nextButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  nextButton:SetSize(110, 22)
  nextButton:SetPoint("LEFT", prev, "RIGHT", 8, 0)
  nextButton:SetText(L.PANEL_NEXT)
  nextButton:SetScript("OnClick", function()
    frame.offset = frame.offset + ROWS
    Quarantine.Refresh()
  end)
  local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  close:SetSize(100, 22)
  close:SetPoint("BOTTOMRIGHT", -16, 14)
  close:SetText(L.PANEL_CLOSE)
  close:SetScript("OnClick", function() frame:Hide() end)

  frame:SetScript("OnShow", function() Quarantine.Refresh() end)
  Quarantine.frame, Quarantine.runtime = frame, runtime
  return frame
end

function Quarantine.Refresh()
  local frame, runtime = Quarantine.frame, Quarantine.runtime
  if not frame then return end
  local entries = runtime.engine.quarantine:List(runtime.engine.clock())
  if frame.offset >= #entries then
    frame.offset = math.max(0, #entries - ROWS)
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
end

function Quarantine.Show(runtime)
  if not Quarantine.frame then
    local ok = pcall(build, runtime)
    if not ok then
      Quarantine.frame = nil
      return
    end
  end
  Quarantine.frame:Show()
  Quarantine.Refresh()
end
