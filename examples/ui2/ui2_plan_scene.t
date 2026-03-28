local U = require("unit")
local F = require("fun")

local function L(xs)
    return terralib.newlist(xs or {})
end

-- ============================================================================
-- UiPlan.Scene -> specialize_kernel -> UiKernel.Render
-- ----------------------------------------------------------------------------
-- This file implements the sixth ui2 compiler boundary.
--
-- Boundary meaning:
--   packed render/query plan -> render-only machine phase
--
-- What specialize_kernel consumes:
--   - UiPlan's scene-global render plane
--   - UiPlan's render/query split
--   - UiPlan batch variants with nested item lists
--
-- What specialize_kernel produces:
--   - UiKernel.Spec with only machine-shape facts
--   - UiKernel.Payload with render-only region headers, batch headers, and
--     family-specific global item arrays
--
-- What specialize_kernel intentionally does NOT do:
--   - no backend-native struct/buffer creation
--   - no code generation
--   - no query-plane routing payload
--
-- Core narrowing performed here:
--   - drops UiPlan query planes entirely
--   - converts nested batch variants into header + item-span layout
--   - keeps text payload as whole text items for SDL_ttf-style materialization
--   - preserves custom render families structurally and reflects them into Spec
--
-- Functional-style note:
--   As with the other pure boundaries, this file keeps the work in a LuaFun-
--   shaped style: map/filter/reduce plus small structural helpers. Accumulator
--   mutation is limited to the local reducer state used to build the packed
--   payload arrays.
-- ============================================================================

local function append_all(dst, src)
    F.iter(src):each(function(v)
        dst[#dst + 1] = v
    end)
    return dst
end

local function flat_collect(xs, fn)
    return F.iter(xs):reduce(function(acc, x)
        return append_all(acc, fn(x))
    end, {})
end

local function kernel_region_for(T, region)
    return T.UiKernel.Region(region.draw_start, region.draw_count)
end

local function kernel_box_item(T, item)
    return T.UiKernel.BoxItem(
        item.rect,
        item.fill,
        item.stroke,
        item.stroke_width,
        item.align,
        item.corners
    )
end

local function kernel_shadow_item(T, item)
    return T.UiKernel.ShadowItem(
        item.rect,
        item.brush,
        item.blur,
        item.spread,
        item.dx,
        item.dy,
        item.shadow_kind,
        item.corners
    )
end

local function kernel_image_item(T, item)
    return T.UiKernel.ImageItem(
        item.image,
        item.rect,
        item.sampling,
        item.corners
    )
end

local function kernel_custom_item(T, item)
    return T.UiKernel.CustomItem(item.payload)
end

local function append_text_runs(T, acc, runs)
    local start = #acc.text_runs + 1

    append_all(acc.text_runs, F.iter(runs):map(function(run)
        return T.UiKernel.TextRun(
            run.text,
            run.font,
            run.size_px,
            run.color,
            run.bounds,
            run.wrap,
            run.align
        )
    end):totable())

    return start, #runs
end

local function append_box_items(T, acc, items)
    local start = #acc.boxes + 1
    append_all(acc.boxes, F.iter(items):map(function(item)
        return kernel_box_item(T, item)
    end):totable())
    return start, #items
end

local function append_shadow_items(T, acc, items)
    local start = #acc.shadows + 1
    append_all(acc.shadows, F.iter(items):map(function(item)
        return kernel_shadow_item(T, item)
    end):totable())
    return start, #items
end

local function append_image_items(T, acc, items)
    local start = #acc.images + 1
    append_all(acc.images, F.iter(items):map(function(item)
        return kernel_image_item(T, item)
    end):totable())
    return start, #items
end

local function append_custom_items(T, acc, items)
    local start = #acc.customs + 1
    append_all(acc.customs, F.iter(items):map(function(item)
        return kernel_custom_item(T, item)
    end):totable())
    return start, #items
end

local function kernel_batch_from_plan(T, acc, batch)
    return U.match(batch, {
        BoxBatch = function(v)
            local item_start, item_count = append_box_items(T, acc, v.items)
            return T.UiKernel.Batch(
                T.UiKernel.BoxKind(),
                v.state,
                item_start,
                item_count
            )
        end,
        ShadowBatch = function(v)
            local item_start, item_count = append_shadow_items(T, acc, v.items)
            return T.UiKernel.Batch(
                T.UiKernel.ShadowKind(),
                v.state,
                item_start,
                item_count
            )
        end,
        TextBatch = function(v)
            local item_start, item_count = append_text_runs(T, acc, v.runs)
            return T.UiKernel.Batch(
                T.UiKernel.TextKind(),
                v.state,
                item_start,
                item_count
            )
        end,
        ImageBatch = function(v)
            local item_start, item_count = append_image_items(T, acc, v.items)
            return T.UiKernel.Batch(
                T.UiKernel.ImageKind(),
                v.state,
                item_start,
                item_count
            )
        end,
        CustomBatch = function(v)
            local item_start, item_count = append_custom_items(T, acc, v.items)
            return T.UiKernel.Batch(
                T.UiKernel.CustomKind(v.family),
                v.state,
                item_start,
                item_count
            )
        end,
    })
end

local function custom_family_spec(T, draws)
    local seen = {}
    local kinds = F.iter(draws)
        :reduce(function(acc, batch)
            return U.match(batch, {
                BoxBatch = function() return acc end,
                ShadowBatch = function() return acc end,
                TextBatch = function() return acc end,
                ImageBatch = function() return acc end,
                CustomBatch = function(v)
                    if not seen[v.family] then
                        seen[v.family] = true
                        acc[#acc + 1] = v.family
                    end
                    return acc
                end,
            })
        end, {})

    table.sort(kinds)

    return F.iter(kinds):map(function(family)
        return T.UiKernel.CustomFamily(family)
    end):totable()
end

return function(T)
    -- ---------------------------------------------------------------------
    -- Public boundary:
    --   UiPlan.Scene:specialize_kernel() -> UiKernel.Render
    -- ---------------------------------------------------------------------
    -- No side inputs are required here. UiPlan already contains the fully
    -- packed render plane, and kernel specialization is now just a render-only
    -- structural projection plus the final Spec/Payload split.
    T.UiPlan.Scene.specialize_kernel = U.transition(function(scene)
        local payload_acc = {
            batches = {},
            boxes = {},
            shadows = {},
            text_runs = {},
            images = {},
            customs = {},
        }

        payload_acc.batches = F.iter(scene.draws):map(function(batch)
            return kernel_batch_from_plan(T, payload_acc, batch)
        end):totable()

        return T.UiKernel.Render(
            T.UiKernel.Spec(L(custom_family_spec(T, scene.draws))),
            T.UiKernel.Payload(
                L(F.iter(scene.regions):map(function(region)
                    return kernel_region_for(T, region)
                end):totable()),
                scene.clips,
                L(payload_acc.batches),
                L(payload_acc.boxes),
                L(payload_acc.shadows),
                L(payload_acc.text_runs),
                L(payload_acc.images),
                L(payload_acc.customs)
            )
        )
    end)
end
