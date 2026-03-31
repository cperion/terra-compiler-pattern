local U = require("unit")

return function(T, U, P)
    local tests = {}

    function tests.test_install()
        error("scaffold: fill in test for MoreFunLuaJIT.Spec:install", 2)
        -- local input = T.MoreFunLuaJIT.Spec(...)
        -- local out = input:install()
        -- assert(out ~= nil)
    end

    return tests
end
