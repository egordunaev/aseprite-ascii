-- REXPaint .xp export.
-- For reference, see https://www.gridsagegames.com/rexpaint/manual.txt
-- Format (REXPaint manual, appendix B): gzip of int32 version, int32 layer count, then per layer
-- int32 width, int32 height and column-major cells of uint32 CP437 code, fg RGB, bg RGB.
local xp = {}

-- REXPaint stores a CP437 code per cell and draws it with whatever font it has loaded.
local CODES = {}
local function map(first, chars)
  local code = first
  for _, c in utf8.codes(chars) do
    CODES[utf8.char(c)] = code
    code = code + 1
  end
end
map(1, "☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼")
for i = 32, 126 do CODES[string.char(i)] = i end
map(127, "⌂ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧"
  .. "╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u{A0}")

-- Glyphs CP437 doesn't have become "?", as REXPaint's own text import does.
function xp.code(glyph)
  return CODES[glyph] or 63
end

local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do c = (c & 1 == 1) and (0xEDB88320 ~ (c >> 1)) or (c >> 1) end
  CRC[i] = c
end

function xp.crc32(s)
  local c = 0xFFFFFFFF
  for i = 1, #s do c = CRC[(c ~ s:byte(i)) & 0xFF] ~ (c >> 8) end
  return c ~ 0xFFFFFFFF
end

-- Stored (uncompressed) deflate blocks: any zlib reader, REXPaint's included, takes them and no
-- compressor is needed. That costs ~10 bytes per cell on disk; a fixed-Huffman encoder would cut it.
function xp.gzip(s)
  local out = { "\31\139\8\0\0\0\0\0\0\255" } -- magic, deflate, no flags or mtime, unknown OS
  local i = 1
  repeat
    local chunk = s:sub(i, i + 65534)
    i = i + #chunk
    out[#out + 1] = string.pack("<BI2I2", i > #s and 1 or 0, #chunk, ~#chunk & 0xFFFF) .. chunk
  until i > #s
  out[#out + 1] = string.pack("<I4I4", xp.crc32(s), #s & 0xFFFFFFFF)
  return table.concat(out)
end

-- cells[row][col] = { code, fg = { r, g, b }, bg = { r, g, b } } -> a one-layer .xp file.
-- Channels may be fractional, like core.sample's averages; they're floored.
function xp.encode(cells)
  local floor = math.floor
  local w, h = #cells[1], #cells
  local out = { string.pack("<i4i4i4i4", -1, 1, w, h) } -- version -1 is what current REXPaint writes
  for col = 1, w do
    for row = 1, h do
      local c = cells[row][col]
      local f, b = c.fg, c.bg
      out[#out + 1] = string.pack("<I4BBBBBB", c.code, floor(f.r), floor(f.g), floor(f.b), floor(b.r), floor(b.g), floor(b.b))
    end
  end
  return xp.gzip(table.concat(out))
end

return xp
