local F = require("fun")

local Assets = {}

local function require_catalog(catalog, where)
    if catalog then return catalog end
    error(("%s: UiAsset.Catalog is required"):format(where), 2)
end

local function find_font(catalog, font_ref)
    local ref = font_ref or catalog.default_font
    local matches = F.iter(catalog.fonts)
        :filter(function(asset) return asset.ref == ref end)
        :totable()

    if #matches == 0 then
        error(("UiAsset: no font asset for FontRef(%s)"):format(tostring(ref and ref.value)), 2)
    end

    return matches[1]
end

local function find_image(catalog, image_ref)
    local matches = F.iter(catalog.images)
        :filter(function(asset) return asset.ref == image_ref end)
        :totable()

    if #matches == 0 then
        error(("UiAsset: no image asset for ImageRef(%s)"):format(tostring(image_ref and image_ref.value)), 2)
    end

    return matches[1]
end

function Assets.default_font_ref(catalog)
    return require_catalog(catalog, "UiAsset.default_font_ref").default_font
end

function Assets.font_path(catalog, font_ref)
    return find_font(require_catalog(catalog, "UiAsset.font_path"), font_ref).path
end

function Assets.image_path(catalog, image_ref)
    return find_image(require_catalog(catalog, "UiAsset.image_path"), image_ref).path
end

return Assets
