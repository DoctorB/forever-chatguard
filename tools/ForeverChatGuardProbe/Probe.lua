-- Forever ChatGuard compatibility probe (development tool, not packaged).
--
-- Records which chat APIs exist on this client and how CHAT_MSG_* payloads
-- look, WITHOUT storing message text, player names or GUIDs: only types,
-- secret flags, lengths and a few non-personal numbers (channel IDs, line IDs).
--
-- It hides a message only when its text contains the marker "fcgprobe-hide";
-- use it in a private custom channel (/join fcgprobetest), never in public.
--
-- /fcgprobe          print a summary
-- /fcgprobe reset    clear the recorded data
-- Data is written to WTF/.../SavedVariables/ForeverChatGuardProbe.lua on /reload or logout.
local ADDON = ...

local EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }
local MAX_SAMPLES = 25
local MAX_LINES = 60

local db

local function out(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00FCG probe|r: " .. tostring(message))
  end
end

local function isSecret(value)
  if type(issecretvalue) ~= "function" then return false end
  local ok, result = pcall(issecretvalue, value)
  return (not ok) or result == true
end

local function safeType(value)
  local ok, t = pcall(type, value)
  return ok and t or "error"
end

local function restrictionState()
  local result = {}
  local api = C_RestrictedActions
  if type(api) == "table" and type(api.IsAddOnRestrictionActive) == "function" then
    for typeIndex = 0, 8 do
      local ok, active = pcall(api.IsAddOnRestrictionActive, typeIndex)
      result[#result + 1] = ok and tostring(active) or "err"
    end
  end
  return table.concat(result, ",")
end

-- Shape of one argument; personal strings are reduced to their length.
local NUMERIC_KEEP = { [7] = true, [8] = true, [10] = true, [11] = true }
local NAME_KEEP = { [9] = true } -- channelBaseName (e.g. "Trade"), not personal
local function describe(index, value)
  local entry = { t = safeType(value) }
  if isSecret(value) then
    entry.secret = true
    return entry
  end
  if entry.t == "number" and NUMERIC_KEEP[index] then
    entry.v = value
  elseif entry.t == "string" then
    entry.len = #value
    if NAME_KEEP[index] then entry.v = value:sub(1, 40) end
    if index == 2 then entry.hasRealm = value:find("-", 1, true) ~= nil end
    if index == 12 then entry.prefix = value:match("^(%a+)%-") end
  elseif entry.t == "boolean" then
    entry.v = value
  end
  return entry
end

local function record(source, frameName, event, ...)
  local n = select("#", ...)
  local text, _, _, _, _, _, _, _, _, _, lineID = ...
  local perEvent = db.samples[event]
  if not perEvent then
    perEvent = {}
    db.samples[event] = perEvent
  end
  if source == "frame" and #perEvent < MAX_SAMPLES then
    local args = {}
    for index = 1, math.min(n, 20) do
      args[index] = describe(index, (select(index, ...)))
    end
    perEvent[#perEvent + 1] = { n = n, args = args, restrictions = restrictionState(), time = GetTime and GetTime() }
  end
  -- Callback multiplicity per line identity.
  if not isSecret(lineID) and type(lineID) == "number" then
    local key = event .. ":" .. lineID
    local line = db.lines[key]
    if not line and db.lineCount < MAX_LINES then
      line = { frameEvents = 0, filterCalls = 0, windows = {} }
      db.lines[key] = line
      db.lineCount = db.lineCount + 1
    end
    if line then
      if source == "frame" then
        line.frameEvents = line.frameEvents + 1
      else
        line.filterCalls = line.filterCalls + 1
        line.windows[frameName or "?"] = (line.windows[frameName or "?"] or 0) + 1
      end
      if not isSecret(text) and type(text) == "string" then
        line.marker = text:find("fcgprobe-hide", 1, true) and "hide"
          or (text:find("fcgprobe-pass", 1, true) and "pass") or nil
        line.textLen = #text
      end
    end
  else
    db.missingLineId = (db.missingLineId or 0) + 1
  end
end

local function filter(chatFrame, event, ...)
  local ok, hide = pcall(function(...)
    local name = chatFrame and chatFrame.GetName and chatFrame:GetName() or "?"
    record("filter", name, event, ...)
    local text = ...
    if not isSecret(text) and type(text) == "string" and text:find("fcgprobe-hide", 1, true) then
      db.hideRequests = (db.hideRequests or 0) + 1
      return true
    end
    return false
  end, ...)
  if ok and hide then
    return true
  end
  return false
end

-- Test widgets live in a hidden holder: a visible EditBox with the default
-- auto-focus would capture all keyboard input (seen on 2026-10-14).
local function probeTemplates()
  local result = {}
  local holder = CreateFrame("Frame", nil, UIParent)
  holder:Hide()
  for _, spec in ipairs({
    { "Button", "UIPanelButtonTemplate" },
    { "CheckButton", "UICheckButtonTemplate" },
    { "EditBox", "InputBoxTemplate" },
    { "Frame", "BasicFrameTemplateWithInset" },
    { "Frame", "BackdropTemplate" },
  }) do
    local ok, widget = pcall(CreateFrame, spec[1], nil, holder, spec[2])
    result[spec[2]] = ok
    if ok and widget then
      if spec[1] == "EditBox" then
        widget:SetAutoFocus(false)
        widget:ClearFocus()
      end
      widget:Hide()
    end
  end
  return result
end

local function probeGlobals()
  local names = {
    "ChatFrame_AddMessageEventFilter", "ChatFrame_RemoveMessageEventFilter", "ChatFrameUtil",
    "issecretvalue", "canaccessvalue", "canaccesstable", "C_RestrictedActions", "C_ChatInfo",
    "GetChannelList", "GetChannelName", "GetTime", "GetTimePreciseSec", "CreateFrame",
    "SlashCmdList", "UISpecialFrames", "GetNormalizedRealmName", "UnitGUID", "UnitName",
    "GetLocale", "C_Timer", "utf8", "bit", "strsplit", "date", "time", "Settings",
    "InCombatLockdown", "DEFAULT_CHAT_FRAME", "SendChatMessage",
  }
  local result = {}
  for _, name in ipairs(names) do
    result[name] = safeType(_G[name])
  end
  if type(ChatFrameUtil) == "table" then
    result["ChatFrameUtil.AddMessageEventFilter"] = safeType(ChatFrameUtil.AddMessageEventFilter)
    result["ChatFrameUtil.RemoveMessageEventFilter"] = safeType(ChatFrameUtil.RemoveMessageEventFilter)
  end
  if type(C_ChatInfo) == "table" then
    result["C_ChatInfo.GetChannelInfoFromIdentifier"] = safeType(C_ChatInfo.GetChannelInfoFromIdentifier)
    result["C_ChatInfo.GetChannelShortcut"] = safeType(C_ChatInfo.GetChannelShortcut)
  end
  return result
end

local function luaFeatures()
  local result = { version = _VERSION }
  result["goto"] = loadstring and (loadstring("goto x ::x::") ~= nil) or false
  result.integerDivision = loadstring and (loadstring("return 7 // 2") ~= nil) or false
  result.bitwiseOps = loadstring and (loadstring("return 1 & 1") ~= nil) or false
  result.stringFindPlain = select(1, string.find("a.b", ".", 1, true)) == 2
  return result
end

local function start()
  ForeverChatGuardProbeDB = type(ForeverChatGuardProbeDB) == "table" and ForeverChatGuardProbeDB or {}
  db = ForeverChatGuardProbeDB
  db.loads = (db.loads or 0) + 1
  db.samples = db.samples or {}
  db.lines = db.lines or {}
  db.lineCount = db.lineCount or 0
  db.forbidden = db.forbidden or {}
  local version, build, buildDate, interface = GetBuildInfo()
  db.build = { version = version, build = build, date = buildDate, interface = interface,
    projectId = WOW_PROJECT_ID, locale = GetLocale and GetLocale() }
  db.globals = probeGlobals()
  db.templates = probeTemplates()
  db.lua = luaFeatures()
  db.restrictionsAtLoad = restrictionState()

  local add = ChatFrame_AddMessageEventFilter
  if type(add) ~= "function" and type(ChatFrameUtil) == "table" then
    add = ChatFrameUtil.AddMessageEventFilter
  end
  db.filterRegistration = {}
  for _, event in ipairs(EVENTS) do
    if type(add) == "function" then
      local ok, err = pcall(add, event, filter)
      db.filterRegistration[event] = ok and "ok" or ("error: " .. tostring(err))
    else
      db.filterRegistration[event] = "no api"
    end
  end
  out(string.format("loaded (load #%d). Build %s (%s), Interface %s. Type /fcgprobe for a summary.",
    db.loads, tostring(version), tostring(build), tostring(interface)))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
for _, event in ipairs(EVENTS) do
  frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == ADDON then
      local ok, err = pcall(start)
      if not ok then out("start failed: " .. tostring(err)) end
    end
  elseif event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
    local addon, action = ...
    if addon == ADDON and db then
      db.forbidden[#db.forbidden + 1] = event .. ":" .. tostring(action)
    end
  elseif db then
    local ok, err = pcall(record, "frame", nil, event, ...)
    if not ok then db.recordError = tostring(err) end
  end
end)

SLASH_FCGPROBE1 = "/fcgprobe"
SlashCmdList.FCGPROBE = function(input)
  if not db then out("not started") return end
  if input == "reset" then
    ForeverChatGuardProbeDB = nil
    db = nil
    out("data cleared; /reload to start again")
    return
  end
  local b = db.build
  out(string.format("build %s.%s Interface %s project %s, %s; loads %d",
    tostring(b.version), tostring(b.build), tostring(b.interface), tostring(b.projectId), tostring(db.lua.version), db.loads))
  out("filter API: " .. tostring(db.globals.ChatFrame_AddMessageEventFilter)
    .. " / ChatFrameUtil." .. tostring(db.globals["ChatFrameUtil.AddMessageEventFilter"])
    .. "; issecretvalue " .. tostring(db.globals.issecretvalue))
  for event, state in pairs(db.filterRegistration) do
    out(event .. " filter registration: " .. state)
  end
  for event, list in pairs(db.samples) do
    local secret = 0
    for _, sample in ipairs(list) do
      if sample.args[1] and sample.args[1].secret then secret = secret + 1 end
    end
    out(string.format("%s: %d samples, %d with secret text", event, #list, secret))
  end
  local lines, multi = 0, 0
  for _, line in pairs(db.lines) do
    lines = lines + 1
    if line.filterCalls > 1 then multi = multi + 1 end
  end
  out(string.format("lines tracked %d, with >1 filter callback %d, missing lineID %d, hide requests %d",
    lines, multi, db.missingLineId or 0, db.hideRequests or 0))
  out("forbidden/blocked actions: " .. #db.forbidden .. ". /reload to save the report.")
end
