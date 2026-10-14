local F = T.F

T.Case("disabled addon: every message passes", function()
  local ctx = F.Engine({ configure = function(db) db.enabled = false; db.blocklist[F.ALICE] = true end })
  for _ = 1, 3 do
    local d, hide = F.Deliver(ctx, { text = "same" })
    T.Eq(d.reason, "DISABLED")
    T.NotOk(hide)
  end
end)

T.Case("observe mode: nothing hidden, wouldSuppress counted", function()
  local ctx = F.Engine()
  F.Deliver(ctx, { text = "repeat me" })
  local d, hide = F.Deliver(ctx, { text = "repeat me" })
  T.Eq(d.action, "suppress")
  T.Eq(d.reason, "DUPLICATE")
  T.NotOk(hide, "observe never hides")
  local c = ctx.engine.counters
  T.Eq(c.wouldSuppress, 1)
  T.Eq(c.suppressed, 0)
  T.Eq(c.allowed, 1)
  T.Eq(c.evaluated, 2)
  local list = ctx.engine.quarantine:List(ctx.clock.now())
  T.Eq(#list, 1)
  T.NotOk(list[1].hidden)
end)

T.Case("filter mode hides and counts suppressed", function()
  local ctx = F.Engine({ configure = function(db) db.mode = "filter" end })
  F.Deliver(ctx, { text = "x" })
  local _, hide = F.Deliver(ctx, { text = "x" })
  T.Ok(hide)
  T.Eq(ctx.engine.counters.suppressed, 1)
  T.Eq(ctx.engine.counters.wouldSuppress, 0)
end)

T.Case("filter mode without filter capability never hides", function()
  local ctx = F.Engine({
    configure = function(db) db.mode = "filter" end,
    capabilities = { analysis = true, filter = false, stateful = true },
  })
  F.Deliver(ctx, { text = "x" })
  local d, hide = F.Deliver(ctx, { text = "x" })
  T.Eq(d.reason, "DUPLICATE")
  T.NotOk(hide)
end)

T.Case("unselected channel passes and does not touch rate state", function()
  local ctx = F.Engine({ configure = function(db) db.flood.enabled = true end })
  for _ = 1, 10 do
    local d = F.Deliver(ctx, { channelKey = "zone:26", text = "same" })
    T.Eq(d.reason, "OUT_OF_SCOPE")
  end
  T.Eq(ctx.engine.flood:AuthorCount("zone:26"), 0)
  T.Eq(ctx.engine.duplicates.count, 0)
end)

T.Case("whisper/party/guild/system pass even for a blocked author", function()
  local ctx = F.Engine({ configure = function(db) db.blocklist[F.ALICE] = true; db.mode = "filter" end })
  for _, event in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_GUILD", "CHAT_MSG_SYSTEM" }) do
    local d, hide = F.Deliver(ctx, { event = event, eligible = false })
    T.Eq(d.reason, "OUT_OF_SCOPE", event)
    T.NotOk(hide)
  end
end)

T.Case("own message passes", function()
  local ctx = F.Engine({ configure = function(db) db.blocklist[F.ALICE] = true end })
  T.Eq(F.Deliver(ctx, { isSelf = true }).reason, "SELF")
end)

T.Case("author on both lists passes via allowlist", function()
  local ctx = F.Engine({ configure = function(db)
    db.allowlist[F.ALICE] = true
    db.blocklist[F.ALICE] = true
  end })
  T.Eq(F.Deliver(ctx).reason, "ALLOWLIST")
  T.Eq(#ctx.ns.Core.Config.Conflicts(ctx.db), 1)
end)

T.Case("blocklist suppresses only in selected channels", function()
  local ctx = F.Engine({ configure = function(db) db.blocklist[F.ALICE] = true end })
  T.Eq(F.Deliver(ctx).reason, "BLOCKLIST")
  T.Eq(F.Deliver(ctx, { channelKey = "custom:mine" }).reason, "OUT_OF_SCOPE")
end)

T.Case("same name on another realm is a different author", function()
  local ctx = F.Engine({ configure = function(db) db.blocklist[F.ALICE] = true end })
  T.Eq(F.Deliver(ctx, { authorKey = F.ALICE_OTHER_REALM }).reason, "PASS")
end)

T.Case("first occurrence passes, replica at +1s is a duplicate", function()
  local ctx = F.Engine()
  T.Eq(F.Deliver(ctx, { text = "hello" }).reason, "PASS")
  ctx.clock.advance(1)
  T.Eq(F.Deliver(ctx, { text = "hello" }).reason, "DUPLICATE")
end)

T.Case("replica at exactly +30s passes and opens a new window", function()
  local ctx = F.Engine()
  F.Deliver(ctx, { text = "hello" })
  ctx.clock.advance(30)
  T.Eq(F.Deliver(ctx, { text = "hello" }).reason, "PASS")
  ctx.clock.advance(29.9)
  T.Eq(F.Deliver(ctx, { text = "hello" }).reason, "DUPLICATE")
  ctx.clock.advance(0.1)
  T.Eq(F.Deliver(ctx, { text = "hello" }).reason, "PASS")
end)

T.Case("suppressed replicas do not move the expiry", function()
  local ctx = F.Engine()
  F.Deliver(ctx, { text = "spam" })
  for _ = 1, 5 do
    ctx.clock.advance(5)
    T.Eq(F.Deliver(ctx, { text = "spam" }).reason, "DUPLICATE")
  end
  ctx.clock.advance(5) -- t = +30 from the first
  T.Eq(F.Deliver(ctx, { text = "spam" }).reason, "PASS")
end)

T.Case("same text from a different author is not a duplicate", function()
  local ctx = F.Engine()
  F.Deliver(ctx, { text = "lfg deadmines" })
  T.Eq(F.Deliver(ctx, { text = "lfg deadmines", authorKey = F.BOB }).reason, "PASS")
end)

T.Case("same text in a different channel is not a duplicate", function()
  local ctx = F.Engine()
  F.Deliver(ctx, { text = "lfg deadmines" })
  T.Eq(F.Deliver(ctx, { text = "lfg deadmines", channelKey = F.GENERAL }).reason, "PASS")
end)

T.Case("prices 10g and 100g are not duplicates", function()
  local ctx = F.Engine()
  F.Deliver(ctx, { text = "WTS bag 10g" })
  T.Eq(F.Deliver(ctx, { text = "WTS bag 100g" }).reason, "PASS")
end)

T.Case("different items with the same label are not duplicates", function()
  local ctx = F.Engine()
  F.Deliver(ctx, { text = "WTS " .. F.ITEM_A })
  T.Eq(F.Deliver(ctx, { text = "WTS " .. F.ITEM_B }).reason, "PASS")
  T.Eq(F.Deliver(ctx, { text = "WTS " .. F.ITEM_B }).reason, "DUPLICATE")
end)

T.Case("sixth unique delivery in 10s with limit 5 is FLOOD", function()
  local ctx = F.Engine({ configure = function(db) db.flood.enabled = true end })
  for index = 1, 5 do
    T.Eq(F.Deliver(ctx, { text = "msg " .. index }).reason, "PASS", "message " .. index)
    ctx.clock.advance(1)
  end
  local d = F.Deliver(ctx, { text = "msg 6" })
  T.Eq(d.reason, "FLOOD")
  T.Eq(d.detail, 5)
end)

T.Case("timestamp exactly now - window is outside the flood window", function()
  local ctx = F.Engine({ configure = function(db) db.flood.enabled = true end })
  F.Deliver(ctx, { text = "m1" }) -- t0
  ctx.clock.advance(1)
  for index = 2, 5 do
    F.Deliver(ctx, { text = "m" .. index }) -- t0+1
  end
  ctx.clock.advance(9) -- now = t0 + 10: t0 is exactly now - window
  T.Eq(F.Deliver(ctx, { text = "m6" }).reason, "PASS", "t0 must be excluded")
  T.Eq(F.Deliver(ctx, { text = "m7" }).reason, "FLOOD")
end)

T.Case("duplicates count as traffic but give a single reason", function()
  local ctx = F.Engine({ configure = function(db) db.flood.enabled = true end })
  for _ = 1, 5 do
    F.Deliver(ctx, { text = "same" })
  end
  local d = F.Deliver(ctx, { text = "same" })
  T.Eq(d.reason, "DUPLICATE", "duplicate wins over flood by priority")
  T.Eq(F.Deliver(ctx, { text = "different" }).reason, "FLOOD", "duplicates counted as traffic")
  T.Eq(#ctx.engine.quarantine:List(ctx.clock.now()), 6, "one entry per delivery")
end)

T.Case("priority: blocklist > custom term > duplicate > flood", function()
  local ctx = F.Engine({ configure = function(db)
    db.flood.enabled = true
    db.customTerms.enabled = true
    db.customTerms.list = { { id = 4, text = "boost", enabled = true } }
  end })
  F.Deliver(ctx, { text = "boost run" })
  T.Eq(F.Deliver(ctx, { text = "boost run" }).reason, "CUSTOM_TERM")
  ctx.store:SetListed("blocklist", F.ALICE, true)
  T.Eq(F.Deliver(ctx, { text = "boost run" }).reason, "BLOCKLIST")
end)

T.Case("higher-priority rule still updates duplicate history once", function()
  local ctx = F.Engine({ configure = function(db) db.blocklist[F.ALICE] = true end })
  T.Eq(F.Deliver(ctx, { text = "hello" }).reason, "BLOCKLIST")
  ctx.store:SetListed("blocklist", F.ALICE, false)
  T.Eq(F.Deliver(ctx, { text = "hello" }).reason, "DUPLICATE", "window opened by the blocked delivery")
end)

T.Case("custom term decision exposes the rule id", function()
  local ctx = F.Engine({ configure = function(db)
    db.customTerms.enabled = true
    db.customTerms.list = { { id = 9, text = "cheap gold", enabled = true } }
  end })
  local d = F.Deliver(ctx, { text = "CHEAP   Gold for you" })
  T.Eq(d.reason, "CUSTOM_TERM")
  T.Eq(d.ruleId, 9)
end)

T.Case("custom terms ignored while the feature is disabled", function()
  local ctx = F.Engine({ configure = function(db)
    db.customTerms.list = { { id = 1, text = "gold", enabled = true } }
  end })
  T.Eq(F.Deliver(ctx, { text = "gold" }).reason, "PASS")
end)

T.Case("same delivery in 3 chat windows: same decision, counted once", function()
  local ctx = F.Engine({ configure = function(db) db.mode = "filter"; db.flood.enabled = true end })
  F.Deliver(ctx, { text = "dup" })
  local message = F.Message(ctx, { text = "dup" })
  local results = {}
  for window = 1, 3 do
    local hide, decision = ctx.engine:Deliver(message)
    results[window] = { hide = hide, reason = decision.reason }
  end
  for window = 2, 3 do
    T.Eq(results[window].reason, results[1].reason)
    T.Eq(results[window].hide, results[1].hide)
  end
  local c = ctx.engine.counters
  T.Eq(c.evaluated, 2)
  T.Eq(c.suppressed, 1)
  T.Eq(c.cachedCallbacks, 2)
  T.Eq(#ctx.engine.flood.channels[F.TRADE].authors[F.ALICE].times, 2, "flood state updated once")
  T.Eq(ctx.engine.quarantine:Size(), 1)
end)

T.Case("two real identical events at the same instant: two counts, second duplicate", function()
  local ctx = F.Engine()
  local d1 = F.Deliver(ctx, { text = "twin" })
  local d2 = F.Deliver(ctx, { text = "twin" })
  T.Eq(d1.reason, "PASS")
  T.Eq(d2.reason, "DUPLICATE")
  T.Eq(ctx.engine.counters.evaluated, 2)
end)

T.Case("missing message id with stateful disabled: explicit degradation", function()
  local ctx = F.Engine({ capabilities = { analysis = true, filter = true, stateful = false },
    configure = function(db)
      db.flood.enabled = true
      db.blocklist[F.BOB] = true
      db.customTerms.enabled = true
      db.customTerms.list = { { id = 1, text = "gold", enabled = true } }
    end })
  for _ = 1, 8 do
    T.Eq(F.Deliver(ctx, { text = "same", eventId = false }).reason, "PASS", "no stateful rules")
  end
  T.Eq(ctx.engine.duplicates.count, 0)
  T.Eq(F.Deliver(ctx, { text = "gold", eventId = false }).reason, "CUSTOM_TERM", "stateless rules remain")
  T.Eq(F.Deliver(ctx, { authorKey = F.BOB, eventId = false }).reason, "BLOCKLIST")
end)

T.Case("invalid inputs pass without errors", function()
  local ctx = F.Engine({ configure = function(db) db.mode = "filter" end })
  local bad = {
    "not a table",
    { text = nil, authorKey = F.ALICE, channelKey = F.TRADE, now = 1, eligible = true },
    { text = {}, authorKey = F.ALICE, channelKey = F.TRADE, now = 1, eligible = true },
    { text = "x", authorKey = "", channelKey = F.TRADE, now = 1, eligible = true },
    { text = "x", authorKey = F.ALICE, channelKey = F.TRADE, now = 0 / 0, eligible = true },
    { text = "x", authorKey = string.rep("a", 500), channelKey = F.TRADE, now = 1, eligible = true },
  }
  for index = 1, #bad do
    local hide, decision = ctx.engine:Deliver(bad[index])
    T.NotOk(hide)
    T.Eq(decision.reason, "INVALID_INPUT", "case " .. index)
  end
  T.Eq(ctx.engine.counters.invalid, #bad)
  T.Eq(ctx.engine.counters.engineErrors, 0)
end)

T.Case("oversized text passes unanalysed and is counted", function()
  local ctx = F.Engine({ configure = function(db) db.blocklist[F.ALICE] = true end })
  local d = F.Deliver(ctx, { text = string.rep("x", 4097) })
  T.Eq(d.reason, "INVALID_INPUT")
  T.Eq(ctx.engine.counters.oversized, 1)
  T.Eq(F.Deliver(ctx, { text = string.rep("x", 4096) }).reason, "BLOCKLIST")
end)

T.Case("engine error fails open and trips the breaker after 3 in 60s", function()
  local notices = 0
  local ctx = F.Engine({ configure = function(db) db.mode = "filter"; db.blocklist[F.ALICE] = true end,
    onBreaker = function() notices = notices + 1 end })
  local original = ctx.engine.Evaluate
  ctx.engine.Evaluate = function() error("induced") end
  for index = 1, 2 do
    local d, hide = F.Deliver(ctx)
    T.Eq(d.reason, "ENGINE_ERROR")
    T.NotOk(hide)
    ctx.clock.advance(25)
    T.NotOk(ctx.engine.breakerTripped, "not yet after " .. index)
  end
  F.Deliver(ctx)
  T.Ok(ctx.engine.breakerTripped)
  T.Eq(notices, 1)
  ctx.engine.Evaluate = original
  local d, hide = F.Deliver(ctx)
  T.Eq(d.reason, "ENGINE_ERROR", "suspended for the session")
  T.NotOk(hide)
  F.Deliver(ctx)
  T.Eq(notices, 1, "notice shown once")
  ctx.engine:ResetBreaker()
  T.Eq(F.Deliver(ctx).reason, "BLOCKLIST", "manual reactivation")
end)

T.Case("errors spread over more than 60s do not trip the breaker", function()
  local ctx = F.Engine()
  ctx.engine.Evaluate = function() error("induced") end
  for _ = 1, 5 do
    F.Deliver(ctx)
    ctx.clock.advance(31)
  end
  T.NotOk(ctx.engine.breakerTripped)
end)

T.Case("rule change invalidates cached decisions", function()
  local ctx = F.Engine()
  local message = F.Message(ctx, { text = "hello" })
  T.Eq(select(2, ctx.engine:Deliver(message)).reason, "PASS")
  ctx.store:SetListed("blocklist", F.ALICE, true)
  local _, d = ctx.engine:Deliver(message)
  T.Eq(d.reason, "BLOCKLIST", "no stale decision from cache")
end)

T.Case("allowing an author changes future decisions", function()
  local ctx = F.Engine({ configure = function(db) db.blocklist[F.ALICE] = true end })
  T.Eq(F.Deliver(ctx).reason, "BLOCKLIST")
  ctx.store:SetListed("allowlist", F.ALICE, true)
  T.Eq(F.Deliver(ctx).reason, "ALLOWLIST")
end)

T.Case("changing a window clears only that history", function()
  local ctx = F.Engine({ configure = function(db) db.flood.enabled = true end })
  F.Deliver(ctx, { text = "a" })
  T.Eq(ctx.engine.duplicates.count, 1)
  ctx.store:SetDuplicate(nil, 60)
  T.Eq(ctx.engine.duplicates.count, 0)
  T.Eq(#ctx.engine.flood.channels[F.TRADE].authors[F.ALICE].times, 1, "flood kept")
  ctx.store:SetFlood(nil, 20, nil)
  T.Eq(ctx.engine.flood:AuthorCount(F.TRADE), 0)
end)

T.Case("disabling mid-session: new messages pass immediately", function()
  local ctx = F.Engine({ configure = function(db) db.mode = "filter"; db.blocklist[F.ALICE] = true end })
  T.Ok(select(2, F.Deliver(ctx)))
  ctx.store:SetEnabled(false)
  local d, hide = F.Deliver(ctx)
  T.Eq(d.reason, "DISABLED")
  T.NotOk(hide)
end)

T.Case("duplicate store respects the key limit and TTL", function()
  local ctx = F.Engine()
  local limit = ctx.ns.Core.Defaults.LIMITS.maxDuplicateKeys
  for index = 1, limit + 250 do
    F.Deliver(ctx, { text = "unique " .. index, authorKey = "A" .. (index % 300) .. "-R" })
  end
  T.Ok(ctx.engine.duplicates.count <= limit, "count " .. ctx.engine.duplicates.count)
  ctx.clock.advance(31)
  F.Deliver(ctx, { text = "trigger prune" })
  T.Eq(ctx.engine.duplicates.count, 1, "expired windows reclaimed")
end)

T.Case("flood store respects authors-per-channel and channel limits", function()
  local ctx = F.Engine({ configure = function(db) db.flood.enabled = true end })
  local L = ctx.ns.Core.Defaults.LIMITS
  for index = 1, L.maxAuthorsPerChannel + 50 do
    F.Deliver(ctx, { authorKey = "P" .. index .. "-R", text = "t" })
  end
  T.Ok(ctx.engine.flood:AuthorCount(F.TRADE) <= L.maxAuthorsPerChannel)
  local flood = ctx.engine.flood
  for index = 1, L.maxChannels + 5 do
    flood:Record("A-R", "c" .. index, ctx.clock.now() + index, 10, 5)
  end
  T.Ok(flood.channelCount <= L.maxChannels)
end)

T.Case("decision cache respects size and TTL", function()
  local ctx = F.Engine()
  local L = ctx.ns.Core.Defaults.LIMITS
  for index = 1, L.maxDecisionCache + 100 do
    F.Deliver(ctx, { text = "c" .. index })
  end
  T.Ok(ctx.engine.cache.count <= L.maxDecisionCache)
  ctx.clock.advance(L.decisionCacheTtl + 1)
  F.Deliver(ctx, { text = "after ttl" })
  T.Eq(ctx.engine.cache.count, 1)
end)

T.Case("quarantine respects max entries and TTL", function()
  local ctx = F.Engine({ configure = function(db)
    db.blocklist[F.ALICE] = true
    db.quarantine.maxEntries = 20
    db.quarantine.ttlSeconds = 60
  end })
  for index = 1, 50 do
    F.Deliver(ctx, { text = "q" .. index })
  end
  local list = ctx.engine.quarantine:List(ctx.clock.now())
  T.Eq(#list, 20)
  T.Eq(list[1].text, "q50", "newest first")
  ctx.clock.advance(60)
  T.Eq(#ctx.engine.quarantine:List(ctx.clock.now()), 0)
end)

T.Case("quarantine keeps the original text unchanged", function()
  local ctx = F.Engine({ configure = function(db) db.blocklist[F.ALICE] = true end })
  local raw = "WTS " .. F.ITEM_A .. "  "
  F.Deliver(ctx, { text = raw })
  T.Eq(ctx.engine.quarantine:List(ctx.clock.now())[1].text, raw)
end)

T.Case("engine never reads client globals", function()
  local ns = T.LoadAddon()
  local source = T.ReadFile(T.ADDON_DIR .. "/Core/Engine.lua")
    .. T.ReadFile(T.ADDON_DIR .. "/Core/Store.lua")
    .. T.ReadFile(T.ADDON_DIR .. "/Core/Rules.lua")
    .. T.ReadFile(T.ADDON_DIR .. "/Core/Normalize.lua")
  for _, name in ipairs({ "GetTime", "CreateFrame", "ChatFrame_", "UnitName", "_G", "DEFAULT_CHAT_FRAME" }) do
    T.NotOk(source:find(name, 1, true), name .. " referenced in core")
  end
  T.Ok(ns.Core.Engine)
end)
