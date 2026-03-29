local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui2.ui2_asdl"),
        require("examples.tasks.tasks_asdl"),
    },

    pipeline = {
        "UiInput",
        "UiSession",
        "UiIntent",
        "UiApply",
        "TaskDecode",
        "TaskEvent",
        "TaskApp",
        "TaskView",
        "UiDecl",
        "UiBound",
        "UiFlat",
        "UiLowered",
        "UiGeometry",
        "UiRender",
        "UiQuery",
        "UiKernel",
        "UiMachine",
    },

    install = function(T)
        U.install_stubs(T, {
            ["UiSession.State"] = { "initial", "apply_with_intents", "apply" },
            ["UiDecl.Document"] = "bind",
            ["UiBound.Document"] = "flatten",
            ["UiFlat.Scene"] = "lower",
            ["UiLowered.Scene"] = "solve_geometry",
            ["UiGeometry.Scene"] = { "project_render", "project_query" },
            ["UiRender.Scene"] = "specialize_kernel",
            ["UiKernel.Render"] = "define_machine",
            ["UiMachine.Gen"] = "compile",
            ["UiMachine.Render"] = "materialize",
        })
    end,
}
