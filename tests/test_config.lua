local ns = T.LoadAddon()
local Config = ns.Core.Config
local Defaults = ns.Core.Defaults

local function snapshot(value)
  -- Deterministic serialisation used to prove raw tables stay untouched.
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. "=" .. snapshot(value[key])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

T.Case("first run: observe mode, no channels, terms off", function()
  local db, status = Config.Load(nil)
  T.Eq(db.mode, "observe")
  T.Eq(db.enabled, true)
  T.Eq(next(db.channels), nil)
  T.Eq(db.duplicate.enabled, true)
  T.Eq(db.duplicate.windowSeconds, 30)
  T.Eq(db.flood.enabled, false)
  T.Eq(db.flood.windowSeconds, 10)
  T.Eq(db.flood.maxMessages, 5)
  T.Eq(db.customTerms.enabled, false)
  T.Eq(#db.customTerms.list, 0)
  T.Eq(db.quarantine.maxEntries, 200)
  T.Eq(db.quarantine.ttlSeconds, 900)
  T.Eq(db.schemaVersion, Defaults.SCHEMA_VERSION)
  T.NotOk(status.corrupt)
end)

T.Case("valid saved data round-trips", function()
  local raw = Defaults.NewDB()
  raw.mode = "filter"
  raw.channels["zone:2"] = "Trade"
  raw.duplicate.windowSeconds = 45
  raw.customTerms.list = { { id = 3, text = "boost", enabled = true } }
  raw.customTerms.nextId = 4
  raw.allowlist["Alice-Realm"] = true
  local db, status = Config.Load(raw)
  T.NotOk(status.corrupt)
  T.Eq(db.mode, "filter")
  T.Eq(db.channels["zone:2"], "Trade")
  T.Eq(db.duplicate.windowSeconds, 45)
  T.Eq(db.customTerms.list[1].text, "boost")
  T.Eq(db.customTerms.nextId, 4)
  T.Eq(db.allowlist["Alice-Realm"], true)
end)

T.Case("corrupt root falls back to safe defaults with a flag", function()
  for _, raw in ipairs({ "garbage", 42, true }) do
    local db, status = Config.Load(raw)
    T.Ok(status.corrupt)
    T.Eq(db.mode, "observe")
  end
end)

T.Case("invalid fields are repaired individually", function()
  local raw = {
    schemaVersion = 1,
    enabled = "yes",
    mode = "nuke",
    channels = { ["zone:2"] = "Trade", [5] = "x", ["zone:9"] = {} },
    duplicate = { enabled = true, windowSeconds = 500 },
    flood = { enabled = true, windowSeconds = 2.5, maxMessages = 31 },
    customTerms = { enabled = true, list = {
      { id = 1, text = "ok" },
      { id = 2, text = "   " },
      { id = 3, text = string.rep("x", 129) },
      { id = 1, text = "duplicate id" },
      { id = 4, text = "OK" },
      "not a table",
    } },
    allowlist = { ["Bad Name-Realm"] = true, ["Good-Realm"] = true, ["Other-Realm"] = "yes" },
    blocklist = "nope",
    quarantine = { maxEntries = 10, ttlSeconds = 120 },
    ui = { x = 10, bad = {} },
  }
  local before = snapshot(raw)
  local db, status = Config.Load(raw)
  T.Ok(status.corrupt)
  T.Eq(snapshot(raw), before, "raw saved table must stay untouched")
  T.Eq(db.enabled, true)
  T.Eq(db.mode, "observe")
  T.Eq(db.channels["zone:2"], "Trade")
  T.Eq(db.channels["zone:9"], nil)
  T.Eq(db.duplicate.windowSeconds, 30)
  T.Eq(db.flood.enabled, true)
  T.Eq(db.flood.windowSeconds, 10)
  T.Eq(db.flood.maxMessages, 5)
  T.Eq(#db.customTerms.list, 1, "only the first valid unique term survives")
  T.Eq(db.customTerms.list[1].text, "ok")
  T.Eq(db.allowlist["Good-Realm"], true)
  T.Eq(db.allowlist["Bad Name-Realm"], nil)
  T.Eq(db.allowlist["Other-Realm"], nil)
  T.Eq(next(db.blocklist), nil)
  T.Eq(db.quarantine.maxEntries, 200)
  T.Eq(db.quarantine.ttlSeconds, 120)
  T.Eq(db.ui.x, 10)
  T.Eq(db.ui.bad, nil)
end)

T.Case("future schema: disabled, raw data never replaced", function()
  local raw = { schemaVersion = Defaults.SCHEMA_VERSION + 1, enabled = true, mode = "filter", newField = { 1, 2 } }
  local before = snapshot(raw)
  local db, status = Config.Load(raw)
  T.Ok(status.futureSchema)
  T.Eq(db.enabled, false)
  T.Eq(snapshot(raw), before)
end)

T.Case("unversioned data migrates to the current schema", function()
  local raw = { enabled = false, mode = "filter" }
  local db, status = Config.Load(raw)
  T.Eq(status.migratedFrom, 0)
  T.Eq(db.schemaVersion, Defaults.SCHEMA_VERSION)
  T.Eq(db.enabled, false)
  T.Eq(db.mode, "filter")
  T.Eq(raw.schemaVersion, nil, "migration runs on a copy")
end)

T.Case("migrations are sequential and idempotent", function()
  local db1 = Config.Load({ mode = "filter" })
  local db2 = Config.Load(db1)
  T.Eq(snapshot(db1), snapshot(db2))
end)

T.Case("failed migration keeps raw data and uses defaults", function()
  local saved = Config.MIGRATIONS[0]
  Config.MIGRATIONS[0] = function() error("boom") end
  local raw = { mode = "filter" }
  local db, status = Config.Load(raw)
  Config.MIGRATIONS[0] = saved
  T.Ok(status.corrupt)
  T.Eq(db.mode, "observe")
  T.Eq(raw.mode, "filter")
  T.Eq(raw.schemaVersion, nil)
end)

T.Case("negative or fractional schema versions are treated as corrupt", function()
  local _, status = Config.Load({ schemaVersion = -1 })
  T.Ok(status.corrupt)
  _, status = Config.Load({ schemaVersion = 0.5 })
  T.Ok(status.corrupt)
end)

T.Case("store validates ranges and limits", function()
  local store = Config.NewStore(Defaults.NewDB())
  T.NotOk(store:SetDuplicate(nil, 4))
  T.NotOk(store:SetDuplicate(nil, 121))
  T.Ok(store:SetDuplicate(nil, 120))
  T.NotOk(store:SetFlood(nil, 2, nil))
  T.NotOk(store:SetFlood(nil, nil, 31))
  T.Ok(store:SetFlood(true, 60, 30))
  T.NotOk(store:SetMode("loud"))
  T.NotOk(store:SetEnabled("yes"))
end)

T.Case("terms: empty, whitespace, too long, duplicates and count limit", function()
  local store = Config.NewStore(Defaults.NewDB())
  T.NotOk(store:AddTerm(""))
  T.NotOk(store:AddTerm("   \t "))
  local ok, err = store:AddTerm(string.rep("y", 129))
  T.NotOk(ok)
  T.Eq(err, "ERR_TERM_TOO_LONG")
  T.Ok(store:AddTerm(string.rep("y", 128)))
  T.Ok(store:AddTerm("Cheap Gold"))
  ok, err = store:AddTerm("cheap   GOLD")
  T.NotOk(ok)
  T.Eq(err, "ERR_TERM_DUPLICATE")
  for index = 3, 100 do
    T.Ok(store:AddTerm("term " .. index))
  end
  ok, err = store:AddTerm("one too many")
  T.NotOk(ok)
  T.Eq(err, "ERR_TERM_LIMIT")
  T.Ok(store:RemoveTerm("CHEAP GOLD"))
  T.Ok(store:RemoveTerm(1))
  T.Eq(#store.db.customTerms.list, 98)
end)

T.Case("every change notifies listeners once", function()
  local store = Config.NewStore(Defaults.NewDB())
  local kinds = {}
  store:OnChange(function(kind) kinds[#kinds + 1] = kind end)
  store:SetEnabled(false)
  store:SetMode("filter")
  store:AddTerm("x")
  store:SetDuplicate(nil, 40)
  store:SelectChannel("zone:2", "Trade")
  store:Reset()
  T.Eq(table.concat(kinds, ","), "scope,mode,rules,windows,scope,reset")
end)

T.Case("reset restores defaults in place", function()
  local db = Defaults.NewDB()
  local store = Config.NewStore(db)
  store:SetMode("filter")
  store:SetListed("blocklist", "Bob-Realm", true)
  store:Reset()
  T.Eq(db.mode, "observe")
  T.Eq(next(db.blocklist), nil)
  T.Ok(store.db == db)
end)

T.Case("author names with spaces or pipes are rejected", function()
  local store = Config.NewStore(Defaults.NewDB())
  T.NotOk(store:SetListed("allowlist", "Bad Name-Realm", true))
  T.NotOk(store:SetListed("allowlist", "Pipe|cff-Realm", true))
  T.NotOk(store:SetListed("nolist", "A-B", true))
  T.Ok(store:SetListed("allowlist", "Àlice-Realm", true))
end)

T.Case("persisted table never contains chat text or histories", function()
  local db = Defaults.NewDB()
  local allowed = {
    schemaVersion = true, enabled = true, mode = true, channels = true, duplicate = true,
    flood = true, customTerms = true, allowlist = true, blocklist = true, quarantine = true, ui = true,
  }
  for key in pairs(db) do
    T.Ok(allowed[key], "unexpected persisted key " .. tostring(key))
  end
  T.Eq(db.quarantine.entries, nil)
end)
