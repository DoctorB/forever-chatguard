-- Geometry of the settings and quarantine windows against a mock widget API.
-- Text height is estimated (average glyph width), so these checks prove the
-- layout rules (column alignment, no overlap, inside the frame), not pixels.

local GLYPH, LINE = { small = 5.6, normal = 6.6 }, { small = 12, normal = 14 }

local function newUI()
  local ui = { regions = {} }
  local function region(kind, parent, template)
    local r = { kind = kind, parent = parent, template = template, w = 0, h = 0, shown = true, scripts = {} }
    ui.regions[#ui.regions + 1] = r
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetWidth(w) self.w = w end
    function r:SetHeight(h) self.h = h end
    function r:GetWidth() return self.w end
    function r:ClearAllPoints() self.point = nil end
    function r:SetPoint(p, rel, relP, x, y)
      if type(rel) == "number" then rel, relP, x, y = parent, p, rel, relP end
      self.point = { p, rel or parent, relP or p, x or 0, y or 0 }
    end
    function r:SetText(t) self.text = t end
    function r:GetText() return self.text end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:GetStringHeight()
      local size = (self.template or ""):find("Small") and "small" or "normal"
      local lines = 0
      for piece in ((self.text or "") .. "\n"):gmatch("([^\n]*)\n") do
        lines = lines + math.max(1, math.ceil(#piece * GLYPH[size] / math.max(self.w, 1)))
      end
      return lines * LINE[size]
    end
    function r:CreateFontString(_, _, tpl) return region("FontString", self, tpl) end
    for _, name in ipairs({ "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetSpacing", "SetMaxLines",
      "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "SetFrameStrata",
      "SetAutoFocus", "SetMaxBytes", "ClearFocus", "SetChecked", "SetEnabled", "StartMoving",
      "StopMovingOrSizing", "Click" }) do
      r[name] = r[name] or function() end
    end
    function r:GetChecked() return false end
    if template == "BasicFrameTemplateWithInset" then
      r.TitleText = region("FontString", r, "GameFontNormal")
    end
    return r
  end
  ui.CreateFrame = function(kind, _, parent, template)
    local r = region(kind, parent, template)
    if template == "UIPanelButtonTemplate" or template == "UICheckButtonTemplate" then
      r.w, r.h = 26, 26
    end
    return r
  end
  return ui
end

-- Absolute TOPLEFT (x right, y down) of a region inside its top frame.
local function absolute(r, frame)
  if r == frame or not r.point then return 0, 0 end
  local p, rel, relP, x, y = unpack(r.point)
  local rx, ry = absolute(rel, frame)
  local relW, relH = rel.w, rel.h
  local ax = rx + x + (relP:find("RIGHT") and relW or 0)
  local ay = ry - y + (relP:find("BOTTOM") and relH or 0)
  local h = r.kind == "FontString" and r:GetStringHeight() or r.h
  if p:find("RIGHT") then ax = ax - r.w end
  if p:find("BOTTOM") then ay = ay - h end
  if p == "LEFT" or p == "RIGHT" then ay = ay - h / 2 + (relP == "LEFT" or relP == "RIGHT" and relH / 2 or 0) end
  return ax, ay
end

local function boxes(ui, frame)
  local list = {}
  for _, r in ipairs(ui.regions) do
    local visible, node = r.shown, r.parent
    while visible and node and node ~= frame do
      visible, node = node.shown, node.parent
    end
    if visible and r ~= frame and r.point and r ~= frame.TitleText and (r.kind ~= "FontString" or (r.text or "") ~= "") then
      local x, y = absolute(r, frame)
      local h = r.kind == "FontString" and r:GetStringHeight() or r.h
      list[#list + 1] = { r = r, x = x, y = y, w = r.w, h = h }
    end
  end
  return list
end

local function overlaps(a, b)
  return a.x < b.x + b.w - 0.5 and b.x < a.x + a.w - 0.5 and a.y < b.y + b.h - 0.5 and b.y < a.y + a.h - 0.5
end

local function describe(b)
  return string.format("%s %q at %.0f,%.0f %.0fx%.0f", b.r.kind, tostring(b.r.text or b.r.template), b.x, b.y, b.w, b.h)
end

local function runtimeWith(ns, configure)
  local env = {
    GetTime = function() return 10 end,
    GetNormalizedRealmName = function() return "Realm" end,
    UnitName = function() return "Me" end,
    CreateFrame = function() return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end } end,
    SlashCmdList = {},
  }
  local runtime = ns.Adapters.Forever.Start(env)
  if configure then configure(runtime) end
  return runtime
end

local function checkLayout(locale, configure)
  local ui = newUI()
  local ns = T.LoadAddon({ locale = locale })
  local runtime = runtimeWith(ns, configure)
  local saved = { CreateFrame = CreateFrame, UIParent = UIParent, UISpecialFrames = UISpecialFrames }
  CreateFrame, UIParent, UISpecialFrames = ui.CreateFrame, { w = 1920, h = 1080 }, {}
  local ok, err = pcall(function()
    ns.UI.Panel.Build(runtime)
    ns.UI.Panel.Refresh()
  end)
  CreateFrame, UIParent, UISpecialFrames = saved.CreateFrame, saved.UIParent, saved.UISpecialFrames
  T.Ok(ok, tostring(err))
  local frame = ns.UI.Panel.frame
  local list = boxes(ui, frame)
  T.Ok(#list > 20, "panel populated")
  for _, b in ipairs(list) do
    T.Ok(b.x >= 12 and b.x + b.w <= frame.w - 12, "outside horizontally: " .. describe(b))
    T.Ok(b.y >= 28 and b.y + b.h <= frame.h - 8, "outside vertically: " .. describe(b))
  end
  for i = 1, #list do
    for j = i + 1, #list do
      T.NotOk(overlaps(list[i], list[j]), "overlap: " .. describe(list[i]) .. " / " .. describe(list[j]))
    end
  end
  -- Every rule checkbox sits in one column (no staircase).
  local column
  for _, toggle in ipairs(frame.widgets.toggles) do
    local x = absolute(toggle.check, frame)
    column = column or x
    T.Eq(x, column, "rule checkboxes aligned")
  end
  return frame
end

T.Case("settings panel: aligned, inside the frame, no overlap (English)", function()
  checkLayout(nil)
end)

T.Case("settings panel: same guarantees with Italian strings", function()
  checkLayout("itIT")
end)

T.Case("settings panel grows with channels, terms and authors", function()
  local small = checkLayout(nil).h
  local big = checkLayout(nil, function(runtime)
    for index = 1, 10 do runtime.adapter:RememberChannel("custom:c" .. index, "Channel number " .. index) end
    for index = 1, 15 do runtime.store:AddTerm("term number " .. index) end
    for index = 1, 12 do runtime.store:SetListed("allowlist", "Player" .. index .. "-Realm", true) end
  end)
  T.Ok(big.h > small, "frame height follows content")
end)

T.Case("quarantine window: rows and buttons stay inside, empty notice shown", function()
  local ui = newUI()
  local ns = T.LoadAddon()
  local runtime = runtimeWith(ns, function(rt)
    rt.store:SelectChannel("say", "Say")
    rt.store:SetListed("blocklist", "Bob-Realm", true)
  end)
  local saved = { CreateFrame = CreateFrame, UIParent = UIParent, UISpecialFrames = UISpecialFrames }
  CreateFrame, UIParent, UISpecialFrames = ui.CreateFrame, { w = 1920, h = 1080 }, {}
  local ok, err = pcall(function()
    T.Ok(ns.UI.Quarantine.Show(runtime))
    T.Ok(ns.UI.Quarantine.frame.empty.shown, "empty notice")
    for index = 1, 11 do
      runtime.engine:Deliver({ authorKey = "Bob-Realm", authorLabel = "Bob", channelKey = "say", channelLabel = "Say",
        text = string.rep("long message " .. index .. " ", 20), now = 10, eligible = true, receivedAt = "12:00:00" })
    end
    ns.UI.Quarantine.Refresh()
  end)
  CreateFrame, UIParent, UISpecialFrames = saved.CreateFrame, saved.UIParent, saved.UISpecialFrames
  T.Ok(ok, tostring(err))
  local frame = ns.UI.Quarantine.frame
  T.NotOk(frame.empty.shown)
  T.Eq(frame.page.text, "1-8 of 11")
  for _, b in ipairs(boxes(ui, frame)) do
    T.Ok(b.x >= 12 and b.x + b.w <= frame.w - 12, "outside horizontally: " .. describe(b))
    T.Ok(b.y >= 28 and b.y + b.h <= frame.h - 8, "outside vertically: " .. describe(b))
  end
end)
