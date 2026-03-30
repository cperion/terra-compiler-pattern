local U = require("unit")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_check()
        error("scaffold: fill in profile for FrontendSource.Spec:check", 2)
        -- TODO: build larger workload for profiling input:check()
    end

    return profiles
end
