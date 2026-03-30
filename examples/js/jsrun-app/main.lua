-- jsrun main.lua — luvi app entry point
--
-- This bootstraps the luvit environment, then runs a JS file or expression.
-- The full luvit stack (libuv, http, fs, net, timers, streams) is available
-- to the JS code through the Node compatibility bridge.
--
-- Build:  cd examples/js/jsrun-app && lit install && luvi . -o jsrun
-- Run:    ./jsrun server.js
--         ./jsrun -e "console.log('hello')"

-- Find repo root (for development; in production, files are bundled)
local function find_repo_root()
    local info = debug.getinfo(1, "S")
    local src = info.source or ""
    if src:sub(1,1) == "@" then src = src:sub(2) end
    -- Try to find the repo root from the script path
    local dir = src:match("(.+)/examples/js/jsrun%-app/main%.lua$")
    if dir then return dir end
    -- Try from bundle
    dir = src:match("(.+)/examples/js/jsrun%-app$")
    if dir then return dir end
    -- Fallback: check if we're in the repo
    local uv = require('uv')
    local cwd = uv.cwd()
    if uv.fs_stat(cwd .. "/unit.lua") then return cwd end
    if uv.fs_stat(cwd .. "/../unit.lua") then return cwd .. "/.." end
    return cwd
end

require('luvit')(function(...)
    local repo_root = find_repo_root()
    package.path = table.concat({
        repo_root .. "/?.lua",
        repo_root .. "/?/init.lua",
        package.path,
    }, ";")

    local js_node_proto = require('examples.js.js_node')
    local jsnode = type(js_node_proto.init) == "function"
        and js_node_proto.init(require) or js_node_proto

    local pargs = _G.process.argv or {}

    -- Find the first non-flag argument
    local script = nil
    local eval_mode = false
    local eval_source = nil

    for i = 1, #pargs do
        local a = pargs[i]
        if a == "-e" then
            eval_mode = true
            eval_source = pargs[i + 1]
            break
        elseif a:sub(1,1) ~= "-" then
            script = a
            break
        end
    end

    if eval_mode then
        if not eval_source then
            io.stderr:write("jsrun -e: missing expression\n")
            _G.process.exit(1)
        end
        local ok, err = pcall(jsnode.run_string, eval_source)
        if not ok then
            io.stderr:write("Error: " .. tostring(err) .. "\n")
            _G.process.exit(1)
        end
    elseif script then
        local ok, err = pcall(jsnode.run_file, script)
        if not ok then
            io.stderr:write("Error: " .. tostring(err) .. "\n")
            _G.process.exit(1)
        end
    else
        print("jsrun v0.1.0 — tiny Node.js-compatible JS runtime")
        print("")
        print("usage:")
        print("  jsrun <script.js>")
        print("  jsrun -e \"console.log('hello')\"")
        print("")
        print("powered by: LuaJIT + libuv (luvit) + js.lua compiler")
        print("binary size: ~5MB  |  startup: ~3ms  |  memory: ~5MB")
        _G.process.exit(0)
    end
end, ...)
