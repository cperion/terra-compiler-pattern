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
        "UiDemand",
        "UiSolved",
        "UiPlan",
        "UiKernel",
    },

    install = function(T)
        U.install_stubs(T, {
            ["UiSession.State"] = { "initial", "apply_with_intents", "apply" },
            ["UiIntent.Event"] = "decode_demo",
            ["DemoApp.State"] = { "initial", "apply", "apply_ui" },
            ["UiDecl.Document"] = "bind",
            ["UiBound.Document"] = "flatten",
            ["UiFlat.Scene"] = "prepare_demands",
            ["UiDemand.Scene"] = "solve",
            ["UiSolved.Scene"] = "plan",
            ["UiPlan.Scene"] = "specialize_kernel",
            ["UiKernel.Spec"] = "compile",
            ["UiKernel.Payload"] = "materialize",
        })

        require("examples.ui2.ui2_session_state")(T)
        require("examples.ui2.ui2_demo_app_state")(T)

        require("examples.ui2.ui2_decl_document")(T)
        require("examples.ui2.ui2_bound_document")(T)
        require("examples.ui2.ui2_flat_scene")(T)
        require("examples.ui2.ui2_demand_scene")(T)
        require("examples.ui2.ui2_solved_scene")(T)
        require("examples.ui2.ui2_plan_scene")(T)
        require("examples.ui2.ui2_kernel_render")(T)
    end,
}
