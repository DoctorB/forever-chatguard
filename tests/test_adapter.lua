-- Adapter contract against a MOCK client. These checks prove the adapter's
-- own logic only; they are not evidence of compatibility with WoW Forever.
local F = T.F

-- Mock of the classic chat-filter dispatch: every chat window runs every
-- filter; true hides; extra return values replace the arguments.
local function newClient(options)
  options = options or {}
  local env = { filters = {}, frames = {}, now = 500, secret = {} }
  env.GetTime = function() return env.now end
  env.UnitName = function() return "Me" end
  env.UnitGUID = function() return "Player-1-0001" end
  env.GetNormalizedRealmName = function() return "Realm" end
  env.date = function() return "12:00:00" end
  env.SlashCmdList = {}
  if options.secrets then
    env.issecretvalue = function(value) return env.secret[value] == true end
  end
  env.CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    env.frames[#env.frames + 1] = frame
    return frame
  end
  if not options.noFilterApi then
    env.ChatFrame_AddMessageEventFilter = function(event, fn)
      env.filters[event] = env.filters[event] or {}
      for _, existing in ipairs(env.filters[event]) do
        if existing == fn then return end
      end
      table.insert(env.filters[event], fn)
    end
    env.ChatFrame_RemoveMessageEventFilter = function(event, fn)
      local list = env.filters[event] or {}
      for index = #list, 1, -1 do
        if list[index] == fn then table.remove(list, index) end
      end
    end
  end
  -- Returns per-window results: { hidden = bool, args = {...}, n = count }.
  function env.dispatch(windows, event, ...)
    local results = {}
    for window = 1, windows do
      local args = { n = select("#", ...), ... }
      local hidden = false
      for _, fn in ipairs(env.filters[event] or {}) do
        local packed = { fn({ id = window }, event, unpack(args, 1, args.n)) }
        if packed[1] then
          hidden = true
          break
        elseif packed[2] ~= nil then
          args = { n = #packed - 1, unpack(packed, 2) }
        end
      end
      results[window] = { hidden = hidden, args = args }
    end
    return results
  end
  -- Event-frame delivery: one OnEvent per registered frame.
  function env.fire(event, ...)
    for _, frame in ipairs(env.frames) do
      if frame.events[event] and frame.scripts.OnEvent then
        frame.scripts.OnEvent(frame, event, ...)
      end
    end
  end
  return env
end

local function payload(text, author, zoneChannelID, baseName, lineID, guid)
  -- text, author, language, channelName, author2, flags, zoneChannelID,
  -- channelIndex, channelBaseName, languageID, lineID, guid, then trailing nils.
  return text, author, "Common", "2. Trade", "", "", zoneChannelID or 2, 2,
    baseName or "Trade", 7, lineID, guid or "Player-1-00AA", nil, false, nil
end

local function start(options)
  options = options or {}
  local ns = T.LoadAddon()
  local Adapter = ns.Adapters.Forever
  if options.verified then
    for key, value in pairs(options.verified) do Adapter.COMPAT.verified[key] = value end
  end
  local env = newClient(options)
  env.ForeverChatGuardDB = options.saved
  local runtime = Adapter.Start(env)
  return ns, env, runtime, Adapter
end

local ALL_VERIFIED = { filterApi = true, payload = true, lineId = true, eventFrame = true }

T.Case("compatibility flags match the docs", function()
  local ns = T.LoadAddon()
  local verified = ns.Adapters.Forever.COMPAT.verified
  local doc = T.ReadFile(T.ROOT .. "/docs/compatibility.md")
  local block = doc:match("<!%-%- compat:(.-)%-%->")
  T.Ok(block, "machine-readable compat block missing in docs/compatibility.md")
  local count = 0
  for key, value in block:gmatch("(%w+)=(%w+)") do
    count = count + 1
    T.Eq(tostring(verified[key]), value, "flag " .. key)
  end
  local expected = 0
  for _ in pairs(verified) do expected = expected + 1 end
  T.Eq(count, expected)
  T.Eq(tostring(ns.Adapters.Forever.COMPAT.interface), T.TocField("Interface"))
end)

local NONE_VERIFIED = { filterApi = false, payload = false, lineId = false, eventFrame = false }

T.Case("unverified client: observes through an event frame, filter mode refused", function()
  local _, env, runtime = start({ verified = NONE_VERIFIED })
  T.Ok(runtime.adapter.caps.filterApiPresent)
  T.NotOk(runtime.adapter.caps.filter)
  T.Eq(next(env.filters), nil, "no chat filter registered while unverified")
  T.Ok(env.frames[#env.frames].events.CHAT_MSG_CHANNEL)
  T.Ok(runtime.engine.capabilities.stateful, "one OnEvent per event keeps state exact")
  runtime.store:SelectChannel("zone:2", "Trade")
  env.fire("CHAT_MSG_CHANNEL", payload("hi", "Bob-Realm", 2, "Trade", 1))
  env.fire("CHAT_MSG_CHANNEL", payload("hi", "Bob-Realm", 2, "Trade", 2))
  T.Eq(runtime.engine.counters.evaluated, 2)
  T.Eq(runtime.engine.counters.wouldSuppress, 1)
end)

T.Case("first start is observe mode and stores a validated DB", function()
  local _, env, runtime = start()
  T.Eq(runtime.db.mode, "observe")
  T.Ok(env.ForeverChatGuardDB == runtime.db)
end)

T.Case("future schema in saved variables is left untouched", function()
  local saved = { schemaVersion = 99, secret = "keep" }
  local _, env, runtime = start({ saved = saved })
  T.Ok(env.ForeverChatGuardDB == saved, "saved table not replaced")
  T.Eq(saved.secret, "keep")
  T.Eq(runtime.db.enabled, false)
end)

T.Case("verified client in filter mode: same decision in 3 windows, counted once", function()
  local _, env, runtime = start({ verified = ALL_VERIFIED })
  runtime.store:SelectChannel("zone:2", "Trade")
  runtime.store:SetMode("filter")
  T.Ok(env.filters.CHAT_MSG_CHANNEL and #env.filters.CHAT_MSG_CHANNEL == 1)
  env.dispatch(3, "CHAT_MSG_CHANNEL", payload("spam", "Bob-Realm", 2, "Trade", 10))
  local results = env.dispatch(3, "CHAT_MSG_CHANNEL", payload("spam", "Bob-Realm", 2, "Trade", 11))
  for window = 1, 3 do
    T.Ok(results[window].hidden, "window " .. window)
  end
  local c = runtime.engine.counters
  T.Eq(c.evaluated, 2)
  T.Eq(c.suppressed, 1)
  T.Eq(c.cachedCallbacks, 4)
end)

T.Case("allowed messages keep text, order and nil arguments unchanged", function()
  local _, env, runtime = start({ verified = ALL_VERIFIED })
  runtime.store:SelectChannel("zone:2", "Trade")
  runtime.store:SetMode("filter")
  local results = env.dispatch(2, "CHAT_MSG_CHANNEL", payload("hello |cffff0000x|r", "Bob-Realm", 2, "Trade", 20))
  local args = results[1].args
  T.NotOk(results[1].hidden)
  T.Eq(args.n, 15)
  T.Eq(args[1], "hello |cffff0000x|r")
  T.Eq(args[2], "Bob-Realm")
  T.Eq(args[11], 20)
  T.Eq(args[13], nil)
  T.Eq(args[14], false)
  T.Eq(args[15], nil)
end)

T.Case("toggling and repeated registration never stack filters", function()
  local _, env, runtime = start({ verified = ALL_VERIFIED })
  runtime.store:SetMode("filter")
  runtime.adapter:RegisterPaths()
  runtime.adapter:RegisterPaths()
  runtime.store:SetEnabled(false)
  runtime.store:SetEnabled(true)
  T.Eq(#env.filters.CHAT_MSG_CHANNEL, 1)
  runtime.store:SetMode("observe")
  T.Eq(#env.filters.CHAT_MSG_CHANNEL, 0, "filter removed in observe mode")
  runtime.store:SetMode("filter")
  T.Eq(#env.filters.CHAT_MSG_CHANNEL, 1)
end)

T.Case("filter path without verified line id disables stateful rules", function()
  local _, env, runtime = start({ verified = { filterApi = true, payload = true, lineId = false } })
  runtime.store:SelectChannel("zone:2", "Trade")
  runtime.store:SetMode("filter")
  T.NotOk(runtime.engine.capabilities.stateful)
  env.dispatch(3, "CHAT_MSG_CHANNEL", payload("dup", "Bob-Realm", 2, "Trade", 30))
  local results = env.dispatch(3, "CHAT_MSG_CHANNEL", payload("dup", "Bob-Realm", 2, "Trade", 31))
  T.NotOk(results[1].hidden, "duplicates cannot be judged without an id")
  runtime.store:SetListed("blocklist", "Bob-Realm", true)
  results = env.dispatch(3, "CHAT_MSG_CHANNEL", payload("dup", "Bob-Realm", 2, "Trade", 32))
  T.Ok(results[1].hidden and results[3].hidden, "stateless rules still work")
end)

T.Case("secret payload values are never analysed and never hidden", function()
  local _, env, runtime = start({ verified = ALL_VERIFIED, secrets = true })
  runtime.store:SelectChannel("zone:2", "Trade")
  runtime.store:SetMode("filter")
  runtime.store:SetListed("blocklist", "Bob-Realm", true)
  env.secret["secret text"] = true
  local results = env.dispatch(1, "CHAT_MSG_CHANNEL", payload("secret text", "Bob-Realm", 2, "Trade", 40))
  T.NotOk(results[1].hidden)
  T.Eq(runtime.engine.counters.unreadable, 1)
  T.Eq(runtime.engine.counters.evaluated, 0)
end)

T.Case("no filter API: observation only, explained once", function()
  local ns, env, runtime = start({ noFilterApi = true, verified = NONE_VERIFIED })
  T.NotOk(runtime.adapter.caps.filterApiPresent)
  T.NotOk(runtime.adapter.caps.filter)
  T.Eq(next(env.filters), nil)
  local out = {}
  runtime.store:SetMode("observe")
  ns.UI.Commands.Execute(runtime, "filter", function(line) out[#out + 1] = line end)
  T.Eq(runtime.db.mode, "observe")
  T.Eq(out[1], ns.L.STATUS_FILTER_NEEDS_CAPABILITY)
end)

T.Case("no read path at all: analysis disabled, chat untouched", function()
  local ns = T.LoadAddon()
  local env = newClient({ noFilterApi = true })
  env.CreateFrame = nil
  local runtime = ns.Adapters.Forever.Start(env)
  T.NotOk(runtime.adapter.caps.analysis)
  local found = false
  for _, line in ipairs(ns.printed) do
    if line:find(ns.L.STATUS_NO_FILTER_API, 1, true) then found = true end
  end
  T.Ok(found, "single local explanation printed")
end)

T.Case("channel identity uses zone channel id, not the visible number", function()
  local _, env, runtime = start()
  runtime.store:SelectChannel("zone:2", "Trade")
  env.fire("CHAT_MSG_CHANNEL", "x", "Bob-Realm", "Common", "5. Trade - City", "", "", 2, 5, "Trade", 7, 1, "G")
  T.Eq(runtime.engine.counters.evaluated, 1)
  T.Eq(runtime.engine.counters.allowed, 1)
  local list = runtime.adapter:ChannelList()
  local keys = {}
  for _, item in ipairs(list) do keys[item.key] = item.selected end
  T.Eq(keys["zone:2"], true)
end)

T.Case("custom channels are keyed by base name", function()
  local ns = T.LoadAddon()
  local env = newClient()
  local runtime = ns.Adapters.Forever.Start(env)
  local message = runtime.adapter:BuildMessage("CHAT_MSG_CHANNEL",
    "x", "Bob-Realm", "", "6. MyChan", "", "", 0, 6, "MyChan", 7, 3, "G")
  T.Eq(message.channelKey, "custom:mychan")
end)

T.Case("own messages detected by name-realm or GUID", function()
  local _, _, runtime = start()
  local m1 = runtime.adapter:BuildMessage("CHAT_MSG_SAY", "hi", "Me-Realm")
  T.Ok(m1.isSelf)
  local m2 = runtime.adapter:BuildMessage("CHAT_MSG_SAY", "hi", "Me", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-0001")
  T.Ok(m2.isSelf)
  local m3 = runtime.adapter:BuildMessage("CHAT_MSG_SAY", "hi", "Other-Realm")
  T.NotOk(m3.isSelf)
end)

T.Case("realm-less names are qualified with the player realm", function()
  local _, _, runtime = start()
  T.Eq(runtime.adapter:QualifyName("Bob"), "Bob-Realm")
  T.Eq(runtime.adapter:QualifyName("Bob-Other"), "Bob-Other")
  T.Eq(runtime.adapter:QualifyName("Uorriora  Uorrior"), "Uorriora Uorrior-Realm")
  T.Eq(runtime.adapter:QualifyName("Bad|Name"), nil)
end)

T.Case("events outside the public scope are not eligible", function()
  local _, _, runtime = start()
  local message = runtime.adapter:BuildMessage("CHAT_MSG_WHISPER", "hi", "Bob-Realm")
  T.NotOk(message.eligible)
end)

T.Case("errors inside the adapter fail open", function()
  local _, env, runtime = start({ verified = ALL_VERIFIED })
  runtime.store:SelectChannel("zone:2", "Trade")
  runtime.store:SetMode("filter")
  runtime.adapter.BuildMessage = function() error("adapter bug") end
  local results = env.dispatch(1, "CHAT_MSG_CHANNEL", payload("x", "Bob-Realm", 2, "Trade", 50))
  T.NotOk(results[1].hidden)
end)

T.Case("say and yell are selectable scopes; nothing is selected by default", function()
  local _, _, runtime = start()
  local list = runtime.adapter:ChannelList()
  T.Eq(list[1].key, "say")
  T.Eq(list[2].key, "yell")
  T.NotOk(list[1].selected)
  T.Eq(next(runtime.db.channels), nil)
end)

T.Case("slash command registered once", function()
  local ns, env = start()
  ns.UI.Commands.Register(env)
  T.Eq(env.SLASH_FOREVERCHATGUARD1, "/fcg")
  T.Eq(type(env.SlashCmdList.FOREVERCHATGUARD), "function")
end)

-- Payload shape observed on 1.60.1.70374 (probe, 2026-10-14): 18 arguments,
-- author without realm containing one space, zoneChannelID 0 for Say.
T.Case("Forever Say payload with a surname is analysed", function()
  local _, env, runtime = start()
  runtime.store:SelectChannel("say", "Say")
  local function say(text, line)
    env.fire("CHAT_MSG_SAY", text, "Uorriora Uorrior", "", "", "Uorriora Uorrior", "", 0, 0, "", 7,
      line, "Player-4618-01732DD6", nil, false, false, false, false, {})
  end
  say("ciao test", 100)
  say("ciao test", 101)
  T.Eq(runtime.engine.counters.invalid, 0)
  T.Eq(runtime.engine.counters.wouldSuppress, 1)
  local entry = runtime.engine.quarantine:List(env.now)[1]
  T.Eq(entry.authorKey, "Uorriora Uorrior-Realm")
end)

T.Case("joined channels are discovered from the client list", function()
  local ns = T.LoadAddon()
  local env = newClient()
  env.GetChannelList = function() return 1, "General", false, 2, "Trade", false, 6, "fcgprobetest", false end
  env.C_ChatInfo = { GetChannelInfoFromIdentifier = function(name)
    local ids = { General = 1, Trade = 2, fcgprobetest = 0 }
    return { name = name, zoneChannelID = ids[name] }
  end }
  local runtime = ns.Adapters.Forever.Start(env)
  local keys = {}
  for _, item in ipairs(runtime.adapter:ChannelList()) do keys[item.key] = item.label end
  T.Eq(keys["zone:1"], "General")
  T.Eq(keys["zone:2"], "Trade")
  T.Eq(keys["custom:fcgprobetest"], "fcgprobetest")
end)

T.Case("unexpected channel list shapes are ignored", function()
  local ns = T.LoadAddon()
  local env = newClient()
  env.GetChannelList = function() return { "weird" } end
  env.C_ChatInfo = { GetChannelInfoFromIdentifier = function() error("no") end }
  local runtime = ns.Adapters.Forever.Start(env)
  T.Eq(#runtime.adapter:ChannelList(), 2, "only Say and Yell")
end)

T.Case("testself judges own messages for the session only, never persisted", function()
  local ns, env, runtime = start()
  runtime.store:SelectChannel("say", "Say")
  local out = {}
  ns.UI.Commands.Execute(runtime, "testself on", function(line) out[#out + 1] = line end)
  env.fire("CHAT_MSG_SAY", "ciao test", "Me", "", "", "Me", "", 0, 0, "", 7, 200, "Player-1-0001")
  env.fire("CHAT_MSG_SAY", "ciao test", "Me", "", "", "Me", "", 0, 0, "", 7, 201, "Player-1-0001")
  T.Eq(runtime.engine.counters.wouldSuppress, 1)
  for key in pairs(runtime.db) do T.NotOk(key:lower():find("test"), "persisted " .. key) end
  ns.UI.Commands.Execute(runtime, "testself off", function() end)
  env.fire("CHAT_MSG_SAY", "ciao test", "Me", "", "", "Me", "", 0, 0, "", 7, 202, "Player-1-0001")
  T.Eq(runtime.engine.counters.wouldSuppress, 1, "own message passes again")
end)
