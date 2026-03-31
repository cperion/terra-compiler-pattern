local Fixture = require("frontendc.frontend_machine_fixture")
local Profile = require("frontendc.profile_common")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_check()
        local pool_size = 512
        local iters = 10000
        local pool = {}
        for i = 1, pool_size do
            pool[i] = select(1, Fixture.new_source_spec_and_target_ctx(T))
        end

        local info = Profile.profile_run(iters, function(i)
            local checked = pool[((i - 1) % pool_size) + 1]:check()
            return #checked.parser.rules + #checked.lexer.tokens
        end)
        Profile.print_summary("frontendc check", info)
    end

    return profiles
end
