-- ============================================================================
-- Canonical UI backend scaffold
-- ----------------------------------------------------------------------------
-- Pure phases above:
--   UiDecl -> UiLaid -> { UiBatched, UiRouted }
--
-- Backend leaves below:
--   UiBatched.Scene -> Unit   (canonical path: one stable runner + scene state_t)
--   UiBatched.Batch -> Unit   (kept as direct leaves, but not the integrated scene path)
--   SDL_Event -> UiInput.Event
--
-- Compiler-side boundary code stays pure and structural.
-- Imperative work belongs in emitted Terra code / Unit state.
-- ============================================================================

local U = require("unit")
local F = require("fun")
local Assets = require("examples.ui.ui_asset_resolve")
local SdlGl = require("examples.ui.backend_sdl_gl")
local Text = require("examples.ui.backend_text_sdl_ttf")

local UiBackend = {}
local C = SdlGl.headers()
local Runtime = SdlGl.runtime_t()
local PROFILE = os.getenv("TERRA_TASKS_PROFILE") == "1"

local BoxItemState = terralib.types.newstruct("UiBoxItemState")
BoxItemState.entries:insert({ field = "x", type = double })
BoxItemState.entries:insert({ field = "y", type = double })
BoxItemState.entries:insert({ field = "w", type = double })
BoxItemState.entries:insert({ field = "h", type = double })
BoxItemState.entries:insert({ field = "fill_r", type = double })
BoxItemState.entries:insert({ field = "fill_g", type = double })
BoxItemState.entries:insert({ field = "fill_b", type = double })
BoxItemState.entries:insert({ field = "fill_a", type = double })
BoxItemState.entries:insert({ field = "stroke_enabled", type = int32 })
BoxItemState.entries:insert({ field = "stroke_r", type = double })
BoxItemState.entries:insert({ field = "stroke_g", type = double })
BoxItemState.entries:insert({ field = "stroke_b", type = double })
BoxItemState.entries:insert({ field = "stroke_a", type = double })
BoxItemState.entries:insert({ field = "stroke_width", type = double })

local TexturedItemState = terralib.types.newstruct("UiTexturedItemState")
TexturedItemState.entries:insert({ field = "tex_id", type = uint32 })
TexturedItemState.entries:insert({ field = "x1", type = double })
TexturedItemState.entries:insert({ field = "y1", type = double })
TexturedItemState.entries:insert({ field = "x2", type = double })
TexturedItemState.entries:insert({ field = "y2", type = double })
TexturedItemState.entries:insert({ field = "r", type = double })
TexturedItemState.entries:insert({ field = "g", type = double })
TexturedItemState.entries:insert({ field = "b", type = double })
TexturedItemState.entries:insert({ field = "a", type = double })

local ShadowItemState = terralib.types.newstruct("UiShadowItemState")
ShadowItemState.entries:insert({ field = "x", type = double })
ShadowItemState.entries:insert({ field = "y", type = double })
ShadowItemState.entries:insert({ field = "w", type = double })
ShadowItemState.entries:insert({ field = "h", type = double })
ShadowItemState.entries:insert({ field = "r", type = double })
ShadowItemState.entries:insert({ field = "g", type = double })
ShadowItemState.entries:insert({ field = "b", type = double })
ShadowItemState.entries:insert({ field = "a", type = double })
ShadowItemState.entries:insert({ field = "blur", type = double })
ShadowItemState.entries:insert({ field = "spread", type = double })
ShadowItemState.entries:insert({ field = "dx", type = double })
ShadowItemState.entries:insert({ field = "dy", type = double })
ShadowItemState.entries:insert({ field = "kind", type = int32 })

local ImageItemState = terralib.types.newstruct("UiImageItemState")
ImageItemState.entries:insert({ field = "x", type = double })
ImageItemState.entries:insert({ field = "y", type = double })
ImageItemState.entries:insert({ field = "w", type = double })
ImageItemState.entries:insert({ field = "h", type = double })
ImageItemState.entries:insert({ field = "opacity", type = double })
ImageItemState.entries:insert({ field = "sampling", type = int32 })

local EffectItemState = terralib.types.newstruct("UiEffectItemState")
EffectItemState.entries:insert({ field = "kind", type = int32 })
EffectItemState.entries:insert({ field = "value", type = double })
EffectItemState.entries:insert({ field = "m11", type = double })
EffectItemState.entries:insert({ field = "m12", type = double })
EffectItemState.entries:insert({ field = "m21", type = double })
EffectItemState.entries:insert({ field = "m22", type = double })
EffectItemState.entries:insert({ field = "tx", type = double })
EffectItemState.entries:insert({ field = "ty", type = double })
EffectItemState.entries:insert({ field = "mode", type = int32 })
EffectItemState.entries:insert({ field = "clip_x", type = double })
EffectItemState.entries:insert({ field = "clip_y", type = double })
EffectItemState.entries:insert({ field = "clip_w", type = double })
EffectItemState.entries:insert({ field = "clip_h", type = double })

local function batch_state_type(name, item_t)
    local S = terralib.types.newstruct(name)
    S.entries:insert({ field = "count", type = int32 })
    S.entries:insert({ field = "clip_enabled", type = int32 })
    S.entries:insert({ field = "clip_x", type = double })
    S.entries:insert({ field = "clip_y", type = double })
    S.entries:insert({ field = "clip_w", type = double })
    S.entries:insert({ field = "clip_h", type = double })
    S.entries:insert({ field = "items", type = &item_t })
    return S
end

local BoxBatchState = batch_state_type("UiBoxBatchState", BoxItemState)
local GlyphBatchState = batch_state_type("UiGlyphBatchState", TexturedItemState)
local TextBatchState = batch_state_type("UiTextBatchState", TexturedItemState)
local ShadowBatchState = batch_state_type("UiShadowBatchState", ShadowItemState)
local ImageBatchState = batch_state_type("UiImageBatchState", ImageItemState)
local EffectBatchState = batch_state_type("UiEffectBatchState", EffectItemState)

local function ptr_t(t)
    return &t
end

local RenderCommandState = terralib.types.newstruct("UiRenderCommandState")
RenderCommandState.entries:insert({ field = "kind", type = int32 })
RenderCommandState.entries:insert({ field = "index", type = int32 })

local SceneState = terralib.types.newstruct("UiSceneRenderState")
SceneState.entries:insert({ field = "command_count", type = int32 })
SceneState.entries:insert({ field = "commands", type = ptr_t(RenderCommandState) })
SceneState.entries:insert({ field = "box_count", type = int32 })
SceneState.entries:insert({ field = "boxes", type = ptr_t(BoxBatchState) })
SceneState.entries:insert({ field = "shadow_count", type = int32 })
SceneState.entries:insert({ field = "shadows", type = ptr_t(ShadowBatchState) })
SceneState.entries:insert({ field = "image_count", type = int32 })
SceneState.entries:insert({ field = "images", type = ptr_t(ImageBatchState) })
SceneState.entries:insert({ field = "glyph_count", type = int32 })
SceneState.entries:insert({ field = "glyphs", type = ptr_t(GlyphBatchState) })
SceneState.entries:insert({ field = "text_count", type = int32 })
SceneState.entries:insert({ field = "texts", type = ptr_t(TextBatchState) })
SceneState.entries:insert({ field = "effect_count", type = int32 })
SceneState.entries:insert({ field = "effects", type = ptr_t(EffectBatchState) })

local function now_ns()
    return tonumber(SdlGl.FFI.SDL_GetTicksNS())
end

local function ms(ns)
    return (ns or 0) / 1000000.0
end

local function clip_fields(clip)
    if not clip then return 0, 0, 0, 0, 0 end
    return 1, clip.x, clip.y, clip.w, clip.h
end

local function stateful_unit(fn, state_t, init, release)
    local unit = U.new(fn, state_t)
    unit.init = init
    unit.release = release
    return unit
end

local CMD_BOX = 1
local CMD_SHADOW = 2
local CMD_IMAGE = 3
local CMD_GLYPH = 4
local CMD_TEXT = 5
local CMD_EFFECT = 6

local box_runner
local glyph_runner
local text_runner
local shadow_runner
local image_runner
local effect_runner
local scene_runner

local function solid_color(brush, context)
    if not brush then return nil end
    if brush.kind ~= "Solid" then
        error(("%s: only UiCore.Brush.Solid is supported, got %s")
            :format(context, tostring(brush.kind)), 3)
    end
    return brush.color
end

local function square_corners(corners)
    return corners.top_left == 0
       and corners.top_right == 0
       and corners.bottom_right == 0
       and corners.bottom_left == 0
end

local function supported_clip_rect(shape, context)
    if not shape then return nil end

    return U.match(shape, {
        ClipRect = function(v)
            return v.rect
        end,
        ClipRoundedRect = function(_)
            error(("%s: ClipRoundedRect is not implemented yet"):format(context), 3)
        end,
    })
end

local function require_square_box(index, item)
    if not square_corners(item.corners) then
        error(("compile_box_batch: rounded corners are not implemented yet (item %d)")
            :format(index), 3)
    end
    return item
end

local function require_known_atlas(batch)
    local atlas = Text.lookup_atlas(batch.atlas)
    if not atlas then
        error(("compile_glyph_batch: unknown atlas ref %s")
            :format(tostring(batch.atlas and batch.atlas.value)), 3)
    end
    if batch.font and atlas.font_id ~= batch.font.value then
        error(("compile_glyph_batch: atlas/font mismatch (atlas font=%s, batch font=%s)")
            :format(tostring(atlas.font_id), tostring(batch.font.value)), 3)
    end
    return atlas
end

local EFFECT_PUSH_OPACITY = 1
local EFFECT_POP_OPACITY = 2
local EFFECT_PUSH_TRANSFORM = 3
local EFFECT_POP_TRANSFORM = 4
local EFFECT_PUSH_BLEND = 5
local EFFECT_POP_BLEND = 6
local EFFECT_PUSH_CLIP = 7
local EFFECT_POP_CLIP = 8

local SHADOW_DROP = 1
local SHADOW_INNER = 2

local BLEND_NORMAL = 1
local BLEND_ADD = 2
local BLEND_MULTIPLY = 3
local BLEND_SCREEN = 4

local function blend_mode_id(mode)
    return U.match(mode, {
        BlendNormal = function() return BLEND_NORMAL end,
        BlendAdd = function() return BLEND_ADD end,
        BlendMultiply = function() return BLEND_MULTIPLY end,
        BlendScreen = function() return BLEND_SCREEN end,
        BlendOverlay = function() error("compile_effect_batch: BlendOverlay is not implemented yet", 3) end,
    })
end

local function create_state_array(item_t, rows)
    local n = math.max(1, #rows)
    local arr = terralib.new(item_t[n], rows)
    return arr, terralib.cast(&item_t, arr)
end

local function compile_items(items, mapper)
    return F.iter(items):enumerate():map(mapper):totable()
end

local function compile_box_item(index, item)
    require_square_box(index, item)
    return {
        rect = item.rect,
        fill = solid_color(item.fill, "compile_box_batch(fill)"),
        stroke = item.stroke and solid_color(item.stroke, "compile_box_batch(stroke)") or nil,
        stroke_width = item.stroke_width,
    }
end

local function compile_glyph_item(font_path, size_px, index, item)
    local glyph = Text.rasterize_glyph(font_path, size_px, item.glyph_id)
    local texture = (glyph.w > 0 and glyph.h > 0)
        and SdlGl.ensure_rgba_texture(glyph.cache_key, glyph.w, glyph.h, glyph.pixels, "Linear")
        or nil
    return {
        origin = item.origin,
        color = item.color,
        glyph = glyph,
        texture = texture,
    }
end

local function compile_text_item(font_path, size_px, index, item)
    local rendered = Text.rasterize_text(font_path, size_px, item.text, item.color, item.wrap.kind, item.align.kind, item.bounds.w)
    local texture = (rendered.w > 0 and rendered.h > 0)
        and SdlGl.ensure_rgba_texture(rendered.cache_key, rendered.w, rendered.h, rendered.pixels, "Linear")
        or nil
    local x = item.bounds.x
    if item.wrap.kind == "NoWrap" then
        if item.align.kind == "TextCenter" then
            x = x + math.max(0, (item.bounds.w - rendered.w) / 2)
        elseif item.align.kind == "TextEnd" then
            x = x + math.max(0, item.bounds.w - rendered.w)
        end
    end
    return {
        origin = { x = x, y = item.bounds.y },
        color = item.color,
        text = rendered,
        texture = texture,
    }
end

local function compile_shadow_item(index, item)
    require_square_box(index, item)
    return {
        rect = item.rect,
        color = solid_color(item.brush, "compile_shadow_batch(brush)"),
        blur = math.max(0, item.blur),
        spread = item.spread,
        dx = item.dx,
        dy = item.dy,
        kind = item.kind,
    }
end

local function compile_image_item(index, item)
    if item.style.corners and not square_corners(item.style.corners) then
        error(("compile_image_batch: rounded image corners are not implemented yet (item %d)")
            :format(index), 3)
    end

    if item.style.fit.kind ~= "StretchImage" then
        error(("compile_image_batch: only UiCore.ImageFit.StretchImage is supported right now (item %d, got %s)")
            :format(index, tostring(item.style.fit.kind)), 3)
    end

    if item.style.sampling.kind ~= "Linear" and item.style.sampling.kind ~= "Nearest" then
        error(("compile_image_batch: unsupported sampling kind at item %d: %s")
            :format(index, tostring(item.style.sampling.kind)), 3)
    end

    return {
        rect = item.rect,
        style = item.style,
    }
end

local function batch_payload(clip, item_rows)
    local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_fields(clip)
    return {
        count = #item_rows,
        clip_enabled = clip_enabled,
        clip_x = clip_x,
        clip_y = clip_y,
        clip_w = clip_w,
        clip_h = clip_h,
        item_rows = item_rows,
    }
end

local function pack_box_batch(batch)
    local clip = supported_clip_rect(batch.clip, "compile_box_batch(clip)")
    local items = compile_items(batch.items, compile_box_item)
    local item_rows = F.iter(items):map(function(item)
        return {
            item.rect.x, item.rect.y, item.rect.w, item.rect.h,
            item.fill.r, item.fill.g, item.fill.b, item.fill.a,
            item.stroke and 1 or 0,
            item.stroke and item.stroke.r or 0, item.stroke and item.stroke.g or 0, item.stroke and item.stroke.b or 0, item.stroke and item.stroke.a or 0,
            item.stroke_width,
        }
    end):totable()
    return batch_payload(clip, item_rows)
end

local function pack_glyph_batch(batch, assets)
    local atlas = require_known_atlas(batch)
    local font_path = Assets.font_path(assets, batch.font)
    local clip = supported_clip_rect(batch.clip, "compile_glyph_batch(clip)")
    local items = compile_items(batch.items, function(index, item)
        return compile_glyph_item(font_path, atlas.size_px, index, item)
    end)
    local visible_items = F.iter(items):filter(function(item)
        return item.glyph.w > 0 and item.glyph.h > 0
    end):totable()
    local item_rows = F.iter(visible_items):map(function(item)
        return {
            item.texture.id,
            item.origin.x,
            item.origin.y,
            item.origin.x + item.glyph.w,
            item.origin.y + item.glyph.h,
            item.color.r,
            item.color.g,
            item.color.b,
            item.color.a,
        }
    end):totable()
    return batch_payload(clip, item_rows)
end

local function pack_text_batch(batch, assets)
    local clip = supported_clip_rect(batch.clip, "compile_text_batch(clip)")
    local font_path = Assets.font_path(assets, batch.font)
    local items = compile_items(batch.items, function(index, item)
        return compile_text_item(font_path, batch.size_px, index, item)
    end)
    local visible_items = F.iter(items):filter(function(item)
        return item.text.w > 0 and item.text.h > 0
    end):totable()
    local item_rows = F.iter(visible_items):map(function(item)
        return {
            item.texture.id,
            item.origin.x,
            item.origin.y,
            item.origin.x + item.text.w,
            item.origin.y + item.text.h,
            1.0,
            1.0,
            1.0,
            1.0,
        }
    end):totable()
    return batch_payload(clip, item_rows)
end

local function pack_shadow_batch(batch)
    local clip = supported_clip_rect(batch.clip, "compile_shadow_batch(clip)")
    local items = compile_items(batch.items, compile_shadow_item)
    local item_rows = F.iter(items):map(function(item)
        return {
            item.rect.x,
            item.rect.y,
            item.rect.w,
            item.rect.h,
            item.color.r,
            item.color.g,
            item.color.b,
            item.color.a,
            item.blur,
            item.spread,
            item.dx,
            item.dy,
            item.kind.kind == "DropShadow" and SHADOW_DROP or SHADOW_INNER,
        }
    end):totable()
    return batch_payload(clip, item_rows)
end

local function pack_image_batch(batch, assets)
    Assets.image_path(assets, batch.image)
    local clip = supported_clip_rect(batch.clip, "compile_image_batch(clip)")
    local items = compile_items(batch.items, compile_image_item)
    local item_rows = F.iter(items):map(function(item)
        return {
            item.rect.x,
            item.rect.y,
            item.rect.w,
            item.rect.h,
            item.style.opacity or 1.0,
            batch.sampling.kind == "Nearest" and 1 or 0,
        }
    end):totable()
    return batch_payload(clip, item_rows)
end

local function pack_effect_batch(batch)
    local clip = supported_clip_rect(batch.clip, "compile_effect_batch(clip)")
    validate_effect_items(batch.items)
    local item_rows = F.iter(batch.items):map(function(item)
        return U.match(item, {
            PushOpacity = function(v) return { EFFECT_PUSH_OPACITY, v.value, 0,0,0,0,0,0,0, 0,0,0,0 } end,
            PopOpacity = function() return { EFFECT_POP_OPACITY, 0, 0,0,0,0,0,0,0, 0,0,0,0 } end,
            PushTransform = function(v) return { EFFECT_PUSH_TRANSFORM, 0, v.xform.m11, v.xform.m12, v.xform.m21, v.xform.m22, v.xform.tx, v.xform.ty, 0, 0,0,0,0 } end,
            PopTransform = function() return { EFFECT_POP_TRANSFORM, 0, 0,0,0,0,0,0,0, 0,0,0,0 } end,
            PushBlend = function(v) return { EFFECT_PUSH_BLEND, 0, 0,0,0,0,0,0, blend_mode_id(v.mode), 0,0,0,0 } end,
            PopBlend = function() return { EFFECT_POP_BLEND, 0, 0,0,0,0,0,0,0, 0,0,0,0 } end,
            PushClip = function(v)
                local r = supported_clip_rect(v.shape, "compile_effect_batch(PushClip)")
                return { EFFECT_PUSH_CLIP, 0, 0,0,0,0,0,0,0, r.x,r.y,r.w,r.h }
            end,
            PopClip = function() return { EFFECT_POP_CLIP, 0, 0,0,0,0,0,0,0, 0,0,0,0 } end,
        })
    end):totable()
    return batch_payload(clip, item_rows)
end

local function offset_rect(rect, dx, dy)
    return {
        x = rect.x + dx,
        y = rect.y + dy,
        w = rect.w,
        h = rect.h,
    }
end

local function inflate_rect(rect, amount)
    return {
        x = rect.x - amount,
        y = rect.y - amount,
        w = rect.w + amount * 2,
        h = rect.h + amount * 2,
    }
end

local function rect_valid(rect)
    return rect.w > 0 and rect.h > 0
end

local function color_with_alpha(color, alpha)
    return {
        r = color.r,
        g = color.g,
        b = color.b,
        a = alpha,
    }
end

local function shadow_pass_count(blur)
    return math.max(1, math.min(16, math.ceil(blur)))
end

local function emit_solid_quad(rt, rect, color)
    local x1, y1 = rect.x, rect.y
    local x2, y2 = rect.x + rect.w, rect.y + rect.h
    return quote
        C.glColor4d([double](color.r), [double](color.g), [double](color.b), [double](color.a) * rt.opacity)
        C.glBegin(C.GL_QUADS)
        C.glVertex2d([double](x1), [double](y1))
        C.glVertex2d([double](x2), [double](y1))
        C.glVertex2d([double](x2), [double](y2))
        C.glVertex2d([double](x1), [double](y2))
        C.glEnd()
    end
end

local function emit_stroke_loop(rt, rect, color, stroke_width)
    local x1, y1 = rect.x, rect.y
    local x2, y2 = rect.x + rect.w, rect.y + rect.h
    return quote
        C.glLineWidth([float](stroke_width))
        C.glColor4d([double](color.r), [double](color.g), [double](color.b), [double](color.a) * rt.opacity)
        C.glBegin(C.GL_LINE_LOOP)
        C.glVertex2d([double](x1), [double](y1))
        C.glVertex2d([double](x2), [double](y1))
        C.glVertex2d([double](x2), [double](y2))
        C.glVertex2d([double](x1), [double](y2))
        C.glEnd()
    end
end

local function emit_box_item(rt, item)
    local fill = emit_solid_quad(rt, item.rect, item.fill)
    if item.stroke and item.stroke_width > 0 then
        local stroke = emit_stroke_loop(rt, item.rect, item.stroke, item.stroke_width)
        return quote
            [fill]
            [stroke]
        end
    end
    return fill
end

local function emit_glyph_item(rt, item)
    local glyph = item.glyph
    local tex_id = item.texture.id
    local x1 = item.origin.x
    local y1 = item.origin.y
    local x2 = x1 + glyph.w
    local y2 = y1 + glyph.h

    return quote
        C.glBindTexture(C.GL_TEXTURE_2D, [uint32](tex_id))
        C.glColor4d([double](item.color.r), [double](item.color.g), [double](item.color.b), [double](item.color.a) * rt.opacity)
        C.glBegin(C.GL_QUADS)
        C.glTexCoord2d(0.0, 0.0)
        C.glVertex2d([double](x1), [double](y1))
        C.glTexCoord2d(1.0, 0.0)
        C.glVertex2d([double](x2), [double](y1))
        C.glTexCoord2d(1.0, 1.0)
        C.glVertex2d([double](x2), [double](y2))
        C.glTexCoord2d(0.0, 1.0)
        C.glVertex2d([double](x1), [double](y2))
        C.glEnd()
    end
end

local function emit_text_item(rt, item)
    local rendered = item.text
    local tex_id = item.texture.id
    local x1 = item.origin.x
    local y1 = item.origin.y
    local x2 = x1 + rendered.w
    local y2 = y1 + rendered.h

    return quote
        C.glBindTexture(C.GL_TEXTURE_2D, [uint32](tex_id))
        C.glColor4d(1.0, 1.0, 1.0, rt.opacity)
        C.glBegin(C.GL_QUADS)
        C.glTexCoord2d(0.0, 0.0)
        C.glVertex2d([double](x1), [double](y1))
        C.glTexCoord2d(1.0, 0.0)
        C.glVertex2d([double](x2), [double](y1))
        C.glTexCoord2d(1.0, 1.0)
        C.glVertex2d([double](x2), [double](y2))
        C.glTexCoord2d(0.0, 1.0)
        C.glVertex2d([double](x1), [double](y2))
        C.glEnd()
    end
end

local function emit_rect_bands(rt, outer_rect, inner_rect, color)
    local bands = F.iter({
        {
            x = outer_rect.x,
            y = outer_rect.y,
            w = outer_rect.w,
            h = inner_rect.y - outer_rect.y,
        },
        {
            x = outer_rect.x,
            y = inner_rect.y + inner_rect.h,
            w = outer_rect.w,
            h = (outer_rect.y + outer_rect.h) - (inner_rect.y + inner_rect.h),
        },
        {
            x = outer_rect.x,
            y = inner_rect.y,
            w = inner_rect.x - outer_rect.x,
            h = inner_rect.h,
        },
        {
            x = inner_rect.x + inner_rect.w,
            y = inner_rect.y,
            w = (outer_rect.x + outer_rect.w) - (inner_rect.x + inner_rect.w),
            h = inner_rect.h,
        },
    })
        :filter(rect_valid)
        :map(function(rect)
            return emit_solid_quad(rt, rect, color)
        end)
        :totable()

    return quote
        escape
            for _, band in ipairs(bands) do
                emit(band)
            end
        end
    end
end

local function emit_push_clip(rt, rect)
    local x = math.floor(rect.x + 0.5)
    local y = math.floor(rect.y + 0.5)
    local r = math.floor(rect.x + rect.w + 0.5)
    local b = math.floor(rect.y + rect.h + 0.5)

    return quote
        rt.clip_enabled_stack[rt.clip_top] = rt.clip_enabled
        rt.clip_stack[rt.clip_top].x = rt.clip_x
        rt.clip_stack[rt.clip_top].y = rt.clip_y
        rt.clip_stack[rt.clip_top].w = rt.clip_w
        rt.clip_stack[rt.clip_top].h = rt.clip_h
        rt.clip_top = rt.clip_top + 1

        var nx : int32 = [int32](x)
        var ny : int32 = [int32](y)
        var nr : int32 = [int32](r)
        var nb : int32 = [int32](b)

        if nx < 0 then nx = 0 end
        if ny < 0 then ny = 0 end
        if nr > rt.width then nr = rt.width end
        if nb > rt.height then nb = rt.height end

        if rt.clip_enabled ~= 0 then
            if nx < rt.clip_x then nx = rt.clip_x end
            if ny < rt.clip_y then ny = rt.clip_y end
            if nr > rt.clip_x + rt.clip_w then nr = rt.clip_x + rt.clip_w end
            if nb > rt.clip_y + rt.clip_h then nb = rt.clip_y + rt.clip_h end
        end

        if nr < nx then nr = nx end
        if nb < ny then nb = ny end

        rt.clip_enabled = 1
        rt.clip_x = nx
        rt.clip_y = ny
        rt.clip_w = nr - nx
        rt.clip_h = nb - ny

        C.glEnable(C.GL_SCISSOR_TEST)
        C.glScissor(rt.clip_x, rt.height - (rt.clip_y + rt.clip_h), rt.clip_w, rt.clip_h)
    end
end

local function emit_pop_clip(rt)
    return quote
        rt.clip_top = rt.clip_top - 1
        rt.clip_enabled = rt.clip_enabled_stack[rt.clip_top]
        rt.clip_x = rt.clip_stack[rt.clip_top].x
        rt.clip_y = rt.clip_stack[rt.clip_top].y
        rt.clip_w = rt.clip_stack[rt.clip_top].w
        rt.clip_h = rt.clip_stack[rt.clip_top].h

        if rt.clip_enabled ~= 0 then
            C.glEnable(C.GL_SCISSOR_TEST)
            C.glScissor(rt.clip_x, rt.height - (rt.clip_y + rt.clip_h), rt.clip_w, rt.clip_h)
        else
            C.glDisable(C.GL_SCISSOR_TEST)
        end
    end
end

local function emit_drop_shadow_item(rt, item)
    local base_rect = inflate_rect(offset_rect(item.rect, item.dx, item.dy), item.spread)
    local passes = shadow_pass_count(item.blur)
    local draw_ops = F.iter(F.range(1, passes)):map(function(i)
        local expansion = item.blur <= 0 and 0 or (item.blur * (passes - i + 1) / passes)
        local alpha = item.blur <= 0 and item.color.a or (item.color.a / passes)
        return emit_solid_quad(rt, inflate_rect(base_rect, expansion), color_with_alpha(item.color, alpha))
    end):totable()

    return quote
        escape
            for _, draw in ipairs(draw_ops) do
                emit(draw)
            end
        end
    end
end

local function emit_inner_shadow_item(rt, item)
    local clip_push = emit_push_clip(rt, item.rect)
    local clip_pop = emit_pop_clip(rt)
    local source_rect = inflate_rect(offset_rect(item.rect, item.dx, item.dy), item.spread)
    local passes = shadow_pass_count(item.blur)
    local draw_ops = F.iter(F.range(1, passes)):map(function(i)
        local outer_inset = item.blur <= 0 and 0 or (item.blur * (i - 1) / passes)
        local inner_inset = item.blur <= 0 and 1 or (item.blur * i / passes)
        local outer_rect = inflate_rect(source_rect, -outer_inset)
        local inner_rect = inflate_rect(source_rect, -inner_inset)
        local alpha = item.blur <= 0 and item.color.a or (item.color.a / passes)
        return emit_rect_bands(rt, outer_rect, inner_rect, color_with_alpha(item.color, alpha))
    end):totable()

    return quote
        [clip_push]
        escape
            for _, draw in ipairs(draw_ops) do
                emit(draw)
            end
        end
        [clip_pop]
    end
end

local function emit_shadow_item(rt, item)
    return U.match(item.kind, {
        DropShadow = function()
            return emit_drop_shadow_item(rt, item)
        end,
        InnerShadow = function()
            return emit_inner_shadow_item(rt, item)
        end,
    })
end

local function emit_image_item(rt, image, sampling, item)
    local rect = item.rect
    local color = {
        r = 0.45,
        g = 0.45,
        b = 0.48,
        a = item.style.opacity or 1.0,
    }
    local border = {
        r = 0.75,
        g = 0.75,
        b = 0.78,
        a = item.style.opacity or 1.0,
    }
    local fill = emit_solid_quad(rt, rect, color)
    local stroke = emit_stroke_loop(rt, rect, border, sampling.kind == "Nearest" and 2 or 1)

    return quote
        [fill]
        [stroke]
    end
end

local function blend_push_quote(mode)
    return U.match(mode, {
        BlendNormal = function()
            return quote
                C.glPushAttrib(C.GL_COLOR_BUFFER_BIT)
                C.glEnable(C.GL_BLEND)
                C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
            end
        end,
        BlendAdd = function()
            return quote
                C.glPushAttrib(C.GL_COLOR_BUFFER_BIT)
                C.glEnable(C.GL_BLEND)
                C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE)
            end
        end,
        BlendMultiply = function()
            return quote
                C.glPushAttrib(C.GL_COLOR_BUFFER_BIT)
                C.glEnable(C.GL_BLEND)
                C.glBlendFunc(C.GL_DST_COLOR, C.GL_ONE_MINUS_SRC_ALPHA)
            end
        end,
        BlendScreen = function()
            return quote
                C.glPushAttrib(C.GL_COLOR_BUFFER_BIT)
                C.glEnable(C.GL_BLEND)
                C.glBlendFunc(C.GL_ONE, C.GL_ONE_MINUS_SRC_COLOR)
            end
        end,
        BlendOverlay = function()
            error("compile_effect_batch: BlendOverlay is not implemented yet", 3)
        end,
    })
end

local function effect_balance_step(state, index, item)
    return U.match(item, {
        PushOpacity = function(_)
            return {
                opacity = state.opacity + 1,
                transform = state.transform,
                blend = state.blend,
                clip = state.clip,
            }
        end,
        PopOpacity = function()
            if state.opacity <= 0 then
                error(("compile_effect_batch: PopOpacity underflow at item %d"):format(index), 3)
            end
            return {
                opacity = state.opacity - 1,
                transform = state.transform,
                blend = state.blend,
                clip = state.clip,
            }
        end,
        PushTransform = function(_)
            return {
                opacity = state.opacity,
                transform = state.transform + 1,
                blend = state.blend,
                clip = state.clip,
            }
        end,
        PopTransform = function()
            if state.transform <= 0 then
                error(("compile_effect_batch: PopTransform underflow at item %d"):format(index), 3)
            end
            return {
                opacity = state.opacity,
                transform = state.transform - 1,
                blend = state.blend,
                clip = state.clip,
            }
        end,
        PushBlend = function(v)
            blend_push_quote(v.mode)
            return {
                opacity = state.opacity,
                transform = state.transform,
                blend = state.blend + 1,
                clip = state.clip,
            }
        end,
        PopBlend = function()
            if state.blend <= 0 then
                error(("compile_effect_batch: PopBlend underflow at item %d"):format(index), 3)
            end
            return {
                opacity = state.opacity,
                transform = state.transform,
                blend = state.blend - 1,
                clip = state.clip,
            }
        end,
        PushClip = function(v)
            supported_clip_rect(v.shape, ("compile_effect_batch(PushClip item %d)"):format(index))
            return {
                opacity = state.opacity,
                transform = state.transform,
                blend = state.blend,
                clip = state.clip + 1,
            }
        end,
        PopClip = function()
            if state.clip <= 0 then
                error(("compile_effect_batch: PopClip underflow at item %d"):format(index), 3)
            end
            return {
                opacity = state.opacity,
                transform = state.transform,
                blend = state.blend,
                clip = state.clip - 1,
            }
        end,
    })
end

local function validate_effect_items(items)
    local final = F.iter(items):enumerate():reduce(effect_balance_step, {
        opacity = 0,
        transform = 0,
        blend = 0,
        clip = 0,
    })

    if final.opacity ~= 0 then
        error("compile_effect_batch: unbalanced opacity push/pop", 2)
    end
    if final.transform ~= 0 then
        error("compile_effect_batch: unbalanced transform push/pop", 2)
    end
    if final.blend ~= 0 then
        error("compile_effect_batch: unbalanced blend push/pop", 2)
    end
    if final.clip ~= 0 then
        error("compile_effect_batch: unbalanced clip push/pop", 2)
    end

    return items
end

local function emit_effect_item(rt, item)
    return U.match(item, {
        PushOpacity = function(v)
            return quote
                rt.opacity_stack[rt.opacity_top] = rt.opacity
                rt.opacity_top = rt.opacity_top + 1
                rt.opacity = rt.opacity * [double](v.value)
            end
        end,
        PopOpacity = function()
            return quote
                rt.opacity_top = rt.opacity_top - 1
                rt.opacity = rt.opacity_stack[rt.opacity_top]
            end
        end,
        PushTransform = function(v)
            local matrix = terralib.constant(terralib.new(double[16], {
                v.xform.m11, v.xform.m12, 0.0, 0.0,
                v.xform.m21, v.xform.m22, 0.0, 0.0,
                0.0,        0.0,        1.0, 0.0,
                v.xform.tx, v.xform.ty, 0.0, 1.0,
            }))
            return quote
                var mx = [matrix]
                C.glMatrixMode(C.GL_MODELVIEW)
                C.glPushMatrix()
                C.glMultMatrixd(&mx[0])
            end
        end,
        PopTransform = function()
            return quote
                C.glMatrixMode(C.GL_MODELVIEW)
                C.glPopMatrix()
            end
        end,
        PushBlend = function(v)
            return blend_push_quote(v.mode)
        end,
        PopBlend = function()
            return quote
                C.glPopAttrib()
            end
        end,
        PushClip = function(v)
            return emit_push_clip(rt, supported_clip_rect(v.shape, "compile_effect_batch(PushClip)"))
        end,
        PopClip = function()
            return emit_pop_clip(rt)
        end,
    })
end

local runtime_push_clip = terra(rt : &Runtime, x : double, y : double, w : double, h : double)
    var nx : int32 = x + 0.5
    var ny : int32 = y + 0.5
    var nr : int32 = x + w + 0.5
    var nb : int32 = y + h + 0.5

    rt.clip_enabled_stack[rt.clip_top] = rt.clip_enabled
    rt.clip_stack[rt.clip_top].x = rt.clip_x
    rt.clip_stack[rt.clip_top].y = rt.clip_y
    rt.clip_stack[rt.clip_top].w = rt.clip_w
    rt.clip_stack[rt.clip_top].h = rt.clip_h
    rt.clip_top = rt.clip_top + 1

    if nx < 0 then nx = 0 end
    if ny < 0 then ny = 0 end
    if nr > rt.width then nr = rt.width end
    if nb > rt.height then nb = rt.height end

    if rt.clip_enabled ~= 0 then
        if nx < rt.clip_x then nx = rt.clip_x end
        if ny < rt.clip_y then ny = rt.clip_y end
        if nr > rt.clip_x + rt.clip_w then nr = rt.clip_x + rt.clip_w end
        if nb > rt.clip_y + rt.clip_h then nb = rt.clip_y + rt.clip_h end
    end

    if nr < nx then nr = nx end
    if nb < ny then nb = ny end

    rt.clip_enabled = 1
    rt.clip_x = nx
    rt.clip_y = ny
    rt.clip_w = nr - nx
    rt.clip_h = nb - ny

    C.glEnable(C.GL_SCISSOR_TEST)
    C.glScissor(rt.clip_x, rt.height - (rt.clip_y + rt.clip_h), rt.clip_w, rt.clip_h)
end
runtime_push_clip:compile()

local runtime_pop_clip = terra(rt : &Runtime)
    rt.clip_top = rt.clip_top - 1
    rt.clip_enabled = rt.clip_enabled_stack[rt.clip_top]
    rt.clip_x = rt.clip_stack[rt.clip_top].x
    rt.clip_y = rt.clip_stack[rt.clip_top].y
    rt.clip_w = rt.clip_stack[rt.clip_top].w
    rt.clip_h = rt.clip_stack[rt.clip_top].h

    if rt.clip_enabled ~= 0 then
        C.glEnable(C.GL_SCISSOR_TEST)
        C.glScissor(rt.clip_x, rt.height - (rt.clip_y + rt.clip_h), rt.clip_w, rt.clip_h)
    else
        C.glDisable(C.GL_SCISSOR_TEST)
    end
end
runtime_pop_clip:compile()

local draw_solid_quad_rt = terra(rt : &Runtime, x : double, y : double, w : double, h : double, r : double, g : double, b : double, a : double)
    C.glColor4d(r, g, b, a * rt.opacity)
    C.glBegin(C.GL_QUADS)
    C.glVertex2d(x, y)
    C.glVertex2d(x + w, y)
    C.glVertex2d(x + w, y + h)
    C.glVertex2d(x, y + h)
    C.glEnd()
end
draw_solid_quad_rt:compile()

local draw_stroke_loop_rt = terra(rt : &Runtime, x : double, y : double, w : double, h : double, r : double, g : double, b : double, a : double, stroke_width : double)
    C.glLineWidth(stroke_width)
    C.glColor4d(r, g, b, a * rt.opacity)
    C.glBegin(C.GL_LINE_LOOP)
    C.glVertex2d(x, y)
    C.glVertex2d(x + w, y)
    C.glVertex2d(x + w, y + h)
    C.glVertex2d(x, y + h)
    C.glEnd()
end
draw_stroke_loop_rt:compile()

local function get_box_runner()
    if box_runner then return box_runner end
    box_runner = terra(rt : &Runtime, state : &BoxBatchState)
        C.glEnable(C.GL_BLEND)
        C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
        C.glDisable(C.GL_TEXTURE_2D)
        if state.clip_enabled ~= 0 then runtime_push_clip(rt, state.clip_x, state.clip_y, state.clip_w, state.clip_h) end
        var i : int32 = 0
        while i < state.count do
            var item = state.items[i]
            draw_solid_quad_rt(rt, item.x, item.y, item.w, item.h, item.fill_r, item.fill_g, item.fill_b, item.fill_a)
            if item.stroke_enabled ~= 0 and item.stroke_width > 0 then
                draw_stroke_loop_rt(rt, item.x, item.y, item.w, item.h, item.stroke_r, item.stroke_g, item.stroke_b, item.stroke_a, item.stroke_width)
            end
            i = i + 1
        end
        if state.clip_enabled ~= 0 then runtime_pop_clip(rt) end
    end
    box_runner:compile()
    return box_runner
end

local function get_textured_runner(state_t)
    return terralib.memoize(function(_)
        local fn = terra(rt : &Runtime, state : &state_t)
            C.glEnable(C.GL_BLEND)
            C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
            C.glEnable(C.GL_TEXTURE_2D)
            if state.clip_enabled ~= 0 then runtime_push_clip(rt, state.clip_x, state.clip_y, state.clip_w, state.clip_h) end
            var i : int32 = 0
            while i < state.count do
                var item = state.items[i]
                C.glBindTexture(C.GL_TEXTURE_2D, item.tex_id)
                C.glColor4d(item.r, item.g, item.b, item.a * rt.opacity)
                C.glBegin(C.GL_QUADS)
                C.glTexCoord2d(0.0, 0.0)
                C.glVertex2d(item.x1, item.y1)
                C.glTexCoord2d(1.0, 0.0)
                C.glVertex2d(item.x2, item.y1)
                C.glTexCoord2d(1.0, 1.0)
                C.glVertex2d(item.x2, item.y2)
                C.glTexCoord2d(0.0, 1.0)
                C.glVertex2d(item.x1, item.y2)
                C.glEnd()
                i = i + 1
            end
            if state.clip_enabled ~= 0 then runtime_pop_clip(rt) end
            C.glDisable(C.GL_TEXTURE_2D)
        end
        fn:compile()
        return fn
    end)(state_t)
end

local function get_shadow_runner()
    if shadow_runner then return shadow_runner end
    shadow_runner = terra(rt : &Runtime, state : &ShadowBatchState)
        C.glEnable(C.GL_BLEND)
        C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
        C.glDisable(C.GL_TEXTURE_2D)
        if state.clip_enabled ~= 0 then runtime_push_clip(rt, state.clip_x, state.clip_y, state.clip_w, state.clip_h) end
        var i : int32 = 0
        while i < state.count do
            var item = state.items[i]
            if item.kind == SHADOW_DROP then
                var passes : int32 = 1
                if item.blur > 0 then
                    passes = [int32](item.blur + 0.999999)
                end
                if passes > 16 then passes = 16 end
                var j : int32 = 0
                while j < passes do
                    var expansion = 0.0
                    if item.blur > 0 then
                        expansion = item.blur * (passes - j) / passes
                    end
                    var alpha = item.a
                    if item.blur > 0 then
                        alpha = item.a / passes
                    end
                    draw_solid_quad_rt(rt, item.x + item.dx - item.spread - expansion, item.y + item.dy - item.spread - expansion, item.w + 2 * (item.spread + expansion), item.h + 2 * (item.spread + expansion), item.r, item.g, item.b, alpha)
                    j = j + 1
                end
            else
                runtime_push_clip(rt, item.x, item.y, item.w, item.h)
                var passes : int32 = 1
                if item.blur > 0 then
                    passes = [int32](item.blur + 0.999999)
                end
                if passes > 16 then passes = 16 end
                var j : int32 = 0
                while j < passes do
                    var outer_inset = 0.0
                    var inner_inset = 1.0
                    if item.blur > 0 then
                        outer_inset = item.blur * j / passes
                        inner_inset = item.blur * (j + 1) / passes
                    end
                    var source_x = item.x + item.dx - item.spread
                    var source_y = item.y + item.dy - item.spread
                    var source_w = item.w + 2 * item.spread
                    var source_h = item.h + 2 * item.spread
                    var ox = source_x + outer_inset
                    var oy = source_y + outer_inset
                    var ow = source_w - 2 * outer_inset
                    var oh = source_h - 2 * outer_inset
                    var ix = source_x + inner_inset
                    var iy = source_y + inner_inset
                    var iw = source_w - 2 * inner_inset
                    var ih = source_h - 2 * inner_inset
                    var alpha = item.a
                    if item.blur > 0 then
                        alpha = item.a / passes
                    end
                    if oh > 0 and ow > 0 then
                        if iy > oy then draw_solid_quad_rt(rt, ox, oy, ow, iy - oy, item.r, item.g, item.b, alpha) end
                        if oy + oh > iy + ih then draw_solid_quad_rt(rt, ox, iy + ih, ow, (oy + oh) - (iy + ih), item.r, item.g, item.b, alpha) end
                        if ix > ox and ih > 0 then draw_solid_quad_rt(rt, ox, iy, ix - ox, ih, item.r, item.g, item.b, alpha) end
                        if ox + ow > ix + iw and ih > 0 then draw_solid_quad_rt(rt, ix + iw, iy, (ox + ow) - (ix + iw), ih, item.r, item.g, item.b, alpha) end
                    end
                    j = j + 1
                end
                runtime_pop_clip(rt)
            end
            i = i + 1
        end
        if state.clip_enabled ~= 0 then runtime_pop_clip(rt) end
    end
    shadow_runner:compile()
    return shadow_runner
end

local function get_image_runner()
    if image_runner then return image_runner end
    image_runner = terra(rt : &Runtime, state : &ImageBatchState)
        C.glEnable(C.GL_BLEND)
        C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
        C.glDisable(C.GL_TEXTURE_2D)
        if state.clip_enabled ~= 0 then runtime_push_clip(rt, state.clip_x, state.clip_y, state.clip_w, state.clip_h) end
        var i : int32 = 0
        while i < state.count do
            var item = state.items[i]
            var stroke_width = 1.0
            if item.sampling == 1 then stroke_width = 2.0 end
            draw_solid_quad_rt(rt, item.x, item.y, item.w, item.h, 0.45, 0.45, 0.48, item.opacity)
            draw_stroke_loop_rt(rt, item.x, item.y, item.w, item.h, 0.75, 0.75, 0.78, item.opacity, stroke_width)
            i = i + 1
        end
        if state.clip_enabled ~= 0 then runtime_pop_clip(rt) end
    end
    image_runner:compile()
    return image_runner
end

local function get_effect_runner()
    if effect_runner then return effect_runner end
    effect_runner = terra(rt : &Runtime, state : &EffectBatchState)
        var i : int32 = 0
        if state.clip_enabled ~= 0 then runtime_push_clip(rt, state.clip_x, state.clip_y, state.clip_w, state.clip_h) end
        while i < state.count do
            var item = state.items[i]
            if item.kind == EFFECT_PUSH_OPACITY then
                rt.opacity_stack[rt.opacity_top] = rt.opacity
                rt.opacity_top = rt.opacity_top + 1
                rt.opacity = rt.opacity * item.value
            elseif item.kind == EFFECT_POP_OPACITY then
                rt.opacity_top = rt.opacity_top - 1
                rt.opacity = rt.opacity_stack[rt.opacity_top]
            elseif item.kind == EFFECT_PUSH_TRANSFORM then
                var mx : double[16]
                mx[0], mx[1], mx[2], mx[3] = item.m11, item.m12, 0.0, 0.0
                mx[4], mx[5], mx[6], mx[7] = item.m21, item.m22, 0.0, 0.0
                mx[8], mx[9], mx[10], mx[11] = 0.0, 0.0, 1.0, 0.0
                mx[12], mx[13], mx[14], mx[15] = item.tx, item.ty, 0.0, 1.0
                C.glMatrixMode(C.GL_MODELVIEW)
                C.glPushMatrix()
                C.glMultMatrixd(&mx[0])
            elseif item.kind == EFFECT_POP_TRANSFORM then
                C.glMatrixMode(C.GL_MODELVIEW)
                C.glPopMatrix()
            elseif item.kind == EFFECT_PUSH_BLEND then
                C.glPushAttrib(C.GL_COLOR_BUFFER_BIT)
                C.glEnable(C.GL_BLEND)
                if item.mode == BLEND_NORMAL then
                    C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
                elseif item.mode == BLEND_ADD then
                    C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE)
                elseif item.mode == BLEND_MULTIPLY then
                    C.glBlendFunc(C.GL_DST_COLOR, C.GL_ONE_MINUS_SRC_ALPHA)
                else
                    C.glBlendFunc(C.GL_ONE, C.GL_ONE_MINUS_SRC_COLOR)
                end
            elseif item.kind == EFFECT_POP_BLEND then
                C.glPopAttrib()
            elseif item.kind == EFFECT_PUSH_CLIP then
                runtime_push_clip(rt, item.clip_x, item.clip_y, item.clip_w, item.clip_h)
            elseif item.kind == EFFECT_POP_CLIP then
                runtime_pop_clip(rt)
            end
            i = i + 1
        end
        if state.clip_enabled ~= 0 then runtime_pop_clip(rt) end
    end
    effect_runner:compile()
    return effect_runner
end

local function get_scene_runner()
    if scene_runner then return scene_runner end

    local render_box = get_box_runner()
    local render_shadow = get_shadow_runner()
    local render_image = get_image_runner()
    local render_glyph = get_textured_runner(GlyphBatchState)
    local render_text = get_textured_runner(TextBatchState)
    local render_effect = get_effect_runner()

    scene_runner = terra(rt : &Runtime, state : &SceneState)
        rt.opacity = 1.0
        rt.opacity_top = 0
        rt.clip_enabled = 0
        rt.clip_top = 0

        C.glViewport(0, 0, rt.width, rt.height)
        C.glMatrixMode(C.GL_PROJECTION)
        C.glLoadIdentity()
        C.glOrtho(0.0, [double](rt.width), [double](rt.height), 0.0, -1.0, 1.0)
        C.glMatrixMode(C.GL_MODELVIEW)
        C.glLoadIdentity()
        C.glDisable(C.GL_DEPTH_TEST)
        C.glDisable(C.GL_SCISSOR_TEST)
        C.glClearColor(0.12, 0.12, 0.12, 1.0)
        C.glClear(C.GL_COLOR_BUFFER_BIT)

        var i : int32 = 0
        while i < state.command_count do
            var cmd = state.commands[i]
            if cmd.kind == [int32](CMD_BOX) then
                render_box(rt, &(state.boxes[cmd.index]))
            elseif cmd.kind == [int32](CMD_SHADOW) then
                render_shadow(rt, &(state.shadows[cmd.index]))
            elseif cmd.kind == [int32](CMD_IMAGE) then
                render_image(rt, &(state.images[cmd.index]))
            elseif cmd.kind == [int32](CMD_GLYPH) then
                render_glyph(rt, &(state.glyphs[cmd.index]))
            elseif cmd.kind == [int32](CMD_TEXT) then
                render_text(rt, &(state.texts[cmd.index]))
            elseif cmd.kind == [int32](CMD_EFFECT) then
                render_effect(rt, &(state.effects[cmd.index]))
            end
            i = i + 1
        end
    end
    scene_runner:compile()
    return scene_runner
end

UiBackend.compile_box_batch = U.terminal(function(batch)
    local clip = supported_clip_rect(batch.clip, "compile_box_batch(clip)")
    local items = compile_items(batch.items, compile_box_item)
    local rows = F.iter(items):map(function(item)
        return {
            item.rect.x, item.rect.y, item.rect.w, item.rect.h,
            item.fill.r, item.fill.g, item.fill.b, item.fill.a,
            item.stroke and 1 or 0,
            item.stroke and item.stroke.r or 0, item.stroke and item.stroke.g or 0, item.stroke and item.stroke.b or 0, item.stroke and item.stroke.a or 0,
            item.stroke_width,
        }
    end):totable()
    local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_fields(clip)
    local runner = get_box_runner()
    local keep = {}

    return stateful_unit(runner, BoxBatchState, function(state)
        local arr, ptr = create_state_array(BoxItemState, rows)
        keep.items = arr
        state.count = #items
        state.clip_enabled = clip_enabled
        state.clip_x, state.clip_y, state.clip_w, state.clip_h = clip_x, clip_y, clip_w, clip_h
        state.items = ptr
    end, function(state)
        state.items = nil
        keep.items = nil
    end)
end)

UiBackend.compile_glyph_batch = U.terminal(function(batch, assets)
    local atlas = require_known_atlas(batch)
    local font_path = Assets.font_path(assets, batch.font)
    local clip = supported_clip_rect(batch.clip, "compile_glyph_batch(clip)")
    local items = compile_items(batch.items, function(index, item)
        return compile_glyph_item(font_path, atlas.size_px, index, item)
    end)
    local visible_items = F.iter(items):filter(function(item) return item.glyph.w > 0 and item.glyph.h > 0 end):totable()
    local rows = F.iter(visible_items):map(function(item)
        return { item.texture.id, item.origin.x, item.origin.y, item.origin.x + item.glyph.w, item.origin.y + item.glyph.h, item.color.r, item.color.g, item.color.b, item.color.a }
    end):totable()
    local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_fields(clip)
    local runner = get_textured_runner(GlyphBatchState)
    local keep = {}

    return stateful_unit(runner, GlyphBatchState, function(state)
        local arr, ptr = create_state_array(TexturedItemState, rows)
        keep.items = arr
        state.count = #visible_items
        state.clip_enabled = clip_enabled
        state.clip_x, state.clip_y, state.clip_w, state.clip_h = clip_x, clip_y, clip_w, clip_h
        state.items = ptr
    end, function(state)
        state.items = nil
        keep.items = nil
    end)
end)

UiBackend.compile_text_batch = U.terminal(function(batch, assets)
    local clip = supported_clip_rect(batch.clip, "compile_text_batch(clip)")
    local font_path = Assets.font_path(assets, batch.font)
    local items = compile_items(batch.items, function(index, item)
        return compile_text_item(font_path, batch.size_px, index, item)
    end)
    local visible_items = F.iter(items):filter(function(item) return item.text.w > 0 and item.text.h > 0 end):totable()
    local rows = F.iter(visible_items):map(function(item)
        return { item.texture.id, item.origin.x, item.origin.y, item.origin.x + item.text.w, item.origin.y + item.text.h, 1.0, 1.0, 1.0, 1.0 }
    end):totable()
    local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_fields(clip)
    local runner = get_textured_runner(TextBatchState)
    local keep = {}

    return stateful_unit(runner, TextBatchState, function(state)
        local arr, ptr = create_state_array(TexturedItemState, rows)
        keep.items = arr
        state.count = #visible_items
        state.clip_enabled = clip_enabled
        state.clip_x, state.clip_y, state.clip_w, state.clip_h = clip_x, clip_y, clip_w, clip_h
        state.items = ptr
    end, function(state)
        state.items = nil
        keep.items = nil
    end)
end)

UiBackend.compile_effect_batch = U.terminal(function(batch)
    local clip = supported_clip_rect(batch.clip, "compile_effect_batch(clip)")
    validate_effect_items(batch.items)
    local rows = F.iter(batch.items):map(function(item)
        return U.match(item, {
            PushOpacity = function(v) return { EFFECT_PUSH_OPACITY, v.value, 0,0,0,0,0,0,0, 0,0,0,0 } end,
            PopOpacity = function() return { EFFECT_POP_OPACITY, 0, 0,0,0,0,0,0,0, 0,0,0,0 } end,
            PushTransform = function(v) return { EFFECT_PUSH_TRANSFORM, 0, v.xform.m11, v.xform.m12, v.xform.m21, v.xform.m22, v.xform.tx, v.xform.ty, 0, 0,0,0,0 } end,
            PopTransform = function() return { EFFECT_POP_TRANSFORM, 0, 0,0,0,0,0,0,0, 0,0,0,0 } end,
            PushBlend = function(v) return { EFFECT_PUSH_BLEND, 0, 0,0,0,0,0,0, blend_mode_id(v.mode), 0,0,0,0 } end,
            PopBlend = function() return { EFFECT_POP_BLEND, 0, 0,0,0,0,0,0,0, 0,0,0,0 } end,
            PushClip = function(v) local r = supported_clip_rect(v.shape, "compile_effect_batch(PushClip)"); return { EFFECT_PUSH_CLIP, 0, 0,0,0,0,0,0,0, r.x,r.y,r.w,r.h } end,
            PopClip = function() return { EFFECT_POP_CLIP, 0, 0,0,0,0,0,0,0, 0,0,0,0 } end,
        })
    end):totable()
    local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_fields(clip)
    local runner = get_effect_runner()
    local keep = {}

    return stateful_unit(runner, EffectBatchState, function(state)
        local arr, ptr = create_state_array(EffectItemState, rows)
        keep.items = arr
        state.count = #rows
        state.clip_enabled = clip_enabled
        state.clip_x, state.clip_y, state.clip_w, state.clip_h = clip_x, clip_y, clip_w, clip_h
        state.items = ptr
    end, function(state)
        state.items = nil
        keep.items = nil
    end)
end)

UiBackend.compile_shadow_batch = U.terminal(function(batch)
    local clip = supported_clip_rect(batch.clip, "compile_shadow_batch(clip)")
    local items = compile_items(batch.items, compile_shadow_item)
    local rows = F.iter(items):map(function(item)
        return { item.rect.x, item.rect.y, item.rect.w, item.rect.h, item.color.r, item.color.g, item.color.b, item.color.a, item.blur, item.spread, item.dx, item.dy, item.kind.kind == "DropShadow" and SHADOW_DROP or SHADOW_INNER }
    end):totable()
    local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_fields(clip)
    local runner = get_shadow_runner()
    local keep = {}

    return stateful_unit(runner, ShadowBatchState, function(state)
        local arr, ptr = create_state_array(ShadowItemState, rows)
        keep.items = arr
        state.count = #rows
        state.clip_enabled = clip_enabled
        state.clip_x, state.clip_y, state.clip_w, state.clip_h = clip_x, clip_y, clip_w, clip_h
        state.items = ptr
    end, function(state)
        state.items = nil
        keep.items = nil
    end)
end)

UiBackend.compile_image_batch = U.terminal(function(batch, assets)
    Assets.image_path(assets, batch.image)
    local clip = supported_clip_rect(batch.clip, "compile_image_batch(clip)")
    local items = compile_items(batch.items, compile_image_item)
    local rows = F.iter(items):map(function(item)
        return { item.rect.x, item.rect.y, item.rect.w, item.rect.h, item.style.opacity or 1.0, batch.sampling.kind == "Nearest" and 1 or 0 }
    end):totable()
    local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_fields(clip)
    local runner = get_image_runner()
    local keep = {}

    return stateful_unit(runner, ImageBatchState, function(state)
        local arr, ptr = create_state_array(ImageItemState, rows)
        keep.items = arr
        state.count = #rows
        state.clip_enabled = clip_enabled
        state.clip_x, state.clip_y, state.clip_w, state.clip_h = clip_x, clip_y, clip_w, clip_h
        state.items = ptr
    end, function(state)
        state.items = nil
        keep.items = nil
    end)
end)

UiBackend.compile_batch = U.terminal(function(batch, assets)
    return U.match(batch, {
        BoxBatch = function(v) return UiBackend.compile_box_batch(v) end,
        ShadowBatch = function(v) return UiBackend.compile_shadow_batch(v) end,
        ImageBatch = function(v) return UiBackend.compile_image_batch(v, assets) end,
        GlyphBatch = function(v) return UiBackend.compile_glyph_batch(v, assets) end,
        TextBatch = function(v) return UiBackend.compile_text_batch(v, assets) end,
        EffectBatch = function(v) return UiBackend.compile_effect_batch(v) end,
        CustomBatch = function(_)
            error("compile_batch: CustomBatch is not implemented yet", 2)
        end,
    })
end)

UiBackend.compile_scene = U.terminal(function(scene, assets)
    local batch_profile = {}
    local command_rows = {}
    local packed = {
        boxes = {},
        shadows = {},
        images = {},
        glyphs = {},
        texts = {},
        effects = {},
    }

    local function note_batch(kind, payload, elapsed_ns)
        if not PROFILE then return end
        local slot = batch_profile[kind] or { count = 0, total_ns = 0, max_ns = 0, items = 0 }
        slot.count = slot.count + 1
        slot.total_ns = slot.total_ns + elapsed_ns
        slot.max_ns = math.max(slot.max_ns, elapsed_ns)
        slot.items = slot.items + payload.count
        batch_profile[kind] = slot
    end

    F.iter(scene.batches):each(function(batch)
        local t0 = PROFILE and now_ns() or nil
        U.match(batch, {
            BoxBatch = function(v)
                local payload = pack_box_batch(v)
                command_rows[#command_rows + 1] = { CMD_BOX, #packed.boxes }
                packed.boxes[#packed.boxes + 1] = payload
                note_batch("BoxBatch", payload, (PROFILE and (now_ns() - t0)) or 0)
            end,
            ShadowBatch = function(v)
                local payload = pack_shadow_batch(v)
                command_rows[#command_rows + 1] = { CMD_SHADOW, #packed.shadows }
                packed.shadows[#packed.shadows + 1] = payload
                note_batch("ShadowBatch", payload, (PROFILE and (now_ns() - t0)) or 0)
            end,
            ImageBatch = function(v)
                local payload = pack_image_batch(v, assets)
                command_rows[#command_rows + 1] = { CMD_IMAGE, #packed.images }
                packed.images[#packed.images + 1] = payload
                note_batch("ImageBatch", payload, (PROFILE and (now_ns() - t0)) or 0)
            end,
            GlyphBatch = function(v)
                local payload = pack_glyph_batch(v, assets)
                command_rows[#command_rows + 1] = { CMD_GLYPH, #packed.glyphs }
                packed.glyphs[#packed.glyphs + 1] = payload
                note_batch("GlyphBatch", payload, (PROFILE and (now_ns() - t0)) or 0)
            end,
            TextBatch = function(v)
                local payload = pack_text_batch(v, assets)
                command_rows[#command_rows + 1] = { CMD_TEXT, #packed.texts }
                packed.texts[#packed.texts + 1] = payload
                note_batch("TextBatch", payload, (PROFILE and (now_ns() - t0)) or 0)
            end,
            EffectBatch = function(v)
                local payload = pack_effect_batch(v)
                command_rows[#command_rows + 1] = { CMD_EFFECT, #packed.effects }
                packed.effects[#packed.effects + 1] = payload
                note_batch("EffectBatch", payload, (PROFILE and (now_ns() - t0)) or 0)
            end,
            CustomBatch = function(_)
                error("compile_scene: CustomBatch is not implemented yet", 2)
            end,
        })
    end)

    if PROFILE then
        local parts = {}
        for _, key in ipairs({ "BoxBatch", "ShadowBatch", "ImageBatch", "GlyphBatch", "TextBatch", "EffectBatch" }) do
            local slot = batch_profile[key]
            if slot then
                parts[#parts + 1] = ("%s=%d batches/%d items %.2fms pack avg %.2fms max %.2fms")
                    :format(key, slot.count, slot.items, ms(slot.total_ns), ms(slot.total_ns / slot.count), ms(slot.max_ns))
            end
        end
        if #parts > 0 then
            print("compile_scene: " .. table.concat(parts, " | "))
        end
    end

    local runner = get_scene_runner()
    local keep = {}

    local function init_batch_array(batch_t, item_t, batches)
        local item_arrays = {}
        local batch_rows = F.iter(batches):map(function(batch)
            local item_arr, item_ptr = create_state_array(item_t, batch.item_rows)
            item_arrays[#item_arrays + 1] = item_arr
            return {
                batch.count,
                batch.clip_enabled,
                batch.clip_x,
                batch.clip_y,
                batch.clip_w,
                batch.clip_h,
                item_ptr,
            }
        end):totable()
        local batch_arr, batch_ptr = create_state_array(batch_t, batch_rows)
        return batch_arr, batch_ptr, item_arrays
    end

    return stateful_unit(runner, SceneState, function(state)
        local commands_arr, commands_ptr = create_state_array(RenderCommandState, command_rows)
        local box_arr, box_ptr, box_item_arrays = init_batch_array(BoxBatchState, BoxItemState, packed.boxes)
        local shadow_arr, shadow_ptr, shadow_item_arrays = init_batch_array(ShadowBatchState, ShadowItemState, packed.shadows)
        local image_arr, image_ptr, image_item_arrays = init_batch_array(ImageBatchState, ImageItemState, packed.images)
        local glyph_arr, glyph_ptr, glyph_item_arrays = init_batch_array(GlyphBatchState, TexturedItemState, packed.glyphs)
        local text_arr, text_ptr, text_item_arrays = init_batch_array(TextBatchState, TexturedItemState, packed.texts)
        local effect_arr, effect_ptr, effect_item_arrays = init_batch_array(EffectBatchState, EffectItemState, packed.effects)

        keep.commands = commands_arr
        keep.boxes, keep.box_items = box_arr, box_item_arrays
        keep.shadows, keep.shadow_items = shadow_arr, shadow_item_arrays
        keep.images, keep.image_items = image_arr, image_item_arrays
        keep.glyphs, keep.glyph_items = glyph_arr, glyph_item_arrays
        keep.texts, keep.text_items = text_arr, text_item_arrays
        keep.effects, keep.effect_items = effect_arr, effect_item_arrays

        state.command_count = #command_rows
        state.commands = commands_ptr
        state.box_count, state.boxes = #packed.boxes, box_ptr
        state.shadow_count, state.shadows = #packed.shadows, shadow_ptr
        state.image_count, state.images = #packed.images, image_ptr
        state.glyph_count, state.glyphs = #packed.glyphs, glyph_ptr
        state.text_count, state.texts = #packed.texts, text_ptr
        state.effect_count, state.effects = #packed.effects, effect_ptr
    end, function(state)
        state.commands = nil
        state.boxes = nil
        state.shadows = nil
        state.images = nil
        state.glyphs = nil
        state.texts = nil
        state.effects = nil

        keep.commands = nil
        keep.boxes, keep.box_items = nil, nil
        keep.shadows, keep.shadow_items = nil, nil
        keep.images, keep.image_items = nil, nil
        keep.glyphs, keep.glyph_items = nil, nil
        keep.texts, keep.text_items = nil, nil
        keep.effects, keep.effect_items = nil, nil
    end)
end)

function UiBackend.decode_sdl_event(runtime, raw_event)
    error("TODO: SDL_Event -> UiInput.Event", 2)
end

function UiBackend.route_input(ui_session, ui_routed, ui_input)
    return ui_session:apply(ui_routed, ui_input)
end

function UiBackend.install(T)
    T.UiBatched.BoxBatch.compile = UiBackend.compile_box_batch
    T.UiBatched.ShadowBatch.compile = UiBackend.compile_shadow_batch
    T.UiBatched.ImageBatch.compile = UiBackend.compile_image_batch
    T.UiBatched.GlyphBatch.compile = UiBackend.compile_glyph_batch
    T.UiBatched.TextBatch.compile = UiBackend.compile_text_batch
    T.UiBatched.EffectBatch.compile = UiBackend.compile_effect_batch
    T.UiBatched.CustomBatch.compile = UiBackend.compile_batch
    T.UiBatched.Scene.compile = UiBackend.compile_scene
end

UiBackend.Runtime = Runtime
UiBackend.C = C

return UiBackend
