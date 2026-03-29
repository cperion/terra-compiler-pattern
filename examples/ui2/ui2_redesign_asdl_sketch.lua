return [=[
-- ui2 redesign ASDL sketch
--
-- Purpose:
--   separate leaf-first machine-driven ASDL sketch file
--   not wired into the live schema yet
--
-- Working source of truth for the redesign process:
--   examples/ui2/leaf-first-redesign.md
--
-- Current target architecture being sketched here:
--
--   UiDecl
--     -> bind
--   UiBound
--     -> flatten
--   UiFlat
--     -> lower_geometry
--   UiGeometryInput
--     -> solve
--   UiGeometry
--     -> project_render_machine_ir
--   UiRenderMachineIR
--     -> define_machine
--   UiMachine
--     -> Unit
--
--   UiGeometry
--     -> project_query_machine_ir
--   UiQueryMachineIR
--     -> reducer/query execution
--
-- Notes:
--   - this file is intentionally separate from examples/ui2/ui2_asdl.lua
--   - use this file for redesign iteration before rewriting the live ASDL
--   - placeholders exist only to keep the sketch structurally explicit

module UiGeometryInput {
    -- first shared pure phase to sketch concretely
    Placeholder = (
        number _placeholder
    ) unique
}

module UiGeometry {
    -- shared solved geometry coupling point
    Placeholder = (
        number _placeholder
    ) unique
}

module UiRenderMachineIR {
    -- intended stronger naming than UiKernel
    -- target split:
    --   Shape
    --   Input
    --   StateSchema
    Placeholder = (
        number _placeholder
    ) unique
}

module UiQueryMachineIR {
    -- lean query/reducer-facing machine IR
    Placeholder = (
        number _placeholder
    ) unique
}

module UiMachine {
    -- canonical machine layer remains:
    --   Gen
    --   Param
    --   State
    Placeholder = (
        number _placeholder
    ) unique
}
]=]
