#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local A = require("asdl")

local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = assert(f:read("*a"))
    f:close()
    return s
end

local source = A.parse(slurp("asdl_language.asdl"))
local resolved = A.resolve(source)
local lowered = A.lower_luajit(resolved, { prefix = "schema_test" })

assert(#source.definitions == 1)
assert(#resolved.definitions == 1)
assert(#lowered.types > 0)

print("ok")
