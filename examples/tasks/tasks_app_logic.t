local U = require("unit")
local F = require("fun")

local Logic = {}

local function L(xs)
    return terralib.newlist(xs or {})
end

local function contains(xs, value)
    return F.iter(xs):any(function(v) return v == value end)
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

local function find_project(workspace, ref)
    local items = F.iter(workspace.projects):filter(function(project)
        return project.id == ref
    end):totable()
    return #items > 0 and items[1] or nil
end

local function find_task(workspace, ref)
    local matches = F.iter(workspace.projects):map(function(project)
        return F.iter(project.tasks):filter(function(task) return task.id == ref end):totable()
    end):totable()
    for _, group in ipairs(matches) do
        if #group > 0 then return group[1] end
    end
    return nil
end

local function task_project_ref(workspace, ref)
    local matches = F.iter(workspace.projects):filter(function(project)
        return F.iter(project.tasks):any(function(task) return task.id == ref end)
    end):totable()
    return #matches > 0 and matches[1].id or nil
end

local function find_tag(workspace, ref)
    local items = F.iter(workspace.tags):filter(function(tag)
        return tag.id == ref
    end):totable()
    return #items > 0 and items[1] or nil
end

local function note_preview(text)
    if #text <= 80 then return text end
    return text:sub(1, 77) .. "..."
end

local function selected_project_ref(selection)
    return U.match(selection, {
        NoSelection = function() return nil end,
        ProjectSelected = function(v) return v.project end,
        TaskSelected = function(v) return v.project end,
    })
end

local function selected_task_ref(selection)
    return U.match(selection, {
        NoSelection = function() return nil end,
        ProjectSelected = function(_) return nil end,
        TaskSelected = function(v) return v.task end,
    })
end

local function query_match(query, task)
    if query == nil or query == "" then return true end
    local q = query:lower()
    return task.title:lower():find(q, 1, true) ~= nil
        or task.notes:lower():find(q, 1, true) ~= nil
end

local function filter_task(filter, task)
    local status_ok = #filter.statuses == 0 or contains(filter.statuses, task.status)
    local tags_ok = #filter.tags == 0 or F.iter(filter.tags):all(function(tag_ref)
        return contains(task.tags, tag_ref)
    end)
    local done_ok = filter.include_done or task.status.kind ~= "Done"
    return status_ok and tags_ok and done_ok and query_match(filter.query, task)
end

local function sort_tasks(sort, tasks)
    local out = F.iter(tasks):totable()
    table.sort(out, function(a, b)
        if sort.kind == "PriorityOrder" then
            local pa, pb = priority_code(a.priority), priority_code(b.priority)
            if pa ~= pb then return pa > pb end
        elseif sort.kind == "TitleOrder" then
            if a.title ~= b.title then return a.title < b.title end
        end
        return a.id.value < b.id.value
    end)
    return out
end

local function count_if(xs, pred)
    return F.iter(xs):reduce(function(acc, v)
        return pred(v) and (acc + 1) or acc
    end, 0)
end

local function status_filters(T, workspace, project, filter)
    local statuses = {
        T.TaskCore.Todo(),
        T.TaskCore.InProgress(),
        T.TaskCore.Blocked(),
        T.TaskCore.Done(),
    }
    return L(F.iter(statuses):map(function(status)
        local count = count_if(project.tasks, function(task) return task.status == status end)
        return T.TaskView.StatusFilter(status, count, contains(filter.statuses, status))
    end):totable())
end

local function tag_filters(T, workspace, project, filter)
    return L(F.iter(workspace.tags):map(function(tag)
        local count = count_if(project.tasks, function(task)
            return contains(task.tags, tag.id)
        end)
        return T.TaskView.TagFilter(tag.id, tag.name, tag.color, count, contains(filter.tags, tag.id))
    end):totable())
end

local function tag_chips(T, workspace, refs)
    return L(F.iter(refs):map(function(ref)
        local tag = find_tag(workspace, ref)
        return T.TaskView.TagChip(tag.id, tag.name, tag.color)
    end):totable())
end

local function draft_form(T, workspace, draft, base_id)
    local statuses = {
        T.TaskCore.Todo(),
        T.TaskCore.InProgress(),
        T.TaskCore.Blocked(),
        T.TaskCore.Done(),
    }
    local priorities = {
        T.TaskCore.NoPriority(),
        T.TaskCore.Low(),
        T.TaskCore.Medium(),
        T.TaskCore.High(),
    }

    return T.TaskView.TaskEditorForm(
        T.UiCore.TextModelRef(1000 + base_id),
        T.UiCore.TextModelRef(2000 + base_id),
        draft.title,
        draft.notes,
        L(F.iter(statuses):map(function(status)
            return T.TaskView.StatusChoice(status, draft.status == status)
        end):totable()),
        L(F.iter(priorities):map(function(priority)
            return T.TaskView.PriorityChoice(priority, draft.priority == priority)
        end):totable()),
        L(F.iter(workspace.tags):map(function(tag)
            return T.TaskView.TagChoice(tag.id, tag.name, tag.color, contains(draft.tags, tag.id))
        end):totable())
    )
end

local function next_task_id(workspace)
    local max_id = F.iter(workspace.projects):map(function(project)
        local local_max = 0
        for _, task in ipairs(project.tasks) do
            if task.id.value > local_max then local_max = task.id.value end
        end
        return local_max
    end):reduce(math.max, 0)
    return max_id + 1
end

local function with_projects(T, workspace, projects)
    return T.TaskDoc.Workspace(workspace.version, workspace.name, L(projects), workspace.tags)
end

local function update_project_tasks(T, workspace, project_ref, mapper)
    return with_projects(T, workspace, F.iter(workspace.projects):map(function(project)
        if project.id ~= project_ref then return project end
        return T.TaskDoc.Project(project.id, project.name, project.archived, L(mapper(project.tasks)))
    end):totable())
end

local function toggle_in_list(xs, value)
    if contains(xs, value) then
        return L(F.iter(xs):filter(function(v) return v ~= value end):totable())
    end
    local out = F.iter(xs):totable()
    out[#out + 1] = value
    return L(out)
end

function Logic.install(T)
    T.TaskApp.State.project_view = U.transition(function(state)
        local selected_project = selected_project_ref(state.session.selection)
        local project = selected_project and find_project(state.workspace, selected_project) or nil
        local selected_task = selected_task_ref(state.session.selection)
        local sidebar = T.TaskView.Sidebar(
            T.TaskView.WorkspaceHeader(state.workspace.name),
            L(F.iter(state.workspace.projects):map(function(project_item)
                local open_count = count_if(project_item.tasks, function(task) return task.status.kind ~= "Done" end)
                local done_count = count_if(project_item.tasks, function(task) return task.status.kind == "Done" end)
                return T.TaskView.ProjectItem(project_item.id, project_item.name, open_count, done_count, selected_project == project_item.id)
            end):totable()),
            T.TaskView.FilterPanel(
                T.UiCore.TextModelRef(1),
                state.session.filter.query,
                project and status_filters(T, state.workspace, project, state.session.filter) or L(),
                project and tag_filters(T, state.workspace, project, state.session.filter) or L(),
                state.session.filter.include_done,
                state.session.sort
            )
        )

        local content = project and (function()
            local visible_tasks = sort_tasks(state.session.sort, F.iter(project.tasks):filter(function(task)
                return filter_task(state.session.filter, task)
            end):totable())
            local detail_task = selected_task and find_task(state.workspace, selected_task) or nil
            return T.TaskView.ProjectScreen(
                T.TaskView.ProjectHeader(project.id, project.name, #visible_tasks, #project.tasks),
                T.UiCore.ScrollRef(3000 + project.id.value),
                T.UiCore.ScrollRef(4000 + project.id.value),
                L(F.iter(visible_tasks):map(function(task)
                    return T.TaskView.TaskRow(task.id, task.title, note_preview(task.notes), task.status, task.priority, tag_chips(T, state.workspace, task.tags), selected_task == task.id)
                end):totable()),
                detail_task and T.TaskView.TaskDetail(T.TaskView.TaskCard(detail_task.id, detail_task.title, detail_task.notes, detail_task.status, detail_task.priority, tag_chips(T, state.workspace, detail_task.tags))) or T.TaskView.NoDetail()
            )
        end)() or T.TaskView.NothingSelected(
            "No project selected",
            "Choose a project from the sidebar to view tasks."
        )

        local overlays = U.match(state.session.editor, {
            NoEditor = function() return L() end,
            CreatingTask = function(v)
                return L { T.TaskView.TaskEditorOverlay(T.TaskView.CreateTaskEditor(v.project, draft_form(T, state.workspace, v.draft, v.project.value))) }
            end,
            EditingTask = function(v)
                return L { T.TaskView.TaskEditorOverlay(T.TaskView.EditTaskEditor(v.task, draft_form(T, state.workspace, v.draft, 5000 + v.task.value))) }
            end,
            ConfirmingDelete = function(v)
                local task = find_task(state.workspace, v.task)
                return L { T.TaskView.DeleteTaskOverlay(T.TaskView.DeleteDialog(v.task, "Delete Task", "Delete '" .. task.title .. "'?")) }
            end,
        })

        return T.TaskView.Screen(sidebar, content, overlays)
    end)

    T.TaskApp.State.apply = U.transition(function(state, event)
        return U.match(event, {
            Quit = function()
                return U.with(state, { running = false })
            end,
            ClearSelection = function()
                return U.with(state, { session = U.with(state.session, { selection = T.TaskSession.NoSelection() }) })
            end,
            SelectProject = function(v)
                return U.with(state, { session = U.with(state.session, { selection = T.TaskSession.ProjectSelected(v.project) }) })
            end,
            SelectTask = function(v)
                local project_ref = task_project_ref(state.workspace, v.task)
                return U.with(state, { session = U.with(state.session, { selection = T.TaskSession.TaskSelected(project_ref, v.task) }) })
            end,
            SetQuery = function(v)
                return U.with(state, { session = U.with(state.session, { filter = U.with(state.session.filter, { query = v.value }) }) })
            end,
            ToggleStatusFilter = function(v)
                return U.with(state, { session = U.with(state.session, { filter = U.with(state.session.filter, { statuses = toggle_in_list(state.session.filter.statuses, v.status) }) }) })
            end,
            ToggleTagFilter = function(v)
                return U.with(state, { session = U.with(state.session, { filter = U.with(state.session.filter, { tags = toggle_in_list(state.session.filter.tags, v.tag) }) }) })
            end,
            SetIncludeDone = function(v)
                return U.with(state, { session = U.with(state.session, { filter = U.with(state.session.filter, { include_done = v.value }) }) })
            end,
            SetSort = function(v)
                return U.with(state, { session = U.with(state.session, { sort = v.sort }) })
            end,
            BeginCreateTask = function(v)
                local draft = T.TaskSession.Draft("", "", T.TaskCore.Todo(), T.TaskCore.NoPriority(), L())
                return U.with(state, { session = U.with(state.session, { editor = T.TaskSession.CreatingTask(v.project, draft), selection = T.TaskSession.ProjectSelected(v.project) }) })
            end,
            BeginEditTask = function(v)
                local task = find_task(state.workspace, v.task)
                local project_ref = task_project_ref(state.workspace, v.task)
                local draft = T.TaskSession.Draft(task.title, task.notes, task.status, task.priority, task.tags)
                return U.with(state, { session = U.with(state.session, { editor = T.TaskSession.EditingTask(v.task, draft), selection = T.TaskSession.TaskSelected(project_ref, v.task) }) })
            end,
            UpdateDraftTitle = function(v)
                return U.with(state, { session = U.with(state.session, { editor = U.match(state.session.editor, {
                    CreatingTask = function(ed) return T.TaskSession.CreatingTask(ed.project, U.with(ed.draft, { title = v.value })) end,
                    EditingTask = function(ed) return T.TaskSession.EditingTask(ed.task, U.with(ed.draft, { title = v.value })) end,
                    NoEditor = function(ed) return ed end,
                    ConfirmingDelete = function(ed) return ed end,
                }) }) })
            end,
            UpdateDraftNotes = function(v)
                return U.with(state, { session = U.with(state.session, { editor = U.match(state.session.editor, {
                    CreatingTask = function(ed) return T.TaskSession.CreatingTask(ed.project, U.with(ed.draft, { notes = v.value })) end,
                    EditingTask = function(ed) return T.TaskSession.EditingTask(ed.task, U.with(ed.draft, { notes = v.value })) end,
                    NoEditor = function(ed) return ed end,
                    ConfirmingDelete = function(ed) return ed end,
                }) }) })
            end,
            UpdateDraftStatus = function(v)
                return U.with(state, { session = U.with(state.session, { editor = U.match(state.session.editor, {
                    CreatingTask = function(ed) return T.TaskSession.CreatingTask(ed.project, U.with(ed.draft, { status = v.status })) end,
                    EditingTask = function(ed) return T.TaskSession.EditingTask(ed.task, U.with(ed.draft, { status = v.status })) end,
                    NoEditor = function(ed) return ed end,
                    ConfirmingDelete = function(ed) return ed end,
                }) }) })
            end,
            UpdateDraftPriority = function(v)
                return U.with(state, { session = U.with(state.session, { editor = U.match(state.session.editor, {
                    CreatingTask = function(ed) return T.TaskSession.CreatingTask(ed.project, U.with(ed.draft, { priority = v.priority })) end,
                    EditingTask = function(ed) return T.TaskSession.EditingTask(ed.task, U.with(ed.draft, { priority = v.priority })) end,
                    NoEditor = function(ed) return ed end,
                    ConfirmingDelete = function(ed) return ed end,
                }) }) })
            end,
            ToggleDraftTag = function(v)
                return U.with(state, { session = U.with(state.session, { editor = U.match(state.session.editor, {
                    CreatingTask = function(ed) return T.TaskSession.CreatingTask(ed.project, U.with(ed.draft, { tags = toggle_in_list(ed.draft.tags, v.tag) })) end,
                    EditingTask = function(ed) return T.TaskSession.EditingTask(ed.task, U.with(ed.draft, { tags = toggle_in_list(ed.draft.tags, v.tag) })) end,
                    NoEditor = function(ed) return ed end,
                    ConfirmingDelete = function(ed) return ed end,
                }) }) })
            end,
            SubmitEditor = function()
                return U.match(state.session.editor, {
                    NoEditor = function()
                        return state
                    end,
                    ConfirmingDelete = function()
                        return state
                    end,
                    CreatingTask = function(ed)
                        local new_task = T.TaskDoc.Task(T.TaskCore.TaskRef(next_task_id(state.workspace)), ed.draft.title, ed.draft.notes, ed.draft.status, ed.draft.priority, ed.draft.tags)
                        local workspace = update_project_tasks(T, state.workspace, ed.project, function(tasks)
                            local out = F.iter(tasks):totable()
                            out[#out + 1] = new_task
                            return out
                        end)
                        return T.TaskApp.State(workspace, T.TaskSession.State(T.TaskSession.TaskSelected(ed.project, new_task.id), state.session.filter, state.session.sort, T.TaskSession.NoEditor()), state.running)
                    end,
                    EditingTask = function(ed)
                        local workspace = update_project_tasks(T, state.workspace, task_project_ref(state.workspace, ed.task), function(tasks)
                            return F.iter(tasks):map(function(task)
                                if task.id ~= ed.task then return task end
                                return T.TaskDoc.Task(task.id, ed.draft.title, ed.draft.notes, ed.draft.status, ed.draft.priority, ed.draft.tags)
                            end):totable()
                        end)
                        return T.TaskApp.State(workspace, U.with(state.session, { editor = T.TaskSession.NoEditor() }), state.running)
                    end,
                })
            end,
            CancelOverlay = function()
                return U.with(state, { session = U.with(state.session, { editor = T.TaskSession.NoEditor() }) })
            end,
            RequestDeleteTask = function(v)
                return U.with(state, { session = U.with(state.session, { editor = T.TaskSession.ConfirmingDelete(v.task) }) })
            end,
            ConfirmDelete = function()
                return U.match(state.session.editor, {
                    ConfirmingDelete = function(ed)
                        local project_ref = task_project_ref(state.workspace, ed.task)
                        local workspace = update_project_tasks(T, state.workspace, project_ref, function(tasks)
                            return F.iter(tasks):filter(function(task) return task.id ~= ed.task end):totable()
                        end)
                        return T.TaskApp.State(workspace, U.with(state.session, { editor = T.TaskSession.NoEditor(), selection = T.TaskSession.ProjectSelected(project_ref) }), state.running)
                    end,
                    NoEditor = function() return state end,
                    CreatingTask = function() return state end,
                    EditingTask = function() return state end,
                })
            end,
            SetTaskStatus = function(v)
                local project_ref = task_project_ref(state.workspace, v.task)
                return U.with(state, { workspace = update_project_tasks(T, state.workspace, project_ref, function(tasks)
                    return F.iter(tasks):map(function(task)
                        if task.id ~= v.task then return task end
                        return T.TaskDoc.Task(task.id, task.title, task.notes, v.status, task.priority, task.tags)
                    end):totable()
                end) })
            end,
            SetTaskPriority = function(v)
                local project_ref = task_project_ref(state.workspace, v.task)
                return U.with(state, { workspace = update_project_tasks(T, state.workspace, project_ref, function(tasks)
                    return F.iter(tasks):map(function(task)
                        if task.id ~= v.task then return task end
                        return T.TaskDoc.Task(task.id, task.title, task.notes, task.status, v.priority, task.tags)
                    end):totable()
                end) })
            end,
        })
    end)
end

return Logic
