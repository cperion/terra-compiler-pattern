local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui2.ui2_asdl"),
        require("examples.ui2.ui2_demo_asdl"),
    },

    pipeline = {
        "UiInput",
        "UiSession",
        "UiIntent",
        "UiApply",
        "DemoCommand",
        "DemoDecode",
        "DemoEvent",
        "DemoApp",
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
            ["UiIntent.Event"] = "decode_demo",
            ["DemoApp.State"] = { "initial", "apply", "apply_ui" },
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
