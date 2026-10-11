-- Run from the project folder:
--   aseprite -b --script test.lua
local core = dofile("core.lua")
local pc = app.pixelColor

local function eq(got, want, what)
  if got ~= want then error(("%s: got %q, want %q"):format(what, got, want), 2) end
end

local BLACK, GRAY, WHITE = pc.rgba(0, 0, 0), pc.rgba(128, 128, 128), pc.rgba(255, 255, 255)
local CLEAR = pc.rgba(0, 0, 0, 0)

local function image(pixelRows)
  local img = Image(#pixelRows[1], #pixelRows, ColorMode.RGB)
  for y, row in ipairs(pixelRows) do
    for x, p in ipairs(row) do img:drawPixel(x - 1, y - 1, p) end
  end
  return img
end

local function ascii(img, cellW, cellH, glyphs, invert)
  return core.toText(core.toGlyphs(core.sample(img, cellW, cellH), core.split(glyphs), invert))
end

-- multibyte glyphs split per character
local blocks = core.split(core.presets.Blocks)
eq(#blocks, 5, "blocks count")
eq(blocks[2], "░", "blocks[2]")

-- one char per pixel: dark is dense, transparent is blank
local strip = image{ { BLACK, GRAY, WHITE, CLEAR } }
eq(ascii(strip, 1, 1, " .#"), "#.  ", "1x1")
eq(ascii(strip, 1, 1, " .#", true), " .# ", "1x1 inverted")

-- cells average their pixels; partial cells at the right and bottom edges
eq(ascii(image{ { BLACK, WHITE, BLACK } }, 2, 1, " .#"), ".#", "average + edge cell")
eq(ascii(image{ { BLACK }, { WHITE }, { BLACK } }, 1, 2, " .#"), ".\n#", "rows")
-- half-transparent cell keeps its color but only half the ink
eq(ascii(image{ { BLACK, CLEAR } }, 2, 1, " .#"), ".", "half coverage")

-- indexed sprites flatten to RGB; the transparent index stays clear
local spr = Sprite(2, 1, ColorMode.INDEXED)
spr.palettes[1]:setColor(1, Color{ r = 0, g = 0, b = 0 })
spr.cels[1].image:drawPixel(0, 0, 1)
local flat = core.flatten(spr, 1)
eq(flat:getPixel(0, 0), BLACK, "indexed black")
eq(pc.rgbaA(flat:getPixel(1, 0)), 0, "indexed clear")
spr:close()

-- bundled pixel fonts parse: ASCII from ' ', "M" sets the cell size
local mini = core.loadFont(assert(core.fontPath("aseprite_mini.png"), "mini font found"))
local regular = core.loadFont(assert(core.fontPath("aseprite_font.png"), "regular font found"))
eq(mini.h, 5, "mini height")
eq(regular.h, 7, "regular height")
assert(mini.glyphs["~"] and regular.glyphs["~"], "fonts cover printable ASCII")

local function inked(img)
  local n = 0
  for p in img:pixels() do if pc.rgbaA(p()) > 0 then n = n + 1 end end
  return n
end

-- glyphs stamp into their cell; ink color applies; space and unknown glyphs stay blank
local cellGrid = { { { r = 0, g = 0, b = 0, a = 1 }, { r = 0, g = 0, b = 0, a = 1 } } }
local stamped = core.render({ { "#", " " } }, cellGrid, mini, 16, 8, 8, 8, WHITE)
assert(inked(stamped) > 0, "# drawn")
for p in stamped:pixels(Rectangle(8, 0, 8, 8)) do eq(p(), CLEAR, "space cell blank") end
for p in stamped:pixels() do assert(p() == CLEAR or p() == WHITE, "ink color") end
eq(inked(core.render({ { "☃" } }, cellGrid, mini, 8, 8, 8, 8, WHITE)), 0, "missing glyph blank")

-- shade blocks dither: 4x4 cell -> 4, 8, 12, 16 pixels; nil ink uses the cell color
for g, n in pairs{ ["░"] = 4, ["▒"] = 8, ["▓"] = 12, ["█"] = 16 } do
  eq(inked(core.render({ { g } }, cellGrid, mini, 4, 4, 4, 4, WHITE)), n, g .. " coverage")
end
eq(core.render({ { "█" } }, { { { r = 255, g = 0, b = 0, a = 1 } } }, mini, 2, 2, 2, 2):getPixel(1, 1),
  pc.rgba(255, 0, 0), "cell color")

-- plugin script loads and registers its command
local command
assert(loadfile("ascii.lua"))()
init{ path = ".", preferences = {}, newCommand = function(_, t) command = t end }
assert(command and command.onclick and command.group == "view_new", "command registered")
assert(command.onchecked() == false, "panel starts closed")
exit{}

print("ok")
