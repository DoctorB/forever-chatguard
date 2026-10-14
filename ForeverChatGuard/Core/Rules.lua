-- Literal term rules (spec §7). Terms are substrings, case-insensitive for
-- A-Z only; never Lua patterns, regular expressions or code.
local _, ns = ...

local Normalize = ns.Core.Normalize

local Rules = {}
ns.Core.Rules = Rules

local find = string.find

-- Compiles enabled terms into { id, needle, text } in list order, so the
-- first matching rule is deterministic. Rebuilt whenever rules change.
function Rules.Compile(customTerms)
  local compiled = {}
  if type(customTerms) ~= "table" or type(customTerms.list) ~= "table" then
    return compiled
  end
  for index = 1, #customTerms.list do
    local entry = customTerms.list[index]
    if entry.enabled then
      local needle = Normalize.LowerASCII(Normalize.CollapseSpace(entry.text))
      if needle ~= "" then
        compiled[#compiled + 1] = { id = entry.id, needle = needle, text = entry.text }
      end
    end
  end
  return compiled
end

-- visible: normalized visible text (Normalize.Text second result).
function Rules.Match(compiled, visible)
  for index = 1, #compiled do
    local rule = compiled[index]
    if find(visible, rule.needle, 1, true) then
      return rule
    end
  end
  return nil
end

-- Local preview before activation: counts matches among sample texts.
function Rules.Preview(termText, samples)
  local needle = Normalize.LowerASCII(Normalize.CollapseSpace(termText or ""))
  local matches = {}
  if needle == "" then
    return matches, 0
  end
  for index = 1, #samples do
    local _, visible = Normalize.Text(samples[index])
    if find(visible, needle, 1, true) then
      matches[#matches + 1] = samples[index]
    end
  end
  return matches, #samples
end
