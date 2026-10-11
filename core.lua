-- Image -> ASCII conversion. No UI here, so test.lua can run it in batch mode.
local core = {}

-- Ramps go from no ink (space) to the densest glyph.
core.presets = {
  Standard = " .:-=+*#%@",
  Detailed = " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$",
}

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

-- Bundled pixel font sheets live in data/fonts next to the executable (Windows/Linux portable),
-- in Contents/Resources on macOS, or in share/aseprite on Linux installs.
function core.fontPath(name)
  local bin = app.fs.filePath(app.fs.appPath)
  local up = app.fs.filePath(bin)
  for _, dir in ipairs{ app.fs.joinPath(bin, "data/fonts"), app.fs.joinPath(up, "Resources/data/fonts"),
                        app.fs.joinPath(up, "share/aseprite/data/fonts") } do
    local path = app.fs.joinPath(dir, name)
    if app.fs.isFile(path) then return path end
  end
end

-- Parses an Aseprite sprite-sheet font: glyph boxes separated by the key color (top-left pixel),
-- in codepoint order from ' ', red boxes for missing glyphs. Same scan as laf's SpriteSheetTypeface.
-- Returns { img, glyphs = { [char] = Rectangle }, w, h } with w/h the size of the "M" box.
function core.loadFont(path)
  local img = Image{ fromFile = path }
  local key, red = img:getPixel(0, 0), app.pixelColor.rgba(255, 0, 0)
  local glyphs = {}
  local x, y, h, cp = 0, 0, 1, 32
  while true do
    if x >= img.width then x, y, h = 0, y + h, 1 end
    if y >= img.height then break end
    if img:getPixel(x, y) == key then
      x = x + 1
    else
      local w, bh = 0, 0
      while x + w < img.width and img:getPixel(x + w, y) ~= key do w = w + 1 end
      while y + bh < img.height and img:getPixel(x, y + bh) ~= key do bh = bh + 1 end
      if img:getPixel(x, y) ~= red then glyphs[utf8.char(cp)] = Rectangle(x, y, w, bh) end
      x, h, cp = x + w, bh, cp + 1
    end
  end
  return { img = img, glyphs = glyphs, w = glyphs.M.width, h = glyphs.M.height }
end

-- Shade blocks aren't in the fonts, so they're dithered: 25/50/75/100% coverage.
local SHADES = {
  ["░"] = function(x, y) return x % 2 == 0 and y % 2 == 0 end,
  ["▒"] = function(x, y) return (x + y) % 2 == 0 end,
  ["▓"] = function(x, y) return x % 2 == 0 or y % 2 == 0 end,
  ["█"] = function() return true end,
}

-- Stamps each cell's glyph, centered and clipped to the cell, into a width x height RGB image.
-- ink is the pixel color for every glyph, or nil to use each cell's average color.
-- Glyphs the font doesn't have are left blank.
function core.render(rows, grid, font, width, height, cellW, cellH, ink)
  local pc = app.pixelColor
  local out = Image(width, height, ColorMode.RGB)
  for r, row in ipairs(rows) do
    for c, g in ipairs(row) do
      local x0, y0 = (c - 1) * cellW, (r - 1) * cellH
      local x1, y1 = math.min(x0 + cellW, width), math.min(y0 + cellH, height)
      local cell = grid[r][c]
      local color = ink or pc.rgba(math.floor(cell.r), math.floor(cell.g), math.floor(cell.b))
      local shade, box = SHADES[g], font.glyphs[g]
      if shade then
        for y = y0, y1 - 1 do
          for x = x0, x1 - 1 do
            if shade(x, y) then out:drawPixel(x, y, color) end
          end
        end
      elseif box and g ~= " " then
        local dx, dy = x0 + (cellW - box.width) // 2, y0 + (cellH - box.height) // 2
        for y = math.max(y0, dy), math.min(y1, dy + box.height) - 1 do
          for x = math.max(x0, dx), math.min(x1, dx + box.width) - 1 do
            if pc.rgbaA(font.img:getPixel(box.x + x - dx, box.y + y - dy)) > 0 then out:drawPixel(x, y, color) end
          end
        end
      end
    end
  end
  return out
end

return core
