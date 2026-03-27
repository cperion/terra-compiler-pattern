local Backend = require("examples.ui.backend_sdl_gl")
local Text = require("examples.ui.backend_text_sdl_ttf")
local UiBackend = require("examples.ui.ui_backend")

local runtime = Backend.init_window("terra ui box + text demo", 800, 600)
Text.init(runtime)

local shaped = Text.shape(runtime,
    { value = "Hello Terra UI" },
    {
        font = { value = 1 },
        size_px = 28,
        color = { r = 0.97, g = 0.98, b = 1.0, a = 1.0 },
    },
    {
        wrap = { kind = "NoWrap" },
        overflow = { kind = "ClipText" },
        align = { kind = "TextStart" },
        line_limit = 1,
    },
    { x = 110, y = 130, w = 500, h = 60 }
)

local glyph_items = {}
for _, line in ipairs(shaped.lines) do
    for _, run in ipairs(line.runs) do
        for _, glyph in ipairs(run.glyphs) do
            glyph_items[#glyph_items + 1] = {
                glyph_id = glyph.glyph_id,
                origin = glyph.origin,
                color = run.color,
            }
        end
    end
end

local scene = {
    bounds = { x = 0, y = 0, w = 800, h = 600 },
    batches = {
        {
            kind = "BoxBatch",
            sort_key = 0,
            clip = nil,
            items = {
                {
                    rect = { x = 80, y = 80, w = 320, h = 180 },
                    fill = {
                        kind = "Solid",
                        color = { r = 0.18, g = 0.42, b = 0.92, a = 1.0 },
                    },
                    stroke = {
                        kind = "Solid",
                        color = { r = 0.95, g = 0.97, b = 1.0, a = 1.0 },
                    },
                    stroke_width = 2,
                    align = { kind = "CenterStroke" },
                    corners = {
                        top_left = 0,
                        top_right = 0,
                        bottom_right = 0,
                        bottom_left = 0,
                    },
                },
                {
                    rect = { x = 440, y = 120, w = 180, h = 220 },
                    fill = {
                        kind = "Solid",
                        color = { r = 0.92, g = 0.34, b = 0.28, a = 0.92 },
                    },
                    stroke = nil,
                    stroke_width = 0,
                    align = { kind = "CenterStroke" },
                    corners = {
                        top_left = 0,
                        top_right = 0,
                        bottom_right = 0,
                        bottom_left = 0,
                    },
                },
            },
        },
        {
            kind = "GlyphBatch",
            sort_key = 1,
            clip = nil,
            font = { value = 1 },
            atlas = shaped.atlas,
            items = glyph_items,
        },
    },
}

local unit = UiBackend.compile_scene(scene)
Backend.render_unit(runtime, unit)
Backend.FFI.SDL_Delay(1500)
Text.shutdown(runtime)
Backend.shutdown_window(runtime)
