-- unit_inspect_core.lua
--
-- Backend-independent helpers for schema inspection / reflection.
--
-- This module stays pure. It knows nothing about Terra, LuaJIT FFI,
-- drivers, hot swap, or Unit state allocation. It only helps inspect
-- ASDL shapes and accumulated boundary metadata.

local M = {}

function M.new(U)
    local H = {}

    function H.basename(name)
        if not name then return nil end
        return name:match("([^.]+)$") or name
    end

    function H.unwrap_class(value)
        if type(value) == "table" and rawget(value, "__class") ~= nil then
            return rawget(value, "__class")
        end
        return value
    end

    function H.is_asdl_class(value)
        local class = H.unwrap_class(value)
        return type(class) == "table"
            and type(class.isclassof) == "function"
    end

    function H.is_public_method(name, value)
        return type(value) == "function"
            and name ~= "isclassof"
            and name ~= "init"
            and not name:match("^__")
    end

    function H.is_stub(boundary)
        local ok, err = pcall(boundary.fn, nil)
        if ok then return false end
        return tostring(err):lower():match("not implemented") ~= nil
    end

    function H.field_type_string(field)
        local suffix = ""
        if field.optional then suffix = "?"
        elseif field.list then suffix = "*" end
        return tostring(field.type) .. suffix
    end

    function H.new_phase_bucket()
        return {
            type_total = 0,
            record_total = 0,
            enum_total = 0,
            variant_total = 0,
            boundary_total = 0,
            boundary_real = 0,
            boundary_stub = 0,
            boundary_coverage = 0,
        }
    end

    function H.ensure_phase_bucket(by_phase, phase_name)
        local phase = by_phase[phase_name]
        if not phase then
            phase = H.new_phase_bucket()
            by_phase[phase_name] = phase
        end
        return phase
    end

    function H.discover_phases(ctx)
        local namespaces = (ctx and ctx.namespaces) or {}
        local phases = {}

        U.each(U.each_name({ namespaces }), function(name)
            local ns = namespaces[name]
            if type(ns) == "table" and U.any(U.each_name({ ns }), function(member_name)
                return H.is_asdl_class(ns[member_name])
            end) then
                phases[#phases + 1] = name
            end
        end)

        return phases
    end

    function H.sorted_class_names(ns)
        local names = {}
        U.filter_map_into(names, U.each_name({ ns }), function(name)
            local value = ns[name]
            if H.is_asdl_class(value) then
                return name
            end
        end)
        return names
    end

    function H.sort_boundaries(boundaries)
        table.sort(boundaries, function(a, b)
            if a.receiver == b.receiver then
                return a.name < b.name
            end
            return a.receiver < b.receiver
        end)
        return boundaries
    end

    function H.append_unique_item(list, seen, item)
        if not seen[item] then
            seen[item] = true
            list[#list + 1] = item
        end
    end

    function H.find_boundary(boundaries, boundary_name)
        return U.find(boundaries, function(b)
            return b.receiver .. ":" .. b.name == boundary_name
        end)
    end

    function H.resolve_type_name(type_map, basename_map, basename_ambiguous, type_name, phase_name)
        if type(type_name) ~= "string" then return nil end

        if type_map[type_name] then
            return type_name
        end

        if phase_name then
            local fqname = phase_name .. "." .. type_name
            if type_map[fqname] then
                return fqname
            end
        end

        if basename_ambiguous and basename_ambiguous[type_name] then
            return nil
        end

        return basename_map and basename_map[type_name] or nil
    end

    function H.direct_refs(type_map, resolve_type_name, t)
        local refs, seen = {}, {}

        local function add(fqname)
            if fqname and not seen[fqname] then
                seen[fqname] = true
                refs[#refs + 1] = type_map[fqname]
            end
        end

        if t.kind == "enum" then
            U.each(t.variant_types, function(variant_t)
                if variant_t then add(variant_t.fqname) end
            end)
        end

        U.each(t.fields or {}, function(field)
            add(resolve_type_name(field.type, t.phase))
        end)

        table.sort(refs, function(a, b)
            return a.fqname < b.fqname
        end)

        return refs
    end

    function H.render_type_graph(type_map, resolve_type_name, root_type, max_depth)
        max_depth = max_depth or 3

        local visited = {}
        local out = {}
        local first = true

        local function add(line)
            out[#out + 1] = line
        end

        local function walk(type_name, depth)
            if visited[type_name] then return end
            if depth > max_depth then return end

            local t = type_map[type_name]
            if not t then return end

            visited[type_name] = true

            if not first then add("") end
            first = false

            local indent = string.rep("  ", depth)
            local title = indent .. "### " .. t.fqname
            if t.kind == "enum" then
                title = title .. " (" .. #t.variants .. " variants)"
            end
            add(title)

            if t.kind == "enum" then
                U.each(t.variants, function(vname)
                    add(indent .. "| " .. vname)
                end)
            end

            U.each(t.fields or {}, function(field)
                add(indent .. "- "
                    .. tostring(field.name or field[1] or "?")
                    .. ": " .. H.field_type_string(field))
            end)

            if depth >= max_depth then return end

            if t.kind == "enum" then
                U.each(t.variant_types, function(variant_t)
                    if variant_t then walk(variant_t.fqname, depth + 1) end
                end)
            end

            U.each(t.fields or {}, function(field)
                local ref = resolve_type_name(field.type, t.phase)
                if ref then walk(ref, depth + 1) end
            end)
        end

        local root_name = root_type
        if type(root_type) == "table" and root_type.fqname then
            root_name = root_type.fqname
        end

        walk(root_name, 0)
        return table.concat(out, "\n")
    end

    function H.collect_prompt_child_items(boundaries, direct_refs, boundary)
        local child_items = {}
        local seen = {}

        U.each(direct_refs(boundary.type), function(ref_t)
            if ref_t and type(ref_t.class[boundary.name]) == "function" then
                H.append_unique_item(
                    child_items,
                    seen,
                    ref_t.fqname .. ":" .. boundary.name .. "()")
            end
        end)

        if #child_items == 0 then
            U.each(boundaries, function(other)
                if other.phase == boundary.phase and other.receiver ~= boundary.receiver then
                    H.append_unique_item(
                        child_items,
                        seen,
                        other.receiver .. ":" .. other.name .. "()")
                end
            end)
        end

        table.sort(child_items)
        return child_items
    end

    function H.append_prompt_sections(sections, boundary, type_graph_text, child_items)
        sections[#sections + 1] = "## Phase: " .. boundary.phase
        sections[#sections + 1] = "## Input type: " .. boundary.receiver
        sections[#sections + 1] = type_graph_text
        sections[#sections + 1] = "## Available child boundaries:"

        if #child_items == 0 then
            sections[#sections + 1] = "- none"
        else
            U.map_into(sections, child_items, function(item)
                return "- " .. item
            end)
        end

        sections[#sections + 1] = "## Implement: " .. boundary.receiver .. ":" .. boundary.name
        sections[#sections + 1] =
            "## Available: U.match, U.errors, U.with, U.transition, U.terminal"
    end

    function H.collect_record_scaffold_calls(type_map, resolve_type_name, t, boundary_name)
        local child_calls = {}
        U.filter_map_into(child_calls, t.fields or {}, function(field)
            local ref = resolve_type_name(field.type, t.phase)
            local ref_t = ref and type_map[ref] or nil
            if ref_t and type(ref_t.class[boundary_name]) == "function" then
                return {
                    field = field,
                    ref = ref_t,
                }
            end
        end)
        return child_calls
    end

    function H.append_record_scaffold(lines, boundary_name, child_calls)
        if #child_calls > 0 then
            lines[#lines + 1] = "    local errs = U.errors()"
            lines[#lines + 1] = ""

            U.each(child_calls, function(call)
                local fname = tostring(call.field.name or call.field[1] or "field")
                if call.field.list then
                    lines[#lines + 1] = "    local " .. fname
                        .. " = errs:each(self." .. fname
                        .. ", function(x)"
                    lines[#lines + 1] = "        return x:" .. boundary_name .. "()"
                    lines[#lines + 1] = "    end, \"id\")"
                else
                    lines[#lines + 1] = "    local " .. fname
                        .. " = errs:call(self." .. fname
                        .. ", function(x)"
                    lines[#lines + 1] = "        return x:" .. boundary_name .. "()"
                    lines[#lines + 1] = "    end)"
                end
                lines[#lines + 1] = ""
            end)

            lines[#lines + 1] = "    error(\"scaffold: construct return value and plumb errs:get()\", 2)"
        else
            lines[#lines + 1] = "    error(\"scaffold: implement boundary\", 2)"
        end

        lines[#lines + 1] = "end"
    end

    function H.append_type_markdown(lines, t)
        lines[#lines + 1] = "### " .. t.fqname .. " (" .. t.kind .. ")"

        if t.kind == "enum" then
            U.each(t.variants, function(vname)
                lines[#lines + 1] = "- `" .. vname .. "`"
            end)
        end

        U.each(t.fields or {}, function(field)
            lines[#lines + 1] = "- `"
                .. tostring(field.name or field[1] or "?")
                .. ": " .. H.field_type_string(field) .. "`"
        end)

        lines[#lines + 1] = ""
    end

    function H.append_phase_markdown(lines, phase_name, phase_types, phase_boundaries)
        lines[#lines + 1] = "## Phase: " .. phase_name
        lines[#lines + 1] = ""

        U.each(phase_types or {}, function(t)
            H.append_type_markdown(lines, t)
        end)

        if phase_boundaries and #phase_boundaries > 0 then
            lines[#lines + 1] = "### Boundaries"
            U.each(phase_boundaries, function(b)
                lines[#lines + 1] = "- `" .. b.receiver .. ":" .. b.name .. "()`"
            end)
        end

        lines[#lines + 1] = ""
    end

    function H.render_status(progress, phases)
        local p = progress
        local lines = {
            "Schema inventory:",
        }

        U.each(phases, function(phase_name)
            local phase = p.by_phase[phase_name]
            if phase and phase.type_total > 0 then
                lines[#lines + 1] = string.format(
                    "  %-14s types=%d records=%d enums=%d variants=%d",
                    phase_name .. ":",
                    phase.type_total,
                    phase.record_total,
                    phase.enum_total,
                    phase.variant_total)
            end
        end)

        lines[#lines + 1] = string.rep("─", 45)
        lines[#lines + 1] = string.format(
            "  %-14s types=%d records=%d enums=%d variants=%d",
            "Total:",
            p.type_total,
            p.record_total,
            p.enum_total,
            p.variant_total)

        lines[#lines + 1] = ""
        lines[#lines + 1] = "Boundary coverage:"

        U.each(phases, function(phase_name)
            local phase = p.by_phase[phase_name]
            if phase and phase.boundary_total > 0 then
                local bar_len = 20
                local filled = math.floor((phase.boundary_real / phase.boundary_total) * bar_len)
                local bar = string.rep("█", filled)
                    .. string.rep("░", bar_len - filled)

                lines[#lines + 1] = string.format(
                    "  %-14s %s  %d/%d",
                    phase_name .. ":",
                    bar,
                    phase.boundary_real,
                    phase.boundary_total)
            end
        end)

        lines[#lines + 1] = string.rep("─", 45)
        lines[#lines + 1] = string.format(
            "  %-14s %d/%d (%.1f%%)",
            "Total:",
            p.boundary_real,
            p.boundary_total,
            p.boundary_coverage * 100)

        return table.concat(lines, "\n")
    end

    function H.append_enum_scaffold(lines, variants)
        lines[#lines + 1] = "    return U.match(self, {"
        U.each(variants, function(vname)
            lines[#lines + 1] = "        " .. vname .. " = function(self)"
            lines[#lines + 1] = "            error(\"scaffold: implement enum branch\", 2)"
            lines[#lines + 1] = "        end,"
        end)
        lines[#lines + 1] = "    })"
        lines[#lines + 1] = "end"
    end

    return H
end

function M.build(U, ctx, phases, pipeline_phases)
    local H = M.new(U)

    phases = phases or H.discover_phases(ctx)
    if #phases == 0 then phases = H.discover_phases(ctx) end
    pipeline_phases = pipeline_phases or phases

    local I = {
        ctx = ctx,
        phases = phases,
        pipeline_phases = pipeline_phases,
        types = {},
        types_by_phase = {},
        type_map = {},
        basename_map = {},
        basename_ambiguous = {},
        boundaries = {},
        boundaries_by_phase = {},
        boundary_counts_by_phase = {},
        phase_primary_verbs = {},
    }

    local class_map = {}

    U.each(phases, function(phase_name)
        local ns = ctx[phase_name]
        if type(ns) == "table" then
            local phase_types = I.types_by_phase[phase_name]
            if not phase_types then
                phase_types = {}
                I.types_by_phase[phase_name] = phase_types
            end

            U.each(H.sorted_class_names(ns), function(name)
                local raw_value = ns[name]
                local class = H.unwrap_class(raw_value)
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
                phase_types[#phase_types + 1] = t
                I.type_map[fqname] = t
                class_map[class] = t
                class.__name = class.__name or fqname

                if not I.basename_ambiguous[name] then
                    local existing = I.basename_map[name]
                    if existing and existing ~= fqname then
                        I.basename_map[name] = nil
                        I.basename_ambiguous[name] = true
                    else
                        I.basename_map[name] = fqname
                    end
                end
            end)
        end
    end)

    U.each(I.types, function(t)
        local variant_entries = {}
        if type(t.class.members) == "table" then
            U.filter_map_into(variant_entries, t.class.members, function(member)
                if member ~= t.class then
                    local variant_t = class_map[member]
                    return {
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

    U.each(I.types, function(t)
        local method_names = {}
        local parent = t.class.__sum_parent
        U.filter_map_into(method_names, U.each_name({ t.class }), function(name)
            local fn = t.class[name]
            if H.is_public_method(name, fn)
                and not (parent and parent[name] == fn) then
                return name
            end
        end)
        t.methods = method_names

        local phase_boundaries = I.boundaries_by_phase[t.phase]
        if not phase_boundaries then
            phase_boundaries = {}
            I.boundaries_by_phase[t.phase] = phase_boundaries
        end

        local phase_counts = I.boundary_counts_by_phase[t.phase]
        if not phase_counts then
            phase_counts = {}
            I.boundary_counts_by_phase[t.phase] = phase_counts
        end

        U.each(method_names, function(name)
            local boundary = {
                receiver = t.fqname,
                receiver_name = t.name,
                name = name,
                fn = t.class[name],
                phase = t.phase,
                type = t,
            }
            I.boundaries[#I.boundaries + 1] = boundary
            phase_boundaries[#phase_boundaries + 1] = boundary
            phase_counts[name] = (phase_counts[name] or 0) + 1
        end)
    end)

    H.sort_boundaries(I.boundaries)
    U.each(phases, function(phase_name)
        local phase_boundaries = I.boundaries_by_phase[phase_name]
        if phase_boundaries then
            H.sort_boundaries(phase_boundaries)
        end

        local counts = I.boundary_counts_by_phase[phase_name] or {}
        local primary = { verb = "?", count = 0 }
        U.each(U.each_name({ counts }), function(name)
            local count = counts[name]
            if count > primary.count then
                primary.verb = name
                primary.count = count
            end
        end)
        I.phase_primary_verbs[phase_name] = primary
    end)

    local function resolve_type_name(type_name, phase_name)
        return H.resolve_type_name(
            I.type_map,
            I.basename_map,
            I.basename_ambiguous,
            type_name,
            phase_name)
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
            if H.is_stub(b) then
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
        local edges = {}
        for i = 1, #pipeline_phases - 1 do
            local from = pipeline_phases[i]
            local to = pipeline_phases[i + 1]
            local primary = I.phase_primary_verbs[from] or { verb = "?", count = 0 }

            edges[#edges + 1] = {
                from = from,
                to = to,
                verb = primary.verb,
                count = primary.count,
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
            H.append_phase_markdown(
                lines,
                phase_name,
                I.types_by_phase[phase_name],
                I.boundaries_by_phase[phase_name])
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

function M.install(U)
    U.inspect = function(ctx, phases, pipeline_phases)
        return M.build(U, ctx, phases, pipeline_phases)
    end
    return U
end

return M
