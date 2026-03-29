local U = require("unit")
local F = require("fun")
local Assets = require("examples.ui.ui_asset_resolve")
local ImageData = require("examples.ui.backend_image_sdl")
local SdlGl = require("examples.ui.backend_sdl_gl")
local Text = require("examples.ui.backend_text_sdl_ttf")
local Std = terralib.includec("stdlib.h")

local int32 = terralib.types.int32
local uint32 = terralib.types.uint32
local double = terralib.types.double
local uintptr = terralib.types.uint64

local function L(xs)
    return terralib.newlist(xs or {})
end

local function ptr_t(t)
    return &t
end

-- ============================================================================
-- UiMachine.Gen:compile / UiMachine.Render:materialize
-- ----------------------------------------------------------------------------
-- This file implements backend realization of the explicit ui2 machine layer.
--
-- Boundary meanings:
--   UiMachine.Gen:compile(target) -> Unit
--   UiMachine.Render:materialize(target, assets, state) -> keep
--
-- Why compile/materialize are split:
--   compile answers:
--     "what stable machine code + ABI do we install?"
--
--   materialize answers:
--     "what live payload do we load into that ABI right now?"
--
-- What compile consumes:
--   - UiMachine.Gen
--   - explicit render target contract
--
-- What compile produces:
--   - one Unit with a stable scene runner and one state_t layout
--   - generic init/release hooks for emptying scene state
--
-- What materialize consumes:
--   - UiMachine.Render.param
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


local function normalize_target(target)
    if not target then
        error("UiMachine.Render: target is required", 3)
    end

    if type(target.runtime_t) == "function" and type(target.headers) == "function" then
        return {
            backend = target,
            custom = {},
        }
    end

    if type(target) ~= "table" or type(target.backend) ~= "table" then
        error("UiMachine.Render: target must be a backend module or { backend = ..., custom = ... }", 3)
    end

    if type(target.backend.runtime_t) ~= "function" or type(target.backend.headers) ~= "function" then
        error("UiMachine.Render: target.backend must provide runtime_t() and headers()", 3)
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
BoxItemState.entries:insert({ field = "tl", type = double })
BoxItemState.entries:insert({ field = "tr", type = double })
BoxItemState.entries:insert({ field = "br", type = double })
BoxItemState.entries:insert({ field = "bl", type = double })

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
ShadowItemState.entries:insert({ field = "tl", type = double })
ShadowItemState.entries:insert({ field = "tr", type = double })
ShadowItemState.entries:insert({ field = "br", type = double })
ShadowItemState.entries:insert({ field = "bl", type = double })

local TextRunState = terralib.types.newstruct("Ui2KernelTextRunState")
TextRunState.entries:insert({ field = "cache_key", type = uint32 })
TextRunState.entries:insert({ field = "tex_id", type = uint32 })
TextRunState.entries:insert({ field = "x1", type = double })
TextRunState.entries:insert({ field = "y1", type = double })
TextRunState.entries:insert({ field = "x2", type = double })
TextRunState.entries:insert({ field = "y2", type = double })

local ImageItemState = terralib.types.newstruct("Ui2KernelImageItemState")
ImageItemState.entries:insert({ field = "tex_id", type = uint32 })
ImageItemState.entries:insert({ field = "x", type = double })
ImageItemState.entries:insert({ field = "y", type = double })
ImageItemState.entries:insert({ field = "w", type = double })
ImageItemState.entries:insert({ field = "h", type = double })
ImageItemState.entries:insert({ field = "opacity", type = double })
ImageItemState.entries:insert({ field = "sampling", type = int32 })
ImageItemState.entries:insert({ field = "tl", type = double })
ImageItemState.entries:insert({ field = "tr", type = double })
ImageItemState.entries:insert({ field = "br", type = double })
ImageItemState.entries:insert({ field = "bl", type = double })

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
SceneState.entries:insert({ field = "text_run_capacity", type = int32 })
SceneState.entries:insert({ field = "text_runs", type = ptr_t(TextRunState) })
SceneState.entries:insert({ field = "image_count", type = int32 })
SceneState.entries:insert({ field = "images", type = ptr_t(ImageItemState) })
SceneState.entries:insert({ field = "custom_count", type = int32 })
SceneState.entries:insert({ field = "customs", type = ptr_t(CustomItemState) })

local init_scene_state = terra(state : &SceneState)
    state.text_run_capacity = 0
    state.text_runs = nil
    state.batch_count = 0
    state.batches = nil
    state.box_count = 0
    state.boxes = nil
    state.shadow_count = 0
    state.shadows = nil
    state.text_run_count = 0
    state.image_count = 0
    state.images = nil
    state.custom_count = 0
    state.customs = nil
end
init_scene_state:compile()

local clear_scene_state = terra(state : &SceneState)
    state.batch_count = 0
    state.batches = nil
    state.box_count = 0
    state.boxes = nil
    state.shadow_count = 0
    state.shadows = nil
    state.text_run_count = 0
    if state.text_run_capacity == 0 then
        state.text_runs = nil
    end
    state.image_count = 0
    state.images = nil
    state.custom_count = 0
    state.customs = nil
end
clear_scene_state:compile()

local release_scene_state = terra(state : &SceneState)
    if state.text_runs ~= nil then
        Std.free(state.text_runs)
    end
    state.text_run_capacity = 0
    clear_scene_state(state)
end
release_scene_state:compile()

local CMD_BOX = 1
local CMD_SHADOW = 2
local CMD_TEXT = 3
local CMD_IMAGE = 4
local CMD_CUSTOM = 5

local SHADOW_DROP = 1
local SHADOW_INNER = 2

local QUARTER_ARC = {
    { 0.0, -1.0 },
    { 0.38268343236509, -0.92387953251129 },
    { 0.70710678118655, -0.70710678118655 },
    { 0.92387953251129, -0.38268343236509 },
    { 1.0, 0.0 },
}

local function custom_handlers_for(target, spec)
    local target_custom = target.custom or {}

    return F.iter(spec.custom_families):map(function(family)
        local fn = target_custom[family.family]
        if fn == nil then
            error(("UiMachine.Render: missing target custom handler for family %s")
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

    local draw_rounded_solid_rt = terra(rt : &Runtime, x : double, y : double, w : double, h : double, tl : double, tr : double, br : double, bl : double, r : double, g : double, b : double, a : double)
        var limit = w
        if h < limit then limit = h end
        limit = limit * 0.5
        if tl < 0 then tl = 0 elseif tl > limit then tl = limit end
        if tr < 0 then tr = 0 elseif tr > limit then tr = limit end
        if br < 0 then br = 0 elseif br > limit then br = limit end
        if bl < 0 then bl = 0 elseif bl > limit then bl = limit end

        C.glColor4d(r, g, b, a * rt.opacity)
        C.glBegin(C.GL_POLYGON)
        if tr > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + w - tr) + [q[1]] * tr, (y + tr) + [q[2]] * tr) end
                end
            end
        else
            C.glVertex2d(x + w, y)
        end
        if br > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + w - br) - [q[2]] * br, (y + h - br) + [q[1]] * br) end
                end
            end
        else
            C.glVertex2d(x + w, y + h)
        end
        if bl > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + bl) - [q[1]] * bl, (y + h - bl) - [q[2]] * bl) end
                end
            end
        else
            C.glVertex2d(x, y + h)
        end
        if tl > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + tl) + [q[2]] * tl, (y + tl) - [q[1]] * tl) end
                end
            end
        else
            C.glVertex2d(x, y)
        end
        C.glEnd()
    end
    draw_rounded_solid_rt:compile()

    local draw_rounded_stroke_rt = terra(rt : &Runtime, x : double, y : double, w : double, h : double, tl : double, tr : double, br : double, bl : double, r : double, g : double, b : double, a : double, stroke_width : double)
        var limit = w
        if h < limit then limit = h end
        limit = limit * 0.5
        if tl < 0 then tl = 0 elseif tl > limit then tl = limit end
        if tr < 0 then tr = 0 elseif tr > limit then tr = limit end
        if br < 0 then br = 0 elseif br > limit then br = limit end
        if bl < 0 then bl = 0 elseif bl > limit then bl = limit end

        C.glLineWidth(stroke_width)
        C.glColor4d(r, g, b, a * rt.opacity)
        C.glBegin(C.GL_LINE_LOOP)
        if tr > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + w - tr) + [q[1]] * tr, (y + tr) + [q[2]] * tr) end
                end
            end
        else
            C.glVertex2d(x + w, y)
        end
        if br > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + w - br) - [q[2]] * br, (y + h - br) + [q[1]] * br) end
                end
            end
        else
            C.glVertex2d(x + w, y + h)
        end
        if bl > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + bl) - [q[1]] * bl, (y + h - bl) - [q[2]] * bl) end
                end
            end
        else
            C.glVertex2d(x, y + h)
        end
        if tl > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + tl) + [q[2]] * tl, (y + tl) - [q[1]] * tl) end
                end
            end
        else
            C.glVertex2d(x, y)
        end
        C.glEnd()
    end
    draw_rounded_stroke_rt:compile()

    local draw_rounded_textured_rt = terra(rt : &Runtime, tex_id : uint32, x : double, y : double, w : double, h : double, tl : double, tr : double, br : double, bl : double, opacity : double)
        var limit = w
        if h < limit then limit = h end
        limit = limit * 0.5
        if tl < 0 then tl = 0 elseif tl > limit then tl = limit end
        if tr < 0 then tr = 0 elseif tr > limit then tr = limit end
        if br < 0 then br = 0 elseif br > limit then br = limit end
        if bl < 0 then bl = 0 elseif bl > limit then bl = limit end

        C.glBindTexture(C.GL_TEXTURE_2D, tex_id)
        C.glColor4d(1.0, 1.0, 1.0, opacity * rt.opacity)
        C.glBegin(C.GL_POLYGON)
        if tr > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote
                        C.glTexCoord2d((((x + w - tr) + [q[1]] * tr) - x) / w, (((y + tr) + [q[2]] * tr) - y) / h)
                        C.glVertex2d((x + w - tr) + [q[1]] * tr, (y + tr) + [q[2]] * tr)
                    end
                end
            end
        else
            C.glTexCoord2d(1.0, 0.0)
            C.glVertex2d(x + w, y)
        end
        if br > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote
                        C.glTexCoord2d((((x + w - br) - [q[2]] * br) - x) / w, (((y + h - br) + [q[1]] * br) - y) / h)
                        C.glVertex2d((x + w - br) - [q[2]] * br, (y + h - br) + [q[1]] * br)
                    end
                end
            end
        else
            C.glTexCoord2d(1.0, 1.0)
            C.glVertex2d(x + w, y + h)
        end
        if bl > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote
                        C.glTexCoord2d((((x + bl) - [q[1]] * bl) - x) / w, (((y + h - bl) - [q[2]] * bl) - y) / h)
                        C.glVertex2d((x + bl) - [q[1]] * bl, (y + h - bl) - [q[2]] * bl)
                    end
                end
            end
        else
            C.glTexCoord2d(0.0, 1.0)
            C.glVertex2d(x, y + h)
        end
        if tl > 0 then
            escape
                for _, q in ipairs(QUARTER_ARC) do
                    emit quote
                        C.glTexCoord2d((((x + tl) + [q[2]] * tl) - x) / w, (((y + tl) - [q[1]] * tl) - y) / h)
                        C.glVertex2d((x + tl) + [q[2]] * tl, (y + tl) - [q[1]] * tl)
                    end
                end
            end
        else
            C.glTexCoord2d(0.0, 0.0)
            C.glVertex2d(x, y)
        end
        C.glEnd()
    end
    draw_rounded_textured_rt:compile()

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
            if item.tl ~= 0 or item.tr ~= 0 or item.br ~= 0 or item.bl ~= 0 then
                draw_rounded_solid_rt(rt, item.x, item.y, item.w, item.h, item.tl, item.tr, item.br, item.bl, item.fill_r, item.fill_g, item.fill_b, item.fill_a)
                if item.stroke_enabled ~= 0 and item.stroke_width > 0 then
                    draw_rounded_stroke_rt(rt, item.x, item.y, item.w, item.h, item.tl, item.tr, item.br, item.bl, item.stroke_r, item.stroke_g, item.stroke_b, item.stroke_a, item.stroke_width)
                end
            else
                draw_solid_quad_rt(rt, item.x, item.y, item.w, item.h, item.fill_r, item.fill_g, item.fill_b, item.fill_a)
                if item.stroke_enabled ~= 0 and item.stroke_width > 0 then
                    draw_stroke_loop_rt(rt, item.x, item.y, item.w, item.h, item.stroke_r, item.stroke_g, item.stroke_b, item.stroke_a, item.stroke_width)
                end
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
                    var sx = item.x + item.dx - item.spread - expansion
                    var sy = item.y + item.dy - item.spread - expansion
                    var sw = item.w + 2 * (item.spread + expansion)
                    var sh = item.h + 2 * (item.spread + expansion)
                    if item.tl ~= 0 or item.tr ~= 0 or item.br ~= 0 or item.bl ~= 0 then
                        var grow = item.spread + expansion
                        draw_rounded_solid_rt(rt, sx, sy, sw, sh, item.tl + grow, item.tr + grow, item.br + grow, item.bl + grow, item.r, item.g, item.b, alpha)
                    else
                        draw_solid_quad_rt(rt, sx, sy, sw, sh, item.r, item.g, item.b, alpha)
                    end
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
        C.glEnable(C.GL_TEXTURE_2D)
        var i : int32 = 0
        while i < batch.item_count do
            var item = state.images[batch.item_start + i]
            if item.tex_id ~= 0 then
                if item.tl ~= 0 or item.tr ~= 0 or item.br ~= 0 or item.bl ~= 0 then
                    draw_rounded_textured_rt(rt, item.tex_id, item.x, item.y, item.w, item.h, item.tl, item.tr, item.br, item.bl, item.opacity)
                else
                    C.glBindTexture(C.GL_TEXTURE_2D, item.tex_id)
                    C.glColor4d(1.0, 1.0, 1.0, item.opacity * rt.opacity)
                    C.glBegin(C.GL_QUADS)
                    C.glTexCoord2d(0.0, 0.0)
                    C.glVertex2d(item.x, item.y)
                    C.glTexCoord2d(1.0, 0.0)
                    C.glVertex2d(item.x + item.w, item.y)
                    C.glTexCoord2d(1.0, 1.0)
                    C.glVertex2d(item.x + item.w, item.y + item.h)
                    C.glTexCoord2d(0.0, 1.0)
                    C.glVertex2d(item.x, item.y + item.h)
                    C.glEnd()
                end
            end
            i = i + 1
        end
        C.glDisable(C.GL_TEXTURE_2D)
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
    local path = Assets.image_path(assets, item.image)
    if not square_corners(item.corners) then
        error("UiKernel.Payload:materialize(image): rounded corners are not implemented yet", 3)
    end

    local sampling = item.sampling.kind == "Nearest" and "Nearest" or "Linear"
    local image = ImageData.load_rgba(path)
    local texture = (image.width > 0 and image.height > 0)
        and SdlGl.ensure_rgba_texture(ImageData.texture_key(path, sampling), image.width, image.height, image.pixels, sampling)
        or nil

    return {
        texture and texture.id or 0,
        item.rect.x,
        item.rect.y,
        item.rect.w,
        item.rect.h,
        1.0,
        item.sampling.kind == "Nearest" and 1 or 0,
    }
end

local function ensure_text_run_capacity(state, count)
    if count <= state.text_run_capacity then return end

    if state.text_runs ~= nil then
        Std.free(state.text_runs)
        state.text_runs = nil
    end

    local n = math.max(1, count)
    state.text_runs = terralib.cast(&TextRunState, Std.malloc(terralib.sizeof(TextRunState) * n))
    if state.text_runs == nil then
        error("UiMachine.Render: failed to allocate text run cache", 3)
    end

    state.text_run_capacity = n
    for i = 0, n - 1 do
        state.text_runs[i].cache_key = 0
        state.text_runs[i].tex_id = 0
        state.text_runs[i].x1 = 0
        state.text_runs[i].y1 = 0
        state.text_runs[i].x2 = 0
        state.text_runs[i].y2 = 0
    end
end

local function materialize_text_runs(payload, assets, state)
    local count = #payload.text_runs
    ensure_text_run_capacity(state, count)

    for i, run in ipairs(payload.text_runs) do
        local dst = state.text_runs[i - 1]
        if dst.cache_key ~= run.cache_key then
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

            dst.cache_key = run.cache_key
            dst.tex_id = texture and texture.id or 0
            dst.x1 = x
            dst.y1 = run.bounds.y
            dst.x2 = x + rendered.w
            dst.y2 = run.bounds.y + rendered.h
        end
    end

    state.text_run_count = count
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

local function validate_state_model(machine)
    local param = machine.param.payload
    local state = machine.state

    local function mismatch(field, expected, actual)
        error(
            string.format(
                "UiMachine.Render: state model mismatch for %s: expected %s, got %s",
                field,
                tostring(expected),
                tostring(actual)
            ),
            3
        )
    end

    if state.batch_count ~= #param.batches then mismatch("batch_count", #param.batches, state.batch_count) end
    if state.box_count ~= #param.boxes then mismatch("box_count", #param.boxes, state.box_count) end
    if state.shadow_count ~= #param.shadows then mismatch("shadow_count", #param.shadows, state.shadow_count) end
    if state.text_run_count ~= #param.text_runs then mismatch("text_run_count", #param.text_runs, state.text_run_count) end
    if state.image_count ~= #param.images then mismatch("image_count", #param.images, state.image_count) end
    if state.custom_count ~= #param.customs then mismatch("custom_count", #param.customs, state.custom_count) end
end

local function materialize_param(param, target, assets, state)
    target = normalize_target(target)
    if type(state) ~= "cdata" and type(state) ~= "userdata" and type(state) ~= "table" then
        -- Keep error text simple; the important contract is that compile()
        -- allocates the state_t and passes it here.
    end

    local payload = param

    local box_rows = F.iter(payload.boxes):map(kernel_box_row):totable()
    local shadow_rows = F.iter(payload.shadows):map(kernel_shadow_row):totable()
    local image_rows = F.iter(payload.images):map(function(item)
        return kernel_image_row(item, assets)
    end):totable()
    local custom_rows = F.iter(payload.customs):map(function(item)
        return { item.payload }
    end):totable()
    materialize_text_runs(payload, assets, state)

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
    local image_arr, image_ptr = create_state_array(ImageItemState, image_rows)
    local custom_arr, custom_ptr = create_state_array(CustomItemState, custom_rows)

    state.batch_count = #batch_rows
    state.batches = batch_ptr
    state.box_count = #box_rows
    state.boxes = box_ptr
    state.shadow_count = #shadow_rows
    state.shadows = shadow_ptr
    state.image_count = #image_rows
    state.images = image_ptr
    state.custom_count = #custom_rows
    state.customs = custom_ptr

    return {
        batches = batch_arr,
        boxes = box_arr,
        shadows = shadow_arr,
        images = image_arr,
        customs = custom_arr,
    }
end

return function(T)
    -- ---------------------------------------------------------------------
    -- Public boundary:
    --   UiMachine.Render:materialize(target, assets, state) -> keep
    -- ---------------------------------------------------------------------
    -- assets is explicit here because text/image runtime payload preparation
    -- still depends on the resource catalog. The exact code shape does not, so
    -- assets stays out of gen and out of the stable runner.
    T.UiMachine.Render.materialize = function(machine, target, assets, state)
        validate_state_model(machine)
        return materialize_param(machine.param.payload, target, assets, state)
    end

    -- ---------------------------------------------------------------------
    -- Public boundary:
    --   UiMachine.Gen:compile(target) -> Unit
    -- ---------------------------------------------------------------------
    -- compile is memoized only at the ASDL boundary, on machine `gen`.
    T.UiMachine.Gen.compile = U.terminal(function(gen, target)
        target = normalize_target(target)
        local runner = build_scene_runner(target, gen.spec)

        return stateful_unit(runner, SceneState, function(state)
            init_scene_state(state)
        end, function(state)
            release_scene_state(state)
        end)
    end)
end
