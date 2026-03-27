-- ============================================================================
-- Canonical UI backend scaffold
-- ----------------------------------------------------------------------------
-- Pure phases above:
--   UiDecl -> UiLaid -> { UiBatched, UiRouted }
--
-- Backend leaves below:
--   UiBatched.Batch -> Unit
--   SDL_Event -> UiInput.Event
--
-- Compiler-side boundary code stays pure and structural.
-- Imperative work belongs in emitted Terra code / Unit state.
-- ============================================================================

local U = require("unit")
local F = require("fun")
local SdlGl = require("examples.ui.backend_sdl_gl")
local Text = require("examples.ui.backend_text_sdl_ttf")

local UiBackend = {}
local C = SdlGl.headers()
local Runtime = SdlGl.runtime_t()

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
    return batch
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

local function compile_glyph_item(font, atlas, index, item)
    return {
        origin = item.origin,
        color = item.color,
        glyph = Text.rasterize_glyph(font, atlas, item.glyph_id),
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
    local pixels = terralib.constant(terralib.new(uint8[#glyph.pixels], glyph.pixels))
    local x1 = item.origin.x
    local y1 = item.origin.y
    local x2 = x1 + glyph.w
    local y2 = y1 + glyph.h

    return quote
        var tex : C.GLuint[1]
        tex[0] = 0
        var pixels_local = [pixels]
        C.glGenTextures(1, &tex[0])
        C.glBindTexture(C.GL_TEXTURE_2D, tex[0])
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, C.GL_LINEAR)
        C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAG_FILTER, C.GL_LINEAR)
        C.glPixelStorei(C.GL_UNPACK_ALIGNMENT, 1)
        C.glTexImage2D(C.GL_TEXTURE_2D, 0, C.GL_RGBA, glyph.w, glyph.h, 0, C.GL_RGBA, C.GL_UNSIGNED_BYTE, &pixels_local[0])
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
        C.glDeleteTextures(1, &tex[0])
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

UiBackend.compile_box_batch = U.terminal(function(batch)
    local clip = supported_clip_rect(batch.clip, "compile_box_batch(clip)")
    local items = compile_items(batch.items, compile_box_item)
    local params = terralib.newlist{ symbol(&Runtime, "rt") }

    return U.leaf(nil, params, function(_, p)
        local rt = p[1]
        local draw_ops = F.iter(items):map(function(item)
            return emit_box_item(rt, item)
        end):totable()
        local push_clip = clip and emit_push_clip(rt, clip) or nil
        local pop_clip = clip and emit_pop_clip(rt) or nil

        return quote
            C.glEnable(C.GL_BLEND)
            C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
            C.glDisable(C.GL_TEXTURE_2D)
            escape if push_clip then emit(push_clip) end end
            escape
                for _, draw in ipairs(draw_ops) do
                    emit(draw)
                end
            end
            escape if pop_clip then emit(pop_clip) end end
        end
    end)
end)

UiBackend.compile_glyph_batch = U.terminal(function(batch)
    require_known_atlas(batch)

    local clip = supported_clip_rect(batch.clip, "compile_glyph_batch(clip)")
    local items = compile_items(batch.items, function(index, item)
        return compile_glyph_item(batch.font, batch.atlas, index, item)
    end)
    local visible_items = F.iter(items)
        :filter(function(item) return item.glyph.w > 0 and item.glyph.h > 0 end)
        :totable()
    local params = terralib.newlist{ symbol(&Runtime, "rt") }

    return U.leaf(nil, params, function(_, p)
        local rt = p[1]
        local draw_ops = F.iter(visible_items):map(function(item)
            return emit_glyph_item(rt, item)
        end):totable()
        local push_clip = clip and emit_push_clip(rt, clip) or nil
        local pop_clip = clip and emit_pop_clip(rt) or nil

        return quote
            C.glEnable(C.GL_BLEND)
            C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
            C.glEnable(C.GL_TEXTURE_2D)
            escape if push_clip then emit(push_clip) end end
            escape
                for _, draw in ipairs(draw_ops) do
                    emit(draw)
                end
            end
            escape if pop_clip then emit(pop_clip) end end
            C.glDisable(C.GL_TEXTURE_2D)
        end
    end)
end)

UiBackend.compile_effect_batch = U.terminal(function(batch)
    local clip = supported_clip_rect(batch.clip, "compile_effect_batch(clip)")
    validate_effect_items(batch.items)

    local params = terralib.newlist{ symbol(&Runtime, "rt") }

    return U.leaf(nil, params, function(_, p)
        local rt = p[1]
        local draw_ops = F.iter(batch.items):map(function(item)
            return emit_effect_item(rt, item)
        end):totable()
        local push_clip = clip and emit_push_clip(rt, clip) or nil
        local pop_clip = clip and emit_pop_clip(rt) or nil

        return quote
            escape if push_clip then emit(push_clip) end end
            escape
                for _, draw in ipairs(draw_ops) do
                    emit(draw)
                end
            end
            escape if pop_clip then emit(pop_clip) end end
        end
    end)
end)

UiBackend.compile_shadow_batch = U.terminal(function(batch)
    local clip = supported_clip_rect(batch.clip, "compile_shadow_batch(clip)")
    local items = compile_items(batch.items, compile_shadow_item)
    local params = terralib.newlist{ symbol(&Runtime, "rt") }

    return U.leaf(nil, params, function(_, p)
        local rt = p[1]
        local draw_ops = F.iter(items):map(function(item)
            return emit_shadow_item(rt, item)
        end):totable()
        local push_clip = clip and emit_push_clip(rt, clip) or nil
        local pop_clip = clip and emit_pop_clip(rt) or nil

        return quote
            C.glEnable(C.GL_BLEND)
            C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
            C.glDisable(C.GL_TEXTURE_2D)
            escape if push_clip then emit(push_clip) end end
            escape
                for _, draw in ipairs(draw_ops) do
                    emit(draw)
                end
            end
            escape if pop_clip then emit(pop_clip) end end
        end
    end)
end)

UiBackend.compile_image_batch = U.terminal(function(batch)
    error("TODO: UiBatched.ImageBatch -> Unit", 2)
end)

UiBackend.compile_batch = U.terminal(function(batch)
    return U.match(batch, {
        BoxBatch = UiBackend.compile_box_batch,
        ShadowBatch = UiBackend.compile_shadow_batch,
        ImageBatch = UiBackend.compile_image_batch,
        GlyphBatch = UiBackend.compile_glyph_batch,
        EffectBatch = UiBackend.compile_effect_batch,
        CustomBatch = function(_)
            error("compile_batch: CustomBatch is not implemented yet", 2)
        end,
    })
end)

UiBackend.compile_scene = U.terminal(function(scene)
    local units = F.iter(scene.batches):map(UiBackend.compile_batch):totable()
    local params = terralib.newlist{ symbol(&Runtime, "rt") }

    return U.compose(units, params, function(_, kids, p)
        local rt = p[1]
        local child_calls = F.iter(kids):map(function(kid)
            return kid.call(rt)
        end):totable()

        return quote
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

            escape
                for _, call in ipairs(child_calls) do
                    emit(call)
                end
            end
        end
    end)
end)

function UiBackend.decode_sdl_event(runtime, raw_event)
    error("TODO: SDL_Event -> UiInput.Event", 2)
end

function UiBackend.route_input(ui_session, ui_routed, ui_input)
    error("TODO: UiSession + UiRouted + UiInput -> UiSession + UiIntent", 2)
end

UiBackend.Runtime = Runtime
UiBackend.C = C

return UiBackend
