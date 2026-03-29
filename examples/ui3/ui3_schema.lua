local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui3.ui3_asdl"),
    },

    -- ---------------------------------------------------------------------
    -- ui3 pipeline contract
    -- ---------------------------------------------------------------------
    -- ui3 is the fresh architecture line for the red-teamed lower pipeline:
    --
    --   UiDecl
    --     -> bind
    --   UiBound
    --     -> flatten
    --   UiFlat
    --     -> lower_geometry      -> UiGeometryInput
    --     -> lower_render_facts  -> UiRenderFacts
    --     -> lower_query_facts   -> UiQueryFacts
    --
    --   UiGeometryInput
    --     -> solve
    --   UiGeometry
    --
    --   UiGeometry + UiRenderFacts
    --     -> project_render_scene
    --   UiRenderScene
    --     -> schedule_render_machine_ir
    --   UiRenderMachineIR
    --     -> define_machine
    --   UiMachine.Render
    --     -> Unit
    --
    --   UiGeometry + UiQueryFacts
    --     -> project_query_scene
    --   UiQueryScene
    --     -> organize_query_machine_ir
    --   UiQueryMachineIR
    --     -> reducer/query execution
    --
    -- Side modules:
    --   UiCore, UiAsset, UiInput, UiSession, UiIntent, UiApply
    pipeline = {
        "UiInput",
        "UiSession",
        "UiDecl",
        "UiBound",
        "UiFlat",
        "UiGeometryInput",
        "UiGeometry",
        "UiRenderFacts",
        "UiRenderScene",
        "UiRenderMachineIR",
        "UiQueryFacts",
        "UiQueryScene",
        "UiQueryMachineIR",
        "UiMachine",
    },

    install = function(T)
        -- -----------------------------------------------------------------
        -- Boundary inventory (stub-only scaffold)
        -- -----------------------------------------------------------------
        -- ui3 is intentionally scaffold-first. The live implementations should
        -- be added one boundary at a time in pipeline order.
        U.install_stubs(T, {
            ["UiSession.State"] = { "initial", "apply_with_intents", "apply" },
            ["UiDecl.Document"] = "bind",
            ["UiBound.Document"] = "flatten",
            ["UiFlat.Scene"] = { "lower_geometry", "lower_render_facts", "lower_query_facts" },
            ["UiGeometryInput.Scene"] = "solve",
            ["UiGeometry.Scene"] = { "project_render_scene", "project_query_scene" },
            ["UiRenderScene.Scene"] = "schedule_render_machine_ir",
            ["UiRenderMachineIR.Render"] = "define_machine",
            ["UiQueryScene.Scene"] = "organize_query_machine_ir",
            ["UiMachine.RenderGen"] = "compile",
            ["UiMachine.Render"] = "materialize",
        })

        -- -----------------------------------------------------------------
        -- Explicit side-input policy
        -- -----------------------------------------------------------------
        -- All extra dependencies must remain explicit in boundary signatures.
        -- Examples expected during implementation:
        --   UiSession.State.initial(viewport)
        --   session:apply_with_intents(query_ir, event)
        --   session:apply(query_ir, event)
        --   document:bind(assets)
        --   bound:flatten(viewport)
        --   flat:lower_geometry(assets)
        --   flat:lower_render_facts()
        --   flat:lower_query_facts()
        --   geometry_input:solve()
        --   geometry:project_render_scene(render_facts)
        --   render_scene:schedule_render_machine_ir()
        --   render_ir:define_machine()
        --   machine.gen:compile(target)
        --   machine:materialize(target, assets, state)
        --   geometry:project_query_scene(query_facts)
        --   query_scene:organize_query_machine_ir()
    end,
}
