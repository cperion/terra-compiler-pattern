local Fixture = require("asdl2.asdl2_bench_fixture")

local M = {}

local function env_number(name, default)
    local v = os.getenv(name)
    local n = v and tonumber(v) or nil
    return n or default
end

function M.load_from_env()
    local scenario = os.getenv("ASDL2_INSTALL_SCENARIO") or "mixed"
    local mode = os.getenv("ASDL2_INSTALL_PROFILE_MODE") or "install_distinct"
    local products = env_number("ASDL2_INSTALL_PRODUCTS", 50)
    local fields = env_number("ASDL2_INSTALL_FIELDS", 6)
    local variants = env_number("ASDL2_INSTALL_VARIANTS", 4)
    local iters = env_number("ASDL2_INSTALL_ITERS", 40)

    if scenario == "small" then
        products, fields, variants = 8, 3, 3
    elseif scenario == "wide" then
        fields, variants = 12, 8
    end

    local base_machine = Fixture.build_machine(1, products, fields, variants)
    local base_ctx = Fixture.new_ctx()
    assert(base_machine:install(base_ctx) ~= nil)

    local pool = {}
    local ctx_pool = {}
    for i = 1, iters + 64 do
        pool[i] = Fixture.build_machine(i + 1000, products, fields, variants)
        ctx_pool[i] = Fixture.new_ctx()
    end

    local function run_install_distinct()
        local sink = 0
        for i = 1, iters do
            if pool[i]:install(ctx_pool[i]) ~= nil then sink = sink + 1 end
        end
        return sink
    end

    local function run_build_plus_install()
        local sink = 0
        for i = 1, iters do
            if Fixture.build_machine(i + 200000, products, fields, variants):install(Fixture.new_ctx()) ~= nil then
                sink = sink + 1
            end
        end
        return sink
    end

    return {
        mode = mode,
        scenario = scenario,
        products = products,
        fields = fields,
        variants = variants,
        iters = iters,
        run = ({
            install_distinct = run_install_distinct,
            build_plus_install = run_build_plus_install,
        })[mode],
    }
end

function M.run_from_env()
    local workload = M.load_from_env()
    assert(workload.run, "unknown ASDL2_INSTALL_PROFILE_MODE: " .. tostring(workload.mode))
    print(
        "asdl2_install_profile",
        workload.mode,
        workload.scenario,
        workload.products,
        workload.fields,
        workload.variants,
        workload.iters,
        workload.run()
    )
end

return M
