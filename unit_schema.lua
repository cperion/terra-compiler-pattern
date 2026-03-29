local InspectCore = require("unit_inspect_core")

local M = {}

function M.install(U)
function U.inspect(ctx, phases, pipeline_phases)
    local H = InspectCore.new(U)

    phases = phases or H.discover_phases(ctx)
    if #phases == 0 then phases = H.discover_phases(ctx) end
    pipeline_phases = pipeline_phases or phases

    local I = {
        ctx = ctx,
        phases = phases,
        pipeline_phases = pipeline_phases,
        types = {},
        type_map = {},
        boundaries = {},
    }

    local class_map = {}

    -- Inventory types by phase.
    U.each(phases, function(phase_name)
        local ns = ctx[phase_name]
        if type(ns) == "table" then
            U.each(H.sorted_class_names(ns), function(name)
                local class = ns[name]
                local fqname = phase_name .. "." .. name
                local t = {
                    phase = phase_name,
                    name = name,
                    fqname = fqname,
                    class = class,
                    kind = "record",
                    fields = class.__fields or {},
                    variants = {},
                    variant_types = {},
                    methods = {},
                }
                I.types[#I.types + 1] = t
                I.type_map[fqname] = t
                class_map[class] = t
                class.__name = class.__name or fqname
            end)
        end
    end)

    -- Derive enum metadata from ASDL parent.members.
    U.each(I.types, function(t)
        local variant_entries = {}
        if type(t.class.members) == "table" then
            U.each(t.class.members, function(member)
                if member ~= t.class then
                    local variant_t = class_map[member]
                    variant_entries[#variant_entries + 1] = {
                        class = member,
                        type = variant_t,
                        name = (variant_t and variant_t.name)
                            or member.kind
                            or H.basename(member.__name)
                            or tostring(member),
                    }
                end
            end)
        end

        table.sort(variant_entries, function(a, b)
            return a.name < b.name
        end)

        if #variant_entries > 0 and not t.class.__fields then
            t.kind = "enum"
            U.each(variant_entries, function(entry)
                local i = #t.variants + 1
                t.variants[i] = entry.name
                t.variant_types[i] = entry.type
                entry.class.__sum_parent = t.class
            end)
            t.class.__variants = t.variants
        end
    end)

    -- Discover installed methods.
    -- Sum-type parent methods are copied onto child variant classes by ASDL.
    -- Skip those inherited duplicates so Device:lower() appears once on the
    -- sum parent, not once per variant, unless a variant overrides it.
    U.each(I.types, function(t)
        local method_names = {}
        local parent = t.class.__sum_parent
        U.each(U.each_name({ t.class }), function(name)
            local fn = t.class[name]
            if H.is_public_method(name, fn)
                and not (parent and parent[name] == fn) then
                method_names[#method_names + 1] = name
            end
        end)
        t.methods = method_names

        U.each(method_names, function(name)
            I.boundaries[#I.boundaries + 1] = {
                receiver = t.fqname,
                receiver_name = t.name,
                name = name,
                fn = t.class[name],
                phase = t.phase,
                type = t,
            }
        end)
    end)

    H.sort_boundaries(I.boundaries)

    local function find_boundary(boundary_name)
        return H.find_boundary(I.boundaries, boundary_name)
    end

    local function is_stub(boundary)
        return H.is_stub(boundary)
    end

    local function resolve_type_name(type_name, phase_name)
        return H.resolve_type_name(I.type_map, type_name, phase_name)
    end

    local function direct_refs(t)
        return H.direct_refs(I.type_map, function(type_name, phase_name)
            return resolve_type_name(type_name, phase_name)
        end, t)
    end

    function I.find_boundary(boundary_name)
        return H.find_boundary(I.boundaries, boundary_name)
    end

    function I.resolve_type_name(type_name, phase_name)
        return resolve_type_name(type_name, phase_name)
    end

    function I.is_stub(boundary)
        return H.is_stub(boundary)
    end

    function I.progress()
        local info = {
            boundary_total = #I.boundaries,
            boundary_real = 0,
            boundary_stub = 0,
            boundary_coverage = 0,
            type_total = #I.types,
            record_total = 0,
            enum_total = 0,
            variant_total = 0,
            by_phase = {},
        }

        U.each(phases, function(phase_name)
            info.by_phase[phase_name] = H.new_phase_bucket()
        end)

        U.each(I.types, function(t)
            local phase = H.ensure_phase_bucket(info.by_phase, t.phase)

            phase.type_total = phase.type_total + 1
            if t.kind == "enum" then
                phase.enum_total = phase.enum_total + 1
                phase.variant_total = phase.variant_total + #t.variants
                info.enum_total = info.enum_total + 1
                info.variant_total = info.variant_total + #t.variants
            else
                phase.record_total = phase.record_total + 1
                info.record_total = info.record_total + 1
            end
        end)

        U.each(I.boundaries, function(b)
            local phase = H.ensure_phase_bucket(info.by_phase, b.phase)

            phase.boundary_total = phase.boundary_total + 1
            if is_stub(b) then
                phase.boundary_stub = phase.boundary_stub + 1
                info.boundary_stub = info.boundary_stub + 1
            else
                phase.boundary_real = phase.boundary_real + 1
                info.boundary_real = info.boundary_real + 1
            end
        end)

        U.each(phases, function(phase_name)
            local phase = info.by_phase[phase_name]
            if phase and phase.boundary_total > 0 then
                phase.boundary_coverage = phase.boundary_real / phase.boundary_total
            end
        end)

        if info.boundary_total > 0 then
            info.boundary_coverage = info.boundary_real / info.boundary_total
        end

        return info
    end

    function I.pipeline()
        local counts_by_phase = {}

        for _, b in ipairs(I.boundaries) do
            local counts = counts_by_phase[b.phase]
            if not counts then
                counts = {}
                counts_by_phase[b.phase] = counts
            end
            counts[b.name] = (counts[b.name] or 0) + 1
        end

        local edges = {}
        for i = 1, #pipeline_phases - 1 do
            local from = pipeline_phases[i]
            local to = pipeline_phases[i + 1]
            local counts = counts_by_phase[from] or {}
            local names = U.each_name({ counts })

            local verb = "?"
            local best = -1
            U.each(names, function(name)
                local count = counts[name]
                if count > best then
                    best = count
                    verb = name
                end
            end)

            edges[#edges + 1] = {
                from = from,
                to = to,
                verb = verb,
                count = best > 0 and best or 0,
            }
        end

        return edges
    end

    function I.type_graph(root_type, max_depth)
        return H.render_type_graph(
            I.type_map,
            function(type_name, phase_name)
                return resolve_type_name(type_name, phase_name)
            end,
            root_type,
            max_depth)
    end

    function I.prompt_for(boundary_name, max_depth)
        local b = H.find_boundary(I.boundaries, boundary_name)
        if not b then
            return "boundary not found: " .. tostring(boundary_name)
        end

        local child_items = H.collect_prompt_child_items(
            I.boundaries,
            function(t) return direct_refs(t) end,
            b)

        local sections = {}
        H.append_prompt_sections(
            sections,
            b,
            I.type_graph(b.receiver, max_depth or 3),
            child_items)

        return table.concat(sections, "\n\n")
    end

    function I.markdown()
        local lines = { "# Schema Documentation", "" }

        U.each(phases, function(phase_name)
            H.append_phase_markdown(lines, phase_name, I.types, I.boundaries)
        end)

        return table.concat(lines, "\n")
    end

    function I.test_all()
        local results = {}
        local passed = 0

        U.each(I.boundaries, function(b)
            local result = {
                boundary = b.receiver .. ":" .. b.name,
                exists = type(b.fn) == "function",
                stub = H.is_stub(b),
            }
            results[#results + 1] = result
            if result.exists and not result.stub then
                passed = passed + 1
            end
        end)

        return {
            results = results,
            passed = passed,
            total = #results,
        }
    end

    function I.scaffold(boundary_name)
        local b = H.find_boundary(I.boundaries, boundary_name)
        if not b then return nil end

        local t = b.type
        local lines = {
            "local U = require 'unit'",
            "",
            "-- " .. b.receiver .. ":" .. b.name .. "()",
            "-- Phase: " .. b.phase,
            "",
            "function " .. t.name .. ":" .. b.name .. "()",
        }

        if t.kind == "enum" then
            H.append_enum_scaffold(lines, t.variants)
            return table.concat(lines, "\n")
        end

        local child_calls = H.collect_record_scaffold_calls(
            I.type_map,
            function(type_name, phase_name)
                return resolve_type_name(type_name, phase_name)
            end,
            t,
            b.name)

        H.append_record_scaffold(lines, b.name, child_calls)
        return table.concat(lines, "\n")
    end

    function I.status()
        return H.render_status(I.progress(), phases)
    end

    return I
end

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
        U.each(U.each_name({ ns }), function(name)
            local class = ns[name]
            if U.is_asdl_class(class)
                and not class.__sum_parent
                and not class.kind then
                out[#out + 1] = {
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
