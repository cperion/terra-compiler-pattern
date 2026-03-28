local U = require("unit")
local F = require("fun")
local Assets = require("examples.ui.ui_asset_resolve")
local SdlGl = require("examples.ui.backend_sdl_gl")
local Text = require("examples.ui.backend_text_sdl_ttf")

local int32 = terralib.types.int32
local uint32 = terralib.types.uint32
local double = terralib.types.double

local function L(xs)
    return terralib.newlist(xs or {})
end

local function ptr_t(t)
    return &t
end

-- ============================================================================
-- UiKernel.Spec:compile / UiKernel.Payload:materialize
-- ----------------------------------------------------------------------------
-- This file implements the final two ui2 boundaries.
--
-- Boundary meanings:
--   UiKernel.Spec:compile(target) -> Unit
--   UiKernel.Payload:materialize(target, assets, state) -> keep
--
-- Why compile/materialize are split:
--   compile answers:
--     "what stable machine code + ABI do we install?"
--
--   materialize answers:
--     "what live payload do we load into that ABI right now?"
--
-- What compile consumes:
--   - UiKernel.Spec
--   - explicit render target contract
--
-- What compile produces:
--   - one Unit with a stable scene runner and one state_t layout
--   - generic init/release hooks for emptying scene state
--
-- What materialize consumes:
--   - UiKernel.Payload
--   - explicit target
--   - explicit asset catalog
--   - one allocated state_t instance
--
-- What materialize produces:
--   - populated state pointers/counts for the stable runner
--   - a Lua keep table retaining backing arrays for Terra pointers
--
-- Current backend scope:
--   - built-in rendering targets the existing SDL/OpenGL backend contract
--   - clips / opacity / transforms / supported blend modes are applied per batch
--   - boxes and shadows render directly
--   - text materialization uses one SDL_ttf-rendered texture per text item
--     and draws one textured quad per item
--   - images currently use the same placeholder path as the older ui example:
--     explicit image refs are validated but rendering is still a neutral box
--   - custom families are fully implemented via explicit target-provided Terra
--     handlers, one per custom kind baked into UiKernel.Spec
--
-- Target contract:
--   target may be either:
--     - the backend module itself (for built-ins only), or
--     - { backend = backend_module, custom = { [kind] = terra(rt, payload) } }
--
--   where backend_module must provide the existing SDL/GL contract used by
--   examples.ui.backend_sdl_gl:
--     backend.runtime_t()
--     backend.headers()
--
--   and each custom handler must be a Terra function of shape:
--     terra(rt : &backend.runtime_t(), payload : double)
--
-- Functional-style note:
--   The pure boundary work above stayed in LuaFun style. This file is the
--   terminal/backend layer, so some low-level row packing and Terra runner
--   construction is necessarily more imperative. The ASDL -> Unit boundary is
--   still explicit and structurally staged.
-- ============================================================================

local function append_all(dst, src)
    F.iter(src):each(function(v)
        dst[#dst + 1] = v
    end)
    return dst
end

local function create_state_array(item_t, rows)
    local n = math.max(1, #rows)
    local arr = terralib.new(item_t[n], rows)
    return arr, terralib.cast(&item_t, arr)
end

local function stateful_unit(fn, state_t, init, release)
    local unit = U.new(fn, state_t)
    unit.init = init
    unit.release = release
    return unit
end

local function clear_scene_state(state)
    state.batch_count = 0
    state.batches = nil
    state.box_count = 0
    state.boxes = nil
    state.shadow_count = 0
    state.shadows = nil
    state.text_run_count = 0
    state.text_runs = nil
    state.image_count = 0
    state.images = nil
    state.custom_count = 0
    state.customs = nil
end

local function normalize_target(target)
    if not target then
        error("UiKernel.Spec:compile: target is required", 3)
    end

    if type(target.runtime_t) == "function" and type(target.headers) == "function" then
        return {
            backend = target,
            custom = {},
        }
    end

    if type(target) ~= "table" or type(target.backend) ~= "table" then
        error("UiKernel.Spec:compile: target must be a backend module or { backend = ..., custom = ... }", 3)
    end

    if type(target.backend.runtime_t) ~= "function" or type(target.backend.headers) ~= "function" then
        error("UiKernel.Spec:compile: target.backend must provide runtime_t() and headers()", 3)
    end

    return {
        backend = target.backend,
        custom = target.custom or {},
    }
end

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

local function supported_clip_rect(clip, context)
    if not clip then return nil end
    return U.match(clip, {
        ClipRect = function(v)
            return v.rect
        end,
        ClipRoundedRect = function(_)
            error(("%s: ClipRoundedRect is not implemented yet"):format(context), 3)
        end,
    })
end

local function blend_mode_id(mode)
    return U.match(mode, {
        BlendNormal = function() return 1 end,
        BlendAdd = function() return 2 end,
        BlendMultiply = function() return 3 end,
        BlendScreen = function() return 4 end,
        BlendOverlay = function()
            error("UiKernel.Payload:materialize: BlendOverlay is not implemented yet", 3)
        end,
    })
end

local function clip_row(payload, draw_state)
    local clip = draw_state.clip_index and payload.clips[draw_state.clip_index] or nil
    local rect = supported_clip_rect(clip, "UiKernel.Payload:materialize(batch clip)")
    if not rect then return 0, 0, 0, 0, 0 end
    return 1, rect.x, rect.y, rect.w, rect.h
end

local function transform_row(draw_state)
    local xform = draw_state.transform
    if not xform then return 0, 0,0,0,0,0,0 end
    return 1, xform.m11, xform.m12, xform.m21, xform.m22, xform.tx, xform.ty
end

local BoxItemState = terralib.types.newstruct("Ui2KernelBoxItemState")
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

local ShadowItemState = terralib.types.newstruct("Ui2KernelShadowItemState")
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

local TextRunState = terralib.types.newstruct("Ui2KernelTextRunState")
TextRunState.entries:insert({ field = "tex_id", type = uint32 })
TextRunState.entries:insert({ field = "x1", type = double })
TextRunState.entries:insert({ field = "y1", type = double })
TextRunState.entries:insert({ field = "x2", type = double })
TextRunState.entries:insert({ field = "y2", type = double })

local ImageItemState = terralib.types.newstruct("Ui2KernelImageItemState")
ImageItemState.entries:insert({ field = "x", type = double })
ImageItemState.entries:insert({ field = "y", type = double })
ImageItemState.entries:insert({ field = "w", type = double })
ImageItemState.entries:insert({ field = "h", type = double })
ImageItemState.entries:insert({ field = "opacity", type = double })
ImageItemState.entries:insert({ field = "sampling", type = int32 })

local CustomItemState = terralib.types.newstruct("Ui2KernelCustomItemState")
CustomItemState.entries:insert({ field = "payload", type = double })

local BatchState = terralib.types.newstruct("Ui2KernelBatchState")
BatchState.entries:insert({ field = "kind", type = int32 })
BatchState.entries:insert({ field = "custom_kind", type = int32 })
BatchState.entries:insert({ field = "item_start", type = int32 })
BatchState.entries:insert({ field = "item_count", type = int32 })
BatchState.entries:insert({ field = "clip_enabled", type = int32 })
BatchState.entries:insert({ field = "clip_x", type = double })
BatchState.entries:insert({ field = "clip_y", type = double })
BatchState.entries:insert({ field = "clip_w", type = double })
BatchState.entries:insert({ field = "clip_h", type = double })
BatchState.entries:insert({ field = "opacity", type = double })
BatchState.entries:insert({ field = "blend_mode", type = int32 })
BatchState.entries:insert({ field = "has_transform", type = int32 })
BatchState.entries:insert({ field = "m11", type = double })
BatchState.entries:insert({ field = "m12", type = double })
BatchState.entries:insert({ field = "m21", type = double })
BatchState.entries:insert({ field = "m22", type = double })
BatchState.entries:insert({ field = "tx", type = double })
BatchState.entries:insert({ field = "ty", type = double })

local SceneState = terralib.types.newstruct("Ui2KernelSceneState")
SceneState.entries:insert({ field = "batch_count", type = int32 })
SceneState.entries:insert({ field = "batches", type = ptr_t(BatchState) })
SceneState.entries:insert({ field = "box_count", type = int32 })
SceneState.entries:insert({ field = "boxes", type = ptr_t(BoxItemState) })
SceneState.entries:insert({ field = "shadow_count", type = int32 })
SceneState.entries:insert({ field = "shadows", type = ptr_t(ShadowItemState) })
SceneState.entries:insert({ field = "text_run_count", type = int32 })
SceneState.entries:insert({ field = "text_runs", type = ptr_t(TextRunState) })
SceneState.entries:insert({ field = "image_count", type = int32 })
SceneState.entries:insert({ field = "images", type = ptr_t(ImageItemState) })
SceneState.entries:insert({ field = "custom_count", type = int32 })
SceneState.entries:insert({ field = "customs", type = ptr_t(CustomItemState) })

local CMD_BOX = 1
local CMD_SHADOW = 2
local CMD_TEXT = 3
local CMD_IMAGE = 4
local CMD_CUSTOM = 5

local SHADOW_DROP = 1
local SHADOW_INNER = 2

local function custom_handlers_for(target, spec)
    local target_custom = target.custom or {}

    return F.iter(spec.custom_families):map(function(family)
        local fn = target_custom[family.family]
        if fn == nil then
            error(("UiKernel.Spec:compile: missing target custom handler for family %s")
                :format(tostring(family.family)), 3)
        end
        return {
            family = family.family,
            fn = fn,
        }
    end):totable()
end

local function build_scene_runner(target, spec)
    local backend = target.backend
    local custom_handlers = custom_handlers_for(target, spec)
    local Runtime = backend.runtime_t()
    local C = backend.headers()

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

    local begin_batch = terra(rt : &Runtime, batch : &BatchState)
        rt.opacity_stack[rt.opacity_top] = rt.opacity
        rt.opacity_top = rt.opacity_top + 1
        rt.opacity = rt.opacity * batch.opacity

        C.glPushAttrib(C.GL_COLOR_BUFFER_BIT)
        C.glEnable(C.GL_BLEND)
        if batch.blend_mode == 1 then
            C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
        elseif batch.blend_mode == 2 then
            C.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE)
        elseif batch.blend_mode == 3 then
            C.glBlendFunc(C.GL_DST_COLOR, C.GL_ONE_MINUS_SRC_ALPHA)
        else
            C.glBlendFunc(C.GL_ONE, C.GL_ONE_MINUS_SRC_COLOR)
        end

        if batch.has_transform ~= 0 then
            var mx : double[16]
            mx[0], mx[1], mx[2], mx[3] = batch.m11, batch.m12, 0.0, 0.0
            mx[4], mx[5], mx[6], mx[7] = batch.m21, batch.m22, 0.0, 0.0
            mx[8], mx[9], mx[10], mx[11] = 0.0, 0.0, 1.0, 0.0
            mx[12], mx[13], mx[14], mx[15] = batch.tx, batch.ty, 0.0, 1.0
            C.glMatrixMode(C.GL_MODELVIEW)
            C.glPushMatrix()
            C.glMultMatrixd(&mx[0])
        end

        if batch.clip_enabled ~= 0 then
            runtime_push_clip(rt, batch.clip_x, batch.clip_y, batch.clip_w, batch.clip_h)
        end
    end
    begin_batch:compile()

    local end_batch = terra(rt : &Runtime, batch : &BatchState)
        if batch.clip_enabled ~= 0 then
            runtime_pop_clip(rt)
        end
        if batch.has_transform ~= 0 then
            C.glMatrixMode(C.GL_MODELVIEW)
            C.glPopMatrix()
        end
        C.glPopAttrib()
        rt.opacity_top = rt.opacity_top - 1
        rt.opacity = rt.opacity_stack[rt.opacity_top]
    end
    end_batch:compile()

    local render_boxes = terra(rt : &Runtime, state : &SceneState, batch : &BatchState)
        C.glDisable(C.GL_TEXTURE_2D)
        var i : int32 = 0
        while i < batch.item_count do
            var item = state.boxes[batch.item_start + i]
            draw_solid_quad_rt(rt, item.x, item.y, item.w, item.h, item.fill_r, item.fill_g, item.fill_b, item.fill_a)
            if item.stroke_enabled ~= 0 and item.stroke_width > 0 then
                draw_stroke_loop_rt(rt, item.x, item.y, item.w, item.h, item.stroke_r, item.stroke_g, item.stroke_b, item.stroke_a, item.stroke_width)
            end
            i = i + 1
        end
    end
    render_boxes:compile()

    local render_shadows = terra(rt : &Runtime, state : &SceneState, batch : &BatchState)
        C.glDisable(C.GL_TEXTURE_2D)
        var i : int32 = 0
        while i < batch.item_count do
            var item = state.shadows[batch.item_start + i]
            if item.kind == SHADOW_DROP then
                var passes : int32 = 1
                if item.blur > 0 then passes = [int32](item.blur + 0.999999) end
                if passes > 16 then passes = 16 end
                var j : int32 = 0
                while j < passes do
                    var expansion = 0.0
                    if item.blur > 0 then expansion = item.blur * (passes - j) / passes end
                    var alpha = item.a
                    if item.blur > 0 then alpha = item.a / passes end
                    draw_solid_quad_rt(rt, item.x + item.dx - item.spread - expansion, item.y + item.dy - item.spread - expansion, item.w + 2 * (item.spread + expansion), item.h + 2 * (item.spread + expansion), item.r, item.g, item.b, alpha)
                    j = j + 1
                end
            else
                runtime_push_clip(rt, item.x, item.y, item.w, item.h)
                var passes : int32 = 1
                if item.blur > 0 then passes = [int32](item.blur + 0.999999) end
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
                    if item.blur > 0 then alpha = item.a / passes end
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
    end
    render_shadows:compile()

    local render_text = terra(rt : &Runtime, state : &SceneState, batch : &BatchState)
        C.glEnable(C.GL_TEXTURE_2D)
        var i : int32 = 0
        while i < batch.item_count do
            var item = state.text_runs[batch.item_start + i]
            if item.tex_id ~= 0 then
                C.glBindTexture(C.GL_TEXTURE_2D, item.tex_id)
                C.glColor4d(1.0, 1.0, 1.0, rt.opacity)
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
            end
            i = i + 1
        end
        C.glDisable(C.GL_TEXTURE_2D)
    end
    render_text:compile()

    local render_images = terra(rt : &Runtime, state : &SceneState, batch : &BatchState)
        C.glDisable(C.GL_TEXTURE_2D)
        var i : int32 = 0
        while i < batch.item_count do
            var item = state.images[batch.item_start + i]
            var stroke_width = 1.0
            if item.sampling == 1 then stroke_width = 2.0 end
            draw_solid_quad_rt(rt, item.x, item.y, item.w, item.h, 0.45, 0.45, 0.48, item.opacity)
            draw_stroke_loop_rt(rt, item.x, item.y, item.w, item.h, 0.75, 0.75, 0.78, item.opacity, stroke_width)
            i = i + 1
        end
    end
    render_images:compile()

    local runner = terra(rt : &Runtime, state : &SceneState)
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
        while i < state.batch_count do
            var batch = &(state.batches[i])
            begin_batch(rt, batch)
            if batch.kind == CMD_BOX then
                render_boxes(rt, state, batch)
            elseif batch.kind == CMD_SHADOW then
                render_shadows(rt, state, batch)
            elseif batch.kind == CMD_TEXT then
                render_text(rt, state, batch)
            elseif batch.kind == CMD_IMAGE then
                render_images(rt, state, batch)
            elseif batch.kind == CMD_CUSTOM then
                escape
                    for _, info in ipairs(custom_handlers) do
                        emit quote
                            if batch.custom_kind == [int32](info.family) then
                                var j : int32 = 0
                                while j < batch.item_count do
                                    var item = state.customs[batch.item_start + j]
                                    [info.fn](rt, item.payload)
                                    j = j + 1
                                end
                            end
                        end
                    end
                end
            end
            end_batch(rt, batch)
            i = i + 1
        end
    end
    runner:compile()
    return runner
end

local function kernel_box_row(item)
    if not square_corners(item.corners) then
        error("UiKernel.Payload:materialize(box): rounded corners are not implemented yet", 3)
    end

    local fill = solid_color(item.fill, "UiKernel.Payload:materialize(box fill)")
    local stroke = item.stroke and solid_color(item.stroke, "UiKernel.Payload:materialize(box stroke)") or nil

    return {
        item.rect.x, item.rect.y, item.rect.w, item.rect.h,
        fill.r, fill.g, fill.b, fill.a,
        stroke and 1 or 0,
        stroke and stroke.r or 0,
        stroke and stroke.g or 0,
        stroke and stroke.b or 0,
        stroke and stroke.a or 0,
        item.stroke_width,
    }
end

local function kernel_shadow_row(item)
    if not square_corners(item.corners) then
        error("UiKernel.Payload:materialize(shadow): rounded corners are not implemented yet", 3)
    end

    local brush = solid_color(item.brush, "UiKernel.Payload:materialize(shadow brush)")
    return {
        item.rect.x, item.rect.y, item.rect.w, item.rect.h,
        brush.r, brush.g, brush.b, brush.a,
        math.max(0, item.blur),
        item.spread,
        item.dx,
        item.dy,
        item.shadow_kind.kind == "DropShadow" and SHADOW_DROP or SHADOW_INNER,
    }
end

local function kernel_image_row(item, assets)
    Assets.image_path(assets, item.image)
    if not square_corners(item.corners) then
        error("UiKernel.Payload:materialize(image): rounded corners are not implemented yet", 3)
    end

    return {
        item.rect.x,
        item.rect.y,
        item.rect.w,
        item.rect.h,
        1.0,
        item.sampling.kind == "Nearest" and 1 or 0,
    }
end

local function materialize_text_rows(payload, assets)
    return F.iter(payload.text_runs):map(function(run)
        local font_path = Assets.font_path(assets, run.font)
        local rendered = Text.rasterize_text(
            font_path,
            run.size_px,
            run.text.value,
            run.color,
            run.wrap.kind,
            run.align.kind,
            run.bounds.w
        )
        local texture = (rendered.w > 0 and rendered.h > 0)
            and SdlGl.ensure_rgba_texture(rendered.cache_key, rendered.w, rendered.h, rendered.pixels, "Linear")
            or nil

        local x = run.bounds.x
        if run.wrap.kind == "NoWrap" then
            if run.align.kind == "TextCenter" then
                x = x + math.max(0, (run.bounds.w - rendered.w) / 2)
            elseif run.align.kind == "TextEnd" then
                x = x + math.max(0, run.bounds.w - rendered.w)
            end
        end

        return {
            texture and texture.id or 0,
            x,
            run.bounds.y,
            x + rendered.w,
            run.bounds.y + rendered.h,
        }
    end):totable()
end

local function kernel_batch_row(payload, batch)
    local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_row(payload, batch.state)
    local has_transform, m11, m12, m21, m22, tx, ty = transform_row(batch.state)
    local blend_mode = blend_mode_id(batch.state.blend)

    return U.match(batch.kind, {
        BoxKind = function()
            return {
                CMD_BOX,
                0,
                0,
                batch.item_count,
                clip_enabled,
                clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity,
                blend_mode,
                has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
        ShadowKind = function()
            return {
                CMD_SHADOW,
                0,
                0,
                batch.item_count,
                clip_enabled,
                clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity,
                blend_mode,
                has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
        TextKind = function()
            return {
                CMD_TEXT,
                0,
                0,
                batch.item_count,
                clip_enabled,
                clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity,
                blend_mode,
                has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
        ImageKind = function()
            return {
                CMD_IMAGE,
                0,
                0,
                batch.item_count,
                clip_enabled,
                clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity,
                blend_mode,
                has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
        CustomKind = function(v)
            return {
                CMD_CUSTOM,
                v.family,
                0,
                batch.item_count,
                clip_enabled,
                clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity,
                blend_mode,
                has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
    })
end

return function(T)
    -- ---------------------------------------------------------------------
    -- Public boundary:
    --   UiKernel.Payload:materialize(target, assets, state) -> keep
    -- ---------------------------------------------------------------------
    -- assets is explicit here because text/image runtime payload preparation
    -- still depends on the resource catalog. The exact code shape does not, so
    -- assets stays out of Spec and out of the stable runner.
    T.UiKernel.Payload.materialize = function(payload, target, assets, state)
        target = normalize_target(target)
        if type(state) ~= "cdata" and type(state) ~= "userdata" and type(state) ~= "table" then
            -- Keep error text simple; the important contract is that compile()
            -- allocates the state_t and passes it here.
        end

        local box_rows = F.iter(payload.boxes):map(kernel_box_row):totable()
        local shadow_rows = F.iter(payload.shadows):map(kernel_shadow_row):totable()
        local image_rows = F.iter(payload.images):map(function(item)
            return kernel_image_row(item, assets)
        end):totable()
        local custom_rows = F.iter(payload.customs):map(function(item)
            return { item.payload }
        end):totable()
        local text_run_rows = materialize_text_rows(payload, assets)

        local batch_offsets = {
            BoxBatch = 0,
            ShadowBatch = 0,
            TextBatch = 0,
            ImageBatch = 0,
            CustomBatch = 0,
        }

        local batch_rows = F.iter(payload.batches):map(function(batch)
            local row = kernel_batch_row(payload, batch)
            local ctor = U.match(batch.kind, {
                BoxKind = function() return "BoxBatch" end,
                ShadowKind = function() return "ShadowBatch" end,
                TextKind = function() return "TextBatch" end,
                ImageKind = function() return "ImageBatch" end,
                CustomKind = function() return "CustomBatch" end,
            })
            local item_start = batch_offsets[ctor]
            row[3] = item_start
            batch_offsets[ctor] = item_start + row[4]
            return row
        end):totable()

        local batch_arr, batch_ptr = create_state_array(BatchState, batch_rows)
        local box_arr, box_ptr = create_state_array(BoxItemState, box_rows)
        local shadow_arr, shadow_ptr = create_state_array(ShadowItemState, shadow_rows)
        local run_arr, run_ptr = create_state_array(TextRunState, text_run_rows)
        local image_arr, image_ptr = create_state_array(ImageItemState, image_rows)
        local custom_arr, custom_ptr = create_state_array(CustomItemState, custom_rows)

        state.batch_count = #batch_rows
        state.batches = batch_ptr
        state.box_count = #box_rows
        state.boxes = box_ptr
        state.shadow_count = #shadow_rows
        state.shadows = shadow_ptr
        state.text_run_count = #text_run_rows
        state.text_runs = run_ptr
        state.image_count = #image_rows
        state.images = image_ptr
        state.custom_count = #custom_rows
        state.customs = custom_ptr

        return {
            batches = batch_arr,
            boxes = box_arr,
            shadows = shadow_arr,
            text_runs = run_arr,
            images = image_arr,
            customs = custom_arr,
        }
    end

    -- ---------------------------------------------------------------------
    -- Public boundary:
    --   UiKernel.Spec:compile(target) -> Unit
    -- ---------------------------------------------------------------------
    -- compile now depends only on baked machine facts. Live scene payload is
    -- loaded explicitly later through UiKernel.Payload:materialize.
    T.UiKernel.Spec.compile = U.terminal(function(spec, target)
        target = normalize_target(target)
        local runner = build_scene_runner(target, spec)

        return stateful_unit(runner, SceneState, function(state)
            clear_scene_state(state)
        end, function(state)
            clear_scene_state(state)
        end)
    end)
end
