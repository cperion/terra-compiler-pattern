local Fixture = require("asdl2.asdl2_source_fixture")

local M = {}

local function env_number(name, default)
    local v = os.getenv(name)
    local n = v and tonumber(v) or nil
    return n or default
end

function M.load_from_env()
    local scenario = os.getenv("ASDL2_CLASSIFY_LOWER_SCENARIO") or "mixed"
    local mode = os.getenv("ASDL2_CLASSIFY_LOWER_PROFILE_MODE") or "classify_distinct"
    local types = env_number("ASDL2_CLASSIFY_LOWER_TYPES", 500)
    local fields = env_number("ASDL2_CLASSIFY_LOWER_FIELDS", 6)
    local variants = env_number("ASDL2_CLASSIFY_LOWER_VARIANTS", 4)
    local iters = env_number("ASDL2_CLASSIFY_LOWER_ITERS", 80)

    if scenario == "small" then
        types, fields, variants = 64, 3, 3
    elseif scenario == "wide" then
        fields, variants = 12, 8
    end

    local base = Fixture.build_source(1, types, fields, variants):catalog()
    assert(base:classify_lower().records[1] ~= nil)

    local pool = {}
    for i = 1, iters + 256 do pool[i] = Fixture.build_source(i + 10000, types, fields, variants):catalog() end

    local function run_classify_distinct()
        local sink = 0
        for i = 1, iters do sink = sink + pool[i]:classify_lower().records[1].header.class_id end
        return sink
    end

    local function run_build_plus_lower()
        local sink = 0
        for i = 1, iters do sink = sink + Fixture.build_source(i + 200000, types, fields, variants):catalog():classify_lower().records[1].header.class_id end
        return sink
    end

    local function run_classify_existing()
        local sink = 0
        for i = 1, iters do sink = sink + base:classify_lower().records[1].header.class_id end
        return sink
    end

    return {
        mode = mode,
        scenario = scenario,
        types = types,
        fields = fields,
        variants = variants,
        iters = iters,
        run = ({
            classify_distinct = run_classify_distinct,
            build_plus_lower = run_build_plus_lower,
            classify_existing = run_classify_existing,
        })[mode],
    }
end

function M.run_from_env()
    local workload = M.load_from_env()
    assert(workload.run, "unknown ASDL2_CLASSIFY_LOWER_PROFILE_MODE: " .. tostring(workload.mode))
    print(
        "asdl2_classify_lower_profile",
        workload.mode,
        workload.scenario,
        workload.types,
        workload.fields,
        workload.variants,
        workload.iters,
        workload.run()
    )
end

return M
