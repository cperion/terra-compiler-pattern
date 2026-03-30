local U = require("unit")

return U.spec {
    texts = {
        require("examples.parser.parser_asdl"),
    },

    -- ---------------------------------------------------------------------
    -- Parser compiler pipeline
    -- ---------------------------------------------------------------------
    --   GrammarSource
    --     -> compile
    --   GrammarCompiled (closure tree that LuaJIT traces)
    pipeline = {
        "GrammarSource",
        "GrammarCompiled",
    },

    install = function(T)
        require("examples.parser.parser_compile")(T)
        require("examples.parser.parser_builder")(T)
    end,
}
