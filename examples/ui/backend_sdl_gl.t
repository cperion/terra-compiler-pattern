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
local U = require("unit")

local Backend = {}

if not rawget(_G, "__terra_ui_sdl_gl_ffi_cdef") then
    ffi.cdef [[
        typedef struct SDL_Window SDL_Window;
        typedef void *SDL_GLContext;
        typedef uint8_t Uint8;
        typedef uint16_t Uint16;
        typedef uint32_t Uint32;
        typedef int32_t Sint32;
        typedef uint32_t SDL_InitFlags;
        typedef uint64_t SDL_WindowFlags;
        typedef int SDL_GLAttr;
        typedef uint32_t SDL_WindowID;
        typedef uint32_t SDL_MouseID;
        typedef uint32_t SDL_KeyboardID;
        typedef uint32_t SDL_Scancode;
        typedef uint32_t SDL_Keycode;
        typedef uint16_t SDL_Keymod;
        typedef uint32_t SDL_EventType;
        typedef uint32_t SDL_MouseButtonFlags;
        typedef uint32_t SDL_MouseWheelDirection;

        typedef struct SDL_WindowEvent {
            SDL_EventType type;
            Uint32 reserved;
            uint64_t timestamp;
            SDL_WindowID windowID;
            Sint32 data1;
            Sint32 data2;
        } SDL_WindowEvent;

        typedef struct SDL_KeyboardEvent {
            SDL_EventType type;
            Uint32 reserved;
            uint64_t timestamp;
            SDL_WindowID windowID;
            SDL_KeyboardID which;
            SDL_Scancode scancode;
            SDL_Keycode key;
            SDL_Keymod mod;
            Uint16 raw;
            bool down;
            bool repeat_;
        } SDL_KeyboardEvent;

        typedef struct SDL_TextInputEvent {
            SDL_EventType type;
            Uint32 reserved;
            uint64_t timestamp;
            SDL_WindowID windowID;
            const char *text;
        } SDL_TextInputEvent;

        typedef struct SDL_MouseMotionEvent {
            SDL_EventType type;
            Uint32 reserved;
            uint64_t timestamp;
            SDL_WindowID windowID;
            SDL_MouseID which;
            SDL_MouseButtonFlags state;
            float x;
            float y;
            float xrel;
            float yrel;
        } SDL_MouseMotionEvent;

        typedef struct SDL_MouseButtonEvent {
            SDL_EventType type;
            Uint32 reserved;
            uint64_t timestamp;
            SDL_WindowID windowID;
            SDL_MouseID which;
            Uint8 button;
            bool down;
            Uint8 clicks;
            Uint8 padding;
            float x;
            float y;
        } SDL_MouseButtonEvent;

        typedef struct SDL_MouseWheelEvent {
            SDL_EventType type;
            Uint32 reserved;
            uint64_t timestamp;
            SDL_WindowID windowID;
            SDL_MouseID which;
            float x;
            float y;
            SDL_MouseWheelDirection direction;
            float mouse_x;
            float mouse_y;
            Sint32 integer_x;
            Sint32 integer_y;
        } SDL_MouseWheelEvent;

        typedef union SDL_Event {
            Uint32 type;
            SDL_WindowEvent window;
            SDL_KeyboardEvent key;
            SDL_TextInputEvent text;
            SDL_MouseMotionEvent motion;
            SDL_MouseButtonEvent button;
            SDL_MouseWheelEvent wheel;
            Uint8 padding[128];
        } SDL_Event;

        typedef unsigned int GLenum;
        typedef unsigned int GLuint;
        typedef unsigned int GLbitfield;
        typedef int GLint;
        typedef int GLsizei;
        typedef float GLfloat;
        typedef double GLdouble;

        bool SDL_Init(SDL_InitFlags flags);
        void SDL_Quit(void);
        const char *SDL_GetError(void);

        void glGenTextures(GLsizei n, GLuint *textures);
        void glBindTexture(GLenum target, GLuint texture);
        void glTexParameteri(GLenum target, GLenum pname, GLint param);
        void glPixelStorei(GLenum pname, GLint param);
        void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
        void glDeleteTextures(GLsizei n, const GLuint *textures);
        void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
        void glMatrixMode(GLenum mode);
        void glLoadIdentity(void);
        void glOrtho(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear, GLdouble zFar);
        void glDisable(GLenum cap);
        void glClearColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
        void glClear(GLbitfield mask);

        bool SDL_GL_SetAttribute(SDL_GLAttr attr, int value);
        SDL_Window *SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags);
        void SDL_DestroyWindow(SDL_Window *window);
        SDL_GLContext SDL_GL_CreateContext(SDL_Window *window);
        bool SDL_GL_DestroyContext(SDL_GLContext context);
        bool SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context);
        bool SDL_GL_SetSwapInterval(int interval);
        bool SDL_GL_SwapWindow(SDL_Window *window);
        bool SDL_GetWindowSize(SDL_Window *window, int *w, int *h);
        bool SDL_GetWindowSizeInPixels(SDL_Window *window, int *w, int *h);
        bool SDL_StartTextInput(SDL_Window *window);
        bool SDL_StopTextInput(SDL_Window *window);
        bool SDL_PollEvent(SDL_Event *event);
        uint64_t SDL_GetTicksNS(void);
        void SDL_Delay(uint32_t ms);
    ]]
    _G.__terra_ui_sdl_gl_ffi_cdef = true
end

Backend.FFI = ffi.load("SDL3", true)
Backend.GL = ffi.load("GL", true)
Backend.texture_cache = {}

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

function Backend.ensure_rgba_texture(key, width, height, pixels, sampling)
    local cached = Backend.texture_cache[key]
    if cached then return cached end

    local C = Backend.headers()
    local GL = Backend.GL
    local tex = ffi.new("GLuint[1]", 0)
    local minmag = (sampling == "Nearest") and C.GL_NEAREST or C.GL_LINEAR
    local byte_count = #pixels
    local buffer = ffi.new("uint8_t[?]", byte_count)

    if type(pixels) == "string" then
        ffi.copy(buffer, pixels, byte_count)
    elseif type(pixels) == "cdata" then
        ffi.copy(buffer, pixels, byte_count)
    else
        for i = 1, byte_count do
            buffer[i - 1] = pixels[i]
        end
    end

    GL.glGenTextures(1, tex)
    GL.glBindTexture(C.GL_TEXTURE_2D, tex[0])
    GL.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, minmag)
    GL.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAG_FILTER, minmag)
    GL.glPixelStorei(C.GL_UNPACK_ALIGNMENT, 1)
    GL.glTexImage2D(C.GL_TEXTURE_2D, 0, C.GL_RGBA, width, height, 0, C.GL_RGBA, C.GL_UNSIGNED_BYTE, buffer)

    cached = {
        id = tonumber(tex[0]),
        w = width,
        h = height,
    }
    Backend.texture_cache[key] = cached
    return cached
end

function Backend.clear_texture_cache()
    local GL = Backend.GL
    for _, texture in pairs(Backend.texture_cache) do
        if texture.id and texture.id ~= 0 then
            local tex = ffi.new("GLuint[1]", texture.id)
            GL.glDeleteTextures(1, tex)
        end
    end
    Backend.texture_cache = {}
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

    local text_input = false
    if SDL.SDL_StartTextInput(window) then
        text_input = true
    end

    return {
        window = window,
        gl_context = gl_context,
        state = state,
        text_input = text_input,
    }
end

function Backend.shutdown_window(runtime)
    if not runtime then return end

    local SDL = Backend.FFI
    if runtime.current_unit then
        Backend.release_unit(runtime.current_unit)
        runtime.current_unit = nil
    end
    Backend.clear_texture_cache()
    if runtime.gl_context ~= nil then
        SDL.SDL_GL_DestroyContext(runtime.gl_context)
        runtime.gl_context = nil
    end
    if runtime.window ~= nil then
        if runtime.text_input then
            SDL.SDL_StopTextInput(runtime.window)
            runtime.text_input = false
        end
        SDL.SDL_DestroyWindow(runtime.window)
        runtime.window = nil
    end
    SDL.SDL_Quit()
end

local function native_event_kind(event)
    local C = Backend.headers()
    if event.type == C.SDL_EVENT_QUIT or event.type == C.SDL_EVENT_WINDOW_CLOSE_REQUESTED then
        return "Quit"
    end
    if event.type == C.SDL_EVENT_WINDOW_RESIZED or event.type == C.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED then
        return "WindowResized"
    end
    if event.type == C.SDL_EVENT_WINDOW_FOCUS_GAINED then
        return "FocusGained"
    end
    if event.type == C.SDL_EVENT_WINDOW_FOCUS_LOST then
        return "FocusLost"
    end
    if event.type == C.SDL_EVENT_MOUSE_MOTION then
        return "PointerMoved"
    end
    if event.type == C.SDL_EVENT_MOUSE_BUTTON_DOWN then
        return "PointerPressed"
    end
    if event.type == C.SDL_EVENT_MOUSE_BUTTON_UP then
        return "PointerReleased"
    end
    if event.type == C.SDL_EVENT_MOUSE_WHEEL then
        return "WheelScrolled"
    end
    if event.type == C.SDL_EVENT_KEY_DOWN then
        return event.key.repeat_ and "KeyRepeat" or "KeyDown"
    end
    if event.type == C.SDL_EVENT_KEY_UP then
        return "KeyUp"
    end
    if event.type == C.SDL_EVENT_TEXT_INPUT then
        return "TextEntered"
    end
    return nil
end

function Backend.poll_native_event(runtime)
    local SDL = Backend.FFI
    local event = ffi.new("SDL_Event[1]")
    if not SDL.SDL_PollEvent(event) then
        return nil
    end

    local e = event[0]
    local timestamp_ns = tonumber(e.window.timestamp)
    local kind = native_event_kind(e)
    if not kind then
        return { kind = "Ignored", timestamp_ns = timestamp_ns }
    end

    if kind == "Quit" then
        return { kind = "Quit", timestamp_ns = timestamp_ns }
    end
    if kind == "WindowResized" then
        local w = ffi.new("int[1]", 0)
        local h = ffi.new("int[1]", 0)
        SDL.SDL_GetWindowSize(runtime.window, w, h)
        return { kind = "WindowResized", w = w[0], h = h[0], timestamp_ns = timestamp_ns }
    end
    if kind == "FocusGained" then
        return { kind = "FocusChanged", focused = true, timestamp_ns = timestamp_ns }
    end
    if kind == "FocusLost" then
        return { kind = "FocusChanged", focused = false, timestamp_ns = timestamp_ns }
    end
    if kind == "PointerMoved" then
        return { kind = "PointerMoved", x = e.motion.x, y = e.motion.y, timestamp_ns = timestamp_ns }
    end
    if kind == "PointerPressed" then
        return { kind = "PointerPressed", x = e.button.x, y = e.button.y, button = e.button.button, clicks = e.button.clicks, timestamp_ns = timestamp_ns }
    end
    if kind == "PointerReleased" then
        return { kind = "PointerReleased", x = e.button.x, y = e.button.y, button = e.button.button, clicks = e.button.clicks, timestamp_ns = timestamp_ns }
    end
    if kind == "WheelScrolled" then
        return { kind = "WheelScrolled", x = e.wheel.mouse_x, y = e.wheel.mouse_y, dx = e.wheel.integer_x ~= 0 and e.wheel.integer_x or e.wheel.x, dy = e.wheel.integer_y ~= 0 and e.wheel.integer_y or e.wheel.y, timestamp_ns = timestamp_ns }
    end
    if kind == "KeyDown" or kind == "KeyUp" or kind == "KeyRepeat" then
        return { kind = kind, key = tonumber(e.key.key), mod = tonumber(e.key.mod), timestamp_ns = timestamp_ns }
    end
    if kind == "TextEntered" then
        return { kind = "TextEntered", text = ffi.string(e.text.text), timestamp_ns = timestamp_ns }
    end

    return { kind = "Ignored", timestamp_ns = timestamp_ns }
end

function Backend.poll_sdl_event(runtime)
    error("TODO: SDL raw event -> UiInput.Event requires an explicit ASDL context and belongs above the backend runtime helper", 2)
end

function Backend.swap_window(runtime)
    if not runtime or runtime.window == nil then return end
    local SDL = Backend.FFI
    sdl_ok(SDL.SDL_GL_SwapWindow(runtime.window), "SDL_GL_SwapWindow")
end

function Backend.present_clear(runtime)
    if not runtime or runtime.window == nil then return end
    Backend.sync_window_size(runtime)

    local C = Backend.headers()
    local GL = Backend.GL
    GL.glViewport(0, 0, runtime.state.width, runtime.state.height)
    GL.glMatrixMode(C.GL_PROJECTION)
    GL.glLoadIdentity()
    GL.glOrtho(0.0, runtime.state.width, runtime.state.height, 0.0, -1.0, 1.0)
    GL.glMatrixMode(C.GL_MODELVIEW)
    GL.glLoadIdentity()
    GL.glDisable(C.GL_DEPTH_TEST)
    GL.glDisable(C.GL_SCISSOR_TEST)
    GL.glClearColor(0.12, 0.12, 0.12, 1.0)
    GL.glClear(C.GL_COLOR_BUFFER_BIT)
    Backend.swap_window(runtime)
end

function Backend.window_size(runtime)
    if not runtime or runtime.window == nil then return 0, 0 end
    local SDL = Backend.FFI
    local w = ffi.new("int[1]", 0)
    local h = ffi.new("int[1]", 0)
    sdl_ok(SDL.SDL_GetWindowSize(runtime.window, w, h), "SDL_GetWindowSize")
    return w[0], h[0]
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

function Backend.release_unit(unit)
    if not unit then return end
    if unit.__state and unit.release then
        unit.release(unit.__state)
    end
    unit.__state = nil
end

function Backend.render_unit(runtime, unit)
    Backend.sync_window_size(runtime)

    if runtime.current_unit ~= unit then
        if runtime.current_unit then
            Backend.release_unit(runtime.current_unit)
        end
        runtime.current_unit = unit
    end

    if unit.state_t ~= U.EMPTY then
        if unit.__state == nil then
            unit.__state = terralib.new(unit.state_t)
            if unit.init then unit.init(unit.__state) end
        end
        unit.fn(runtime.state, unit.__state)
    else
        unit.fn(runtime.state)
    end

    Backend.swap_window(runtime)
end

return Backend
