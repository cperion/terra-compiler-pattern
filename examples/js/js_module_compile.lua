local ffi = require("ffi")
local U = require("unit")
local JS_TDZ = require("examples.js.js_runtime").JS_TDZ

local function S(v)
    if v == nil then return nil end
    if type(v) == "cdata" then return ffi.string(v) end
    return tostring(v)
end

return function(T)
    local ML = T.JsModuleLinked

    local function module_id_string(id)
        return id and S(id.value) or nil
    end

    local function slot_key(slot)
        if not slot then return nil end
        if S(slot.kind) ~= "LocalSlot" then return nil end
        return tostring(tonumber(slot.depth)) .. ":" .. tostring(tonumber(slot.index))
    end

    local function export_record(linked_export)
        local binding = linked_export.binding
        local kind = S(binding.kind)
        return {
            exported_name = S(linked_export.exported_name),
            binding = binding,
            kind = kind,
            cell = binding.cell and tonumber(binding.cell) or nil,
            slot = binding.slot or nil,
            from_module = binding.from_module and module_id_string(binding.from_module) or nil,
        }
    end

    local function import_record(linked_import)
        return {
            local_slot = linked_import.local_slot,
            local_slot_key = slot_key(linked_import.local_slot),
            from_module = module_id_string(linked_import.from_module),
            import_name = S(linked_import.import_name),
            kind = S(linked_import.kind.kind),
            import_cell = tonumber(linked_import.import_cell) or 0,
        }
    end

    local function own_export_cell_count(exports)
        local max_cell = 0
        for i = 1, #exports do
            local ex = exports[i]
            if (ex.kind == "LocalSlotExport" or ex.kind == "ExprExport") and ex.cell and ex.cell > max_cell then
                max_cell = ex.cell
            end
        end
        return max_cell
    end

    local function unique_dependencies(imports)
        local out = {}
        local seen = {}
        for i = 1, #imports do
            local dep = imports[i].from_module
            if dep and dep ~= "" and not seen[dep] then
                seen[dep] = true
                out[#out + 1] = dep
            end
        end
        return out
    end

    local function compute_sccs(compiled_modules)
        local by_id = {}
        for i = 1, #compiled_modules do by_id[compiled_modules[i].id] = compiled_modules[i] end

        local index = 0
        local stack = {}
        local onstack = {}
        local indices = {}
        local lowlink = {}
        local sccs = {}
        local module_to_scc = {}

        local strongconnect
        strongconnect = function(id)
            index = index + 1
            indices[id] = index
            lowlink[id] = index
            stack[#stack + 1] = id
            onstack[id] = true

            local m = by_id[id]
            for i = 1, #(m and m.deps or {}) do
                local dep = m.deps[i]
                if by_id[dep] then
                    if not indices[dep] then
                        strongconnect(dep)
                        if lowlink[dep] < lowlink[id] then lowlink[id] = lowlink[dep] end
                    elseif onstack[dep] and indices[dep] < lowlink[id] then
                        lowlink[id] = indices[dep]
                    end
                end
            end

            if lowlink[id] == indices[id] then
                local comp = {}
                while true do
                    local w = stack[#stack]
                    stack[#stack] = nil
                    onstack[w] = nil
                    comp[#comp + 1] = w
                    module_to_scc[w] = #sccs + 1
                    if w == id then break end
                end
                sccs[#sccs + 1] = comp
            end
        end

        for i = 1, #compiled_modules do
            local id = compiled_modules[i].id
            if not indices[id] then strongconnect(id) end
        end

        return sccs, module_to_scc
    end

    local function module_root(E)
        local f = E
        while f[0] do f = f[0] end
        return f
    end

    local function raw_frame_read(E, depth, index)
        local f = E
        for _ = 1, depth do f = f[0] end
        return f[index]
    end

    local function stmt_kind(stmt)
        return stmt and S(stmt.kind) or nil
    end

    local function varkind_name(var_kind)
        if not var_kind then return nil end
        if type(var_kind) == "string" then return var_kind end
        return S(var_kind.kind or var_kind)
    end

    local function split_module_bodies(T, body)
        local instantiate_body = {}
        local eval_body = {}
        local hoisted_function_slots = {}

        for i = 1, #body do
            local stmt = body[i]
            local kind = stmt_kind(stmt)
            if kind == "FuncDecl" then
                instantiate_body[#instantiate_body + 1] = stmt
                hoisted_function_slots[slot_key(stmt.target)] = true
            elseif kind == "VarDecl" and varkind_name(stmt.var_kind) == "Var" then
                local decls = {}
                for j = 1, #stmt.decls do
                    local d = stmt.decls[j]
                    decls[j] = T.JsResolved.RDeclarator(d.target, nil)
                end
                instantiate_body[#instantiate_body + 1] = T.JsResolved.VarDecl(stmt.var_kind, decls)
                eval_body[#eval_body + 1] = stmt
            else
                eval_body[#eval_body + 1] = stmt
            end
        end

        return instantiate_body, eval_body, hoisted_function_slots
    end

    local function lexical_tdz_inventory(scope, imports_by_slot, hoisted_function_slots)
        local slot_names = {}
        local slot_indices = {}
        if not scope then return slot_names, slot_indices end
        for i = 1, #scope.bindings do
            local binding = scope.bindings[i]
            local kind = varkind_name(binding.kind)
            local slot = T.JsResolved.LocalSlot(scope.depth, binding.slot, binding.kind)
            local key = slot_key(slot)
            if kind ~= "Var" and not imports_by_slot[key] and not hoisted_function_slots[key] then
                slot_names[key] = S(binding.name)
                slot_indices[#slot_indices + 1] = tonumber(binding.slot)
            end
        end
        return slot_names, slot_indices
    end

    ML.ModuleGraph.compile_modules = U.terminal("JsModuleLinked.ModuleGraph:compile_modules", function(graph)
        local compiled_modules = {}
        local compiled_by_id = {}

        for i = 1, #graph.modules do
            local linked = graph.modules[i]

            local imports = {}
            local imports_by_slot = {}
            for j = 1, #linked.imports do
                local rec = import_record(linked.imports[j])
                imports[j] = rec
                if rec.local_slot_key then imports_by_slot[rec.local_slot_key] = rec end
            end

            local exports = {}
            local exported_local_slots = {}
            local has_expr_exports = false
            for j = 1, #linked.exports do
                local rec = export_record(linked.exports[j])
                exports[j] = rec
                if rec.kind == "LocalSlotExport" and rec.slot then
                    exported_local_slots[slot_key(rec.slot)] = rec.cell
                elseif rec.kind == "ExprExport" then
                    has_expr_exports = true
                end
            end

            local instantiate_body, eval_body, hoisted_function_slots = split_module_bodies(T, linked.eval_body)
            local lexical_tdz_slot_names, lexical_tdz_slot_indices = lexical_tdz_inventory(linked.scope, imports_by_slot, hoisted_function_slots)

            local hooks = {
                read_slot = function(slot, globals, current_depth, plain)
                    local key = slot_key(slot)
                    local imp = imports_by_slot[key]
                    if imp then
                        if imp.kind == "ValueImport" then
                            return function(E)
                                local root = module_root(E)
                                local runtime = root.__module_runtime
                                return runtime:read_export_cell(imp.from_module, imp.import_cell, imp.import_name)
                            end
                        elseif imp.kind == "NamespaceImport" then
                            return function(E)
                                local root = module_root(E)
                                return root.__module_runtime:namespace_of(imp.from_module)
                            end
                        end
                        return nil
                    end
                    local local_name = lexical_tdz_slot_names[key]
                    if local_name then
                        local d = (current_depth or 0) - tonumber(slot.depth)
                        local idx = tonumber(slot.index)
                        return function(E)
                            local v
                            if d == 0 then
                                v = E[idx]
                            elseif d == 1 then
                                v = E[0][idx]
                            else
                                v = raw_frame_read(E, d, idx)
                            end
                            if rawequal(v, JS_TDZ) then
                                error("Cannot access local module binding '" .. tostring(local_name) .. "' before initialization")
                            end
                            return v
                        end
                    end
                    return nil
                end,
                init_slot = function(slot, globals, current_depth, plain)
                    local key = slot_key(slot)
                    local cell = exported_local_slots[key]
                    if cell then
                        local base = plain()
                        return function(E, v)
                            base(E, v)
                            local root = module_root(E)
                            root.__module_state.export_cells[cell] = v
                        end
                    end
                    return nil
                end,
                write_slot = function(slot, globals, current_depth, plain)
                    local key = slot_key(slot)
                    local imp = imports_by_slot[key]
                    if imp then
                        return function(E, v)
                            error("assignment to import binding")
                        end
                    end
                    local cell = exported_local_slots[key]
                    if cell then
                        local base = plain()
                        return function(E, v)
                            base(E, v)
                            local root = module_root(E)
                            root.__module_state.export_cells[cell] = v
                        end
                    end
                    return nil
                end,
            }

            local instantiate_program = T.JsResolved.Program(instantiate_body, linked.scope)
            local eval_program = T.JsResolved.Program(eval_body, linked.scope)
            local compiled_instantiate = T._js_compile_program(instantiate_program, nil, hooks)
            local compiled_eval = T._js_compile_program(eval_program, nil, hooks)

            local compiled_module = {
                id = module_id_string(linked.id),
                frame_size = compiled_eval.frame_size,
                instantiate_machine = compiled_instantiate,
                eval_machine = compiled_eval,
                imports = imports,
                imports_by_slot = imports_by_slot,
                exports = exports,
                export_cell_count = own_export_cell_count(exports),
                has_expr_exports = has_expr_exports,
                deps = unique_dependencies(imports),
                lexical_tdz_slot_indices = lexical_tdz_slot_indices,
            }
            compiled_modules[#compiled_modules + 1] = compiled_module
            compiled_by_id[compiled_module.id] = compiled_module
        end

        local sccs, module_to_scc = compute_sccs(compiled_modules)

        local compiled_graph = {
            modules = compiled_modules,
            modules_by_id = compiled_by_id,
            entry = module_id_string(graph.entry),
            sccs = sccs,
            module_to_scc = module_to_scc,
        }

        function compiled_graph:instantiate()
            local runtime = {
                entry = self.entry,
                modules = {},
                module_by_id = {},
                namespace_cache = {},
                __sccs = self.sccs,
                __module_to_scc = self.module_to_scc,
            }

            for i = 1, #self.modules do
                local cm = self.modules[i]
                local inst = {
                    id = cm.id,
                    state = "instantiated",
                    frame_size = cm.frame_size,
                    instantiate_machine = cm.instantiate_machine,
                    eval_machine = cm.eval_machine,
                    imports = cm.imports,
                    exports = cm.exports,
                    deps = cm.deps,
                    export_cells = {},
                    frame = nil,
                    exports_by_name = {},
                    has_expr_exports = cm.has_expr_exports,
                    lexical_tdz_slot_indices = cm.lexical_tdz_slot_indices,
                }
                for j = 1, cm.export_cell_count do
                    inst.export_cells[j] = JS_TDZ
                end
                for j = 1, #cm.exports do
                    local ex = cm.exports[j]
                    inst.exports_by_name[ex.exported_name] = ex
                end
                local root = { [0] = nil, __module_runtime = runtime, __module_state = inst }
                for j = 1, cm.frame_size do root[j] = nil end
                for j = 1, #cm.lexical_tdz_slot_indices do
                    root[cm.lexical_tdz_slot_indices[j]] = JS_TDZ
                end
                inst.frame = root
                runtime.modules[#runtime.modules + 1] = inst
                runtime.module_by_id[cm.id] = inst
            end

            function runtime:read_export_cell(module_id, cell, export_name)
                local inst = self.module_by_id[module_id]
                if not inst then error("unknown module: " .. tostring(module_id)) end
                local value = rawget(inst.export_cells, cell)
                if rawequal(value, JS_TDZ) then
                    error("Cannot access module binding '" .. tostring(export_name) .. "' from module '" .. tostring(module_id) .. "' before initialization")
                end
                return value
            end

            function runtime:namespace_of(module_id)
                local cached = self.namespace_cache[module_id]
                if cached then return cached end
                local inst = self.module_by_id[module_id]
                if not inst then error("unknown module namespace: " .. tostring(module_id)) end
                local ns = setmetatable({}, {
                    __index = function(_, key)
                        local ex = inst.exports_by_name[key]
                        if not ex then return nil end
                        if ex.kind == "NamespaceExport" then
                            return self:namespace_of(ex.from_module)
                        elseif ex.kind == "ReExportCell" then
                            return self:read_export_cell(ex.from_module, ex.cell, key)
                        elseif ex.kind == "LocalSlotExport" or ex.kind == "ExprExport" then
                            return self:read_export_cell(module_id, ex.cell, key)
                        end
                        return nil
                    end,
                })
                self.namespace_cache[module_id] = ns
                return ns
            end

            function runtime:instantiate_one(module_id)
                local inst = self.module_by_id[module_id]
                if not inst then error("unknown module: " .. tostring(module_id)) end
                if inst.state ~= "instantiated" then return end
                inst.state = "preparing"
                inst.instantiate_machine.run_with_frame(inst.frame)
                inst.state = "prepared"
            end

            function runtime:evaluate_one(module_id)
                local inst = self.module_by_id[module_id]
                if not inst then error("unknown module: " .. tostring(module_id)) end
                if inst.state == "evaluated" then return end
                if inst.state == "instantiated" then self:instantiate_one(module_id) end
                if inst.has_expr_exports then
                    error("Native module execution does not support ExprExport yet; export default expressions still need ordered execution hookup")
                end
                inst.state = "evaluating"
                inst.eval_machine.run_with_frame(inst.frame)
                inst.state = "evaluated"
            end

            function runtime:reachable_modules(entry_id)
                local seen = {}
                local out = {}
                local function visit(id)
                    if not id or seen[id] then return end
                    seen[id] = true
                    out[#out + 1] = id
                    local inst = self.module_by_id[id]
                    if inst then
                        for i = 1, #inst.deps do visit(inst.deps[i]) end
                    end
                end
                visit(entry_id)
                return out, seen
            end

            function runtime:scc_order(entry_id)
                local _, reachable = self:reachable_modules(entry_id)
                local indegree = {}
                local edges = {}
                local present = {}
                for module_id, _ in pairs(reachable) do
                    local scc = self.__module_to_scc[module_id]
                    present[scc] = true
                    indegree[scc] = indegree[scc] or 0
                    edges[scc] = edges[scc] or {}
                end
                for module_id, _ in pairs(reachable) do
                    local from_scc = self.__module_to_scc[module_id]
                    local inst = self.module_by_id[module_id]
                    for i = 1, #inst.deps do
                        local dep = inst.deps[i]
                        if reachable[dep] then
                            local to_scc = self.__module_to_scc[dep]
                            if from_scc ~= to_scc and not edges[to_scc][from_scc] then
                                edges[to_scc][from_scc] = true
                                indegree[from_scc] = (indegree[from_scc] or 0) + 1
                            end
                        end
                    end
                end
                local queue = {}
                for scc, _ in pairs(present) do
                    if (indegree[scc] or 0) == 0 then queue[#queue + 1] = scc end
                end
                table.sort(queue)
                local order = {}
                local qh = 1
                while qh <= #queue do
                    local scc = queue[qh]
                    qh = qh + 1
                    order[#order + 1] = scc
                    for dep_scc, _ in pairs(edges[scc] or {}) do
                        indegree[dep_scc] = indegree[dep_scc] - 1
                        if indegree[dep_scc] == 0 then queue[#queue + 1] = dep_scc end
                    end
                end
                return order
            end

            function runtime:execute(entry_id)
                local target = entry_id or self.entry
                if not target then error("no entry module configured") end
                local order = self:scc_order(target)
                for i = 1, #order do
                    local scc_index = order[i]
                    local component = self.__sccs[scc_index]
                    table.sort(component)
                    for j = 1, #component do
                        self:instantiate_one(component[j])
                    end
                    for j = 1, #component do
                        self:evaluate_one(component[j])
                    end
                end
                return self.module_by_id[target]
            end

            return runtime
        end

        return compiled_graph
    end)
end
