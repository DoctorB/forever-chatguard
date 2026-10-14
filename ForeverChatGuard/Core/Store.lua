-- Bounded in-memory state (spec §8, §10). Nothing here is persisted: every
-- store is rebuilt empty on reload/logout. All times are monotonic seconds.
local _, ns = ...

local Store = {}
ns.Core.Store = Store

local tremove = table.remove

---------------------------------------------------------------------------
-- FIFO queue with O(1) push/pop, used for oldest-first eviction.
---------------------------------------------------------------------------
local Queue = {}
Queue.__index = Queue

local function newQueue()
  return setmetatable({ head = 1, tail = 0, items = {} }, Queue)
end

function Queue:Push(item)
  self.tail = self.tail + 1
  self.items[self.tail] = item
end

function Queue:Peek()
  if self.head > self.tail then return nil end
  return self.items[self.head]
end

function Queue:Pop()
  if self.head > self.tail then return nil end
  local item = self.items[self.head]
  self.items[self.head] = nil
  self.head = self.head + 1
  if self.head > self.tail then
    self.head, self.tail = 1, 0
  end
  return item
end

function Queue:Size()
  return self.tail - self.head + 1
end

---------------------------------------------------------------------------
-- Duplicate windows: author -> channel -> compareText -> firstSeen.
-- Nested tables avoid ambiguous string concatenation of the logical key.
---------------------------------------------------------------------------
local Duplicates = {}
Duplicates.__index = Duplicates

function Store.NewDuplicates(maxKeys)
  local self = setmetatable({}, Duplicates)
  self.maxKeys = maxKeys
  self:Clear()
  return self
end

function Duplicates:Clear()
  self.map = {}
  self.count = 0
  self.queue = newQueue()
end

local function dupGet(map, author, channel, key)
  local byChannel = map[author]
  local byKey = byChannel and byChannel[channel]
  return byKey and byKey[key]
end

local function dupRemove(self, author, channel, key)
  local byChannel = self.map[author]
  local byKey = byChannel and byChannel[channel]
  if not byKey or byKey[key] == nil then return end
  byKey[key] = nil
  self.count = self.count - 1
  if next(byKey) == nil then
    byChannel[channel] = nil
    if next(byChannel) == nil then
      self.map[author] = nil
    end
  end
end

-- Drops expired windows and, if still above the limit, the oldest windows.
-- Queue entries whose firstSeen no longer matches the map are stale and skipped.
function Duplicates:Prune(now, window)
  while true do
    local head = self.queue:Peek()
    if not head then break end
    local current = dupGet(self.map, head.author, head.channel, head.key)
    if current ~= head.firstSeen then
      self.queue:Pop()
    elseif now >= head.firstSeen + window or self.count > self.maxKeys then
      self.queue:Pop()
      dupRemove(self, head.author, head.channel, head.key)
    else
      break
    end
  end
end

-- Returns true when key repeats inside [firstSeen, firstSeen + window).
-- Suppressed repeats never extend the window; at the exact boundary the
-- window has expired and this occurrence opens a new one.
function Duplicates:Check(author, channel, key, now, window)
  local firstSeen = dupGet(self.map, author, channel, key)
  if firstSeen and now < firstSeen + window then
    return true
  end
  local byChannel = self.map[author]
  if not byChannel then
    byChannel = {}
    self.map[author] = byChannel
  end
  local byKey = byChannel[channel]
  if not byKey then
    byKey = {}
    byChannel[channel] = byKey
  end
  if firstSeen == nil then
    self.count = self.count + 1
  end
  byKey[key] = now
  self.queue:Push({ author = author, channel = channel, key = key, firstSeen = now })
  self:Prune(now, window)
  return false
end

---------------------------------------------------------------------------
-- Burst windows: channel -> author -> ascending timestamps in (now-window, now].
---------------------------------------------------------------------------
local Flood = {}
Flood.__index = Flood

function Store.NewFlood(maxAuthorsPerChannel, maxChannels)
  local self = setmetatable({}, Flood)
  self.maxAuthors = maxAuthorsPerChannel
  self.maxChannels = maxChannels
  self:Clear()
  return self
end

function Flood:Clear()
  self.channels = {}
  self.channelCount = 0
end

local function trim(times, cutoff)
  while times[1] and times[1] <= cutoff do
    tremove(times, 1)
  end
end

-- Least recently active key of a table whose values carry .last.
local function oldestKey(map)
  local oldest, oldestLast
  for key, value in pairs(map) do
    if oldestLast == nil or value.last < oldestLast then
      oldest, oldestLast = key, value.last
    end
  end
  return oldest
end

function Flood:Channel(channel, now, window)
  local entry = self.channels[channel]
  if entry then return entry end
  if self.channelCount >= self.maxChannels then
    local victim = oldestKey(self.channels)
    self.channels[victim] = nil
    self.channelCount = self.channelCount - 1
  end
  entry = { authors = {}, count = 0, last = now }
  self.channels[channel] = entry
  self.channelCount = self.channelCount + 1
  return entry
end

function Flood:SweepChannel(entry, now, window)
  local cutoff = now - window
  for author, data in pairs(entry.authors) do
    trim(data.times, cutoff)
    if not data.times[1] then
      entry.authors[author] = nil
      entry.count = entry.count - 1
    end
  end
end

-- Records one unique delivery and returns true when it is the (max+1)-th
-- inside the window. Duplicates are recorded too: they are traffic.
function Flood:Record(author, channel, now, window, maxMessages)
  local entry = self:Channel(channel, now, window)
  local data = entry.authors[author]
  if not data then
    if entry.count >= self.maxAuthors then
      self:SweepChannel(entry, now, window)
      if entry.count >= self.maxAuthors then
        entry.authors[oldestKey(entry.authors)] = nil
        entry.count = entry.count - 1
      end
    end
    data = { times = {}, last = now }
    entry.authors[author] = data
    entry.count = entry.count + 1
  end
  local times = data.times
  trim(times, now - window)
  local isFlood = #times >= maxMessages
  times[#times + 1] = now
  -- Only the latest maxMessages timestamps can ever decide a future result.
  while #times > maxMessages do
    tremove(times, 1)
  end
  data.last, entry.last = now, now
  return isFlood
end

function Flood:AuthorCount(channel)
  local entry = self.channels[channel]
  return entry and entry.count or 0
end

---------------------------------------------------------------------------
-- Decision cache for repeated callbacks of the same delivery.
---------------------------------------------------------------------------
local Cache = {}
Cache.__index = Cache

function Store.NewDecisionCache(maxEntries, ttl)
  local self = setmetatable({}, Cache)
  self.maxEntries, self.ttl = maxEntries, ttl
  self:Clear()
  return self
end

function Cache:Clear()
  self.map = {}
  self.count = 0
  self.queue = newQueue()
end

function Cache:Prune(now)
  while true do
    local head = self.queue:Peek()
    if not head then break end
    local current = self.map[head.id]
    if current ~= head.value then
      self.queue:Pop()
    elseif now - head.value.at >= self.ttl or self.count > self.maxEntries then
      self.queue:Pop()
      self.map[head.id] = nil
      self.count = self.count - 1
    else
      break
    end
  end
end

function Cache:Get(id, now)
  local value = self.map[id]
  if value and now - value.at < self.ttl then
    return value
  end
  return nil
end

function Cache:Put(id, value, now)
  value.at = now
  if self.map[id] == nil then
    self.count = self.count + 1
  end
  self.map[id] = value
  self.queue:Push({ id = id, value = value })
  self:Prune(now)
end

---------------------------------------------------------------------------
-- Session quarantine: newest entries kept, bounded by count and TTL.
---------------------------------------------------------------------------
local Quarantine = {}
Quarantine.__index = Quarantine

Store.QUARANTINE_HARD_MAX = 500

function Store.NewQuarantine(maxEntries, ttl)
  local self = setmetatable({}, Quarantine)
  self.seq = 0
  self:Resize(maxEntries, ttl)
  self:Clear()
  return self
end

function Quarantine:Resize(maxEntries, ttl)
  if maxEntries > Store.QUARANTINE_HARD_MAX then
    maxEntries = Store.QUARANTINE_HARD_MAX
  end
  self.maxEntries, self.ttl = maxEntries, ttl
  if self.queue then
    self:Prune(nil)
  end
end

function Quarantine:Clear()
  self.queue = newQueue()
  self.bySeq = {}
end

function Quarantine:Prune(now)
  while true do
    local head = self.queue:Peek()
    if not head then break end
    local expired = now ~= nil and now - head.now >= self.ttl
    if expired or self.queue:Size() > self.maxEntries then
      self.queue:Pop()
      self.bySeq[head.seq] = nil
    else
      break
    end
  end
end

function Quarantine:Add(entry, now)
  self.seq = self.seq + 1
  entry.seq = self.seq
  entry.now = now
  self.queue:Push(entry)
  self.bySeq[entry.seq] = entry
  self:Prune(now)
  return entry
end

function Quarantine:Get(seq)
  return self.bySeq[seq]
end

-- Newest first.
function Quarantine:List(now)
  if now then
    self:Prune(now)
  end
  local result, q = {}, self.queue
  for index = q.tail, q.head, -1 do
    result[#result + 1] = q.items[index]
  end
  return result
end

function Quarantine:Size()
  return self.queue:Size()
end
