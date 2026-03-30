-- js_node.lua
--
-- Node.js compatibility layer: maps Node built-in modules to luvit equivalents.
-- This is the bridge between JS-world `require('http')` and luvit's HTTP.
--
-- Architecture:
--   JS require('http')     -> node_modules.http     -> luvit http
--   JS require('fs')       -> node_modules.fs       -> luvit fs
--   JS require('path')     -> node_modules.path     -> luvit path
--   JS require('./foo')    -> compile & run foo.js   -> module.exports
--
-- The bridge is THIN because luvit was designed to be Node-compatible.
-- Same API shapes, same callback conventions, same event loop (libuv).
--
-- Usage:
--   Inside luvit:  local jsnode = require('examples.js.js_node').init(require)
--   The module needs luvit's require to find bundled modules (fs, http, etc).
--
-- In luvi apps, Lua's standard require can't find luvit's bundled deps.
-- The caller must pass luvit's require function via init().

local M_proto = {}

local fs, path, http, https, net, url, timer, json, uv, qs, childprocess, stream, dns, core, pp

function M_proto.init(luvit_require)
    local req = luvit_require or require
    fs = req('fs')
    path = req('path')
    http = req('http')
    https = req('https')
    net = req('net')
    url = req('url')
    timer = req('timer')
    json = req('json')
    uv = req('uv')
    qs = req('querystring')
    childprocess = req('childprocess')
    stream = req('stream')
    dns = req('dns')
    core = req('core')
    pp = req('pretty-print')
    return M_proto._build()
end

local js_runtime = require('examples.js.js_runtime')
local JS_NULL = js_runtime.JS_NULL
local js_array = js_runtime.js_array
local js_truthy = js_runtime.js_truthy

function M_proto._build()

-- ═══════════════════════════════════════════════════════════════
-- Module cache
-- ═══════════════════════════════════════════════════════════════

local module_cache = {}

-- ═══════════════════════════════════════════════════════════════
-- Response wrapper: make luvit res match Node's res exactly
-- ═══════════════════════════════════════════════════════════════

local function wrap_response(res)
    local proxy = {}
    local mt = {
        __index = function(self, key)
            if key == "end" then
                -- JS: res.end(body) -> Lua: res:finish(body)
                return function(self_or_body, maybe_body)
                    local body = maybe_body or self_or_body
                    if type(body) == "table" and body == self then
                        body = maybe_body
                    end
                    res:finish(body or "")
                end
            end
            if key == "write" then
                return function(self_or_data, maybe_data)
                    local data = maybe_data or self_or_data
                    if type(data) == "table" and data == self then
                        data = maybe_data
                    end
                    res:write(data)
                end
            end
            if key == "writeHead" then
                return function(self_or_code, maybe_code, maybe_headers)
                    local code, headers
                    if type(self_or_code) == "number" then
                        code = self_or_code
                        headers = maybe_code
                    else
                        code = maybe_code
                        headers = maybe_headers
                    end
                    res.statusCode = code or 200
                    if headers then
                        for k, v in pairs(headers) do
                            res:setHeader(k, v)
                        end
                    end
                end
            end
            if key == "setHeader" then
                return function(self_or_name, maybe_name, maybe_value)
                    local name, value
                    if type(self_or_name) == "string" then
                        name, value = self_or_name, maybe_name
                    else
                        name, value = maybe_name, maybe_value
                    end
                    res:setHeader(name, value)
                end
            end
            if key == "statusCode" then
                return res.statusCode
            end
            -- Fall through to luvit res
            local v = res[key]
            if type(v) == "function" then
                return function(self_or_arg, ...)
                    if self_or_arg == proxy then
                        return v(res, ...)
                    end
                    return v(res, self_or_arg, ...)
                end
            end
            return v
        end,
        __newindex = function(self, key, value)
            if key == "statusCode" then
                res.statusCode = value
            else
                rawset(self, key, value)
            end
        end,
    }
    return setmetatable(proxy, mt)
end

-- ═══════════════════════════════════════════════════════════════
-- Request wrapper
-- ═══════════════════════════════════════════════════════════════

local function wrap_request(req)
    local proxy = {}
    local mt = {
        __index = function(self, key)
            if key == "url" then return req.url end
            if key == "method" then return req.method end
            if key == "headers" then return req.headers end
            if key == "on" then
                return function(self_or_event, maybe_event, maybe_cb)
                    local event, cb
                    if type(self_or_event) == "string" then
                        event, cb = self_or_event, maybe_event
                    else
                        event, cb = maybe_event, maybe_cb
                    end
                    req:on(event, cb)
                end
            end
            local v = req[key]
            if type(v) == "function" then
                return function(self_or_arg, ...)
                    if self_or_arg == proxy then
                        return v(req, ...)
                    end
                    return v(req, self_or_arg, ...)
                end
            end
            return v
        end,
    }
    return setmetatable(proxy, mt)
end

-- ═══════════════════════════════════════════════════════════════
-- Node built-in modules -> luvit equivalents
-- ═══════════════════════════════════════════════════════════════

local node_modules = {}

-- ── Server wrapper: JS calls server.listen(port, cb) without self ──
local function wrap_server(srv)
    local proxy = {}
    local mt = {
        __index = function(self, key)
            if key == "listen" then
                return function(port, host_or_cb, maybe_cb)
                    local host, cb
                    if type(host_or_cb) == "function" then
                        host = "0.0.0.0"
                        cb = host_or_cb
                    else
                        host = host_or_cb or "0.0.0.0"
                        cb = maybe_cb
                    end
                    srv:listen(port, host)
                    if cb then
                        -- luvit fires 'listening' but we just call cb directly
                        timer.setImmediate(cb)
                    end
                    return proxy
                end
            end
            if key == "close" then
                return function(cb_or_nil)
                    srv:close()
                    if cb_or_nil then timer.setImmediate(cb_or_nil) end
                end
            end
            if key == "address" then
                return function()
                    return srv:address()
                end
            end
            local v = srv[key]
            if type(v) == "function" then
                return function(...) return v(srv, ...) end
            end
            return v
        end,
    }
    return setmetatable(proxy, mt)
end

-- ── http ──
node_modules.http = {
    createServer = function(handler)
        local srv = http.createServer(function(req, res)
            handler(wrap_request(req), wrap_response(res))
        end)
        return wrap_server(srv)
    end,
    request = function(opts, cb)
        return http.request(opts, cb)
    end,
    get = function(url_str, cb)
        return http.get(url_str, cb)
    end,
}

-- ── https ──
node_modules.https = {
    createServer = function(opts, handler)
        return https.createServer(opts, function(req, res)
            handler(wrap_request(req), wrap_response(res))
        end)
    end,
    request = function(opts, cb)
        return https.request(opts, cb)
    end,
    get = function(url_str, cb)
        return https.get(url_str, cb)
    end,
}

-- ── fs ──
node_modules.fs = {
    readFile = function(filepath, opts_or_cb, maybe_cb)
        local cb = maybe_cb or opts_or_cb
        local encoding = type(opts_or_cb) == "string" and opts_or_cb
            or (type(opts_or_cb) == "table" and opts_or_cb.encoding)
            or nil
        fs.readFile(filepath, function(err, data)
            if err then return cb(err) end
            if encoding == "utf8" or encoding == "utf-8" then
                cb(nil, data)
            else
                cb(nil, data)
            end
        end)
    end,
    readFileSync = function(filepath, opts)
        local data = fs.readFileSync(filepath)
        return data
    end,
    writeFile = function(filepath, data, cb)
        fs.writeFile(filepath, data, cb or function() end)
    end,
    writeFileSync = function(filepath, data)
        fs.writeFileSync(filepath, data)
    end,
    existsSync = function(filepath)
        return fs.existsSync(filepath)
    end,
    mkdirSync = function(dirpath, opts)
        fs.mkdirSync(dirpath)
    end,
    readdirSync = function(dirpath)
        local entries = fs.readdirSync(dirpath)
        return js_array(entries or {})
    end,
    statSync = function(filepath)
        return fs.statSync(filepath)
    end,
    unlinkSync = function(filepath)
        fs.unlinkSync(filepath)
    end,
    appendFileSync = function(filepath, data)
        fs.appendFileSync(filepath, data)
    end,
}

-- ── path ──
node_modules.path = {
    join = function(...)
        return path.join(...)
    end,
    resolve = function(...)
        local parts = { ... }
        if #parts == 0 then return uv.cwd() end
        local result = parts[1]
        if result:sub(1,1) ~= "/" then
            result = uv.cwd() .. "/" .. result
        end
        for i = 2, #parts do
            if parts[i]:sub(1,1) == "/" then
                result = parts[i]
            else
                result = result .. "/" .. parts[i]
            end
        end
        return result
    end,
    dirname = function(p)
        return p:match("(.+)/[^/]*$") or "."
    end,
    basename = function(p, ext)
        local base = p:match("([^/]+)$") or p
        if ext and base:sub(-#ext) == ext then
            base = base:sub(1, -#ext - 1)
        end
        return base
    end,
    extname = function(p)
        return p:match("(%.[^./]+)$") or ""
    end,
    sep = "/",
}

-- ── url ──
node_modules.url = {
    parse = function(url_str)
        return url.parse(url_str)
    end,
    format = function(url_obj)
        return url.format(url_obj)
    end,
}

-- ── querystring ──
node_modules.querystring = {
    parse = function(str)
        return qs.parse(str)
    end,
    stringify = function(obj)
        return qs.stringify(obj)
    end,
}

-- ── net ──
node_modules.net = {
    createServer = function(handler)
        return net.createServer(handler)
    end,
    connect = function(opts, cb)
        return net.connect(opts, cb)
    end,
}

-- ── dns ──
node_modules.dns = {
    resolve = function(hostname, cb)
        dns.resolve(hostname, { type = "A" }, cb)
    end,
}

-- ── child_process ──
node_modules.child_process = {
    spawn = function(cmd, args, opts)
        return childprocess.spawn(cmd, args, opts)
    end,
    exec = function(cmd, cb)
        return childprocess.exec(cmd, {}, cb)
    end,
}

-- ── os ──
node_modules.os = {
    platform = function()
        return jit and jit.os:lower() or "unknown"
    end,
    hostname = function()
        return uv.os_gethostname and uv.os_gethostname() or "localhost"
    end,
    tmpdir = function()
        return os.getenv("TMPDIR") or os.getenv("TMP") or "/tmp"
    end,
    homedir = function()
        return uv.os_homedir and uv.os_homedir() or os.getenv("HOME") or "/"
    end,
    cpus = function()
        return js_array(uv.cpu_info and uv.cpu_info() or {})
    end,
    EOL = "\n",
}

-- ── events ──
node_modules.events = {
    EventEmitter = core and core.Emitter or nil,
}

-- ── stream ──
node_modules.stream = stream or {}

-- ── buffer ──
node_modules.buffer = {
    Buffer = {
        from = function(data, encoding)
            if type(data) == "string" then return data end
            if type(data) == "table" then
                local bytes = {}
                for i, v in ipairs(data) do bytes[i] = string.char(v) end
                return table.concat(bytes)
            end
            return tostring(data)
        end,
        alloc = function(size)
            return string.rep("\0", size)
        end,
        isBuffer = function(obj)
            return type(obj) == "string"
        end,
    },
}

-- ── util ──
node_modules.util = {
    format = string.format,
    inspect = pp and pp.dump or tostring,
    promisify = function(fn)
        return fn -- simplified: no real promise support yet
    end,
}

-- ── JSON (not a Node built-in but universally expected) ──
node_modules.JSON = {
    parse = function(str) return json.parse(str) end,
    stringify = function(val, replacer, space)
        return json.stringify(val)
    end,
}

-- ── timers ──
node_modules.timers = {
    setTimeout = function(fn, ms)
        return timer.setTimeout(ms or 0, fn)
    end,
    setInterval = function(fn, ms)
        return timer.setInterval(ms or 0, fn)
    end,
    clearTimeout = function(id)
        timer.clearTimeout(id)
    end,
    clearInterval = function(id)
        timer.clearInterval(id)
    end,
    setImmediate = function(fn)
        return timer.setImmediate(fn)
    end,
}

-- ── process ──
node_modules.process = {
    env = setmetatable({}, {
        __index = function(_, key)
            return os.getenv(key)
        end,
    }),
    argv = js_array(arg or {}),
    cwd = function() return uv.cwd() end,
    exit = function(code) os.exit(code or 0) end,
    pid = uv.getpid and uv.getpid() or 0,
    platform = jit and jit.os:lower() or "unknown",
    version = "v18.0.0-jsrun",
    versions = { node = "18.0.0", jsrun = "0.1.0", luajit = jit.version },
    stdout = {
        write = function(self_or_data, maybe_data)
            local data = maybe_data or self_or_data
            if type(data) == "table" then data = maybe_data end
            io.write(data or "")
        end,
    },
    stderr = {
        write = function(self_or_data, maybe_data)
            local data = maybe_data or self_or_data
            if type(data) == "table" then data = maybe_data end
            io.stderr:write(data or "")
        end,
    },
    on = function(self_or_event, maybe_event, maybe_handler)
        -- stub: no process event handling yet
    end,
    nextTick = function(fn, ...)
        local args = { ... }
        timer.setImmediate(function() fn(unpack(args)) end)
    end,
}

-- ═══════════════════════════════════════════════════════════════
-- JS module loader
-- ═══════════════════════════════════════════════════════════════

local js_compiler = nil  -- lazily loaded

local function ensure_compiler()
    if js_compiler then return end
    local spec = require('examples.js.js_schema')
    js_compiler = spec.ctx
end

local function resolve_js_path(module_name, from_dir)
    -- Try exact path
    local candidates = {
        module_name,
        module_name .. ".js",
        module_name .. "/index.js",
    }
    for _, candidate in ipairs(candidates) do
        local full
        if candidate:sub(1,1) == "/" then
            full = candidate
        else
            full = from_dir .. "/" .. candidate
        end
        if fs.existsSync(full) then return full end
    end
    return nil
end

local function find_in_node_modules(module_name, from_dir)
    local dir = from_dir
    while dir and #dir > 0 do
        local nm_dir = dir .. "/node_modules/" .. module_name
        local found = resolve_js_path(nm_dir, dir)
        if found then return found end
        -- Check package.json main
        local pkg = nm_dir .. "/package.json"
        if fs.existsSync(pkg) then
            local data = fs.readFileSync(pkg)
            local ok, parsed = pcall(json.parse, data)
            if ok and parsed and parsed.main then
                local main_path = nm_dir .. "/" .. parsed.main
                local found2 = resolve_js_path(main_path, nm_dir)
                if found2 then return found2 end
            end
        end
        local parent = dir:match("(.+)/[^/]+$")
        if parent == dir then break end
        dir = parent
    end
    return nil
end

local function load_js_file(filepath, from_dir)
    -- Check cache
    if module_cache[filepath] then
        return module_cache[filepath].exports
    end

    ensure_compiler()

    local source = fs.readFileSync(filepath)
    if not source then
        error("Cannot find module: " .. filepath)
    end

    local file_dir = filepath:match("(.+)/[^/]*$") or "."

    -- Create module/exports objects
    local module_obj = { exports = {} }
    local exports = module_obj.exports

    -- Build the JS require function for this file
    local function js_require(name)
        -- Built-in Node modules
        if node_modules[name] then
            return node_modules[name]
        end

        -- Relative path
        if name:sub(1,1) == "." or name:sub(1,1) == "/" then
            local resolved = resolve_js_path(name, file_dir)
            if not resolved then
                error("Cannot find module '" .. name .. "' from " .. filepath)
            end
            if resolved:match("%.json$") then
                return json.parse(fs.readFileSync(resolved))
            end
            return load_js_file(resolved, file_dir)
        end

        -- node_modules lookup
        local found = find_in_node_modules(name, file_dir)
        if found then
            if found:match("%.json$") then
                return json.parse(fs.readFileSync(found))
            end
            return load_js_file(found, file_dir)
        end

        error("Cannot find module '" .. name .. "' from " .. filepath)
    end

    -- Extra globals for this module.
    --
    -- Note: the current JS frontend accepts ES-module surface syntax, but it
    -- lowers that syntax into these CommonJS-style globals rather than
    -- implementing native ESM linking/instantiation semantics.
    local module_globals = {
        require = js_require,
        module = module_obj,
        exports = exports,
        __dirname = file_dir,
        __filename = filepath,
        setTimeout = node_modules.timers.setTimeout,
        setInterval = node_modules.timers.setInterval,
        clearTimeout = node_modules.timers.clearTimeout,
        clearInterval = node_modules.timers.clearInterval,
        setImmediate = node_modules.timers.setImmediate,
        Buffer = node_modules.buffer.Buffer,
        process = node_modules.process,
        JSON = node_modules.JSON,
        global = {},
    }

    -- Parse -> resolve -> compile -> run
    local ast = js_compiler.JsSource.parse(source)
    local resolved = ast:resolve()
    local compiled = resolved:compile(module_globals)

    -- Cache before running (handles circular requires)
    module_cache[filepath] = module_obj

    compiled.run()

    return module_obj.exports
end

-- ═══════════════════════════════════════════════════════════════
-- Public API
-- ═══════════════════════════════════════════════════════════════

local M = {}

M.node_modules = node_modules
M.load_js_file = load_js_file
M.module_cache = module_cache

function M.run_file(filepath)
    local resolved = node_modules.path.resolve(filepath)
    return load_js_file(resolved, node_modules.path.dirname(resolved))
end

function M.run_string(source, opts)
    opts = opts or {}
    ensure_compiler()

    local extra = {
        require = function(name)
            if node_modules[name] then return node_modules[name] end
            error("Cannot find module '" .. name .. "'")
        end,
        setTimeout = node_modules.timers.setTimeout,
        setInterval = node_modules.timers.setInterval,
        clearTimeout = node_modules.timers.clearTimeout,
        clearInterval = node_modules.timers.clearInterval,
        setImmediate = node_modules.timers.setImmediate,
        Buffer = node_modules.buffer.Buffer,
        process = node_modules.process,
        JSON = node_modules.JSON,
        module = { exports = {} },
        exports = {},
    }
    if opts.globals then
        for k, v in pairs(opts.globals) do extra[k] = v end
    end

    local ast = js_compiler.JsSource.parse(source)
    local resolved = ast:resolve()
    local compiled = resolved:compile(extra)
    return compiled.run()
end

return M
end -- _build()

-- Auto-init: if luvit's require('fs') works, init immediately
local ok_fs = pcall(require, 'fs')
if ok_fs then
    return M_proto.init(require)
end

-- Otherwise return the proto; caller must call .init(luvit_require)
return M_proto
