#!/usr/bin/env luajit

local sketch = require("asdl2.asdl2_asdl_sketch")

local TOKENS = "=|?*,(){}."
local KEYWORDS = { module = true, unique = true }
for i = 1, #TOKENS do
    KEYWORDS[TOKENS:sub(i, i)] = true
end

local function serialize(v, indent)
    indent = indent or ""
    local next_indent = indent .. "    "
    local tv = type(v)
    if tv == "nil" then return "nil" end
    if tv == "boolean" or tv == "number" then return tostring(v) end
    if tv == "string" then return string.format("%q", v) end
    if tv ~= "table" then error("cannot serialize " .. tv) end

    local is_array = true
    local n = #v
    for k, _ in pairs(v) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            is_array = false
            break
        end
    end

    local parts = { "{" }
    if is_array then
        for i = 1, n do
            parts[#parts + 1] = "\n" .. next_indent .. serialize(v[i], next_indent) .. ","
        end
    else
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            parts[#parts + 1] = "\n" .. next_indent .. tostring(k) .. " = " .. serialize(v[k], next_indent) .. ","
        end
    end
    if #parts > 1 then parts[#parts + 1] = "\n" .. indent end
    parts[#parts + 1] = "}"
    return table.concat(parts)
end

local text = sketch
local pos = 1
local cur = nil
local value = nil

local function err(what)
    error(string.format(
        "generate_schema_boot: expected %s but found '%s' near:\n%s",
        what,
        tostring(value),
        text:sub(math.max(1, pos - 60), math.min(#text, pos + 60))
    ), 2)
end

local function skip(pattern)
    local matched = text:match(pattern, pos)
    pos = pos + #matched
    if pos <= #text then return false end
    cur, value = "EOF", "EOF"
    return true
end

local function next_token()
    if skip("^%s*") then return end

    local c = text:sub(pos, pos)
    if c == "#" then
        if skip("^[^\n]*\n") then return end
        return next_token()
    end

    if KEYWORDS[c] then
        cur, value, pos = c, c, pos + 1
        return
    end

    local ident = text:match("^[%a_][%a_%d]*", pos)
    if not ident then
        value = text:sub(pos, pos)
        err("valid token")
    end

    cur, value = KEYWORDS[ident] and ident or "Ident", ident
    pos = pos + #ident
end

local function nextif(kind)
    if cur ~= kind then return false end
    next_token()
    return true
end

local function expect(kind)
    if cur ~= kind then err(kind) end
    local v = value
    next_token()
    return v
end

local function parse_type_name()
    local parts = { expect("Ident") }
    while nextif(".") do
        parts[#parts + 1] = expect("Ident")
    end
    return table.concat(parts, ".")
end

local function parse_field()
    local type_name = parse_type_name()
    local optional = nextif("?") and true or false
    local list = nextif("*") and true or false
    local name = expect("Ident")
    return {
        name = name,
        type = type_name,
        optional = optional,
        list = list,
    }
end

local function parse_fields()
    expect("(")
    local fields = {}
    if cur ~= ")" then
        repeat
            fields[#fields + 1] = parse_field()
        until not nextif(",")
    end
    expect(")")
    return fields
end

local function parse_record_def(name)
    local fields = parse_fields()
    local unique = nextif("unique") and true or false
    return {
        fields = fields,
        name = name,
        unique = unique,
    }
end

local function parse_variant_record(name)
    local fields = (cur == "(") and parse_fields() or {}
    local unique = nextif("unique") and true or false
    return {
        fields = fields,
        name = name,
        unique = unique,
    }
end

local function parse_sum_def(name, phase_spec)
    local variants = {}
    local first = parse_variant_record(expect("Ident"))
    phase_spec.records[#phase_spec.records + 1] = first
    variants[#variants + 1] = first.name
    while nextif("|") do
        local variant = parse_variant_record(expect("Ident"))
        phase_spec.records[#phase_spec.records + 1] = variant
        variants[#variants + 1] = variant.name
    end
    phase_spec.sums[#phase_spec.sums + 1] = {
        name = name,
        variants = variants,
    }
end

local function sort_phase_spec(phase_spec)
    table.sort(phase_spec.records, function(a, b) return a.name < b.name end)
    table.sort(phase_spec.sums, function(a, b) return a.name < b.name end)
end

local spec = {
    pipeline = {},
    phases = {},
}

next_token()
while cur ~= "EOF" do
    expect("module")
    local module_name = expect("Ident")
    spec.pipeline[#spec.pipeline + 1] = module_name
    expect("{")
    local phase_spec = { records = {}, sums = {} }
    spec.phases[module_name] = phase_spec

    while cur ~= "}" do
        local name = expect("Ident")
        expect("=")
        if cur == "(" then
            phase_spec.records[#phase_spec.records + 1] = parse_record_def(name)
        else
            parse_sum_def(name, phase_spec)
        end
    end
    expect("}")
    sort_phase_spec(phase_spec)
end

local content = table.concat({
    "-- generated by asdl2/generate_schema_boot.lua\n",
    "local Boot = require(\"asdl2.asdl2_boot\")\n\n",
    "return Boot.build(", serialize(spec), ")\n",
})

local out = assert(io.open("asdl2/asdl2_schema_boot.lua", "wb"))
out:write(content)
out:close()
print("wrote asdl2/asdl2_schema_boot.lua")
