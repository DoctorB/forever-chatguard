local F = T.F
local ns = T.LoadAddon()
local N = ns.Core.Normalize
local Rules = ns.Core.Rules

T.Case("ASCII lowercase only; non-ASCII bytes untouched", function()
  T.Eq(N.LowerASCII("ÀBC Città ÉÈ"), "Àbc città ÉÈ")
end)

T.Case("whitespace collapsed and trimmed", function()
  local compare, visible = N.Text("  WTS \t  Mats\n\nnow  ")
  T.Eq(compare, "wts mats now")
  T.Eq(visible, "wts mats now")
end)

T.Case("prices and digits preserved: 10g vs 100g differ", function()
  local a = N.Text("selling for 10g")
  local b = N.Text("selling for 100g")
  T.Ok(a ~= b)
  T.Eq(a, "selling for 10g")
end)

T.Case("punctuation preserved", function()
  T.Eq((N.Text("Hi!!! 5% off, (only) today?")), "hi!!! 5% off, (only) today?")
end)

T.Case("validated colour markup removed; text kept", function()
  local compare = N.Text("|cff00ff00Green|r text")
  T.Eq(compare, "green text")
end)

T.Case("different items with the same label are not equal", function()
  local a = N.Text("WTS " .. F.ITEM_A)
  local b = N.Text("WTS " .. F.ITEM_B)
  T.Ok(a ~= b, "link identity must be kept")
  local _, visA = N.Text("WTS " .. F.ITEM_A)
  local _, visB = N.Text("WTS " .. F.ITEM_B)
  T.Eq(visA, "wts [thunderfury]")
  T.Eq(visA, visB, "visible copies hold labels only")
end)

T.Case("same link twice compares equal", function()
  T.Eq((N.Text("x " .. F.ITEM_A)), (N.Text("X  " .. F.ITEM_A)))
end)

T.Case("encoding is unambiguous for control bytes in plain text", function()
  local fake = "\2" .. "6:item:1" .. "6:[sword]"
  local real = "|Hitem:1|h[Sword]|h"
  T.Ok(N.Text(fake) ~= N.Text(real))
end)

T.Case("malformed markup does not crash and keeps literal characters", function()
  local compare, visible = N.Text(F.MALFORMED)
  T.Eq(type(compare), "string")
  T.Ok(visible:find("|cffzz", 1, true), "invalid colour kept literally")
  T.Ok(visible:find("|c literal", 1, true), "escaped pipe decoded")
end)

T.Case("UTF-8 text survives normalization", function()
  local _, visible = N.Text(F.UTF8)
  T.Ok(visible:find("città", 1, true))
  T.Ok(visible:find("✓", 1, true))
end)

T.Case("UTF-8 truncation never splits a sequence", function()
  local text = "aàb" -- a, C3 A0, b
  T.Eq(N.TruncateUTF8(text, 2), "a")
  T.Eq(N.TruncateUTF8(text, 3), "aà")
  T.Eq(N.TruncateUTF8("✓✓", 4), "✓")
  T.Eq(N.TruncateUTF8("abc", 10), "abc")
end)

T.Case("display escaping neutralises links, colours and textures", function()
  local shown = N.EscapeForDisplay(F.ITEM_A .. "|TInterface\\x:0|t")
  T.NotOk(shown:find("[^|]|[^|]"), "no single pipe may remain")
  T.Eq(N.EscapeForDisplay("a|b"), "a||b")
end)

T.Case("literal rules: magic characters match literally", function()
  for _, term in ipairs({ ".", "%", "+", "[", "a.b", "100%", "x+y", "[wts]" }) do
    local compiled = Rules.Compile({ list = { { id = 1, text = term, enabled = true } } })
    T.NotOk(Rules.Match(compiled, "plain words only"), "no false match for " .. term)
  end
  local compiled = Rules.Compile({ list = { { id = 7, text = "[WTS]", enabled = true } } })
  local rule = Rules.Match(compiled, "selling [wts] now")
  T.Ok(rule and rule.id == 7)
  compiled = Rules.Compile({ list = { { id = 8, text = "100%", enabled = true } } })
  T.Ok(Rules.Match(compiled, "100% safe"))
  T.NotOk(Rules.Match(compiled, "1000 safe"))
end)

T.Case("rules are case-insensitive and match inside words", function()
  local compiled = Rules.Compile({ list = { { id = 1, text = "Gold", enabled = true } } })
  T.Ok(Rules.Match(compiled, select(2, N.Text("cheap GOLDEN items"))))
end)

T.Case("disabled rules never match; order is deterministic", function()
  local compiled = Rules.Compile({ list = {
    { id = 1, text = "aaa", enabled = false },
    { id = 2, text = "bbb", enabled = true },
    { id = 3, text = "b", enabled = true },
  } })
  T.Eq(#compiled, 2)
  T.Eq(Rules.Match(compiled, "aaa bbb").id, 2)
end)

T.Case("preview counts matches without activating anything", function()
  local matches, total = Rules.Preview("boost", { "Cheap BOOST here", "hello", "boosting" })
  T.Eq(#matches, 2)
  T.Eq(total, 3)
end)
