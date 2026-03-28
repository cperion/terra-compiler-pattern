local U = require("unit")
local F = require("fun")

local Resolve = {}

local function L(xs)
    return terralib.newlist(xs or {})
end

local function head(xs)
    for _, value in ipairs(xs) do
        return value
    end
    return nil
end

local function find_by(xs, pred, where)
    local value = head(F.iter(xs):filter(pred):totable())
    if value ~= nil then return value end
    error(where, 3)
end

local function option_map(value, fn)
    return value and fn(value) or nil
end

local function contains_ref(stack, ref)
    return F.iter(stack):any(function(v) return v == ref end)
end

local function push_ref(stack, ref)
    local out = {}
    for i, v in ipairs(stack) do out[i] = v end
    out[#out + 1] = ref
    return out
end

function Resolve.install(T)
    local function find_token(doc, ref)
        return find_by(doc.tokens, function(token)
            return token.id == ref
        end, ("DesignDecl.Document:resolve: unknown token ref %s"):format(tostring(ref and ref.value)))
    end

    local function find_role(doc, ref)
        return find_by(doc.roles, function(role)
            return role.id == ref
        end, ("DesignDecl.Document:resolve: unknown role ref %s"):format(tostring(ref and ref.value)))
    end

    local function find_theme(doc, ref)
        return find_by(doc.themes, function(theme)
            return theme.id == ref
        end, ("DesignDecl.Document:resolve: unknown theme ref %s"):format(tostring(ref and ref.value)))
    end

    local function token_override(mode, ref)
        return head(F.iter(mode.overrides):filter(function(override)
            return override.kind == "TokenOverride" and override.token == ref
        end):totable())
    end

    local function role_override(mode, kind, ref)
        return head(F.iter(mode.overrides):filter(function(override)
            return override.kind == kind and override.role == ref
        end):totable())
    end

    local function resolve_token_value(token_value)
        return U.match(token_value, {
            ColorValue = function(v)
                return T.DesignResolved.ColorToken(nil, nil, v.value)
            end,
            NumberValue = function(v)
                return T.DesignResolved.NumberToken(nil, nil, v.kind, v.value)
            end,
            FontValue = function(v)
                return T.DesignResolved.FontToken(nil, nil, v.value)
            end,
        })
    end

    local function resolve_token(mode, token)
        local override = token_override(mode, token.id)
        return U.match(token, {
            ColorToken = function(v)
                if override then
                    if override.value.kind ~= "ColorValue" then
                        error(("DesignDecl.Document:resolve: token override kind mismatch for %s"):format(v.name), 3)
                    end
                    return T.DesignResolved.ColorToken(v.id, v.name, override.value.value)
                end
                return T.DesignResolved.ColorToken(v.id, v.name, v.value)
            end,
            NumberToken = function(v)
                if override then
                    if override.value.kind ~= "NumberValue" then
                        error(("DesignDecl.Document:resolve: token override kind mismatch for %s"):format(v.name), 3)
                    end
                    if override.value.kind ~= nil and override.value.kind ~= v.kind then
                        error(("DesignDecl.Document:resolve: token override number kind mismatch for %s"):format(v.name), 3)
                    end
                    return T.DesignResolved.NumberToken(v.id, v.name, v.kind, override.value.value)
                end
                return T.DesignResolved.NumberToken(v.id, v.name, v.kind, v.value)
            end,
            FontToken = function(v)
                if override then
                    if override.value.kind ~= "FontValue" then
                        error(("DesignDecl.Document:resolve: token override kind mismatch for %s"):format(v.name), 3)
                    end
                    return T.DesignResolved.FontToken(v.id, v.name, override.value.value)
                end
                return T.DesignResolved.FontToken(v.id, v.name, v.value)
            end,
        })
    end

    local function resolve_token_by_ref(doc, mode_decl, ref)
        return resolve_token(mode_decl, find_token(doc, ref))
    end

    local resolve_color_expr, resolve_number_expr, resolve_font_expr, resolve_text_style_expr
    local resolve_resolved_role

    resolve_resolved_role = function(doc, mode_decl, role_decl, stack)
        if contains_ref(stack, role_decl.id) then
            error(("DesignDecl.Document:resolve: cyclic role reference at %s"):format(role_decl.name), 3)
        end

        local next_stack = push_ref(stack, role_decl.id)

        return U.match(role_decl, {
            ColorRole = function(v)
                local override = role_override(mode_decl, "ColorRoleOverride", v.id)
                local value = resolve_color_expr(doc, mode_decl, override and override.value or v.default, next_stack)
                return T.DesignResolved.ColorRole(v.id, v.name, value)
            end,
            NumberRole = function(v)
                local override = role_override(mode_decl, "NumberRoleOverride", v.id)
                local value = resolve_number_expr(doc, mode_decl, override and override.value or v.default, next_stack)
                return T.DesignResolved.NumberRole(v.id, v.name, v.kind, value)
            end,
            FontRole = function(v)
                local override = role_override(mode_decl, "FontRoleOverride", v.id)
                local value = resolve_font_expr(doc, mode_decl, override and override.value or v.default, next_stack)
                return T.DesignResolved.FontRole(v.id, v.name, value)
            end,
            TextRole = function(v)
                local override = role_override(mode_decl, "TextRoleOverride", v.id)
                local value = resolve_text_style_expr(doc, mode_decl, override and override.value or v.default, next_stack)
                return T.DesignResolved.TextRole(v.id, v.name, value)
            end,
        })
    end

    local function resolve_role_by_ref(doc, mode_decl, ref, stack)
        return resolve_resolved_role(doc, mode_decl, find_role(doc, ref), stack)
    end

    resolve_color_expr = function(doc, mode_decl, expr, stack)
        return U.match(expr, {
            LiteralColor = function(v)
                return v.value
            end,
            TokenColor = function(v)
                local token = resolve_token_by_ref(doc, mode_decl, v.token)
                if token.kind ~= "ColorToken" then
                    error("DesignDecl.Document:resolve: TokenColor referenced non-color token", 3)
                end
                return token.value
            end,
            RoleColor = function(v)
                local role = resolve_role_by_ref(doc, mode_decl, v.role, stack)
                if role.kind ~= "ColorRole" then
                    error("DesignDecl.Document:resolve: RoleColor referenced non-color role", 3)
                end
                return role.value
            end,
        })
    end

    resolve_number_expr = function(doc, mode_decl, expr, stack)
        return U.match(expr, {
            LiteralNumber = function(v)
                return v.value
            end,
            TokenNumber = function(v)
                local token = resolve_token_by_ref(doc, mode_decl, v.token)
                if token.kind ~= "NumberToken" then
                    error("DesignDecl.Document:resolve: TokenNumber referenced non-number token", 3)
                end
                return token.value
            end,
            RoleNumber = function(v)
                local role = resolve_role_by_ref(doc, mode_decl, v.role, stack)
                if role.kind ~= "NumberRole" then
                    error("DesignDecl.Document:resolve: RoleNumber referenced non-number role", 3)
                end
                return role.value
            end,
        })
    end

    resolve_font_expr = function(doc, mode_decl, expr, stack)
        return U.match(expr, {
            LiteralFont = function(v)
                return v.value
            end,
            TokenFont = function(v)
                local token = resolve_token_by_ref(doc, mode_decl, v.token)
                if token.kind ~= "FontToken" then
                    error("DesignDecl.Document:resolve: TokenFont referenced non-font token", 3)
                end
                return token.value
            end,
            RoleFont = function(v)
                local role = resolve_role_by_ref(doc, mode_decl, v.role, stack)
                if role.kind ~= "FontRole" then
                    error("DesignDecl.Document:resolve: RoleFont referenced non-font role", 3)
                end
                return role.value
            end,
        })
    end

    resolve_text_style_expr = function(doc, mode_decl, expr, stack)
        return T.DesignResolved.TextStyle(
            option_map(expr.font, function(v) return resolve_font_expr(doc, mode_decl, v, stack) end),
            option_map(expr.size_px, function(v) return resolve_number_expr(doc, mode_decl, v, stack) end),
            expr.weight,
            expr.slant,
            option_map(expr.letter_spacing_px, function(v) return resolve_number_expr(doc, mode_decl, v, stack) end),
            option_map(expr.line_height_px, function(v) return resolve_number_expr(doc, mode_decl, v, stack) end),
            option_map(expr.color, function(v) return resolve_color_expr(doc, mode_decl, v, stack) end)
        )
    end

    local function resolved_roles(doc, mode_decl)
        return L(F.iter(doc.roles):map(function(role_decl)
            return resolve_resolved_role(doc, mode_decl, role_decl, {})
        end):totable())
    end

    local function resolved_tokens(doc, mode_decl)
        return L(F.iter(doc.tokens):map(function(token_decl)
            return resolve_token(mode_decl, token_decl)
        end):totable())
    end

    local function resolve_measure(doc, mode_decl, expr)
        return U.match(expr, {
            Auto = function() return T.DesignResolved.Auto() end,
            Px = function(v) return T.DesignResolved.Px(resolve_number_expr(doc, mode_decl, v.value, {})) end,
            Percent = function(v) return T.DesignResolved.Percent(v.value) end,
            Content = function() return T.DesignResolved.Content() end,
            Flex = function(v) return T.DesignResolved.Flex(v.weight) end,
        })
    end

    local function resolve_edge(doc, mode_decl, expr)
        return U.match(expr, {
            Unset = function() return T.DesignResolved.Unset() end,
            EdgePx = function(v) return T.DesignResolved.EdgePx(resolve_number_expr(doc, mode_decl, v.value, {})) end,
            EdgePercent = function(v) return T.DesignResolved.EdgePercent(v.value) end,
        })
    end

    local function resolve_track(doc, mode_decl, expr)
        return U.match(expr, {
            AutoTrack = function() return T.DesignResolved.AutoTrack() end,
            PxTrack = function(v) return T.DesignResolved.PxTrack(resolve_number_expr(doc, mode_decl, v.value, {})) end,
            ContentTrack = function() return T.DesignResolved.ContentTrack() end,
            FlexTrack = function(v) return T.DesignResolved.FlexTrack(v.weight) end,
        })
    end

    local function resolve_insets(doc, mode_decl, expr)
        return T.UiCore.Insets(
            resolve_number_expr(doc, mode_decl, expr.top, {}),
            resolve_number_expr(doc, mode_decl, expr.right, {}),
            resolve_number_expr(doc, mode_decl, expr.bottom, {}),
            resolve_number_expr(doc, mode_decl, expr.left, {})
        )
    end

    local function resolve_corners(doc, mode_decl, expr)
        return T.UiCore.Corners(
            resolve_number_expr(doc, mode_decl, expr.top_left, {}),
            resolve_number_expr(doc, mode_decl, expr.top_right, {}),
            resolve_number_expr(doc, mode_decl, expr.bottom_right, {}),
            resolve_number_expr(doc, mode_decl, expr.bottom_left, {})
        )
    end

    local function resolve_aspect(doc, mode_decl, expr)
        return T.UiCore.Aspect(
            resolve_number_expr(doc, mode_decl, expr.width, {}),
            resolve_number_expr(doc, mode_decl, expr.height, {})
        )
    end

    local function resolve_point(doc, mode_decl, expr)
        return T.UiCore.Point(
            resolve_number_expr(doc, mode_decl, expr.x, {}),
            resolve_number_expr(doc, mode_decl, expr.y, {})
        )
    end

    local function resolve_brush(doc, mode_decl, expr)
        return U.match(expr, {
            Solid = function(v)
                return T.UiCore.Solid(resolve_color_expr(doc, mode_decl, v.color, {}))
            end,
            LinearGradient = function(v)
                return T.UiCore.LinearGradient(
                    L(F.iter(v.stops):map(function(stop)
                        return T.UiCore.Stop(stop.t, resolve_color_expr(doc, mode_decl, stop.color, {}))
                    end):totable()),
                    resolve_point(doc, mode_decl, v.from),
                    resolve_point(doc, mode_decl, v.to)
                )
            end,
            RadialGradient = function(v)
                return T.UiCore.RadialGradient(
                    L(F.iter(v.stops):map(function(stop)
                        return T.UiCore.Stop(stop.t, resolve_color_expr(doc, mode_decl, stop.color, {}))
                    end):totable()),
                    resolve_point(doc, mode_decl, v.center),
                    resolve_number_expr(doc, mode_decl, v.radius, {})
                )
            end,
        })
    end

    local function resolve_layout_patch(doc, mode_decl, patch)
        return T.DesignResolved.LayoutPatch(
            option_map(patch.width, function(v)
                return T.DesignResolved.SizeSpec(
                    resolve_measure(doc, mode_decl, v.min),
                    resolve_measure(doc, mode_decl, v.preferred),
                    resolve_measure(doc, mode_decl, v.max)
                )
            end),
            option_map(patch.height, function(v)
                return T.DesignResolved.SizeSpec(
                    resolve_measure(doc, mode_decl, v.min),
                    resolve_measure(doc, mode_decl, v.preferred),
                    resolve_measure(doc, mode_decl, v.max)
                )
            end),
            option_map(patch.position, function(pos)
                return U.match(pos, {
                    InFlow = function() return T.DesignResolved.InFlow() end,
                    Absolute = function(v)
                        return T.DesignResolved.Absolute(
                            resolve_edge(doc, mode_decl, v.left),
                            resolve_edge(doc, mode_decl, v.top),
                            resolve_edge(doc, mode_decl, v.right),
                            resolve_edge(doc, mode_decl, v.bottom)
                        )
                    end,
                    Anchored = function(v)
                        return T.DesignResolved.Anchored(
                            v.target,
                            v.self_x,
                            v.self_y,
                            v.target_x,
                            v.target_y,
                            resolve_number_expr(doc, mode_decl, v.dx, {}),
                            resolve_number_expr(doc, mode_decl, v.dy, {})
                        )
                    end,
                })
            end),
            patch.flow,
            option_map(patch.grid, function(v)
                return T.DesignResolved.GridTemplate(
                    L(F.iter(v.columns):map(function(track) return resolve_track(doc, mode_decl, track) end):totable()),
                    L(F.iter(v.rows):map(function(track) return resolve_track(doc, mode_decl, track) end):totable()),
                    resolve_number_expr(doc, mode_decl, v.column_gap, {}),
                    resolve_number_expr(doc, mode_decl, v.row_gap, {}),
                    v.auto_flow
                )
            end),
            patch.cell,
            patch.main_align,
            patch.cross_align,
            option_map(patch.padding, function(v) return resolve_insets(doc, mode_decl, v) end),
            option_map(patch.margin, function(v) return resolve_insets(doc, mode_decl, v) end),
            option_map(patch.gap, function(v) return resolve_number_expr(doc, mode_decl, v, {}) end),
            patch.overflow_x,
            patch.overflow_y,
            option_map(patch.aspect, function(v) return resolve_aspect(doc, mode_decl, v) end)
        )
    end

    local function resolve_paint_patch(doc, mode_decl, patch)
        return T.DesignResolved.PaintPatch(L(F.iter(patch.ops):map(function(op)
            return U.match(op, {
                Box = function(v)
                    return T.DesignResolved.Box(
                        resolve_brush(doc, mode_decl, v.fill),
                        option_map(v.stroke, function(s) return resolve_brush(doc, mode_decl, s) end),
                        resolve_number_expr(doc, mode_decl, v.stroke_width, {}),
                        v.align,
                        resolve_corners(doc, mode_decl, v.corners)
                    )
                end,
                Shadow = function(v)
                    return T.DesignResolved.Shadow(
                        resolve_brush(doc, mode_decl, v.brush),
                        resolve_number_expr(doc, mode_decl, v.blur, {}),
                        resolve_number_expr(doc, mode_decl, v.spread, {}),
                        resolve_number_expr(doc, mode_decl, v.dx, {}),
                        resolve_number_expr(doc, mode_decl, v.dy, {}),
                        v.kind,
                        resolve_corners(doc, mode_decl, v.corners)
                    )
                end,
                Clip = function(v)
                    return T.DesignResolved.Clip(resolve_corners(doc, mode_decl, v.corners))
                end,
                Opacity = function(v)
                    return T.DesignResolved.Opacity(resolve_number_expr(doc, mode_decl, v.value, {}))
                end,
                Transform = function(v)
                    return T.DesignResolved.Transform(v.xform)
                end,
                Blend = function(v)
                    return T.DesignResolved.Blend(v.mode)
                end,
                CustomPaint = function(v)
                    return T.DesignResolved.CustomPaint(v.kind, v.payload)
                end,
            })
        end):totable()))
    end

    local function resolve_content_patch(doc, mode_decl, patch)
        return U.match(patch, {
            NoContent = function()
                return T.DesignResolved.NoContent()
            end,
            TextContent = function(v)
                return T.DesignResolved.TextContent(
                    resolve_text_style_expr(doc, mode_decl, v.style, {}),
                    v.layout
                )
            end,
            ImageContent = function(v)
                return T.DesignResolved.ImageContent(v.style)
            end,
        })
    end

    local function resolve_affordance_patch(patch)
        return T.DesignResolved.AffordancePatch(
            patch.hit and U.match(patch.hit, {
                HitNone = function() return T.DesignResolved.HitNone() end,
                HitSelf = function() return T.DesignResolved.HitSelf() end,
                HitSelfAndChildren = function() return T.DesignResolved.HitSelfAndChildren() end,
                HitChildrenOnly = function() return T.DesignResolved.HitChildrenOnly() end,
            }) or nil,
            patch.focus and U.match(patch.focus, {
                NoFocus = function() return T.DesignResolved.NoFocus() end,
                Focusable = function(v) return T.DesignResolved.Focusable(v.mode, v.order) end,
            }) or nil,
            patch.hover_cursor,
            patch.scroll and T.DesignResolved.Scrollable(patch.scroll.axis) or nil,
            patch.edit and T.DesignResolved.Editable(patch.edit.multiline, patch.edit.read_only) or nil,
            patch.drag_drop and U.match(patch.drag_drop, {
                Draggable = function(v) return T.DesignResolved.Draggable(v.payload_kind) end,
                DropTarget = function(v) return T.DesignResolved.DropTarget(v.policy) end,
            }) or nil
        )
    end

    local function resolve_accessibility_patch(patch)
        return T.DesignResolved.AccessibilityPatch(
            patch.role,
            patch.label,
            patch.description,
            patch.hidden
        )
    end

    local function resolve_patch(doc, mode_decl, patch)
        return T.DesignResolved.Patch(
            option_map(patch.layout, function(v) return resolve_layout_patch(doc, mode_decl, v) end),
            option_map(patch.paint, function(v) return resolve_paint_patch(doc, mode_decl, v) end),
            option_map(patch.content, function(v) return resolve_content_patch(doc, mode_decl, v) end),
            option_map(patch.affordance, resolve_affordance_patch),
            option_map(patch.accessibility, resolve_accessibility_patch)
        )
    end

    local function resolve_recipe(doc, mode_decl, recipe)
        return T.DesignResolved.Recipe(
            recipe.id,
            recipe.name,
            recipe.root_slot,
            L(F.iter(recipe.slots):map(function(slot)
                return T.DesignResolved.Slot(
                    slot.id,
                    slot.name,
                    slot.kind,
                    slot.element_role,
                    slot.flags,
                    slot.children,
                    resolve_patch(doc, mode_decl, slot.base)
                )
            end):totable()),
            L(F.iter(recipe.variant_axes):map(function(axis)
                return T.DesignResolved.VariantAxis(axis.id, axis.name, axis.required,
                    L(F.iter(axis.values):map(function(value)
                        return T.DesignResolved.VariantValue(value.id, value.name)
                    end):totable())
                )
            end):totable()),
            L(F.iter(recipe.rules):map(function(rule)
                return U.match(rule, {
                    VariantRule = function(v)
                        return T.DesignResolved.VariantRule(
                            v.when,
                            L(F.iter(v.patches):map(function(slot_patch)
                                return T.DesignResolved.SlotPatch(slot_patch.slot, resolve_patch(doc, mode_decl, slot_patch.patch))
                            end):totable())
                        )
                    end,
                    StateRule = function(v)
                        return T.DesignResolved.StateRule(
                            v.when,
                            L(F.iter(v.patches):map(function(slot_patch)
                                return T.DesignResolved.SlotPatch(slot_patch.slot, resolve_patch(doc, mode_decl, slot_patch.patch))
                            end):totable())
                        )
                    end,
                })
            end):totable()),
            L(F.iter(recipe.constraints):map(function(constraint)
                return U.match(constraint, {
                    RequireSlot = function(v) return T.DesignResolved.RequireSlot(v.id, v.slot) end,
                    RequireVariantAxis = function(v) return T.DesignResolved.RequireVariantAxis(v.id, v.axis) end,
                    ForbidVariantCombo = function(v) return T.DesignResolved.ForbidVariantCombo(v.id, v.when) end,
                    RequireSlotContent = function(v) return T.DesignResolved.RequireSlotContent(v.id, v.slot) end,
                    RequireStateRule = function(v) return T.DesignResolved.RequireStateRule(v.id, v.state, v.slot) end,
                    ForbidLiteralColorInSlot = function(v) return T.DesignResolved.ForbidLiteralColorInSlot(v.id, v.slot) end,
                    ForbidLiteralNumberInSlot = function(v) return T.DesignResolved.ForbidLiteralNumberInSlot(v.id, v.slot, v.kind) end,
                })
            end):totable())
        )
    end

    local function resolve_mode(doc, mode_decl)
        return T.DesignResolved.Mode(
            mode_decl.id,
            mode_decl.name,
            resolved_tokens(doc, mode_decl),
            resolved_roles(doc, mode_decl),
            L(F.iter(doc.recipes):map(function(recipe)
                return resolve_recipe(doc, mode_decl, recipe)
            end):totable())
        )
    end

    local function resolve_theme(doc, theme_decl)
        return T.DesignResolved.Theme(
            theme_decl.id,
            theme_decl.name,
            theme_decl.default_mode,
            L(F.iter(theme_decl.modes):map(function(mode_decl)
                return resolve_mode(doc, mode_decl)
            end):totable())
        )
    end

    local function resolve_policy(policy)
        return U.match(policy, {
            RequireThemeCoverage = function(v) return T.DesignResolved.RequireThemeCoverage(v.id) end,
            RequireRoleCoverage = function(v) return T.DesignResolved.RequireRoleCoverage(v.id) end,
            ForbidLiteralColors = function(v) return T.DesignResolved.ForbidLiteralColors(v.id) end,
            ForbidLiteralNumbers = function(v) return T.DesignResolved.ForbidLiteralNumbers(v.id, v.kind) end,
            ForbidUndeclaredVariants = function(v) return T.DesignResolved.ForbidUndeclaredVariants(v.id) end,
            ForbidUndeclaredSlots = function(v) return T.DesignResolved.ForbidUndeclaredSlots(v.id) end,
            RequireAccessibleText = function(v) return T.DesignResolved.RequireAccessibleText(v.id) end,
        })
    end

    T.DesignDecl.Document.resolve = U.transition(function(document)
        if document.default_theme then
            find_theme(document, document.default_theme)
        end

        return T.DesignResolved.Document(
            document.version,
            document.default_theme,
            L(F.iter(document.themes):map(function(theme)
                return resolve_theme(document, theme)
            end):totable()),
            L(F.iter(document.policies):map(resolve_policy):totable())
        )
    end)
end

return Resolve
