local U = require("unit")

local Codec = {}

Codec.DOMAIN = 700
Codec.commands = {
    select_title = 1,
    select_image = 2,
    select_custom = 3,
    select_overlay = 4,
}

local function target_code(target)
    return U.match(target, {
        TitleCard = function() return 1 end,
        ImagePlaceholder = function() return 2 end,
        CustomCard = function() return 3 end,
        OverlayCard = function() return 4 end,
    })
end

local function target_for_key(T, key)
    return ({
        select_title = function() return T.DemoCore.TitleCard() end,
        select_image = function() return T.DemoCore.ImagePlaceholder() end,
        select_custom = function() return T.DemoCore.CustomCard() end,
        select_overlay = function() return T.DemoCore.OverlayCard() end,
    })[key]()
end

function Codec.encode_command(T, command)
    return U.match(command, {
        SelectTarget = function(v)
            return T.UiCore.CommandRef(Codec.commands[({
                TitleCard = "select_title",
                ImagePlaceholder = "select_image",
                CustomCard = "select_custom",
                OverlayCard = "select_overlay",
            })[v.target.kind]])
        end,
    })
end

function Codec.decode_command(T, ref)
    if not ref then return nil end

    local by_code = {
        [Codec.commands.select_title] = function()
            return T.DemoCommand.SelectTarget(T.DemoCore.TitleCard())
        end,
        [Codec.commands.select_image] = function()
            return T.DemoCommand.SelectTarget(T.DemoCore.ImagePlaceholder())
        end,
        [Codec.commands.select_custom] = function()
            return T.DemoCommand.SelectTarget(T.DemoCore.CustomCard())
        end,
        [Codec.commands.select_overlay] = function()
            return T.DemoCommand.SelectTarget(T.DemoCore.OverlayCard())
        end,
    }

    local decode = by_code[ref.value]
    if not decode then return nil end
    return decode()
end

function Codec.semantic_ref(T, key)
    local target = target_for_key(T, key)
    return T.UiCore.SemanticRef(Codec.DOMAIN, target_code(target))
end

function Codec.decode_target(T, semantic_ref)
    if not semantic_ref or semantic_ref.domain ~= Codec.DOMAIN then return nil end

    local by_value = {
        [1] = function() return T.DemoCore.TitleCard() end,
        [2] = function() return T.DemoCore.ImagePlaceholder() end,
        [3] = function() return T.DemoCore.CustomCard() end,
        [4] = function() return T.DemoCore.OverlayCard() end,
    }

    local decode = by_value[semantic_ref.value]
    if not decode then return nil end
    return decode()
end

function Codec.command_ref(T, key)
    local target = target_for_key(T, key)
    return Codec.encode_command(T, T.DemoCommand.SelectTarget(target))
end

return Codec
