local U = require("unit")

return function(T)
    local backend = os.getenv("UNIT_BACKEND") or (rawget(_G, "terralib") and "terra" or "luajit")
    if backend == "terra" then
        return require("examples.ui.backends.terra_ui_batched")(T)
    end

    local unsupported = U.terminal(function()
        error("examples.ui.ui_batched: LuaJIT backend realization is not implemented for the legacy ui stack", 3)
    end)

    T.UiBatched.BoxBatch.compile = unsupported
    T.UiBatched.ShadowBatch.compile = unsupported
    T.UiBatched.ImageBatch.compile = unsupported
    T.UiBatched.GlyphBatch.compile = unsupported
    T.UiBatched.TextBatch.compile = unsupported
    T.UiBatched.EffectBatch.compile = unsupported
    T.UiBatched.CustomBatch.compile = unsupported
    T.UiBatched.Scene.compile = unsupported
end
