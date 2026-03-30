local InspectCore = require("unit_inspect_core")

local M = {}

local function path_sep()
    return package.config:sub(1, 1)
end

local SEP = path_sep()

local function join_path(...)
    local parts = { ... }
    local out = {}
    for i = 1, #parts do
        local part = parts[i]
        if part and part ~= "" then
            if #out == 0 then
                out[1] = tostring(part)
            else
                local prev = out[#out]
                local next_part = tostring(part)
                prev = prev:gsub("[\\/]+$", "")
                next_part = next_part:gsub("^[\\/]+", "")
                out[#out] = prev
                out[#out + 1] = next_part
            end
        end
    end
    return table.concat(out, SEP)
end

local function dirname(path)
    local dir = tostring(path):match("^(.*)[/\\][^/\\]+$")
    return dir or "."
end

local function basename(path)
    return tostring(path):match("([^/\\]+)$") or tostring(path)
end

local function split_fqname(fqname)
    local parts = {}
    for part in tostring(fqname):gmatch("[^.]+") do
        parts[#parts + 1] = part
    end
    return parts
end

local function snake_part(part)
    local s = tostring(part)
    s = s:gsub("(%u)(%u%l)", "%1_%2")
    s = s:gsub("(%l%d)(%u)", "%1_%2")
    s = s:gsub("(%l)(%u)", "%1_%2")
    s = s:gsub("[^%w]+", "_")
    s = s:lower()
    return s
end

local function path_parts_for_fqname(fqname)
    local parts = split_fqname(fqname)
    local out = {}
    for i = 1, #parts do
        out[i] = snake_part(parts[i])
    end
    return out
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command_output(command)
    local f = io.popen(command)
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function shell_true(command)
    local text = command_output(command)
    return text and text:match("^1") ~= nil or false
end

local function is_dir(path)
    return shell_true("[ -d " .. shell_quote(path) .. " ] && printf 1 || printf 0")
end

local function is_file(path)
    return shell_true("[ -f " .. shell_quote(path) .. " ] && printf 1 || printf 0")
end

local function list_find(root, extra)
    if not is_dir(root) then return {} end
    local cmd = "find " .. shell_quote(root) .. " " .. extra .. " | LC_ALL=C sort"
    local text = command_output(cmd) or ""
    local out = {}
    for line in text:gmatch("[^\n]+") do
        if line ~= "" then out[#out + 1] = line end
    end
    return out
end

local function mkdir_p(path)
    local ok = os.execute("mkdir -p " .. shell_quote(path))
    if ok == true or ok == 0 then return true end
    return false
end

local function write_text(path, content)
    assert(mkdir_p(dirname(path)))
    local f, err = io.open(path, "wb")
    if not f then error(err or ("cannot open file for write: " .. tostring(path)), 2) end
    f:write(content)
    f:close()
end

local function load_chunk_from_path(path)
    local terralib_mod = rawget(_G, "terralib")
    if terralib_mod and type(terralib_mod.loadfile) == "function" then
        local ok_t, chunk_t = pcall(terralib_mod.loadfile, path)
        if ok_t and type(chunk_t) == "function" then
            return chunk_t
        end
    end

    local chunk_lua, err_lua = loadfile(path)
    if not chunk_lua then
        error(err_lua, 3)
    end
    return chunk_lua
end

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

    local function define_asdl2_context(text)
        local asdl2_schema = require("asdl2.asdl2_schema")
        local asdl2_T = asdl2_schema.ctx
        return asdl2_T.Asdl2Text.Spec(text):parse():catalog():classify_lower():define_machine():install()
    end

    local function run_installer(ctx, config, inst)
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
            error("installer module must return a function or { install = fn }", 3)
        end
        if type(inst) == "table" and type(inst.install) == "function" then
            return inst.install(ctx, U, config)
        end
        error("installer must be a function, module name, or { install = fn }", 3)
    end

    function U.normalize_project(project)
        if type(project) ~= "table" then
            error("U.normalize_project: project must be a table", 2)
        end

        local root = project.root or "."
        local layout = project.layout or "flat"
        if layout ~= "tree" and layout ~= "flat" then
            error("U.normalize_project: layout must be 'tree' or 'flat'", 2)
        end

        return {
            kind = "UnitProject",
            root = root,
            source_kind = project.source_kind or "project_dir",
            layout = layout,
            schema_root = project.schema_root or "schema",
            boundary_root = project.boundary_root or "boundaries",
            schema_paths = project.schema_paths or {},
            pipeline = project.pipeline,
            phases = project.phases,
            stubs = project.stubs,
            install = project.install,
            deps = project.deps or {},
        }
    end

    function U.project_type_artifact_path(project, fqname, kind)
        project = U.normalize_project(project)
        kind = kind or "impl"
        local suffix = kind == "impl" and ""
            or (kind == "test" and "_test")
            or (kind == "bench" and "_bench")
            or (kind == "profile" and "_profile")
        if suffix == nil then
            error("U.project_type_artifact_path: unknown artifact kind '" .. tostring(kind) .. "'", 2)
        end

        local parts = path_parts_for_fqname(fqname)
        if #parts == 0 then
            error("U.project_type_artifact_path: invalid fqname", 2)
        end

        local boundary_root = join_path(project.root, project.boundary_root)
        if project.layout == "tree" then
            local path = boundary_root
            for i = 1, #parts - 1 do
                path = join_path(path, parts[i])
            end
            return join_path(path, parts[#parts] .. suffix .. ".lua")
        end

        return join_path(boundary_root, table.concat(parts, "_") .. suffix .. ".lua")
    end

    function U.project_type_path(project, fqname)
        return U.project_type_artifact_path(project, fqname, "impl")
    end

    function U.project_type_test_path(project, fqname)
        return U.project_type_artifact_path(project, fqname, "test")
    end

    function U.project_type_bench_path(project, fqname)
        return U.project_type_artifact_path(project, fqname, "bench")
    end

    function U.project_type_profile_path(project, fqname)
        return U.project_type_artifact_path(project, fqname, "profile")
    end

    local function normalize_backend_name(backend)
        if backend ~= "luajit" and backend ~= "terra" then
            error("unknown backend '" .. tostring(backend) .. "'", 3)
        end
        return backend
    end

    local function backend_ext(backend)
        backend = normalize_backend_name(backend)
        return backend == "terra" and ".t" or ".lua"
    end

    function U.project_type_backend_artifact_path(project, fqname, backend, kind)
        project = U.normalize_project(project)
        backend = normalize_backend_name(backend)
        kind = kind or "impl"
        local suffix = kind == "impl" and ("_" .. backend)
            or (kind == "test" and ("_" .. backend .. "_test"))
            or (kind == "bench" and ("_" .. backend .. "_bench"))
            or (kind == "profile" and ("_" .. backend .. "_profile"))
        if suffix == nil then
            error("U.project_type_backend_artifact_path: unknown artifact kind '" .. tostring(kind) .. "'", 2)
        end

        local parts = path_parts_for_fqname(fqname)
        if #parts == 0 then
            error("U.project_type_backend_artifact_path: invalid fqname", 2)
        end

        local boundary_root = join_path(project.root, project.boundary_root)
        if project.layout == "tree" then
            local path = boundary_root
            for i = 1, #parts - 1 do
                path = join_path(path, parts[i])
            end
            return join_path(path, parts[#parts] .. suffix .. backend_ext(backend))
        end

        return join_path(boundary_root, table.concat(parts, "_") .. suffix .. backend_ext(backend))
    end

    function U.project_type_backend_path(project, fqname, backend)
        return U.project_type_backend_artifact_path(project, fqname, backend, "impl")
    end

    function U.project_type_backend_test_path(project, fqname, backend)
        return U.project_type_backend_artifact_path(project, fqname, backend, "test")
    end

    function U.project_type_backend_bench_path(project, fqname, backend)
        return U.project_type_backend_artifact_path(project, fqname, backend, "bench")
    end

    function U.project_type_backend_profile_path(project, fqname, backend)
        return U.project_type_backend_artifact_path(project, fqname, backend, "profile")
    end

    local function selected_backend_name()
        local forced = os.getenv("UNIT_BACKEND")
        if forced == "terra" or forced == "luajit" then
            return forced
        end
        return rawget(_G, "terralib") and "terra" or "luajit"
    end

    local function load_project_file(path)
        return load_chunk_from_path(path)()
    end

    local function discover_project_dir(root)
        local meta_path = join_path(root, "unit_project.lua")
        local meta = is_file(meta_path) and load_project_file(meta_path) or {}
        if type(meta) ~= "table" then
            error("unit_project.lua must return a table", 3)
        end

        local schema_root = meta.schema_root or "schema"
        local boundary_root = meta.boundary_root or "boundaries"
        local schema_dir = join_path(root, schema_root)
        local schema_paths = {}

        U.map_into(schema_paths, list_find(schema_dir,
            "-maxdepth 1 -type f \\( -name '*.asdl' -o -name '*.lua' -o -name '*.t' \\)"), function(path)
            return path
        end)

        local pipeline = meta.pipeline
        local pipeline_path = join_path(root, "pipeline.lua")
        if pipeline == nil and is_file(pipeline_path) then
            pipeline = load_project_file(pipeline_path)
        end

        return U.normalize_project {
            root = root,
            source_kind = "project_dir",
            layout = meta.layout or "flat",
            schema_root = schema_root,
            boundary_root = boundary_root,
            schema_paths = schema_paths,
            pipeline = pipeline,
            phases = meta.phases,
            stubs = meta.stubs,
            install = meta.install,
            deps = meta.deps,
        }
    end

    function U.load_project(source)
        if type(source) ~= "string" or source == "" then
            error("U.load_project: source must be a non-empty string", 2)
        end

        if is_dir(source) then
            return discover_project_dir(source)
        end

        if source:match("%.asdl$") then
            return U.normalize_project {
                root = dirname(source),
                source_kind = "schema_file",
                layout = "flat",
                schema_paths = { source },
            }
        end

        local looks_like_path = source:find("/", 1, true)
            or source:find("\\", 1, true)
            or source:match("%.t$")
            or source:match("%.lua$")

        if looks_like_path and is_file(source) then
            error("U.load_project: file sources must be .asdl files or project directories; legacy .lua/.t spec sources were removed", 2)
        end

        error("U.load_project: source must be a project directory or direct .asdl schema file", 2)
    end

    local function load_schema_source(path)
        if path:match("%.asdl$") then
            return U.read_asdl_file(path)
        end
        local value = load_project_file(path)
        if type(value) == "function" then value = value(U) end
        if type(value) ~= "string" then
            error("schema source '" .. tostring(path) .. "' must return ASDL text", 3)
        end
        return U.normalize_asdl_text(value)
    end

    local function resolve_project_source(base_root, source)
        if type(source) ~= "string" or source == "" then
            error("project dependency source must be a non-empty string", 3)
        end

        local joined = join_path(base_root, source)
        if is_dir(joined) or is_file(joined) then
            return joined
        end
        return source
    end

    local function dependency_source(project, dep)
        if type(dep) == "string" then
            return resolve_project_source(project.root, dep)
        end
        if type(dep) == "table" and type(dep.source) == "string" then
            return resolve_project_source(project.root, dep.source)
        end
        if type(dep) == "table" and type(dep.project) == "string" then
            return resolve_project_source(project.root, dep.project)
        end
        error("project dependency must be a string or { source = <path> }", 3)
    end

    local function project_key(project)
        return tostring(project.root) .. "|" .. tostring(project.source_kind)
    end

    local function collect_project_closure(project)
        local ordered = {}
        local seen = {}
        local active = {}

        local function visit(current)
            current = U.normalize_project(current)
            local key = project_key(current)
            if active[key] then
                error("cyclic project dependency detected at '" .. tostring(current.root) .. "'", 3)
            end
            if seen[key] then return end

            active[key] = true
            U.each(current.deps or {}, function(dep)
                visit(U.load_project(dependency_source(current, dep)))
            end)
            active[key] = nil
            seen[key] = current
            ordered[#ordered + 1] = current
        end

        visit(project)
        return ordered
    end

    local function list_boundary_impl_paths(project)
        local root = join_path(project.root, project.boundary_root)
        return list_find(root,
            "-type f -name '*.lua' ! -name '*_test.lua' ! -name '*_bench.lua' ! -name '*_profile.lua' ! -name '*_luajit.lua' ! -name '*_terra.lua'")
    end

    local function list_backend_impl_paths(project, backend)
        project = U.normalize_project(project)
        backend = normalize_backend_name(backend)
        local root = join_path(project.root, project.boundary_root)
        local ext = backend_ext(backend)
        return list_find(root,
            "-type f -name '*_" .. backend .. tostring(ext) .. "' ! -name '*_test" .. tostring(ext) .. "' ! -name '*_bench" .. tostring(ext) .. "' ! -name '*_profile" .. tostring(ext) .. "'")
    end

    local function install_project_boundaries_shallow(project, ctx)
        project = U.normalize_project(project)

        local function install_path(path)
            local mod = load_project_file(path)
            if type(mod) == "function" then
                mod(ctx, U, project)
            elseif type(mod) == "table" and type(mod.install) == "function" then
                mod.install(ctx, U, project)
            else
                error("boundary module '" .. tostring(path) .. "' must return function(T,U,P) or { install = fn }", 2)
            end
        end

        U.each(list_boundary_impl_paths(project), install_path)
        U.each(list_backend_impl_paths(project, selected_backend_name()), install_path)
        return ctx
    end

    function U.install_project_boundaries(project, ctx)
        local projects = collect_project_closure(U.normalize_project(project))
        U.each(projects, function(p)
            install_project_boundaries_shallow(p, ctx)
        end)
        return ctx
    end

    function U.project_inspect_spec(project)
        project = U.normalize_project(project)
        local projects = collect_project_closure(project)

        local combined_schema_texts = {}
        U.each(projects, function(p)
            U.each(p.schema_paths, function(path)
                combined_schema_texts[#combined_schema_texts + 1] = load_schema_source(path)
            end)
        end)
        local combined_text = table.concat(combined_schema_texts, "\n\n")
        local ctx = define_asdl2_context(combined_text)

        U.each(projects, function(p)
            if p.stubs then
                U.install_stubs(ctx, p.stubs)
            end

            if p.install ~= nil then
                if type(p.install) == "table" and p.install[1] ~= nil then
                    U.each(p.install, function(inst)
                        run_installer(ctx, p, inst)
                    end)
                else
                    run_installer(ctx, p, p.install)
                end
            end

            install_project_boundaries_shallow(p, ctx)
        end)

        return {
            project = project,
            projects = projects,
            ctx = ctx,
            phases = project.phases,
            pipeline = project.pipeline,
        }
    end

    function U.load_inspect_spec(source)
        return U.project_inspect_spec(U.load_project(source))
    end

    local function find_project_artifact(projects, receiver, kind)
        for i = #projects, 1, -1 do
            local project = projects[i]
            local path = U.project_type_artifact_path(project, receiver, kind)
            if is_file(path) then
                return path, project
            end
        end
        return nil, nil
    end

    local function find_project_backend_artifact(projects, receiver, backend, kind)
        for i = #projects, 1, -1 do
            local project = projects[i]
            local path = U.project_type_backend_artifact_path(project, receiver, backend, kind)
            if is_file(path) then
                return path, project
            end
        end
        return nil, nil
    end

    local function collect_backend_inventory(projects, I)
        local receivers = {}
        local seen = {}
        U.each(I.boundaries, function(b)
            if not seen[b.receiver] then
                seen[b.receiver] = true
                receivers[#receivers + 1] = b.receiver
            end
        end)
        table.sort(receivers)

        local backends = { "luajit", "terra" }
        local kinds = { "impl", "test", "bench", "profile" }
        local items = {}
        local totals = {
            receiver_total = #receivers,
            by_backend = {},
        }

        U.each(backends, function(backend)
            totals.by_backend[backend] = { impl = 0, test = 0, bench = 0, profile = 0 }
        end)

        U.each(receivers, function(receiver)
            local item = {
                receiver = receiver,
                semantic = {},
                backends = {},
            }

            U.each(kinds, function(kind)
                local path, owner = find_project_artifact(projects, receiver, kind)
                if path then
                    item.semantic[kind] = { path = path, project = owner }
                end
            end)

            U.each(backends, function(backend)
                local entry = {}
                U.each(kinds, function(kind)
                    local path, owner = find_project_backend_artifact(projects, receiver, backend, kind)
                    if path then
                        entry[kind] = { path = path, project = owner }
                        totals.by_backend[backend][kind] = totals.by_backend[backend][kind] + 1
                    end
                end)
                item.backends[backend] = entry
            end)
            items[#items + 1] = item
        end)

        return {
            receivers = receivers,
            items = items,
            totals = totals,
        }
    end

    local function render_backend_status(inventory)
        local lines = {
            "Backend artifacts:",
        }
        local order = { "luajit", "terra" }
        U.each(order, function(backend)
            local counts = inventory.totals.by_backend[backend] or { impl = 0, test = 0, bench = 0, profile = 0 }
            lines[#lines + 1] = string.format(
                "  %-7s receivers=%d impl=%d test=%d bench=%d profile=%d",
                backend .. ":",
                inventory.totals.receiver_total,
                counts.impl,
                counts.test,
                counts.bench,
                counts.profile)
        end)
        return table.concat(lines, "\n")
    end

    function U.inspect_from(source)
        local spec = U.load_inspect_spec(source)
        local I = U.inspect(spec.ctx, spec.phases, spec.pipeline)
        I.project = spec.project
        I.projects = spec.projects or { spec.project }
        I.backend_inventory = collect_backend_inventory(I.projects, I)
        I.backends = function()
            return I.backend_inventory
        end
        I.backend_status = function()
            return render_backend_status(I.backend_inventory)
        end
        return I
    end

    local function receiver_for_selector(I, selector)
        if type(selector) ~= "string" or selector == "" then return nil end
        local receiver = selector:match("^(.-):") or selector
        if I.type_map[receiver] then return receiver end
        return I.resolve_type_name(receiver)
    end

    local function boundaries_for_receiver(I, receiver)
        local out = {}
        U.filter_map_into(out, I.boundaries, function(b)
            if b.receiver == receiver then return b end
        end)
        return out
    end

    local function artifact_header(kind)
        if kind == "impl" then return nil end
        if kind == "test" then return "tests" end
        if kind == "bench" then return "benches" end
        if kind == "profile" then return "profiles" end
        error("unknown artifact kind '" .. tostring(kind) .. "'", 3)
    end

    local function scaffold_impl_artifact(I, project, receiver)
        local H = InspectCore.new(U)
        local t = I.type_map[receiver]
        if not t then return nil end
        local bs = boundaries_for_receiver(I, receiver)
        if #bs == 0 then return nil end

        local lines = {
            "local U = require(\"unit\")",
            "",
            "return function(T, U, P)",
            "",
        }

        U.each(bs, function(b)
            local method_lines = {
                "function T." .. receiver .. ":" .. b.name .. "()",
            }
            if t.kind == "enum" then
                H.append_enum_scaffold(method_lines, t.variants)
            else
                local child_calls = H.collect_record_scaffold_calls(
                    I.type_map,
                    function(type_name, phase_name)
                        return I.resolve_type_name(type_name, phase_name)
                    end,
                    t,
                    b.name)
                H.append_record_scaffold(method_lines, b.name, child_calls)
            end
            U.map_into(lines, method_lines, function(line) return line end)
            lines[#lines + 1] = ""
        end)

        lines[#lines + 1] = "end"
        return table.concat(lines, "\n")
    end

    local function scaffold_sidecar_artifact(I, project, receiver, kind)
        local t = I.type_map[receiver]
        if not t then return nil end
        local bs = boundaries_for_receiver(I, receiver)
        if #bs == 0 then return nil end

        local group = artifact_header(kind)
        local lines = {
            "local U = require(\"unit\")",
            "",
            "return function(T, U, P)",
            "    local " .. group .. " = {}",
            "",
        }

        U.each(bs, function(b)
            local fn_name = kind .. "_" .. b.name
            lines[#lines + 1] = "    function " .. group .. "." .. fn_name .. "()"
            lines[#lines + 1] = "        -- TODO: build representative input for " .. receiver .. ":" .. b.name
            if kind == "test" then
                lines[#lines + 1] = "        -- local input = T." .. receiver .. "(...)"
                lines[#lines + 1] = "        -- local out = input:" .. b.name .. "()"
                lines[#lines + 1] = "        -- assert(out ~= nil)"
            elseif kind == "bench" then
                lines[#lines + 1] = "        -- local iters = 1000"
                lines[#lines + 1] = "        -- TODO: time repeated calls to input:" .. b.name .. "()"
            else
                lines[#lines + 1] = "        -- TODO: build larger workload for profiling input:" .. b.name .. "()"
            end
            lines[#lines + 1] = "    end"
            lines[#lines + 1] = ""
        end)

        lines[#lines + 1] = "    return " .. group
        lines[#lines + 1] = "end"
        return table.concat(lines, "\n")
    end

    function U.scaffold_type_artifact(project, I, selector, kind)
        kind = kind or "impl"
        local receiver = receiver_for_selector(I, selector)
        if not receiver then return nil, nil end
        if kind == "impl" then
            return scaffold_impl_artifact(I, project, receiver), receiver
        end
        return scaffold_sidecar_artifact(I, project, receiver, kind), receiver
    end

    function U.scaffold_project(project, I, opts)
        project = U.normalize_project(project)
        opts = opts or {}

        local kinds = { "impl" }
        if opts.all_artifacts or opts.with_test then kinds[#kinds + 1] = "test" end
        if opts.all_artifacts or opts.with_bench then kinds[#kinds + 1] = "bench" end
        if opts.all_artifacts or opts.with_profile then kinds[#kinds + 1] = "profile" end

        local written = {}
        local receivers = {}
        local seen = {}
        U.each(I.boundaries, function(b)
            if not seen[b.receiver] then
                seen[b.receiver] = true
                receivers[#receivers + 1] = b.receiver
            end
        end)
        table.sort(receivers)

        U.each(receivers, function(receiver)
            U.each(kinds, function(kind)
                local text = U.scaffold_type_artifact(project, I, receiver, kind)
                if text then
                    local path = U.project_type_artifact_path(project, receiver, kind)
                    if opts.force or not is_file(path) then
                        write_text(path, text .. "\n")
                        written[#written + 1] = { path = path, kind = kind, receiver = receiver }
                    end
                end
            end)
        end)

        return written
    end

    function U.cli_usage()
        return table.concat({
            "usage: terra unit.t <command> <source> [args...]",
            "",
            "commands:",
            "  init <dir> [--layout flat|tree]",
            "  status <source>",
            "  markdown <source>",
            "  pipeline <source>",
            "  boundaries <source>",
            "  backends <source>",
            "  path <source> <type-or-boundary> [impl|test|bench|profile]",
            "  backend-path <source> <type-or-boundary> <luajit|terra> [impl|test|bench|profile]",
            "  type-graph <source> <root> [max_depth]",
            "  prompt <source> <boundary> [max_depth]",
            "  scaffold <source> <boundary>",
            "  scaffold-all <source>",
            "  scaffold-file <source> <type-or-boundary> [impl|test|bench|profile]",
            "  scaffold-project <source> [--with-test] [--with-bench] [--with-profile] [--all-artifacts] [--force]",
            "  test-all <source>",
            "",
            "source forms:",
            "  - project directory with schema/, optional pipeline.lua, optional unit_project.lua",
            "  - direct .asdl schema file",
        }, "\n")
    end

    local function parse_scaffold_opts(args, offset)
        local opts = {}
        for i = offset or 1, #args do
            local arg = args[i]
            if arg == "--with-test" then opts.with_test = true
            elseif arg == "--with-bench" then opts.with_bench = true
            elseif arg == "--with-profile" then opts.with_profile = true
            elseif arg == "--all-artifacts" then opts.all_artifacts = true
            elseif arg == "--force" then opts.force = true
            elseif arg == "--missing" then opts.force = false
            end
        end
        return opts
    end

    function U.cli(argv)
        argv = argv or rawget(_G, "arg") or {}

        local command = argv[1]
        if not command or command == "help" or command == "--help" or command == "-h" then
            io.write(U.cli_usage(), "\n")
            return 0
        end

        if command == "init" then
            local dir = argv[2]
            if not dir then
                error("unit CLI: init requires <dir>", 2)
            end
            local layout = "flat"
            for i = 3, #argv do
                local value = argv[i]:match("^%-%-layout=(.+)$")
                if value then layout = value end
                if argv[i] == "--layout" then layout = argv[i + 1] or layout end
            end
            mkdir_p(join_path(dir, "schema"))
            mkdir_p(join_path(dir, "boundaries"))
            if not is_file(join_path(dir, "pipeline.lua")) then
                write_text(join_path(dir, "pipeline.lua"), "return {\n    -- \"PhaseA\",\n    -- \"PhaseB\",\n}\n")
            end
            if layout == "tree" and not is_file(join_path(dir, "unit_project.lua")) then
                write_text(join_path(dir, "unit_project.lua"), "return {\n    layout = \"tree\",\n}\n")
            end
            if not is_file(join_path(dir, "schema", "app.asdl")) then
                write_text(join_path(dir, "schema", "app.asdl"), "module Demo {\n    Node = () unique\n}\n")
            end
            io.write("initialized ", dir, "\n")
            return 0
        end

        local source = argv[2]
        if not source then
            error("unit CLI: missing <source>.\n\n" .. U.cli_usage(), 2)
        end

        local project = U.load_project(source)
        local I = U.inspect_from(source)

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
                io.write(string.format("%s -%s[%d]-> %s\n", edge.from, edge.verb, edge.count, edge.to))
            end
            return 0
        end

        if command == "boundaries" then
            for _, b in ipairs(I.boundaries) do
                io.write(b.receiver, ":", b.name, "()\n")
            end
            return 0
        end

        if command == "backends" then
            io.write(I.backend_status(), "\n")
            return 0
        end

        if command == "path" then
            local selector = argv[3]
            if not selector then error("unit CLI: path requires <type-or-boundary>", 2) end
            local kind = argv[4] or "impl"
            local receiver = receiver_for_selector(I, selector)
            if not receiver then error("unit CLI: unknown type or boundary '" .. tostring(selector) .. "'", 2) end
            local found = find_project_artifact(I.projects or { project }, receiver, kind)
            io.write((found or U.project_type_artifact_path(project, receiver, kind)), "\n")
            return 0
        end

        if command == "backend-path" then
            local selector = argv[3]
            if not selector then error("unit CLI: backend-path requires <type-or-boundary>", 2) end
            local backend = argv[4]
            if not backend then error("unit CLI: backend-path requires <luajit|terra>", 2) end
            local kind = argv[5] or "impl"
            local receiver = receiver_for_selector(I, selector)
            if not receiver then error("unit CLI: unknown type or boundary '" .. tostring(selector) .. "'", 2) end
            local found = find_project_backend_artifact(I.projects or { project }, receiver, backend, kind)
            io.write((found or U.project_type_backend_artifact_path(project, receiver, backend, kind)), "\n")
            return 0
        end

        if command == "type-graph" then
            local root = argv[3]
            if not root then error("unit CLI: type-graph requires <root>", 2) end
            local max_depth = tonumber(argv[4]) or 3
            io.write(I.type_graph(root, max_depth), "\n")
            return 0
        end

        if command == "prompt" then
            local boundary = argv[3]
            if not boundary then error("unit CLI: prompt requires <boundary>", 2) end
            local max_depth = tonumber(argv[4]) or 3
            io.write(I.prompt_for(boundary, max_depth), "\n")
            return 0
        end

        if command == "scaffold" then
            local boundary = argv[3]
            if not boundary then error("unit CLI: scaffold requires <boundary>", 2) end
            local scaffold = I.scaffold(boundary)
            if not scaffold then error("unit CLI: boundary not found: " .. tostring(boundary), 2) end
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

        if command == "scaffold-file" then
            local selector = argv[3]
            if not selector then error("unit CLI: scaffold-file requires <type-or-boundary>", 2) end
            local kind = argv[4] or "impl"
            local text, receiver = U.scaffold_type_artifact(project, I, selector, kind)
            if not text then error("unit CLI: cannot scaffold '" .. tostring(selector) .. "'", 2) end
            io.write("-- ", U.project_type_artifact_path(project, receiver, kind), "\n")
            io.write(text, "\n")
            return 0
        end

        if command == "scaffold-project" then
            local written = U.scaffold_project(project, I, parse_scaffold_opts(argv, 3))
            U.each(written, function(item)
                io.write(item.kind, " ", item.receiver, " -> ", item.path, "\n")
            end)
            io.write("wrote ", tostring(#written), " file(s)\n")
            return 0
        end

        if command == "test-all" then
            local results = I.test_all()
            io.write(string.format("passed %d/%d\n", results.passed, results.total))
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
