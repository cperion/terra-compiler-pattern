local Schema = require("asdl2.asdl2_schema")
local T = Schema.ctx

local M = {}
local KEEP = {}

local function KS(s)
    KEEP[#KEEP + 1] = s
    return s
end

local function type_ref_for(i)
    if i % 11 == 0 then return "Extern.Type" .. tostring(i % 4) end
    if i % 6 == 0 then return "Product1" end
    if i % 5 == 0 then return "Sum" end
    if i % 3 == 0 then return "number" end
    if i % 2 == 0 then return "boolean" end
    return "string"
end

local function card_for(i)
    if i % 5 == 0 then return "?" end
    if i % 7 == 0 then return "*" end
    return ""
end

local function field_line(i)
    return string.format("%s%s field_%d", type_ref_for(i), card_for(i), i)
end

local function product_text(i, field_count)
    local fields = {}
    for j = 1, field_count do
        fields[j] = field_line(i * 11 + j)
    end
    return string.format("Product%d = (%s)%s", i, table.concat(fields, ", "), (i % 3 == 0) and " unique" or "")
end

local function ctor_text(i, field_count)
    local fields = {}
    for j = 1, field_count do
        fields[j] = field_line(i * 13 + j + 1000)
    end
    return string.format("V%d(%s)%s", i, table.concat(fields, ", "), (i % 2 == 0) and " unique" or "")
end

local function sum_text(variant_count, field_count)
    local ctors = {}
    local attrs = {}
    for i = 1, variant_count do
        ctors[i] = ctor_text(i, field_count)
    end
    for i = 1, math.max(1, math.floor(field_count / 2)) do
        attrs[i] = field_line(5000 + i)
    end
    return string.format("Sum = %s attributes (%s)", table.concat(ctors, " | "), table.concat(attrs, ", "))
end

local function module_name(seed)
    return "Bench" .. tostring(seed)
end

local function build_text(seed, type_count, field_count, variant_count)
    local lines = { "module " .. module_name(seed) .. " {" }
    for i = 1, type_count do
        lines[#lines + 1] = product_text(i, field_count)
    end
    lines[#lines + 1] = sum_text(variant_count, field_count)
    lines[#lines + 1] = "}"
    return KS(table.concat(lines, "\n"))
end

local function env_number(name, default)
    local v = os.getenv(name)
    local n = v and tonumber(v) or nil
    return n or default
end

function M.load_from_env()
    local scenario = os.getenv("ASDL2_PARSE_SCENARIO") or "mixed"
    local mode = os.getenv("ASDL2_PARSE_PROFILE_MODE") or "parse_distinct"
    local types = env_number("ASDL2_PARSE_TYPES", 1000)
    local fields = env_number("ASDL2_PARSE_FIELDS", 6)
    local variants = env_number("ASDL2_PARSE_VARIANTS", 4)
    local iters = env_number("ASDL2_PARSE_ITERS", 80)

    if scenario == "small" then
        types, fields, variants = 64, 3, 3
    elseif scenario == "wide" then
        fields, variants = 12, 8
    end

    local text_pool = nil
    local token_pool = nil
    if mode == "tokenize_distinct" or mode == "parse_distinct" then
        text_pool = {}
        for i = 1, iters do
            text_pool[i] = T.Asdl2Text.Spec(build_text(i + 10000, types, fields, variants))
        end
    end
    if mode == "parse_distinct" then
        token_pool = {}
        for i = 1, iters do
            token_pool[i] = text_pool[i]:tokenize()
        end
    end

    local base = T.Asdl2Text.Spec(build_text(1, types, fields, variants))
    local base_tokens = base:tokenize()
    assert(base_tokens:parse().definitions[1] ~= nil)

    local function run_tokenize_distinct()
        local sink = 0
        for i = 1, iters do
            local token_spec = text_pool[i]:tokenize()
            sink = sink + #token_spec.tokens
        end
        return sink
    end

    local function run_parse_distinct()
        local sink = 0
        for i = 1, iters do
            local source = token_pool[i]:parse()
            sink = sink + #source.definitions
        end
        return sink
    end

    local function run_build_plus_parse()
        local sink = 0
        for i = 1, iters do
            local source = T.Asdl2Text.Spec(build_text(i + 200000, types, fields, variants)):tokenize():parse()
            sink = sink + #source.definitions
        end
        return sink
    end

    local function run_parse_existing()
        local sink = 0
        for i = 1, iters do
            local source = base_tokens:parse()
            sink = sink + #source.definitions
        end
        return sink
    end

    local function run_tokenize_existing()
        local sink = 0
        for i = 1, iters do
            local token_spec = base:tokenize()
            sink = sink + #token_spec.tokens
        end
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
            tokenize_distinct = run_tokenize_distinct,
            tokenize_existing = run_tokenize_existing,
            parse_distinct = run_parse_distinct,
            build_plus_parse = run_build_plus_parse,
            parse_existing = run_parse_existing,
        })[mode],
    }
end

function M.run_from_env()
    local workload = M.load_from_env()
    assert(workload.run, "unknown ASDL2_PARSE_PROFILE_MODE: " .. tostring(workload.mode))
    print(
        "asdl2_parse_profile",
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
