local InspectCore = require("unit_inspect_core")

local M = {}

function M.install(U)
InspectCore.install(U)

function U.read_file(path)
    local f, err = io.open(path, "rb")
    if not f then error(err or ("cannot open file: " .. tostring(path)), 2) end
    local text = assert(f:read("*a"))
    f:close()
    return text
end

function U.normalize_asdl_text(text)
    if type(text) ~= "string" then
        error("U.normalize_asdl_text: text must be a string", 2)
    end

    return (("\n" .. text):gsub("(\n[ \t]*)%-%-", "%1#")):sub(2)
end

function U.read_asdl_file(path)
    return U.normalize_asdl_text(U.read_file(path))
end

function U.is_asdl_class(value)
    return type(value) == "table"
        and type(value.isclassof) == "function"
end

function U.stub(boundary_name)
    return function(...)
        error((boundary_name or "boundary") .. " not implemented", 2)
    end
end

-- Install stub methods onto ASDL classes.
--
-- plan forms:
--   { ["TaskView"] = "lower" }
--   { ["TaskApp.State"] = { "apply", "project_view" } }
--
-- Namespace keys install onto all top-level classes in that namespace.
-- Fully qualified type keys install onto one exact ASDL class.
function U.install_stubs(ctx, plan)
    if type(ctx) ~= "table" then
        error("U.install_stubs: ctx must be an ASDL context", 2)
    end
    if type(plan) ~= "table" then
        error("U.install_stubs: plan must be a table", 2)
    end

    local function normalize_verbs(value)
        if type(value) == "string" then
            return { value }
        end
        if type(value) == "table" and value[1] ~= nil then
            return value
        end
        error("U.install_stubs: plan values must be a verb string or verb list", 3)
    end

    local function classes_in_namespace(phase_name)
        local ns = ctx[phase_name]
        if type(ns) ~= "table" then
            error("U.install_stubs: unknown namespace '" .. tostring(phase_name) .. "'", 3)
        end

        local out = {}
        U.filter_map_into(out, U.each_name({ ns }), function(name)
            local class = ns[name]
            if U.is_asdl_class(class)
                and not class.__sum_parent
                and not class.kind then
                return {
                    fqname = phase_name .. "." .. name,
                    class = class,
                }
            end
        end)
        return out
    end

    local function resolve_target(target)
        if type(target) ~= "string" then
            error("U.install_stubs: plan keys must be namespace or fully qualified type strings", 3)
        end

        if target:find(".", 1, true) then
            local class = ctx.definitions and ctx.definitions[target]
            if not U.is_asdl_class(class) then
                error("U.install_stubs: unknown ASDL type '" .. tostring(target) .. "'", 3)
            end
            return {
                {
                    fqname = target,
                    class = class,
                }
            }
        end

        return classes_in_namespace(target)
    end

    local targets = U.each_name({ plan })

    U.each(targets, function(target)
        local verbs = normalize_verbs(plan[target])
        local classes = resolve_target(target)
        U.each(classes, function(info)
            U.each(verbs, function(verb)
                info.class[verb] = U.stub(info.fqname .. ":" .. verb)
            end)
        end)
    end)

    return ctx
end

function U.spec(config)
    if type(config) ~= "table" then
        error("U.spec: config must be a table", 2)
    end

    local asdl = require("asdl")
    local ctx = config.ctx or asdl.NewContext()

    local function define_asdl(source_name, text)
        local ok, err = pcall(function()
            ctx:Define(text)
        end)
        if ok then return end

        local msg = tostring(err)
        if msg:match("class name already defined") then
            error((
                "U.spec: ASDL source '%s' is not raw-terra-ASDL-compatible. "
                .. "This usually means two sum constructors in the same module "
                .. "share a name (for example Auto/Start/Center across multiple sums). "
                .. "Current terra/src/asdl.lua requires constructor class names to be unique within a module. "
                .. "You need an ASDL-module lowering pass that qualifies constructors before T:Define(...).\n\n"
                .. "Original error: %s"
            ):format(tostring(source_name), msg), 2)
        end

        error(err, 2)
    end

    if type(config.file) == "string" then
        define_asdl(config.file, U.read_asdl_file(config.file))
    end

    if type(config.text) == "string" then
        define_asdl("<inline text>", U.normalize_asdl_text(config.text))
    end

    if type(config.files) == "table" then
        for _, path in ipairs(config.files) do
            define_asdl(path, U.read_asdl_file(path))
        end
    end

    if type(config.texts) == "table" then
        for i, text in ipairs(config.texts) do
            define_asdl("<inline text #" .. tostring(i) .. ">", U.normalize_asdl_text(text))
        end
    end

    local function run_installer(inst)
        if type(inst) == "function" then
            return inst(ctx, U, config)
        end
        if type(inst) == "string" then
            local mod = require(inst)
            if type(mod) == "function" then
                return mod(ctx, U, config)
            end
            if type(mod) == "table" and type(mod.install) == "function" then
                return mod.install(ctx, U, config)
            end
            error("U.spec: installer module must return a function or { install = fn }", 3)
        end
        if type(inst) == "table" and type(inst.install) == "function" then
            return inst.install(ctx, U, config)
        end
        error("U.spec: installer must be a function, module name, or { install = fn }", 3)
    end

    if config.install ~= nil then
        if type(config.install) == "table" and config.install[1] ~= nil then
            for _, inst in ipairs(config.install) do
                run_installer(inst)
            end
        else
            run_installer(config.install)
        end
    end

    return {
        ctx = ctx,
        phases = config.phases,
        pipeline = config.pipeline,
    }
end

function U.load_inspect_spec(source)
    if type(source) ~= "string" or source == "" then
        error("U.load_inspect_spec: source must be a non-empty string", 2)
    end

    local function normalize(a, b)
        if type(a) == "function" and b == nil then
            return normalize(a(U))
        end

        if type(a) == "table" and type(a.inspect) == "function"
            and (a.ctx == nil or a.phases == nil) then
            local ctx, phases = a.inspect(U)
            return normalize(ctx, phases)
        end

        if type(a) == "table" and (a.files or a.file or a.texts or a.text or a.install)
            and a.ctx == nil then
            return U.spec(a)
        end

        if type(a) == "table" and a.ctx then
            return {
                ctx = a.ctx,
                phases = a.phases,
                pipeline = a.pipeline,
            }
        end

        if a ~= nil and type(b) == "table" then
            return {
                ctx = a,
                phases = b,
            }
        end

        error(
            "inspect spec must return { ctx = ..., phases = {...} }, "
            .. "a U.spec(...) config table, "
            .. "a function(U) -> one of those, or (ctx, phases)",
            3)
    end

    local function load_from_path(path)
        local terralib_mod = rawget(_G, "terralib")
        if terralib_mod and type(terralib_mod.loadfile) == "function" then
            local ok_t, chunk_t = pcall(terralib_mod.loadfile, path)
            if ok_t and type(chunk_t) == "function" then
                return normalize(chunk_t())
            end
        end

        local chunk_lua, err_lua = loadfile(path)
        if not chunk_lua then
            error(err_lua, 3)
        end
        return normalize(chunk_lua())
    end

    local looks_like_path = source:find("/", 1, true)
        or source:find("\\", 1, true)
        or source:match("%.t$")
        or source:match("%.lua$")

    if looks_like_path then
        return load_from_path(source)
    end

    return normalize(require(source))
end

function U.inspect_from(source)
    local spec = U.load_inspect_spec(source)
    return U.inspect(spec.ctx, spec.phases, spec.pipeline)
end

function U.cli_usage()
    return table.concat({
        "usage: terra unit.t <command> <spec> [args...]",
        "",
        "commands:",
        "  status <spec>",
        "  markdown <spec>",
        "  pipeline <spec>",
        "  boundaries <spec>",
        "  type-graph <spec> <root> [max_depth]",
        "  prompt <spec> <boundary> [max_depth]",
        "  scaffold <spec> <boundary>",
        "  scaffold-all <spec>",
        "  test-all <spec>",
        "",
        "spec forms:",
        "  - path/module returning { ctx = T, phases = {...}, pipeline = {...} }",
        "  - path/module returning U.spec{ texts/files = {...}, install = ..., pipeline = {...} }",
        "  - path/module returning function(U) -> one of those",
        "  - path/module returning (ctx, phases)",
    }, "\n")
end

function U.cli(argv)
    argv = argv or rawget(_G, "arg") or {}

    local command = argv[1]
    if not command or command == "help" or command == "--help" or command == "-h" then
        io.write(U.cli_usage(), "\n")
        return 0
    end

    local spec_source = argv[2]
    if not spec_source then
        error("unit CLI: missing <spec>.\n\n" .. U.cli_usage(), 2)
    end

    local I = U.inspect_from(spec_source)

    if command == "status" then
        io.write(I.status(), "\n")
        return 0
    end

    if command == "markdown" then
        io.write(I.markdown(), "\n")
        return 0
    end

    if command == "pipeline" then
        for _, edge in ipairs(I.pipeline()) do
            io.write(string.format(
                "%s -%s[%d]-> %s\n",
                edge.from, edge.verb, edge.count, edge.to))
        end
        return 0
    end

    if command == "boundaries" then
        for _, b in ipairs(I.boundaries) do
            io.write(b.receiver, ":", b.name, "()\n")
        end
        return 0
    end

    if command == "type-graph" then
        local root = argv[3]
        if not root then
            error("unit CLI: type-graph requires <root>", 2)
        end
        local max_depth = tonumber(argv[4]) or 3
        io.write(I.type_graph(root, max_depth), "\n")
        return 0
    end

    if command == "prompt" then
        local boundary = argv[3]
        if not boundary then
            error("unit CLI: prompt requires <boundary>", 2)
        end
        local max_depth = tonumber(argv[4]) or 3
        io.write(I.prompt_for(boundary, max_depth), "\n")
        return 0
    end

    if command == "scaffold" then
        local boundary = argv[3]
        if not boundary then
            error("unit CLI: scaffold requires <boundary>", 2)
        end
        local scaffold = I.scaffold(boundary)
        if not scaffold then
            error("unit CLI: boundary not found: " .. tostring(boundary), 2)
        end
        io.write(scaffold, "\n")
        return 0
    end

    if command == "scaffold-all" then
        for i, b in ipairs(I.boundaries) do
            local name = b.receiver .. ":" .. b.name
            local scaffold = I.scaffold(name)
            if scaffold then
                if i > 1 then io.write("\n", string.rep("-", 72), "\n\n") end
                io.write("-- ", name, "\n")
                io.write(scaffold, "\n")
            end
        end
        return 0
    end

    if command == "test-all" then
        local results = I.test_all()
        io.write(string.format(
            "passed %d/%d\n",
            results.passed,
            results.total))
        for _, r in ipairs(results.results) do
            local status = r.exists and (r.stub and "stub" or "real") or "missing"
            io.write("- ", r.boundary, " : ", status, "\n")
        end
        return 0
    end

    error("unit CLI: unknown command '" .. tostring(command) .. "'", 2)
end

end

return M
