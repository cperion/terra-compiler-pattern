local U = require("unit")
local F = require("fun")
local Codec = require("examples.tasks.tasks_command_codec")

local Lower = {}
local unpack_fn = table.unpack or unpack

local function L(xs)
    return terralib.newlist(xs or {})
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

local function sort_code(sort)
    return U.match(sort, {
        ManualOrder = function() return 1 end,
        PriorityOrder = function() return 2 end,
        TitleOrder = function() return 3 end,
    })
end

local function command_ref(T, command)
    return Codec.encode(T, command)
end

local function eid(T, n)
    return T.UiCore.ElementId(n)
end

local function project_sem(T, ref)
    return T.UiCore.SemanticRef(1, ref.value)
end

local function task_sem(T, ref)
    return T.UiCore.SemanticRef(2, ref.value)
end

local function tag_sem(T, ref)
    return T.UiCore.SemanticRef(3, ref.value)
end

local function text_style(T, color, size_px)
    return T.UiCore.TextStyle(nil, size_px or 14, nil, nil, nil, nil, color)
end

local function text_layout(T)
    return T.UiCore.TextLayout(T.UiCore.WrapWord(), T.UiCore.ClipText(), T.UiCore.TextStart(), 4)
end

local function no_wrap_layout(T)
    return T.UiCore.TextLayout(T.UiCore.NoWrap(), T.UiCore.ClipText(), T.UiCore.TextStart(), 1)
end

local function insets(T, all)
    return T.UiCore.Insets(all, all, all, all)
end

local function measure_px(T, n)
    return T.UiCore.SizeSpec(T.UiCore.Px(n), T.UiCore.Px(n), T.UiCore.Px(n))
end

local function auto_size(T)
    return T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Auto(), T.UiCore.Auto())
end

local function flex_size(T, weight)
    return T.UiCore.SizeSpec(T.UiCore.Auto(), T.UiCore.Flex(weight or 1), T.UiCore.Flex(weight or 1))
end

local function base_layout(T, flow, padding, margin)
    return T.UiDecl.Layout(
        auto_size(T),
        auto_size(T),
        T.UiCore.InFlow(),
        flow or T.UiCore.None(),
        nil,
        nil,
        T.UiCore.Start(),
        T.UiCore.CrossStart(),
        padding or T.UiCore.Insets(0, 0, 0, 0),
        margin or T.UiCore.Insets(0, 0, 0, 0),
        8,
        T.UiCore.Visible(),
        T.UiCore.Visible(),
        nil
    )
end

local function brush(T, r, g, b, a)
    return T.UiCore.Solid(T.UiCore.Color(r, g, b, a or 1.0))
end

local function panel_paint(T)
    return T.UiDecl.Paint(L {
        T.UiDecl.Box(brush(T, 0.17, 0.18, 0.20, 1), nil, 0, T.UiCore.CenterStroke(), T.UiCore.Corners(0, 0, 0, 0))
    })
end

local function button_paint(T, active)
    return T.UiDecl.Paint(L {
        T.UiDecl.Box(active and brush(T, 0.28, 0.43, 0.72, 1) or brush(T, 0.24, 0.25, 0.28, 1), nil, 0, T.UiCore.CenterStroke(), T.UiCore.Corners(0, 0, 0, 0))
    })
end

local function behavior_button(T, command)
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

local function behavior_input(T, model, multiline)
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

local function empty_behavior(T)
    return T.UiDecl.Behavior(T.UiDecl.HitNone(), T.UiDecl.NotFocusable(), L(), nil, L(), nil, L())
end

local function accessibility(T, role, label)
    return T.UiDecl.Accessibility(role, label, nil, false, 0)
end

local function text_element(T, idn, text, color, size_px, semantic_ref)
    return T.UiDecl.Element(
        eid(T, idn),
        semantic_ref,
        nil,
        T.UiCore.TextRole(),
        T.UiDecl.Flags(true, true),
        base_layout(T, T.UiCore.None(), T.UiCore.Insets(0, 0, 0, 0), T.UiCore.Insets(0, 0, 0, 0)),
        T.UiDecl.Paint(L()),
        T.UiDecl.Text(T.UiCore.TextValue(text), text_style(T, color or T.UiCore.Color(0.95, 0.97, 1.0, 1.0), size_px or 14), no_wrap_layout(T)),
        empty_behavior(T),
        accessibility(T, T.UiCore.AccText(), text),
        L()
    )
end

local function wrapped_text_element(T, idn, text, color, size_px, semantic_ref)
    return T.UiDecl.Element(
        eid(T, idn),
        semantic_ref,
        nil,
        T.UiCore.TextRole(),
        T.UiDecl.Flags(true, true),
        base_layout(T, T.UiCore.None(), T.UiCore.Insets(0, 0, 0, 0), T.UiCore.Insets(0, 0, 0, 0)),
        T.UiDecl.Paint(L()),
        T.UiDecl.Text(T.UiCore.TextValue(text), text_style(T, color or T.UiCore.Color(0.95, 0.97, 1.0, 1.0), size_px or 14), text_layout(T)),
        empty_behavior(T),
        accessibility(T, T.UiCore.AccText(), text),
        L()
    )
end

local function container(T, idn, debug_name, role, semantic_ref, children, flow, paint)
    return T.UiDecl.Element(
        eid(T, idn),
        semantic_ref,
        debug_name,
        role or T.UiCore.View(),
        T.UiDecl.Flags(true, true),
        base_layout(T, flow or T.UiCore.Column(), insets(T, 8), T.UiCore.Insets(0, 0, 0, 0)),
        paint or panel_paint(T),
        T.UiDecl.NoContent(),
        empty_behavior(T),
        accessibility(T, T.UiCore.AccGroup(), debug_name),
        children or L()
    )
end

local function with_size(T, element, width, height)
    return U.with(element, {
        layout = U.with(element.layout, {
            width = width or element.layout.width,
            height = height or element.layout.height,
        })
    })
end

local function scroll_container(T, idn, debug_name, semantic_ref, children, model)
    return T.UiDecl.Element(
        eid(T, idn),
        semantic_ref,
        debug_name,
        T.UiCore.ScrollPort(),
        T.UiDecl.Flags(true, true),
        base_layout(T, T.UiCore.Column(), insets(T, 8), T.UiCore.Insets(0, 0, 0, 0)),
        panel_paint(T),
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
        accessibility(T, T.UiCore.AccScrollArea(), debug_name),
        children or L()
    )
end

local function button(T, idn, label, command, semantic_ref, active)
    return T.UiDecl.Element(
        eid(T, idn),
        semantic_ref,
        nil,
        T.UiCore.View(),
        T.UiDecl.Flags(true, true),
        base_layout(T, T.UiCore.None(), insets(T, 8), T.UiCore.Insets(0, 0, 0, 0)),
        button_paint(T, active),
        T.UiDecl.Text(T.UiCore.TextValue(label), text_style(T, T.UiCore.Color(1, 1, 1, 1), 14), no_wrap_layout(T)),
        behavior_button(T, command),
        accessibility(T, T.UiCore.AccButton(), label),
        L()
    )
end

local function input(T, idn, label, model, value, multiline)
    return with_size(T, T.UiDecl.Element(
        eid(T, idn),
        nil,
        label,
        T.UiCore.InputField(),
        T.UiDecl.Flags(true, true),
        base_layout(T, T.UiCore.None(), insets(T, 8), T.UiCore.Insets(0, 0, 0, 0)),
        panel_paint(T),
        T.UiDecl.Text(T.UiCore.TextValue(value), text_style(T, T.UiCore.Color(1, 1, 1, 1), 14), text_layout(T)),
        behavior_input(T, model, multiline),
        accessibility(T, T.UiCore.AccTextbox(), label),
        L()
    ), flex_size(T, 1), auto_size(T))
end

local function next_status(T, status)
    return U.match(status, {
        Todo = function() return T.TaskCore.InProgress() end,
        InProgress = function() return T.TaskCore.Blocked() end,
        Blocked = function() return T.TaskCore.Done() end,
        Done = function() return T.TaskCore.Todo() end,
    })
end

local function next_priority(T, priority)
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

function Lower.install(T)
    T.TaskView.WorkspaceHeader.lower = U.transition(function(self)
        return text_element(T, 1000, self.name, T.UiCore.Color(1, 1, 1, 1), 18, nil)
    end)

    T.TaskView.ProjectItem.lower = U.transition(function(self)
        local label = (self.selected and "• " or "") .. self.name .. " (" .. tostring(self.open_count) .. "/" .. tostring(self.done_count) .. ")"
        return button(T, 10000 + self.id.value, label, command_ref(T, T.TaskCommand.SelectProject(self.id)), project_sem(T, self.id), self.selected)
    end)

    T.TaskView.StatusFilter.lower = U.transition(function(self)
        local label = (self.enabled and "[x] " or "[ ] ") .. status_label(self.status) .. " (" .. tostring(self.count) .. ")"
        return button(T, 20000 + status_code(self.status), label, command_ref(T, T.TaskCommand.ToggleStatusFilter(self.status)), nil, self.enabled)
    end)

    T.TaskView.TagFilter.lower = U.transition(function(self)
        local label = (self.enabled and "[x] " or "[ ] ") .. self.name .. " (" .. tostring(self.count) .. ")"
        return button(T, 21000 + self.id.value, label, command_ref(T, T.TaskCommand.ToggleTagFilter(self.id)), tag_sem(T, self.id), self.enabled)
    end)

    T.TaskView.FilterPanel.lower = U.transition(function(self)
        local children = chain_lists {
            L { text_element(T, 22000, "Filters", T.UiCore.Color(1, 1, 1, 1), 16, nil) },
            L { input(T, 22001 + self.query_model.value, "Query", self.query_model, self.query, false) },
            L(F.iter(self.statuses):map(function(v) return v:lower() end):totable()),
            L(F.iter(self.tags):map(function(v) return v:lower() end):totable()),
            L {
                button(T, 22002, self.include_done and "Include Done" or "Hide Done", command_ref(T, T.TaskCommand.SetIncludeDone(not self.include_done)), nil, self.include_done),
                button(T, 22003, "Sort: " .. sort_label(self.sort), command_ref(T, T.TaskCommand.SetSort(self.sort.kind == "ManualOrder" and T.TaskCore.PriorityOrder() or (self.sort.kind == "PriorityOrder" and T.TaskCore.TitleOrder() or T.TaskCore.ManualOrder()))), nil, false)
            },
        }
        return with_size(T, container(T, 22010, "filter-panel", T.UiCore.View(), nil, children, T.UiCore.Column(), panel_paint(T)), flex_size(T, 1), auto_size(T))
    end)

    T.TaskView.Sidebar.lower = U.transition(function(self)
        local project_children = L(F.iter(self.projects):map(function(v) return v:lower() end):totable())
        local children = chain_lists {
            L { self.workspace:lower() },
            project_children,
            L { self.filter:lower() },
        }
        return with_size(T, container(T, 30000, "sidebar", T.UiCore.ListHost(), nil, children, T.UiCore.Column(), panel_paint(T)), measure_px(T, 260), flex_size(T, 1))
    end)

    T.TaskView.ProjectHeader.lower = U.transition(function(self)
        return with_size(T, container(T, 31000 + self.id.value, "project-header", T.UiCore.View(), project_sem(T, self.id), L {
            text_element(T, 31010 + self.id.value, self.name, T.UiCore.Color(1,1,1,1), 18, project_sem(T, self.id)),
            text_element(T, 31020 + self.id.value, tostring(self.visible_count) .. " visible / " .. tostring(self.total_count) .. " total", T.UiCore.Color(0.8,0.82,0.86,1), 12, nil),
            button(T, 31030 + self.id.value, "New Task", command_ref(T, T.TaskCommand.BeginCreateTask(self.id)), project_sem(T, self.id), false),
        }, T.UiCore.Column(), panel_paint(T)), flex_size(T, 1), auto_size(T))
    end)

    T.TaskView.TagChip.lower = U.transition(function(self)
        return T.UiDecl.Element(
            eid(T, 32000 + self.id.value),
            tag_sem(T, self.id),
            nil,
            T.UiCore.View(),
            T.UiDecl.Flags(true, true),
            base_layout(T, T.UiCore.None(), insets(T, 4), T.UiCore.Insets(0, 0, 0, 0)),
            T.UiDecl.Paint(L { T.UiDecl.Box(T.UiCore.Solid(self.color), nil, 0, T.UiCore.CenterStroke(), T.UiCore.Corners(0,0,0,0)) }),
            T.UiDecl.Text(T.UiCore.TextValue(self.name), text_style(T, T.UiCore.Color(0,0,0,1), 12), no_wrap_layout(T)),
            empty_behavior(T),
            accessibility(T, T.UiCore.AccText(), self.name),
            L()
        )
    end)

    T.TaskView.TaskRow.lower = U.transition(function(self)
        local children = chain_lists {
            L { text_element(T, 40010 + self.id.value, self.title, T.UiCore.Color(1,1,1,1), 15, task_sem(T, self.id)) },
            L { wrapped_text_element(T, 40020 + self.id.value, self.notes_preview, T.UiCore.Color(0.8,0.82,0.86,1), 12, nil) },
            L(F.iter(self.tags):map(function(tag) return tag:lower() end):totable())
        }
        return with_size(T, T.UiDecl.Element(
            eid(T, 40000 + self.id.value),
            task_sem(T, self.id),
            nil,
            T.UiCore.View(),
            T.UiDecl.Flags(true, true),
            base_layout(T, T.UiCore.Column(), insets(T, 8), T.UiCore.Insets(0,0,0,0)),
            button_paint(T, self.selected),
            T.UiDecl.NoContent(),
            behavior_button(T, command_ref(T, T.TaskCommand.SelectTask(self.id))),
            accessibility(T, T.UiCore.AccButton(), self.title),
            children
        ), flex_size(T, 1), auto_size(T))
    end)

    T.TaskView.TaskCard.lower = U.transition(function(self)
        local status_next = next_status(T, self.status)
        local priority_next = next_priority(T, self.priority)
        local children = chain_lists {
            L {
                text_element(T, 50010 + self.id.value, self.title, T.UiCore.Color(1,1,1,1), 18, task_sem(T, self.id)),
                wrapped_text_element(T, 50020 + self.id.value, self.notes, T.UiCore.Color(0.86,0.88,0.92,1), 13, nil),
                button(T, 50030 + self.id.value, "Status: " .. status_label(self.status), command_ref(T, T.TaskCommand.SetTaskStatus(self.id, status_next)), task_sem(T, self.id), false),
                button(T, 50040 + self.id.value, "Priority: " .. priority_label(self.priority), command_ref(T, T.TaskCommand.SetTaskPriority(self.id, priority_next)), task_sem(T, self.id), false),
                button(T, 50050 + self.id.value, "Edit", command_ref(T, T.TaskCommand.BeginEditTask(self.id)), task_sem(T, self.id), false),
                button(T, 50060 + self.id.value, "Delete", command_ref(T, T.TaskCommand.RequestDeleteTask(self.id)), task_sem(T, self.id), false),
            },
            L(F.iter(self.tags):map(function(tag) return tag:lower() end):totable())
        }
        return with_size(T, container(T, 50000 + self.id.value, "task-card", T.UiCore.View(), task_sem(T, self.id), children, T.UiCore.Column(), panel_paint(T)), flex_size(T, 1), auto_size(T))
    end)

    T.TaskView.DetailPane.lower = U.transition(function(self)
        return U.match(self, {
            NoDetail = function()
                return with_size(T, container(T, 51000, "detail-empty", T.UiCore.View(), nil, L {
                    text_element(T, 51010, "No task selected", T.UiCore.Color(0.8,0.82,0.86,1), 14, nil)
                }, T.UiCore.Column(), panel_paint(T)), flex_size(T, 1), flex_size(T, 1))
            end,
            TaskDetail = function(v)
                return v.task:lower()
            end,
        })
    end)

    T.TaskView.StatusChoice.lower = U.transition(function(self)
        local label = (self.selected and "● " or "○ ") .. status_label(self.status)
        return button(T, 60000 + status_code(self.status), label, command_ref(T, T.TaskCommand.SetDraftStatus(self.status)), nil, self.selected)
    end)

    T.TaskView.PriorityChoice.lower = U.transition(function(self)
        local label = (self.selected and "● " or "○ ") .. priority_label(self.priority)
        return button(T, 61000 + priority_code(self.priority), label, command_ref(T, T.TaskCommand.SetDraftPriority(self.priority)), nil, self.selected)
    end)

    T.TaskView.TagChoice.lower = U.transition(function(self)
        local label = (self.selected and "[x] " or "[ ] ") .. self.name
        return button(T, 62000 + self.id.value, label, command_ref(T, T.TaskCommand.ToggleDraftTag(self.id)), tag_sem(T, self.id), self.selected)
    end)

    T.TaskView.TaskEditorForm.lower = U.transition(function(self)
        local children = chain_lists {
            L {
                input(T, 63000 + self.title_model.value, "Title", self.title_model, self.title, false),
                input(T, 63010 + self.notes_model.value, "Notes", self.notes_model, self.notes, true),
                text_element(T, 63020, "Status", T.UiCore.Color(1,1,1,1), 14, nil),
            },
            L(F.iter(self.statuses):map(function(v) return v:lower() end):totable()),
            L { text_element(T, 63030, "Priority", T.UiCore.Color(1,1,1,1), 14, nil) },
            L(F.iter(self.priorities):map(function(v) return v:lower() end):totable()),
            L { text_element(T, 63040, "Tags", T.UiCore.Color(1,1,1,1), 14, nil) },
            L(F.iter(self.tags):map(function(v) return v:lower() end):totable()),
        }
        return container(T, 63050, "task-editor-form", T.UiCore.View(), nil, children, T.UiCore.Column(), panel_paint(T))
    end)

    T.TaskView.TaskEditor.lower = U.transition(function(self)
        return U.match(self, {
            CreateTaskEditor = function(v)
                return container(T, 64000 + v.project.value, "create-task-editor", T.UiCore.OverlayHost(), project_sem(T, v.project), L {
                    text_element(T, 64010 + v.project.value, "Create Task", T.UiCore.Color(1,1,1,1), 18, nil),
                    v.form:lower(),
                    button(T, 64020 + v.project.value, "Save", command_ref(T, T.TaskCommand.SubmitEditor()), nil, false),
                    button(T, 64030 + v.project.value, "Cancel", command_ref(T, T.TaskCommand.CancelOverlay()), nil, false),
                }, T.UiCore.Column(), panel_paint(T))
            end,
            EditTaskEditor = function(v)
                return container(T, 64100 + v.task.value, "edit-task-editor", T.UiCore.OverlayHost(), task_sem(T, v.task), L {
                    text_element(T, 64110 + v.task.value, "Edit Task", T.UiCore.Color(1,1,1,1), 18, nil),
                    v.form:lower(),
                    button(T, 64120 + v.task.value, "Save", command_ref(T, T.TaskCommand.SubmitEditor()), nil, false),
                    button(T, 64130 + v.task.value, "Cancel", command_ref(T, T.TaskCommand.CancelOverlay()), nil, false),
                }, T.UiCore.Column(), panel_paint(T))
            end,
        })
    end)

    T.TaskView.DeleteDialog.lower = U.transition(function(self)
        return container(T, 65000 + self.task.value, "delete-dialog", T.UiCore.OverlayHost(), task_sem(T, self.task), L {
            text_element(T, 65010 + self.task.value, self.heading, T.UiCore.Color(1,1,1,1), 18, nil),
            text_element(T, 65020 + self.task.value, self.message, T.UiCore.Color(0.9,0.9,0.9,1), 14, nil),
            button(T, 65030 + self.task.value, "Delete", command_ref(T, T.TaskCommand.ConfirmDelete()), task_sem(T, self.task), false),
            button(T, 65040 + self.task.value, "Cancel", command_ref(T, T.TaskCommand.CancelOverlay()), nil, false),
        }, T.UiCore.Column(), panel_paint(T))
    end)

    T.TaskView.Overlay.lower = U.transition(function(self)
        return U.match(self, {
            TaskEditorOverlay = function(v)
                return container(T, 66000, "overlay-editor", T.UiCore.OverlayHost(), nil, L { v.editor:lower() }, T.UiCore.Column(), panel_paint(T))
            end,
            DeleteTaskOverlay = function(v)
                return container(T, 66100, "overlay-delete", T.UiCore.OverlayHost(), nil, L { v.dialog:lower() }, T.UiCore.Column(), panel_paint(T))
            end,
        })
    end)

    T.TaskView.Content.lower = U.transition(function(self)
        return U.match(self, {
            NothingSelected = function(v)
                return with_size(T, container(T, 70000, "content-empty", T.UiCore.View(), nil, L {
                    text_element(T, 70010, v.title, T.UiCore.Color(1,1,1,1), 18, nil),
                    text_element(T, 70020, v.message, T.UiCore.Color(0.8,0.82,0.86,1), 14, nil),
                }, T.UiCore.Column(), panel_paint(T)), flex_size(T, 1), flex_size(T, 1))
            end,
            ProjectScreen = function(v)
                local task_list = with_size(T, scroll_container(T, 70100 + v.project.id.value, "task-list", project_sem(T, v.project.id), chain_lists {
                    L { v.project:lower() },
                    L(F.iter(v.tasks):map(function(task) return task:lower() end):totable()),
                }, v.task_list_scroll), measure_px(T, 360), flex_size(T, 1))
                local detail = with_size(T, scroll_container(T, 70150 + v.project.id.value, "detail-scroll", project_sem(T, v.project.id), L { v.detail:lower() }, v.detail_scroll), measure_px(T, 432), flex_size(T, 1))
                return with_size(T, container(T, 70200 + v.project.id.value, "content-project", T.UiCore.View(), project_sem(T, v.project.id), L { task_list, detail }, T.UiCore.Row(), T.UiDecl.Paint(L())), measure_px(T, 816), flex_size(T, 1))
            end,
        })
    end)

    T.TaskView.Screen.lower = U.transition(function(self)
        return T.UiDecl.Document(
            1,
            L {
                T.UiDecl.Root(eid(T, 80000), "task-screen", with_size(T, container(T, 80010, "screen", T.UiCore.View(), nil, L { self.sidebar:lower(), self.content:lower() }, T.UiCore.Row(), T.UiDecl.Paint(L())), flex_size(T, 1), flex_size(T, 1)))
            },
            L(F.iter(self.overlays):enumerate():map(function(i, overlay)
                return T.UiDecl.Overlay(eid(T, 81000 + i), "overlay", overlay:lower(), 100 + i, true, true)
            end):totable())
        )
    end)
end

return Lower
