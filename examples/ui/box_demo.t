local asdl = require("asdl")
local List = asdl.List

local Backend = require("examples.ui.backend_sdl_gl")
local RawText = require("examples.ui.backend_text_sdl_ttf")
local Text = require("examples.ui.ui_text_resolve")
local Schema = require("examples.ui.ui_schema")
local T = Schema.ctx

local runtime = Backend.init_window("terra ui box + text demo", 800, 600)
RawText.init(runtime)

local font = T.UiCore.FontRef(1)
local assets = T.UiAsset.Catalog(
    font,
    List {
        T.UiAsset.FontAsset(font, "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf")
    },
    List()
)

local shaped = Text.shape(
    T,
    assets,
    runtime,
    T.UiCore.TextValue("Hello Terra UI"),
    T.UiCore.TextStyle(font, 28, nil, nil, nil, nil, T.UiCore.Color(0.97, 0.98, 1.0, 1.0)),
    T.UiCore.TextLayout(T.UiCore.NoWrap(), T.UiCore.ClipText(), T.UiCore.TextStart(), 1),
    T.UiCore.Rect(110, 130, 500, 60)
)

local glyph_items = List()
for _, line in ipairs(shaped.lines) do
    for _, run in ipairs(line.runs) do
        for _, glyph in ipairs(run.glyphs) do
            glyph_items:insert(T.UiBatched.GlyphItem(glyph.glyph_id, glyph.origin, run.color))
        end
    end
end

local scene = T.UiBatched.Scene(
    List {
        T.UiBatched.BoxBatch(
            0,
            nil,
            List {
                T.UiBatched.BoxItem(
                    T.UiCore.Rect(80, 80, 320, 180),
                    T.UiCore.Solid(T.UiCore.Color(0.18, 0.42, 0.92, 1.0)),
                    T.UiCore.Solid(T.UiCore.Color(0.95, 0.97, 1.0, 1.0)),
                    2,
                    T.UiCore.CenterStroke(),
                    T.UiCore.Corners(0, 0, 0, 0)
                ),
                T.UiBatched.BoxItem(
                    T.UiCore.Rect(440, 120, 180, 220),
                    T.UiCore.Solid(T.UiCore.Color(0.92, 0.34, 0.28, 0.92)),
                    nil,
                    0,
                    T.UiCore.CenterStroke(),
                    T.UiCore.Corners(0, 0, 0, 0)
                )
            }
        ),
        T.UiBatched.GlyphBatch(
            1,
            nil,
            font,
            Text.ensure_atlas(T, font, 28),
            glyph_items
        )
    },
    T.UiCore.Rect(0, 0, 800, 600)
)

local unit = scene:compile(assets)
Backend.render_unit(runtime, unit)
Backend.FFI.SDL_Delay(1500)
RawText.shutdown(runtime)
Backend.shutdown_window(runtime)
