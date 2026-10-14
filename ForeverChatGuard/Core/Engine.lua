-- Decision engine (spec §6, §8). Never touches client globals: it receives the
-- live settings table, capability flags and an injected monotonic clock.
local _, ns = ...

local Defaults = ns.Core.Defaults
local Normalize = ns.Core.Normalize
local Rules = ns.Core.Rules
local Store = ns.Core.Store

local Engine = {}
Engine.__index = Engine
ns.Core.Engine = Engine

local LIMITS = Defaults.LIMITS

Engine.REASONS = {
  PASS = true, DISABLED = true, OUT_OF_SCOPE = true, SELF = true,
  ALLOWLIST = true, BLOCKLIST = true, CUSTOM_TERM = true, DUPLICATE = true,
  FLOOD = true, INVALID_INPUT = true, ENGINE_ERROR = true,
}

local function allow(reason)
  return { action = "allow", reason = reason }
end

local function suppress(reason, ruleId, detail)
  return { action = "suppress", reason = reason, ruleId = ruleId, detail = detail }
end

local function isFiniteNumber(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function newCounters()
  return {
    evaluated = 0, allowed = 0, suppressed = 0, wouldSuppress = 0,
    oversized = 0, invalid = 0, unreadable = 0, engineErrors = 0, cachedCallbacks = 0,
  }
end

-- options:
--   db            live settings table (validated)
--   clock         function() -> monotonic seconds
--   capabilities  { analysis = bool, filter = bool, stateful = bool }
--   onBreaker     optional callback, called once when the breaker trips
function Engine.New(options)
  local self = setmetatable({}, Engine)
  self.db = options.db
  self.clock = options.clock
  self.capabilities = options.capabilities or { analysis = true, filter = true, stateful = true }
  self.onBreaker = options.onBreaker
  self.counters = newCounters()
  self.duplicates = Store.NewDuplicates(LIMITS.maxDuplicateKeys)
  self.flood = Store.NewFlood(LIMITS.maxAuthorsPerChannel, LIMITS.maxChannels)
  self.cache = Store.NewDecisionCache(LIMITS.maxDecisionCache, LIMITS.decisionCacheTtl)
  local q = self.db.quarantine
  self.quarantine = Store.NewQuarantine(q.maxEntries, q.ttlSeconds)
  self.errorTimes = {}
  self.breakerTripped = false
  self:CompileRules()
  return self
end

function Engine:CompileRules()
  self.compiledTerms = Rules.Compile(self.db.customTerms)
end

-- Config listener: one invalidation path for every settings change.
function Engine:OnConfigChanged(kind, detail)
  self.cache:Clear()
  self:CompileRules()
  local q = self.db.quarantine
  self.quarantine:Resize(q.maxEntries, q.ttlSeconds)
  if kind == "windows" then
    if detail == "duplicate" then
      self.duplicates:Clear()
    elseif detail == "flood" then
      self.flood:Clear()
    end
  elseif kind == "reset" then
    self.duplicates:Clear()
    self.flood:Clear()
    self.quarantine:Clear()
  end
end

function Engine:SetCapabilities(capabilities)
  self.capabilities = capabilities
  if not capabilities.stateful then
    self.duplicates:Clear()
    self.flood:Clear()
  end
  self.cache:Clear()
end

-- Pure rule evaluation plus the single state update for a unique delivery.
-- Order is binding (spec §6). Any error raised here fails open in Deliver.
function Engine:Evaluate(message)
  if type(message) ~= "table" then
    self.counters.invalid = self.counters.invalid + 1
    return allow("INVALID_INPUT")
  end
  local text, author, channel, now = message.text, message.authorKey, message.channelKey, message.now
  if type(text) ~= "string" or type(author) ~= "string" or author == ""
    or type(channel) ~= "string" or channel == "" or not isFiniteNumber(now)
    or #author > LIMITS.maxIdentityBytes or #channel > LIMITS.maxIdentityBytes then
    self.counters.invalid = self.counters.invalid + 1
    return allow("INVALID_INPUT")
  end
  if #text > LIMITS.maxTextBytes then
    -- Not analysed: truncating could create false duplicates or term matches.
    self.counters.oversized = self.counters.oversized + 1
    return allow("INVALID_INPUT")
  end

  local db = self.db
  if not db.enabled then
    return allow("DISABLED")
  end
  if message.eligible ~= true or not db.channels[channel] then
    return allow("OUT_OF_SCOPE")
  end
  if message.isSelf then
    return allow("SELF")
  end
  if db.allowlist[author] then
    return allow("ALLOWLIST")
  end

  local compare, visible = Normalize.Text(text)

  -- State update first, once per unique delivery, regardless of which rule
  -- finally decides (spec §8 "Contabilità").
  local isDuplicate, isFlood = false, false
  if self.capabilities.stateful then
    if db.duplicate.enabled then
      isDuplicate = self.duplicates:Check(author, channel, compare, now, db.duplicate.windowSeconds)
    end
    if db.flood.enabled then
      isFlood = self.flood:Record(author, channel, now, db.flood.windowSeconds, db.flood.maxMessages)
    end
  end

  if db.blocklist[author] then
    return suppress("BLOCKLIST")
  end
  if db.customTerms.enabled then
    local rule = Rules.Match(self.compiledTerms, visible)
    if rule then
      return suppress("CUSTOM_TERM", rule.id, rule.text)
    end
  end
  if isDuplicate then
    return suppress("DUPLICATE", nil, db.duplicate.windowSeconds)
  end
  if isFlood then
    return suppress("FLOOD", nil, db.flood.maxMessages)
  end
  return allow("PASS")
end

function Engine:RecordError(now)
  self.counters.engineErrors = self.counters.engineErrors + 1
  local times, kept = self.errorTimes, {}
  for index = 1, #times do
    if now - times[index] < LIMITS.breakerWindow then
      kept[#kept + 1] = times[index]
    end
  end
  kept[#kept + 1] = now
  self.errorTimes = kept
  if #kept >= LIMITS.breakerErrors and not self.breakerTripped then
    self.breakerTripped = true
    if self.onBreaker then
      pcall(self.onBreaker)
    end
  end
end

-- Manual re-activation (/fcg on) after the breaker tripped.
function Engine:ResetBreaker()
  self.breakerTripped = false
  self.errorTimes = {}
end

-- Whether a suppress decision actually hides the message right now.
function Engine:Hides(decision)
  return decision.action == "suppress" and self.db.enabled and self.db.mode == "filter"
    and self.capabilities.filter == true and not self.breakerTripped
end

-- Entry point for the adapter. Returns hide (boolean) and the decision.
-- message.eventId, when present, must be a verified per-delivery identity:
-- repeated callbacks for it (one per chat window) reuse the first decision
-- and never touch counters or state again.
function Engine:Deliver(message)
  local now = self.clock()
  if self.breakerTripped then
    return false, allow("ENGINE_ERROR")
  end
  if not self.capabilities.analysis then
    return false, allow("DISABLED")
  end

  local eventId = type(message) == "table" and message.eventId or nil
  if eventId ~= nil then
    local cached = self.cache:Get(eventId, now)
    if cached then
      self.counters.cachedCallbacks = self.counters.cachedCallbacks + 1
      return self:Hides(cached.decision), cached.decision
    end
  end

  local ok, decision = pcall(self.Evaluate, self, message)
  if not ok or type(decision) ~= "table" or not Engine.REASONS[decision.reason] then
    self:RecordError(now)
    decision = allow("ENGINE_ERROR")
  end

  local counters = self.counters
  counters.evaluated = counters.evaluated + 1
  local hide = self:Hides(decision)
  if decision.action == "suppress" then
    if hide then
      counters.suppressed = counters.suppressed + 1
    else
      counters.wouldSuppress = counters.wouldSuppress + 1
    end
    self.quarantine:Add({
      hidden = hide,
      reason = decision.reason,
      ruleId = decision.ruleId,
      detail = decision.detail,
      text = message.text,
      authorKey = message.authorKey,
      authorLabel = message.authorLabel or message.authorKey,
      channelKey = message.channelKey,
      channelLabel = message.channelLabel or message.channelKey,
      receivedAt = message.receivedAt,
    }, now)
  else
    counters.allowed = counters.allowed + 1
  end

  if eventId ~= nil then
    self.cache:Put(eventId, { decision = decision }, now)
  end
  return hide, decision
end

function Engine:ResetCounters()
  self.counters = newCounters()
end
