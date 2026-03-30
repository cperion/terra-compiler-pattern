local U = require("unit")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_lower()
        error("scaffold: fill in profile for FrontendChecked.Spec:lower", 2)
        -- TODO: build larger workload for profiling input:lower()
    end

    return profiles
end
