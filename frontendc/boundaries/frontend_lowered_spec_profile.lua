local Fixture = require("frontendc.frontend_machine_fixture")
local Profile = require("frontendc.profile_common")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_define_machine()
        local pool_size = 512
        local iters = 10000
        local pool = {}
        for i = 1, pool_size do
            local source = select(1, Fixture.new_source_spec_and_target_ctx(T))
            pool[i] = source:check():lower()
        end

        local info = Profile.profile_run(iters, function(i)
            local machine = pool[((i - 1) % pool_size) + 1]:define_machine()
            return #machine.parse.result_ctors + #machine.parse.machine.rules + #machine.tokenize.machine.fixed_dispatches
        end)
        Profile.print_summary("frontendc define_machine", info)
    end

    return profiles
end
