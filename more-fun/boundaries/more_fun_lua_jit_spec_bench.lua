local U = require("unit")

return function(T, U, P)
    local benches = {}

    function benches.bench_install()
        error("scaffold: fill in bench for MoreFunLuaJIT.Spec:install", 2)
        -- local iters = 1000
        -- TODO: time repeated calls to input:install()
    end

    return benches
end
