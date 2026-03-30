-- ============================================================================
-- SDL_ttf text backend scaffold
-- ----------------------------------------------------------------------------
-- Text measurement + glyph raster support for the first UI vertical slice.
--
-- Initial implementation order (leaf first):
--   1. TTF init/shutdown
--   2. load font by explicit resolved asset path
--   3. measure text for UiDecl.Content.Text
--   4. shape/raster simple glyph runs for UiLaid -> UiBatched.GlyphBatch
-- ============================================================================

local ffi = require("ffi")
local utf8 = rawget(_G, "utf8")

local Text = {}

if not rawget(_G, "__terra_ui_text_ffi_cdef") then
    local ok = pcall(ffi.cdef, [[
        typedef unsigned long size_t;
        typedef uint8_t Uint8;
        typedef uint32_t Uint32;
        typedef uint32_t SDL_PixelFormat;

        typedef struct TTF_Font TTF_Font;

        typedef struct SDL_Surface {
            Uint32 flags;
            SDL_PixelFormat format;
            int w;
            int h;
            int pitch;
            void *pixels;
            int refcount;
            void *reserved;
        } SDL_Surface;

        typedef struct SDL_Color {
            Uint8 r;
            Uint8 g;
            Uint8 b;
            Uint8 a;
        } SDL_Color;

        bool TTF_Init(void);
        void TTF_Quit(void);
        TTF_Font *TTF_OpenFont(const char *file, float ptsize);
        void TTF_CloseFont(TTF_Font *font);

        int TTF_GetFontHeight(const TTF_Font *font);
        int TTF_GetFontAscent(const TTF_Font *font);
        int TTF_GetFontDescent(const TTF_Font *font);

        bool TTF_GetGlyphMetrics(TTF_Font *font, Uint32 ch, int *minx, int *maxx, int *miny, int *maxy, int *advance);
        bool TTF_GetGlyphKerning(TTF_Font *font, Uint32 previous_ch, Uint32 ch, int *kerning);

        bool TTF_GetStringSize(TTF_Font *font, const char *text, size_t length, int *w, int *h);
        bool TTF_GetStringSizeWrapped(TTF_Font *font, const char *text, size_t length, int wrap_width, int *w, int *h);

        typedef int TTF_HorizontalAlignment;

        SDL_Surface *TTF_RenderGlyph_Blended(TTF_Font *font, Uint32 ch, SDL_Color fg);
        SDL_Surface *TTF_RenderText_Blended(TTF_Font *font, const char *text, size_t length, SDL_Color fg);
        SDL_Surface *TTF_RenderText_Blended_Wrapped(TTF_Font *font, const char *text, size_t length, SDL_Color fg, int wrap_width);
        void TTF_SetFontWrapAlignment(TTF_Font *font, TTF_HorizontalAlignment align);

        const char *SDL_GetError(void);
        SDL_Surface *SDL_ConvertSurface(SDL_Surface *surface, SDL_PixelFormat format);
        void SDL_DestroySurface(SDL_Surface *surface);
        bool SDL_LockSurface(SDL_Surface *surface);
        void SDL_UnlockSurface(SDL_Surface *surface);
    ]])
    if not ok then
        pcall(ffi.cdef, [[
            typedef unsigned long size_t;
            typedef uint8_t Uint8;
            typedef uint32_t Uint32;
            typedef uint32_t SDL_PixelFormat;
            typedef struct TTF_Font TTF_Font;
            typedef struct SDL_Color {
                Uint8 r;
                Uint8 g;
                Uint8 b;
                Uint8 a;
            } SDL_Color;
            bool TTF_Init(void);
            void TTF_Quit(void);
            TTF_Font *TTF_OpenFont(const char *file, float ptsize);
            void TTF_CloseFont(TTF_Font *font);
            int TTF_GetFontHeight(const TTF_Font *font);
            int TTF_GetFontAscent(const TTF_Font *font);
            int TTF_GetFontDescent(const TTF_Font *font);
            bool TTF_GetGlyphMetrics(TTF_Font *font, Uint32 ch, int *minx, int *maxx, int *miny, int *maxy, int *advance);
            bool TTF_GetGlyphKerning(TTF_Font *font, Uint32 previous_ch, Uint32 ch, int *kerning);
            bool TTF_GetStringSize(TTF_Font *font, const char *text, size_t length, int *w, int *h);
            bool TTF_GetStringSizeWrapped(TTF_Font *font, const char *text, size_t length, int wrap_width, int *w, int *h);
            typedef int TTF_HorizontalAlignment;
            SDL_Surface *TTF_RenderGlyph_Blended(TTF_Font *font, Uint32 ch, SDL_Color fg);
            SDL_Surface *TTF_RenderText_Blended(TTF_Font *font, const char *text, size_t length, SDL_Color fg);
            SDL_Surface *TTF_RenderText_Blended_Wrapped(TTF_Font *font, const char *text, size_t length, SDL_Color fg, int wrap_width);
            void TTF_SetFontWrapAlignment(TTF_Font *font, TTF_HorizontalAlignment align);
            const char *SDL_GetError(void);
            SDL_Surface *SDL_ConvertSurface(SDL_Surface *surface, SDL_PixelFormat format);
            void SDL_DestroySurface(SDL_Surface *surface);
            bool SDL_LockSurface(SDL_Surface *surface);
            void SDL_UnlockSurface(SDL_Surface *surface);
        ]])
    end
    _G.__terra_ui_text_ffi_cdef = true
end

Text.SDL = ffi.load("SDL3", true)
Text.TTF = ffi.load("SDL3_ttf", true)

Text.initialized = false
Text.font_cache = {}
Text.glyph_cache = {}
Text.text_cache = {}

function Text.headers()
    if Text.C then return Text.C end

    Text.C = {
        SDL_PIXELFORMAT_RGBA32 = ffi.abi("le") and 0x16762004 or 0x16462004,
    }

    return Text.C
end

local function ttf_error(where)
    error(("%s: %s"):format(where, ffi.string(Text.SDL.SDL_GetError())), 3)
end

local function ttf_ok(ok, where)
    if ok then return end
    ttf_error(where)
end

local function line_size(font, text)
    local w = ffi.new("int[1]", 0)
    local h = ffi.new("int[1]", 0)
    ttf_ok(Text.TTF.TTF_GetStringSize(font, text or "", #(text or ""), w, h), "TTF_GetStringSize")
    return w[0], h[0]
end

local function glyph_metrics(font, glyph_id)
    local minx = ffi.new("int[1]", 0)
    local maxx = ffi.new("int[1]", 0)
    local miny = ffi.new("int[1]", 0)
    local maxy = ffi.new("int[1]", 0)
    local advance = ffi.new("int[1]", 0)
    ttf_ok(Text.TTF.TTF_GetGlyphMetrics(font, glyph_id, minx, maxx, miny, maxy, advance), "TTF_GetGlyphMetrics")
    return {
        minx = minx[0],
        maxx = maxx[0],
        miny = miny[0],
        maxy = maxy[0],
        advance = advance[0],
    }
end

local function glyph_kerning(font, previous_glyph, glyph_id)
    if not previous_glyph then return 0 end
    local kerning = ffi.new("int[1]", 0)
    ttf_ok(Text.TTF.TTF_GetGlyphKerning(font, previous_glyph, glyph_id, kerning), "TTF_GetGlyphKerning")
    return kerning[0]
end

local function split_lines(text)
    text = (text or ""):gsub("\r\n", "\n")
    if text == "" then return { "" } end

    local lines = {}
    local start = 1
    while true do
        local i = text:find("\n", start, true)
        if not i then
            lines[#lines + 1] = text:sub(start)
            break
        end
        lines[#lines + 1] = text:sub(start, i - 1)
        start = i + 1
    end
    return lines
end

local function codepoints(text)
    local out = {}
    if utf8 and utf8.codes then
        for _, cp in utf8.codes(text) do
            out[#out + 1] = cp
        end
        return out
    end

    for i = 1, #text do
        out[#out + 1] = text:byte(i)
    end
    return out
end

local function surface_to_rgba_bytes(surface)
    local rgba = Text.SDL.SDL_ConvertSurface(surface, Text.headers().SDL_PIXELFORMAT_RGBA32)
    if rgba == nil then
        ttf_error("SDL_ConvertSurface")
    end

    ttf_ok(Text.SDL.SDL_LockSurface(rgba), "SDL_LockSurface")

    local row_bytes = rgba.w * 4
    local src = ffi.cast("uint8_t *", rgba.pixels)
    local bytes = {}
    local k = 1

    for y = 0, rgba.h - 1 do
        local row = src + y * rgba.pitch
        for x = 0, row_bytes - 1 do
            bytes[k] = row[x]
            k = k + 1
        end
    end

    Text.SDL.SDL_UnlockSurface(rgba)
    Text.SDL.SDL_DestroySurface(rgba)

    return bytes
end

local function font_id(font_ref)
    if font_ref == nil then return 0 end
    if type(font_ref) == "number" then return font_ref end
    return font_ref.value
end

local function atlas_id(atlas_ref)
    if atlas_ref == nil then return nil end
    if type(atlas_ref) == "number" then return atlas_ref end
    return atlas_ref.value
end

local ATLAS_SIZE_SCALE = 65536

local function pack_atlas_id(font_ref, size_px)
    local resolved_size = math.max(1, math.floor((size_px or 16) + 0.5))
    return font_id(font_ref) * ATLAS_SIZE_SCALE + resolved_size, resolved_size
end

local function unpack_atlas_id(atlas_ref)
    local id = atlas_id(atlas_ref)
    if id == nil then return nil end
    return {
        font_id = math.floor(id / ATLAS_SIZE_SCALE),
        size_px = id % ATLAS_SIZE_SCALE,
    }
end

function Text.init(runtime)
    if Text.initialized then
        if runtime then runtime.text = runtime.text or {} end
        return runtime
    end

    ttf_ok(Text.TTF.TTF_Init(), "TTF_Init")
    Text.initialized = true
    if runtime then runtime.text = runtime.text or {} end
    return runtime
end

function Text.shutdown(runtime)
    for _, font in pairs(Text.font_cache) do
        Text.TTF.TTF_CloseFont(font)
    end

    Text.font_cache = {}
    Text.glyph_cache = {}
    Text.text_cache = {}

    if Text.initialized then
        Text.TTF.TTF_Quit()
        Text.initialized = false
    end

    if runtime then runtime.text = nil end
end

function Text.load_font(runtime, font_path, size_px)
    Text.init(runtime)

    if not font_path or font_path == "" then
        error("Text.load_font: explicit font path is required", 2)
    end

    local resolved_size = math.max(1, math.floor((size_px or 16) + 0.5))
    local key = tostring(font_path) .. ":" .. tostring(resolved_size)
    local cached = Text.font_cache[key]
    if cached then return cached end

    local font = Text.TTF.TTF_OpenFont(font_path, resolved_size)
    if font == nil then
        error(("TTF_OpenFont(%s, %d): %s"):format(font_path, resolved_size, ffi.string(Text.SDL.SDL_GetError())), 2)
    end

    Text.font_cache[key] = font
    return font
end

function Text.ensure_atlas(font_ref, size_px)
    local id = pack_atlas_id(font_ref, size_px)
    return id
end

function Text.lookup_atlas(atlas_ref)
    return unpack_atlas_id(atlas_ref)
end

local function normalize_text_value(text_value)
    local raw = text_value and text_value.value or ""
    if type(raw) == "cdata" then
        return ffi.string(raw)
    end
    return raw
end

function Text.measure(runtime, font_path, text_value, text_style, text_layout, max_width)
    local text = normalize_text_value(text_value)
    local size_px = text_style and text_style.size_px or 16
    local font = Text.load_font(runtime, font_path, size_px)

    if text == "" then
        return {
            w = 0,
            h = (text_style and text_style.line_height_px) or Text.TTF.TTF_GetFontHeight(font),
        }
    end

    local w = ffi.new("int[1]", 0)
    local h = ffi.new("int[1]", 0)

    local should_wrap = text_layout
        and text_layout.wrap
        and text_layout.wrap.kind ~= "NoWrap"
        and max_width
        and max_width > 0

    if should_wrap then
        ttf_ok(Text.TTF.TTF_GetStringSizeWrapped(font, text, #text, math.floor(max_width + 0.5), w, h), "TTF_GetStringSizeWrapped")
    else
        ttf_ok(Text.TTF.TTF_GetStringSize(font, text, #text, w, h), "TTF_GetStringSize")
    end

    return {
        w = w[0],
        h = h[0],
    }
end

function Text.rasterize_glyph(font_path, size_px, glyph_id)
    local resolved_size = math.max(1, math.floor((size_px or 16) + 0.5))
    local key = tostring(font_path) .. ":" .. tostring(resolved_size) .. ":" .. tostring(glyph_id)
    local cached = Text.glyph_cache[key]
    if cached then return cached end

    local font = Text.load_font(nil, font_path, resolved_size)
    local metrics = glyph_metrics(font, glyph_id)

    if metrics.maxx <= metrics.minx or metrics.maxy <= metrics.miny then
        cached = {
            cache_key = key,
            glyph_id = glyph_id,
            w = 0,
            h = 0,
            pixels = {},
            minx = metrics.minx,
            maxx = metrics.maxx,
            miny = metrics.miny,
            maxy = metrics.maxy,
            advance = metrics.advance,
        }
        Text.glyph_cache[key] = cached
        return cached
    end

    local surface = Text.TTF.TTF_RenderGlyph_Blended(font, glyph_id, ffi.new("SDL_Color", { 255, 255, 255, 255 }))
    if surface == nil then
        ttf_error("TTF_RenderGlyph_Blended")
    end

    local w = surface.w
    local h = surface.h
    local bytes = surface_to_rgba_bytes(surface)
    Text.SDL.SDL_DestroySurface(surface)

    cached = {
        cache_key = key,
        glyph_id = glyph_id,
        w = w,
        h = h,
        pixels = bytes,
        minx = metrics.minx,
        maxx = metrics.maxx,
        miny = metrics.miny,
        maxy = metrics.maxy,
        advance = metrics.advance,
    }

    Text.glyph_cache[key] = cached
    return cached
end

local function wrap_alignment(align_kind)
    if align_kind == "TextCenter" then return 1 end
    if align_kind == "TextEnd" then return 2 end
    return 0
end

function Text.rasterize_text(font_path, size_px, text, color, wrap_kind, align_kind, bounds_w)
    local resolved_size = math.max(1, math.floor((size_px or 16) + 0.5))
    local key = table.concat({ tostring(font_path), tostring(resolved_size), text or "", tostring(color.r), tostring(color.g), tostring(color.b), tostring(color.a), tostring(wrap_kind), tostring(align_kind), tostring(bounds_w) }, ":")
    local cached = Text.text_cache[key]
    if cached then return cached end

    if text == nil or text == "" then
        cached = { cache_key = key, w = 0, h = 0, pixels = {} }
        Text.text_cache[key] = cached
        return cached
    end

    local font = Text.load_font(nil, font_path, resolved_size)
    local fg = ffi.new("SDL_Color", {
        math.floor((color.r or 1) * 255 + 0.5),
        math.floor((color.g or 1) * 255 + 0.5),
        math.floor((color.b or 1) * 255 + 0.5),
        math.floor((color.a or 1) * 255 + 0.5),
    })
    local wrapped = wrap_kind ~= "NoWrap" and bounds_w and bounds_w > 0
    if wrapped then
        Text.TTF.TTF_SetFontWrapAlignment(font, wrap_alignment(align_kind))
    end
    local surface = wrapped
        and Text.TTF.TTF_RenderText_Blended_Wrapped(font, text or "", #(text or ""), fg, math.max(1, math.floor(bounds_w + 0.5)))
        or Text.TTF.TTF_RenderText_Blended(font, text or "", #(text or ""), fg)
    if surface == nil then
        ttf_error("TTF_RenderText_Blended")
    end

    local w = surface.w
    local h = surface.h
    local bytes = surface_to_rgba_bytes(surface)
    Text.SDL.SDL_DestroySurface(surface)

    cached = {
        cache_key = key,
        w = w,
        h = h,
        pixels = bytes,
    }
    Text.text_cache[key] = cached
    return cached
end

function Text.shape(runtime, font_path, text_value, text_style, text_layout, bounds)
    local text = text_value and text_value.value or ""
    local size_px = text_style and text_style.size_px or 16
    local font = Text.load_font(runtime, font_path, size_px)

    local line_height = (text_style and text_style.line_height_px) or Text.TTF.TTF_GetFontHeight(font)
    local ascent = Text.TTF.TTF_GetFontAscent(font)
    local letter_spacing = (text_style and text_style.letter_spacing_px) or 0
    local x0 = bounds and bounds.x or 0
    local y0 = bounds and bounds.y or 0
    local raw_lines = split_lines(text)
    local line_limit = text_layout and text_layout.line_limit or #raw_lines

    local lines = {}
    local scene_bottom = y0

    for line_index, line_text in ipairs(raw_lines) do
        if line_index > line_limit then break end

        local cps = codepoints(line_text)
        local baseline_y = y0 + (line_index - 1) * line_height + ascent
        local line_w = line_size(font, line_text)
        local cursor_x = x0
        if bounds and text_layout and text_layout.align then
            if text_layout.align.kind == "TextCenter" then
                cursor_x = x0 + math.max(0, (bounds.w - line_w) / 2)
            elseif text_layout.align.kind == "TextEnd" then
                cursor_x = x0 + math.max(0, bounds.w - line_w)
            end
        end
        local previous_glyph = nil
        local glyphs = {}
        local min_x = nil
        local min_y = nil
        local max_x = nil
        local max_y = nil

        for cluster, glyph_id in ipairs(cps) do
            cursor_x = cursor_x + glyph_kerning(font, previous_glyph, glyph_id)

            local m = glyph_metrics(font, glyph_id)
            local gx = cursor_x + m.minx
            local gy = baseline_y - m.maxy
            local gw = math.max(0, m.maxx - m.minx)
            local gh = math.max(0, m.maxy - m.miny)

            glyphs[#glyphs + 1] = {
                glyph_id = glyph_id,
                cluster = cluster,
                origin = { x = gx, y = gy },
                ink_bounds = { x = gx, y = gy, w = gw, h = gh },
            }

            if gw > 0 and gh > 0 then
                min_x = min_x and math.min(min_x, gx) or gx
                min_y = min_y and math.min(min_y, gy) or gy
                max_x = max_x and math.max(max_x, gx + gw) or (gx + gw)
                max_y = max_y and math.max(max_y, gy + gh) or (gy + gh)
            end

            cursor_x = cursor_x + m.advance + letter_spacing
            previous_glyph = glyph_id
        end

        local ink_bounds
        if min_x then
            ink_bounds = {
                x = min_x,
                y = min_y,
                w = max_x - min_x,
                h = max_y - min_y,
            }
        else
            ink_bounds = {
                x = x0,
                y = baseline_y - ascent,
                w = 0,
                h = line_height,
            }
        end

        lines[#lines + 1] = {
            text = line_text,
            baseline_y = baseline_y,
            ink_bounds = ink_bounds,
            runs = {
                {
                    size_px = size_px,
                    glyphs = glyphs,
                }
            },
        }

        scene_bottom = math.max(scene_bottom, baseline_y + math.abs(Text.TTF.TTF_GetFontDescent(font)))
    end

    local measured = Text.measure(runtime, font_path, text_value, text_style, text_layout, bounds and bounds.w or nil)

    return {
        bounds = bounds or { x = x0, y = y0, w = measured.w, h = measured.h },
        baseline_y = y0 + ascent,
        lines = lines,
    }
end

return Text
