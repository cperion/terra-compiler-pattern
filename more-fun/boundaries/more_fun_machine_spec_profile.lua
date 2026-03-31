local U = require("unit")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_lower_luajit()
        error("scaffold: fill in profile for MoreFunMachine.Spec:lower_luajit", 2)
        -- TODO: build larger workload for profiling input:lower_luajit()
    end

    return profiles
end
