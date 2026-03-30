local asdl = require("asdl")
local U = require("unit")
local F = require("fun")

local L = asdl.List

-- ============================================================================
-- UiGeometry.Scene + UiRenderFacts.Scene -> project_render_scene -> UiRenderScene.Scene
-- ----------------------------------------------------------------------------
-- ui3 Layer 3: project shared solved geometry plus render-side facts into a
-- concrete render occurrence scene.
--
-- What this boundary consumes:
--   - solved region/node geometry aligned by shared flat headers
--   - render-side local facts/effects/content aligned to the same node space
--
-- What this boundary produces:
--   - region occurrence spans in final render order
--   - concrete occurrences with solved rects attached
--   - occurrence-local resolved draw state
--
-- What this boundary intentionally does NOT do:
--   - no resource dedupe / slot assignment
--   - no clip refs / batch headers / machine packing
--   - no query organization
-- ============================================================================

local function Ls(xs)
    return L(xs or {})
end

local function region_header_equals(a, b)
    return a.id.value == b.id.value
       and a.root_index == b.root_index
       and a.debug_name == b.debug_name
end

local function corners_are_square(c)
    return c.top_left == 0
       and c.top_right == 0
       and c.bottom_right == 0
       and c.bottom_left == 0
end

local function clip_shape_for(T, rect, corners)
    if corners_are_square(corners) then
        return T.UiCore.ClipRect(rect)
    end
    return T.UiCore.ClipRoundedRect(rect, corners)
end

local function merge_clip_lists(parent_clips, local_clips)
    local pn = parent_clips and #parent_clips or 0
    local ln = local_clips and #local_clips or 0
    if ln == 0 then return parent_clips end
    if pn == 0 then return Ls(local_clips) end
    local merged = {}
    local i = 1
    while i <= pn do
        merged[#merged + 1] = parent_clips[i]
        i = i + 1
    end
    i = 1
    while i <= ln do
        merged[#merged + 1] = local_clips[i]
        i = i + 1
    end
    return Ls(merged)
end

local function effects_summary_for(T, effects, placed)
    return F.iter(effects):reduce(function(acc, effect)
        return U.match(effect, {
            LocalClip = function(v)
                if placed ~= nil then
                    acc.local_clips[#acc.local_clips + 1] = clip_shape_for(T, placed.border_box, v.corners)
                end
                return acc
            end,
            LocalOpacity = function(v)
                acc.opacity = acc.opacity * v.value
                return acc
            end,
            LocalTransform = function(v)
                acc.transform = v.xform
                return acc
            end,
            LocalBlend = function(v)
                acc.blend = v.mode
                return acc
            end,
        })
    end, {
        local_clips = {},
        opacity = 1,
        transform = nil,
        blend = nil,
    })
end

local function inherited_state_for(T, parent_state, effects, placed)
    local summary = effects_summary_for(T, effects, placed)
    return {
        clips = merge_clip_lists(parent_state.clips, summary.local_clips),
        opacity = parent_state.opacity * summary.opacity,
        transform = summary.transform or parent_state.transform,
        blend = summary.blend or parent_state.blend,
    }
end

local function default_occurrence_state(T)
    return {
        clips = Ls(),
        opacity = 1,
        transform = nil,
        blend = T.UiCore.BlendNormal(),
    }
end

local function image_corners_for(T, use)
    return U.match(use, {
        DefaultUse = function()
            return T.UiCore.Corners(0, 0, 0, 0)
        end,
        ImageUse = function(v)
            return v.corners
        end,
    })
end

local function occurrence_state_value(T, state)
    return T.UiRenderScene.OccurrenceState(
        state.clips,
        state.blend,
        state.opacity,
        state.transform
    )
end

local function emit_decorations(T, facts, placed, state_value, out)
    F.iter(facts.decorations):each(function(decoration)
        U.match(decoration, {
            BoxDecor = function(v)
                out[#out + 1] = T.UiRenderScene.Box(
                    T.UiRenderScene.BoxOccurrence(
                        state_value,
                        placed.border_box,
                        v.fill,
                        v.stroke,
                        v.stroke_width,
                        v.align,
                        v.corners
                    )
                )
            end,
            ShadowDecor = function(v)
                out[#out + 1] = T.UiRenderScene.Shadow(
                    T.UiRenderScene.ShadowOccurrence(
                        state_value,
                        placed.border_box,
                        v.brush,
                        v.blur,
                        v.spread,
                        v.dx,
                        v.dy,
                        v.shadow_kind,
                        v.corners
                    )
                )
            end,
            CustomDecor = function(_)
                error("UiGeometry.Scene:project_render_scene: custom render decorations are not implemented yet", 3)
            end,
        })
    end)
end

local function emit_content(T, facts, placed, state_value, out)
    return U.match(facts.content, {
        NoContent = function()
            return out
        end,
        Text = function(v)
            out[#out + 1] = T.UiRenderScene.Text(
                T.UiRenderScene.TextOccurrence(
                    state_value,
                    v.text,
                    placed.content_box
                )
            )
            return out
        end,
        Image = function(v)
            out[#out + 1] = T.UiRenderScene.Image(
                T.UiRenderScene.ImageOccurrence(
                    state_value,
                    v.image,
                    placed.content_box,
                    image_corners_for(T, facts.use)
                )
            )
            return out
        end,
        Custom = function(v)
            return U.match(v.custom, {
                InlineCustomContent = function(cv)
                    out[#out + 1] = T.UiRenderScene.Custom(
                        T.UiRenderScene.InlineCustom(
                            state_value,
                            cv.family,
                            cv.payload
                        )
                    )
                    return out
                end,
                ResourceCustomContent = function(cv)
                    out[#out + 1] = T.UiRenderScene.Custom(
                        T.UiRenderScene.ResourceCustom(
                            state_value,
                            cv.family,
                            cv.resource_payload,
                            cv.instance_payload
                        )
                    )
                    return out
                end,
            })
        end,
    })
end

local function project_region(T, geometry_region, facts_region)
    if not region_header_equals(geometry_region.header, facts_region.header) then
        error("UiGeometry.Scene:project_render_scene: region headers are not aligned", 3)
    end

    if #geometry_region.headers ~= #geometry_region.nodes then
        error("UiGeometry.Scene:project_render_scene: geometry region headers/nodes length mismatch", 3)
    end

    if #geometry_region.headers ~= #facts_region.node_facts then
        error("UiGeometry.Scene:project_render_scene: geometry/render-facts node count mismatch", 3)
    end

    local occurrences = {}
    local stack = {}
    local base_state = default_occurrence_state(T)
    local i = 1

    while i <= #geometry_region.headers do
        local header = geometry_region.headers[i]
        local node = geometry_region.nodes[i]
        local facts = facts_region.node_facts[i]

        while #stack > 0 and stack[#stack].end_index < header.index do
            stack[#stack] = nil
        end

        local parent_state = (#stack > 0 and stack[#stack].state) or base_state
        local placed = U.match(node, {
            Excluded = function()
                return nil
            end,
            Placed = function(v)
                return v.node
            end,
        })

        local state = inherited_state_for(T, parent_state, facts.effects, placed)
        stack[#stack + 1] = {
            end_index = header.index + header.subtree_count - 1,
            state = state,
        }

        if placed ~= nil then
            local state_value = occurrence_state_value(T, state)
            emit_decorations(T, facts, placed, state_value, occurrences)
            emit_content(T, facts, placed, state_value, occurrences)
        end

        i = i + 1
    end

    return {
        header = geometry_region.header,
        z_index = facts_region.z_index,
        occurrences = occurrences,
    }
end

local function project_render_scene(T, geometry, render_facts)
    if #geometry.regions ~= #render_facts.regions then
        error("UiGeometry.Scene:project_render_scene: geometry/render-facts region count mismatch", 3)
    end

    local projected = F.iter(geometry.regions):reduce(function(acc, geometry_region)
        local idx = #acc.regions + 1
        local facts_region = render_facts.regions[idx]
        local region = project_region(T, geometry_region, facts_region)
        local occurrence_start = #acc.occurrences

        F.iter(region.occurrences):each(function(occurrence)
            acc.occurrences[#acc.occurrences + 1] = occurrence
        end)

        acc.regions[#acc.regions + 1] = T.UiRenderScene.Region(
            region.header,
            region.z_index,
            occurrence_start,
            #region.occurrences
        )
        return acc
    end, {
        regions = {},
        occurrences = {},
    })

    return T.UiRenderScene.Scene(
        Ls(projected.regions),
        Ls(projected.occurrences)
    )
end

return function(T)
    T.UiGeometry.Scene.project_render_scene = U.transition(function(geometry, render_facts)
        return project_render_scene(T, geometry, render_facts)
    end)
end
