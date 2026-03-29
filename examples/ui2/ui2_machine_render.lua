local U = require("unit")

-- ============================================================================
-- UiKernel.Render -> define_machine -> UiMachine.Render
-- ----------------------------------------------------------------------------
-- This file makes the canonical machine layer explicit without changing the
-- already-honest ui2 bake/live split.
--
-- Boundary meaning:
--   render Machine IR -> explicit gen/param/state machine
--
-- What define_machine consumes:
--   - UiKernel.Spec as code-shaping machine input
--   - UiKernel.Payload as stable render-machine environment input
--
-- What define_machine produces:
--   - UiMachine.Render(gen, param, state)
--
-- Current ui2 mapping:
--   - gen   = UiKernel.Spec
--   - param = UiKernel.Payload
--   - state = backend-neutral StateModel summarizing runtime-owned slot shape
--
-- Important:
--   StateModel is not the live mutable runtime value. It is the pure typed
--   statement of what mutable runtime state the realized Unit must own.
-- ============================================================================

local function state_model_for_payload(T, payload)
    return T.UiMachine.StateModel(
        #payload.batches,
        #payload.boxes,
        #payload.shadows,
        #payload.text_runs,
        #payload.images,
        #payload.customs
    )
end

return function(T)
    T.UiKernel.Render.define_machine = U.transition(function(render)
        return T.UiMachine.Render(
            T.UiMachine.Gen(render.spec),
            T.UiMachine.Param(render.payload),
            state_model_for_payload(T, render.payload)
        )
    end)
end
