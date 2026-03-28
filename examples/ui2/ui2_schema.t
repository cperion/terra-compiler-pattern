local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui2.ui2_asdl"),
    },

    -- ---------------------------------------------------------------------
    -- ui2 pipeline contract
    -- ---------------------------------------------------------------------
    -- This schema deliberately models ui2 as a single semantic spine:
    --
    --   UiDecl
    --     -> bind
    --   UiBound
    --     -> flatten
    --   UiFlat
    --     -> prepare_demands
    --   UiDemand
    --     -> solve
    --   UiSolved
    --     -> plan
    --   UiPlan
    --     -> specialize_kernel
    --   UiKernel.Render
    --     -> split
    --   UiKernel.Spec
    --     -> compile
    --   Unit
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
    --   - UiDecl is the authored tree language
    --   - UiBound keeps tree structure but binds refs/defaults/facets
    --   - UiFlat makes topology explicit and region-local
    --   - UiDemand is the solver input language
    --   - UiSolved is the node-centered solved scene
    --   - UiPlan is the packed render/query projection
    --   - UiKernel is the render-only machine phase with spec/payload split
    --
    -- The crucial bake/live split appears at the end:
    --   - UiKernel.Spec     = baked machine facts that affect code / ABI
    --   - UiKernel.Payload  = live render payload loaded into state_t
    --
    -- This keeps the render runner stable while ordinary scene edits mainly
    -- change payload, not code.
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

    install = function(T)
        -- -----------------------------------------------------------------
        -- Boundary inventory (stubs for the intended implementation path)
        -- -----------------------------------------------------------------
        -- These stubs are installed on exact ASDL classes so the inspect/
        -- scaffold/status tooling can see the intended boundary surface.
        --
        -- Pure compiler spine:
        --   UiDecl.Document:bind()               -> UiBound.Document
        --   UiBound.Document:flatten()          -> UiFlat.Scene
        --   UiFlat.Scene:prepare_demands()      -> UiDemand.Scene
        --   UiDemand.Scene:solve()              -> UiSolved.Scene
        --   UiSolved.Scene:plan()               -> UiPlan.Scene
        --   UiPlan.Scene:specialize_kernel()           -> UiKernel.Render
        --   UiKernel.Spec:compile(target)              -> Unit
        --
        -- Runtime-side materialization helper:
        --   UiKernel.Payload:materialize(target, assets, state)
        --
        -- Runtime-side reducer helpers:
        --   UiSession.State.initial(viewport)                   -> UiSession.State
        --   UiSession.State:apply_with_intents(plan, event)     -> UiApply.Result
        --   UiSession.State:apply(plan, event)                  -> UiSession.State
        --
        -- Reducer-side side modules involved here:
        --   UiInput.Event   raw event language
        --   UiIntent.Event  semantic output language
        --   UiApply.Result  explicit coupling of next state + intents
        --
        -- Note that compile/materialize are intentionally split:
        --   spec:compile(target) answers "what machine code + ABI do we install?"
        --   payload:materialize(target, assets, state) answers "what live payload do we load into it?"
        --
        -- This split is the core result of the leaf-first design work.
        U.install_stubs(T, {
            ["UiSession.State"] = { "initial", "apply_with_intents", "apply" },
            ["UiDecl.Document"] = "bind",
            ["UiBound.Document"] = "flatten",
            ["UiFlat.Scene"] = "prepare_demands",
            ["UiDemand.Scene"] = "solve",
            ["UiSolved.Scene"] = "plan",
            ["UiPlan.Scene"] = "specialize_kernel",
            ["UiKernel.Spec"] = "compile",
            ["UiKernel.Payload"] = "materialize",
        })

        -- Install real boundary implementations after stubs so the boundary
        -- inventory remains visible to tooling while implemented methods simply
        -- override their corresponding stub.
        require("examples.ui2.ui2_session_state")(T)
        require("examples.ui2.ui2_decl_document")(T)
        require("examples.ui2.ui2_bound_document")(T)
        require("examples.ui2.ui2_flat_scene")(T)
        require("examples.ui2.ui2_demand_scene")(T)
        require("examples.ui2.ui2_solved_scene")(T)
        require("examples.ui2.ui2_plan_scene")(T)
        require("examples.ui2.ui2_kernel_render")(T)

        -- -----------------------------------------------------------------
        -- Explicit side-input policy
        -- -----------------------------------------------------------------
        -- ui2 phases are allowed to depend on additional explicit arguments,
        -- but those dependencies must be ordinary function arguments, never
        -- hidden globals, registries, or ambient context objects.
        --
        -- Expected examples:
        --   UiSession.State.initial(viewport)
        --   session:apply_with_intents(plan, event)
        --   session:apply(plan, event)
        --   document:bind(assets)
        --   bound:flatten(viewport)
        --   flat:prepare_demands(assets)
        --   demand:solve(assets)
        --   spec:compile(target)
        --   payload:materialize(target, assets, state)
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
        -- UiPlan.Region remains authoritative for top-level scene routing
        -- semantics such as z-order / modality / pointer consumption.
        --
        -- The intended query policy is:
        --   1. choose/scan regions in region order
        --   2. consult region modal / pointer-consumption semantics
        --   3. scan that region's hit span inside UiPlan.hits
        --
        -- Therefore HitItem stays lean and does NOT duplicate region-level
        -- modal/pointer-consumption facts onto every hit record.

        -- -----------------------------------------------------------------
        -- Clip index policy
        -- -----------------------------------------------------------------
        -- UiPlan.clips and UiKernel.Payload.clips are scene-global clip tables.
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
        --   - UiSolved carries CustomDraw with full solved VisualState
        --   - UiPlan carries CustomBatch with DrawState + payload items
        --   - UiKernel will carry CustomKind batches plus custom payload arrays
        --
        -- This keeps the custom path structurally explicit instead of smuggling
        -- it through ad hoc runtime interpretation. Backend-specific execution
        -- details still belong to the final compile/materialize stages.

        -- -----------------------------------------------------------------
        -- Expected implementation order
        -- -----------------------------------------------------------------
        -- Recommended coding order, one boundary at a time:
        --   1. UiDecl.Document:bind
        --   2. UiBound.Document:flatten
        --   3. UiFlat.Scene:prepare_demands
        --   4. UiDemand.Scene:solve
        --   5. UiSolved.Scene:plan
        --   6. UiPlan.Scene:specialize_kernel
        --   7. UiKernel.Spec:compile
        --   8. UiKernel.Payload:materialize
        --
        -- This order follows the current design discovery exactly and keeps the
        -- leaf-driven kernel story aligned with the actual implementation path.
    end,
}
