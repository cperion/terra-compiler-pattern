local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui.ui_asdl"),
    },

    pipeline = {
        "UiInput",
        "UiSession",
        "UiDecl",
        "UiLaid",
        "UiBatched",
    },

    install = function(T)
        local Backend = require("examples.ui.ui_batched_compile")
        local SessionApply = require("examples.ui.ui_session_apply")
        local Layout = require("examples.ui.ui_decl_layout")
        local Batching = require("examples.ui.ui_laid_batch")
        local Routing = require("examples.ui.ui_laid_route")

        SessionApply.install(T)
        Layout.install(T)
        Batching.install(T)
        Routing.install(T)
        Backend.install(T)
    end,
}
