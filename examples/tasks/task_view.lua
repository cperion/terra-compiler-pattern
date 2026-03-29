local U = require("unit")
local F = require("fun")
local Codec = require("examples.tasks.tasks_command_codec")

return function(T)
    local List = require("asdl").List

local function L(xs)
        return List(xs or {})
    end

    local function chain_lists(lists)
        local out = {}
        for _, xs in ipairs(lists) do
            for _, v in ipairs(xs) do out[#out + 1] = v end
        end
        return L(out)
    end

    local function status_code(status)
        return U.match(status, {
            Todo = function() return 1 end,
            InProgress = function() return 2 end,
            Blocked = function() return 3 end,
            Done = function() return 4 end,
        })
    end

    local function priority_code(priority)
        return U.match(priority, {
            NoPriority = function() return 1 end,
            Low = function() return 2 end,
            Medium = function() return 3 end,
            High = function() return 4 end,
        })
    end

    local function command_ref(command)
        return Codec.encode(T, command)
    end

    local function eid(n)
        return T.UiCore.ElementId(n)
    end

    local function scoped(base, value, slot)
        return base + value * 1000 + slot
    end

    local function project_sem(ref)
        return T.UiCore.SemanticRef(1, ref.value)
    end

    local function task_sem(ref)
        return T.UiCore.SemanticRef(2, ref.value)
    end

    local function tag_sem(ref)
        return T.UiCore.SemanticRef(3, ref.value)
    end

    local function color(r, g, b, a)
        return T.UiCore.Color(r, g, b, a or 1.0)
    end

    local BG = color(0.06, 0.08, 0.11, 1.0)
    local SURFACE = color(0.10, 0.12, 0.16, 1.0)
    local SURFACE_ALT = color(0.13, 0.15, 0.20, 1.0)
    local SURFACE_HI = color(0.17, 0.20, 0.26, 1.0)
    local BORDER = color(0.24, 0.28, 0.35, 1.0)
    local TEXT = color(0.96, 0.98, 1.0, 1.0)
    local MUTED = color(0.69, 0.75, 0.82, 1.0)
    local ACCENT = color(0.38, 0.60, 0.98, 1.0)
    local ACCENT_SOFT = color(0.17, 0.28, 0.44, 1.0)
    local DANGER = color(0.85, 0.31, 0.36, 1.0)
    local SHADOW = color(0, 0, 0, 0.32)
    local SCRIM = color(0.02, 0.03, 0.05, 0.72)

    local function brush_from(color_value)
        return T.UiCore.Solid(color_value)
    end

    local function rounded(_radius)
        return T.UiCore.Corners(0, 0, 0, 0)
    end

    local function text_style(color_value, size_px)
        return T.UiCore.TextStyle(nil, size_px or 14, nil, nil, nil, nil, color_value)
    end

    local function text_layout()
        return T.UiCore.TextLayout(T.UiCore.WrapWord(), T.UiCore.ClipText(), T.UiCore.TextStart(), 4)
    end

    local function no_wrap_layout()
        return T.UiCore.TextLayout(T.UiCore.NoWrap(), T.UiCore.ClipText(), T.UiCore.TextStart(), 1)
    end

    local function insets(all)
        return T.UiCore.Insets(all, all, all, all)
    end

    local function insets_xy(x, y)
        return T.UiCore.Insets(y, x, y, x)
    end

    local function measure_px(n)
        return T.UiCore.SizeSpec(T.UiCore.Px(n), T.UiCore.Px(n), T.UiCore.Px(n))
    end

    local function measure_percent(n)
        return T.UiCore.SizeSpec(T.UiCore.Percent(n), T.UiCore.Percent(n), T.UiCore.Percent(n))
    end

    local function auto_size()
        return T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto())
    end

    local function flex_size(weight)
        return T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Flex(weight or 1), T.UiCore.Flex(weight or 1))
    end

    local function base_layout(flow, padding, margin, gap)
        return T.UiDecl.Layout(
            auto_size(),
            auto_size(),
            T.UiCore.InFlow(),
            flow or T.UiCore.None(),
            nil,
            nil,
            T.UiCore.Start(),
            T.UiCore.CrossStart(),
            padding or T.UiCore.Insets(0, 0, 0, 0),
            margin or T.UiCore.Insets(0, 0, 0, 0),
            gap or 12,
            T.UiCore.Visible(),
            T.UiCore.Visible(),
            nil
        )
    end

    local function surface_paint(fill_color, stroke_color, radius, _shadow_alpha)
        return T.UiDecl.Paint(L {
            T.UiDecl.Box(
                brush_from(fill_color),
                stroke_color and brush_from(stroke_color) or nil,
                stroke_color and 1 or 0,
                T.UiCore.CenterStroke(),
                rounded(radius)
            )
        })
    end

    local function background_paint()
        return T.UiDecl.Paint(L {
            T.UiDecl.Box(brush_from(BG), nil, 0, T.UiCore.CenterStroke(), rounded(0))
        })
    end

    local function panel_paint()
        return surface_paint(SURFACE, BORDER, 18, 0.22)
    end

    local function panel_alt_paint()
        return surface_paint(SURFACE_ALT, BORDER, 18, 0.18)
    end

    local function input_paint()
        return surface_paint(SURFACE_HI, BORDER, 14, 0.10)
    end

    local function button_paint(active)
        if active then
            return surface_paint(ACCENT, color(0.56, 0.74, 1.0, 1.0), 14, 0.18)
        end
        return surface_paint(SURFACE_HI, BORDER, 14, 0.10)
    end

    local function primary_button_paint()
        return surface_paint(ACCENT, color(0.56, 0.74, 1.0, 1.0), 14, 0.18)
    end

    local function danger_button_paint()
        return surface_paint(DANGER, color(0.98, 0.58, 0.62, 1.0), 14, 0.18)
    end

    local function task_row_paint(selected)
        if selected then
            return surface_paint(ACCENT_SOFT, color(0.46, 0.68, 1.0, 1.0), 18, 0.22)
        end
        return surface_paint(SURFACE_ALT, BORDER, 18, 0.14)
    end

    local function chip_paint(fill_color)
        return surface_paint(fill_color, nil, 999, 0)
    end

    local function overlay_scrim_paint()
        return T.UiDecl.Paint(L {
            T.UiDecl.Box(brush_from(SCRIM), nil, 0, T.UiCore.CenterStroke(), rounded(0))
        })
    end

    local function empty_behavior()
        return T.UiDecl.Behavior(T.UiDecl.HitNone(), T.UiDecl.NotFocusable(), L(), nil, L(), nil, L())
    end

    local function behavior_button(command)
        return T.UiDecl.Behavior(
            T.UiDecl.HitSelf(),
            T.UiDecl.Focusable(T.UiCore.ClickFocus(), nil),
            L { T.UiDecl.Press(T.UiCore.Primary(), 1, command) },
            nil,
            L(),
            nil,
            L()
        )
    end

    local function behavior_input(model, multiline)
        return T.UiDecl.Behavior(
            T.UiDecl.HitSelf(),
            T.UiDecl.Focusable(T.UiCore.TextFocus(), nil),
            L(),
            nil,
            L(),
            T.UiDecl.EditRule(model, multiline, false, nil),
            L()
        )
    end

    local function accessibility(role, label)
        return T.UiDecl.Accessibility(role, label, nil, false, 0)
    end

    local function element(idn, semantic_ref, debug_name, role, layout, paint, content, behavior, a11y, children)
        return T.UiDecl.Element(
            eid(idn),
            semantic_ref,
            debug_name,
            role,
            T.UiDecl.Flags(true, true),
            layout,
            paint,
            content,
            behavior,
            a11y,
            children or L()
        )
    end

    local function text_element(idn, text, color_value, size_px, semantic_ref)
        return element(
            idn,
            semantic_ref,
            nil,
            T.UiCore.TextRole(),
            base_layout(T.UiCore.None(), T.UiCore.Insets(0, 0, 0, 0), T.UiCore.Insets(0, 0, 0, 0), 0),
            T.UiDecl.Paint(L()),
            T.UiDecl.Text(T.UiCore.TextValue(text), text_style(color_value or TEXT, size_px or 14), no_wrap_layout()),
            empty_behavior(),
            accessibility(T.UiCore.AccText(), text),
            L()
        )
    end

    local function wrapped_text_element(idn, text, color_value, size_px, semantic_ref)
        local el = element(
            idn,
            semantic_ref,
            nil,
            T.UiCore.TextRole(),
            base_layout(T.UiCore.None(), T.UiCore.Insets(0, 0, 0, 0), T.UiCore.Insets(0, 0, 0, 0), 0),
            T.UiDecl.Paint(L()),
            T.UiDecl.Text(T.UiCore.TextValue(text), text_style(color_value or TEXT, size_px or 14), text_layout()),
            empty_behavior(),
            accessibility(T.UiCore.AccText(), text),
            L()
        )
        return U.with(el, {
            layout = U.with(el.layout, {
                width = flex_size(1),
                height = auto_size(),
            })
        })
    end

    local function container(idn, debug_name, role, semantic_ref, children, flow, paint)
        return element(
            idn,
            semantic_ref,
            debug_name,
            role or T.UiCore.View(),
            base_layout(flow or T.UiCore.Column(), insets(16), T.UiCore.Insets(0, 0, 0, 0), 12),
            paint or panel_paint(),
            T.UiDecl.NoContent(),
            empty_behavior(),
            accessibility(T.UiCore.AccGroup(), debug_name),
            children or L()
        )
    end

    local function group(idn, debug_name, role, semantic_ref, children, flow)
        return element(
            idn,
            semantic_ref,
            debug_name,
            role or T.UiCore.View(),
            base_layout(flow or T.UiCore.Column(), T.UiCore.Insets(0, 0, 0, 0), T.UiCore.Insets(0, 0, 0, 0), 12),
            T.UiDecl.Paint(L()),
            T.UiDecl.NoContent(),
            empty_behavior(),
            accessibility(T.UiCore.AccGroup(), debug_name),
            children or L()
        )
    end

    local function with_layout(element_value, patch)
        return U.with(element_value, {
            layout = U.with(element_value.layout, patch)
        })
    end

    local function with_size(element_value, width, height)
        return with_layout(element_value, {
            width = width or element_value.layout.width,
            height = height or element_value.layout.height,
        })
    end

    local function scroll_container(idn, debug_name, semantic_ref, children, model)
        return element(
            idn,
            semantic_ref,
            debug_name,
            T.UiCore.ScrollPort(),
            base_layout(T.UiCore.Column(), insets(18), T.UiCore.Insets(0, 0, 0, 0), 14),
            panel_paint(),
            T.UiDecl.NoContent(),
            T.UiDecl.Behavior(
                T.UiDecl.HitSelfAndChildren(),
                T.UiDecl.NotFocusable(),
                L(),
                T.UiDecl.ScrollRule(T.UiCore.Vertical(), model),
                L(),
                nil,
                L()
            ),
            accessibility(T.UiCore.AccScrollArea(), debug_name),
            children or L()
        )
    end

    local function button_base(idn, label, command, semantic_ref, paint, text_color)
        return element(
            idn,
            semantic_ref,
            nil,
            T.UiCore.View(),
            base_layout(T.UiCore.None(), insets_xy(12, 10), T.UiCore.Insets(0, 0, 0, 0), 0),
            paint,
            T.UiDecl.Text(T.UiCore.TextValue(label), text_style(text_color or TEXT, 14), no_wrap_layout()),
            behavior_button(command),
            accessibility(T.UiCore.AccButton(), label),
            L()
        )
    end

    local function button(idn, label, command, semantic_ref, active)
        return button_base(idn, label, command, semantic_ref, button_paint(active), TEXT)
    end

    local function primary_button(idn, label, command, semantic_ref)
        return button_base(idn, label, command, semantic_ref, primary_button_paint(), TEXT)
    end

    local function danger_button(idn, label, command, semantic_ref)
        return button_base(idn, label, command, semantic_ref, danger_button_paint(), TEXT)
    end

    local function input(idn, label, model, value, multiline)
        return with_size(element(
            idn,
            nil,
            label,
            T.UiCore.InputField(),
            base_layout(T.UiCore.None(), insets_xy(12, 12), T.UiCore.Insets(0, 0, 0, 0), 0),
            input_paint(),
            T.UiDecl.Text(T.UiCore.TextValue(value), text_style(TEXT, 14), text_layout()),
            behavior_input(model, multiline),
            accessibility(T.UiCore.AccTextbox(), label),
            L()
        ), flex_size(1), auto_size())
    end

    local function next_status(status)
        return U.match(status, {
            Todo = function() return T.TaskCore.InProgress() end,
            InProgress = function() return T.TaskCore.Blocked() end,
            Blocked = function() return T.TaskCore.Done() end,
            Done = function() return T.TaskCore.Todo() end,
        })
    end

    local function next_priority(priority)
        return U.match(priority, {
            NoPriority = function() return T.TaskCore.Low() end,
            Low = function() return T.TaskCore.Medium() end,
            Medium = function() return T.TaskCore.High() end,
            High = function() return T.TaskCore.NoPriority() end,
        })
    end

    local function status_label(status)
        return U.match(status, {
            Todo = function() return "Todo" end,
            InProgress = function() return "In Progress" end,
            Blocked = function() return "Blocked" end,
            Done = function() return "Done" end,
        })
    end

    local function priority_label(priority)
        return U.match(priority, {
            NoPriority = function() return "No Priority" end,
            Low = function() return "Low" end,
            Medium = function() return "Medium" end,
            High = function() return "High" end,
        })
    end

    local function sort_label(sort)
        return U.match(sort, {
            ManualOrder = function() return "Manual" end,
            PriorityOrder = function() return "Priority" end,
            TitleOrder = function() return "Title" end,
        })
    end

    T.TaskView.WorkspaceHeader.lower = U.transition(function(self)
        return with_size(group(900000, "workspace-header", T.UiCore.View(), nil, L {
            text_element(900010, self.name, TEXT, 26, nil),
            wrapped_text_element(900011, "A focused workspace for planning, editing, and shipping work.", MUTED, 13, nil),
        }, T.UiCore.Column()), flex_size(1), auto_size())
    end)

    T.TaskView.ProjectItem.lower = U.transition(function(self)
        local label = self.name
        local meta = tostring(self.open_count) .. " open · " .. tostring(self.done_count) .. " done"
        local body = group(scoped(1000000, self.id.value, 0), "project-item-body", T.UiCore.View(), project_sem(self.id), L {
            text_element(scoped(1000000, self.id.value, 10), label, TEXT, 15, project_sem(self.id)),
            text_element(scoped(1000000, self.id.value, 20), meta, MUTED, 12, nil),
        }, T.UiCore.Column())

        local card = element(
            scoped(1000000, self.id.value, 30),
            project_sem(self.id),
            "project-item",
            T.UiCore.View(),
            base_layout(T.UiCore.Column(), insets(14), T.UiCore.Insets(0, 0, 0, 0), 4),
            task_row_paint(self.selected),
            T.UiDecl.NoContent(),
            behavior_button(command_ref(T.TaskCommand.SelectProject(self.id))),
            accessibility(T.UiCore.AccButton(), self.name),
            L { body }
        )
        return card
    end)

    T.TaskView.StatusFilter.lower = U.transition(function(self)
        local label = status_label(self.status) .. " · " .. tostring(self.count)
        return button(20000 + status_code(self.status), label, command_ref(T.TaskCommand.ToggleStatusFilter(self.status)), nil, self.enabled)
    end)

    T.TaskView.TagFilter.lower = U.transition(function(self)
        local label = self.name .. " · " .. tostring(self.count)
        return button(scoped(2000000, self.id.value, 0), label, command_ref(T.TaskCommand.ToggleTagFilter(self.id)), tag_sem(self.id), self.enabled)
    end)

    T.TaskView.FilterPanel.lower = U.transition(function(self)
        local controls = chain_lists {
            L { input(22100 + self.query_model.value, "Search tasks", self.query_model, self.query, false) },
            L { text_element(22110, "Status", MUTED, 12, nil) },
            L(F.iter(self.statuses):map(function(v) return v:lower() end):totable()),
            L { text_element(22111, "Tags", MUTED, 12, nil) },
            L(F.iter(self.tags):map(function(v) return v:lower() end):totable()),
            L {
                button(22120, self.include_done and "Showing completed" or "Hiding completed", command_ref(T.TaskCommand.SetIncludeDone(not self.include_done)), nil, self.include_done),
                button(22121, "Sort: " .. sort_label(self.sort), command_ref(T.TaskCommand.SetSort(self.sort.kind == "ManualOrder" and T.TaskCore.PriorityOrder() or (self.sort.kind == "PriorityOrder" and T.TaskCore.TitleOrder() or T.TaskCore.ManualOrder()))), nil, false),
            },
        }
        local panel = container(22130, "filter-panel", T.UiCore.View(), nil, chain_lists {
            L {
                text_element(22131, "Refine", TEXT, 17, nil),
                wrapped_text_element(22132, "Use search, status, and tags to narrow the worklist.", MUTED, 12, nil),
            },
            controls,
        }, T.UiCore.Column(), panel_alt_paint())
        return with_size(panel, flex_size(1), auto_size())
    end)

    T.TaskView.Sidebar.lower = U.transition(function(self)
        local project_children = L(F.iter(self.projects):map(function(v) return v:lower() end):totable())
        local projects_group = group(900100, "projects-group", T.UiCore.ListHost(), nil, chain_lists {
            L { text_element(900101, "Projects", MUTED, 12, nil) },
            project_children,
        }, T.UiCore.Column())

        local sidebar = container(900110, "sidebar", T.UiCore.ListHost(), nil, chain_lists {
            L { self.workspace:lower() },
            L { projects_group },
            L { self.filter:lower() },
        }, T.UiCore.Column(), panel_paint())

        return with_size(with_layout(sidebar, { padding = insets(20), gap = 18 }), measure_px(320), flex_size(1))
    end)

    T.TaskView.ProjectHeader.lower = U.transition(function(self)
        local summary = group(scoped(3000000, self.id.value, 0), "project-header-summary", T.UiCore.View(), project_sem(self.id), L {
            text_element(scoped(3000000, self.id.value, 10), self.name, TEXT, 28, project_sem(self.id)),
            text_element(scoped(3000000, self.id.value, 20), tostring(self.visible_count) .. " visible · " .. tostring(self.total_count) .. " total", MUTED, 13, nil),
        }, T.UiCore.Column())

        local actions = group(scoped(3000000, self.id.value, 25), "project-header-actions", T.UiCore.View(), nil, L {
            primary_button(scoped(3000000, self.id.value, 30), "New Task", command_ref(T.TaskCommand.BeginCreateTask(self.id)), project_sem(self.id)),
        }, T.UiCore.Row())

        local header = group(scoped(3000000, self.id.value, 40), "project-header-shell", T.UiCore.View(), project_sem(self.id), L {
            summary,
            actions,
        }, T.UiCore.Row())

        return with_size(with_layout(container(scoped(3000000, self.id.value, 50), "project-header", T.UiCore.View(), project_sem(self.id), L { header }, T.UiCore.Column(), panel_paint()), {
            cross_align = T.UiCore.Stretch(),
            gap = 8,
        }), flex_size(1), auto_size())
    end)

    T.TaskView.TagChip.lower = U.transition(function(self)
        return element(
            32000 + self.key,
            tag_sem(self.id),
            nil,
            T.UiCore.View(),
            base_layout(T.UiCore.None(), insets_xy(10, 6), T.UiCore.Insets(0, 0, 0, 0), 0),
            chip_paint(self.color),
            T.UiDecl.Text(T.UiCore.TextValue(self.name), text_style(color(0.04, 0.05, 0.08, 0.92), 12), no_wrap_layout()),
            empty_behavior(),
            accessibility(T.UiCore.AccText(), self.name),
            L()
        )
    end)

    T.TaskView.TaskRow.lower = U.transition(function(self)
        local tags = #self.tags > 0 and L {
            with_layout(group(scoped(4000000, self.id.value, 25), "task-row-tags", T.UiCore.View(), nil, L(F.iter(self.tags):map(function(tag) return tag:lower() end):totable()), T.UiCore.Row()), {
                gap = 8,
            })
        } or L()

        local children = chain_lists {
            L { text_element(scoped(4000000, self.id.value, 10), self.title, TEXT, 16, task_sem(self.id)) },
            self.notes_preview ~= "" and L { wrapped_text_element(scoped(4000000, self.id.value, 20), self.notes_preview, MUTED, 13, nil) } or L(),
            tags,
        }

        local card = element(
            scoped(4000000, self.id.value, 0),
            task_sem(self.id),
            "task-row",
            T.UiCore.View(),
            base_layout(T.UiCore.Column(), insets(16), T.UiCore.Insets(0, 0, 0, 0), 10),
            task_row_paint(self.selected),
            T.UiDecl.NoContent(),
            behavior_button(command_ref(T.TaskCommand.SelectTask(self.id))),
            accessibility(T.UiCore.AccButton(), self.title),
            children
        )

        return with_size(with_layout(card, { margin = T.UiCore.Insets(0, 0, 10, 0) }), flex_size(1), auto_size())
    end)

    T.TaskView.TaskCard.lower = U.transition(function(self)
        local status_next = next_status(self.status)
        local priority_next = next_priority(self.priority)
        local tags = #self.tags > 0 and L {
            with_layout(group(scoped(5000000, self.id.value, 5), "task-card-tags", T.UiCore.View(), nil, L(F.iter(self.tags):map(function(tag) return tag:lower() end):totable()), T.UiCore.Row()), {
                gap = 8,
            })
        } or L()

        local children = chain_lists {
            L {
                text_element(scoped(5000000, self.id.value, 10), self.title, TEXT, 24, task_sem(self.id)),
                wrapped_text_element(scoped(5000000, self.id.value, 20), self.notes, MUTED, 14, nil),
            },
            tags,
            L {
                button(scoped(5000000, self.id.value, 30), "Status · " .. status_label(self.status), command_ref(T.TaskCommand.SetTaskStatus(self.id, status_next)), task_sem(self.id), false),
                button(scoped(5000000, self.id.value, 40), "Priority · " .. priority_label(self.priority), command_ref(T.TaskCommand.SetTaskPriority(self.id, priority_next)), task_sem(self.id), false),
            },
            L {
                primary_button(scoped(5000000, self.id.value, 50), "Edit task", command_ref(T.TaskCommand.BeginEditTask(self.id)), task_sem(self.id)),
                danger_button(scoped(5000000, self.id.value, 60), "Delete", command_ref(T.TaskCommand.RequestDeleteTask(self.id)), task_sem(self.id)),
            },
        }

        return with_size(container(scoped(5000000, self.id.value, 0), "task-card", T.UiCore.View(), task_sem(self.id), children, T.UiCore.Column(), panel_paint()), flex_size(1), auto_size())
    end)

    T.TaskView.DetailPane.lower = U.transition(function(self)
        return U.match(self, {
            NoDetail = function()
                return with_size(container(900200, "detail-empty", T.UiCore.View(), nil, L {
                    text_element(900210, "Nothing selected", TEXT, 22, nil),
                    wrapped_text_element(900220, "Choose a task from the list to inspect details and make changes.", MUTED, 14, nil),
                }, T.UiCore.Column(), panel_alt_paint()), flex_size(1), flex_size(1))
            end,
            TaskDetail = function(v)
                return v.task:lower()
            end,
        })
    end)

    T.TaskView.StatusChoice.lower = U.transition(function(self)
        local label = (self.selected and "● " or "○ ") .. status_label(self.status)
        return button(60000 + status_code(self.status), label, command_ref(T.TaskCommand.SetDraftStatus(self.status)), nil, self.selected)
    end)

    T.TaskView.PriorityChoice.lower = U.transition(function(self)
        local label = (self.selected and "● " or "○ ") .. priority_label(self.priority)
        return button(61000 + priority_code(self.priority), label, command_ref(T.TaskCommand.SetDraftPriority(self.priority)), nil, self.selected)
    end)

    T.TaskView.TagChoice.lower = U.transition(function(self)
        local label = (self.selected and "[x] " or "[ ] ") .. self.name
        return button(scoped(6000000, self.id.value, 0), label, command_ref(T.TaskCommand.ToggleDraftTag(self.id)), tag_sem(self.id), self.selected)
    end)

    T.TaskView.TaskEditorForm.lower = U.transition(function(self)
        local children = chain_lists {
            L {
                input(630000 + self.title_model.value, "Title", self.title_model, self.title, false),
                input(631000 + self.notes_model.value, "Notes", self.notes_model, self.notes, true),
            },
            L { text_element(900310, "Status", MUTED, 12, nil) },
            L(F.iter(self.statuses):map(function(v) return v:lower() end):totable()),
            L { text_element(900320, "Priority", MUTED, 12, nil) },
            L(F.iter(self.priorities):map(function(v) return v:lower() end):totable()),
            L { text_element(900330, "Tags", MUTED, 12, nil) },
            L(F.iter(self.tags):map(function(v) return v:lower() end):totable()),
        }
        return with_layout(container(900340, "task-editor-form", T.UiCore.View(), nil, children, T.UiCore.Column(), T.UiDecl.Paint(L())), {
            padding = T.UiCore.Insets(0, 0, 0, 0),
        })
    end)

    T.TaskView.TaskEditor.lower = U.transition(function(self)
        return U.match(self, {
            CreateTaskEditor = function(v)
                return with_layout(with_size(container(scoped(7000000, v.project.value, 0), "create-task-editor", T.UiCore.OverlayHost(), project_sem(v.project), L {
                    text_element(scoped(7000000, v.project.value, 10), "Create task", TEXT, 24, nil),
                    wrapped_text_element(scoped(7000000, v.project.value, 11), "Capture the intent, then refine status, priority, and tags.", MUTED, 13, nil),
                    v.form:lower(),
                    with_layout(group(scoped(7000000, v.project.value, 15), "create-task-actions", T.UiCore.View(), nil, L {
                        primary_button(scoped(7000000, v.project.value, 20), "Save", command_ref(T.TaskCommand.SubmitEditor()), nil),
                        button(scoped(7000000, v.project.value, 30), "Cancel", command_ref(T.TaskCommand.CancelOverlay()), nil, false),
                    }, T.UiCore.Row()), { gap = 10 }),
                }, T.UiCore.Column(), panel_paint()), measure_px(620), auto_size()), {
                    position = T.UiCore.Absolute(T.UiCore.EdgePercent(0.5), T.UiCore.EdgePx(72), T.UiCore.Unset(), T.UiCore.Unset()),
                    margin = T.UiCore.Insets(0, 0, 0, -310),
                })
            end,
            EditTaskEditor = function(v)
                return with_layout(with_size(container(scoped(8000000, v.task.value, 0), "edit-task-editor", T.UiCore.OverlayHost(), task_sem(v.task), L {
                    text_element(scoped(8000000, v.task.value, 10), "Edit task", TEXT, 24, nil),
                    wrapped_text_element(scoped(8000000, v.task.value, 11), "Update the details without losing the surrounding context.", MUTED, 13, nil),
                    v.form:lower(),
                    with_layout(group(scoped(8000000, v.task.value, 15), "edit-task-actions", T.UiCore.View(), nil, L {
                        primary_button(scoped(8000000, v.task.value, 20), "Save", command_ref(T.TaskCommand.SubmitEditor()), nil),
                        button(scoped(8000000, v.task.value, 30), "Cancel", command_ref(T.TaskCommand.CancelOverlay()), nil, false),
                    }, T.UiCore.Row()), { gap = 10 }),
                }, T.UiCore.Column(), panel_paint()), measure_px(620), auto_size()), {
                    position = T.UiCore.Absolute(T.UiCore.EdgePercent(0.5), T.UiCore.EdgePx(72), T.UiCore.Unset(), T.UiCore.Unset()),
                    margin = T.UiCore.Insets(0, 0, 0, -310),
                })
            end,
        })
    end)

    T.TaskView.DeleteDialog.lower = U.transition(function(self)
        return with_layout(with_size(container(scoped(9000000, self.task.value, 0), "delete-dialog", T.UiCore.OverlayHost(), task_sem(self.task), L {
            text_element(scoped(9000000, self.task.value, 10), self.heading, TEXT, 24, nil),
            wrapped_text_element(scoped(9000000, self.task.value, 20), self.message, MUTED, 14, nil),
            with_layout(group(scoped(9000000, self.task.value, 25), "delete-dialog-actions", T.UiCore.View(), nil, L {
                danger_button(scoped(9000000, self.task.value, 30), "Delete", command_ref(T.TaskCommand.ConfirmDelete()), task_sem(self.task)),
                button(scoped(9000000, self.task.value, 40), "Cancel", command_ref(T.TaskCommand.CancelOverlay()), nil, false),
            }, T.UiCore.Row()), { gap = 10 }),
        }, T.UiCore.Column(), panel_paint()), measure_px(540), auto_size()), {
            position = T.UiCore.Absolute(T.UiCore.EdgePercent(0.5), T.UiCore.EdgePx(120), T.UiCore.Unset(), T.UiCore.Unset()),
            margin = T.UiCore.Insets(0, 0, 0, -270),
        })
    end)

    T.TaskView.Overlay.lower = U.transition(function(self)
        local child = U.match(self, {
            TaskEditorOverlay = function(v) return v.editor:lower() end,
            DeleteTaskOverlay = function(v) return v.dialog:lower() end,
        })

        local shell = container(900400, "overlay-shell", T.UiCore.OverlayHost(), nil, L { child }, T.UiCore.None(), overlay_scrim_paint())
        return with_layout(with_size(shell, measure_percent(1), measure_percent(1)), {
            padding = T.UiCore.Insets(0, 0, 0, 0),
            gap = 0,
        })
    end)

    T.TaskView.Content.lower = U.transition(function(self)
        return U.match(self, {
            NothingSelected = function(v)
                return with_size(container(900500, "content-empty", T.UiCore.View(), nil, L {
                    text_element(900510, v.title, TEXT, 28, nil),
                    wrapped_text_element(900520, v.message, MUTED, 15, nil),
                }, T.UiCore.Column(), panel_paint()), flex_size(1), flex_size(1))
            end,
            ProjectScreen = function(v)
                local task_list = with_size(scroll_container(scoped(10000000, v.project.id.value, 0), "task-list", project_sem(v.project.id), chain_lists {
                    L { v.project:lower() },
                    L(F.iter(v.tasks):map(function(task) return task:lower() end):totable()),
                }, v.task_list_scroll), measure_px(420), flex_size(1))

                local detail = with_size(scroll_container(scoped(10000000, v.project.id.value, 50), "detail-scroll", project_sem(v.project.id), L { v.detail:lower() }, v.detail_scroll), flex_size(1), flex_size(1))

                local layout_group = group(scoped(10000000, v.project.id.value, 90), "content-project", T.UiCore.View(), project_sem(v.project.id), L { task_list, detail }, T.UiCore.Row())
                return with_size(with_layout(layout_group, { gap = 20 }), flex_size(1), flex_size(1))
            end,
        })
    end)

    T.TaskView.Screen.lower = U.transition(function(self)
        local root = with_layout(container(900600, "screen", T.UiCore.View(), nil, L {
            self.sidebar:lower(),
            self.content:lower(),
        }, T.UiCore.Row(), background_paint()), {
            padding = insets(20),
            gap = 20,
        })

        return T.UiDecl.Document(
            1,
            L {
                T.UiDecl.Root(eid(900610), "task-screen", with_size(root, flex_size(1), flex_size(1)))
            },
            L(F.iter(self.overlays):enumerate():map(function(i, overlay)
                return T.UiDecl.Overlay(eid(900700 + i), "overlay", overlay:lower(), 100 + i, true, true)
            end):totable())
        )
    end)
end
