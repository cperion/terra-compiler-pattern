local M = {}

local NIL_KEY = {}
local LIST_MT = { __is_asdl_list = true }
local load_fn = loadstring or load
local setfenv_fn = setfenv

function M.List(xs)
    if xs == nil then return setmetatable({}, LIST_MT) end
    if getmetatable(xs) == LIST_MT then return xs end
    return setmetatable(xs, LIST_MT)
end

local Context = {}
function Context:__index(idx)
    local d = self.definitions[idx] or self.namespaces[idx]
    if d ~= nil then return d end
    return getmetatable(self)[idx]
end

function Context:_SetDefinition(name, value)
    local ctx = self.namespaces
    for part in name:gmatch("([^.]+)%.") do
        ctx[part] = ctx[part] or {}
        ctx = ctx[part]
    end
    local base = name:match("([^.]+)$")
    ctx[base] = value
    self.definitions[name] = value
end

function M.new_context()
    return setmetatable({
        definitions = {},
        namespaces = {},
    }, Context)
end

local function compile_ctor(source, chunkname, env)
    local chunk, err = load_fn(source, chunkname)
    if not chunk then error(err, 2) end
    if setfenv_fn then setfenv_fn(chunk, env) end
    return chunk()
end

local function ctor_source(class_name, fields, kind, unique)
    local argc = #fields
    local args = {}
    local assigns = {}
    for i = 1, argc do
        args[i] = "a" .. tostring(i)
        assigns[i] = string.format("obj[%q] = a%d", fields[i].name, i)
    end

    local kind_name = kind or class_name:match("([^.]+)$") or class_name
    local obj_init = string.format("local obj = { kind = %q }", kind_name)

    if argc == 0 then
        return table.concat({
            "return function(class, NIL_KEY, setmetatable)",
            "  local singleton = nil",
            "  return function(_) ",
            "    if singleton ~= nil then return singleton end",
            "    " .. obj_init,
            "    singleton = setmetatable(obj, class)",
            "    return singleton",
            "  end",
            "end",
        }, "\n")
    end

    local body = {}
    if unique then
        body[#body + 1] = "  local cache = {}"
    end
    body[#body + 1] = "  return function(_, " .. table.concat(args, ", ") .. ")"

    if unique then
        body[#body + 1] = "    local node = cache"
        for i = 1, argc - 1 do
            body[#body + 1] = string.format("    local k%d = a%d", i, i)
            body[#body + 1] = string.format("    if k%d == nil then k%d = NIL_KEY end", i, i)
            body[#body + 1] = string.format("    local n%d = node[k%d]", i, i)
            body[#body + 1] = string.format("    if n%d == nil then n%d = {}; node[k%d] = n%d end", i, i, i, i)
            body[#body + 1] = string.format("    node = n%d", i)
        end
        body[#body + 1] = string.format("    local k%d = a%d", argc, argc)
        body[#body + 1] = string.format("    if k%d == nil then k%d = NIL_KEY end", argc, argc)
        body[#body + 1] = string.format("    local existing = node[k%d]", argc)
        body[#body + 1] = "    if existing ~= nil then return existing end"
    end

    body[#body + 1] = "    " .. obj_init
    for i = 1, argc do
        body[#body + 1] = "    " .. assigns[i]
    end
    body[#body + 1] = "    obj = setmetatable(obj, class)"
    if unique then
        body[#body + 1] = string.format("    node[k%d] = obj", argc)
    end
    body[#body + 1] = "    return obj"
    body[#body + 1] = "  end"

    return table.concat({
        "return function(class, NIL_KEY, setmetatable)",
        table.concat(body, "\n"),
        "end",
    }, "\n")
end

local function install_class_runtime(class, construct)
    class.__index = class
    class.members[class] = true
    setmetatable(class, {
        __call = construct,
        __newindex = function(self, k, v)
            for member, _ in pairs(self.members) do
                rawset(member, k, v)
            end
        end,
        __tostring = function()
            return string.format("Class(%s)", class.__name or "?")
        end,
    })
end

local function install_record_class(class, unique)
    local source = ctor_source(class.__name, class.__fields, class.__kind, unique)
    local construct = compile_ctor(
        source,
        "asdl2_boot_ctor_" .. tostring(class.__name:gsub("[^%w_]", "_")),
        {}
    )(class, NIL_KEY, setmetatable)

    install_class_runtime(class, construct)
    function class:isclassof(obj)
        return type(obj) == "table" and getmetatable(obj) == class
    end
end

local function install_sum_class(class)
    install_class_runtime(class, function()
        error("cannot construct sum parent '" .. tostring(class.__name) .. "' directly", 2)
    end)
    function class:isclassof(obj)
        if type(obj) ~= "table" then return false end
        local mt = getmetatable(obj)
        return mt ~= nil and class.members[mt] == true and mt ~= class
    end
end

function M.build(spec)
    local ctx = M.new_context()
    local classes = {}

    for _, phase in ipairs(spec.pipeline) do
        ctx.namespaces[phase] = ctx.namespaces[phase] or {}
        local phase_spec = assert(spec.phases[phase], "missing phase spec: " .. tostring(phase))

        for _, record in ipairs(phase_spec.records or {}) do
            local class = {
                __name = phase .. "." .. record.name,
                __fields = record.fields,
                __kind = record.kind,
                members = {},
            }
            install_record_class(class, record.unique)
            classes[class.__name] = class
            ctx:_SetDefinition(class.__name, class)
        end

        for _, sum in ipairs(phase_spec.sums or {}) do
            local class = {
                __name = phase .. "." .. sum.name,
                __variants = sum.variants,
                members = {},
            }
            install_sum_class(class)
            classes[class.__name] = class
            ctx:_SetDefinition(class.__name, class)
        end
    end

    for _, phase in ipairs(spec.pipeline) do
        local phase_spec = spec.phases[phase]
        for _, sum in ipairs(phase_spec.sums or {}) do
            local parent = classes[phase .. "." .. sum.name]
            for _, variant_name in ipairs(sum.variants) do
                local child = classes[phase .. "." .. variant_name]
                if child == nil then
                    error("missing variant class " .. phase .. "." .. variant_name, 2)
                end
                child.__sum_parent = parent
                parent.members[child] = true
            end
        end
    end

    return {
        ctx = ctx,
        pipeline = spec.pipeline,
    }
end

return M
