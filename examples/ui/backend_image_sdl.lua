local ffi = require("ffi")

if not rawget(_G, "__ui_backend_image_sdl_ffi_cdef") then
    local ok = pcall(ffi.cdef, [[
        typedef uint32_t SDL_PixelFormat;
        typedef uint32_t SDL_SurfaceFlags;

        typedef struct SDL_Surface {
            SDL_SurfaceFlags flags;
            SDL_PixelFormat format;
            int w;
            int h;
            int pitch;
            void *pixels;
            int refcount;
            void *reserved;
        } SDL_Surface;

        SDL_Surface *SDL_LoadBMP(const char *file);
        SDL_Surface *SDL_LoadPNG(const char *file);
        SDL_Surface *SDL_ConvertSurface(SDL_Surface *surface, SDL_PixelFormat format);
        void SDL_DestroySurface(SDL_Surface *surface);
        const char *SDL_GetError(void);
    ]])
    if not ok then
        pcall(ffi.cdef, [[
            SDL_Surface *SDL_LoadBMP(const char *file);
            SDL_Surface *SDL_LoadPNG(const char *file);
            SDL_Surface *SDL_ConvertSurface(SDL_Surface *surface, SDL_PixelFormat format);
            void SDL_DestroySurface(SDL_Surface *surface);
            const char *SDL_GetError(void);
        ]])
    end
    _G.__ui_backend_image_sdl_ffi_cdef = true
end

local SDL = ffi.load("SDL3", true)

local SDL_PIXELFORMAT_RGBA32 = ffi.abi("be") and 0x16462004 or 0x16762004

local cache = {}
local MISSING_PIXELS = string.char(
    255, 0, 255, 255,   32, 32, 32, 255,
    32, 32, 32, 255,    255, 0, 255, 255
)

local function sdl_error(where)
    error(("%s: %s"):format(where, ffi.string(SDL.SDL_GetError())), 3)
end

local function missing_image(path)
    return {
        path = path,
        width = 2,
        height = 2,
        pixels = MISSING_PIXELS,
        missing = true,
    }
end

local function read_pixels_rgba(surface)
    local row_bytes = surface.w * 4
    local total = row_bytes * surface.h

    if total == 0 then return "" end

    if surface.pitch == row_bytes then
        return ffi.string(surface.pixels, total)
    end

    local src = ffi.cast("uint8_t *", surface.pixels)
    local out = ffi.new("uint8_t[?]", total)
    for y = 0, surface.h - 1 do
        ffi.copy(out + y * row_bytes, src + y * surface.pitch, row_bytes)
    end
    return ffi.string(out, total)
end

local function decode_surface(path)
    local lower = path:lower()
    local surface
    if lower:match("%.png$") then
        surface = SDL.SDL_LoadPNG(path)
        if surface == nil then sdl_error("SDL_LoadPNG") end
    elseif lower:match("%.bmp$") then
        surface = SDL.SDL_LoadBMP(path)
        if surface == nil then sdl_error("SDL_LoadBMP") end
    else
        error(("UiImage: unsupported image format for '%s' (expected .png or .bmp)"):format(path), 3)
    end
    return surface
end

local Image = {}

function Image.load_rgba(path)
    local cached = cache[path]
    if cached then return cached end

    local ok, surface = pcall(decode_surface, path)
    if not ok or surface == nil then
        local result = missing_image(path)
        cache[path] = result
        return result
    end

    local converted = SDL.SDL_ConvertSurface(surface, SDL_PIXELFORMAT_RGBA32)
    SDL.SDL_DestroySurface(surface)
    if converted == nil then
        local result = missing_image(path)
        cache[path] = result
        return result
    end

    local result = {
        path = path,
        width = converted.w,
        height = converted.h,
        pixels = read_pixels_rgba(converted),
    }
    SDL.SDL_DestroySurface(converted)

    cache[path] = result
    return result
end

function Image.size(path)
    local image = Image.load_rgba(path)
    return image.width, image.height
end

function Image.texture_key(path, sampling)
    return string.format("image:%s:%s", path, sampling or "Linear")
end

return Image
