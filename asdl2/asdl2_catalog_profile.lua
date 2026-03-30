local Fixture = require("asdl2.asdl2_source_fixture")

local M = {}

local function env_number(name, default)
    local v = os.getenv(name)
    local n = v and tonumber(v) or nil
    return n or default
end

function M.load_from_env()
    local scenario = os.getenv("ASDL2_CATALOG_SCENARIO") or "mixed"
    local mode = os.getenv("ASDL2_CATALOG_PROFILE_MODE") or "catalog_distinct"
    local types = env_number("ASDL2_CATALOG_TYPES", 500)
    local fields = env_number("ASDL2_CATALOG_FIELDS", 6)
    local variants = env_number("ASDL2_CATALOG_VARIANTS", 4)
    local iters = env_number("ASDL2_CATALOG_ITERS", 80)

    if scenario == "small" then
        types, fields, variants = 64, 3, 3
    elseif scenario == "wide" then
        fields, variants = 12, 8
    end

    local base = Fixture.build_source(1, types, fields, variants)
    assert(base:catalog().definitions[1] ~= nil)

    local pool = {}
    for i = 1, iters + 256 do pool[i] = Fixture.build_source(i + 10000, types, fields, variants) end

    local function run_catalog_distinct()
        local sink = 0
        for i = 1, iters do sink = sink + #pool[i]:catalog().definitions end
        return sink
    end

    local function run_build_plus_catalog()
        local sink = 0
        for i = 1, iters do sink = sink + #Fixture.build_source(i + 200000, types, fields, variants):catalog().definitions end
        return sink
    end

    local function run_catalog_existing()
        local sink = 0
        for i = 1, iters do sink = sink + #base:catalog().definitions end
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
            catalog_distinct = run_catalog_distinct,
            build_plus_catalog = run_build_plus_catalog,
            catalog_existing = run_catalog_existing,
        })[mode],
    }
end

function M.run_from_env()
    local workload = M.load_from_env()
    assert(workload.run, "unknown ASDL2_CATALOG_PROFILE_MODE: " .. tostring(workload.mode))
    print(
        "asdl2_catalog_profile",
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
