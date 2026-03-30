local Spec = require("asdl2.asdl2_schema_boot")

local T = Spec.ctx

require("asdl2.asdl2_text")(T)
require("asdl2.asdl2_source")(T)
require("asdl2.asdl2_catalog")(T)
require("asdl2.asdl2_machine")(T)
require("asdl2.asdl2_install")(T)

Spec.pipeline = {
    "Asdl2Text",
    "Asdl2Source",
    "Asdl2Catalog",
    "Asdl2Lowered",
    "Asdl2Machine",
}

return {
    ctx = T,
    pipeline = Spec.pipeline,
}
