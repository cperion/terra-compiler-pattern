local U = require("unit")

return U.spec {
    texts = {
        require("examples.ui.ui_asdl"),
    },

    pipeline = {
        "UiDecl",
        "UiLaid",
        "UiBatched",
        "UiRouted",
    },

    install = function(T)
        local Backend = require("examples.ui.ui_backend")

        T.UiBatched.BoxBatch.compile = Backend.compile_box_batch
        T.UiBatched.ShadowBatch.compile = Backend.compile_shadow_batch
        T.UiBatched.ImageBatch.compile = Backend.compile_image_batch
        T.UiBatched.GlyphBatch.compile = Backend.compile_glyph_batch
        T.UiBatched.EffectBatch.compile = Backend.compile_effect_batch
        T.UiBatched.CustomBatch.compile = Backend.compile_batch
        T.UiBatched.Scene.compile = Backend.compile_scene
    end,
}
