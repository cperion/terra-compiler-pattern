local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui.ui_asdl"),
    },

    pipeline = {
        "UiInput",
        "UiSession",
        "UiDecl",
        "UiBound",
        "UiFlat",
        "UiDemand",
        "UiResolved",
        "UiPlan",
    },

    install = function(T)
        require("examples.ui.ui_session_state")(T)
        require("examples.ui.ui_decl_document")(T)
        require("examples.ui.ui_batched")(T)
    end,
}
