local U = require("unit")

return function(T, U, P)
    local tests = {}

    function tests.test_check()
        error("scaffold: fill in test for FrontendSource.Spec:check", 2)
        -- local input = T.FrontendSource.Spec(...)
        -- local out = input:check()
        -- assert(out ~= nil)
    end

    return tests
end
