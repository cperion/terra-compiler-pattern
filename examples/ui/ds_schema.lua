local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui.ui_asdl"),
        require("examples.ui.ds_asdl"),
    },

    pipeline = {
        "DesignDecl",
        "DesignResolved",
        "DesignUse",
        "UiDecl",
    },

    install = function(T)
        local Resolve = require("examples.ui.ds_decl_resolve")
        local Apply = require("examples.ui.ds_use_apply")

        Resolve.install(T)
        Apply.install(T)
    end,
}
