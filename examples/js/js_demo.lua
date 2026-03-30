#!/usr/bin/env luajit

-- js_demo.lua
--
-- End-to-end demonstration: JS source text -> parse -> resolve -> compile -> run
--
-- Run from the repository root:
--   luajit examples/js/js_demo.lua

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local spec = require("examples.js.js_schema")
local asdl = require("asdl")
local T = spec.ctx

-- ═══════════════════════════════════════════════════════════════
-- Helper: run JS source and return result
-- ═══════════════════════════════════════════════════════════════

local function run_js(source, extra_globals)
    local ast = T.JsSource.parse(source)
    local resolved = ast:resolve()
    local compiled = resolved:compile(extra_globals)
    return compiled.run(), compiled.globals
end

local function test(name, source, expected)
    local ok, result = pcall(function()
        local val = run_js(source)
        return val
    end)
    if not ok then
        print(string.format("FAIL  %s\n      error: %s", name, tostring(result)))
        return
    end
    if result == expected then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      expected: %s  got: %s",
            name, tostring(expected), tostring(result)))
    end
end

local function test_output(name, source, expected_output)
    local output = {}
    local ok, err = pcall(function()
        run_js(source, {
            console = {
                log = function(...)
                    local parts = {}
                    for i = 1, select("#", ...) do
                        parts[#parts+1] = tostring(select(i, ...))
                    end
                    output[#output+1] = table.concat(parts, "\t")
                end,
            },
        })
    end)
    local got = table.concat(output, "\n")
    if not ok then
        print(string.format("FAIL  %s\n      error: %s", name, tostring(err)))
        return
    end
    if got == expected_output then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      expected: %q\n      got:      %q",
            name, expected_output, got))
    end
end

local function make_require(modules)
    return function(name)
        local v = modules and modules[name]
        if v ~= nil then return v end
        error("Cannot find module '" .. tostring(name) .. "'")
    end
end

local function run_module(source, modules, extra_globals)
    local module_obj = { exports = {} }
    local globals = {
        require = make_require(modules),
        module = module_obj,
        exports = module_obj.exports,
    }
    if extra_globals then
        for k, v in pairs(extra_globals) do globals[k] = v end
    end
    run_js(source, globals)
    return module_obj.exports, globals
end

local function test_with_modules(name, source, modules, expected)
    local ok, result = pcall(function()
        local module_obj = { exports = {} }
        local val = run_js(source, {
            require = make_require(modules),
            module = module_obj,
            exports = module_obj.exports,
        })
        return val
    end)
    if not ok then
        print(string.format("FAIL  %s\n      error: %s", name, tostring(result)))
        return
    end
    if result == expected then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      expected: %s  got: %s",
            name, tostring(expected), tostring(result)))
    end
end

local function test_module(name, source, modules, check)
    local ok, err = pcall(function()
        local exports = run_module(source, modules)
        check(exports)
    end)
    if ok then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      error: %s", name, tostring(err)))
    end
end

local function test_error(name, source, needle)
    local ok, err = pcall(function()
        return run_js(source)
    end)
    if ok then
        print(string.format("FAIL  %s\n      expected runtime error", name))
        return
    end
    local msg = tostring(err)
    if not needle or msg:find(needle, 1, true) then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      error: %s", name, msg))
    end
end

print("═══════════════════════════════════════════════════════════")
print("JS compiler demo — ASDL-first, leaf-first")
print("═══════════════════════════════════════════════════════════")
print()

local function test_lex(name, source, check)
    local ok, err = pcall(function()
        local stream = T.JsLex.lex(source)
        check(stream)
    end)
    if ok then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      error: %s", name, tostring(err)))
    end
end

-- ── Lexer ──
test_lex("lexer keywords + punct", "const x = 1 + 2;", function(stream)
    assert(#stream.tokens >= 8)
    assert(stream.tokens[1].kind == "Keyword" and stream.tokens[1].text == "const")
    assert(stream.tokens[2].kind == "Identifier" and stream.tokens[2].text == "x")
end)

test_lex("lexer preserves comments", "// hi\nlet x = `a ${b}`;", function(stream)
    assert(stream.tokens[1].kind == "Comment")
    local saw_template = false
    for i = 1, #stream.tokens do
        if stream.tokens[i].kind == "Template" then saw_template = true end
    end
    assert(saw_template)
end)

local function test_surface(name, source)
    local ok, err = pcall(function()
        local surface = T.JsSurface.parse(source)
        assert(surface and #surface.body >= 1)
        local lowered = surface:lower()
        assert(lowered and #lowered.body >= 1)
    end)
    if ok then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      error: %s", name, tostring(err)))
    end
end

test_surface("surface parse + lower", "let x = 1; return x + 2;")
test_surface("surface label lower", "outer: while (x < 3) { break outer; }")

local function test_surface_only(name, source)
    local ok, err = pcall(function()
        local surface = T.JsSurface.parse(source)
        assert(surface and #surface.body >= 1)
    end)
    if ok then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      error: %s", name, tostring(err)))
    end
end

local function test_lower_error(name, source, needle)
    local ok, err = pcall(function()
        local surface = T.JsSurface.parse(source)
        return surface:lower()
    end)
    if ok then
        print(string.format("FAIL  %s\n      expected lowering error", name))
        return
    end
    local msg = tostring(err)
    if not needle or msg:find(needle, 1, true) then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      error: %s", name, msg))
    end
end

local function test_native_module_phase(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print(string.format("OK    %s", name))
    else
        print(string.format("FAIL  %s\n      error: %s", name, tostring(err)))
    end
end

test_surface("surface modules", [[
    import http, { createServer as create } from "http";
    export { create as createServer };
    export * as netns from "net";
]])

test_lex("native module lowering scaffold", "export default function f() { return 1; }", function()
    local mod = T.JsSurface.parse([[
        import foo, { bar as baz } from "pkg";
        export default function f() { return baz(); }
        export { f as named };
    ]]):lower_module()
    assert(#mod.imports == 2)
    assert(#mod.exports == 2)
    assert(#mod.eval_body == 1)
end)

test_lex("native module resolve locals scaffold", "export default x;", function()
    local mod = T.JsSurface.parse([[
        import foo, { bar as baz } from "pkg";
        let x = baz();
        export { x };
        export default x;
    ]]):lower_module():resolve_locals()
    assert(#mod.imports == 2)
    assert(#mod.exports == 2)
    assert(#mod.eval_body == 2)
    assert(mod.imports[1].kind == "ImportDefault")
    assert(mod.imports[2].kind == "ImportNamed")
    assert(mod.exports[1].kind == "ExportLocal")
    assert(mod.exports[2].kind == "ExportLocal")
    assert(mod.exports[1].local_slot.kind == "LocalSlot")
    assert(mod.exports[2].local_slot.kind == "LocalSlot")
    assert(mod.exports[2].exported_name == "default")
end)

test_native_module_phase("native module link scaffold", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end

    local dep = with_id([[ const answer = 42; export { answer }; export default answer; ]], "dep")
    local main = with_id([[ import x, { answer as a } from "dep"; let y = x + a; export { y }; ]], "main")
    local graph = T.JsModuleResolved.ModuleGraph(asdl.List{ dep, main }, T.JsModuleSource.ModuleId("main"))
    local linked = graph:link()
    assert(#linked.modules == 2)
    local linked_main = linked.modules[2]
    assert(#linked_main.imports == 2)
    assert(linked_main.imports[1].kind.kind == "ValueImport")
    assert(linked_main.imports[1].import_name == "default")
    assert(linked_main.imports[2].import_name == "answer")
    assert(linked_main.imports[1].local_slot.kind == "LocalSlot")
    assert(linked_main.exports[1].binding.kind == "LocalSlotExport")
    assert(linked.modules[1].exports[2].binding.kind == "LocalSlotExport")
end)

test_native_module_phase("native module link export from", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local dep = with_id([[ const answer = 42; export { answer }; export default answer; ]], "dep")
    local mid = with_id([[ export { answer as value, default as def } from "dep"; ]], "mid")
    local main = with_id([[ import { value, def as d } from "mid"; export { value }; export default d; ]], "main")
    local graph = T.JsModuleResolved.ModuleGraph(asdl.List{ dep, mid, main }, T.JsModuleSource.ModuleId("main"))
    local linked = graph:link()
    assert(#linked.modules == 3)
    local linked_mid = linked.modules[2]
    assert(linked_mid.exports[1].binding.kind == "ReExportCell")
    assert(linked_mid.exports[1].exported_name == "value")
    assert(linked_mid.exports[2].binding.kind == "ReExportCell")
    assert(linked_mid.exports[2].exported_name == "def")
    local linked_main = linked.modules[3]
    assert(linked_main.imports[1].import_name == "value")
    assert(linked_main.imports[2].import_name == "def")
end)

test_native_module_phase("native module link namespace forms", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local dep = with_id([[ const answer = 42; export { answer }; export default answer; ]], "dep")
    local mid = with_id([[ export * as ns from "dep"; ]], "mid")
    local main = with_id([[ import * as depns from "dep"; import { ns as midns } from "mid"; export { depns, midns }; ]], "main")
    local graph = T.JsModuleResolved.ModuleGraph(asdl.List{ dep, mid, main }, T.JsModuleSource.ModuleId("main"))
    local linked = graph:link()
    local linked_mid = linked.modules[2]
    assert(linked_mid.exports[1].binding.kind == "NamespaceExport")
    local linked_main = linked.modules[3]
    assert(linked_main.imports[1].kind.kind == "NamespaceImport")
    assert(linked_main.imports[1].import_name == "*")
    assert(linked_main.imports[2].kind.kind == "NamespaceImport")
    assert(linked_main.imports[2].import_name == "*")
    assert(linked_main.imports[2].from_module.value == "dep")
end)

test_native_module_phase("native module link export star", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local dep = with_id([[ const answer = 42; export { answer }; export default answer; ]], "dep")
    local mid = with_id([[ export * from "dep"; const local = 1; export { local }; ]], "mid")
    local main = with_id([[ import { answer } from "mid"; export default answer; ]], "main")
    local graph = T.JsModuleResolved.ModuleGraph(asdl.List{ dep, mid, main }, T.JsModuleSource.ModuleId("main"))
    local linked = graph:link()
    local linked_mid = linked.modules[2]
    assert(#linked_mid.exports == 2)
    assert(linked_mid.exports[1].exported_name == "answer")
    assert(linked_mid.exports[1].binding.kind == "ReExportCell")
    assert(linked_mid.exports[2].exported_name == "local")
    local linked_main = linked.modules[3]
    assert(linked_main.imports[1].import_name == "answer")
end)

test_native_module_phase("native module link rejects export star conflicts", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local a = with_id([[ const x = 1; export { x as shared }; ]], "a")
    local b = with_id([[ const y = 2; export { y as shared }; ]], "b")
    local main = with_id([[ export * from "a"; export * from "b"; ]], "main")
    local graph = T.JsModuleResolved.ModuleGraph(asdl.List{ a, b, main }, T.JsModuleSource.ModuleId("main"))
    local ok, err = pcall(function() graph:link() end)
    assert(not ok)
    assert(tostring(err):find("duplicate export name 'shared'", 1, true))
end)

test_native_module_phase("native module compile instantiate scaffold", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local dep = with_id([[ const answer = 42; export { answer }; export default answer; ]], "dep")
    local mid = with_id([[ export * as ns from "dep"; export * from "dep"; ]], "mid")
    local main = with_id([[ import * as depns from "dep"; import { ns as midns, answer } from "mid"; export { depns, midns, answer }; ]], "main")
    local linked = T.JsModuleResolved.ModuleGraph(asdl.List{ dep, mid, main }, T.JsModuleSource.ModuleId("main")):link()
    local compiled = linked:compile_modules()
    assert(compiled.entry == "main")
    assert(#compiled.modules == 3)
    assert(compiled.modules_by_id.dep.export_cell_count == 2)
    assert(compiled.modules_by_id.mid.export_cell_count == 0)
    local runtime = compiled:instantiate()
    assert(runtime.module_by_id.dep.export_cells[1] ~= nil)
    assert(runtime.module_by_id.dep.export_cells[2] ~= nil)
    local ok, err = pcall(function() return runtime:namespace_of("dep").answer end)
    assert(not ok)
    assert(tostring(err):find("before initialization", 1, true))
    assert(type(runtime:namespace_of("mid").ns) == "table")
    local inst = runtime:execute()
    assert(inst.id == "main")
    assert(runtime:namespace_of("dep").answer == 42)
end)


test_native_module_phase("native module execute default expr ordering", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local dep = with_id([[
        let x = 1;
        export default x + 1;
        x = 5;
        export { x };
    ]], "dep")
    local main = with_id([[
        import d, { x } from "dep";
        export { d, x };
    ]], "main")
    local runtime = T.JsModuleResolved.ModuleGraph(asdl.List{ dep, main }, T.JsModuleSource.ModuleId("main"))
        :link()
        :compile_modules()
        :instantiate()
    runtime:execute()
    assert(runtime:namespace_of("dep").default == 2)
    assert(runtime:namespace_of("dep").x == 5)
    assert(runtime:namespace_of("main").d == 2)
    assert(runtime:namespace_of("main").x == 5)
end)


test_native_module_phase("native module function hoist within module", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local dep = with_id([[
        let seen = f();
        function f() { return 7; }
        export { seen, f };
    ]], "dep")
    local runtime = T.JsModuleResolved.ModuleGraph(asdl.List{ dep }, T.JsModuleSource.ModuleId("dep"))
        :link()
        :compile_modules()
        :instantiate()
    runtime:execute()
    assert(runtime:namespace_of("dep").seen == 7)
    assert(runtime:namespace_of("dep").f() == 7)
end)


test_native_module_phase("native module local lexical tdz", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local dep = with_id([[
        let y = x;
        let x = 1;
        export { y, x };
    ]], "dep")
    local runtime = T.JsModuleResolved.ModuleGraph(asdl.List{ dep }, T.JsModuleSource.ModuleId("dep"))
        :link()
        :compile_modules()
        :instantiate()
    local ok, err = pcall(function() runtime:execute() end)
    assert(not ok)
    assert(tostring(err):find("Cannot access local module binding 'x' before initialization", 1, true))
end)


test_native_module_phase("native module execute live imports", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local dep = with_id([[
        let x = 1;
        function bump() { x = x + 1; return x; }
        export { x, bump };
    ]], "dep")
    local main = with_id([[
        import { x, bump } from "dep";
        let before = x;
        let after = bump();
        let seen = x;
        export { before, after, seen };
    ]], "main")
    local runtime = T.JsModuleResolved.ModuleGraph(asdl.List{ dep, main }, T.JsModuleSource.ModuleId("main"))
        :link()
        :compile_modules()
        :instantiate()
    runtime:execute()
    assert(runtime:namespace_of("dep").x == 2)
    assert(runtime:namespace_of("main").before == 1)
    assert(runtime:namespace_of("main").after == 2)
    assert(runtime:namespace_of("main").seen == 2)
end)


test_native_module_phase("native module execute cycle subset", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local a = with_id([[
        import { getB } from "b";
        let a = 1;
        function getA() { return a; }
        function readB() { return getB(); }
        export { getA, readB };
    ]], "a")
    local b = with_id([[
        import { getA } from "a";
        let b = 2;
        function getB() { return b + getA(); }
        export { getB };
    ]], "b")
    local main = with_id([[
        import { readB } from "a";
        export { readB };
    ]], "main")
    local runtime = T.JsModuleResolved.ModuleGraph(asdl.List{ a, b, main }, T.JsModuleSource.ModuleId("main"))
        :link()
        :compile_modules()
        :instantiate()
    runtime:execute()
    assert(runtime:namespace_of("main").readB() == 3)
end)


test_native_module_phase("native module cycle function hoist", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local a = with_id([[
        import { f } from "b";
        let seen = f();
        export { seen };
    ]], "a")
    local b = with_id([[
        import { seen } from "a";
        export function f() { return 11; }
        export { seen };
    ]], "b")
    local main = with_id([[
        import { seen } from "a";
        export { seen };
    ]], "main")
    local runtime = T.JsModuleResolved.ModuleGraph(asdl.List{ a, b, main }, T.JsModuleSource.ModuleId("main"))
        :link()
        :compile_modules()
        :instantiate()
    runtime:execute()
    assert(runtime:namespace_of("main").seen == 11)
end)


test_native_module_phase("native module cycle lexical tdz through hoisted function", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local a = with_id([[
        import { f } from "b";
        let seen = f();
        export { seen };
    ]], "a")
    local b = with_id([[
        import { seen } from "a";
        export function f() { return x; }
        let x = 1;
        export { x, seen };
    ]], "b")
    local main = with_id([[
        import { seen } from "a";
        export { seen };
    ]], "main")
    local runtime = T.JsModuleResolved.ModuleGraph(asdl.List{ a, b, main }, T.JsModuleSource.ModuleId("main"))
        :link()
        :compile_modules()
        :instantiate()
    local ok, err = pcall(function() runtime:execute() end)
    assert(not ok)
    assert(tostring(err):find("Cannot access local module binding 'x' before initialization", 1, true))
end)


test_native_module_phase("native module cycle tdz error", function()
    local function with_id(source, id)
        local m = T.JsSurface.parse(source):lower_module():resolve_locals()
        return T.JsModuleResolved.Module(T.JsModuleSource.ModuleId(id), m.imports, m.exports, m.eval_body, m.scope)
    end
    local a = with_id([[
        import { x } from "b";
        let y = x;
        export { y };
    ]], "a")
    local b = with_id([[
        import { y } from "a";
        let x = 1;
        export { x, y };
    ]], "b")
    local main = with_id([[
        import { y } from "a";
        export { y };
    ]], "main")
    local runtime = T.JsModuleResolved.ModuleGraph(asdl.List{ a, b, main }, T.JsModuleSource.ModuleId("main"))
        :link()
        :compile_modules()
        :instantiate()
    local ok, err = pcall(function() runtime:execute() end)
    assert(not ok)
    assert(tostring(err):find("Cannot access module binding 'x' from module 'b' before initialization", 1, true))
end)

test_surface_only("surface class + richer stmts", [[
    class Foo extends Bar {
        static count = 0;
        #secret = 1;
        get value() { return this.x; }
        set value(v) { this.x = v; }
        run(a, b) { return a + b; }
    }
    outer: do { switch (x) { case 1: break; default: continue; } } while (flag);
]])

test_lower_error("with intentionally unsupported", [[
    with (obj) { return x; }
]], "intentionally unsupported")


-- ── Arithmetic ──
test("numeric literal", "return 42;", 42)
test("addition", "return 1 + 2;", 3)
test("operator precedence", "return 2 + 3 * 4;", 14)
test("parentheses", "return (2 + 3) * 4;", 20)
test("modulo", "return 10 % 3;", 1)
test("exponent", "return 2 ** 10;", 1024)
test("unary minus", "return -5;", -5)
test("unary not", "return !false;", true)

-- ── Variables ──
test("let declaration", "let x = 10; return x;", 10)
test("var declaration", "var y = 20; return y;", 20)
test("multiple decls", "let a = 1, b = 2; return a + b;", 3)
test("assignment", "let x = 1; x = 5; return x;", 5)
test("compound assign", "let x = 10; x += 5; return x;", 15)
test_lower_error("const declaration requires initializer", "const x;", "const declaration requires initializer")
test_error("const assignment error", "const x = 1; x = 2;", "assignment to const binding")
test_error("const update error", "const x = 1; x++;", "assignment to const binding")
test_error("const compound assign error", "const x = 1; x += 2;", "assignment to const binding")

-- ── Strings ──
test("string literal", 'return "hello";', "hello")
test("string concat +", 'return "hello" + " " + "world";', "hello world")
test("string + number", 'return "val:" + 42;', "val:42")

-- ── Booleans ──
test("true", "return true;", true)
test("false", "return false;", false)
test("strict equal", "return 1 === 1;", true)
test("strict not equal", "return 1 !== 2;", true)

-- ── Control flow ──
test("if true", "if (true) { return 1; } return 0;", 1)
test("if false", "if (false) { return 1; } return 0;", 0)
test("if/else", "if (false) { return 1; } else { return 2; }", 2)
test("block scope", [[
    let x = 1;
    {
        let x = 2;
    }
    return x;
]], 1)
test_error("block lexical tdz", [[
    {
        let y = x;
        let x = 1;
    }
]], "before initialization")
test("while loop", [[
    let i = 0;
    let sum = 0;
    while (i < 5) {
        sum += i;
        i++;
    }
    return sum;
]], 10)

test("do while loop", [[
    let i = 0;
    let sum = 0;
    do {
        sum += i;
        i++;
    } while (i < 5);
    return sum;
]], 10)

test("for loop", [[
    let sum = 0;
    for (let i = 0; i < 5; i++) {
        sum += i;
    }
    return sum;
]], 10)
test("for let per-iteration closures", [[
    let f0 = null;
    let f1 = null;
    let f2 = null;
    for (let i = 0; i < 3; i++) {
        if (i === 0) f0 = function() { return i; };
        else if (i === 1) f1 = function() { return i; };
        else f2 = function() { return i; };
    }
    return f0() + f1() + f2();
]], 3)
test("for var shared closure", [[
    let f0 = null;
    let f1 = null;
    let f2 = null;
    for (var i = 0; i < 3; i++) {
        if (i === 0) f0 = function() { return i; };
        else if (i === 1) f1 = function() { return i; };
        else f2 = function() { return i; };
    }
    return f0() + f1() + f2();
]], 9)
test_error("for let header tdz", [[
    for (let i = i; false; ) {
    }
]], "before initialization")

test("for in", [[
    let obj = { a: 1, b: 2 };
    let sum = 0;
    for (let k in obj) {
        sum += obj[k];
    }
    return sum;
]], 3)
test("for in let per-iteration closures", [[
    let f0 = null;
    let f1 = null;
    let f2 = null;
    let n = 0;
    for (let k in { 0: true, 1: true, 2: true }) {
        if (n === 0) f0 = function() { return +k; };
        else if (n === 1) f1 = function() { return +k; };
        else f2 = function() { return +k; };
        n++;
    }
    return f0() + f1() + f2();
]], 3)

test("for of", [[
    let sum = 0;
    for (let x of [1, 2, 3]) {
        sum += x;
    }
    return sum;
]], 6)
test("for of const header", [[
    let sum = 0;
    for (const x of [1, 2, 3]) {
        sum += x;
    }
    return sum;
]], 6)
test("for of let per-iteration closures", [[
    let f0 = null;
    let f1 = null;
    let f2 = null;
    let n = 0;
    for (let x of [0, 1, 2]) {
        if (n === 0) f0 = function() { return x; };
        else if (n === 1) f1 = function() { return x; };
        else f2 = function() { return x; };
        n++;
    }
    return f0() + f1() + f2();
]], 3)
test("for of var shared closure", [[
    let f0 = null;
    let f1 = null;
    let f2 = null;
    let n = 0;
    for (var x of [0, 1, 2]) {
        if (n === 0) f0 = function() { return x; };
        else if (n === 1) f1 = function() { return x; };
        else f2 = function() { return x; };
        n++;
    }
    return f0() + f1() + f2();
]], 6)

test("labeled break block", [[
    let x = 0;
    outer: {
        x = 1;
        break outer;
        x = 2;
    }
    return x;
]], 1)

test("labeled continue outer loop", [[
    let out = 0;
    outer: for (let i = 0; i < 3; i++) {
        for (let j = 0; j < 3; j++) {
            if (j === 1) continue outer;
            out += 1;
        }
    }
    return out;
]], 3)

test("multi-label continue", [[
    let n = 0;
    a: b: while (n < 5) {
        n++;
        if (n < 5) continue a;
    }
    return n;
]], 5)

test("labeled break switch", [[
    let x = 0;
    outer: switch (1) {
        case 1:
            x = 7;
            break outer;
        default:
            x = 9;
    }
    return x;
]], 7)

test("break", [[
    let i = 0;
    while (true) {
        if (i >= 3) { break; }
        i++;
    }
    return i;
]], 3)

test("switch", [[
    let x = 2;
    switch (x) {
        case 1: return 10;
        case 2: return 20;
        default: return 30;
    }
]], 20)

test("switch fallthrough", [[
    let x = 1;
    let y = 0;
    switch (x) {
        case 1: y = 10;
        case 2: y = y + 5; break;
        default: y = 99;
    }
    return y;
]], 15)
test("switch lexical scope no leak", [[
    let x = 10;
    switch (0) {
        case 0:
            let x = 1;
            break;
    }
    return x;
]], 10)
test("switch lexical fallthrough shared scope", [[
    switch (0) {
        case 0:
            let x = 1;
        case 1:
            x = x + 1;
            return x;
    }
]], 2)
test_error("switch lexical tdz across cases", [[
    switch (1) {
        case 0:
            let x = 1;
            break;
        case 1:
            return x;
    }
]], "before initialization")

-- ── Functions ──
test("function decl", [[
    function add(a, b) { return a + b; }
    return add(3, 4);
]], 7)
test("function decl hoist", [[
    return add(3, 4);
    function add(a, b) { return a + b; }
]], 7)
test_error("function lexical tdz", [[
    function f() {
        let y = x;
        let x = 1;
        return y;
    }
    return f();
]], "before initialization")

test("arrow expr", [[
    let double = (x) => x * 2;
    return double(5);
]], 10)

test("arrow block", [[
    let fact = (n) => {
        if (n <= 1) { return 1; }
        return n * fact(n - 1);
    };
    return fact(5);
]], 120)

test("closure", [[
    function make() {
        let x = 10;
        return () => x;
    }
    return make()();
]], 10)
test("method call this binding", [[
    let obj = {
        x: 5,
        get: function() { return this.x; }
    };
    return obj.get();
]], 5)
test("array push method call", [[
    let xs = [];
    xs.push(1);
    xs.push(2);
    return xs.length;
]], 2)

test("named function expr self", [[
    let fact = function inner(n) {
        if (n <= 1) { return 1; }
        return n * inner(n - 1);
    };
    return fact(5);
]], 120)

-- ── Objects ──
test("object literal", [[
    let obj = { a: 1, b: 2 };
    return obj.a + obj.b;
]], 3)

test("computed member", [[
    let obj = { x: 42 };
    let key = "x";
    return obj[key];
]], 42)

-- ── Arrays ──
test("array literal", [[
    let arr = [10, 20, 30];
    return arr.length;
]], 3)

-- ── Ternary ──
test("ternary true", "return true ? 1 : 2;", 1)
test("ternary false", "return false ? 1 : 2;", 2)

-- ── Logical operators ──
test("logical and", "return 1 && 2;", 2)
test("logical or", "return 0 || 42;", 42)
test("nullish coalescing", "return null ?? 5;", 5)

-- ── typeof ──
test("typeof number", 'return typeof 42;', "number")
test("typeof string", 'return typeof "hi";', "string")
test("typeof undefined", 'return typeof undefined;', "undefined")

-- ── Console output ──
test_output("console.log", 'console.log("hello", "world");', "hello\tworld")
test_output("console.log number", 'console.log(1 + 2);', "3")

-- ── try/catch ──
test("try/catch", [[
    let result = 0;
    try {
        throw 42;
    } catch (e) {
        result = e;
    }
    return result;
]], 42)

-- ── Fibonacci ──
test("fibonacci", [[
    function fib(n) {
        if (n <= 1) { return n; }
        return fib(n - 1) + fib(n - 2);
    }
    return fib(10);
]], 55)

-- ── Higher-order ──
test_output("higher order", [[
    function apply(fn, x) { return fn(x); }
    let double = (x) => x * 2;
    console.log(apply(double, 21));
]], "42")

-- ── Template literals ──
test("template literal", [[
    let name = "world";
    return `hello ${name}`;
]], "hello world")

-- ── Classes ──
test("class constructor + method", [[
    class Counter {
        constructor(x) { this.x = x; }
        inc() { this.x = this.x + 1; return this.x; }
    }
    let c = new Counter(5);
    return c.inc();
]], 6)
test_error("class declaration tdz", [[
    return C;
    class C {}
]], "before initialization")
test("class declaration self binding", [[
    class C {
        static self = C;
        static make() { return C; }
    }
    return (C.self === C) && (C.make() === C);
]], true)
test("named class expr self binding", [[
    let Outer = class Inner {
        static make() { return Inner; }
    };
    return Outer.make() === Outer;
]], true)

test("class getter + setter", [[
    class Box {
        constructor() { this._x = 1; }
        get value() { return this._x; }
        set value(v) { this._x = v; }
    }
    let b = new Box();
    b.value = 7;
    return b.value;
]], 7)

test("class static field", [[
    class Counter {
        static count = 3;
    }
    return Counter.count;
]], 3)

test("class inheritance instanceof", [[
    class A {
        constructor(v) { this.v = v; }
    }
    class B extends A {
        inc() { this.v = this.v + 1; return this.v; }
    }
    let b = new B(10);
    return (b instanceof B) && (b instanceof A) && (b.inc() === 11);
]], true)

-- ── Modules lowered to CommonJS globals ──
test_with_modules("module imports", [[
    import http, { createServer as create } from "http";
    import * as netns from "net";
    import answer from "esmish";
    return http.kind + ":" + create() + ":" + netns.listen() + ":" + answer();
]], {
    http = { kind = "http", createServer = function() return "srv" end },
    net = { listen = function() return "net" end },
    esmish = { default = function() return "ok" end },
}, "http:srv:net:ok")

test_with_modules("module default import fallback cjs object", [[
    import thing from "plain";
    return thing.value;
]], {
    plain = { value = 9 },
}, 9)

test_module("module exports named + default expr", [[
    let x = 7;
    function add(a, b) { return a + b; }
    export { x as value, add };
    export default x + 1;
]], nil, function(exports)
    assert(exports.value == 7)
    assert(exports.add(2, 3) == 5)
    assert(exports.default == 8)
end)

test_module("module export from + export all + default decl", [[
    export { createServer as create } from "http";
    export * as netns from "net";
    export * from "utilmod";
    export default function (x) { return x + 1; }
]], {
    http = { createServer = function() return "srv" end },
    net = { listen = function() return "net" end },
    utilmod = { answer = 42, default = "skip-me" },
}, function(exports)
    assert(exports.create() == "srv")
    assert(exports.netns.listen() == "net")
    assert(exports.answer == 42)
    assert(exports.default(4) == 5)
end)

test_module("module export star skips default", [[
    export * from "utilmod";
]], {
    utilmod = { answer = 42, default = "skip-me" },
}, function(exports)
    assert(exports.answer == 42)
    assert(exports.default == nil)
end)

print()
print("done.")
