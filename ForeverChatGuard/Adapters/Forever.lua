-- Client adapter for WoW Forever (spec §3, §12).
--
-- Everything client-specific lives here. Each capability is detected at
-- runtime AND must be marked verified in COMPAT (docs/compatibility.md)
-- before it can change what the player sees. Unverified paths only observe.
local _, ns = ...

local Normalize = ns.Core.Normalize
local Config = ns.Core.Config
local Engine = ns.Core.Engine
local Defaults = ns.Core.Defaults

local Adapter = {}
Adapter.__index = Adapter
ns.Adapters.Forever = Adapter

-- In-game evidence recorded in docs/compatibility.md. Only flip a flag to
-- true together with the evidence; tests assert both stay in sync.
Adapter.COMPAT = {
  build = "1.60.1.70338",
  interface = 16001,
  verified = {
    filterApi = false,       -- ChatFrame message filter: exists, signature, hide semantics
    payload = false,         -- CHAT_MSG_* argument layout and readability (not secret)
    lineId = false,          -- per-delivery identity shared by all chat-window callbacks
    eventFrame = false,      -- RegisterEvent delivery of CHAT_MSG_* to an addon frame
  },
}

-- Public scopes ChatGuard may analyse. Everything else (whispers, party,
-- raid, guild, system, combat) is never registered and never filtered.
Adapter.EVENTS = {
  CHAT_MSG_CHANNEL = "channel",
  CHAT_MSG_SAY = "say",
  CHAT_MSG_YELL = "yell",
}

local LIMITS = Defaults.LIMITS

local function isSecret(env, value)
  local check = env.issecretvalue
  if type(check) == "function" then
    local ok, secret = pcall(check, value)
    return not ok or secret == true
  end
  return false
end

function Adapter.New(env, engine, store)
  local self = setmetatable({}, Adapter)
  self.env = env
  self.engine = engine
  self.store = store
  self.seenChannels = {}   -- key -> label, session only
  self.seenOrder = {}
  self.filterRegistered = false
  self.eventFrameRegistered = false
  self.notices = {}
  self:DetectCapabilities()
  return self
end

-- Resolves candidate APIs. Existence alone never enables filtering.
function Adapter:DetectCapabilities()
  local env = self.env
  local add, remove
  if type(env.ChatFrame_AddMessageEventFilter) == "function" then
    add, remove = env.ChatFrame_AddMessageEventFilter, env.ChatFrame_RemoveMessageEventFilter
  elseif type(env.ChatFrameUtil) == "table" and type(env.ChatFrameUtil.AddMessageEventFilter) == "function" then
    local util = env.ChatFrameUtil
    add = function(event, fn) return util.AddMessageEventFilter(event, fn) end
    if type(util.RemoveMessageEventFilter) == "function" then
      remove = function(event, fn) return util.RemoveMessageEventFilter(event, fn) end
    end
  end
  if type(remove) ~= "function" then
    remove = nil
  end
  local verified = Adapter.COMPAT.verified
  local canFrame = type(env.CreateFrame) == "function"
  local hasFilter = add ~= nil and remove ~= nil
  self.api = { addFilter = add, removeFilter = remove }
  self.caps = {
    filterApiPresent = hasFilter,
    -- Filter mode: verified filter + verified payload are both required.
    filter = hasFilter and verified.filterApi and verified.payload,
    -- Observation: a read path must exist.
    analysis = (hasFilter or canFrame) and true or false,
    observeViaFrame = canFrame,
    lineIdVerified = verified.lineId,
  }
  return self.caps
end

-- Stateful rules need one evaluation per delivery. An event frame gets one
-- OnEvent per event; filter callbacks run once per chat window and therefore
-- need a verified line identity.
function Adapter:EngineCapabilities()
  local useFilter = self:UsesFilter()
  return {
    analysis = self.caps.analysis,
    filter = self.caps.filter,
    stateful = (not useFilter) or self.caps.lineIdVerified,
  }
end

function Adapter:UsesFilter()
  return self.caps.filter and self.store.db.mode == "filter"
end

function Adapter:PlayerKey()
  if self.playerKey then return self.playerKey end
  local env = self.env
  local name = type(env.UnitName) == "function" and env.UnitName("player") or nil
  local realm = self:Realm()
  if type(name) == "string" and not isSecret(env, name) and realm then
    self.playerKey = name .. "-" .. realm
  end
  return self.playerKey
end

function Adapter:Realm()
  local env = self.env
  local fn = env.GetNormalizedRealmName
  if type(fn) == "function" then
    local ok, realm = pcall(fn)
    if ok and type(realm) == "string" and realm ~= "" and not isSecret(env, realm) then
      return realm
    end
  end
  return nil
end

-- Name or Name-Realm -> Name-Realm. Realm-less names get the player's realm.
function Adapter:QualifyName(name)
  if type(name) ~= "string" then return nil end
  name = Normalize.Identity(name, LIMITS.maxIdentityBytes)
  if not name or string.find(name, "[%s|]") then return nil end
  if string.find(name, "-", 1, true) then
    return name
  end
  local realm = self:Realm()
  return realm and (name .. "-" .. realm) or nil
end

function Adapter:RememberChannel(key, label)
  if not self.seenChannels[key] then
    if #self.seenOrder >= LIMITS.maxChannels then return end
    self.seenOrder[#self.seenOrder + 1] = key
  end
  self.seenChannels[key] = label
end

function Adapter:ChannelList()
  local L = ns.L
  local result = {
    { key = "say", label = L.CHANNEL_SAY },
    { key = "yell", label = L.CHANNEL_YELL },
  }
  for index = 1, #self.seenOrder do
    local key = self.seenOrder[index]
    result[#result + 1] = { key = key, label = self.seenChannels[key] }
  end
  -- Selected channels not seen this session are still listed.
  for key, label in pairs(self.store.db.channels) do
    local listed = false
    for index = 1, #result do
      if result[index].key == key then listed = true break end
    end
    if not listed then
      result[#result + 1] = { key = key, label = label }
    end
  end
  for index = 1, #result do
    result[index].selected = self.store.db.channels[result[index].key] ~= nil
  end
  return result
end

-- Builds the engine message from a CHAT_MSG_* payload. Candidate layout
-- (modern client): text, author, language, channelName, author2, flags,
-- zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid.
-- Returns nil when anything needed is missing or secret.
function Adapter:BuildMessage(event, ...)
  local scope = Adapter.EVENTS[event]
  local env = self.env
  local text, author = ...
  local zoneChannelID = select(7, ...)
  local channelBaseName = select(9, ...)
  local lineID = select(11, ...)
  local guid = select(12, ...)

  if isSecret(env, text) or isSecret(env, author) or isSecret(env, zoneChannelID)
    or isSecret(env, channelBaseName) or isSecret(env, lineID) or isSecret(env, guid) then
    self.engine.counters.unreadable = self.engine.counters.unreadable + 1
    return nil
  end
  if type(text) ~= "string" or type(author) ~= "string" then
    return nil
  end

  local channelKey, channelLabel
  if scope == "channel" then
    if type(zoneChannelID) == "number" and zoneChannelID > 0 then
      channelKey = "zone:" .. zoneChannelID
    elseif type(channelBaseName) == "string" and channelBaseName ~= "" then
      channelKey = "custom:" .. Normalize.LowerASCII(channelBaseName)
    end
    channelLabel = type(channelBaseName) == "string" and channelBaseName ~= "" and channelBaseName or channelKey
  elseif scope then
    channelKey = scope
    channelLabel = scope == "say" and ns.L.CHANNEL_SAY or ns.L.CHANNEL_YELL
  end
  channelKey = channelKey and Normalize.Identity(channelKey, LIMITS.maxIdentityBytes)
  if channelKey and scope == "channel" then
    self:RememberChannel(channelKey, Normalize.Identity(channelLabel, LIMITS.maxIdentityBytes) or channelKey)
  end

  local authorKey = self:QualifyName(author)
  local playerGuid = type(env.UnitGUID) == "function" and env.UnitGUID("player") or nil
  local isSelf = (authorKey ~= nil and authorKey == self:PlayerKey())
    or (type(guid) == "string" and guid ~= "" and guid == playerGuid and not isSecret(env, playerGuid))

  local eventId
  if self.caps.lineIdVerified and type(lineID) == "number" then
    eventId = event .. ":" .. lineID
  end

  return {
    event = event,
    eventId = eventId,
    authorKey = authorKey or "",
    authorLabel = author,
    channelKey = channelKey or "",
    channelLabel = channelLabel,
    text = text,
    now = self.engine.clock(),
    isSelf = isSelf and true or false,
    eligible = scope ~= nil and channelKey ~= nil,
    receivedAt = type(env.date) == "function" and env.date("%H:%M:%S") or nil,
  }
end

-- Shared evaluation; never raises. Returns whether to hide.
function Adapter:Handle(event, ...)
  local ok, hide = pcall(function(...)
    local message = self:BuildMessage(event, ...)
    if not message then return false end
    local result = self.engine:Deliver(message)
    return result
  end, ...)
  return ok and hide == true
end

-- Filter callback. Returning plain false (no further values) tells the
-- client to keep the original arguments untouched, nils included.
function Adapter:FilterCallback()
  if not self.filterFn then
    self.filterFn = function(_, event, ...)
      if self:Handle(event, ...) then
        return true
      end
      return false
    end
  end
  return self.filterFn
end

-- Idempotent: repeated calls never stack registrations.
function Adapter:RegisterPaths()
  local useFilter = self:UsesFilter()
  if useFilter and not self.filterRegistered then
    local fn = self:FilterCallback()
    for event in pairs(Adapter.EVENTS) do
      self.api.addFilter(event, fn)
    end
    self.filterRegistered = true
  elseif not useFilter and self.filterRegistered then
    self:UnregisterFilter()
  end

  local useFrame = not useFilter and self.caps.observeViaFrame
  if useFrame and not self.eventFrameRegistered then
    if not self.frame then
      self.frame = self.env.CreateFrame("Frame")
      self.frame:SetScript("OnEvent", function(_, event, ...)
        self:Handle(event, ...)
      end)
    end
    for event in pairs(Adapter.EVENTS) do
      self.frame:RegisterEvent(event)
    end
    self.eventFrameRegistered = true
  elseif not useFrame and self.eventFrameRegistered then
    for event in pairs(Adapter.EVENTS) do
      self.frame:UnregisterEvent(event)
    end
    self.eventFrameRegistered = false
  end
  self.engine:SetCapabilities(self:EngineCapabilities())
end

function Adapter:UnregisterFilter()
  if self.filterRegistered and self.api.removeFilter then
    for event in pairs(Adapter.EVENTS) do
      self.api.removeFilter(event, self.filterFn)
    end
  end
  self.filterRegistered = false
end

function Adapter:CompatibilityLabel()
  local L = ns.L
  if not self.caps.analysis then
    return L.COMPAT_UNAVAILABLE
  end
  if self.caps.filter and self.caps.lineIdVerified then
    return L.COMPAT_VERIFIED
  end
  return L.COMPAT_UNVERIFIED
end

---------------------------------------------------------------------------
-- Lifecycle: ADDON_LOADED -> settings, engine, adapter, UI.
---------------------------------------------------------------------------
local SAVED = "ForeverChatGuardDB"

function Adapter.Start(env)
  local raw = env[SAVED]
  local db, status = Config.Load(raw)
  -- A newer schema is left untouched on disk: the in-memory copy is used
  -- (disabled) and never assigned back to the saved variable.
  if not status.futureSchema then
    env[SAVED] = db
  end
  local store = Config.NewStore(db, { readOnly = status.futureSchema })
  local clock = env.GetTime
  local engine = Engine.New({
    db = db,
    clock = clock,
    onBreaker = function() ns.Print(ns.L.STATUS_BREAKER) end,
  })
  local adapter = Adapter.New(env, engine, store)
  store:OnChange(function(kind, detail)
    engine:OnConfigChanged(kind, detail)
    if kind == "mode" or kind == "reset" then
      adapter:RegisterPaths()
    end
  end)
  adapter:RegisterPaths()

  ns.runtime = { db = db, store = store, engine = engine, adapter = adapter, status = status }

  if status.futureSchema then
    ns.Print(ns.L.STATUS_FUTURE_SCHEMA)
  elseif status.corrupt then
    ns.Print(ns.L.STATUS_CORRUPT)
  end
  if not adapter.caps.analysis then
    ns.Print(ns.L.STATUS_NO_FILTER_API)
  end
  if db.mode == "filter" and not adapter.caps.filter then
    ns.Print(ns.L.STATUS_FILTER_NEEDS_CAPABILITY)
  end
  if ns.UI.Commands and ns.UI.Commands.Register then
    ns.UI.Commands.Register(env)
  end
  return ns.runtime
end

-- Client bootstrap. Skipped by the offline test runner (no CreateFrame).
if type(CreateFrame) == "function" and type(_G) == "table" then
  local loader = CreateFrame("Frame")
  loader:RegisterEvent("ADDON_LOADED")
  loader:SetScript("OnEvent", function(frame, _, name)
    if name ~= ns.ADDON_NAME then return end
    frame:UnregisterEvent("ADDON_LOADED")
    local ok, err = pcall(Adapter.Start, _G)
    if not ok then
      ns.Print("startup failed; chat is unchanged (" .. tostring(err) .. ")")
    end
  end)
end
