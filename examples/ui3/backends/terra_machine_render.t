local ffi = require("ffi")
local U = require("unit")
local F = require("fun")
local Assets = require("examples.ui.ui_asset_resolve")
local Text = require("examples.ui.backend_text_sdl_ttf")
local ImageData = require("examples.ui.backend_image_sdl")
local SdlGl = require("examples.ui.backend_sdl_gl")
local Std = terralib.includecstring [[
    #include <stdlib.h>
]]

local int32 = terralib.types.int32
local uint32 = terralib.types.uint32
local uint64 = terralib.types.uint64
local double = terralib.types.double

local CMD_BOX = 1
local CMD_SHADOW = 2
local CMD_TEXT = 3
local CMD_IMAGE = 4

local SHADOW_DROP = 1
local SHADOW_INNER = 2

local QUARTER_ARC = {
    { 0.0, -1.0 },
    { 0.38268343236509, -0.92387953251129 },
    { 0.70710678118655, -0.70710678118655 },
    { 0.92387953251129, -0.38268343236509 },
    { 1.0, 0.0 },
}

local function unsupported(context, detail)
    error(("%s: %s"):format(context, detail), 3)
end

local function reject_any(xs, context, detail)
    F.iter(xs):each(function(_)
        unsupported(context, detail)
    end)
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

    if type(target) == "table" and type(target.backend) == "table"
        and type(target.backend.runtime_t) == "function"
        and type(target.backend.headers) == "function" then
        return {
            backend = target.backend,
            custom = target.custom or {},
        }
    end

    error("UiMachine.Render: target must be a backend module or { backend = backend_module }", 3)
end

local function solid_color(brush, context)
    if not brush then return nil end
    return U.match(brush, {
        Solid = function(v)
            return v.color
        end,
        LinearGradient = function(_)
            unsupported(context, "only Solid brush is supported in ui3 Layer 1")
        end,
        RadialGradient = function(_)
            unsupported(context, "only Solid brush is supported in ui3 Layer 1")
        end,
    })
end

local function square_corners(corners)
    return corners.top_left == 0
       and corners.top_right == 0
       and corners.bottom_right == 0
       and corners.bottom_left == 0
end

local function supported_clip_rect(shape, context)
    return U.match(shape, {
        ClipRect = function(v)
            return v.rect
        end,
        ClipRoundedRect = function(_)
            unsupported(context, "rounded clip shapes are not implemented yet")
        end,
    })
end

local function intersect_rects(a, b)
    local x1 = math.max(a.x, b.x)
    local y1 = math.max(a.y, b.y)
    local x2 = math.min(a.x + a.w, b.x + b.w)
    local y2 = math.min(a.y + a.h, b.y + b.h)
    if x2 < x1 then x2 = x1 end
    if y2 < y1 then y2 = y1 end
    return {
        x = x1,
        y = y1,
        w = x2 - x1,
        h = y2 - y1,
    }
end

local function clip_path_rect(path, context)
    if not path then return nil end
    return F.iter(path.shapes)
        :map(function(shape)
            return supported_clip_rect(shape, context)
        end)
        :reduce(function(acc, rect)
            return acc and intersect_rects(acc, rect) or rect
        end, nil)
end

local function blend_mode_id(mode)
    return U.match(mode, {
        BlendNormal = function() return 1 end,
        BlendAdd = function() return 2 end,
        BlendMultiply = function() return 3 end,
        BlendScreen = function() return 4 end,
        BlendOverlay = function()
            unsupported("UiMachine.Render", "BlendOverlay is not implemented yet")
        end,
    })
end

local function resource_at(resources, ref, context)
    if ref == nil then
        unsupported(context, "resource ref is required")
    end
    local index = type(ref) == "number"
        and (ref + 1)
        or ((ref.slot or ref.index or ref.value or 0) + 1)
    local value = resources[index]
    if value == nil then
        unsupported(context, "resource ref out of range")
    end
    return value
end

local function text_cache_key(spec)
    return tonumber(spec.key) or 0
end

local function image_cache_key(spec)
    return tonumber(spec.key) or 0
end

local function validate_shape(gen)
    reject_any(gen.shape.custom_families,
        "UiMachine.RenderGen",
        "custom families are not implemented yet")
end

local function validate_state_schema(machine)
    local schema = machine.state.schema
    reject_any(schema.custom,
        "UiMachine.Render",
        "custom state families are not implemented yet")
    U.match(schema.install, {
        CapacityTracking = function() end,
    })
    F.iter(schema.resources):each(function(resource)
        U.match(resource, {
            TextResources = function() end,
            ImageResources = function() end,
        })
    end)
    F.iter(machine.state.text_residency):each(function(slot)
        if slot.request_index == nil then
            unsupported("UiMachine.Render", "text residency request index is required")
        end
    end)
    F.iter(machine.state.image_residency):each(function(slot)
        if slot.request_index == nil then
            unsupported("UiMachine.Render", "image residency request index is required")
        end
    end)
end

local function validate_draw_state(draw_state)
    U.match(draw_state.blend, {
        BlendNormal = function() end,
        BlendAdd = function() end,
        BlendMultiply = function() end,
        BlendScreen = function() end,
        BlendOverlay = function()
            unsupported("UiMachine.Render", "BlendOverlay is not implemented yet")
        end,
    })
    return draw_state
end

local function batch_kind_info(kind)
    return U.match(kind, {
        BoxKind = function() return { id = CMD_BOX } end,
        ShadowKind = function() return { id = CMD_SHADOW } end,
        TextKind = function() return { id = CMD_TEXT } end,
        ImageKind = function() return { id = CMD_IMAGE } end,
        CustomKind = function(_)
            unsupported("UiMachine.Render", "custom batches are not implemented yet")
        end,
    })
end

return function(T)
    local BatchState = terralib.types.newstruct("Ui3Layer1BatchState")
    BatchState.entries:insert({ field = "kind", type = int32 })
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

    local BoxItemState = terralib.types.newstruct("Ui3Layer1BoxItemState")
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

    local ShadowItemState = terralib.types.newstruct("Ui3Layer1ShadowItemState")
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

    local TextResourceState = terralib.types.newstruct("Ui3Layer1TextResourceState")
    TextResourceState.entries:insert({ field = "cache_key", type = uint64 })
    TextResourceState.entries:insert({ field = "tex_id", type = uint32 })
    TextResourceState.entries:insert({ field = "w", type = double })
    TextResourceState.entries:insert({ field = "h", type = double })

    local TextDrawState = terralib.types.newstruct("Ui3Layer1TextDrawState")
    TextDrawState.entries:insert({ field = "request_index", type = int32 })
    TextDrawState.entries:insert({ field = "x", type = double })
    TextDrawState.entries:insert({ field = "y", type = double })

    local ImageResourceState = terralib.types.newstruct("Ui3Layer1ImageResourceState")
    ImageResourceState.entries:insert({ field = "cache_key", type = uint64 })
    ImageResourceState.entries:insert({ field = "tex_id", type = uint32 })

    local ImageDrawState = terralib.types.newstruct("Ui3Layer1ImageDrawState")
    ImageDrawState.entries:insert({ field = "request_index", type = int32 })
    ImageDrawState.entries:insert({ field = "x", type = double })
    ImageDrawState.entries:insert({ field = "y", type = double })
    ImageDrawState.entries:insert({ field = "w", type = double })
    ImageDrawState.entries:insert({ field = "h", type = double })
    ImageDrawState.entries:insert({ field = "opacity", type = double })
    ImageDrawState.entries:insert({ field = "tl", type = double })
    ImageDrawState.entries:insert({ field = "tr", type = double })
    ImageDrawState.entries:insert({ field = "br", type = double })
    ImageDrawState.entries:insert({ field = "bl", type = double })

    local SceneState = terralib.types.newstruct("Ui3Layer1SceneState")
    SceneState.entries:insert({ field = "batch_count", type = int32 })
    SceneState.entries:insert({ field = "batch_capacity", type = int32 })
    SceneState.entries:insert({ field = "batches", type = &BatchState })
    SceneState.entries:insert({ field = "box_count", type = int32 })
    SceneState.entries:insert({ field = "box_capacity", type = int32 })
    SceneState.entries:insert({ field = "boxes", type = &BoxItemState })
    SceneState.entries:insert({ field = "shadow_count", type = int32 })
    SceneState.entries:insert({ field = "shadow_capacity", type = int32 })
    SceneState.entries:insert({ field = "shadows", type = &ShadowItemState })
    SceneState.entries:insert({ field = "text_resource_count", type = int32 })
    SceneState.entries:insert({ field = "text_resource_capacity", type = int32 })
    SceneState.entries:insert({ field = "text_resources", type = &TextResourceState })
    SceneState.entries:insert({ field = "text_draw_count", type = int32 })
    SceneState.entries:insert({ field = "text_draw_capacity", type = int32 })
    SceneState.entries:insert({ field = "text_draws", type = &TextDrawState })
    SceneState.entries:insert({ field = "image_resource_count", type = int32 })
    SceneState.entries:insert({ field = "image_resource_capacity", type = int32 })
    SceneState.entries:insert({ field = "image_resources", type = &ImageResourceState })
    SceneState.entries:insert({ field = "image_draw_count", type = int32 })
    SceneState.entries:insert({ field = "image_draw_capacity", type = int32 })
    SceneState.entries:insert({ field = "image_draws", type = &ImageDrawState })

    local init_scene_state = terra(state : &SceneState)
        state.batch_count = 0
        state.batch_capacity = 0
        state.batches = nil
        state.box_count = 0
        state.box_capacity = 0
        state.boxes = nil
        state.shadow_count = 0
        state.shadow_capacity = 0
        state.shadows = nil
        state.text_resource_count = 0
        state.text_resource_capacity = 0
        state.text_resources = nil
        state.text_draw_count = 0
        state.text_draw_capacity = 0
        state.text_draws = nil
        state.image_resource_count = 0
        state.image_resource_capacity = 0
        state.image_resources = nil
        state.image_draw_count = 0
        state.image_draw_capacity = 0
        state.image_draws = nil
    end
    init_scene_state:compile()

    local clear_scene_state = terra(state : &SceneState)
        state.batch_count = 0
        if state.batch_capacity == 0 then state.batches = nil end
        state.box_count = 0
        if state.box_capacity == 0 then state.boxes = nil end
        state.shadow_count = 0
        if state.shadow_capacity == 0 then state.shadows = nil end
        state.text_resource_count = 0
        if state.text_resource_capacity == 0 then state.text_resources = nil end
        state.text_draw_count = 0
        if state.text_draw_capacity == 0 then state.text_draws = nil end
        state.image_resource_count = 0
        if state.image_resource_capacity == 0 then state.image_resources = nil end
        state.image_draw_count = 0
        if state.image_draw_capacity == 0 then state.image_draws = nil end
    end
    clear_scene_state:compile()

    local release_scene_state = terra(state : &SceneState)
        if state.batches ~= nil then Std.free(state.batches) end
        if state.boxes ~= nil then Std.free(state.boxes) end
        if state.shadows ~= nil then Std.free(state.shadows) end
        if state.text_resources ~= nil then Std.free(state.text_resources) end
        if state.text_draws ~= nil then Std.free(state.text_draws) end
        if state.image_resources ~= nil then Std.free(state.image_resources) end
        if state.image_draws ~= nil then Std.free(state.image_draws) end
        state.batch_capacity = 0
        state.box_capacity = 0
        state.shadow_capacity = 0
        state.text_resource_capacity = 0
        state.text_draw_capacity = 0
        state.image_resource_capacity = 0
        state.image_draw_capacity = 0
        clear_scene_state(state)
    end
    release_scene_state:compile()

    local function ensure_capacity(state, count_field, ptr_field, item_t, count)
        local capacity_field = count_field:gsub("_count$", "_capacity")
        if count <= state[capacity_field] then return state[ptr_field] end

        if state[ptr_field] ~= nil then
            Std.free(state[ptr_field])
            state[ptr_field] = nil
        end

        local n = math.max(1, count)
        state[ptr_field] = terralib.cast(&item_t, Std.malloc(terralib.sizeof(item_t) * n))
        if state[ptr_field] == nil then
            unsupported("UiMachine.Render", "failed to allocate scene buffer")
        end
        state[capacity_field] = n
        return state[ptr_field]
    end

    local function clip_row(batch)
        local rect = batch.clip_rect
        if not rect then return 0, 0, 0, 0, 0 end
        return 1, rect.x, rect.y, rect.w, rect.h
    end

    local function transform_row(batch)
        local xform = batch.transform
        if not xform then return 0, 0,0,0,0,0,0 end
        return 1, xform.m11, xform.m12, xform.m21, xform.m22, xform.tx, xform.ty
    end

    local function install_batches(state, payload)
        local count = #payload.batches
        local ptr = ensure_capacity(state, "batch_count", "batches", BatchState, count)
        F.iter(payload.batches):reduce(function(idx, batch)
            validate_draw_state(batch)
            local clip_enabled, clip_x, clip_y, clip_w, clip_h = clip_row(batch)
            local has_transform, m11, m12, m21, m22, tx, ty = transform_row(batch)
            local kind = batch_kind_info(batch.kind)
            local dst = ptr[idx]
            dst.kind = kind.id
            dst.item_start = batch.item_start
            dst.item_count = batch.item_count
            dst.clip_enabled = clip_enabled
            dst.clip_x = clip_x
            dst.clip_y = clip_y
            dst.clip_w = clip_w
            dst.clip_h = clip_h
            dst.opacity = batch.opacity
            dst.blend_mode = blend_mode_id(batch.blend)
            dst.has_transform = has_transform
            dst.m11 = m11
            dst.m12 = m12
            dst.m21 = m21
            dst.m22 = m22
            dst.tx = tx
            dst.ty = ty
            return idx + 1
        end, 0)
        state.batch_count = count
    end

    local function install_boxes(state, payload)
        local count = #payload.boxes
        local ptr = ensure_capacity(state, "box_count", "boxes", BoxItemState, count)
        F.iter(payload.boxes):reduce(function(idx, item)
            local stroke = item.stroke
            local dst = ptr[idx]
            dst.x = item.rect.x
            dst.y = item.rect.y
            dst.w = item.rect.w
            dst.h = item.rect.h
            dst.fill_r = item.fill.r
            dst.fill_g = item.fill.g
            dst.fill_b = item.fill.b
            dst.fill_a = item.fill.a
            dst.stroke_enabled = stroke and 1 or 0
            dst.stroke_r = stroke and stroke.r or 0
            dst.stroke_g = stroke and stroke.g or 0
            dst.stroke_b = stroke and stroke.b or 0
            dst.stroke_a = stroke and stroke.a or 0
            dst.stroke_width = item.stroke_width
            dst.tl = item.corners.top_left
            dst.tr = item.corners.top_right
            dst.br = item.corners.bottom_right
            dst.bl = item.corners.bottom_left
            return idx + 1
        end, 0)
        state.box_count = count
    end

    local function install_shadows(state, payload)
        local count = #payload.shadows
        local ptr = ensure_capacity(state, "shadow_count", "shadows", ShadowItemState, count)
        F.iter(payload.shadows):reduce(function(idx, item)
            local dst = ptr[idx]
            dst.x = item.rect.x
            dst.y = item.rect.y
            dst.w = item.rect.w
            dst.h = item.rect.h
            dst.r = item.color.r
            dst.g = item.color.g
            dst.b = item.color.b
            dst.a = item.color.a
            dst.blur = math.max(0, item.blur)
            dst.spread = item.spread
            dst.dx = item.dx
            dst.dy = item.dy
            dst.kind = U.match(item.shadow_kind, {
                DropShadow = function() return SHADOW_DROP end,
                InnerShadow = function()
                    unsupported("UiMachine.Render", "inner shadows are not implemented yet")
                end,
            })
            dst.tl = item.corners.top_left
            dst.tr = item.corners.top_right
            dst.br = item.corners.bottom_right
            dst.bl = item.corners.bottom_left
            return idx + 1
        end, 0)
        state.shadow_count = count
    end

    local function materialize_text_resources(text_residency, text_specs, assets, state)
        local count = #text_residency
        local ptr = ensure_capacity(state, "text_resource_count", "text_resources", TextResourceState, count)
        F.iter(text_residency):reduce(function(idx, slot)
            local spec = resource_at(text_specs, slot.request_index, "UiMachine.Render: text request")
            local dst = ptr[idx]
            local key = text_cache_key(spec)
            if dst.cache_key ~= key then
                local font_path = Assets.font_path(assets, spec.font)
                local rendered = Text.rasterize_text(
                    font_path,
                    spec.size_px,
                    spec.text.value,
                    spec.color,
                    spec.wrap.kind,
                    spec.align.kind,
                    spec.width_px
                )
                local texture = (rendered.w > 0 and rendered.h > 0)
                    and SdlGl.ensure_rgba_texture(rendered.cache_key, rendered.w, rendered.h, rendered.pixels, "Linear")
                    or nil
                dst.cache_key = key
                dst.tex_id = texture and texture.id or 0
                dst.w = rendered.w
                dst.h = rendered.h
            end
            return idx + 1
        end, 0)
        state.text_resource_count = count
    end

    local function install_text_draws(state, payload)
        local count = #payload.texts
        local ptr = ensure_capacity(state, "text_draw_count", "text_draws", TextDrawState, count)
        F.iter(payload.texts):reduce(function(idx, item)
            local dst = ptr[idx]
            dst.request_index = item.request_index
            dst.x = item.bounds.x
            dst.y = item.bounds.y
            return idx + 1
        end, 0)
        state.text_draw_count = count
    end

    local function materialize_image_resources(image_residency, image_specs, assets, state)
        local count = #image_residency
        local ptr = ensure_capacity(state, "image_resource_count", "image_resources", ImageResourceState, count)
        F.iter(image_residency):reduce(function(idx, slot)
            local spec = resource_at(image_specs, slot.request_index, "UiMachine.Render: image request")
            local dst = ptr[idx]
            local key = image_cache_key(spec)
            if dst.cache_key ~= key then
                local path = Assets.image_path(assets, spec.image)
                local mode_name = U.match(spec.sampling, {
                    Nearest = function() return "Nearest" end,
                    Linear = function() return "Linear" end,
                })
                local image = ImageData.load_rgba(path)
                local texture = (image.width > 0 and image.height > 0)
                    and SdlGl.ensure_rgba_texture(ImageData.texture_key(path, mode_name), image.width, image.height, image.pixels, mode_name)
                    or nil
                dst.cache_key = key
                dst.tex_id = texture and texture.id or 0
            end
            return idx + 1
        end, 0)
        state.image_resource_count = count
    end

    local function install_image_draws(state, payload)
        local count = #payload.images
        local ptr = ensure_capacity(state, "image_draw_count", "image_draws", ImageDrawState, count)
        F.iter(payload.images):reduce(function(idx, item)
            local dst = ptr[idx]
            dst.request_index = item.request_index
            dst.x = item.rect.x
            dst.y = item.rect.y
            dst.w = item.rect.w
            dst.h = item.rect.h
            dst.opacity = 1.0
            dst.tl = item.corners.top_left
            dst.tr = item.corners.top_right
            dst.br = item.corners.bottom_right
            dst.bl = item.corners.bottom_left
            return idx + 1
        end, 0)
        state.image_draw_count = count
    end

    local function build_scene_runner(target)
        local backend = target.backend
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
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + w - tr) + [q[1]] * tr, (y + tr) + [q[2]] * tr) end
                end end
            else
                C.glVertex2d(x + w, y)
            end
            if br > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + w - br) - [q[2]] * br, (y + h - br) + [q[1]] * br) end
                end end
            else
                C.glVertex2d(x + w, y + h)
            end
            if bl > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + bl) - [q[1]] * bl, (y + h - bl) - [q[2]] * bl) end
                end end
            else
                C.glVertex2d(x, y + h)
            end
            if tl > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + tl) + [q[2]] * tl, (y + tl) - [q[1]] * tl) end
                end end
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
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + w - tr) + [q[1]] * tr, (y + tr) + [q[2]] * tr) end
                end end
            else
                C.glVertex2d(x + w, y)
            end
            if br > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + w - br) - [q[2]] * br, (y + h - br) + [q[1]] * br) end
                end end
            else
                C.glVertex2d(x + w, y + h)
            end
            if bl > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + bl) - [q[1]] * bl, (y + h - bl) - [q[2]] * bl) end
                end end
            else
                C.glVertex2d(x, y + h)
            end
            if tl > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote C.glVertex2d((x + tl) + [q[2]] * tl, (y + tl) - [q[1]] * tl) end
                end end
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
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote
                        C.glTexCoord2d((((x + w - tr) + [q[1]] * tr) - x) / w, (((y + tr) + [q[2]] * tr) - y) / h)
                        C.glVertex2d((x + w - tr) + [q[1]] * tr, (y + tr) + [q[2]] * tr)
                    end
                end end
            else
                C.glTexCoord2d(1.0, 0.0)
                C.glVertex2d(x + w, y)
            end
            if br > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote
                        C.glTexCoord2d((((x + w - br) - [q[2]] * br) - x) / w, (((y + h - br) + [q[1]] * br) - y) / h)
                        C.glVertex2d((x + w - br) - [q[2]] * br, (y + h - br) + [q[1]] * br)
                    end
                end end
            else
                C.glTexCoord2d(1.0, 1.0)
                C.glVertex2d(x + w, y + h)
            end
            if bl > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote
                        C.glTexCoord2d((((x + bl) - [q[1]] * bl) - x) / w, (((y + h - bl) - [q[2]] * bl) - y) / h)
                        C.glVertex2d((x + bl) - [q[1]] * bl, (y + h - bl) - [q[2]] * bl)
                    end
                end end
            else
                C.glTexCoord2d(0.0, 1.0)
                C.glVertex2d(x, y + h)
            end
            if tl > 0 then
                escape for _, q in ipairs(QUARTER_ARC) do
                    emit quote
                        C.glTexCoord2d((((x + tl) + [q[2]] * tl) - x) / w, (((y + tl) - [q[1]] * tl) - y) / h)
                        C.glVertex2d((x + tl) + [q[2]] * tl, (y + tl) - [q[1]] * tl)
                    end
                end end
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
                end
                i = i + 1
            end
        end
        render_shadows:compile()

        local render_text = terra(rt : &Runtime, state : &SceneState, batch : &BatchState)
            C.glEnable(C.GL_TEXTURE_2D)
            var i : int32 = 0
            while i < batch.item_count do
                var item = state.text_draws[batch.item_start + i]
                var res = state.text_resources[item.request_index]
                if res.tex_id ~= 0 then
                    C.glBindTexture(C.GL_TEXTURE_2D, res.tex_id)
                    C.glColor4d(1.0, 1.0, 1.0, rt.opacity)
                    C.glBegin(C.GL_QUADS)
                    C.glTexCoord2d(0.0, 0.0)
                    C.glVertex2d(item.x, item.y)
                    C.glTexCoord2d(1.0, 0.0)
                    C.glVertex2d(item.x + res.w, item.y)
                    C.glTexCoord2d(1.0, 1.0)
                    C.glVertex2d(item.x + res.w, item.y + res.h)
                    C.glTexCoord2d(0.0, 1.0)
                    C.glVertex2d(item.x, item.y + res.h)
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
                var item = state.image_draws[batch.item_start + i]
                var res = state.image_resources[item.request_index]
                if res.tex_id ~= 0 then
                    if item.tl ~= 0 or item.tr ~= 0 or item.br ~= 0 or item.bl ~= 0 then
                        draw_rounded_textured_rt(rt, res.tex_id, item.x, item.y, item.w, item.h, item.tl, item.tr, item.br, item.bl, item.opacity)
                    else
                        C.glBindTexture(C.GL_TEXTURE_2D, res.tex_id)
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
            C.glClearColor(0.08, 0.08, 0.10, 1.0)
            C.glClear(C.GL_COLOR_BUFFER_BIT)

            var bi : int32 = 0
            while bi < state.batch_count do
                var batch = &(state.batches[bi])
                begin_batch(rt, batch)
                if batch.kind == CMD_BOX then
                    render_boxes(rt, state, batch)
                elseif batch.kind == CMD_SHADOW then
                    render_shadows(rt, state, batch)
                elseif batch.kind == CMD_TEXT then
                    render_text(rt, state, batch)
                elseif batch.kind == CMD_IMAGE then
                    render_images(rt, state, batch)
                end
                end_batch(rt, batch)
                bi = bi + 1
            end
        end
        runner:compile()
        return runner
    end

    T.UiMachine.Render.materialize = function(machine, target, assets, state)
        local normalized = normalize_target(target)
        validate_state_schema(machine)
        if state == nil then
            error("UiMachine.Render: materialize requires an allocated Unit state", 3)
        end
        if assets == nil then
            unsupported("UiMachine.Render", "UiAsset.Catalog is required for Layer 1 materialization")
        end

        local payload = machine.param.payload

        install_batches(state, payload)
        install_boxes(state, payload)
        install_shadows(state, payload)
        materialize_text_resources(machine.state.text_residency, payload.text_requests, assets, state)
        install_text_draws(state, payload)
        materialize_image_resources(machine.state.image_residency, payload.image_requests, assets, state)
        install_image_draws(state, payload)

        return {}
    end

    T.UiMachine.RenderGen.compile = U.terminal(function(gen, target)
        local normalized = normalize_target(target)
        validate_shape(gen)
        return stateful_unit(build_scene_runner(normalized), SceneState, init_scene_state, release_scene_state)
    end)
end
