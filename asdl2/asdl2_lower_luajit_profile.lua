local Fixture = require("asdl2.asdl2_bench_fixture")

local M = {}

local function env_number(name, default)
    local v = os.getenv(name)
    local n = v and tonumber(v) or nil
    return n or default
end

function M.load_from_env()
    local scenario = os.getenv("ASDL2_LOWER_LUAJIT_SCENARIO") or "mixed"
    local mode = os.getenv("ASDL2_LOWER_LUAJIT_PROFILE_MODE") or "lower_distinct"
    local records = env_number("ASDL2_LOWER_LUAJIT_RECORDS", 1000)
    local fields = env_number("ASDL2_LOWER_LUAJIT_FIELDS", 6)
    local variants = env_number("ASDL2_LOWER_LUAJIT_VARIANTS", 4)
    local iters = env_number("ASDL2_LOWER_LUAJIT_ITERS", 40)

    if scenario == "small" then
        records, fields, variants = 64, 3, 3
    elseif scenario == "wide" then
        fields, variants = 12, 8
    end

    local base = Fixture.build_machine(1, records, fields, variants)
    assert(base:lower_luajit().records[1] ~= nil)

    local pool = {}
    for i = 1, iters + 64 do
        pool[i] = Fixture.build_machine(i + 10000, records, fields, variants)
    end

    local function run_lower_distinct()
        local sink = 0
        for i = 1, iters do
            sink = sink + pool[i]:lower_luajit().records[1].header.class_id
        end
        return sink
    end

    local function run_build_plus_lower()
        local sink = 0
        for i = 1, iters do
            sink = sink + Fixture.build_machine(i + 200000, records, fields, variants):lower_luajit().records[1].header.class_id
        end
        return sink
    end

    return {
        mode = mode,
        scenario = scenario,
        records = records,
        fields = fields,
        variants = variants,
        iters = iters,
        run = ({
            lower_distinct = run_lower_distinct,
            build_plus_lower = run_build_plus_lower,
        })[mode],
    }
end

function M.run_from_env()
    local workload = M.load_from_env()
    assert(workload.run, "unknown ASDL2_LOWER_LUAJIT_PROFILE_MODE: " .. tostring(workload.mode))
    print(
        "asdl2_lower_luajit_profile",
        workload.mode,
        workload.scenario,
        workload.records,
        workload.fields,
        workload.variants,
        workload.iters,
        workload.run()
    )
end

return M
