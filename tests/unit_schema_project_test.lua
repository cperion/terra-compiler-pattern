#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local U = require("unit_core").new()
require("unit_schema").install(U)

local ROOT = os.tmpname():gsub("\\", "/")
os.remove(ROOT)
os.execute("mkdir -p " .. string.format("%q", ROOT))

local function write(path, text)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then os.execute("mkdir -p " .. string.format("%q", dir)) end
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function project_dir(name)
    return ROOT .. "/" .. name
end

local function test_load_project_and_paths_flat_default()
    local dir = project_dir("flat_default_proj")
    os.execute("mkdir -p " .. string.format("%q", dir .. "/schema"))

    write(dir .. "/schema/app.asdl", [[
module Demo {
  Expr = Add(number x) | Mul(number y)
  Node = (Expr expr) unique
}
]])

    write(dir .. "/pipeline.lua", "return { \"Demo\" }\n")
    write(dir .. "/unit_project.lua", [[
return {
  stubs = {
    ["Demo.Expr"] = "lower",
    ["Demo.Node"] = "lower",
  },
}
]])

    local P = U.load_project(dir)
    assert(P.source_kind == "project_dir")
    assert(P.layout == "flat")
    assert(#P.schema_paths == 1)
    assert(U.project_type_path(P, "Demo.Node"):match("demo_node%.lua$"))
    assert(U.project_type_test_path(P, "Demo.Node"):match("demo_node_test%.lua$"))
    assert(U.project_type_backend_path(P, "Demo.Node", "luajit"):match("demo_node_luajit%.lua$"))
    assert(U.project_type_backend_path(P, "Demo.Node", "terra"):match("demo_node_terra%.t$"))
    assert(U.project_type_backend_bench_path(P, "Demo.Node", "luajit"):match("demo_node_luajit_bench%.lua$"))
    assert(U.project_type_backend_profile_path(P, "Demo.Node", "terra"):match("demo_node_terra_profile%.t$"))

    write(U.project_type_backend_path(P, "Demo.Node", "luajit"), "return function(T, U, P) end\n")
    write(U.project_type_backend_bench_path(P, "Demo.Node", "luajit"), "return function(T, U, P) end\n")
    write(U.project_type_backend_path(P, "Demo.Node", "terra"), "return function(T, U, P) end\n")

    local I = U.inspect_from(dir)
    assert(#I.boundaries == 2)
    local path = U.project_type_path(P, "Demo.Node")
    local text, receiver = U.scaffold_type_artifact(P, I, "Demo.Node", "impl")
    assert(receiver == "Demo.Node")
    assert(text:match("function T%.Demo%.Node:lower%(%)"))
    assert(path:match("demo_node%.lua$"))
    assert(I.backend_inventory.totals.receiver_total == 2)
    assert(I.backend_inventory.totals.by_backend.luajit.impl == 1)
    assert(I.backend_inventory.totals.by_backend.luajit.bench == 1)
    assert(I.backend_inventory.totals.by_backend.terra.impl == 1)
    assert(I.backend_status():match("Backend artifacts:"))
end

local function test_project_deps_install_active_backend()
    local dep = project_dir("dep_proj")
    os.execute("mkdir -p " .. string.format("%q", dep .. "/schema"))

    write(dep .. "/schema/app.asdl", [[
module Demo {
  Node = () unique
}
]])
    write(dep .. "/pipeline.lua", "return { \"Demo\" }\n")
    write(dep .. "/boundaries/demo_node.lua", [[
return function(T)
  function T.Demo.Node:lower()
    return self
  end
end
]])
    write(dep .. "/boundaries/demo_node_luajit.lua", [[
return function(T)
  function T.Demo.Node:jit_only()
    return self
  end
end
]])

    local host = project_dir("host_proj")
    os.execute("mkdir -p " .. string.format("%q", host .. "/schema"))
    write(host .. "/schema/app.asdl", [[
module Host {
  Marker = () unique
}
]])
    write(host .. "/pipeline.lua", "return { \"Demo\", \"Host\" }\n")
    write(host .. "/unit_project.lua", "return { deps = { \"../dep_proj\" } }\n")

    local I = U.inspect_from(host)
    assert(#I.projects == 2)
    assert(I.find_boundary("Demo.Node:lower") ~= nil)
    assert(I.find_boundary("Demo.Node:jit_only") ~= nil)
    assert(U.project_type_backend_path(I.projects[1], "Demo.Node", "luajit"):match("demo_node_luajit%.lua$"))
    assert(I.backend_inventory.totals.by_backend.luajit.impl == 1)
end

local function test_scaffold_project_tree()
    local dir = project_dir("tree_proj")
    os.execute("mkdir -p " .. string.format("%q", dir .. "/schema"))

    write(dir .. "/schema/app.asdl", [[
module Demo {
  Expr = Add(number x) | Mul(number y)
  Node = (Expr expr) unique
}
]])

    write(dir .. "/unit_project.lua", [[
return {
  layout = "tree",
  stubs = {
    ["Demo.Expr"] = "lower",
    ["Demo.Node"] = "lower",
  },
}
]])

    local P = U.load_project(dir)
    assert(P.layout == "tree")
    assert(U.project_type_path(P, "Demo.Expr"):match("demo[/\\]expr%.lua$"))
    assert(U.project_type_bench_path(P, "Demo.Expr"):match("demo[/\\]expr_bench%.lua$"))

    local I = U.inspect_from(dir)
    local written = U.scaffold_project(P, I, { all_artifacts = true, force = true })
    assert(#written == 8)

    local impl_path = U.project_type_path(P, "Demo.Node")
    local test_path = U.project_type_test_path(P, "Demo.Node")
    local bench_path = U.project_type_bench_path(P, "Demo.Node")
    local profile_path = U.project_type_profile_path(P, "Demo.Node")

    assert(read(impl_path):match("function T%.Demo%.Node:lower%(%)"))
    assert(read(test_path):match("test_lower"))
    assert(read(bench_path):match("bench_lower"))
    assert(read(profile_path):match("profile_lower"))
end

test_load_project_and_paths_flat_default()
test_project_deps_install_active_backend()
test_scaffold_project_tree()

print("unit_schema_project_test.lua: ok")
