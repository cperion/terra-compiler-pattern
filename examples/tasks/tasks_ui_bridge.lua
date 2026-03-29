local F = require("fun")

local Bridge = {}

function Bridge.apply_ui(state, ui_apply_result)
    local screen = state:project_view()
    return F.iter(ui_apply_result.intents)
        :map(function(intent)
            return screen:decode(intent).events
        end)
        :reduce(function(app_state, batch)
            return F.iter(batch):reduce(function(inner_state, event)
                return inner_state:apply(event)
            end, app_state)
        end, state)
end

return Bridge
