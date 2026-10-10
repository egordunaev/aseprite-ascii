-- View > ASCII Art toggles a live ASCII preview of the current frame, kept on the right side.
local core, prefs
local dlg, timer, watched, siteHook, resizeHook
local grid, rows, used, text = nil, nil, nil, ""
local ox, oy, drag = 0, 0, nil -- canvas scroll offset, drag anchor

local WHITE, BLACK = Color{ r = 255, g = 255, b = 255 }, Color{ r = 0, g = 0, b = 0 }

local function glyphs()
  local t = core.split(prefs.glyphs)
  if #t == 0 then t = core.split(core.presets.Standard) end
  return t
end

local function convert()
  local spr = app.sprite
  if not spr then
    grid, rows, text = nil, nil, ""
    return
  end
  used = glyphs()
  grid = core.sample(core.flatten(spr, app.frame and app.frame.frameNumber or 1), prefs.cellW, prefs.cellH)
  rows = core.toGlyphs(grid, used, prefs.invert)
  text = core.toText(rows)
end

local function refresh()
  if not dlg then return end
  convert()
  dlg:modify{ id = "info", text = rows and (#rows[1] .. " × " .. #rows .. " chars") or "No sprite" }
  dlg:repaint()
end

-- Sprite edits fire per stroke; wait for a pause before reconverting.
local function schedule()
  timer:stop()
  timer:start()
end

local function watch(spr)
  if spr == watched then return end
  if watched then pcall(function() watched.events:off(schedule) end) end -- may already be closed
  watched = spr
  if spr then
    spr.events:on("change", schedule)
    spr.events:on("layervisibility", schedule)
  end
end

-- Scripts can't dock into the workspace, so the dialog floats against the main window's right edge.
local function sideBounds()
  if not app.window then return nil end
  local w = math.min(prefs.panelWidth, app.window.width)
  return Rectangle(app.window.width - w, 0, w, app.window.height)
end

local function cleanup()
  if dlg then prefs.panelWidth = dlg.bounds.width end
  if siteHook then app.events:off(siteHook) end
  if resizeHook then app.window.events:off(resizeHook) end
  siteHook, resizeHook = nil, nil
  watch(nil)
  if timer then timer:stop() end
  dlg = nil
end

local function paint(ev)
  local gc = ev.context
  local fg, bg = BLACK, WHITE
  if prefs.invert then fg, bg = WHITE, BLACK end
  gc.color = bg
  gc:fillRect(Rectangle(0, 0, gc.width, gc.height))
  if not rows then return end

  -- The UI font is proportional, so every glyph gets a fixed cell sized to the widest one.
  local widths, cw, ch = {}, 1, 1
  for _, g in ipairs(used) do
    local s = gc:measureText(g)
    widths[g], cw, ch = s.width, math.max(cw, s.width), math.max(ch, s.height)
  end

  ox = math.max(0, math.min(ox, #rows[1] * cw - gc.width))
  oy = math.max(0, math.min(oy, #rows * ch - gc.height))
  gc.color = fg
  for r = oy // ch + 1, math.min(#rows, (oy + gc.height) // ch + 1) do
    local row, cells = rows[r], grid[r]
    for c = ox // cw + 1, math.min(#row, (ox + gc.width) // cw + 1) do
      local g = row[c]
      if g ~= " " then
        if prefs.color then
          local cell = cells[c]
          gc.color = Color{ r = math.floor(cell.r), g = math.floor(cell.g), b = math.floor(cell.b) }
        end
        gc:fillText(g, (c - 1) * cw - ox + (cw - widths[g]) // 2, (r - 1) * ch - oy)
      end
    end
  end
end

local function apply()
  local d = dlg.data
  prefs.cellW, prefs.cellH, prefs.glyphs = d.cellW, d.cellH, d.glyphs
  prefs.invert, prefs.color = d.invert, d.color
  schedule()
end

local function copy()
  if not app.clipboard then return app.alert("Copying needs a newer Aseprite; use Save .txt") end
  app.clipboard.text = text
end

local function save()
  local path = dlg.data.save
  if not path or path == "" then return end
  local f, err = io.open(path, "w")
  if not f then return app.alert("Couldn't save: " .. err) end
  f:write(text, "\n")
  f:close()
end

local function close()
  if dlg then dlg:close() end
  cleanup()
end

local function open()
  timer =timer or Timer{ interval = 0.15, ontick = function() timer:stop(); refresh() end }

  dlg = Dialog{ title = "ASCII Art", resizeable = true, onclose = cleanup }
  dlg:slider{ id = "cellW", label = "Cell width", min = 1, max = 32, value = prefs.cellW, onchange = apply }
  dlg:slider{ id = "cellH", label = "Cell height", min = 1, max = 32, value = prefs.cellH, onchange = apply }
  dlg:combobox{ id = "preset", label = "Preset", option = prefs.preset, options = core.presetNames,
    onchange = function()
      prefs.preset = dlg.data.preset
      dlg:modify{ id = "glyphs", text = core.presets[prefs.preset] }
      apply()
    end }
  dlg:entry{ id = "glyphs", label = "Glyphs", text = prefs.glyphs, onchange = apply }
  dlg:check{ id = "invert", label = "Style", text = "Light on dark", selected = prefs.invert, onclick = apply }
  dlg:check{ id = "color", text = "Colored", selected = prefs.color, onclick = apply }
  dlg:separator()
  dlg:canvas{ id = "view", width = 160, height = 160, onpaint = paint,
    onwheel = function(ev)
      if ev.shiftKey then
        ox = ox + math.floor(ev.deltaY * 30)
      else
        ox, oy = ox + math.floor(ev.deltaX * 30), oy + math.floor(ev.deltaY * 30)
      end
      dlg:repaint()
    end,
    onmousedown = function(ev) drag = { x = ev.x + ox, y = ev.y + oy } end,
    onmousemove = function(ev)
      if not drag then return end
      ox, oy = drag.x - ev.x, drag.y - ev.y
      dlg:repaint()
    end,
    onmouseup = function() drag = nil end }
  dlg:newrow()
  dlg:label{ id = "info", text = "" }
  dlg:separator()
  dlg:file{ id = "save", label = "Save .txt", save = true, filetypes = { "txt" },
    filename = app.fs.filePathAndTitle(app.sprite.filename) .. ".txt", onchange = save }
  dlg:newrow()
  dlg:button{ text = "Copy", onclick = copy }
  dlg:button{ text = "Close" }
  dlg:show{ wait = false, bounds = sideBounds() }

  siteHook = app.events:on("sitechange", function() watch(app.sprite); schedule() end)
  if app.window then
    resizeHook = app.window.events:on("resize", function()
      prefs.panelWidth = dlg.bounds.width -- keep a width the user dragged to
      dlg.bounds = sideBounds()
    end)
  end
  watch(app.sprite)
  refresh()
end

function init(plugin)
  core = dofile(app.fs.joinPath(plugin.path, "core.lua"))
  prefs = plugin.preferences
  local defaults = { cellW = 1, cellH = 2, preset = "Standard", glyphs = core.presets.Standard,
    invert = false, color = false, panelWidth = 320 }
  for k, v in pairs(defaults) do
    if prefs[k] == nil then prefs[k] = v end
  end
  plugin:newCommand{
    id = "AsciiArt",
    title = "ASCII Art",
    group = "view_new",
    onenabled = function() return app.sprite ~= nil or dlg ~= nil end,
    onchecked = function() return dlg ~= nil end,
    onclick = function() if dlg then close() else open() end end,
  }
end

function exit(plugin)
  close()
end
