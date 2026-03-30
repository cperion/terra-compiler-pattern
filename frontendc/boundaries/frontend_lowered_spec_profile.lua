local U = require("unit")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_define_machine()
        error("scaffold: fill in profile for FrontendLowered.Spec:define_machine", 2)
        -- TODO: build larger workload for profiling input:define_machine()
    end

    return profiles
end
