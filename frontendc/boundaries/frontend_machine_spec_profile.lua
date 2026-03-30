local U = require("unit")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_emit_lua()
        error("scaffold: fill in profile for FrontendMachine.Spec:emit_lua", 2)
        -- TODO: build larger workload for profiling input:emit_lua()
    end

    function profiles.profile_install_generated()
        error("scaffold: fill in profile for FrontendMachine.Spec:install_generated", 2)
        -- TODO: build larger workload for profiling input:install_generated()
    end

    return profiles
end
