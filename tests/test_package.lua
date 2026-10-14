-- Static checks over the addon tree: TOC manifest, locales, globals, metadata.

local entries, fields = T.TocEntries()

T.Case("TOC fields present and version consistent", function()
  T.Eq(fields.Title, "Forever ChatGuard")
  T.Ok(fields.Interface and fields.Interface:match("^%d+$"), "numeric Interface")
  T.Eq(fields.SavedVariables, "ForeverChatGuardDB")
  local ns = T.LoadAddon()
  T.Eq(fields.Version, ns.VERSION)
  local changelog = T.ReadFile(T.ROOT .. "/CHANGELOG.md")
  T.Ok(changelog:find("## " .. fields.Version, 1, true), "CHANGELOG section for " .. fields.Version)
end)

T.Case("TOC entries exist, are unique and cover every Lua file", function()
  local seen = {}
  for _, entry in ipairs(entries) do
    T.NotOk(seen[entry], "duplicate " .. entry)
    seen[entry] = true
    T.Ok(io.open(T.ADDON_DIR .. "/" .. entry, "rb"), "missing " .. entry)
  end
  local listing = io.popen((package.config:sub(1, 1) == "\\" and "dir /s /b " or "find ")
    .. '"' .. T.ADDON_DIR .. '"')
  for path in listing:lines() do
    path = path:gsub("\\", "/")
    local relative = path:match("ForeverChatGuard/(.+%.lua)$")
    if relative then
      T.Ok(seen[relative], "Lua file not in TOC: " .. relative)
    end
  end
  listing:close()
end)

T.Case("load order: bootstrap, locales, core, adapter, UI", function()
  local order = {}
  for index, entry in ipairs(entries) do order[entry] = index end
  T.Eq(order["Bootstrap.lua"], 1)
  T.Ok(order["Locale/enUS.lua"] < order["Locale/itIT.lua"])
  T.Ok(order["Locale/itIT.lua"] < order["Core/Defaults.lua"])
  T.Ok(order["Core/Normalize.lua"] < order["Core/Config.lua"])
  T.Ok(order["Core/Engine.lua"] < order["Adapters/Forever.lua"])
  T.Ok(order["Adapters/Forever.lua"] < order["UI/Commands.lua"])
  T.Ok(order["UI/Commands.lua"] < order["UI/Panel.lua"])
end)

T.Case("every Italian key exists in English", function()
  local en = T.LoadAddon().LocaleBase
  local source = T.ReadFile(T.ADDON_DIR .. "/Locale/itIT.lua")
  for key in source:gmatch("\n  ([A-Z_]+) = ") do
    T.Ok(en[key] ~= nil, "itIT key missing in enUS: " .. key)
  end
end)

T.Case("loading the addon creates no global variables", function()
  local before = {}
  for key in pairs(_G) do before[key] = true end
  T.LoadAddon()
  for key in pairs(_G) do
    T.Ok(before[key], "global leaked: " .. tostring(key))
  end
end)

T.Case("no require, io, os or network use in addon code", function()
  for _, entry in ipairs(entries) do
    local source = T.ReadFile(T.ADDON_DIR .. "/" .. entry)
    for _, forbidden in ipairs({ "require%s*%(", "io%.", "os%.", "loadstring", "SendChatMessage", "http" }) do
      T.NotOk(source:find(forbidden), forbidden .. " in " .. entry)
    end
  end
end)

T.Case("no AI tool attribution in distributed metadata", function()
  local packaged = { "ForeverChatGuard.toc" }
  for _, entry in ipairs(entries) do packaged[#packaged + 1] = entry end
  for _, file in ipairs(packaged) do
    local source = T.ReadFile(T.ADDON_DIR .. "/" .. file):lower()
    for _, word in ipairs({ "claude", "anthropic", "co-authored-by", "generated with" }) do
      T.NotOk(source:find(word, 1, true), word .. " in " .. file)
    end
  end
  T.Eq(fields.Author, "DoctorB")
end)

T.Case("every EditBox disables auto-focus right after creation", function()
  local files = { "tools/ForeverChatGuardProbe/Probe.lua" }
  for _, entry in ipairs(entries) do files[#files + 1] = "ForeverChatGuard/" .. entry end
  for _, file in ipairs(files) do
    local source = T.ReadFile(T.ROOT .. "/" .. file)
    local position = 1
    while true do
      local start, finish = source:find('CreateFrame%(%s*"EditBox"', position)
      if not start then
        start, finish = source:find('"EditBox"', position, true)
        if not start then break end
      end
      local after = source:sub(finish, finish + 400)
      T.Ok(after:find("SetAutoFocus(false)", 1, true), "EditBox without SetAutoFocus(false) in " .. file)
      position = finish + 1
    end
  end
end)
