local U = require("unit")

return U.spec {
    texts = {
        require("examples.js.js_asdl"),
        require("examples.js.js_lex_asdl"),
    },

    -- ---------------------------------------------------------------------
    -- JS compiler pipeline contract
    -- ---------------------------------------------------------------------
    --   text
    --     -> lex
    --   JsLex
    --   JsSource
    --     -> resolve
    --   JsResolved
    --     -> compile
    --   JsMachine (closure tree Units)
    --
    -- Side modules:
    --   JsCore (shared operator/kind enums)
    pipeline = {
        "JsSurface",
        "JsSource",
        "JsResolved",
        "JsMachine",
    },

    install = function(T)
        -- -----------------------------------------------------------------
        -- Boundary inventory
        -- -----------------------------------------------------------------
        -- Leaf-first workflow:
        --   1. trust Layer 0: js_compile (JsResolved -> closure tree)
        --   2. then trust Layer 1: js_resolve (JsSource -> JsResolved)
        --   3. then add parser (text -> JsSource)

        require("examples.js.js_runtime").install(T)
        require("examples.js.js_compile")(T)
        require("examples.js.js_resolve")(T)
        require("examples.js.js_lex").install(T)
        require("examples.js.js_lower")(T)
        require("examples.js.js_module_lower")(T)
        require("examples.js.js_module_resolve")(T)
        require("examples.js.js_module_compile")(T)
        require("examples.js.js_parse")(T)

        U.install_stubs(T, {
        })
    end,
}
