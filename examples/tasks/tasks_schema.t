local U = require("unit")

local function stub(boundary_name)
    return function(...)
        error(boundary_name .. " not implemented", 2)
    end
end

return U.spec {
    texts = {
        require("examples.ui.ui_asdl"),
        require("examples.tasks.tasks_asdl"),
    },

    pipeline = {
        "TaskApp",
        "TaskView",
        "UiDecl",
    },

    install = function(T)
        T.TaskApp.State.project_view = stub("TaskApp.State:project_view")

        T.TaskView.Screen.lower = stub("TaskView.Screen:lower")
        T.TaskView.Sidebar.lower = stub("TaskView.Sidebar:lower")
        T.TaskView.WorkspaceHeader.lower = stub("TaskView.WorkspaceHeader:lower")
        T.TaskView.ProjectItem.lower = stub("TaskView.ProjectItem:lower")
        T.TaskView.FilterPanel.lower = stub("TaskView.FilterPanel:lower")
        T.TaskView.StatusFilter.lower = stub("TaskView.StatusFilter:lower")
        T.TaskView.TagFilter.lower = stub("TaskView.TagFilter:lower")
        T.TaskView.Content.lower = stub("TaskView.Content:lower")
        T.TaskView.ProjectHeader.lower = stub("TaskView.ProjectHeader:lower")
        T.TaskView.TaskRow.lower = stub("TaskView.TaskRow:lower")
        T.TaskView.TagChip.lower = stub("TaskView.TagChip:lower")
        T.TaskView.DetailPane.lower = stub("TaskView.DetailPane:lower")
        T.TaskView.TaskCard.lower = stub("TaskView.TaskCard:lower")
        T.TaskView.Overlay.lower = stub("TaskView.Overlay:lower")
        T.TaskView.TaskEditor.lower = stub("TaskView.TaskEditor:lower")
        T.TaskView.StatusChoice.lower = stub("TaskView.StatusChoice:lower")
        T.TaskView.PriorityChoice.lower = stub("TaskView.PriorityChoice:lower")
        T.TaskView.TagChoice.lower = stub("TaskView.TagChoice:lower")
        T.TaskView.DeleteDialog.lower = stub("TaskView.DeleteDialog:lower")
    end,
}
