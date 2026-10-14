local F = T.F

local function setup(options)
  options = options or {}
  local ns = T.LoadAddon({ locale = options.locale })
  local env = {
    GetTime = function() return 100 end,
    UnitName = function() return "Me" end,
    GetNormalizedRealmName = function() return "Realm" end,
    CreateFrame = function()
      return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end }
    end,
    SlashCmdList = {},
  }
  local runtime = ns.Adapters.Forever.Start(env)
  local out = {}
  local function run(input)
    for index = #out, 1, -1 do out[index] = nil end
    ns.UI.Commands.Execute(runtime, input, function(line) out[#out + 1] = line end)
    return out
  end
  return ns, runtime, run, out
end

local function contains(lines, needle)
  for _, line in ipairs(lines) do
    if line:find(needle, 1, true) then return true end
  end
  return false
end

T.Case("help is the default and lists every command", function()
  local _, _, run = setup()
  local out = run("")
  T.Ok(contains(out, "/fcg status"))
  T.Ok(contains(out, "/fcg reset"))
  T.Eq(#run("help"), #out)
end)

T.Case("status shows mode, compatibility and the no-channel warning", function()
  local ns, _, run = setup()
  local out = run("status")
  T.Ok(contains(out, ns.L.MODE_OBSERVE))
  T.Ok(contains(out, ns.L.COMPAT_UNVERIFIED))
  T.Ok(contains(out, ns.L.STATUS_NO_CHANNELS))
end)

T.Case("on/off/observe change state immediately", function()
  local _, runtime, run = setup()
  run("off")
  T.Eq(runtime.db.enabled, false)
  run("on")
  T.Eq(runtime.db.enabled, true)
  run("observe")
  T.Eq(runtime.db.mode, "observe")
end)

T.Case("filter refused while the capability is unverified", function()
  local ns, runtime, run = setup()
  local out = run("filter")
  T.Eq(runtime.db.mode, "observe")
  T.Eq(out[1], ns.L.STATUS_FILTER_NEEDS_CAPABILITY)
end)

T.Case("reset needs confirmation", function()
  local ns, runtime, run = setup()
  run("block Bob")
  T.Eq(runtime.db.blocklist["Bob-Realm"], true)
  local out = run("reset")
  T.Eq(out[1], ns.L.RESET_CONFIRM)
  T.Eq(runtime.db.blocklist["Bob-Realm"], true, "nothing deleted without confirm")
  run("reset confirm")
  T.Eq(next(runtime.db.blocklist), nil)
end)

T.Case("term add/preview/on/remove with literal text", function()
  local ns, runtime, run = setup()
  local out = run("term add   Cheap  Gold% ")
  T.Ok(contains(out, ns.L.TERM_NOTE))
  T.Ok(contains(out, ns.L.TERMS_INACTIVE))
  T.Eq(runtime.db.customTerms.list[1].text, "Cheap Gold%")
  out = run("term add")
  T.Ok(contains(out, ns.L.ERR_TERM_EMPTY))
  out = run("term preview gold")
  T.Ok(out[1]:find("0", 1, true))
  run("term on")
  T.Eq(runtime.db.customTerms.enabled, true)
  run("term remove cheap gold%")
  T.Eq(#runtime.db.customTerms.list, 0)
end)

T.Case("allow/block lists qualify names and report invalid ones", function()
  local ns, runtime, run = setup()
  run("allow Alice")
  run("block Bob-Elsewhere")
  T.Eq(runtime.db.allowlist["Alice-Realm"], true)
  T.Eq(runtime.db.blocklist["Bob-Elsewhere"], true)
  run("block Name Surname")
  T.Eq(runtime.db.blocklist["Name Surname-Realm"], true)
  local out = run("block Bad|Name")
  T.Ok(contains(out, ns.L.ERR_NAME_INVALID))
  run("unblock Bob-Elsewhere")
  T.Eq(runtime.db.blocklist["Bob-Elsewhere"], nil)
end)

T.Case("conflicts between lists are reported in status", function()
  local ns, _, run = setup()
  run("allow Alice")
  run("block Alice")
  local out = run("status")
  T.Ok(contains(out, string.format(ns.L.STATUS_CONFLICT, "Alice-Realm")))
end)

T.Case("dup and flood settings validate ranges", function()
  local _, runtime, run = setup()
  run("dup 4")
  T.Eq(runtime.db.duplicate.windowSeconds, 30)
  run("dup 60")
  T.Eq(runtime.db.duplicate.windowSeconds, 60)
  run("dup off")
  T.Eq(runtime.db.duplicate.enabled, false)
  run("flood on")
  run("flood 20 8")
  T.Eq(runtime.db.flood.enabled, true)
  T.Eq(runtime.db.flood.windowSeconds, 20)
  T.Eq(runtime.db.flood.maxMessages, 8)
  run("flood 99 8")
  T.Eq(runtime.db.flood.windowSeconds, 20)
end)

T.Case("channel selection by list index", function()
  local _, runtime, run = setup()
  run("channel add 1")
  T.Eq(runtime.db.channels.say ~= nil, true)
  run("channel remove 1")
  T.Eq(runtime.db.channels.say, nil)
end)

T.Case("quarantine list, show and allowentry are display-safe", function()
  local _, runtime, run = setup()
  run("channel add 1")
  run("block Bob")
  local text = "evil |cffff0000red|r " .. F.ITEM_A
  runtime.engine:Deliver({
    event = "CHAT_MSG_SAY", authorKey = "Bob-Realm", authorLabel = "Bob|Hx|h",
    channelKey = "say", channelLabel = "Say", text = text, now = 100, eligible = true,
    receivedAt = "10:00:00",
  })
  local out = run("quarantine")
  T.Eq(#out, 2)
  T.NotOk(out[2]:find("[^|]|[^|]"), "entry line has no live escape sequence")
  T.Ok(out[2]:find("10:00:00", 1, true))
  out = run("show 1")
  T.Ok(out[1]:find("||cffff0000", 1, true), "full text shown escaped")
  run("allowentry 1")
  T.Eq(runtime.db.allowlist["Bob-Realm"], true)
  run("clear")
  T.Eq(runtime.engine.quarantine:Size(), 0)
  out = run("show 1")
  T.Ok(out[1]:find("1", 1, true))
end)

T.Case("unknown command reports help hint", function()
  local ns, _, run = setup()
  T.Eq(run("frobnicate")[1], ns.L.UNKNOWN_COMMAND)
end)

T.Case("Italian locale with English fallback", function()
  local ns, _, run = setup({ locale = "itIT" })
  T.Eq(ns.L.MODE_OBSERVE, "osservazione")
  T.Eq(ns.L.ADDON_TITLE, "Forever ChatGuard", "fallback to English")
  T.Eq(ns.L.SOME_MISSING_KEY, "SOME_MISSING_KEY")
  T.Ok(contains(run("status"), "osservazione"))
end)

T.Case("quarantine list prints in chat when no window is available", function()
  local _, runtime, run = setup()
  run("channel add 1")
  run("block Bob")
  runtime.engine:Deliver({ authorKey = "Bob-Realm", channelKey = "say", text = "x", now = 100, eligible = true })
  T.Eq(#run("quarantine list"), 2)
  T.Eq(#run("quarantine"), 2, "falls back to chat output offline")
end)

T.Case("channels can be selected by name, case-insensitively", function()
  local _, runtime, run = setup()
  runtime.adapter:RememberChannel("custom:fcgprobetest", "fcgprobetest")
  run("channel add FCGProbeTest")
  T.Eq(runtime.db.channels["custom:fcgprobetest"], "fcgprobetest")
  run("channel remove fcgprobetest")
  T.Eq(runtime.db.channels["custom:fcgprobetest"], nil)
  run("channel add Yell")
  T.Ok(runtime.db.channels.yell)
end)
