-- Reproducible engine benchmark (spec §15): lua5.1 tests/bench.lua [events]
-- Engine only (no client). Deterministic synthetic traffic: 400 authors,
-- 4 channels, ~25% exact repeats, all rules enabled, filter mode.
-- os.clock() is too coarse for single events, so time is measured over
-- batches of BATCH events; percentiles are over per-event batch averages.

local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]bench%.lua$") or "."
T = { ROOT = ROOT, ADDON_DIR = ROOT .. "/ForeverChatGuard" }

local function tocEntries()
  local handle = assert(io.open(T.ADDON_DIR .. "/ForeverChatGuard.toc", "rb"))
  local toc = handle:read("*a")
  handle:close()
  local entries = {}
  for line in (toc .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    if line:match("%S") and not line:match("^#") then entries[#entries + 1] = line end
  end
  return entries
end

local ns = {}
for _, entry in ipairs(tocEntries()) do
  assert(loadfile(T.ADDON_DIR .. "/" .. entry))("ForeverChatGuard", ns)
end

local EVENTS = tonumber(arg and arg[1]) or 10000
local BATCH = 100
local Core = ns.Core
local db = Core.Defaults.NewDB()
db.mode = "filter"
db.flood.enabled = true
db.customTerms.enabled = true
for index = 1, 20 do
  db.customTerms.list[index] = { id = index, text = "term" .. index, enabled = true }
end
local channels = { "zone:1", "zone:2", "zone:22", "zone:26" }
for _, key in ipairs(channels) do db.channels[key] = key end

local now = 0
local engine = Core.Engine.New({ db = db, clock = function() return now end })

-- Deterministic LCG so every run sees identical traffic.
local seed = 12345
local function rand(n)
  seed = (seed * 16807) % 2147483647 -- products stay below 2^53: exact in doubles
  return seed % n + 1
end

local texts = {}
for index = 1, 500 do
  texts[index] = "WTS |cffa335ee|Hitem:" .. (19000 + index) .. "::::::::60:::::|h[Item " .. index
    .. "]|h|r for " .. index .. "g, whisper me. LFG/LFM Città " .. string.rep("x", index % 40)
end

collectgarbage("collect")
local baseMemory = collectgarbage("count")
local peakMemory = baseMemory
local batchTimes = {}
local startAll = os.clock()
local message = {}
for batch = 1, math.ceil(EVENTS / BATCH) do
  local t0 = os.clock()
  for i = 1, BATCH do
    local n = (batch - 1) * BATCH + i
    if n > EVENTS then break end
    now = now + 0.05
    local textIndex = rand(4) == 1 and 1 + (n % 7) or rand(#texts)
    message = {
      event = "CHAT_MSG_CHANNEL", eventId = "CHAT_MSG_CHANNEL:" .. n,
      authorKey = "Author" .. rand(400) .. "-Realm", channelKey = channels[rand(#channels)],
      text = texts[textIndex], now = now, isSelf = false, eligible = true,
    }
    engine:Deliver(message)
    -- Two extra chat windows per delivery (cached callbacks).
    engine:Deliver(message)
    engine:Deliver(message)
  end
  batchTimes[#batchTimes + 1] = (os.clock() - t0) / BATCH * 1000
  local memory = collectgarbage("count")
  if memory > peakMemory then peakMemory = memory end
end
local total = os.clock() - startAll

table.sort(batchTimes)
local function percentile(p)
  return batchTimes[math.max(1, math.ceil(#batchTimes * p))]
end
local c = engine.counters
print(string.format("runtime: %s", _VERSION))
print(string.format("events: %d unique deliveries x3 callbacks, batches of %d", EVENTS, BATCH))
print(string.format("total: %.3f s, mean %.4f ms/event", total, total / EVENTS * 1000))
print(string.format("batch-mean ms/event: p50 %.4f  p95 %.4f  max %.4f", percentile(0.5), percentile(0.95), batchTimes[#batchTimes]))
print(string.format("memory: base %.0f KiB, peak %.0f KiB (Lua heap, collectgarbage)", baseMemory, peakMemory))
print(string.format("decisions: evaluated %d, allowed %d, hidden %d, cached %d",
  c.evaluated, c.allowed, c.suppressed, c.cachedCallbacks))
print(string.format("state: duplicate keys %d, cache %d, quarantine %d",
  engine.duplicates.count, engine.cache.count, engine.quarantine:Size()))
local budgetOk = percentile(0.95) < 1
print("budget p95 < 1 ms/event: " .. (budgetOk and "met" or "NOT met"))
os.exit(budgetOk and 0 or 1)
