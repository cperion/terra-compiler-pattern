local U = require("unit")

return function(T, U, P)
    local benches = {}

    function benches.bench_define_machine()
        error("scaffold: fill in bench for MoreFunLowered.Spec:define_machine", 2)
        -- local iters = 1000
        -- TODO: time repeated calls to input:define_machine()
    end

    return benches
end
