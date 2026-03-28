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
        local SessionApply = require("examples.ui.ui_session_apply")
        local Layout = require("examples.ui.ui_decl_layout")
        local Batching = require("examples.ui.ui_laid_batch")
        local Routing = require("examples.ui.ui_laid_route")
        local Backend = require("examples.ui.ui_batched_compile")
        local Logic = require("examples.tasks.tasks_app_logic")
        local Decode = require("examples.tasks.tasks_view_decode")
        local Lower = require("examples.tasks.tasks_view_lower")

        SessionApply.install(T)
        Layout.install(T)
        Batching.install(T)
        Routing.install(T)
        Backend.install(T)

        Logic.install(T)
        Decode.install(T)
        Lower.install(T)
    end,
}
