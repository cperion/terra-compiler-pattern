local U = require("unit")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_install()
        error("scaffold: fill in profile for MoreFunLuaJIT.Spec:install", 2)
        -- TODO: build larger workload for profiling input:install()
    end

    return profiles
end
