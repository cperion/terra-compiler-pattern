local U = require("unit")

return function(T, U, P)
    local benches = {}

    function benches.bench_lower_luajit()
        error("scaffold: fill in bench for MoreFunMachine.Spec:lower_luajit", 2)
        -- local iters = 1000
        -- TODO: time repeated calls to input:lower_luajit()
    end

    return benches
end
