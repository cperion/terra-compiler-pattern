local U = require("unit")

local Codec = {}

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

local function status_from_code(T, code)
    if code == 1 then return T.TaskCore.Todo() end
    if code == 2 then return T.TaskCore.InProgress() end
    if code == 3 then return T.TaskCore.Blocked() end
    if code == 4 then return T.TaskCore.Done() end
    error(("TaskCommand.decode: unknown status code %s"):format(tostring(code)), 2)
end

local function priority_from_code(T, code)
    if code == 1 then return T.TaskCore.NoPriority() end
    if code == 2 then return T.TaskCore.Low() end
    if code == 3 then return T.TaskCore.Medium() end
    if code == 4 then return T.TaskCore.High() end
    error(("TaskCommand.decode: unknown priority code %s"):format(tostring(code)), 2)
end

function Codec.encode(T, command)
    local code = U.match(command, {
        ClearSelection = function() return 1000 end,
        SelectProject = function(v) return 200000 + v.project.value end,
        SelectTask = function(v) return 300000 + v.task.value end,
        ToggleStatusFilter = function(v) return 400000 + status_code(v.status) end,
        ToggleTagFilter = function(v) return 500000 + v.tag.value end,
        SetIncludeDone = function(v) return 600000 + (v.value and 1 or 0) end,
        SetSort = function(v)
            return 700000 + U.match(v.sort, {
                ManualOrder = function() return 1 end,
                PriorityOrder = function() return 2 end,
                TitleOrder = function() return 3 end,
            })
        end,
        BeginCreateTask = function(v) return 800000 + v.project.value end,
        BeginEditTask = function(v) return 900000 + v.task.value end,
        RequestDeleteTask = function(v) return 1000000 + v.task.value end,
        ConfirmDelete = function() return 1100000 end,
        CancelOverlay = function() return 1200000 end,
        SubmitEditor = function() return 1300000 end,
        SetDraftStatus = function(v) return 1400000 + status_code(v.status) end,
        SetDraftPriority = function(v) return 1500000 + priority_code(v.priority) end,
        ToggleDraftTag = function(v) return 1600000 + v.tag.value end,
        SetTaskStatus = function(v) return 1700000 + v.task.value * 10 + status_code(v.status) end,
        SetTaskPriority = function(v) return 1800000 + v.task.value * 10 + priority_code(v.priority) end,
    })
    return T.UiCore.CommandRef(code)
end

function Codec.decode(T, command_ref)
    local code = command_ref.value
    if code == 1000 then return T.TaskCommand.ClearSelection() end
    if code >= 200000 and code < 300000 then return T.TaskCommand.SelectProject(T.TaskCore.ProjectRef(code - 200000)) end
    if code >= 300000 and code < 400000 then return T.TaskCommand.SelectTask(T.TaskCore.TaskRef(code - 300000)) end
    if code >= 400000 and code < 500000 then return T.TaskCommand.ToggleStatusFilter(status_from_code(T, code - 400000)) end
    if code >= 500000 and code < 600000 then return T.TaskCommand.ToggleTagFilter(T.TaskCore.TagRef(code - 500000)) end
    if code >= 600000 and code < 700000 then return T.TaskCommand.SetIncludeDone((code - 600000) ~= 0) end
    if code >= 700000 and code < 800000 then
        local sort = code - 700000
        if sort == 1 then return T.TaskCommand.SetSort(T.TaskCore.ManualOrder()) end
        if sort == 2 then return T.TaskCommand.SetSort(T.TaskCore.PriorityOrder()) end
        if sort == 3 then return T.TaskCommand.SetSort(T.TaskCore.TitleOrder()) end
    end
    if code >= 800000 and code < 900000 then return T.TaskCommand.BeginCreateTask(T.TaskCore.ProjectRef(code - 800000)) end
    if code >= 900000 and code < 1000000 then return T.TaskCommand.BeginEditTask(T.TaskCore.TaskRef(code - 900000)) end
    if code >= 1000000 and code < 1100000 then return T.TaskCommand.RequestDeleteTask(T.TaskCore.TaskRef(code - 1000000)) end
    if code == 1100000 then return T.TaskCommand.ConfirmDelete() end
    if code == 1200000 then return T.TaskCommand.CancelOverlay() end
    if code == 1300000 then return T.TaskCommand.SubmitEditor() end
    if code >= 1400000 and code < 1500000 then return T.TaskCommand.SetDraftStatus(status_from_code(T, code - 1400000)) end
    if code >= 1500000 and code < 1600000 then return T.TaskCommand.SetDraftPriority(priority_from_code(T, code - 1500000)) end
    if code >= 1600000 and code < 1700000 then return T.TaskCommand.ToggleDraftTag(T.TaskCore.TagRef(code - 1600000)) end
    if code >= 1700000 and code < 1800000 then
        local payload = code - 1700000
        local task = math.floor(payload / 10)
        local status = payload % 10
        return T.TaskCommand.SetTaskStatus(T.TaskCore.TaskRef(task), status_from_code(T, status))
    end
    if code >= 1800000 and code < 1900000 then
        local payload = code - 1800000
        local task = math.floor(payload / 10)
        local priority = payload % 10
        return T.TaskCommand.SetTaskPriority(T.TaskCore.TaskRef(task), priority_from_code(T, priority))
    end
    error(("TaskCommand.decode: unknown command ref %s"):format(tostring(code)), 2)
end

return Codec
