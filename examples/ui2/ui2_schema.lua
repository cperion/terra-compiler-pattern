local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui2.ui2_asdl"),
    },

    -- ---------------------------------------------------------------------
    -- ui2 pipeline contract
    -- ---------------------------------------------------------------------
    -- This schema now follows the leaf-first redraw of the lower pipeline:
    --
    --   UiDecl
    --     -> bind
    --   UiBound
    --     -> flatten
    --   UiFlat
    --     -> lower
    --   UiLowered
    --     -> solve_geometry
    --   UiGeometry
    --     -> project_render / project_query
    --   UiRender
    --     -> specialize_kernel
    --   UiKernel.Render
    --     -> define_machine
    --   UiMachine.Gen
    --     -> compile
    --   Unit
    --
    -- and in parallel for interaction:
    --
    --   UiGeometry
    --     -> project_query
    --   UiQuery
    --     -> apply / apply_with_intents
    --
    -- Side modules:
    --   UiCore    shared vocabulary
    --   UiAsset   explicit compiler-side resource catalog
    --   UiInput   raw UI input language
    --   UiSession pure reducer-owned interaction state
    --   UiIntent  semantic reducer output language
    --   UiApply   reducer result coupling state + intents
    --
    -- Architectural intent:
    --   - UiFlat is the explicit flat topology + facet split
    --   - UiLowered is the orthogonal lowered fact language
    --   - UiGeometry solves only geometry
    --   - UiRender is the packed render projection
    --   - UiQuery is the packed query/reducer projection
    --   - UiKernel is the render-only machine IR
    pipeline = {
        "UiInput",
        "UiSession",
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
        -- -----------------------------------------------------------------
        -- Boundary inventory (stubs for the new lower-pipeline rewrite)
        -- -----------------------------------------------------------------
        -- This schema is intentionally stub-only for the redraw step. The old
        -- implementations are not loaded here because the ASDL has moved to a
        -- new phase split and the next implementation pass should port one
        -- boundary at a time in pipeline order.
        --
        -- Pure compiler spine:
        --   UiDecl.Document:bind()                    -> UiBound.Document
        --   UiBound.Document:flatten()               -> UiFlat.Scene
        --   UiFlat.Scene:lower()                     -> UiLowered.Scene
        --   UiLowered.Scene:solve_geometry()         -> UiGeometry.Scene
        --   UiGeometry.Scene:project_render()        -> UiRender.Scene
        --   UiGeometry.Scene:project_query()         -> UiQuery.Scene
        --   UiRender.Scene:specialize_kernel()       -> UiKernel.Render
        --   UiKernel.Render:define_machine()         -> UiMachine.Render
        --   UiMachine.Gen:compile(target)            -> Unit
        --
        -- Runtime-side materialization helper:
        --   UiMachine.Render:materialize(target, assets, state)
        --
        -- Runtime-side reducer helpers:
        --   UiSession.State.initial(viewport)                    -> UiSession.State
        --   UiSession.State:apply_with_intents(query, event)     -> UiApply.Result
        --   UiSession.State:apply(query, event)                  -> UiSession.State
        U.install_stubs(T, {
            ["UiSession.State"] = { "initial", "apply_with_intents", "apply" },
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

        -- -----------------------------------------------------------------
        -- Explicit side-input policy
        -- -----------------------------------------------------------------
        -- ui2 phases are allowed to depend on additional explicit arguments,
        -- but those dependencies must be ordinary function arguments, never
        -- hidden globals, registries, or ambient context objects.
        --
        -- Expected examples:
        --   UiSession.State.initial(viewport)
        --   session:apply_with_intents(query, event)
        --   session:apply(query, event)
        --   document:bind(assets)
        --   bound:flatten(viewport)
        --   flat:lower(assets)
        --   lowered:solve_geometry(assets)
        --   geometry:project_render()
        --   geometry:project_query()
        --   machine.gen:compile(target)
        --   machine:materialize(target, assets, state)
        --
        -- The exact auxiliary argument list can still evolve during
        -- implementation, but the rule is fixed now:
        --   every dependency must be explicit in the boundary signature.
        --
        -- This preserves memoize correctness and prevents hidden environment
        -- state from leaking into the pure layer.

        -- -----------------------------------------------------------------
        -- Region-first routing policy
        -- -----------------------------------------------------------------
        -- UiQuery.Region remains authoritative for top-level scene routing
        -- semantics such as z-order / modality / pointer consumption.
        --
        -- The intended query policy is:
        --   1. choose/scan regions in region order
        --   2. consult region modal / pointer-consumption semantics
        --   3. scan that region's hit span inside UiQuery.hits
        --
        -- Therefore HitItem stays lean and does NOT duplicate region-level
        -- modal/pointer-consumption facts onto every hit record.

        -- -----------------------------------------------------------------
        -- Clip index policy
        -- -----------------------------------------------------------------
        -- UiRender.clips and UiKernel.Payload.clips are scene-global clip tables.
        -- DrawState.clip_index refers to that scene-global table.
        --
        -- Regions span draws/hits/focus/etc., but clip indices themselves are
        -- not region-local. This is intentional and should stay consistent
        -- through planning, kernel specialization, and runtime materialization.

        -- -----------------------------------------------------------------
        -- Custom-family policy
        -- -----------------------------------------------------------------
        -- Custom render families are first-class through the lower pipeline.
        --
        -- In particular:
        --   - UiLowered carries CustomDecor / CustomContent as lowered facts
        --   - UiRender carries CustomBatch with DrawState + payload items
        --   - UiKernel will carry CustomKind batches plus custom payload arrays
        --
        -- This keeps the custom path structurally explicit instead of smuggling
        -- it through ad hoc runtime interpretation. Backend-specific execution
        -- details still belong to the final machine compile/materialize stages.

        -- -----------------------------------------------------------------
        -- Expected implementation order
        -- -----------------------------------------------------------------
        -- Recommended coding order, one boundary at a time:
        --   1. UiDecl.Document:bind
        --   2. UiBound.Document:flatten
        --   3. UiFlat.Scene:lower
        --   4. UiLowered.Scene:solve_geometry
        --   5. UiGeometry.Scene:project_render
        --   6. UiGeometry.Scene:project_query
        --   7. UiRender.Scene:specialize_kernel
        --   8. UiKernel.Render:define_machine
        --   9. UiMachine.Gen:compile
        --  10. UiMachine.Render:materialize
        --
        -- This order follows the current design discovery exactly and keeps the
        -- leaf-driven kernel story aligned with the actual implementation path.
    end,
}
