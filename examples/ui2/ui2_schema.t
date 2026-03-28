local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui2.ui2_asdl"),
    },

    pipeline = {
        "UiInput",
        "UiSession",
        "UiDecl",
        "UiBound",
        "UiFlat",
        "UiDemand",
        "UiSolved",
        "UiPlan",
        "UiKernel",
    },
}
