local Spec = require("asdl2.asdl2_schema_boot")
local U = require("unit")

local T = Spec.ctx

require("asdl2.boundaries.asdl2_text_spec")(T, U)
require("asdl2.boundaries.asdl2_source_spec")(T, U)
require("asdl2.boundaries.asdl2_catalog_spec")(T, U)
require("asdl2.boundaries.asdl2_lowered_schema")(T, U)
require("asdl2.boundaries.asdl2_machine_schema_luajit")(T, U)
require("asdl2.boundaries.asdl2_luajit_schema_luajit")(T, U)

Spec.pipeline = {
    "Asdl2Text",
    "Asdl2Source",
    "Asdl2Catalog",
    "Asdl2Lowered",
    "Asdl2Machine",
    "Asdl2LuaJIT",
}

return {
    ctx = T,
    pipeline = Spec.pipeline,
}
