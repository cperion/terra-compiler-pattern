local U = require("unit")
local Native = require("asdl2.asdl2_native_leaf_luajit")

return function(T)
    T.Asdl2Machine.Schema.install = U.terminal(function(schema, ctx)
        ctx = ctx or Native.new_context()
        ctx:Extern("any", function(_) return true end)
        return Native.install(schema, ctx)
    end)
end
