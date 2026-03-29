local function this_path()
    local src = debug.getinfo(1, "S").source or "@unit.lua"
    if src:sub(1, 1) == "@" then src = src:sub(2) end
    return src
end

local function selected_backend()
    local forced = os.getenv("UNIT_BACKEND")
    if forced == "terra" or forced == "luajit" then
        return forced
    end
    return rawget(_G, "terralib") and "terra" or "luajit"
end

local function load_backend()
    if selected_backend() == "terra" then
        local path = this_path():gsub("%.lua$", ".t")
        local chunk = assert(terralib.loadfile(path))
        return chunk()
    end
    return require("unit_luajit")
end

local U = load_backend()
package.loaded["unit"] = U

local function running_as_main()
    local argv = rawget(_G, "arg")
    local script = argv and argv[0]
    if not script then return false end
    local base = tostring(script):match("([^/\\]+)$") or tostring(script)
    return base == "unit.lua"
end

if running_as_main() and type(U.cli) == "function" then
    local ok, result = xpcall(function()
        return U.cli(rawget(_G, "arg"))
    end, debug.traceback)

    if not ok then
        io.stderr:write(result, "\n")
        os.exit(1)
    end

    if type(result) == "number" and result ~= 0 then
        os.exit(result)
    end
end

return U
