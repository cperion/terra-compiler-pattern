local U = require("unit")

return function(T, U, P)
    local benches = {}

    function benches.bench_lower()
        error("scaffold: fill in bench for MoreFunSource.Spec:lower", 2)
        -- local iters = 1000
        -- TODO: time repeated calls to input:lower()
    end

    return benches
end
