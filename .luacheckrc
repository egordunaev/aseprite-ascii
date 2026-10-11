std = "lua54"
max_line_length = 130

-- Aseprite scripting API
read_globals = { app = { read_only = false, other_fields = true }, "Color", "ColorMode", "Dialog", "Image", "Point", "Rectangle", "Sprite", "Timer" }
-- plugin entry points that Aseprite calls
globals = { "init", "exit" }

-- test.lua stubs Dialog, which is nil in batch mode
files["test.lua"] = { globals = { "Dialog" } }
