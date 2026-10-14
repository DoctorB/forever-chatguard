-- Settings validation, migrations and the single mutation path (spec §10, §11).
-- Persisted data: preferences and user-edited lists only. Chat text, timing
-- histories, quarantine and decision caches never enter the saved table.
local _, ns = ...

local Defaults = ns.Core.Defaults
local Normalize = ns.Core.Normalize

local Config = {}
ns.Core.Config = Config

local LIMITS = Defaults.LIMITS
local find = string.find
local RANGES = Defaults.RANGES

local function deepCopy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[deepCopy(k, seen)] = deepCopy(v, seen)
  end
  return copy
end
Config.DeepCopy = deepCopy

local function isInteger(value)
  return type(value) == "number" and value == value and value % 1 == 0
end

local function inRange(value, range)
  return isInteger(value) and value >= range.min and value <= range.max
end

-- Term text as typed by the player: trimmed, bounded, not only whitespace.
function Config.ValidateTermText(text)
  if type(text) ~= "string" then
    return nil, "ERR_TERM_EMPTY"
  end
  local trimmed = Normalize.CollapseSpace(text)
  if trimmed == "" then
    return nil, "ERR_TERM_EMPTY"
  end
  if #trimmed > LIMITS.maxRuleBytes then
    return nil, "ERR_TERM_TOO_LONG"
  end
  return trimmed
end

-- Author keys are "Name-Realm". On WoW Forever a name may hold a first name
-- and a surname ("Name Surname", verified 2026-10-14), so single inner spaces
-- are kept. The adapter qualifies bare names with the player's realm first.
function Config.ValidateAuthorKey(key)
  if type(key) ~= "string" then
    return nil
  end
  local value = Normalize.Identity(Normalize.CollapseSpace(key), LIMITS.maxIdentityBytes)
  if not value or find(value, "|", 1, true) then
    return nil
  end
  return value
end

-- Migrations: each step takes a copy at version N and returns version N+1.
-- Version 0 is an unversioned table (pre-release or hand-edited data).
Config.MIGRATIONS = {
  [0] = function(db)
    db.schemaVersion = 1
    return db
  end,
}

-- Returns a fully valid DB built from raw saved data plus status flags.
-- The raw table is never modified; the caller decides whether to store the
-- returned copy (it must not when status.futureSchema is true).
function Config.Load(raw)
  local status = { corrupt = false, futureSchema = false, migratedFrom = nil }
  if raw == nil then
    return Defaults.NewDB(), status
  end
  if type(raw) ~= "table" then
    status.corrupt = true
    return Defaults.NewDB(), status
  end

  local version = raw.schemaVersion
  if version == nil then
    version = 0
  end
  if not isInteger(version) or version < 0 then
    status.corrupt = true
    version = 0
  end
  if version > Defaults.SCHEMA_VERSION then
    status.futureSchema = true
    local db = Defaults.NewDB()
    db.enabled = false
    return db, status
  end

  local work = deepCopy(raw)
  if version < Defaults.SCHEMA_VERSION then
    status.migratedFrom = version
    for step = version, Defaults.SCHEMA_VERSION - 1 do
      local migrate = Config.MIGRATIONS[step]
      local ok, result = pcall(migrate, work)
      if not ok or type(result) ~= "table" then
        -- Failed migration: keep the raw data untouched, run on defaults.
        status.corrupt = true
        return Defaults.NewDB(), status
      end
      work = result
    end
  end

  local db, repaired = Config.Validate(work)
  if repaired then
    status.corrupt = true
  end
  return db, status
end

-- Validates every field against type, enum and range; invalid values are
-- replaced with defaults. Returns a fresh table and whether anything changed.
function Config.Validate(src)
  local db = Defaults.NewDB()
  local repaired = false
  local function bad()
    repaired = true
  end

  if type(src.enabled) == "boolean" then db.enabled = src.enabled elseif src.enabled ~= nil then bad() end
  if Defaults.MODES[src.mode] then db.mode = src.mode elseif src.mode ~= nil then bad() end

  if type(src.channels) == "table" then
    local count = 0
    for key, label in pairs(src.channels) do
      local k = type(key) == "string" and Normalize.Identity(key, LIMITS.maxIdentityBytes)
      if k and type(label) == "string" and count < LIMITS.maxChannels then
        db.channels[k] = Normalize.Identity(label, LIMITS.maxIdentityBytes) or k
        count = count + 1
      else
        bad()
      end
    end
  elseif src.channels ~= nil then
    bad()
  end

  local dup = src.duplicate
  if type(dup) == "table" then
    if type(dup.enabled) == "boolean" then db.duplicate.enabled = dup.enabled elseif dup.enabled ~= nil then bad() end
    if inRange(dup.windowSeconds, RANGES.duplicateWindow) then
      db.duplicate.windowSeconds = dup.windowSeconds
    elseif dup.windowSeconds ~= nil then
      bad()
    end
  elseif dup ~= nil then
    bad()
  end

  local flood = src.flood
  if type(flood) == "table" then
    if type(flood.enabled) == "boolean" then db.flood.enabled = flood.enabled elseif flood.enabled ~= nil then bad() end
    if inRange(flood.windowSeconds, RANGES.floodWindow) then
      db.flood.windowSeconds = flood.windowSeconds
    elseif flood.windowSeconds ~= nil then
      bad()
    end
    if inRange(flood.maxMessages, RANGES.floodMax) then
      db.flood.maxMessages = flood.maxMessages
    elseif flood.maxMessages ~= nil then
      bad()
    end
  elseif flood ~= nil then
    bad()
  end

  local terms = src.customTerms
  if type(terms) == "table" then
    if type(terms.enabled) == "boolean" then db.customTerms.enabled = terms.enabled elseif terms.enabled ~= nil then bad() end
    local seen, maxId = {}, 0
    if type(terms.list) == "table" then
      for index = 1, #terms.list do
        local entry = terms.list[index]
        local text = type(entry) == "table" and Config.ValidateTermText(entry.text)
        local id = type(entry) == "table" and entry.id
        local normalized = text and Normalize.LowerASCII(text)
        if text and isInteger(id) and id > 0 and not seen[normalized] and not seen[id]
          and #db.customTerms.list < LIMITS.maxRules then
          seen[normalized], seen[id] = true, true
          db.customTerms.list[#db.customTerms.list + 1] = {
            id = id,
            text = text,
            enabled = entry.enabled ~= false,
          }
          if id > maxId then maxId = id end
        else
          bad()
        end
      end
    elseif terms.list ~= nil then
      bad()
    end
    db.customTerms.nextId = maxId + 1
    if isInteger(terms.nextId) and terms.nextId > maxId then
      db.customTerms.nextId = terms.nextId
    end
  elseif terms ~= nil then
    bad()
  end
  db.customTerms.nextId = db.customTerms.nextId or 1

  for _, listName in ipairs({ "allowlist", "blocklist" }) do
    local list = src[listName]
    if type(list) == "table" then
      local count = 0
      for key, value in pairs(list) do
        local k = Config.ValidateAuthorKey(key)
        if k and value == true and count < LIMITS.maxListEntries then
          db[listName][k] = true
          count = count + 1
        else
          bad()
        end
      end
    elseif list ~= nil then
      bad()
    end
  end

  local q = src.quarantine
  if type(q) == "table" then
    if inRange(q.maxEntries, RANGES.quarantineMax) then db.quarantine.maxEntries = q.maxEntries elseif q.maxEntries ~= nil then bad() end
    if inRange(q.ttlSeconds, RANGES.quarantineTtl) then db.quarantine.ttlSeconds = q.ttlSeconds elseif q.ttlSeconds ~= nil then bad() end
  elseif q ~= nil then
    bad()
  end

  if type(src.ui) == "table" then
    -- Only simple scalar UI preferences survive (e.g. panel position).
    for key, value in pairs(src.ui) do
      local t = type(value)
      if type(key) == "string" and (t == "number" or t == "string" or t == "boolean") then
        db.ui[key] = value
      else
        bad()
      end
    end
  elseif src.ui ~= nil then
    bad()
  end

  return db, repaired
end

-- Authors present on both lists: allow wins (spec §6); the UI shows these.
function Config.Conflicts(db)
  local result = {}
  for key in pairs(db.allowlist) do
    if db.blocklist[key] then
      result[#result + 1] = key
    end
  end
  table.sort(result)
  return result
end

---------------------------------------------------------------------------
-- Store: the single mutation path. Every change is validated here and then
-- reported to listeners (engine cache invalidation, UI refresh).
---------------------------------------------------------------------------
local Store = {}
Store.__index = Store
Config.Store = Store

function Config.NewStore(db, options)
  local self = setmetatable({}, Store)
  self.db = db
  self.listeners = {}
  self.generation = 1
  self.readOnly = options and options.readOnly or false
  return self
end

function Store:OnChange(callback)
  self.listeners[#self.listeners + 1] = callback
end

-- kind: "rules" | "windows" | "scope" | "mode" | "reset"
function Store:Changed(kind, detail)
  self.generation = self.generation + 1
  for index = 1, #self.listeners do
    self.listeners[index](kind, detail)
  end
  return true
end

function Store:SetEnabled(value)
  if type(value) ~= "boolean" then return false, "INVALID_VALUE" end
  self.db.enabled = value
  return self:Changed("scope")
end

function Store:SetMode(mode)
  if not Defaults.MODES[mode] then return false, "INVALID_VALUE" end
  self.db.mode = mode
  return self:Changed("mode")
end

function Store:SelectChannel(key, label)
  key = Normalize.Identity(key, LIMITS.maxIdentityBytes)
  if not key then return false, "INVALID_VALUE" end
  if not self.db.channels[key] then
    local count = 0
    for _ in pairs(self.db.channels) do count = count + 1 end
    if count >= LIMITS.maxChannels then return false, "INVALID_VALUE" end
  end
  self.db.channels[key] = Normalize.Identity(label, LIMITS.maxIdentityBytes) or key
  return self:Changed("scope")
end

function Store:UnselectChannel(key)
  if type(key) ~= "string" or not self.db.channels[key] then return false, "INVALID_VALUE" end
  self.db.channels[key] = nil
  return self:Changed("scope", key)
end

function Store:SetDuplicate(enabled, windowSeconds)
  if enabled ~= nil and type(enabled) ~= "boolean" then return false, "INVALID_VALUE" end
  if windowSeconds ~= nil and not inRange(windowSeconds, RANGES.duplicateWindow) then
    return false, "ERR_RANGE", RANGES.duplicateWindow
  end
  if enabled ~= nil then self.db.duplicate.enabled = enabled end
  local windowChanged = windowSeconds ~= nil and windowSeconds ~= self.db.duplicate.windowSeconds
  if windowSeconds ~= nil then self.db.duplicate.windowSeconds = windowSeconds end
  return self:Changed(windowChanged and "windows" or "rules", "duplicate")
end

function Store:SetFlood(enabled, windowSeconds, maxMessages)
  if enabled ~= nil and type(enabled) ~= "boolean" then return false, "INVALID_VALUE" end
  if windowSeconds ~= nil and not inRange(windowSeconds, RANGES.floodWindow) then
    return false, "ERR_RANGE", RANGES.floodWindow
  end
  if maxMessages ~= nil and not inRange(maxMessages, RANGES.floodMax) then
    return false, "ERR_RANGE", RANGES.floodMax
  end
  local f = self.db.flood
  if enabled ~= nil then f.enabled = enabled end
  local windowChanged = (windowSeconds ~= nil and windowSeconds ~= f.windowSeconds)
    or (maxMessages ~= nil and maxMessages ~= f.maxMessages)
  if windowSeconds ~= nil then f.windowSeconds = windowSeconds end
  if maxMessages ~= nil then f.maxMessages = maxMessages end
  return self:Changed(windowChanged and "windows" or "rules", "flood")
end

function Store:SetTermsEnabled(value)
  if type(value) ~= "boolean" then return false, "INVALID_VALUE" end
  self.db.customTerms.enabled = value
  return self:Changed("rules")
end

function Store:AddTerm(text)
  local value, err = Config.ValidateTermText(text)
  if not value then
    return false, err, err == "ERR_TERM_TOO_LONG" and LIMITS.maxRuleBytes or nil
  end
  local list = self.db.customTerms.list
  if #list >= LIMITS.maxRules then
    return false, "ERR_TERM_LIMIT", LIMITS.maxRules
  end
  local normalized = Normalize.LowerASCII(value)
  for index = 1, #list do
    if Normalize.LowerASCII(list[index].text) == normalized then
      return false, "ERR_TERM_DUPLICATE"
    end
  end
  local id = self.db.customTerms.nextId
  self.db.customTerms.nextId = id + 1
  list[#list + 1] = { id = id, text = value, enabled = true }
  self:Changed("rules")
  return true, id, value
end

-- Removes by id (number) or by case-insensitive text.
function Store:RemoveTerm(idOrText)
  local list = self.db.customTerms.list
  local wanted = type(idOrText) == "string" and Normalize.LowerASCII(Normalize.CollapseSpace(idOrText))
  for index = 1, #list do
    local entry = list[index]
    if entry.id == idOrText or (wanted and Normalize.LowerASCII(entry.text) == wanted) then
      table.remove(list, index)
      self:Changed("rules")
      return true, entry.text
    end
  end
  return false, "INVALID_VALUE"
end

function Store:SetListed(listName, key, present)
  if listName ~= "allowlist" and listName ~= "blocklist" then return false, "INVALID_VALUE" end
  local value = Config.ValidateAuthorKey(key)
  if not value then return false, "ERR_NAME_INVALID" end
  local list = self.db[listName]
  if present and not list[value] then
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    if count >= LIMITS.maxListEntries then return false, "INVALID_VALUE" end
  end
  list[value] = present and true or nil
  self:Changed("rules")
  return true, value
end

-- Replaces the content of db in place so references held elsewhere stay valid.
function Store:Reset()
  local fresh = Defaults.NewDB()
  for key in pairs(self.db) do
    self.db[key] = nil
  end
  for key, value in pairs(fresh) do
    self.db[key] = value
  end
  return self:Changed("reset")
end
