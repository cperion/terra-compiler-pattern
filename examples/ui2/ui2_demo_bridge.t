local Codec = require("examples.ui2.ui2_demo_codec")

local Bridge = {}

-- Thin helpers used by the demo file.
--
-- The real app-patterned work now lives in:
--   - examples/ui2/ui2_demo_asdl.t
--   - examples/ui2/ui2_demo_app_state.t
--
-- This bridge only provides small convenience wrappers for the demo source
-- builder and loop.

function Bridge.command_ref(T, key)
    return Codec.command_ref(T, key)
end

function Bridge.semantic_ref(T, key)
    return Codec.semantic_ref(T, key)
end

function Bridge.initial_state(T)
    return T.DemoApp.State.initial()
end

function Bridge.apply_ui(T, state, ui_apply_result)
    return state:apply_ui(ui_apply_result)
end

function Bridge.target_name(target)
    return target and target.kind or "none"
end

return Bridge
