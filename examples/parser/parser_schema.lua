-- parser_schema.lua
-- Loads the parser project via unit project conventions + asdl2.

local U = require("unit")
local spec = U.load_inspect_spec("examples/parser")
local ctx = spec.ctx

return {
    ctx = ctx,
    pipeline = spec.pipeline,
}
