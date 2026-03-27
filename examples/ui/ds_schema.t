local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui.ui_asdl"),
        require("examples.ui.ds_asdl"),
    },

    pipeline = {
        "DesignDecl",
        "DesignResolved",
        "DesignApply",
        "UiDecl",
    },
}
