local Fixture = require("frontendc.frontend_machine_fixture")
local Profile = require("frontendc.profile_common")

return function(T, U, P)
    local profiles = {}

    function profiles.profile_emit_lua()
        local machine = select(1, Fixture.new_tokenize_machine_and_target_ctx(T))
        local info = Profile.profile_run(10000, function()
            local out = machine:emit_lua()
            return #out.files
        end)
        Profile.print_summary("frontendc emit_lua", info)
    end

    function profiles.profile_install_generated()
        local machine, target_ctx = Fixture.new_tokenize_machine_and_target_ctx(T)
        local info = Profile.profile_run(5000, function()
            local fresh_ctx = {
                TargetText = { Spec = {} },
                TargetToken = target_ctx.TargetToken,
                TargetSource = target_ctx.TargetSource,
            }
            machine:install_generated(fresh_ctx)
            return (type(fresh_ctx.TargetText.Spec.tokenize) == "function") and 1 or 0
        end)
        Profile.print_summary("frontendc install_generated", info)
    end

    return profiles
end
