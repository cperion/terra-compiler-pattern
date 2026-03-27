-- ============================================================================
-- SDL + OpenGL backend scaffold
-- ----------------------------------------------------------------------------
-- Backend-only support for the canonical UI compiler.
--
-- This file stays in .t because the backend and terminals are Terra/Lua mixed.
-- The pure UI / app phases remain ASDL -> ASDL above this layer.
--
-- Initial implementation order (leaf first):
--   1. init SDL window + GL context
--   2. poll SDL events -> UiInput.Event
--   3. compile BoxBatch
--   4. compile GlyphBatch
--   5. compile EffectBatch (clip/opacity/transform needed by the app)
-- ============================================================================

local ffi = require("ffi")

local Backend = {}

if not rawget(_G, "__terra_ui_sdl_gl_ffi_cdef") then
    ffi.cdef [[
        typedef struct SDL_Window SDL_Window;
        typedef void *SDL_GLContext;
        typedef uint32_t SDL_InitFlags;
        typedef uint64_t SDL_WindowFlags;
        typedef int SDL_GLAttr;

        bool SDL_Init(SDL_InitFlags flags);
        void SDL_Quit(void);
        const char *SDL_GetError(void);

        bool SDL_GL_SetAttribute(SDL_GLAttr attr, int value);
        SDL_Window *SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags);
        void SDL_DestroyWindow(SDL_Window *window);
        SDL_GLContext SDL_GL_CreateContext(SDL_Window *window);
        bool SDL_GL_DestroyContext(SDL_GLContext context);
        bool SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context);
        bool SDL_GL_SetSwapInterval(int interval);
        bool SDL_GL_SwapWindow(SDL_Window *window);
        bool SDL_GetWindowSizeInPixels(SDL_Window *window, int *w, int *h);
        void SDL_Delay(uint32_t ms);
    ]]
    _G.__terra_ui_sdl_gl_ffi_cdef = true
end

Backend.FFI = ffi.load("SDL3", true)
Backend.GL = ffi.load("GL", true)

Backend.SDL_INIT_VIDEO = 0x00000020
Backend.SDL_WINDOW_OPENGL = 0x0000000000000002
Backend.SDL_WINDOW_RESIZABLE = 0x0000000000000020
Backend.SDL_WINDOW_HIGH_PIXEL_DENSITY = 0x0000000000002000
Backend.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 0x0002

function Backend.headers()
    if Backend.C then return Backend.C end

    Backend.C = terralib.includecstring [[
        #include <stdint.h>
        #include <SDL3/SDL.h>
        #include <SDL3/SDL_opengl.h>
    ]]

    return Backend.C
end

function Backend.runtime_t()
    if Backend.Runtime then return Backend.Runtime end

    local ClipRect = terralib.types.newstruct("UiSdlGlClipRect")
    ClipRect.entries:insert({ field = "x", type = int32 })
    ClipRect.entries:insert({ field = "y", type = int32 })
    ClipRect.entries:insert({ field = "w", type = int32 })
    ClipRect.entries:insert({ field = "h", type = int32 })

    local Runtime = terralib.types.newstruct("UiSdlGlRuntime")
    Runtime.entries:insert({ field = "width", type = int32 })
    Runtime.entries:insert({ field = "height", type = int32 })
    Runtime.entries:insert({ field = "opacity", type = double })
    Runtime.entries:insert({ field = "opacity_top", type = int32 })
    Runtime.entries:insert({ field = "opacity_stack", type = double[64] })
    Runtime.entries:insert({ field = "clip_enabled", type = int32 })
    Runtime.entries:insert({ field = "clip_top", type = int32 })
    Runtime.entries:insert({ field = "clip_x", type = int32 })
    Runtime.entries:insert({ field = "clip_y", type = int32 })
    Runtime.entries:insert({ field = "clip_w", type = int32 })
    Runtime.entries:insert({ field = "clip_h", type = int32 })
    Runtime.entries:insert({ field = "clip_stack", type = ClipRect[64] })
    Runtime.entries:insert({ field = "clip_enabled_stack", type = int32[64] })

    Backend.ClipRect = ClipRect
    Backend.Runtime = Runtime
    return Runtime
end

local function sdl_ok(ok, where)
    if ok then return end
    error(("%s: %s"):format(where, ffi.string(Backend.FFI.SDL_GetError())), 3)
end

function Backend.init_window(title, width, height)
    local C = Backend.headers()
    local Runtime = Backend.runtime_t()
    local SDL = Backend.FFI

    sdl_ok(SDL.SDL_Init(Backend.SDL_INIT_VIDEO), "SDL_Init")
    sdl_ok(SDL.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MAJOR_VERSION, 2), "SDL_GL_SetAttribute(MAJOR)")
    sdl_ok(SDL.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MINOR_VERSION, 1), "SDL_GL_SetAttribute(MINOR)")
    sdl_ok(SDL.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_PROFILE_MASK, Backend.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY), "SDL_GL_SetAttribute(PROFILE)")

    local flags = Backend.SDL_WINDOW_OPENGL
        + Backend.SDL_WINDOW_RESIZABLE
        + Backend.SDL_WINDOW_HIGH_PIXEL_DENSITY

    local window = SDL.SDL_CreateWindow(title or "terra-ui", width or 1280, height or 720, flags)
    if window == nil then
        error(("SDL_CreateWindow: %s"):format(ffi.string(SDL.SDL_GetError())), 2)
    end

    local gl_context = SDL.SDL_GL_CreateContext(window)
    if gl_context == nil then
        SDL.SDL_DestroyWindow(window)
        SDL.SDL_Quit()
        error(("SDL_GL_CreateContext: %s"):format(ffi.string(SDL.SDL_GetError())), 2)
    end

    sdl_ok(SDL.SDL_GL_MakeCurrent(window, gl_context), "SDL_GL_MakeCurrent")
    SDL.SDL_GL_SetSwapInterval(1)

    local w = ffi.new("int[1]", 0)
    local h = ffi.new("int[1]", 0)
    sdl_ok(SDL.SDL_GetWindowSizeInPixels(window, w, h), "SDL_GetWindowSizeInPixels")

    local state = terralib.new(Runtime)
    state.width = w[0]
    state.height = h[0]
    state.opacity = 1.0
    state.opacity_top = 0
    state.clip_enabled = 0
    state.clip_top = 0
    state.clip_x = 0
    state.clip_y = 0
    state.clip_w = 0
    state.clip_h = 0

    return {
        window = window,
        gl_context = gl_context,
        state = state,
    }
end

function Backend.shutdown_window(runtime)
    if not runtime then return end

    local SDL = Backend.FFI
    if runtime.gl_context ~= nil then
        SDL.SDL_GL_DestroyContext(runtime.gl_context)
        runtime.gl_context = nil
    end
    if runtime.window ~= nil then
        SDL.SDL_DestroyWindow(runtime.window)
        runtime.window = nil
    end
    SDL.SDL_Quit()
end

function Backend.poll_sdl_event(runtime)
    error("TODO: SDL_Event -> UiInput.Event", 2)
end

function Backend.swap_window(runtime)
    if not runtime or runtime.window == nil then return end
    local SDL = Backend.FFI
    sdl_ok(SDL.SDL_GL_SwapWindow(runtime.window), "SDL_GL_SwapWindow")
end

function Backend.sync_window_size(runtime)
    if not runtime or runtime.window == nil then return end
    local SDL = Backend.FFI
    local w = ffi.new("int[1]", 0)
    local h = ffi.new("int[1]", 0)
    sdl_ok(SDL.SDL_GetWindowSizeInPixels(runtime.window, w, h), "SDL_GetWindowSizeInPixels")
    runtime.state.width = w[0]
    runtime.state.height = h[0]
end

function Backend.ensure_gl_objects(runtime)
    -- Immediate-mode first slice: no shader/program/vao setup required yet.
    return runtime
end

function Backend.render_unit(runtime, unit)
    Backend.sync_window_size(runtime)
    unit.fn(runtime.state)
    Backend.swap_window(runtime)
end

return Backend
