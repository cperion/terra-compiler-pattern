local asdl = require("asdl")
local U = require("unit")
local F = require("fun")

local L = asdl.List

-- ============================================================================
-- UiRenderMachineIR.Render -> define_machine -> UiMachine.Render
-- ----------------------------------------------------------------------------
-- ui3 Layer 1: explicit gen / param / state machine above raw Unit.
--
-- Current mapping after the Layer-1 audit:
--   gen   = UiRenderMachineIR.Shape
--   param = packed install-ready payload + realization requests
--   state = UiRenderMachineIR.StateSchema
--
-- The key change is that define_machine now performs real packing work so
-- materialize() no longer has to re-lower broad machine IR on every call.
-- ============================================================================

local function unsupported(context, detail)
    error(("%s: %s"):format(context, detail), 3)
end

local function reject_any(xs, context, detail)
    F.iter(xs):each(function(_)
        unsupported(context, detail)
    end)
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

local function resource_at(xs, ref, context)
    local slot = ref and (ref.slot or ref.index or ref.value)
    if slot == nil then
        unsupported(context, "resource ref is required")
    end
    local value = xs[slot + 1]
    if value == nil then
        unsupported(context, "resource ref out of range")
    end
    return value, slot
end

local function intersect_rects(a, b)
    local x1 = math.max(a.x, b.x)
    local y1 = math.max(a.y, b.y)
    local x2 = math.min(a.x + a.w, b.x + b.w)
    local y2 = math.min(a.y + a.h, b.y + b.h)
    return {
        x = x1,
        y = y1,
        w = math.max(0, x2 - x1),
        h = math.max(0, y2 - y1),
    }
end

local function clip_shape_rect(shape)
    return U.match(shape, {
        ClipRect = function(v)
            return v.rect
        end,
        ClipRoundedRect = function(_)
            unsupported("UiRenderMachineIR.Render:define_machine", "rounded clip shapes are not implemented yet")
        end,
    })
end

local function clip_rect_for(input, clip_ref)
    if clip_ref == nil then return nil end
    local path = resource_at(input.clips, clip_ref, "UiRenderMachineIR.Render:define_machine clip")
    return F.iter(path.shapes)
        :map(clip_shape_rect)
        :reduce(function(acc, rect)
            return acc and intersect_rects(acc, rect) or rect
        end, nil)
end

local function batch_param_for(T, input, batch)
    return T.UiMachine.BatchParam(
        batch.kind,
        batch.item_start,
        batch.item_count,
        clip_rect_for(input, batch.state.clip),
        batch.state.opacity,
        batch.state.blend,
        batch.state.transform
    )
end

local function box_param_for(T, item)
    return T.UiMachine.BoxParam(
        item.rect,
        solid_color(item.fill, "UiRenderMachineIR.Render:define_machine box fill"),
        item.stroke and solid_color(item.stroke, "UiRenderMachineIR.Render:define_machine box stroke") or nil,
        item.stroke_width,
        item.align,
        item.corners
    )
end

local function shadow_param_for(T, item)
    return T.UiMachine.ShadowParam(
        item.rect,
        solid_color(item.brush, "UiRenderMachineIR.Render:define_machine shadow brush"),
        item.blur,
        item.spread,
        item.dx,
        item.dy,
        item.shadow_kind,
        item.corners
    )
end

local function text_request_for(T, spec)
    return T.UiMachine.TextRequest(
        spec.key,
        spec.text,
        spec.font,
        spec.size_px,
        spec.weight,
        spec.slant,
        spec.letter_spacing_px,
        spec.line_height_px,
        spec.color,
        spec.wrap,
        spec.overflow,
        spec.align,
        spec.line_limit,
        spec.width_px
    )
end

local function text_draw_for(T, input, item)
    local _, slot = resource_at(input.text_resources, item.resource, "UiRenderMachineIR.Render:define_machine text resource")
    return T.UiMachine.TextDraw(slot, item.bounds)
end

local function image_request_for(T, spec)
    return T.UiMachine.ImageRequest(
        spec.key,
        spec.image,
        spec.sampling
    )
end

local function image_draw_for(T, input, item)
    local _, slot = resource_at(input.image_resources, item.resource, "UiRenderMachineIR.Render:define_machine image resource")
    return T.UiMachine.ImageDraw(slot, item.rect, item.fit, item.corners)
end

local function packed_input_for(T, input)
    reject_any(input.custom_resources,
        "UiRenderMachineIR.Render:define_machine",
        "custom resources are not implemented yet")
    reject_any(input.customs,
        "UiRenderMachineIR.Render:define_machine",
        "custom instances are not implemented yet")

    return T.UiMachine.PackedInput(
        input.regions,
        L(F.iter(input.batches):map(function(batch)
            return batch_param_for(T, input, batch)
        end):totable()),
        L(F.iter(input.boxes):map(function(item)
            return box_param_for(T, item)
        end):totable()),
        L(F.iter(input.shadows):map(function(item)
            return shadow_param_for(T, item)
        end):totable()),
        L(F.iter(input.text_resources):map(function(spec)
            return text_request_for(T, spec)
        end):totable()),
        L(F.iter(input.texts):map(function(item)
            return text_draw_for(T, input, item)
        end):totable()),
        L(F.iter(input.image_resources):map(function(spec)
            return image_request_for(T, spec)
        end):totable()),
        L(F.iter(input.images):map(function(item)
            return image_draw_for(T, input, item)
        end):totable())
    )
end

local function render_state_for(T, render)
    local input = render.input
    return T.UiMachine.RenderState(
        render.state_schema,
        L(F.iter(input.text_resources):reduce(function(rows, spec)
            local idx = #rows
            rows[idx + 1] = T.UiMachine.TextResidency(idx, spec.key)
            return rows
        end, {})),
        L(F.iter(input.image_resources):reduce(function(rows, spec)
            local idx = #rows
            rows[idx + 1] = T.UiMachine.ImageResidency(idx, spec.key)
            return rows
        end, {}))
    )
end

return function(T)
    T.UiRenderMachineIR.Render.define_machine = U.transition(function(render)
        return T.UiMachine.Render(
            T.UiMachine.RenderGen(render.shape),
            T.UiMachine.RenderParam(packed_input_for(T, render.input)),
            render_state_for(T, render)
        )
    end)
end
