local U = require("unit")
local F = require("fun")
local Text = require("examples.ui.ui_text_resolve")

local Batching = {}
local unpack_fn = table.unpack or unpack

local function L(xs)
    return terralib.newlist(xs or {})
end

local function scene_bounds(T, viewport)
    return T.UiCore.Rect(0, 0, viewport.w, viewport.h)
end

local function top_clip(element)
    local n = #element.clip_stack
    if n == 0 then return nil end
    return element.clip_stack[n]
end

local function chain_lists(lists)
    if #lists == 0 then return L() end
    return L(F.chain(unpack_fn(lists)):totable())
end

local function same_value(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end

    local am = getmetatable(a)
    local bm = getmetatable(b)
    if am ~= bm then return false end
    if not am or not am.__fields then return false end

    for _, field in ipairs(am.__fields) do
        local av = a[field.name]
        local bv = b[field.name]
        if field.list then
            if #av ~= #bv then return false end
            for i = 1, #av do
                if not same_value(av[i], bv[i]) then return false end
            end
        else
            if not same_value(av, bv) then return false end
        end
    end
    return true
end

local function merge_batches(T, batches)
    local out = {}

    local function push(batch)
        local prev = out[#out]
        if not prev then
            out[#out + 1] = batch
            return
        end

        local merged = nil
        if prev.kind == "BoxBatch" and batch.kind == "BoxBatch" and same_value(prev.clip, batch.clip) then
            merged = T.UiBatched.BoxBatch(0, prev.clip, chain_lists { prev.items, batch.items })
        elseif prev.kind == "ShadowBatch" and batch.kind == "ShadowBatch" and same_value(prev.clip, batch.clip) then
            merged = T.UiBatched.ShadowBatch(0, prev.clip, chain_lists { prev.items, batch.items })
        elseif prev.kind == "ImageBatch" and batch.kind == "ImageBatch" and same_value(prev.clip, batch.clip) and same_value(prev.image, batch.image) and same_value(prev.sampling, batch.sampling) then
            merged = T.UiBatched.ImageBatch(0, prev.clip, prev.image, prev.sampling, chain_lists { prev.items, batch.items })
        elseif prev.kind == "GlyphBatch" and batch.kind == "GlyphBatch" and same_value(prev.clip, batch.clip) and same_value(prev.font, batch.font) and same_value(prev.atlas, batch.atlas) then
            merged = T.UiBatched.GlyphBatch(0, prev.clip, prev.font, prev.atlas, chain_lists { prev.items, batch.items })
        elseif prev.kind == "TextBatch" and batch.kind == "TextBatch" and same_value(prev.clip, batch.clip) and same_value(prev.font, batch.font) and prev.size_px == batch.size_px then
            merged = T.UiBatched.TextBatch(0, prev.clip, prev.font, prev.size_px, chain_lists { prev.items, batch.items })
        end

        if merged then
            out[#out] = merged
        else
            out[#out + 1] = batch
        end
    end

    for _, batch in ipairs(batches) do
        push(batch)
    end
    return L(out)
end

local function effect_batch(T, clip, item)
    return T.UiBatched.EffectBatch(0, clip, L { item })
end

local function draw_pre_batches(T, clip, draw)
    return U.match(draw, {
        BoxDraw = function(v)
            return L {
                T.UiBatched.BoxBatch(0, clip, L {
                    T.UiBatched.BoxItem(v.rect, v.fill, v.stroke, v.stroke_width, v.align, v.corners)
                })
            }
        end,
        ShadowDraw = function(v)
            return L {
                T.UiBatched.ShadowBatch(0, clip, L {
                    T.UiBatched.ShadowItem(v.rect, v.brush, v.blur, v.spread, v.dx, v.dy, v.kind, v.corners)
                })
            }
        end,
        TextDraw = function(v)
            local first_line = v.text.lines[1]
            local first_run = first_line and first_line.runs[1] or nil
            if not first_run then return L() end
            return L {
                T.UiBatched.TextBatch(
                    0,
                    clip,
                    first_run.font,
                    first_run.size_px,
                    L {
                        T.UiBatched.TextItem(v.text.text, v.text.bounds, first_run.color, v.text.wrap, v.text.align)
                    }
                )
            }
        end,
        ImageDraw = function(v)
            return L {
                T.UiBatched.ImageBatch(
                    0,
                    clip,
                    v.image,
                    v.style.sampling,
                    L {
                        T.UiBatched.ImageItem(v.rect, v.style)
                    }
                )
            }
        end,
        ClipDraw = function(v)
            return L {
                effect_batch(T, clip, T.UiBatched.PushClip(v.shape))
            }
        end,
        OpacityDraw = function(v)
            return L {
                effect_batch(T, clip, T.UiBatched.PushOpacity(v.value))
            }
        end,
        TransformDraw = function(v)
            return L {
                effect_batch(T, clip, T.UiBatched.PushTransform(v.xform))
            }
        end,
        BlendDraw = function(v)
            return L {
                effect_batch(T, clip, T.UiBatched.PushBlend(v.mode))
            }
        end,
        CustomDraw = function(v)
            return L {
                T.UiBatched.CustomBatch(0, clip, v.kind, v.payload)
            }
        end,
    })
end

local function draw_post_batches(T, clip, draw)
    return U.match(draw, {
        BoxDraw = function(_) return L() end,
        ShadowDraw = function(_) return L() end,
        TextDraw = function(_) return L() end,
        ImageDraw = function(_) return L() end,
        CustomDraw = function(_) return L() end,
        ClipDraw = function(_)
            return L {
                effect_batch(T, clip, T.UiBatched.PopClip())
            }
        end,
        OpacityDraw = function(_)
            return L {
                effect_batch(T, clip, T.UiBatched.PopOpacity())
            }
        end,
        TransformDraw = function(_)
            return L {
                effect_batch(T, clip, T.UiBatched.PopTransform())
            }
        end,
        BlendDraw = function(_)
            return L {
                effect_batch(T, clip, T.UiBatched.PopBlend())
            }
        end,
    })
end

local element_batches

element_batches = terralib.memoize(function(T, element)
    if not element.visible then
        return L()
    end

    local clip = top_clip(element)

    local pre = chain_lists(F.iter(element.draw):map(function(draw)
        return draw_pre_batches(T, clip, draw)
    end):totable())

    local children = chain_lists(F.iter(element.children):map(function(child)
        return element_batches(T, child)
    end):totable())

    local draws = F.iter(element.draw):totable()
    local reversed = {}
    for i = #draws, 1, -1 do
        reversed[#reversed + 1] = draws[i]
    end

    local post = chain_lists(F.iter(reversed):map(function(draw)
        return draw_post_batches(T, clip, draw)
    end):totable())

    return chain_lists { pre, children, post }
end)

function Batching.install(T)
    T.UiLaid.Scene.batch = U.transition(function(scene)
        local roots = F.iter(scene.roots):map(function(root)
            return element_batches(T, root.root)
        end):totable()

        local overlays = F.iter(scene.overlays):map(function(overlay)
            return element_batches(T, overlay.root)
        end):totable()

        local batches = merge_batches(T, chain_lists {
            chain_lists(roots),
            chain_lists(overlays),
        })

        return T.UiBatched.Scene(
            batches,
            scene_bounds(T, scene.viewport)
        )
    end)
end

return Batching
