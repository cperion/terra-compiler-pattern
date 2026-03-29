local U = require("unit")
local F = require("fun")
local Codec = require("examples.tasks.tasks_command_codec")

return function(T)
    local List = require("asdl").List

local function L(xs)
        return List(xs or {})
    end

    local function find_editor(screen)
        local overlays = F.iter(screen.overlays)
            :map(function(overlay)
                return U.match(overlay, {
                    TaskEditorOverlay = function(v) return v.editor end,
                    DeleteTaskOverlay = function(_) return nil end,
                })
            end)
            :filter(function(v) return v ~= nil end)
            :totable()
        return #overlays > 0 and overlays[1] or nil
    end

    local function query_model(screen)
        return screen.sidebar.filter.query_model
    end

    local function query_value(screen)
        return screen.sidebar.filter.query
    end

    local function title_model(screen)
        local editor = find_editor(screen)
        if not editor then return nil end
        return U.match(editor, {
            CreateTaskEditor = function(v) return v.form.title_model end,
            EditTaskEditor = function(v) return v.form.title_model end,
        })
    end

    local function title_value(screen)
        local editor = find_editor(screen)
        if not editor then return nil end
        return U.match(editor, {
            CreateTaskEditor = function(v) return v.form.title end,
            EditTaskEditor = function(v) return v.form.title end,
        })
    end

    local function notes_model(screen)
        local editor = find_editor(screen)
        if not editor then return nil end
        return U.match(editor, {
            CreateTaskEditor = function(v) return v.form.notes_model end,
            EditTaskEditor = function(v) return v.form.notes_model end,
        })
    end

    local function notes_value(screen)
        local editor = find_editor(screen)
        if not editor then return nil end
        return U.match(editor, {
            CreateTaskEditor = function(v) return v.form.notes end,
            EditTaskEditor = function(v) return v.form.notes end,
        })
    end

    local function apply_edit_text(current, action)
        return U.match(action, {
            InsertText = function(v)
                return current .. v.text
            end,
            Backspace = function()
                if #current == 0 then return current end
                return current:sub(1, #current - 1)
            end,
            Delete = function()
                if #current == 0 then return current end
                return current:sub(1, #current - 1)
            end,
            MoveCaret = function(_) return current end,
            SelectAll = function() return current end,
            Submit = function() return current end,
        })
    end

    local function event_for_command(command)
        return U.match(command, {
            ClearSelection = function() return T.TaskEvent.ClearSelection() end,
            SelectProject = function(v) return T.TaskEvent.SelectProject(v.project) end,
            SelectTask = function(v) return T.TaskEvent.SelectTask(v.task) end,
            ToggleStatusFilter = function(v) return T.TaskEvent.ToggleStatusFilter(v.status) end,
            ToggleTagFilter = function(v) return T.TaskEvent.ToggleTagFilter(v.tag) end,
            SetIncludeDone = function(v) return T.TaskEvent.SetIncludeDone(v.value) end,
            SetSort = function(v) return T.TaskEvent.SetSort(v.sort) end,
            BeginCreateTask = function(v) return T.TaskEvent.BeginCreateTask(v.project) end,
            BeginEditTask = function(v) return T.TaskEvent.BeginEditTask(v.task) end,
            RequestDeleteTask = function(v) return T.TaskEvent.RequestDeleteTask(v.task) end,
            ConfirmDelete = function() return T.TaskEvent.ConfirmDelete() end,
            CancelOverlay = function() return T.TaskEvent.CancelOverlay() end,
            SubmitEditor = function() return T.TaskEvent.SubmitEditor() end,
            SetDraftStatus = function(v) return T.TaskEvent.UpdateDraftStatus(v.status) end,
            SetDraftPriority = function(v) return T.TaskEvent.UpdateDraftPriority(v.priority) end,
            ToggleDraftTag = function(v) return T.TaskEvent.ToggleDraftTag(v.tag) end,
            SetTaskStatus = function(v) return T.TaskEvent.SetTaskStatus(v.task, v.status) end,
            SetTaskPriority = function(v) return T.TaskEvent.SetTaskPriority(v.task, v.priority) end,
        })
    end

    T.TaskView.Screen.decode = U.transition(function(screen, intent)
        return U.match(intent, {
            Command = function(v)
                return T.TaskDecode.Result(L { event_for_command(Codec.decode(T, v.command)) })
            end,
            Toggle = function(v)
                return T.TaskDecode.Result(v.command and L { event_for_command(Codec.decode(T, v.command)) } or L())
            end,
            Scroll = function(_)
                return T.TaskDecode.Result(L())
            end,
            Focus = function(_)
                return T.TaskDecode.Result(L())
            end,
            Hover = function(_)
                return T.TaskDecode.Result(L())
            end,
            Edit = function(v)
                if v.model == query_model(screen) then
                    return T.TaskDecode.Result(
                        v.action.kind == "Submit"
                            and L()
                            or L { T.TaskEvent.SetQuery(apply_edit_text(query_value(screen), v.action)) }
                    )
                end

                local tm = title_model(screen)
                if tm and v.model == tm then
                    return T.TaskDecode.Result(
                        v.action.kind == "Submit"
                            and L { T.TaskEvent.SubmitEditor() }
                            or L { T.TaskEvent.UpdateDraftTitle(apply_edit_text(title_value(screen) or "", v.action)) }
                    )
                end

                local nm = notes_model(screen)
                if nm and v.model == nm then
                    return T.TaskDecode.Result(
                        v.action.kind == "Submit"
                            and L { T.TaskEvent.SubmitEditor() }
                            or L { T.TaskEvent.UpdateDraftNotes(apply_edit_text(notes_value(screen) or "", v.action)) }
                    )
                end

                return T.TaskDecode.Result(L())
            end,
        })
    end)
end
