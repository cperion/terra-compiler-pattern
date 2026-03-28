local U = require("unit")
local F = require("fun")

local function L(xs)
    return terralib.newlist(xs or {})
end

-- ============================================================================
-- UiSolved.Scene -> plan -> UiPlan.Scene
-- ----------------------------------------------------------------------------
-- This file implements the fifth ui2 compiler boundary.
--
-- Boundary meaning:
--   solved node-centered scene -> packed render/query planes
--
-- What plan consumes:
--   - region-local solved nodes with explicit topology
--   - solved geometry
--   - solved draw atoms with self-contained visual state
--   - solved behavior facts
--   - solved accessibility facts
--
-- What plan produces:
--   - scene-global deduplicated clip table
--   - scene-global draw batch stream grouped by compatible adjacent atoms
--   - scene-global query planes for hit/focus/key/scroll/edit/accessibility
--   - one UiPlan.Region span header per solved region
--
-- What plan intentionally does NOT do:
--   - no geometry solving
--   - no backend specialization
--   - no native state materialization
--
-- Core planning policy:
--   - preserves region order exactly
--   - preserves within-region solved draw/query order semantics
--   - may coalesce only adjacent compatible draw atoms
--   - keeps query planes separate from render payload
--
-- Important custom-family note:
--   Custom draws are implemented here as a real first-class render family.
--   They are not dropped and they are not forced through a fake box/text/image
--   path. Instead, planning packs them into explicit CustomBatch values with a
--   family kind and per-item payload list. Kernel specialization can then keep
--   carrying those families structurally without inventing an interpreter.
--
-- Functional-style note:
--   This code follows the repository convention and keeps the pure boundary in
--   a LuaFun-shaped style: map/filter/reduce over solved records, small pure
--   helpers, and explicit structural construction. The only mutation that
--   remains is local accumulator state inside reducers for list building and
--   clip interning.
-- ============================================================================

local function rect_key(r)
    return table.concat({ r.x, r.y, r.w, r.h }, ":")
end

local function corners_key(c)
    return table.concat({ c.top_left, c.top_right, c.bottom_right, c.bottom_left }, ":")
end

local function transform_key(xform)
    if not xform then return "nil" end
    return table.concat({ xform.m11, xform.m12, xform.m21, xform.m22, xform.tx, xform.ty }, ":")
end

local function clip_key(clip)
    if not clip then return "nil" end
    return U.match(clip, {
        ClipRect = function(v)
            return "rect:" .. rect_key(v.rect)
        end,
        ClipRoundedRect = function(v)
            return "round:" .. rect_key(v.rect) .. ":" .. corners_key(v.corners)
        end,
    })
end

local function draw_state_key(state)
    return table.concat({
        state.clip_index or "nil",
        state.blend.kind,
        state.opacity,
        transform_key(state.transform),
    }, "|")
end

local function hit_z_index(region, node)
    -- Region order remains the primary routing authority. Inside one region we
    -- refine that integer z layer with a stable fractional node-order term so
    -- later nodes sort above earlier ones without disturbing cross-region z.
    return region.z_index + (node.index / (#region.nodes + 1))
end

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

local function clip_index_for(clips, clip_keys, clip)
    if not clip then return nil end

    local key = clip_key(clip)
    local existing = clip_keys[key]
    if existing then return existing end

    local index = #clips + 1
    clips[index] = clip
    clip_keys[key] = index
    return index
end

local function draw_state_for(T, clips, clip_keys, state)
    return T.UiPlan.DrawState(
        clip_index_for(clips, clip_keys, state.clip),
        state.blend,
        state.opacity,
        state.transform
    )
end

local function append_batch_record(region_batches, batch)
    local prev = region_batches[#region_batches]
    if prev == nil
        or prev.kind ~= batch.kind
        or prev.state_key ~= batch.state_key
        or (batch.kind == "CustomBatch" and prev.custom_family ~= batch.custom_family) then
        region_batches[#region_batches + 1] = batch
        return region_batches
    end

    append_all(prev.items, batch.items)
    return region_batches
end

local function text_runs_for(T, shaped)
    local first_line = shaped.lines[1]
    local first_run = first_line and first_line.runs[1] or nil
    if not first_run then return {} end

    return {
        T.UiPlan.TextRun(
            shaped.text,
            first_run.font,
            first_run.size_px,
            first_run.color,
            shaped.bounds,
            shaped.wrap,
            shaped.align
        )
    }
end

local function draw_batch_record_for(T, clips, clip_keys, atom)
    return U.match(atom, {
        BoxDraw = function(v)
            local state = draw_state_for(T, clips, clip_keys, v.state)
            return {
                kind = "BoxBatch",
                state = state,
                state_key = draw_state_key(state),
                items = {
                    T.UiPlan.BoxItem(v.rect, v.fill, v.stroke, v.stroke_width, v.align, v.corners)
                },
            }
        end,
        ShadowDraw = function(v)
            local state = draw_state_for(T, clips, clip_keys, v.state)
            return {
                kind = "ShadowBatch",
                state = state,
                state_key = draw_state_key(state),
                items = {
                    T.UiPlan.ShadowItem(v.rect, v.brush, v.blur, v.spread, v.dx, v.dy, v.shadow_kind, v.corners)
                },
            }
        end,
        TextDraw = function(v)
            local runs = text_runs_for(T, v.shaped)
            if #runs == 0 then return nil end

            local state = draw_state_for(T, clips, clip_keys, v.state)
            return {
                kind = "TextBatch",
                state = state,
                state_key = draw_state_key(state),
                items = runs,
            }
        end,
        ImageDraw = function(v)
            local state = draw_state_for(T, clips, clip_keys, v.state)
            return {
                kind = "ImageBatch",
                state = state,
                state_key = draw_state_key(state),
                items = {
                    T.UiPlan.ImageItem(v.image, v.rect, v.sampling, v.corners)
                },
            }
        end,
        CustomDraw = function(v)
            local state = draw_state_for(T, clips, clip_keys, v.state)
            return {
                kind = "CustomBatch",
                state = state,
                state_key = draw_state_key(state),
                custom_family = v.family,
                items = {
                    T.UiPlan.CustomItem(v.payload)
                },
            }
        end,
    })
end

local function finalize_batch(T, batch)
    return ({
        BoxBatch = function()
            return T.UiPlan.BoxBatch(batch.state, L(batch.items))
        end,
        ShadowBatch = function()
            return T.UiPlan.ShadowBatch(batch.state, L(batch.items))
        end,
        TextBatch = function()
            return T.UiPlan.TextBatch(batch.state, L(batch.items))
        end,
        ImageBatch = function()
            return T.UiPlan.ImageBatch(batch.state, L(batch.items))
        end,
        CustomBatch = function()
            return T.UiPlan.CustomBatch(batch.state, batch.custom_family, L(batch.items))
        end,
    })[batch.kind]()
end

local function region_query_planes(T, region)
    local hits = F.iter(region.nodes)
        :filter(function(node) return node.behavior.hit ~= nil end)
        :map(function(node)
            return T.UiPlan.HitItem(
                node.id,
                node.semantic_ref,
                node.behavior.hit.shape,
                hit_z_index(region, node),
                node.behavior.pointer,
                node.behavior.scroll and T.UiPlan.ScrollBinding(node.behavior.scroll.axis, node.behavior.scroll.model) or nil,
                node.behavior.drag_drop
            )
        end)
        :totable()

    local focus_rows = F.iter(region.nodes)
        :filter(function(node) return node.behavior.focus ~= nil end)
        :map(function(node)
            return {
                index = node.index,
                order = node.behavior.focus.order,
                item = T.UiPlan.FocusItem(
                    node.id,
                    node.semantic_ref,
                    node.behavior.focus.rect,
                    node.behavior.focus.mode,
                    node.behavior.focus.order
                ),
            }
        end)
        :totable()

    local key_routes = flat_collect(region.nodes, function(node)
        return F.iter(node.behavior.keys):map(function(key)
            return T.UiPlan.KeyRoute(
                node.id,
                key.chord,
                key.when,
                key.command,
                key.global
            )
        end):totable()
    end)

    local scroll_hosts = F.iter(region.nodes)
        :filter(function(node) return node.behavior.scroll ~= nil end)
        :map(function(node)
            return T.UiPlan.ScrollHost(
                node.id,
                node.semantic_ref,
                node.behavior.scroll.axis,
                node.behavior.scroll.model,
                node.behavior.scroll.viewport_rect,
                node.behavior.scroll.content_extent
            )
        end)
        :totable()

    local edit_hosts = F.iter(region.nodes)
        :filter(function(node) return node.behavior.edit ~= nil end)
        :map(function(node)
            return T.UiPlan.EditHost(
                node.id,
                node.semantic_ref,
                node.behavior.edit.model,
                node.behavior.edit.rect,
                node.behavior.edit.multiline,
                node.behavior.edit.read_only,
                node.behavior.edit.changed
            )
        end)
        :totable()

    local accessibility = F.iter(region.nodes)
        :filter(function(node) return node.accessibility ~= nil end)
        :map(function(node)
            return T.UiPlan.AccessibilityItem(
                node.id,
                node.semantic_ref,
                node.accessibility.role,
                node.accessibility.label,
                node.accessibility.description,
                node.accessibility.rect,
                node.accessibility.sort_priority
            )
        end)
        :totable()

    -- Focus chain is the one query plane where the name already implies an
    -- ordered sequence. We sort explicit ordered items first by authored order,
    -- then leave unspecified-order items in stable node order afterwards.
    table.sort(focus_rows, function(a, b)
        if a.order ~= nil and b.order ~= nil then
            if a.order == b.order then return a.index < b.index end
            return a.order < b.order
        end
        if a.order ~= nil then return true end
        if b.order ~= nil then return false end
        return a.index < b.index
    end)

    return {
        hits = hits,
        focus_chain = F.iter(focus_rows):map(function(row) return row.item end):totable(),
        key_routes = key_routes,
        scroll_hosts = scroll_hosts,
        edit_hosts = edit_hosts,
        accessibility = accessibility,
    }
end

local function plan_region(T, clips, clip_keys, region)
    local atoms = flat_collect(region.nodes, function(node)
        return node.draw
    end)

    local draw_batches = F.iter(atoms):reduce(function(acc, atom)
        local batch = draw_batch_record_for(T, clips, clip_keys, atom)
        if batch == nil then return acc end
        return append_batch_record(acc, batch)
    end, {})

    local query = region_query_planes(T, region)

    return {
        region = region,
        draws = F.iter(draw_batches):map(function(batch)
            return finalize_batch(T, batch)
        end):totable(),
        hits = query.hits,
        focus_chain = query.focus_chain,
        key_routes = query.key_routes,
        scroll_hosts = query.scroll_hosts,
        edit_hosts = query.edit_hosts,
        accessibility = query.accessibility,
    }
end

return function(T)
    -- ---------------------------------------------------------------------
    -- Public boundary:
    --   UiSolved.Scene:plan() -> UiPlan.Scene
    -- ---------------------------------------------------------------------
    -- No side inputs are required here. By construction, UiSolved already
    -- contains the solved facts needed for both render and query planning.
    -- That is one of the main reasons the UiSolved -> UiPlan boundary is real:
    -- planning is now a pure projection from solved node facts to packed planes.
    T.UiSolved.Scene.plan = U.transition(function(scene)
        local acc = F.iter(scene.regions):reduce(function(acc, region)
            local planned = plan_region(T, acc.clips, acc.clip_keys, region)

            local draw_start = #acc.draws + 1
            local hit_start = #acc.hits + 1
            local focus_start = #acc.focus_chain + 1
            local key_start = #acc.key_routes + 1
            local scroll_start = #acc.scroll_hosts + 1
            local edit_start = #acc.edit_hosts + 1
            local accessibility_start = #acc.accessibility + 1

            append_all(acc.draws, planned.draws)
            append_all(acc.hits, planned.hits)
            append_all(acc.focus_chain, planned.focus_chain)
            append_all(acc.key_routes, planned.key_routes)
            append_all(acc.scroll_hosts, planned.scroll_hosts)
            append_all(acc.edit_hosts, planned.edit_hosts)
            append_all(acc.accessibility, planned.accessibility)

            acc.regions[#acc.regions + 1] = T.UiPlan.Region(
                region.id,
                region.debug_name,
                region.z_index,
                region.modal,
                region.consumes_pointer,
                draw_start,
                #planned.draws,
                hit_start,
                #planned.hits,
                focus_start,
                #planned.focus_chain,
                key_start,
                #planned.key_routes,
                scroll_start,
                #planned.scroll_hosts,
                edit_start,
                #planned.edit_hosts,
                accessibility_start,
                #planned.accessibility
            )

            return acc
        end, {
            clips = {},
            clip_keys = {},
            draws = {},
            hits = {},
            focus_chain = {},
            key_routes = {},
            scroll_hosts = {},
            edit_hosts = {},
            accessibility = {},
            regions = {},
        })

        return T.UiPlan.Scene(
            scene.viewport,
            L(acc.regions),
            L(acc.clips),
            L(acc.draws),
            L(acc.hits),
            L(acc.focus_chain),
            L(acc.key_routes),
            L(acc.scroll_hosts),
            L(acc.edit_hosts),
            L(acc.accessibility)
        )
    end)
end
