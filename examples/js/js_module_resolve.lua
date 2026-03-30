local ffi = require("ffi")
local U = require("unit")
local asdl = require("asdl")
local L = asdl.List

local function S(v)
    if v == nil then return nil end
    if type(v) == "cdata" then return ffi.string(v) end
    return tostring(v)
end

local function concat_lists(...)
    local out = L{}
    for i = 1, select("#", ...) do
        local xs = select(i, ...)
        if xs then
            for j = 1, #xs do out[#out + 1] = xs[j] end
        end
    end
    return out
end

return function(T)
    local MS = T.JsModuleSource
    local MR = T.JsModuleResolved
    local J = T.JsSource

    local function prelude_for_imports(imports)
        local out = L{}
        for i = 1, #imports do
            local imp = imports[i]
            local kind = S(imp.kind)
            local local_name = nil
            if kind == "ImportDefault" or kind == "ImportNamespace" then
                local local_name_v = imp.local_name
                local_name = local_name_v and S(local_name_v) or nil
            elseif kind == "ImportNamed" then
                local_name = S(imp.local_name)
            end
            if local_name then
                out[#out + 1] = J.VarDecl(T.JsCore.Const, L{ J.Declarator(local_name, nil) })
            end
        end
        return out
    end

    local function prelude_for_top_level_lexicals(body)
        local out = L{}
        local seen = {}
        for i = 1, #body do
            local stmt = body[i]
            if S(stmt.kind) == "VarDecl" then
                local var_kind = S(stmt.var_kind.kind or stmt.var_kind)
                if var_kind == "Let" or var_kind == "Const" then
                    for j = 1, #stmt.decls do
                        local d = stmt.decls[j]
                        local name = S(d.name)
                        if not seen[name] then
                            seen[name] = true
                            out[#out + 1] = J.VarDecl(stmt.var_kind, L{ J.Declarator(name, nil) })
                        end
                    end
                end
            end
        end
        return out
    end

    local function binding_map(scope)
        local map = {}
        for i = 1, #scope.bindings do
            local b = scope.bindings[i]
            map[S(b.name)] = T.JsResolved.LocalSlot(scope.depth, b.slot, b.kind)
        end
        return map
    end

    local function resolve_module(module)
        local prelude = concat_lists(
            prelude_for_imports(module.imports),
            prelude_for_top_level_lexicals(module.eval_body)
        )

        local default_expr_tails = L{}
        local default_expr_count = 0
        for i = 1, #module.exports do
            local ex = module.exports[i]
            if S(ex.kind) == "ExportDefaultExpr" then
                default_expr_count = default_expr_count + 1
                default_expr_tails[#default_expr_tails + 1] = J.ExprStmt(ex.expr)
            end
        end

        local source_program = J.Program(concat_lists(prelude, module.eval_body, default_expr_tails))
        local resolved_program = source_program:resolve()
        local slots = binding_map(resolved_program.scope)

        local resolved_eval_body = L{}
        local prelude_count = #prelude
        for i = 1, #module.eval_body do
            resolved_eval_body[#resolved_eval_body + 1] = resolved_program.body[prelude_count + i]
        end

        local resolved_default_exprs = {}
        for i = 1, default_expr_count do
            local stmt = resolved_program.body[prelude_count + #module.eval_body + i]
            resolved_default_exprs[i] = stmt.expr
        end

        local resolved_imports = L{}
        for i = 1, #module.imports do
            local imp = module.imports[i]
            local kind = S(imp.kind)
            if kind == "ImportModule" then
                resolved_imports[#resolved_imports + 1] = MR.ImportModule(S(imp.specifier))
            elseif kind == "ImportDefault" then
                resolved_imports[#resolved_imports + 1] = MR.ImportDefault(slots[S(imp.local_name)], S(imp.specifier))
            elseif kind == "ImportNamespace" then
                resolved_imports[#resolved_imports + 1] = MR.ImportNamespace(slots[S(imp.local_name)], S(imp.specifier))
            elseif kind == "ImportNamed" then
                resolved_imports[#resolved_imports + 1] = MR.ImportNamed(S(imp.imported_name), slots[S(imp.local_name)], S(imp.specifier))
            else
                error("unknown JsModuleSource import kind " .. tostring(kind))
            end
        end

        local resolved_exports = L{}
        local default_expr_index = 1
        for i = 1, #module.exports do
            local ex = module.exports[i]
            local kind = S(ex.kind)
            if kind == "ExportLocal" then
                resolved_exports[#resolved_exports + 1] = MR.ExportLocal(slots[S(ex.local_name)], S(ex.exported_name))
            elseif kind == "ExportDefaultExpr" then
                resolved_exports[#resolved_exports + 1] = MR.ExportDefaultExpr(resolved_default_exprs[default_expr_index])
                default_expr_index = default_expr_index + 1
            elseif kind == "ExportDefaultDecl" then
                resolved_exports[#resolved_exports + 1] = MR.ExportLocal(slots[S(ex.local_name)], "default")
            elseif kind == "ExportFrom" then
                resolved_exports[#resolved_exports + 1] = MR.ExportFrom(S(ex.imported_name), S(ex.exported_name), S(ex.specifier))
            elseif kind == "ExportAll" then
                resolved_exports[#resolved_exports + 1] = MR.ExportAll(S(ex.specifier))
            elseif kind == "ExportAllAs" then
                resolved_exports[#resolved_exports + 1] = MR.ExportAllAs(S(ex.exported_name), S(ex.specifier))
            else
                error("unknown JsModuleSource export kind " .. tostring(kind))
            end
        end

        return MR.Module(module.self_id, resolved_imports, resolved_exports, resolved_eval_body, resolved_program.scope)
    end

    MS.Module.resolve_locals = U.transition("JsModuleSource.Module:resolve_locals", function(module)
        return resolve_module(module)
    end)

    MS.ModuleGraph.resolve_locals = U.transition("JsModuleSource.ModuleGraph:resolve_locals", function(graph)
        local modules = L{}
        for i = 1, #graph.modules do
            modules[#modules + 1] = resolve_module(graph.modules[i])
        end
        return MR.ModuleGraph(modules, graph.entry)
    end)

    local function module_id_string(id)
        if not id then return nil end
        return S(id.value)
    end

    local function graph_index(graph)
        local modules_by_id = {}
        for i = 1, #graph.modules do
            local m = graph.modules[i]
            local id = module_id_string(m.self_id)
            if not id then
                error("JsModuleResolved.ModuleGraph:link requires every module to have self_id")
            end
            if modules_by_id[id] then
                error("duplicate module id in graph: " .. id)
            end
            modules_by_id[id] = m
        end
        return modules_by_id
    end

    local function slot_key(slot)
        if not slot then return nil end
        local kind = S(slot.kind)
        if kind ~= "LocalSlot" then return nil end
        return tostring(tonumber(slot.depth)) .. ":" .. tostring(tonumber(slot.index))
    end

    local function export_cell(binding)
        local kind = S(binding.kind)
        if kind == "LocalSlotExport" or kind == "ExprExport" then
            return tonumber(binding.cell)
        elseif kind == "ReExportCell" then
            return tonumber(binding.cell)
        end
        error("binding has no direct cell: " .. tostring(kind))
    end

    local function forward_binding(target_module, binding)
        local kind = S(binding.kind)
        if kind == "LocalSlotExport" or kind == "ExprExport" then
            return T.JsModuleLinked.ReExportCell(target_module.self_id, export_cell(binding))
        elseif kind == "ReExportCell" then
            return T.JsModuleLinked.ReExportCell(binding.from_module, binding.cell)
        elseif kind == "NamespaceExport" then
            return T.JsModuleLinked.NamespaceExport(binding.from_module)
        end
        error("cannot forward binding kind " .. tostring(kind))
    end

    MR.ModuleGraph.link = U.transition("JsModuleResolved.ModuleGraph:link", function(graph)
        local modules_by_id = graph_index(graph)
        local export_tables = {}
        local export_lists = {}

        local function resolve_exports(module_id, active)
            if export_tables[module_id] then return export_tables[module_id], export_lists[module_id] end
            active = active or {}
            if active[module_id] then
                error("JsModuleResolved.ModuleGraph:link does not support module cycles yet (while resolving exports for '" .. module_id .. "')")
            end
            active[module_id] = true

            local module = modules_by_id[module_id]
            if not module then
                error("JsModuleResolved.ModuleGraph:link missing module '" .. module_id .. "'")
            end

            local exports_by_name = {}
            local ordered = L{}
            local next_cell = 0

            local imported_slots = {}
            for i = 1, #module.imports do
                local imp = module.imports[i]
                local kind = S(imp.kind)
                if kind ~= "ImportModule" then
                    imported_slots[slot_key(imp.local_slot)] = imp
                end
            end

            local function add_export(name, binding)
                if exports_by_name[name] then
                    error("duplicate export name '" .. name .. "' in module " .. module_id)
                end
                exports_by_name[name] = binding
                ordered[#ordered + 1] = T.JsModuleLinked.LinkedExport(name, binding)
            end

            for i = 1, #module.exports do
                local ex = module.exports[i]
                local kind = S(ex.kind)
                if kind == "ExportLocal" then
                    local imported = imported_slots[slot_key(ex.local_slot)]
                    if imported then
                        local import_kind = S(imported.kind)
                        local specifier = S(imported.specifier)
                        local target = modules_by_id[specifier]
                        if not target then
                            error("JsModuleResolved.ModuleGraph:link could not resolve module specifier '" .. tostring(specifier) .. "'")
                        end
                        if import_kind == "ImportNamespace" then
                            resolve_exports(specifier, active)
                            add_export(S(ex.exported_name), T.JsModuleLinked.NamespaceExport(target.self_id))
                        else
                            local import_name = import_kind == "ImportDefault" and "default" or S(imported.imported_name)
                            local target_exports = select(1, resolve_exports(specifier, active))
                            local binding = target_exports[import_name]
                            if not binding then
                                error("module '" .. specifier .. "' has no export named '" .. import_name .. "'")
                            end
                            if S(binding.kind) == "NamespaceExport" then
                                add_export(S(ex.exported_name), T.JsModuleLinked.NamespaceExport(binding.from_module))
                            else
                                add_export(S(ex.exported_name), T.JsModuleLinked.ReExportCell(target.self_id, export_cell(binding)))
                            end
                        end
                    else
                        next_cell = next_cell + 1
                        add_export(S(ex.exported_name), T.JsModuleLinked.LocalSlotExport(ex.local_slot, next_cell))
                    end
                elseif kind == "ExportDefaultExpr" then
                    next_cell = next_cell + 1
                    add_export("default", T.JsModuleLinked.ExprExport(ex.expr, next_cell))
                elseif kind == "ExportFrom" then
                    local specifier = S(ex.specifier)
                    local target = modules_by_id[specifier]
                    if not target then
                        error("JsModuleResolved.ModuleGraph:link could not resolve module specifier '" .. tostring(specifier) .. "'")
                    end
                    local target_exports = select(1, resolve_exports(specifier, active))
                    local import_name = S(ex.imported_name)
                    local binding = target_exports[import_name]
                    if not binding then
                        error("module '" .. specifier .. "' has no export named '" .. import_name .. "'")
                    end
                    add_export(S(ex.exported_name), T.JsModuleLinked.ReExportCell(target.self_id, export_cell(binding)))
                elseif kind == "ExportAllAs" then
                    local specifier = S(ex.specifier)
                    local target = modules_by_id[specifier]
                    if not target then
                        error("JsModuleResolved.ModuleGraph:link could not resolve module specifier '" .. tostring(specifier) .. "'")
                    end
                    resolve_exports(specifier, active)
                    add_export(S(ex.exported_name), T.JsModuleLinked.NamespaceExport(target.self_id))
                elseif kind == "ExportAll" then
                    local specifier = S(ex.specifier)
                    local target = modules_by_id[specifier]
                    if not target then
                        error("JsModuleResolved.ModuleGraph:link could not resolve module specifier '" .. tostring(specifier) .. "'")
                    end
                    local _, target_ordered = resolve_exports(specifier, active)
                    for j = 1, #target_ordered do
                        local linked_export = target_ordered[j]
                        local export_name = S(linked_export.exported_name)
                        if export_name ~= "default" then
                            add_export(export_name, forward_binding(target, linked_export.binding))
                        end
                    end
                else
                    error("unknown JsModuleResolved export kind " .. tostring(kind))
                end
            end

            active[module_id] = nil
            export_tables[module_id] = exports_by_name
            export_lists[module_id] = ordered
            return exports_by_name, ordered
        end

        for module_id, _ in pairs(modules_by_id) do
            resolve_exports(module_id, {})
        end

        local linked_modules = L{}
        for i = 1, #graph.modules do
            local module = graph.modules[i]
            local module_id = module_id_string(module.self_id)
            local linked_imports = L{}

            for j = 1, #module.imports do
                local imp = module.imports[j]
                local kind = S(imp.kind)
                local specifier = S(imp.specifier)
                local target = modules_by_id[specifier]
                if not target then
                    error("JsModuleResolved.ModuleGraph:link could not resolve module specifier '" .. tostring(specifier) .. "'")
                end

                if kind == "ImportModule" then
                    linked_imports[#linked_imports + 1] = T.JsModuleLinked.LinkedImport(nil, target.self_id, "", T.JsModuleLinked.SideEffectImport, 0)
                elseif kind == "ImportDefault" then
                    local binding = export_tables[specifier]["default"]
                    if not binding then
                        error("module '" .. specifier .. "' has no default export")
                    end
                    linked_imports[#linked_imports + 1] = T.JsModuleLinked.LinkedImport(imp.local_slot, target.self_id, "default", T.JsModuleLinked.ValueImport, export_cell(binding))
                elseif kind == "ImportNamed" then
                    local import_name = S(imp.imported_name)
                    local binding = export_tables[specifier][import_name]
                    if not binding then
                        error("module '" .. specifier .. "' has no export named '" .. import_name .. "'")
                    end
                    local binding_kind = S(binding.kind)
                    if binding_kind == "NamespaceExport" then
                        linked_imports[#linked_imports + 1] = T.JsModuleLinked.LinkedImport(imp.local_slot, binding.from_module, "*", T.JsModuleLinked.NamespaceImport, 0)
                    else
                        linked_imports[#linked_imports + 1] = T.JsModuleLinked.LinkedImport(imp.local_slot, target.self_id, import_name, T.JsModuleLinked.ValueImport, export_cell(binding))
                    end
                elseif kind == "ImportNamespace" then
                    resolve_exports(specifier, {})
                    linked_imports[#linked_imports + 1] = T.JsModuleLinked.LinkedImport(imp.local_slot, target.self_id, "*", T.JsModuleLinked.NamespaceImport, 0)
                else
                    error("unknown JsModuleResolved import kind " .. tostring(kind))
                end
            end

            linked_modules[#linked_modules + 1] = T.JsModuleLinked.LinkedModule(
                module.self_id,
                linked_imports,
                export_lists[module_id],
                module.eval_body,
                module.scope
            )
        end

        return T.JsModuleLinked.ModuleGraph(linked_modules, graph.entry)
    end)
end
