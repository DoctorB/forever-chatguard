-- Slash commands (spec §11). Execute() is pure over the runtime table and an
-- output function, so the whole command surface is tested offline.
local _, ns = ...

local Normalize = ns.Core.Normalize
local Config = ns.Core.Config
local Rules = ns.Core.Rules

local Commands = {}
ns.UI.Commands = Commands

local format = string.format
local PREVIEW_CHARS = 120

local function L()
  return ns.L
end

-- Human-readable reason; never shows colours or links from chat.
function Commands.FormatReason(entry)
  local l = L()
  local reason = entry.reason
  if reason == "CUSTOM_TERM" then
    return format(l.REASON_CUSTOM_TERM, Normalize.EscapeForDisplay(tostring(entry.detail or "")))
  elseif reason == "DUPLICATE" then
    return format(l.REASON_DUPLICATE, ns.runtime and ns.runtime.db.duplicate.windowSeconds or entry.detail or 0)
  elseif reason == "FLOOD" then
    local flood = ns.runtime and ns.runtime.db.flood
    return format(l.REASON_FLOOD, flood and flood.maxMessages or entry.detail or 0, flood and flood.windowSeconds or 0)
  end
  return l["REASON_" .. tostring(reason)]
end

-- One-line, display-safe summary of a quarantine entry.
function Commands.FormatEntry(entry, fullText)
  local l = L()
  local text = entry.text or ""
  if not fullText then
    local _, visible = Normalize.Text(text)
    text = visible
    if #text > PREVIEW_CHARS then
      text = Normalize.TruncateUTF8(text, PREVIEW_CHARS) .. "..."
    end
  end
  return format("[%d] %s %s %s (%s): %s -- %s",
    entry.seq,
    entry.receivedAt or "--:--:--",
    Normalize.EscapeForDisplay(tostring(entry.channelLabel or "?")),
    Normalize.EscapeForDisplay(tostring(entry.authorLabel or "?")),
    entry.hidden and l.QUARANTINE_HIDDEN or l.QUARANTINE_WOULD,
    Normalize.EscapeForDisplay(text),
    Commands.FormatReason(entry))
end

-- options.compact drops the diagnostic counters (panel view).
function Commands.StatusLines(runtime, options)
  local l = L()
  local db, engine, adapter = runtime.db, runtime.engine, runtime.adapter
  local lines = {}
  local mode = db.mode == "filter" and l.MODE_FILTER or l.MODE_OBSERVE
  lines[#lines + 1] = format(l.STATUS_LINE, db.enabled and l.ON or l.OFF, mode, adapter:CompatibilityLabel())
  local names = {}
  for _, label in pairs(db.channels) do
    names[#names + 1] = Normalize.EscapeForDisplay(label)
  end
  table.sort(names)
  lines[#lines + 1] = format(l.STATUS_CHANNELS, #names > 0 and table.concat(names, ", ") or l.NONE)
  if #names == 0 then
    lines[#lines + 1] = l.STATUS_NO_CHANNELS
  end
  local c = engine.counters
  lines[#lines + 1] = format(l.STATUS_COUNTERS, c.evaluated, c.allowed, c.suppressed, c.wouldSuppress)
  if not (options and options.compact) then
    lines[#lines + 1] = format(l.STATUS_DIAGNOSTICS, c.oversized, c.unreadable, c.engineErrors, c.cachedCallbacks)
  end
  if not engine.capabilities.stateful then
    lines[#lines + 1] = l.STATUS_STATEFUL_OFF
  end
  if engine.breakerTripped then
    lines[#lines + 1] = l.STATUS_BREAKER
  end
  if runtime.status and runtime.status.futureSchema then
    lines[#lines + 1] = l.STATUS_FUTURE_SCHEMA
  end
  for _, key in ipairs(Config.Conflicts(db)) do
    lines[#lines + 1] = format(l.STATUS_CONFLICT, Normalize.EscapeForDisplay(key))
  end
  return lines
end

local function words(input)
  local result = {}
  for word in string.gmatch(input, "%S+") do
    result[#result + 1] = word
  end
  return result
end

-- Text after the first n words, whitespace preserved inside.
local function rest(input, n)
  local pattern = "^%s*" .. string.rep("%S+%s+", n) .. "(.-)%s*$"
  return string.match(input, pattern) or ""
end

local function reportError(out, err, extra)
  local l = L()
  local message = l[err] or err
  if type(extra) == "table" and extra.min then
    message = format(l.ERR_RANGE, extra.min, extra.max)
  elseif extra ~= nil then
    message = format(message, extra)
  end
  out(format(l.INVALID_VALUE, message))
end

local function quarantineSamples(runtime)
  local samples = {}
  local entries = runtime.engine.quarantine:List(runtime.engine.clock())
  for index = 1, #entries do
    samples[#samples + 1] = entries[index].text
  end
  return samples
end

local handlers = {}

handlers.help = function(_, _, out)
  local l = L()
  out(l.HELP_HEADER)
  for _, line in ipairs(l.HELP_LINES) do
    out(line)
  end
end
handlers[""] = handlers.help

handlers.status = function(runtime, _, out)
  for _, line in ipairs(Commands.StatusLines(runtime)) do
    out(line)
  end
end

handlers.on = function(runtime, _, out)
  local l = L()
  runtime.engine:ResetBreaker()
  runtime.store:SetEnabled(true)
  out(format(l.ENABLED_MSG, runtime.db.mode == "filter" and l.MODE_FILTER or l.MODE_OBSERVE))
end

handlers.off = function(runtime, _, out)
  runtime.store:SetEnabled(false)
  out(L().DISABLED_MSG)
end

handlers.observe = function(runtime, _, out)
  local l = L()
  runtime.store:SetMode("observe")
  out(format(l.MODE_MSG, l.MODE_OBSERVE))
  out(l.MODE_OBSERVE_HELP)
end

handlers.filter = function(runtime, _, out)
  local l = L()
  if not runtime.adapter.caps.filter then
    out(l.STATUS_FILTER_NEEDS_CAPABILITY)
    return
  end
  runtime.store:SetMode("filter")
  out(format(l.MODE_MSG, l.MODE_FILTER))
  out(l.MODE_FILTER_HELP)
end

handlers.config = function(runtime, _, out)
  if ns.UI.Panel and ns.UI.Panel.Toggle then
    ns.UI.Panel.Toggle(runtime)
  else
    handlers.status(runtime, nil, out)
  end
end

handlers.quarantine = function(runtime, args, out)
  local l = L()
  -- The window is the main view; "/fcg quarantine list" prints in chat.
  if args[2] ~= "list" and ns.UI.Quarantine and ns.UI.Quarantine.Show
    and ns.UI.Quarantine.Show(runtime) then
    return
  end
  local entries = runtime.engine.quarantine:List(runtime.engine.clock())
  if #entries == 0 then
    out(l.QUARANTINE_EMPTY)
    return
  end
  out(l.QUARANTINE_HEADER)
  for index = 1, math.min(#entries, 20) do
    out(Commands.FormatEntry(entries[index], false))
  end
end

handlers.show = function(runtime, args, out)
  local seq = tonumber(args[2])
  local entry = seq and runtime.engine.quarantine:Get(seq)
  if not entry then
    out(format(L().QUARANTINE_ENTRY_MISSING, tostring(args[2] or "")))
    return
  end
  out(Commands.FormatEntry(entry, true))
end

handlers.allowentry = function(runtime, args, out)
  local seq = tonumber(args[2])
  local entry = seq and runtime.engine.quarantine:Get(seq)
  if not entry then
    out(format(L().QUARANTINE_ENTRY_MISSING, tostring(args[2] or "")))
    return
  end
  local ok, value = runtime.store:SetListed("allowlist", entry.authorKey, true)
  if ok then
    out(format(L().LIST_ADDED, Normalize.EscapeForDisplay(value), L().LIST_ALLOW))
  else
    reportError(out, value)
  end
end

handlers.clear = function(runtime, _, out)
  runtime.engine.quarantine:Clear()
  out(L().QUARANTINE_CLEARED)
end

handlers.reset = function(runtime, args, out)
  local l = L()
  if args[2] == "confirm" then
    runtime.engine:ResetBreaker()
    runtime.store:Reset()
    out(l.RESET_DONE)
  else
    out(l.RESET_CONFIRM)
  end
end

handlers.channel = function(runtime, args, out)
  local l = L()
  local list = runtime.adapter:ChannelList()
  local sub = args[2] or "list"
  if sub == "list" then
    out(l.CHANNEL_LIST_HEADER)
    for index, item in ipairs(list) do
      out(format("%d: %s%s", index, Normalize.EscapeForDisplay(item.label or item.key), item.selected and " [x]" or ""))
    end
    if #list <= 2 then
      out(l.CHANNEL_NONE_SEEN)
    end
    return
  end
  local item = list[tonumber(args[3] or "") or 0]
  if not item then
    reportError(out, tostring(args[3] or ""))
    return
  end
  if sub == "add" then
    runtime.store:SelectChannel(item.key, item.label)
    out(format(l.CHANNEL_SELECTED, Normalize.EscapeForDisplay(item.label or item.key)))
  elseif sub == "remove" then
    runtime.store:UnselectChannel(item.key)
    out(format(l.CHANNEL_UNSELECTED, Normalize.EscapeForDisplay(item.label or item.key)))
  else
    out(l.UNKNOWN_COMMAND)
  end
end

handlers.term = function(runtime, args, out, input)
  local l = L()
  local sub = args[2]
  local text = rest(input, 2)
  if sub == "add" then
    local ok, err, value = runtime.store:AddTerm(text)
    if ok then
      out(format(l.TERM_ADDED, Normalize.EscapeForDisplay(value)))
      out(l.TERM_NOTE)
      if not runtime.db.customTerms.enabled then
        out(l.TERMS_INACTIVE)
      end
    else
      reportError(out, err, value)
    end
  elseif sub == "remove" then
    local ok, value = runtime.store:RemoveTerm(tonumber(text) or text)
    if ok then
      out(format(l.TERM_REMOVED, Normalize.EscapeForDisplay(value)))
    else
      reportError(out, text)
    end
  elseif sub == "preview" then
    local valid, err = Config.ValidateTermText(text)
    if not valid then
      reportError(out, err)
      return
    end
    local matches, total = Rules.Preview(valid, quarantineSamples(runtime))
    out(format(l.TERM_PREVIEW, Normalize.EscapeForDisplay(valid), #matches, total))
    out(l.TERM_NOTE)
  elseif sub == "on" or sub == "off" then
    runtime.store:SetTermsEnabled(sub == "on")
    out(sub == "on" and l.TERMS_ON or l.TERMS_OFF)
  else
    for _, entry in ipairs(runtime.db.customTerms.list) do
      out(format("%d: %s%s", entry.id, Normalize.EscapeForDisplay(entry.text), entry.enabled and "" or " (off)"))
    end
    out(l.TERM_NOTE)
  end
end

local function listHandler(listName, present)
  return function(runtime, args, out, input)
    local l = L()
    local key = runtime.adapter:QualifyName(rest(input, 1))
    if not key then
      reportError(out, "ERR_NAME_INVALID")
      return
    end
    local ok, value = runtime.store:SetListed(listName, key, present)
    if not ok then
      reportError(out, value)
      return
    end
    local listLabel = listName == "allowlist" and l.LIST_ALLOW or l.LIST_BLOCK
    out(format(present and l.LIST_ADDED or l.LIST_REMOVED, Normalize.EscapeForDisplay(value), listLabel))
  end
end
handlers.allow = listHandler("allowlist", true)
handlers.unallow = listHandler("allowlist", false)
handlers.block = listHandler("blocklist", true)
handlers.unblock = listHandler("blocklist", false)

handlers.dup = function(runtime, args, out)
  local l = L()
  local value = args[2]
  local ok, err, extra
  if value == "on" or value == "off" then
    ok, err, extra = runtime.store:SetDuplicate(value == "on", nil)
  else
    ok, err, extra = runtime.store:SetDuplicate(nil, tonumber(value or ""))
  end
  if not ok then
    reportError(out, err or tostring(value), extra)
    return
  end
  local d = runtime.db.duplicate
  out(format(l.DUP_MSG, d.enabled and l.ON or l.OFF, d.windowSeconds))
end

handlers.flood = function(runtime, args, out)
  local l = L()
  local value = args[2]
  local ok, err, extra
  if value == "on" or value == "off" then
    ok, err, extra = runtime.store:SetFlood(value == "on", nil, nil)
  else
    ok, err, extra = runtime.store:SetFlood(nil, tonumber(value or ""), tonumber(args[3] or ""))
  end
  if not ok then
    reportError(out, err or tostring(value), extra)
    return
  end
  local f = runtime.db.flood
  out(format(l.FLOOD_MSG, f.enabled and l.ON or l.OFF, f.maxMessages, f.windowSeconds))
end

function Commands.Execute(runtime, input, out)
  input = type(input) == "string" and input or ""
  local args = words(input)
  local name = Normalize.LowerASCII(args[1] or "")
  local handler = handlers[name]
  if not handler then
    out(L().UNKNOWN_COMMAND)
    return false
  end
  handler(runtime, args, out, input)
  return true
end

-- Registers /fcg once. Output goes to the default chat frame via AddMessage,
-- which is not a CHAT_MSG_* event and therefore never reaches the filter.
function Commands.Register(env)
  if Commands.registered or type(env.SlashCmdList) ~= "table" then
    return
  end
  env.SLASH_FOREVERCHATGUARD1 = "/fcg"
  env.SlashCmdList.FOREVERCHATGUARD = function(input)
    local ok, err = pcall(Commands.Execute, ns.runtime, input, ns.Print)
    if not ok then
      ns.Print(tostring(err))
    end
  end
  Commands.registered = true
end
