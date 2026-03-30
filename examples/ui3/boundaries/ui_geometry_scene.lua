local asdl = require("asdl")
local U = require("unit")
local F = require("fun")

local L = asdl.List

return function(T)
    do
        -- ====================================================================
        -- UiGeometry.Scene + UiRenderFacts.Scene -> project_render_scene -> UiRenderScene.Scene
        -- ====================================================================

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

        local function clip_shape_for(rect, corners)
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

        local function effects_summary_for(effects, placed)
            return F.iter(effects):reduce(function(acc, effect)
                return U.match(effect, {
                    LocalClip = function(v)
                        if placed ~= nil then
                            acc.local_clips[#acc.local_clips + 1] = clip_shape_for(placed.border_box, v.corners)
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

        local function inherited_state_for(parent_state, effects, placed)
            local summary = effects_summary_for(effects, placed)
            return {
                clips = merge_clip_lists(parent_state.clips, summary.local_clips),
                opacity = parent_state.opacity * summary.opacity,
                transform = summary.transform or parent_state.transform,
                blend = summary.blend or parent_state.blend,
            }
        end

        local function default_occurrence_state()
            return {
                clips = Ls(),
                opacity = 1,
                transform = nil,
                blend = T.UiCore.BlendNormal(),
            }
        end

        local function image_corners_for(use)
            return U.match(use, {
                DefaultUse = function()
                    return T.UiCore.Corners(0, 0, 0, 0)
                end,
                ImageUse = function(v)
                    return v.corners
                end,
            })
        end

        local function occurrence_state_value(state)
            return T.UiRenderScene.OccurrenceState(
                state.clips,
                state.blend,
                state.opacity,
                state.transform
            )
        end

        local function emit_decorations(facts, placed, state_value, out)
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

        local function emit_content(facts, placed, state_value, out)
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
                            image_corners_for(facts.use)
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

        local function project_region(geometry_region, facts_region)
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
            local base_state = default_occurrence_state()
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

                local state = inherited_state_for(parent_state, facts.effects, placed)
                stack[#stack + 1] = {
                    end_index = header.index + header.subtree_count - 1,
                    state = state,
                }

                if placed ~= nil then
                    local state_value = occurrence_state_value(state)
                    emit_decorations(facts, placed, state_value, occurrences)
                    emit_content(facts, placed, state_value, occurrences)
                end

                i = i + 1
            end

            return {
                header = geometry_region.header,
                z_index = facts_region.z_index,
                occurrences = occurrences,
            }
        end

        local function project_render_scene(geometry, render_facts)
            if #geometry.regions ~= #render_facts.regions then
                error("UiGeometry.Scene:project_render_scene: geometry/render-facts region count mismatch", 3)
            end

            local projected = F.iter(geometry.regions):reduce(function(acc, geometry_region)
                local idx = #acc.regions + 1
                local facts_region = render_facts.regions[idx]
                local region = project_region(geometry_region, facts_region)
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

        T.UiGeometry.Scene.project_render_scene = U.transition(function(geometry, render_facts)
            return project_render_scene(geometry, render_facts)
        end)
    end

    do
        -- ====================================================================
        -- UiGeometry.Scene + UiQueryFacts.Scene -> project_query_scene -> UiQueryScene.Scene
        -- ====================================================================

        local function Ls(xs)
            return L(xs or {})
        end

        local function region_header_equals(a, b)
            return a.id.value == b.id.value
               and a.root_index == b.root_index
               and a.debug_name == b.debug_name
        end

        local function hit_shape_for(rect)
            return T.UiCore.HitRect(rect)
        end

        local function placed_geometry(node)
            return U.match(node, {
                Excluded = function()
                    return nil
                end,
                Placed = function(v)
                    return v.node
                end,
            })
        end

        local function pointer_binding_for(binding)
            return U.match(binding, {
                HoverBinding = function(v)
                    return T.UiQueryScene.HoverBinding(v.cursor, v.enter, v.leave)
                end,
                PressBinding = function(v)
                    return T.UiQueryScene.PressBinding(v.button, v.click_count, v.command)
                end,
                ToggleBinding = function(v)
                    return T.UiQueryScene.ToggleBinding(v.value, v.button, v.command)
                end,
                GestureBinding = function(v)
                    return T.UiQueryScene.GestureBinding(v.gesture, v.command)
                end,
            })
        end

        local function drag_drop_binding_for(binding)
            return U.match(binding, {
                DraggableBinding = function(v)
                    return T.UiQueryScene.DraggableBinding(v.payload, v.begin, v.finish)
                end,
                DropTargetBinding = function(v)
                    return T.UiQueryScene.DropTargetBinding(v.policy, v.command)
                end,
            })
        end

        local function scroll_binding_for(scroll)
            if scroll == nil then return nil end
            return T.UiQueryScene.ScrollBinding(scroll.axis, scroll.model)
        end

        local function emit_query_occurrences(region, header, placed, fact, acc)
            local id = header.id
            local semantic_ref = header.semantic_ref

            local pointer = (#fact.pointer > 0) and F.range(1, #fact.pointer):map(function(i)
                return pointer_binding_for(fact.pointer[i])
            end):totable() or {}

            local drag_drop = (#fact.drag_drop > 0) and F.range(1, #fact.drag_drop):map(function(i)
                return drag_drop_binding_for(fact.drag_drop[i])
            end):totable() or {}

            local wants_hit = fact.hit.kind ~= "NoHit"
                or #pointer > 0
                or fact.scroll ~= nil
                or #drag_drop > 0

            if wants_hit then
                acc.hits[#acc.hits + 1] = T.UiQueryScene.HitOccurrence(
                    id,
                    semantic_ref,
                    hit_shape_for(placed.border_box),
                    region.z_index,
                    Ls(pointer),
                    scroll_binding_for(fact.scroll),
                    Ls(drag_drop)
                )
            end

            if fact.focus ~= nil then
                acc.focus[#acc.focus + 1] = T.UiQueryScene.FocusOccurrence(
                    id,
                    semantic_ref,
                    placed.border_box,
                    fact.focus.mode,
                    fact.focus.order
                )
            end

            if #fact.keys > 0 then
                F.range(1, #fact.keys):each(function(i)
                    local key = fact.keys[i]
                    acc.keys[#acc.keys + 1] = T.UiQueryScene.KeyOccurrence(
                        id,
                        key.chord,
                        key.when,
                        key.command,
                        key.global
                    )
                end)
            end

            if fact.scroll ~= nil then
                acc.scroll_hosts[#acc.scroll_hosts + 1] = T.UiQueryScene.ScrollHostOccurrence(
                    id,
                    semantic_ref,
                    fact.scroll.axis,
                    fact.scroll.model,
                    placed.content_box,
                    placed.content_extent
                )
            end

            if fact.edit ~= nil then
                acc.edit_hosts[#acc.edit_hosts + 1] = T.UiQueryScene.EditHostOccurrence(
                    id,
                    semantic_ref,
                    fact.edit.model,
                    placed.content_box,
                    fact.edit.multiline,
                    fact.edit.read_only,
                    fact.edit.changed
                )
            end

            U.match(fact.accessibility, {
                NoAccessibility = function()
                    return acc
                end,
                Exposed = function(v)
                    acc.accessibility[#acc.accessibility + 1] = T.UiQueryScene.AccessibilityOccurrence(
                        id,
                        semantic_ref,
                        v.role,
                        v.label,
                        v.description,
                        placed.border_box,
                        v.sort_priority
                    )
                    return acc
                end,
            })

            return acc
        end

        local function project_region(geometry_region, facts_region, acc)
            if not region_header_equals(geometry_region.header, facts_region.header) then
                error("UiGeometry.Scene:project_query_scene: region headers are not aligned", 3)
            end

            if #geometry_region.headers ~= #geometry_region.nodes then
                error("UiGeometry.Scene:project_query_scene: geometry region headers/nodes length mismatch", 3)
            end

            if #geometry_region.headers ~= #facts_region.node_facts then
                error("UiGeometry.Scene:project_query_scene: geometry/query-facts node count mismatch", 3)
            end

            local hit_start = #acc.hits
            local focus_start = #acc.focus
            local key_start = #acc.keys
            local scroll_start = #acc.scroll_hosts
            local edit_start = #acc.edit_hosts
            local accessibility_start = #acc.accessibility

            F.range(1, #geometry_region.headers):each(function(i)
                local placed = placed_geometry(geometry_region.nodes[i])
                if placed ~= nil then
                    emit_query_occurrences(
                        facts_region,
                        geometry_region.headers[i],
                        placed,
                        facts_region.node_facts[i],
                        acc
                    )
                end
            end)

            acc.regions[#acc.regions + 1] = T.UiQueryScene.Region(
                geometry_region.header,
                facts_region.z_index,
                facts_region.modal,
                facts_region.consumes_pointer,
                hit_start,
                #acc.hits - hit_start,
                focus_start,
                #acc.focus - focus_start,
                key_start,
                #acc.keys - key_start,
                scroll_start,
                #acc.scroll_hosts - scroll_start,
                edit_start,
                #acc.edit_hosts - edit_start,
                accessibility_start,
                #acc.accessibility - accessibility_start
            )

            return acc
        end

        local function project_query_scene(geometry, query_facts)
            if #geometry.regions ~= #query_facts.regions then
                error("UiGeometry.Scene:project_query_scene: region count mismatch", 3)
            end

            local acc = F.range(1, #geometry.regions):reduce(function(state, i)
                return project_region(geometry.regions[i], query_facts.regions[i], state)
            end, {
                regions = {},
                hits = {},
                focus = {},
                keys = {},
                scroll_hosts = {},
                edit_hosts = {},
                accessibility = {},
            })

            return T.UiQueryScene.Scene(
                Ls(acc.regions),
                Ls(acc.hits),
                Ls(acc.focus),
                Ls(acc.keys),
                Ls(acc.scroll_hosts),
                Ls(acc.edit_hosts),
                Ls(acc.accessibility)
            )
        end

        T.UiGeometry.Scene.project_query_scene = U.transition(function(geometry, query_facts)
            return project_query_scene(geometry, query_facts)
        end)
    end
end
