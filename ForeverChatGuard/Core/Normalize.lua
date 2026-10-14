-- Text normalization (spec §7). Pure functions, no client globals.
--
-- Normalize.Text(raw) returns two comparison copies; the original text is
-- never modified and is kept by the caller for local display:
--   compare: duplicate key. Keeps hyperlink identity (link data + label).
--   visible: what the reader sees (labels only). Used for literal terms.
-- Both drop validated colour markup, collapse whitespace and lowercase A-Z
-- only. Digits, prices, punctuation and non-ASCII bytes are kept as they are.
local _, ns = ...

local Normalize = {}
ns.Core.Normalize = Normalize

local find, sub, gsub, byte = string.find, string.sub, string.gsub, string.byte
local concat = table.concat

-- Explicit A-Z map: string.lower depends on the C locale.
local LOWER = {}
for code = 65, 90 do
  LOWER[string.char(code)] = string.char(code + 32)
end

function Normalize.LowerASCII(text)
  return (gsub(text, "[A-Z]", LOWER))
end

function Normalize.CollapseSpace(text)
  text = gsub(text, "[ \t\r\n]+", " ")
  text = gsub(text, "^ ", "")
  text = gsub(text, " $", "")
  return text
end

local function plain(text)
  return Normalize.LowerASCII(Normalize.CollapseSpace(text))
end

-- Byte \2 starts every encoded link; a literal \2 is doubled, so the encoding
-- cannot be confused with link boundaries (prefix-free: \2\2 vs \2<digit>).
local function escapePlain(text)
  return (gsub(text, "\2", "\2\2"))
end

local function encodeLink(data, label)
  return "\2" .. #data .. ":" .. data .. #label .. ":" .. label
end

-- Removes validated colour codes and decodes "||" escapes in a fragment
-- that contains no hyperlink. Malformed sequences stay as literal text.
local function stripColours(text)
  local out, i, n = {}, 1, #text
  while i <= n do
    local p = find(text, "|", i, true)
    if not p then
      out[#out + 1] = sub(text, i)
      break
    end
    out[#out + 1] = sub(text, i, p - 1)
    local nextChar = sub(text, p + 1, p + 1)
    if nextChar == "|" then
      out[#out + 1] = "|"
      i = p + 2
    elseif nextChar == "c" and find(text, "^%x%x%x%x%x%x%x%x", p + 2) then
      i = p + 10
    elseif nextChar == "r" then
      i = p + 2
    else
      out[#out + 1] = "|"
      i = p + 1
    end
  end
  return concat(out)
end

-- Splits raw text into plain fragments and well-formed |H data |h label |h links.
local function scan(text)
  local parts, i, n = {}, 1, #text
  local buffer = {}
  while i <= n do
    local p = find(text, "|", i, true)
    if not p then
      buffer[#buffer + 1] = sub(text, i)
      break
    end
    local nextChar = sub(text, p + 1, p + 1)
    if nextChar == "|" then
      buffer[#buffer + 1] = sub(text, i, p + 1)
      i = p + 2
    elseif nextChar == "H" then
      local dataEnd = find(text, "|h", p + 2, true)
      local labelEnd = dataEnd and find(text, "|h", dataEnd + 2, true)
      if labelEnd then
        buffer[#buffer + 1] = sub(text, i, p - 1)
        parts[#parts + 1] = { kind = "text", value = concat(buffer) }
        buffer = {}
        parts[#parts + 1] = {
          kind = "link",
          data = sub(text, p + 2, dataEnd - 1),
          label = sub(text, dataEnd + 2, labelEnd - 1),
        }
        i = labelEnd + 2
      else
        buffer[#buffer + 1] = sub(text, i, p)
        i = p + 1
      end
    else
      buffer[#buffer + 1] = sub(text, i, p)
      i = p + 1
    end
  end
  parts[#parts + 1] = { kind = "text", value = concat(buffer) }
  return parts
end

function Normalize.Text(raw)
  local parts = scan(raw)
  local compare, visible = {}, {}
  for index = 1, #parts do
    local part = parts[index]
    if part.kind == "text" then
      local value = stripColours(part.value)
      compare[#compare + 1] = escapePlain(value)
      visible[#visible + 1] = value
    else
      local label = stripColours(part.label)
      compare[#compare + 1] = encodeLink(part.data, plain(label))
      visible[#visible + 1] = label
    end
  end
  -- Whitespace/case are normalized per plain run: link encodings carry their
  -- own normalized label, so collapsing cannot merge across a boundary.
  for index = 1, #compare do
    if parts[index].kind == "text" then
      local value = gsub(compare[index], "[ \t\r\n]+", " ")
      compare[index] = Normalize.LowerASCII(value)
    end
  end
  local compareText = gsub(gsub(concat(compare), "^ ", ""), " $", "")
  return compareText, plain(concat(visible))
end

-- Safe local rendering: every "|" is doubled, so the client shows the raw
-- characters and never interprets colours, links or textures from chat.
function Normalize.EscapeForDisplay(text)
  return (gsub(text, "|", "||"))
end

-- Truncates to at most maxBytes without splitting a UTF-8 sequence.
function Normalize.TruncateUTF8(text, maxBytes)
  if #text <= maxBytes then
    return text
  end
  local cut = maxBytes
  -- Step back over continuation bytes (10xxxxxx) to a lead byte.
  while cut > 0 do
    local b = byte(text, cut + 1)
    if not b or b < 0x80 or b >= 0xC0 then
      break
    end
    cut = cut - 1
  end
  return sub(text, 1, cut)
end

-- Trims and bounds identity strings (author/channel keys) by bytes.
function Normalize.Identity(value, maxBytes)
  if type(value) ~= "string" then
    return nil
  end
  value = gsub(gsub(value, "^%s+", ""), "%s+$", "")
  if value == "" then
    return nil
  end
  return Normalize.TruncateUTF8(value, maxBytes)
end
