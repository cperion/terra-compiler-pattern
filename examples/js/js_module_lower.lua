local ffi = require("ffi")
local U = require("unit")
local asdl = require("asdl")
local L = asdl.List

local function S(v)
    if type(v) == "cdata" then return ffi.string(v) end
    return v
end

return function(T)
    local Surf = T.JsSurface
    local Mod = T.JsModuleSource
    local J = T.JsSource
    local next_gensym = 0

    local function gensym(prefix)
        next_gensym = next_gensym + 1
        return prefix .. tostring(next_gensym)
    end

    local function lower_stmt_via_source(stmt)
        local program = Surf.Program(L{ stmt }):lower()
        assert(#program.body == 1)
        return program.body[1]
    end

    local function lower_expr_via_source(expr)
        local program = Surf.Program(L{ Surf.Return(expr) }):lower()
        assert(#program.body == 1)
        local ret = program.body[1]
        return ret.value
    end

    local function declared_name(stmt)
        local kind = S(stmt.kind)
        if kind == "FuncDecl" or kind == "ClassDecl" then
            return S(stmt.name)
        elseif kind == "VarDecl" then
            if #stmt.decls ~= 1 then
                error("native module lowering currently requires single-declarator export declarations")
            end
            return S(stmt.decls[1].name)
        end
        error("native module lowering does not support export declaration kind " .. tostring(kind))
    end

    Surf.Program.lower_module = U.transition("JsSurface.Program:lower_module", function(program)
        local imports = L{}
        local exports = L{}
        local eval_body = L{}

        for i = 1, #program.body do
            local stmt = program.body[i]
            local kind = S(stmt.kind)

            if kind == "Import" then
                local specifier = S(stmt.from)
                local has_bindings = stmt.default_name ~= nil or stmt.namespace_name ~= nil or #stmt.named > 0
                if not has_bindings then
                    imports[#imports + 1] = Mod.ImportModule(specifier)
                else
                    if stmt.default_name then
                        imports[#imports + 1] = Mod.ImportDefault(S(stmt.default_name), specifier)
                    end
                    if stmt.namespace_name then
                        imports[#imports + 1] = Mod.ImportNamespace(S(stmt.namespace_name), specifier)
                    end
                    for j = 1, #stmt.named do
                        local b = stmt.named[j]
                        imports[#imports + 1] = Mod.ImportNamed(S(b.imported_name), S(b.local_name), specifier)
                    end
                end

            elseif kind == "ExportNamed" then
                if stmt.from then
                    local specifier = S(stmt.from)
                    for j = 1, #stmt.bindings do
                        local b = stmt.bindings[j]
                        exports[#exports + 1] = Mod.ExportFrom(S(b.local_name), S(b.exported_name), specifier)
                    end
                else
                    for j = 1, #stmt.bindings do
                        local b = stmt.bindings[j]
                        exports[#exports + 1] = Mod.ExportLocal(S(b.local_name), S(b.exported_name))
                    end
                end

            elseif kind == "ExportAll" then
                if stmt.alias then
                    exports[#exports + 1] = Mod.ExportAllAs(S(stmt.alias), S(stmt.from))
                else
                    exports[#exports + 1] = Mod.ExportAll(S(stmt.from))
                end

            elseif kind == "ExportDefaultExpr" then
                local temp_name = gensym("__js_module_default_")
                eval_body[#eval_body + 1] = J.VarDecl(T.JsCore.Const, L{
                    J.Declarator(temp_name, lower_expr_via_source(stmt.expr))
                })
                exports[#exports + 1] = Mod.ExportLocal(temp_name, "default")

            elseif kind == "ExportDefaultDecl" then
                local decl = lower_stmt_via_source(stmt.decl)
                local local_name = declared_name(stmt.decl)
                eval_body[#eval_body + 1] = decl
                exports[#exports + 1] = Mod.ExportDefaultDecl(decl, local_name)

            elseif kind == "ExportDecl" then
                local decl = lower_stmt_via_source(stmt.decl)
                local local_name = declared_name(stmt.decl)
                eval_body[#eval_body + 1] = decl
                exports[#exports + 1] = Mod.ExportLocal(local_name, local_name)

            else
                eval_body[#eval_body + 1] = lower_stmt_via_source(stmt)
            end
        end

        return Mod.Module(nil, imports, exports, eval_body)
    end)

    Mod.ModuleGraph.link = U.transition("JsModuleSource.ModuleGraph:link", function(graph)
        error("Native module graph linking is not implemented yet. Available today: JsSurface.Program:lower_module() for authored module lowering, while execution still uses the CommonJS-lowered path.")
    end)
end
