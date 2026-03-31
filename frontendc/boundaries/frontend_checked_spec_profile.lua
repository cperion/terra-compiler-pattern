local Fixture = require("frontendc.frontend_machine_fixture")
local Profile = require("frontendc.profile_common")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_lower()
        local pool_size = 512
        local iters = 10000
        local pool = {}
        for i = 1, pool_size do
            local source = select(1, Fixture.new_source_spec_and_target_ctx(T))
            pool[i] = source:check()
        end

        local info = Profile.profile_run(iters, function(i)
            local lowered = pool[((i - 1) % pool_size) + 1]:lower()
            return #lowered.parse.rules + #lowered.tokenize.fixed_dispatches + #lowered.tokenize.ident_dispatches
        end)
        Profile.print_summary("frontendc lower", info)
    end

    return profiles
end
