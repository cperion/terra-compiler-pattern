local asdl = require("asdl")
local U = require("unit")
local F = require("fun")
local bit = require("bit")
local ffi = require("ffi")

local L = asdl.List

-- ============================================================================
-- UiRenderScene.Scene -> schedule_render_machine_ir -> UiRenderMachineIR.Render
-- ----------------------------------------------------------------------------
-- ui3 Layer 2: schedule a concrete render occurrence scene into machine IR.
--
-- What this boundary consumes:
--   - concrete render occurrences in final region/occurrence order
--   - occurrence-local draw state
--   - occurrence-local text/image/custom use-sites
--
-- What this boundary produces:
--   - region batch spans
--   - deduped clip/resource tables
--   - adjacent compatible batch headers
--   - family-specific instance arrays
--   - runtime state-family requirements
--
-- What this boundary intentionally does NOT do:
--   - no occurrence discovery from node facts
--   - no geometry solving
--   - no machine realization / compile
-- ============================================================================

local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619
local UINT32_MOD = 4294967296
local NUMBER_BUF = ffi.new("double[1]", 0)
local NUMBER_BYTES = ffi.cast("unsigned char *", NUMBER_BUF)

local function hash_byte(hash, byte)
    return bit.tobit((bit.bxor(hash, byte) * FNV_PRIME) % UINT32_MOD)
end

local function hash_string(hash, s)
    for i = 1, #s do
        hash = hash_byte(hash, s:byte(i))
    end
    return hash
end

local function hash_nil(hash)
    return hash_string(hash, "<nil>")
end

local function hash_number(hash, n)
    NUMBER_BUF[0] = n or 0
    for i = 0, 7 do
        hash = hash_byte(hash, NUMBER_BYTES[i])
    end
    return hash
end

local function hash_kind(hash, kind)
    return kind and hash_string(hash, kind) or hash_nil(hash)
end

local function finalize_hash(hash)
    if hash < 0 then hash = hash + UINT32_MOD end
    return hash
end

local function unsupported(context, detail)
    error(("%s: %s"):format(context, detail), 3)
end

local function Ls(xs)
    return L(xs or {})
end

local function hash_rect(hash, r)
    hash = hash_number(hash, r.x)
    hash = hash_number(hash, r.y)
    hash = hash_number(hash, r.w)
    hash = hash_number(hash, r.h)
    return hash
end

local function hash_corners(hash, c)
    hash = hash_number(hash, c.top_left)
    hash = hash_number(hash, c.top_right)
    hash = hash_number(hash, c.bottom_right)
    hash = hash_number(hash, c.bottom_left)
    return hash
end

local function hash_transform(hash, xform)
    if not xform then
        return hash_nil(hash)
    end
    hash = hash_number(hash, xform.m11)
    hash = hash_number(hash, xform.m12)
    hash = hash_number(hash, xform.m21)
    hash = hash_number(hash, xform.m22)
    hash = hash_number(hash, xform.tx)
    hash = hash_number(hash, xform.ty)
    return hash
end

local function rect_equals(a, b)
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function corners_equals(a, b)
    return a.top_left == b.top_left
       and a.top_right == b.top_right
       and a.bottom_right == b.bottom_right
       and a.bottom_left == b.bottom_left
end

local function transform_equals(a, b)
    if a == nil or b == nil then return a == b end
    return a.m11 == b.m11 and a.m12 == b.m12
       and a.m21 == b.m21 and a.m22 == b.m22
       and a.tx == b.tx and a.ty == b.ty
end

local function clip_shape_hash(hash, shape)
    return U.match(shape, {
        ClipRect = function(v)
            hash = hash_string(hash, "rect")
            return hash_rect(hash, v.rect)
        end,
        ClipRoundedRect = function(v)
            hash = hash_string(hash, "round")
            hash = hash_rect(hash, v.rect)
            return hash_corners(hash, v.corners)
        end,
    })
end

local function clip_shape_equals(a, b)
    if a.kind ~= b.kind then return false end
    return U.match(a, {
        ClipRect = function(av)
            return rect_equals(av.rect, b.rect)
        end,
        ClipRoundedRect = function(av)
            return rect_equals(av.rect, b.rect) and corners_equals(av.corners, b.corners)
        end,
    })
end

local function clip_path_equals(a, clips)
    local shapes = a.shapes or a
    if #shapes ~= #clips then return false end
    local i = 1
    while i <= #clips do
        if not clip_shape_equals(shapes[i], clips[i]) then return false end
        i = i + 1
    end
    return true
end

local function clip_list_equals(a, b)
    local an = a and #a or 0
    local bn = b and #b or 0
    if an ~= bn then return false end
    if an == 0 then return true end
    return clip_path_equals(a, b)
end

local function clip_path_hash(clips)
    if clips == nil or #clips == 0 then return 0 end
    return finalize_hash(F.iter(clips):reduce(function(hash, shape)
        return clip_shape_hash(hash, shape)
    end, FNV_OFFSET))
end

local function clip_ref_for(T, acc, clips)
    if clips == nil or #clips == 0 then return nil end

    local key = clip_path_hash(clips)
    local bucket = acc.clip_slots[key]
    if bucket ~= nil then
        local i = 1
        while i <= #bucket do
            local slot = bucket[i]
            if clip_path_equals(acc.clips[slot + 1], clips) then
                return T.UiRenderMachineIR.ClipRef(slot)
            end
            i = i + 1
        end
    end

    local slot = #acc.clips
    acc.clips[#acc.clips + 1] = T.UiRenderMachineIR.ClipPath(clips)
    acc.clip_slots[key] = bucket or {}
    acc.clip_slots[key][#acc.clip_slots[key] + 1] = slot
    return T.UiRenderMachineIR.ClipRef(slot)
end

local function draw_state_hash(clip_ref, blend, opacity, transform)
    local hash = FNV_OFFSET
    hash = clip_ref and hash_number(hash, clip_ref.index) or hash_nil(hash)
    hash = hash_kind(hash, blend and blend.kind or nil)
    hash = hash_number(hash, opacity)
    hash = hash_transform(hash, transform)
    return finalize_hash(hash)
end

local function draw_state_equals(a, b)
    return (a.clip and a.clip.index or nil) == (b.clip and b.clip.index or nil)
       and a.blend.kind == b.blend.kind
       and a.opacity == b.opacity
       and transform_equals(a.transform, b.transform)
end

local function source_state_equals(a, b)
    if a == nil or b == nil then return a == b end
    return clip_list_equals(a.clips, b.clips)
       and a.blend.kind == b.blend.kind
       and a.opacity == b.opacity
       and transform_equals(a.transform, b.transform)
end

local function draw_state_for(T, acc, state)
    local clip = clip_ref_for(T, acc, state.clips)
    return T.UiRenderMachineIR.DrawState(
        clip,
        state.blend,
        state.opacity,
        state.transform
    ), draw_state_hash(clip, state.blend, state.opacity, state.transform)
end

local function text_resource_key(text, bounds)
    local hash = FNV_OFFSET
    hash = hash_string(hash, text.text and text.text.value or "")
    hash = hash_number(hash, text.font and text.font.value or 0)
    hash = hash_number(hash, text.size_px)
    hash = hash_kind(hash, text.weight and text.weight.kind or nil)
    hash = hash_kind(hash, text.slant and text.slant.kind or nil)
    hash = hash_number(hash, text.letter_spacing_px)
    hash = hash_number(hash, text.line_height_px)
    hash = hash_number(hash, text.color.r)
    hash = hash_number(hash, text.color.g)
    hash = hash_number(hash, text.color.b)
    hash = hash_number(hash, text.color.a)
    hash = hash_kind(hash, text.wrap and text.wrap.kind or nil)
    hash = hash_kind(hash, text.overflow and text.overflow.kind or nil)
    hash = hash_kind(hash, text.align and text.align.kind or nil)
    hash = hash_number(hash, text.line_limit)
    hash = hash_number(hash, bounds.w)
    return finalize_hash(hash)
end

local function text_resource_equals(spec, text, bounds)
    return spec.text.value == text.text.value
       and spec.font.value == text.font.value
       and spec.size_px == text.size_px
       and spec.weight.kind == text.weight.kind
       and spec.slant.kind == text.slant.kind
       and spec.letter_spacing_px == text.letter_spacing_px
       and spec.line_height_px == text.line_height_px
       and spec.color.r == text.color.r
       and spec.color.g == text.color.g
       and spec.color.b == text.color.b
       and spec.color.a == text.color.a
       and spec.wrap.kind == text.wrap.kind
       and spec.overflow.kind == text.overflow.kind
       and spec.align.kind == text.align.kind
       and spec.line_limit == text.line_limit
       and spec.width_px == bounds.w
end

local function image_resource_key(image)
    local hash = FNV_OFFSET
    hash = hash_number(hash, image.image and image.image.value or 0)
    hash = hash_kind(hash, image.sampling and image.sampling.kind or nil)
    return finalize_hash(hash)
end

local function image_resource_equals(spec, image)
    return spec.image.value == image.image.value
       and spec.sampling.kind == image.sampling.kind
end

local function custom_resource_key(family, payload)
    local hash = FNV_OFFSET
    hash = hash_number(hash, family)
    hash = hash_number(hash, payload)
    return finalize_hash(hash)
end

local function text_resource_ref_for(T, acc, text, bounds)
    local key = text_resource_key(text, bounds)
    local bucket = acc.text_resource_slots[key]
    if bucket ~= nil then
        local i = 1
        while i <= #bucket do
            local slot = bucket[i]
            if text_resource_equals(acc.text_resources[slot + 1], text, bounds) then
                return T.UiRenderMachineIR.TextResourceRef(slot)
            end
            i = i + 1
        end
    end

    local slot = #acc.text_resources
    acc.text_resources[#acc.text_resources + 1] = T.UiRenderMachineIR.TextResourceSpec(
        key,
        text.text,
        text.font,
        text.size_px,
        text.weight,
        text.slant,
        text.letter_spacing_px,
        text.line_height_px,
        text.color,
        text.wrap,
        text.overflow,
        text.align,
        text.line_limit,
        bounds.w
    )
    acc.text_resource_slots[key] = bucket or {}
    acc.text_resource_slots[key][#acc.text_resource_slots[key] + 1] = slot
    return T.UiRenderMachineIR.TextResourceRef(slot)
end

local function image_resource_ref_for(T, acc, image)
    local key = image_resource_key(image)
    local bucket = acc.image_resource_slots[key]
    if bucket ~= nil then
        local i = 1
        while i <= #bucket do
            local slot = bucket[i]
            if image_resource_equals(acc.image_resources[slot + 1], image) then
                return T.UiRenderMachineIR.ImageResourceRef(slot)
            end
            i = i + 1
        end
    end

    local slot = #acc.image_resources
    acc.image_resources[#acc.image_resources + 1] = T.UiRenderMachineIR.ImageResourceSpec(
        key,
        image.image,
        image.sampling
    )
    acc.image_resource_slots[key] = bucket or {}
    acc.image_resource_slots[key][#acc.image_resource_slots[key] + 1] = slot
    return T.UiRenderMachineIR.ImageResourceRef(slot)
end

local function custom_resource_ref_for(T, acc, family, payload)
    local key = custom_resource_key(family, payload)
    local bucket = acc.custom_resource_slots[key]
    if bucket ~= nil then
        local i = 1
        while i <= #bucket do
            local slot = bucket[i]
            local spec = acc.custom_resources[slot + 1]
            if spec.family == family and spec.payload == payload then
                return T.UiRenderMachineIR.CustomResourceRef(slot)
            end
            i = i + 1
        end
    end

    local slot = #acc.custom_resources
    acc.custom_resources[#acc.custom_resources + 1] = T.UiRenderMachineIR.CustomResourceSpec(family, payload)
    acc.custom_resource_slots[key] = bucket or {}
    acc.custom_resource_slots[key][#acc.custom_resource_slots[key] + 1] = slot
    if not acc.custom_state_seen[family] then
        acc.custom_state_seen[family] = true
        acc.custom_state_families[#acc.custom_state_families + 1] = family
    end
    return T.UiRenderMachineIR.CustomResourceRef(slot)
end

local function note_custom_family(acc, family)
    if not acc.custom_family_seen[family] then
        acc.custom_family_seen[family] = true
        acc.custom_families[#acc.custom_families + 1] = family
    end
    return acc
end

local function batch_kind_hash(kind)
    return finalize_hash(U.match(kind, {
        BoxKind = function()
            return hash_string(FNV_OFFSET, "BoxKind")
        end,
        ShadowKind = function()
            return hash_string(FNV_OFFSET, "ShadowKind")
        end,
        TextKind = function()
            return hash_string(FNV_OFFSET, "TextKind")
        end,
        ImageKind = function()
            return hash_string(FNV_OFFSET, "ImageKind")
        end,
        CustomKind = function(v)
            return hash_number(hash_string(FNV_OFFSET, "CustomKind"), v.family)
        end,
    }))
end

local function batch_kind_equals(a, b)
    if a.kind ~= b.kind then return false end
    return U.match(a, {
        BoxKind = function() return true end,
        ShadowKind = function() return true end,
        TextKind = function() return true end,
        ImageKind = function() return true end,
        CustomKind = function(v)
            return v.family == b.family
        end,
    })
end

local function flush_open_batch(T, acc, region_acc)
    if region_acc.open_kind == nil then return region_acc end
    acc.batches[#acc.batches + 1] = T.UiRenderMachineIR.BatchHeader(
        region_acc.open_kind,
        region_acc.open_state,
        region_acc.open_item_start,
        region_acc.open_item_count
    )
    region_acc.batch_count = region_acc.batch_count + 1
    region_acc.open_kind = nil
    region_acc.open_kind_hash = nil
    region_acc.open_state = nil
    region_acc.open_state_hash = nil
    region_acc.open_source_state = nil
    region_acc.open_item_start = nil
    region_acc.open_item_count = 0
    return region_acc
end

local function try_extend_open_batch(region_acc, kind, source_state)
    if region_acc.open_kind == nil then return false end
    if region_acc.open_kind ~= kind then return false end
    if not source_state_equals(region_acc.open_source_state, source_state) then return false end
    region_acc.open_item_count = region_acc.open_item_count + 1
    return true
end

local function push_open_batch(T, acc, region_acc, kind, kind_hash, state, state_hash, source_state, item_start)
    if region_acc.open_kind ~= nil
        and region_acc.open_kind_hash == kind_hash
        and region_acc.open_state_hash == state_hash
        and batch_kind_equals(region_acc.open_kind, kind)
        and draw_state_equals(region_acc.open_state, state) then
        region_acc.open_item_count = region_acc.open_item_count + 1
        return region_acc
    end

    flush_open_batch(T, acc, region_acc)
    region_acc.open_kind = kind
    region_acc.open_kind_hash = kind_hash
    region_acc.open_state = state
    region_acc.open_state_hash = state_hash
    region_acc.open_source_state = source_state
    region_acc.open_item_start = item_start
    region_acc.open_item_count = 1
    return region_acc
end

local function emit_occurrence(T, acc, region_acc, occurrence)
    return U.match(occurrence, {
        Box = function(v)
            local box = v.box
            local item_start = #acc.boxes
            acc.boxes[#acc.boxes + 1] = T.UiRenderMachineIR.BoxInstance(
                box.rect,
                box.fill,
                box.stroke,
                box.stroke_width,
                box.align,
                box.corners
            )
            if try_extend_open_batch(region_acc, acc.box_kind, box.state) then
                return acc, region_acc
            end
            local state, state_hash = draw_state_for(T, acc, box.state)
            push_open_batch(T, acc, region_acc, acc.box_kind, acc.box_kind_hash, state, state_hash, box.state, item_start)
            return acc, region_acc
        end,
        Shadow = function(v)
            local shadow = v.shadow
            local item_start = #acc.shadows
            acc.shadows[#acc.shadows + 1] = T.UiRenderMachineIR.ShadowInstance(
                shadow.rect,
                shadow.brush,
                shadow.blur,
                shadow.spread,
                shadow.dx,
                shadow.dy,
                shadow.shadow_kind,
                shadow.corners
            )
            if try_extend_open_batch(region_acc, acc.shadow_kind, shadow.state) then
                return acc, region_acc
            end
            local state, state_hash = draw_state_for(T, acc, shadow.state)
            push_open_batch(T, acc, region_acc, acc.shadow_kind, acc.shadow_kind_hash, state, state_hash, shadow.state, item_start)
            return acc, region_acc
        end,
        Text = function(v)
            local text = v.text
            local item_start = #acc.texts
            acc.texts[#acc.texts + 1] = T.UiRenderMachineIR.TextDrawInstance(
                text_resource_ref_for(T, acc, text.text, text.bounds),
                text.bounds
            )
            if try_extend_open_batch(region_acc, acc.text_kind, text.state) then
                return acc, region_acc
            end
            local state, state_hash = draw_state_for(T, acc, text.state)
            push_open_batch(T, acc, region_acc, acc.text_kind, acc.text_kind_hash, state, state_hash, text.state, item_start)
            return acc, region_acc
        end,
        Image = function(v)
            local image = v.image
            local item_start = #acc.images
            acc.images[#acc.images + 1] = T.UiRenderMachineIR.ImageDrawInstance(
                image_resource_ref_for(T, acc, image.image),
                image.rect,
                image.image.fit,
                image.corners
            )
            if try_extend_open_batch(region_acc, acc.image_kind, image.state) then
                return acc, region_acc
            end
            local state, state_hash = draw_state_for(T, acc, image.state)
            push_open_batch(T, acc, region_acc, acc.image_kind, acc.image_kind_hash, state, state_hash, image.state, item_start)
            return acc, region_acc
        end,
        Custom = function(v)
            return U.match(v.custom, {
                InlineCustom = function(cv)
                    note_custom_family(acc, cv.family)
                    local kind = acc.custom_kinds[cv.family]
                    local kind_hash = acc.custom_kind_hashes[cv.family]
                    if kind == nil then
                        kind = T.UiRenderMachineIR.CustomKind(cv.family)
                        kind_hash = batch_kind_hash(kind)
                        acc.custom_kinds[cv.family] = kind
                        acc.custom_kind_hashes[cv.family] = kind_hash
                    end
                    local item_start = #acc.customs
                    acc.customs[#acc.customs + 1] = T.UiRenderMachineIR.InlineCustom(
                        cv.family,
                        cv.payload
                    )
                    if try_extend_open_batch(region_acc, kind, cv.state) then
                        return acc, region_acc
                    end
                    local state, state_hash = draw_state_for(T, acc, cv.state)
                    push_open_batch(T, acc, region_acc, kind, kind_hash, state, state_hash, cv.state, item_start)
                    return acc, region_acc
                end,
                ResourceCustom = function(cv)
                    note_custom_family(acc, cv.family)
                    local kind = acc.custom_kinds[cv.family]
                    local kind_hash = acc.custom_kind_hashes[cv.family]
                    if kind == nil then
                        kind = T.UiRenderMachineIR.CustomKind(cv.family)
                        kind_hash = batch_kind_hash(kind)
                        acc.custom_kinds[cv.family] = kind
                        acc.custom_kind_hashes[cv.family] = kind_hash
                    end
                    local item_start = #acc.customs
                    acc.customs[#acc.customs + 1] = T.UiRenderMachineIR.ResourceCustom(
                        cv.family,
                        custom_resource_ref_for(T, acc, cv.family, cv.resource_payload),
                        cv.instance_payload
                    )
                    if try_extend_open_batch(region_acc, kind, cv.state) then
                        return acc, region_acc
                    end
                    local state, state_hash = draw_state_for(T, acc, cv.state)
                    push_open_batch(T, acc, region_acc, kind, kind_hash, state, state_hash, cv.state, item_start)
                    return acc, region_acc
                end,
            })
        end,
    })
end

local function render_shape_for(T, acc)
    table.sort(acc.custom_families)
    return T.UiRenderMachineIR.Shape(Ls(F.iter(acc.custom_families):map(function(family)
        return T.UiRenderMachineIR.CustomFamily(family)
    end):totable()))
end

local function state_schema_for(T, acc)
    table.sort(acc.custom_state_families)

    local resources = {}
    if #acc.text_resources > 0 then
        resources[#resources + 1] = T.UiRenderMachineIR.TextResources()
    end
    if #acc.image_resources > 0 then
        resources[#resources + 1] = T.UiRenderMachineIR.ImageResources()
    end

    local custom = F.iter(acc.custom_state_families):map(function(family)
        return T.UiRenderMachineIR.CustomStateFamily(family)
    end):totable()

    return T.UiRenderMachineIR.StateSchema(
        Ls(resources),
        Ls(custom),
        T.UiRenderMachineIR.CapacityTracking()
    )
end

local function schedule_scene(T, scene)
    local box_kind = T.UiRenderMachineIR.BoxKind()
    local shadow_kind = T.UiRenderMachineIR.ShadowKind()
    local text_kind = T.UiRenderMachineIR.TextKind()
    local image_kind = T.UiRenderMachineIR.ImageKind()

    local acc = {
        clip_slots = {},
        clips = {},
        text_resource_slots = {},
        text_resources = {},
        image_resource_slots = {},
        image_resources = {},
        custom_resource_slots = {},
        custom_resources = {},
        custom_family_seen = {},
        custom_families = {},
        custom_state_seen = {},
        custom_state_families = {},
        custom_kinds = {},
        custom_kind_hashes = {},
        box_kind = box_kind,
        box_kind_hash = batch_kind_hash(box_kind),
        shadow_kind = shadow_kind,
        shadow_kind_hash = batch_kind_hash(shadow_kind),
        text_kind = text_kind,
        text_kind_hash = batch_kind_hash(text_kind),
        image_kind = image_kind,
        image_kind_hash = batch_kind_hash(image_kind),
        boxes = {},
        shadows = {},
        texts = {},
        images = {},
        customs = {},
        batches = {},
        regions = {},
    }

    F.iter(scene.regions):each(function(region)
        local batch_start = #acc.batches
        local region_acc = {
            batch_count = 0,
            open_kind = nil,
            open_kind_hash = nil,
            open_state = nil,
            open_state_hash = nil,
            open_source_state = nil,
            open_item_start = nil,
            open_item_count = 0,
        }
        local start = region.occurrence_start or 0
        local count = region.occurrence_count or 0
        local i = 0
        while i < count do
            emit_occurrence(T, acc, region_acc, scene.occurrences[start + i + 1])
            i = i + 1
        end
        flush_open_batch(T, acc, region_acc)
        acc.regions[#acc.regions + 1] = T.UiRenderMachineIR.RegionSpan(batch_start, region_acc.batch_count)
    end)

    return T.UiRenderMachineIR.Render(
        render_shape_for(T, acc),
        T.UiRenderMachineIR.Input(
            Ls(acc.regions),
            Ls(acc.clips),
            Ls(acc.batches),
            Ls(acc.text_resources),
            Ls(acc.image_resources),
            Ls(acc.custom_resources),
            Ls(acc.boxes),
            Ls(acc.shadows),
            Ls(acc.texts),
            Ls(acc.images),
            Ls(acc.customs)
        ),
        state_schema_for(T, acc)
    )
end

return function(T)
    T.UiRenderScene.Scene.schedule_render_machine_ir = U.transition(function(scene)
        return schedule_scene(T, scene)
    end)
end
