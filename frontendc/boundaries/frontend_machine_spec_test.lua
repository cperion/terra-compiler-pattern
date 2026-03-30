local U = require("unit")

return function(T, U, P)
    local tests = {}

    function tests.test_emit_lua()
        error("scaffold: fill in test for FrontendMachine.Spec:emit_lua", 2)
        -- local input = T.FrontendMachine.Spec(...)
        -- local out = input:emit_lua()
        -- assert(out ~= nil)
    end

    function tests.test_install_generated()
        error("scaffold: fill in test for FrontendMachine.Spec:install_generated", 2)
        -- local input = T.FrontendMachine.Spec(...)
        -- local out = input:install_generated()
        -- assert(out ~= nil)
    end

    return tests
end
