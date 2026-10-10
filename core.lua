-- Image -> ASCII conversion. No UI here, so test.lua can run it in batch mode.
local core = {}

-- Ramps go from no ink (space) to the densest glyph.
core.presets = {
  Standard = " .:-=+*#%@",
  Detailed = " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$",
  Blocks = " ░▒▓█",
}
core.presetNames = { "Standard", "Detailed", "Blocks" }

-- Splits a UTF-8 string into a table of characters.
function core.split(s)
  local t = {}
  for _, c in utf8.codes(s) do t[#t + 1] = utf8.char(c) end
  return t
end

-- Visible layers of one frame, flattened into an RGB image whatever the sprite's color mode.
function core.flatten(sprite, frameNumber)
  local img = Image(sprite.width, sprite.height, ColorMode.RGB)
  img:drawSprite(sprite, frameNumber)
  return img
end

-- Averages each cellW x cellH block of an RGB image.
-- Returns grid[row][col] = { r, g, b, a } with alpha-weighted color (0-255) and coverage a (0-1).
function core.sample(img, cellW, cellH)
  local pc = app.pixelColor
  local grid = {}
  -- ponytail: getPixel per pixel, ~1s on 2000x2000; read img.bytes directly if that ever matters
  for top = 0, img.height - 1, cellH do
    local row = {}
    for left = 0, img.width - 1, cellW do
      local r, g, b, a, n = 0, 0, 0, 0, 0
      for y = top, math.min(top + cellH, img.height) - 1 do
        for x = left, math.min(left + cellW, img.width) - 1 do
          local p = img:getPixel(x, y)
          local pa = pc.rgbaA(p)
          r, g, b = r + pc.rgbaR(p) * pa, g + pc.rgbaG(p) * pa, b + pc.rgbaB(p) * pa
          a, n = a + pa, n + 1
        end
      end
      if a > 0 then
        row[#row + 1] = { r = r / a, g = g / a, b = b / a, a = a / (n * 255) }
      else
        row[#row + 1] = { r = 0, g = 0, b = 0, a = 0 }
      end
    end
    grid[#grid + 1] = row
  end
  return grid
end

-- Maps each cell to a glyph. Default assumes dark text on a light background
-- (dark pixels get dense glyphs); invert is light text on dark.
-- Transparent cells blend into the background, so they come out as the first glyph.
function core.toGlyphs(grid, glyphs, invert)
  local n = #glyphs
  local rows = {}
  for i, cells in ipairs(grid) do
    local row = {}
    for j, c in ipairs(cells) do
      local lum = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255
      local ink = (invert and lum or 1 - lum) * c.a
      row[j] = glyphs[math.min(n, math.floor(ink * n) + 1)]
    end
    rows[i] = row
  end
  return rows
end

function core.toText(rows)
  local lines = {}
  for i, row in ipairs(rows) do lines[i] = table.concat(row) end
  return table.concat(lines, "\n")
end

return core
