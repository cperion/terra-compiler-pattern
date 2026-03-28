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

    function H.is_asdl_class(value)
        return type(value) == "table"
            and type(value.isclassof) == "function"
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
            if type(ns) == "table" then
                local found = false
                U.each(U.each_name({ ns }), function(member_name)
                    if not found and H.is_asdl_class(ns[member_name]) then
                        found = true
                    end
                end)
                if found then
                    phases[#phases + 1] = name
                end
            end
        end)

        return phases
    end

    function H.sorted_class_names(ns)
        local names = {}
        U.each(U.each_name({ ns }), function(name)
            if H.is_asdl_class(ns[name]) then
                names[#names + 1] = name
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
        local match = nil
        U.each(boundaries, function(b)
            if b.receiver .. ":" .. b.name == boundary_name then
                match = b
            end
        end)
        return match
    end

    function H.resolve_type_name(type_map, type_name, phase_name)
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

        local match = nil
        U.each(U.each_name({ type_map }), function(fqname)
            if H.basename(fqname) == type_name then
                if match and match ~= fqname then
                    match = false
                    return
                end
                match = fqname
            end
        end)

        if match == false then return nil end
        return match
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
        local sections = {}

        local function walk(type_name, depth)
            if visited[type_name] then return end
            if depth > max_depth then return end

            local t = type_map[type_name]
            if not t then return end

            visited[type_name] = true

            local indent = string.rep("  ", depth)
            local lines = {}
            local title = indent .. "### " .. t.fqname
            if t.kind == "enum" then
                title = title .. " (" .. #t.variants .. " variants)"
            end
            lines[#lines + 1] = title

            if t.kind == "enum" then
                U.each(t.variants, function(vname)
                    lines[#lines + 1] = indent .. "| " .. vname
                end)
            end

            U.each(t.fields or {}, function(field)
                lines[#lines + 1] = indent .. "- "
                    .. tostring(field.name or field[1] or "?")
                    .. ": " .. H.field_type_string(field)
            end)

            sections[#sections + 1] = table.concat(lines, "\n")

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
        return table.concat(sections, "\n\n")
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
            U.each(child_items, function(item)
                sections[#sections + 1] = "- " .. item
            end)
        end

        sections[#sections + 1] = "## Implement: " .. boundary.receiver .. ":" .. boundary.name
        sections[#sections + 1] =
            "## Available: U.match, U.errors, U.with, U.transition, U.terminal"
    end

    function H.collect_record_scaffold_calls(type_map, resolve_type_name, t, boundary_name)
        local child_calls = {}
        U.each(t.fields or {}, function(field)
            local ref = resolve_type_name(field.type, t.phase)
            local ref_t = ref and type_map[ref] or nil
            if ref_t and type(ref_t.class[boundary_name]) == "function" then
                child_calls[#child_calls + 1] = {
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

            lines[#lines + 1] = "    -- TODO: construct return value"
            lines[#lines + 1] = "    -- return ..., errs:get()"
        else
            lines[#lines + 1] = "    -- TODO: implement"
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

    function H.append_phase_markdown(lines, phase_name, types, boundaries)
        lines[#lines + 1] = "## Phase: " .. phase_name
        lines[#lines + 1] = ""

        U.each(types, function(t)
            if t.phase == phase_name then
                H.append_type_markdown(lines, t)
            end
        end)

        local have_boundaries = false
        U.each(boundaries, function(b)
            if b.phase == phase_name then
                if not have_boundaries then
                    lines[#lines + 1] = "### Boundaries"
                    have_boundaries = true
                end
                lines[#lines + 1] = "- `" .. b.receiver .. ":" .. b.name .. "()`"
            end
        end)

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
            lines[#lines + 1] = "            -- TODO: implement"
            lines[#lines + 1] = "        end,"
        end)
        lines[#lines + 1] = "    })"
        lines[#lines + 1] = "end"
    end

    return H
end

return M
