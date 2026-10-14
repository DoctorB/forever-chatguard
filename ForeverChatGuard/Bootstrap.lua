-- Forever ChatGuard: namespace bootstrap.
-- Every file receives (addonName, ns) from the client loader; the offline test
-- runner reproduces the same contract. No globals are created here.
local addonName, ns = ...

ns.ADDON_NAME = addonName or "ForeverChatGuard"
ns.VERSION = "0.1.0-alpha.1"

-- Session-wide placeholders filled by later files in TOC order.
ns.Core = ns.Core or {}
ns.UI = ns.UI or {}
ns.Adapters = ns.Adapters or {}

-- Local output only: never routed through a filterable chat event.
function ns.Print(message)
  local frame = ns.outputFrame
  if not frame and type(DEFAULT_CHAT_FRAME) == "table" then
    frame = DEFAULT_CHAT_FRAME
  end
  local line = "|cff66bbffChatGuard|r: " .. tostring(message)
  if frame and type(frame.AddMessage) == "function" then
    frame:AddMessage(line)
  elseif type(print) == "function" then
    print(line)
  end
end
