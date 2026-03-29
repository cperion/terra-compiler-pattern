local F = require("fun")
local Assets = require("examples.ui.ui_asset_resolve")
local RawText = require("examples.ui.backend_text_sdl_ttf")

local Text = {}

local List = require("asdl").List

local function L(xs)
    return List(xs or {})
end

local function rect(T, r)
    return T.UiCore.Rect(r.x, r.y, r.w, r.h)
end

local function point(T, p)
    return T.UiCore.Point(p.x, p.y)
end

local function default_font(T, assets, text_style)
    return (text_style and text_style.font) or Assets.default_font_ref(assets)
end

local function default_color(T, text_style)
    return (text_style and text_style.color) or T.UiCore.Color(1, 1, 1, 1)
end

function Text.measure(T, assets, runtime, text_value, text_style, text_layout, max_width)
    local measured = RawText.measure(
        runtime,
        Assets.font_path(assets, text_style and text_style.font or nil),
        text_value,
        text_style,
        text_layout,
        max_width
    )
    return T.UiCore.Size(measured.w, measured.h)
end

function Text.ensure_atlas(T, font_ref, size_px)
    return T.UiCore.GlyphAtlasRef(RawText.ensure_atlas(font_ref, size_px))
end

function Text.shape(T, assets, runtime, text_value, text_style, text_layout, bounds)
    local raw = RawText.shape(
        runtime,
        Assets.font_path(assets, text_style and text_style.font or nil),
        text_value,
        text_style,
        text_layout,
        bounds
    )
    local font = default_font(T, assets, text_style)
    local color = default_color(T, text_style)

    local lines = L(F.iter(raw.lines):map(function(line)
        return T.UiLaid.ShapedLine(
            line.baseline_y,
            rect(T, line.ink_bounds),
            L(F.iter(line.runs):map(function(run)
                return T.UiLaid.ShapedRun(
                    font,
                    run.size_px,
                    color,
                    line.text,
                    L(F.iter(run.glyphs):map(function(glyph)
                        return T.UiLaid.Glyph(
                            glyph.glyph_id,
                            glyph.cluster,
                            point(T, glyph.origin),
                            rect(T, glyph.ink_bounds)
                        )
                    end):totable())
                )
            end):totable())
        )
    end):totable())

    return T.UiLaid.ShapedText(
        rect(T, raw.bounds),
        raw.baseline_y,
        text_value and text_value.value or "",
        (text_layout and text_layout.wrap) or T.UiCore.NoWrap(),
        (text_layout and text_layout.align) or T.UiCore.TextStart(),
        lines
    )
end

return Text
