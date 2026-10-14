-- Synthetic fixtures and a simulated clock. No private conversations:
-- every text below is invented for the tests.
local F = {}
T.F = F

F.TRADE = "zone:2"
F.GENERAL = "zone:1"
F.ALICE = "Alice-Realm"
F.BOB = "Bob-Realm"
F.ALICE_OTHER_REALM = "Alice-OtherRealm"

F.ITEM_A = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
F.ITEM_B = "|cffa335ee|Hitem:99999::::::::60:::::|h[Thunderfury]|h|r"
F.UTF8 = "Vendo pozioni a prezzo onesto, città: Undercity — più info in sussurro ✓"
F.MALFORMED = "|cffzz broken |H no end |h |T Interface\\Icon:0|t ||c literal |"

function F.Clock(start)
  local clock = { t = start or 1000 }
  function clock.now() return clock.t end
  function clock.advance(seconds) clock.t = clock.t + seconds end
  return clock
end

-- Fresh addon namespace + engine with selected channels.
function F.Engine(options)
  options = options or {}
  local ns = T.LoadAddon({ locale = options.locale })
  local Core = ns.Core
  local db = Core.Defaults.NewDB()
  db.channels[F.TRADE] = "Trade"
  db.channels[F.GENERAL] = "General"
  if options.configure then options.configure(db) end
  local clock = F.Clock(options.start)
  local store = Core.Config.NewStore(db)
  local engine = Core.Engine.New({
    db = db,
    clock = clock.now,
    capabilities = options.capabilities or { analysis = true, filter = true, stateful = true },
    onBreaker = options.onBreaker,
  })
  store:OnChange(function(kind, detail) engine:OnConfigChanged(kind, detail) end)
  return { ns = ns, db = db, engine = engine, store = store, clock = clock }
end

local nextLine = 0

-- A unique delivery. fields override defaults.
function F.Message(ctx, fields)
  nextLine = nextLine + 1
  local message = {
    event = "CHAT_MSG_CHANNEL",
    eventId = "CHAT_MSG_CHANNEL:" .. nextLine,
    authorKey = F.ALICE,
    channelKey = F.TRADE,
    text = "WTS mats, cheap",
    now = ctx.clock.now(),
    isSelf = false,
    eligible = true,
  }
  for key, value in pairs(fields or {}) do
    message[key] = value
  end
  if fields and fields.eventId == false then
    message.eventId = nil
  end
  return message
end

function F.Deliver(ctx, fields)
  local message = F.Message(ctx, fields)
  local hide, decision = ctx.engine:Deliver(message)
  return decision, hide, message
end
