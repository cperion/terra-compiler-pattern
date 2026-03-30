local U = require("unit")

return function(T, U, P)
    local benches = {}

    function benches.bench_check()
        error("scaffold: fill in bench for FrontendSource.Spec:check", 2)
        -- local iters = 1000
        -- TODO: time repeated calls to input:check()
    end

    return benches
end
