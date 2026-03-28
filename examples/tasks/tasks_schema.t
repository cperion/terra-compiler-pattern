local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui.ui_asdl"),
        require("examples.tasks.tasks_asdl"),
    },

    pipeline = {
        "UiIntent",
        "TaskDecode",
        "TaskEvent",
        "TaskApp",
        "TaskView",
        "UiDecl",
    },

    install = function(T)
        require("examples.ui.ui_session_state")(T)
        require("examples.ui.ui_decl_document")(T)
        require("examples.ui.ui_laid_scene_batch")(T)
        require("examples.ui.ui_laid_scene_route")(T)
        require("examples.ui.ui_batched")(T)

        require("examples.tasks.task_app_state")(T)
        require("examples.tasks.task_view_screen")(T)
        require("examples.tasks.task_view")(T)
    end,
}
