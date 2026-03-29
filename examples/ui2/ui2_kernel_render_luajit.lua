local ffi = require("ffi")
local U = require("unit")
local F = require("fun")
local Assets = require("examples.ui.ui_asset_resolve")
local ImageData = require("examples.ui.backend_image_sdl")
local SdlGl = require("examples.ui.backend_sdl_gl_luajit")
local Text = require("examples.ui.backend_text_sdl_ttf")

if not rawget(_G, "__ui2_kernel_render_luajit_ffi_cdef") then
    ffi.cdef [[
        void *malloc(size_t size);
        void *realloc(void *ptr, size_t size);
        void free(void *ptr);

        typedef struct {
            double x;
            double y;
            double w;
            double h;
            double fill_r;
            double fill_g;
            double fill_b;
            double fill_a;
            int stroke_enabled;
            double stroke_r;
            double stroke_g;
            double stroke_b;
            double stroke_a;
            double stroke_width;
            double tl;
            double tr;
            double br;
            double bl;
        } Ui2KernelBoxItemState;

        typedef struct {
            double x;
            double y;
            double w;
            double h;
            double r;
            double g;
            double b;
            double a;
            double blur;
            double spread;
            double dx;
            double dy;
            int kind;
            double tl;
            double tr;
            double br;
            double bl;
        } Ui2KernelShadowItemState;

        typedef struct {
            unsigned int cache_key;
            unsigned int tex_id;
            double x1;
            double y1;
            double x2;
            double y2;
        } Ui2KernelTextRunState;

        typedef struct {
            unsigned int tex_id;
            double x;
            double y;
            double w;
            double h;
            double opacity;
            int sampling;
            double tl;
            double tr;
            double br;
            double bl;
        } Ui2KernelImageItemState;

        typedef struct {
            double payload;
        } Ui2KernelCustomItemState;

        typedef struct {
            int kind;
            int custom_kind;
            int item_start;
            int item_count;
            int clip_enabled;
            double clip_x;
            double clip_y;
            double clip_w;
            double clip_h;
            double opacity;
            int blend_mode;
            int has_transform;
            double m11;
            double m12;
            double m21;
            double m22;
            double tx;
            double ty;
        } Ui2KernelBatchState;

        typedef struct {
            int batch_count;
            Ui2KernelBatchState *batches;
            int box_count;
            Ui2KernelBoxItemState *boxes;
            int shadow_count;
            Ui2KernelShadowItemState *shadows;
            int text_run_count;
            int text_run_capacity;
            Ui2KernelTextRunState *text_runs;
            int image_count;
            Ui2KernelImageItemState *images;
            int custom_count;
            Ui2KernelCustomItemState *customs;
        } Ui2KernelSceneState;
    ]]
    _G.__ui2_kernel_render_luajit_ffi_cdef = true
end

local BatchState_ct = ffi.typeof("Ui2KernelBatchState")
local BoxItemState_ct = ffi.typeof("Ui2KernelBoxItemState")
local ShadowItemState_ct = ffi.typeof("Ui2KernelShadowItemState")
local TextRunState_ct = ffi.typeof("Ui2KernelTextRunState")
local ImageItemState_ct = ffi.typeof("Ui2KernelImageItemState")
local CustomItemState_ct = ffi.typeof("Ui2KernelCustomItemState")

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

local function init_scene_state(state)
    state.batch_count = 0
    state.batches = nil
    state.box_count = 0
    state.boxes = nil
    state.shadow_count = 0
    state.shadows = nil
    state.text_run_count = 0
    state.text_run_capacity = 0
    state.text_runs = nil
    state.image_count = 0
    state.images = nil
    state.custom_count = 0
    state.customs = nil
end

local function release_scene_state(state)
    if state.text_runs ~= nil then
        ffi.C.free(state.text_runs)
    end
    init_scene_state(state)
end

local SceneState_t = U.state_ffi("Ui2KernelSceneState", {
    init = init_scene_state,
    release = release_scene_state,
})

local function clear_scene_state(state)
    state.batch_count = 0
    state.batches = nil
    state.box_count = 0
    state.boxes = nil
    state.shadow_count = 0
    state.shadows = nil
    state.text_run_count = 0
    state.text_runs = state.text_run_capacity > 0 and state.text_runs or nil
    state.image_count = 0
    state.images = nil
    state.custom_count = 0
    state.customs = nil
end

local function create_state_array(ctype, count)
    local n = math.max(1, count)
    local arr = ffi.new(ffi.typeof("$[?]", ctype), n)
    local ptr = ffi.cast(ffi.typeof("$*", ctype), arr)
    return arr, ptr
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

    if type(target.backend.headers) ~= "function" then
        error("UiMachine.Render: target.backend must provide headers()", 3)
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
    if not xform then return 0, 0, 0, 0, 0, 0, 0 end
    return 1, xform.m11, xform.m12, xform.m21, xform.m22, xform.tx, xform.ty
end

local function custom_handlers_for(target, spec)
    local target_custom = target.custom or {}

    return F.iter(spec.custom_families):map(function(family)
        local fn = target_custom[family.family]
        if type(fn) ~= "function" then
            error(("UiMachine.Render: missing target custom handler for family %s")
                :format(tostring(family.family)), 3)
        end
        return {
            family = family.family,
            fn = fn,
        }
    end):totable()
end

local function runtime_push_clip(GL, C, rt, x, y, w, h)
    local nx = math.floor(x + 0.5)
    local ny = math.floor(y + 0.5)
    local nr = math.floor(x + w + 0.5)
    local nb = math.floor(y + h + 0.5)

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
        local cx1 = math.max(rt.clip_x, nx)
        local cy1 = math.max(rt.clip_y, ny)
        local cx2 = math.min(rt.clip_x + rt.clip_w, nr)
        local cy2 = math.min(rt.clip_y + rt.clip_h, nb)
        rt.clip_x = cx1
        rt.clip_y = cy1
        rt.clip_w = math.max(0, cx2 - cx1)
        rt.clip_h = math.max(0, cy2 - cy1)
    else
        rt.clip_enabled = 1
        rt.clip_x = nx
        rt.clip_y = ny
        rt.clip_w = math.max(0, nr - nx)
        rt.clip_h = math.max(0, nb - ny)
    end

    if rt.clip_enabled ~= 0 and rt.clip_w > 0 and rt.clip_h > 0 then
        GL.glEnable(C.GL_SCISSOR_TEST)
        GL.glScissor(rt.clip_x, rt.height - (rt.clip_y + rt.clip_h), rt.clip_w, rt.clip_h)
    else
        GL.glDisable(C.GL_SCISSOR_TEST)
    end
end

local function runtime_pop_clip(GL, C, rt)
    if rt.clip_top == 0 then
        rt.clip_enabled = 0
        GL.glDisable(C.GL_SCISSOR_TEST)
        return
    end

    rt.clip_top = rt.clip_top - 1
    rt.clip_enabled = rt.clip_enabled_stack[rt.clip_top]
    rt.clip_x = rt.clip_stack[rt.clip_top].x
    rt.clip_y = rt.clip_stack[rt.clip_top].y
    rt.clip_w = rt.clip_stack[rt.clip_top].w
    rt.clip_h = rt.clip_stack[rt.clip_top].h

    if rt.clip_enabled ~= 0 then
        GL.glEnable(C.GL_SCISSOR_TEST)
        GL.glScissor(rt.clip_x, rt.height - (rt.clip_y + rt.clip_h), rt.clip_w, rt.clip_h)
    else
        GL.glDisable(C.GL_SCISSOR_TEST)
    end
end

local function draw_solid_quad_rt(GL, C, rt, x, y, w, h, r, g, b, a)
    GL.glColor4d(r, g, b, a * rt.opacity)
    GL.glBegin(C.GL_QUADS)
    GL.glVertex2d(x, y)
    GL.glVertex2d(x + w, y)
    GL.glVertex2d(x + w, y + h)
    GL.glVertex2d(x, y + h)
    GL.glEnd()
end

local function draw_stroke_loop_rt(GL, C, rt, x, y, w, h, r, g, b, a, stroke_width)
    GL.glLineWidth(stroke_width)
    GL.glColor4d(r, g, b, a * rt.opacity)
    GL.glBegin(C.GL_LINE_LOOP)
    GL.glVertex2d(x, y)
    GL.glVertex2d(x + w, y)
    GL.glVertex2d(x + w, y + h)
    GL.glVertex2d(x, y + h)
    GL.glEnd()
end

local function rounded_radii(w, h, tl, tr, br, bl)
    local limit = math.max(0, math.min(w, h) * 0.5)
    tl = math.min(limit, math.max(0, tl or 0))
    tr = math.min(limit, math.max(0, tr or 0))
    br = math.min(limit, math.max(0, br or 0))
    bl = math.min(limit, math.max(0, bl or 0))
    return tl, tr, br, bl
end

local function emit_rounded_path(x, y, w, h, tl, tr, br, bl, emit)
    tl, tr, br, bl = rounded_radii(w, h, tl, tr, br, bl)

    if tr > 0 then
        local cx, cy = x + w - tr, y + tr
        for i = 1, #QUARTER_ARC do
            local q = QUARTER_ARC[i]
            emit(cx + q[1] * tr, cy + q[2] * tr)
        end
    else
        emit(x + w, y)
    end

    if br > 0 then
        local cx, cy = x + w - br, y + h - br
        for i = 1, #QUARTER_ARC do
            local q = QUARTER_ARC[i]
            emit(cx - q[2] * br, cy + q[1] * br)
        end
    else
        emit(x + w, y + h)
    end

    if bl > 0 then
        local cx, cy = x + bl, y + h - bl
        for i = 1, #QUARTER_ARC do
            local q = QUARTER_ARC[i]
            emit(cx - q[1] * bl, cy - q[2] * bl)
        end
    else
        emit(x, y + h)
    end

    if tl > 0 then
        local cx, cy = x + tl, y + tl
        for i = 1, #QUARTER_ARC do
            local q = QUARTER_ARC[i]
            emit(cx + q[2] * tl, cy - q[1] * tl)
        end
    else
        emit(x, y)
    end
end

local function draw_rounded_solid_rt(GL, C, rt, x, y, w, h, tl, tr, br, bl, r, g, b, a)
    GL.glColor4d(r, g, b, a * rt.opacity)
    GL.glBegin(C.GL_TRIANGLE_FAN)
    GL.glVertex2d(x + w * 0.5, y + h * 0.5)
    local first_x, first_y = nil, nil
    emit_rounded_path(x, y, w, h, tl, tr, br, bl, function(vx, vy)
        if first_x == nil then first_x, first_y = vx, vy end
        GL.glVertex2d(vx, vy)
    end)
    if first_x ~= nil then GL.glVertex2d(first_x, first_y) end
    GL.glEnd()
end

local function draw_rounded_stroke_rt(GL, C, rt, x, y, w, h, tl, tr, br, bl, r, g, b, a, stroke_width)
    GL.glLineWidth(stroke_width)
    GL.glColor4d(r, g, b, a * rt.opacity)
    GL.glBegin(C.GL_LINE_LOOP)
    emit_rounded_path(x, y, w, h, tl, tr, br, bl, function(vx, vy)
        GL.glVertex2d(vx, vy)
    end)
    GL.glEnd()
end

local function draw_rounded_textured_rt(GL, C, rt, tex_id, x, y, w, h, tl, tr, br, bl, opacity)
    GL.glBindTexture(C.GL_TEXTURE_2D, tex_id)
    GL.glColor4d(1.0, 1.0, 1.0, opacity * rt.opacity)
    GL.glBegin(C.GL_TRIANGLE_FAN)
    GL.glTexCoord2d(0.5, 0.5)
    GL.glVertex2d(x + w * 0.5, y + h * 0.5)
    local first_x, first_y = nil, nil
    emit_rounded_path(x, y, w, h, tl, tr, br, bl, function(vx, vy)
        if first_x == nil then first_x, first_y = vx, vy end
        GL.glTexCoord2d((vx - x) / w, (vy - y) / h)
        GL.glVertex2d(vx, vy)
    end)
    if first_x ~= nil then
        GL.glTexCoord2d((first_x - x) / w, (first_y - y) / h)
        GL.glVertex2d(first_x, first_y)
    end
    GL.glEnd()
end

local function begin_batch(GL, C, rt, batch)
    GL.glPushAttrib(C.GL_COLOR_BUFFER_BIT)
    GL.glEnable(C.GL_BLEND)

    if batch.blend_mode == 1 then
        GL.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE_MINUS_SRC_ALPHA)
    elseif batch.blend_mode == 2 then
        GL.glBlendFunc(C.GL_SRC_ALPHA, C.GL_ONE)
    elseif batch.blend_mode == 3 then
        GL.glBlendFunc(C.GL_DST_COLOR, C.GL_ONE_MINUS_SRC_ALPHA)
    elseif batch.blend_mode == 4 then
        GL.glBlendFunc(C.GL_ONE, C.GL_ONE_MINUS_SRC_COLOR)
    end

    rt.opacity_stack[rt.opacity_top] = rt.opacity
    rt.opacity_top = rt.opacity_top + 1
    rt.opacity = rt.opacity * batch.opacity

    if batch.clip_enabled ~= 0 then
        runtime_push_clip(GL, C, rt, batch.clip_x, batch.clip_y, batch.clip_w, batch.clip_h)
    end

    if batch.has_transform ~= 0 then
        GL.glMatrixMode(C.GL_MODELVIEW)
        GL.glPushMatrix()
        local mx = ffi.new("GLdouble[16]", {
            batch.m11, batch.m12, 0.0, 0.0,
            batch.m21, batch.m22, 0.0, 0.0,
            0.0,       0.0,       1.0, 0.0,
            batch.tx,  batch.ty,  0.0, 1.0,
        })
        GL.glMultMatrixd(mx)
    end
end

local function end_batch(GL, C, rt, batch)
    if batch.has_transform ~= 0 then
        GL.glMatrixMode(C.GL_MODELVIEW)
        GL.glPopMatrix()
    end
    if batch.clip_enabled ~= 0 then
        runtime_pop_clip(GL, C, rt)
    end
    rt.opacity_top = rt.opacity_top - 1
    rt.opacity = rt.opacity_stack[rt.opacity_top]
    GL.glPopAttrib()
end

local function render_boxes(GL, C, rt, state, batch)
    GL.glDisable(C.GL_TEXTURE_2D)
    local i = 0
    while i < batch.item_count do
        local item = state.boxes[batch.item_start + i]
        if item.tl ~= 0 or item.tr ~= 0 or item.br ~= 0 or item.bl ~= 0 then
            draw_rounded_solid_rt(GL, C, rt, item.x, item.y, item.w, item.h, item.tl, item.tr, item.br, item.bl, item.fill_r, item.fill_g, item.fill_b, item.fill_a)
            if item.stroke_enabled ~= 0 and item.stroke_width > 0 then
                draw_rounded_stroke_rt(GL, C, rt, item.x, item.y, item.w, item.h, item.tl, item.tr, item.br, item.bl, item.stroke_r, item.stroke_g, item.stroke_b, item.stroke_a, item.stroke_width)
            end
        else
            draw_solid_quad_rt(GL, C, rt, item.x, item.y, item.w, item.h, item.fill_r, item.fill_g, item.fill_b, item.fill_a)
            if item.stroke_enabled ~= 0 and item.stroke_width > 0 then
                draw_stroke_loop_rt(GL, C, rt, item.x, item.y, item.w, item.h, item.stroke_r, item.stroke_g, item.stroke_b, item.stroke_a, item.stroke_width)
            end
        end
        i = i + 1
    end
end

local function render_shadows(GL, C, rt, state, batch)
    GL.glDisable(C.GL_TEXTURE_2D)
    local i = 0
    while i < batch.item_count do
        local item = state.shadows[batch.item_start + i]
        if item.kind == SHADOW_DROP then
            local passes = item.blur > 0 and math.min(16, math.ceil(item.blur)) or 1
            local j = 0
            while j < passes do
                local expansion = item.blur > 0 and (item.blur * (passes - j) / passes) or 0
                local alpha = item.blur > 0 and (item.a / passes) or item.a
                local sx = item.x + item.dx - item.spread - expansion
                local sy = item.y + item.dy - item.spread - expansion
                local sw = item.w + 2 * (item.spread + expansion)
                local sh = item.h + 2 * (item.spread + expansion)
                if item.tl ~= 0 or item.tr ~= 0 or item.br ~= 0 or item.bl ~= 0 then
                    local grow = item.spread + expansion
                    draw_rounded_solid_rt(GL, C, rt, sx, sy, sw, sh, item.tl + grow, item.tr + grow, item.br + grow, item.bl + grow, item.r, item.g, item.b, alpha)
                else
                    draw_solid_quad_rt(GL, C, rt, sx, sy, sw, sh, item.r, item.g, item.b, alpha)
                end
                j = j + 1
            end
        else
            runtime_push_clip(GL, C, rt, item.x, item.y, item.w, item.h)
            local passes = item.blur > 0 and math.min(16, math.ceil(item.blur)) or 1
            local j = 0
            while j < passes do
                local outer_inset = item.blur > 0 and (item.blur * j / passes) or 0
                local inner_inset = item.blur > 0 and (item.blur * (j + 1) / passes) or 1.0
                local source_x = item.x + item.dx - item.spread
                local source_y = item.y + item.dy - item.spread
                local source_w = item.w + 2 * item.spread
                local source_h = item.h + 2 * item.spread
                local ox = source_x + outer_inset
                local oy = source_y + outer_inset
                local ow = source_w - 2 * outer_inset
                local oh = source_h - 2 * outer_inset
                local ix = source_x + inner_inset
                local iy = source_y + inner_inset
                local iw = source_w - 2 * inner_inset
                local ih = source_h - 2 * inner_inset
                local alpha = item.blur > 0 and (item.a / passes) or item.a
                if oh > 0 and ow > 0 then
                    if iy > oy then draw_solid_quad_rt(GL, C, rt, ox, oy, ow, iy - oy, item.r, item.g, item.b, alpha) end
                    if oy + oh > iy + ih then draw_solid_quad_rt(GL, C, rt, ox, iy + ih, ow, (oy + oh) - (iy + ih), item.r, item.g, item.b, alpha) end
                    if ix > ox and ih > 0 then draw_solid_quad_rt(GL, C, rt, ox, iy, ix - ox, ih, item.r, item.g, item.b, alpha) end
                    if ox + ow > ix + iw and ih > 0 then draw_solid_quad_rt(GL, C, rt, ix + iw, iy, (ox + ow) - (ix + iw), ih, item.r, item.g, item.b, alpha) end
                end
                j = j + 1
            end
            runtime_pop_clip(GL, C, rt)
        end
        i = i + 1
    end
end

local function render_text(GL, C, rt, state, batch)
    GL.glEnable(C.GL_TEXTURE_2D)
    local i = 0
    while i < batch.item_count do
        local item = state.text_runs[batch.item_start + i]
        if item.tex_id ~= 0 then
            GL.glBindTexture(C.GL_TEXTURE_2D, item.tex_id)
            GL.glColor4d(1.0, 1.0, 1.0, rt.opacity)
            GL.glBegin(C.GL_QUADS)
            GL.glTexCoord2d(0.0, 0.0); GL.glVertex2d(item.x1, item.y1)
            GL.glTexCoord2d(1.0, 0.0); GL.glVertex2d(item.x2, item.y1)
            GL.glTexCoord2d(1.0, 1.0); GL.glVertex2d(item.x2, item.y2)
            GL.glTexCoord2d(0.0, 1.0); GL.glVertex2d(item.x1, item.y2)
            GL.glEnd()
        end
        i = i + 1
    end
    GL.glDisable(C.GL_TEXTURE_2D)
end

local function render_images(GL, C, rt, state, batch)
    GL.glEnable(C.GL_TEXTURE_2D)
    local i = 0
    while i < batch.item_count do
        local item = state.images[batch.item_start + i]
        if item.tex_id ~= 0 then
            if item.tl ~= 0 or item.tr ~= 0 or item.br ~= 0 or item.bl ~= 0 then
                draw_rounded_textured_rt(GL, C, rt, item.tex_id, item.x, item.y, item.w, item.h, item.tl, item.tr, item.br, item.bl, item.opacity)
            else
                GL.glBindTexture(C.GL_TEXTURE_2D, item.tex_id)
                GL.glColor4d(1.0, 1.0, 1.0, item.opacity * rt.opacity)
                GL.glBegin(C.GL_QUADS)
                GL.glTexCoord2d(0.0, 0.0); GL.glVertex2d(item.x, item.y)
                GL.glTexCoord2d(1.0, 0.0); GL.glVertex2d(item.x + item.w, item.y)
                GL.glTexCoord2d(1.0, 1.0); GL.glVertex2d(item.x + item.w, item.y + item.h)
                GL.glTexCoord2d(0.0, 1.0); GL.glVertex2d(item.x, item.y + item.h)
                GL.glEnd()
            end
        end
        i = i + 1
    end
    GL.glDisable(C.GL_TEXTURE_2D)
end

local function build_scene_runner(target, spec)
    local backend = target.backend
    local GL = backend.GL
    local C = backend.headers()
    local custom_handlers = custom_handlers_for(target, spec)
    local custom_by_family = {}

    for _, info in ipairs(custom_handlers) do
        custom_by_family[info.family] = info.fn
    end

    return function(state, rt)
        rt.opacity = 1.0
        rt.opacity_top = 0
        rt.clip_enabled = 0
        rt.clip_top = 0

        GL.glViewport(0, 0, rt.width, rt.height)
        GL.glMatrixMode(C.GL_PROJECTION)
        GL.glLoadIdentity()
        GL.glOrtho(0.0, rt.width, rt.height, 0.0, -1.0, 1.0)
        GL.glMatrixMode(C.GL_MODELVIEW)
        GL.glLoadIdentity()
        GL.glDisable(C.GL_DEPTH_TEST)
        GL.glDisable(C.GL_SCISSOR_TEST)
        GL.glClearColor(0.12, 0.12, 0.12, 1.0)
        GL.glClear(C.GL_COLOR_BUFFER_BIT)

        local i = 0
        while i < state.batch_count do
            local batch = state.batches[i]
            begin_batch(GL, C, rt, batch)
            if batch.kind == CMD_BOX then
                render_boxes(GL, C, rt, state, batch)
            elseif batch.kind == CMD_SHADOW then
                render_shadows(GL, C, rt, state, batch)
            elseif batch.kind == CMD_TEXT then
                render_text(GL, C, rt, state, batch)
            elseif batch.kind == CMD_IMAGE then
                render_images(GL, C, rt, state, batch)
            elseif batch.kind == CMD_CUSTOM then
                local fn = custom_by_family[batch.custom_kind]
                if fn then
                    local j = 0
                    while j < batch.item_count do
                        fn(rt, state.customs[batch.item_start + j].payload)
                        j = j + 1
                    end
                end
            end
            end_batch(GL, C, rt, batch)
            i = i + 1
        end
    end
end

local function kernel_box_row(item)
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
        item.corners.top_left,
        item.corners.top_right,
        item.corners.bottom_right,
        item.corners.bottom_left,
    }
end

local function kernel_shadow_row(item)
    if not square_corners(item.corners) and item.shadow_kind.kind ~= "DropShadow" then
        error("UiKernel.Payload:materialize(shadow): rounded inner shadows are not implemented yet", 3)
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
        item.corners.top_left,
        item.corners.top_right,
        item.corners.bottom_right,
        item.corners.bottom_left,
    }
end

local function kernel_image_row(item, assets)
    local path = Assets.image_path(assets, item.image)
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
        item.corners.top_left,
        item.corners.top_right,
        item.corners.bottom_right,
        item.corners.bottom_left,
    }
end

local function ensure_text_run_capacity(state, count)
    if count <= state.text_run_capacity then return end

    local n = math.max(1, count)
    local bytes = ffi.sizeof(TextRunState_ct) * n
    local ptr = ffi.cast(ffi.typeof("Ui2KernelTextRunState*"), ffi.C.realloc(state.text_runs, bytes))
    if ptr == nil then
        error("UiMachine.Render: failed to allocate text run cache", 3)
    end

    local i = state.text_run_capacity
    while i < n do
        ptr[i].cache_key = 0
        ptr[i].tex_id = 0
        ptr[i].x1 = 0
        ptr[i].y1 = 0
        ptr[i].x2 = 0
        ptr[i].y2 = 0
        i = i + 1
    end

    state.text_runs = ptr
    state.text_run_capacity = n
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
                CMD_BOX, 0, 0, batch.item_count,
                clip_enabled, clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity, blend_mode, has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
        ShadowKind = function()
            return {
                CMD_SHADOW, 0, 0, batch.item_count,
                clip_enabled, clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity, blend_mode, has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
        TextKind = function()
            return {
                CMD_TEXT, 0, 0, batch.item_count,
                clip_enabled, clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity, blend_mode, has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
        ImageKind = function()
            return {
                CMD_IMAGE, 0, 0, batch.item_count,
                clip_enabled, clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity, blend_mode, has_transform,
                m11, m12, m21, m22, tx, ty,
            }
        end,
        CustomKind = function(v)
            return {
                CMD_CUSTOM, v.family, 0, batch.item_count,
                clip_enabled, clip_x, clip_y, clip_w, clip_h,
                batch.state.opacity, blend_mode, has_transform,
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

local function materialize_param(payload, target, assets, state)
    target = normalize_target(target)

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
        row[3] = batch_offsets[ctor]
        batch_offsets[ctor] = row[3] + row[4]
        return row
    end):totable()

    local batch_arr, batch_ptr = create_state_array(BatchState_ct, #batch_rows)
    for i, row in ipairs(batch_rows) do
        local dst = batch_arr[i - 1]
        dst.kind = row[1]
        dst.custom_kind = row[2]
        dst.item_start = row[3]
        dst.item_count = row[4]
        dst.clip_enabled = row[5]
        dst.clip_x = row[6]
        dst.clip_y = row[7]
        dst.clip_w = row[8]
        dst.clip_h = row[9]
        dst.opacity = row[10]
        dst.blend_mode = row[11]
        dst.has_transform = row[12]
        dst.m11 = row[13]
        dst.m12 = row[14]
        dst.m21 = row[15]
        dst.m22 = row[16]
        dst.tx = row[17]
        dst.ty = row[18]
    end

    local box_arr, box_ptr = create_state_array(BoxItemState_ct, #box_rows)
    for i, row in ipairs(box_rows) do
        local dst = box_arr[i - 1]
        dst.x = row[1]; dst.y = row[2]; dst.w = row[3]; dst.h = row[4]
        dst.fill_r = row[5]; dst.fill_g = row[6]; dst.fill_b = row[7]; dst.fill_a = row[8]
        dst.stroke_enabled = row[9]
        dst.stroke_r = row[10]; dst.stroke_g = row[11]; dst.stroke_b = row[12]; dst.stroke_a = row[13]
        dst.stroke_width = row[14]
        dst.tl = row[15]; dst.tr = row[16]; dst.br = row[17]; dst.bl = row[18]
    end

    local shadow_arr, shadow_ptr = create_state_array(ShadowItemState_ct, #shadow_rows)
    for i, row in ipairs(shadow_rows) do
        local dst = shadow_arr[i - 1]
        dst.x = row[1]; dst.y = row[2]; dst.w = row[3]; dst.h = row[4]
        dst.r = row[5]; dst.g = row[6]; dst.b = row[7]; dst.a = row[8]
        dst.blur = row[9]; dst.spread = row[10]; dst.dx = row[11]; dst.dy = row[12]
        dst.kind = row[13]
        dst.tl = row[14]; dst.tr = row[15]; dst.br = row[16]; dst.bl = row[17]
    end

    local image_arr, image_ptr = create_state_array(ImageItemState_ct, #image_rows)
    for i, row in ipairs(image_rows) do
        local dst = image_arr[i - 1]
        dst.tex_id = row[1]
        dst.x = row[2]; dst.y = row[3]; dst.w = row[4]; dst.h = row[5]
        dst.opacity = row[6]; dst.sampling = row[7]
        dst.tl = row[8]; dst.tr = row[9]; dst.br = row[10]; dst.bl = row[11]
    end

    local custom_arr, custom_ptr = create_state_array(CustomItemState_ct, #custom_rows)
    for i, row in ipairs(custom_rows) do
        custom_arr[i - 1].payload = row[1]
    end

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
    T.UiMachine.Render.materialize = function(machine, target, assets, state)
        validate_state_model(machine)
        return materialize_param(machine.param.payload, target, assets, state)
    end

    T.UiMachine.Gen.compile = U.terminal(function(gen, target)
        target = normalize_target(target)
        local runner = build_scene_runner(target, gen.spec)
        local unit = U.leaf(SceneState_t, function(state, rt)
            return runner(state, rt)
        end)
        unit.init = init_scene_state
        unit.release = release_scene_state
        return unit
    end)
end
