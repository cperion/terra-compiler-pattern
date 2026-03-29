local ffi = require("ffi")
local U = require("unit")

local Backend = {}

if not rawget(_G, "__ui_sdl_gl_luajit_ffi_cdef") then
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
        void glEnable(GLenum cap);
        void glScissor(GLint x, GLint y, GLsizei width, GLsizei height);
        void glClearColor(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
        void glClear(GLbitfield mask);
        void glColor4d(GLdouble red, GLdouble green, GLdouble blue, GLdouble alpha);
        void glBegin(GLenum mode);
        void glVertex2d(GLdouble x, GLdouble y);
        void glTexCoord2d(GLdouble s, GLdouble t);
        void glEnd(void);
        void glLineWidth(GLfloat width);
        void glPushAttrib(GLbitfield mask);
        void glPopAttrib(void);
        void glBlendFunc(GLenum sfactor, GLenum dfactor);
        void glPushMatrix(void);
        void glPopMatrix(void);
        void glMultMatrixd(const GLdouble *m);

        typedef struct {
            int x;
            int y;
            int w;
            int h;
        } UiSdlGlClipRect;

        typedef struct {
            int width;
            int height;
            double opacity;
            int opacity_top;
            double opacity_stack[64];
            int clip_enabled;
            int clip_top;
            int clip_x;
            int clip_y;
            int clip_w;
            int clip_h;
            UiSdlGlClipRect clip_stack[64];
            int clip_enabled_stack[64];
        } UiSdlGlRuntime;
    ]]
    _G.__ui_sdl_gl_luajit_ffi_cdef = true
end

Backend.FFI = ffi.load("SDL3", true)
Backend.GL = ffi.load("GL", true)
Backend.texture_cache = {}

Backend.SDL_INIT_VIDEO = 0x00000020
Backend.SDL_WINDOW_OPENGL = 0x0000000000000002
Backend.SDL_WINDOW_RESIZABLE = 0x0000000000000020
Backend.SDL_WINDOW_HIGH_PIXEL_DENSITY = 0x0000000000002000
Backend.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY = 0x0002

Backend.C = {
    SDL_EVENT_QUIT = 0x100,
    SDL_EVENT_WINDOW_RESIZED = 0x206,
    SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED = 0x207,
    SDL_EVENT_WINDOW_FOCUS_GAINED = 0x20A,
    SDL_EVENT_WINDOW_FOCUS_LOST = 0x20B,
    SDL_EVENT_WINDOW_CLOSE_REQUESTED = 0x20C,
    SDL_EVENT_KEY_DOWN = 0x300,
    SDL_EVENT_KEY_UP = 0x301,
    SDL_EVENT_TEXT_INPUT = 0x303,
    SDL_EVENT_MOUSE_MOTION = 0x400,
    SDL_EVENT_MOUSE_BUTTON_DOWN = 0x401,
    SDL_EVENT_MOUSE_BUTTON_UP = 0x402,
    SDL_EVENT_MOUSE_WHEEL = 0x403,

    SDL_BUTTON_LEFT = 1,
    SDL_BUTTON_MIDDLE = 2,
    SDL_BUTTON_RIGHT = 3,

    SDL_GL_CONTEXT_MAJOR_VERSION = 17,
    SDL_GL_CONTEXT_MINOR_VERSION = 18,
    SDL_GL_CONTEXT_PROFILE_MASK = 20,

    GL_TEXTURE_2D = 0x0DE1,
    GL_TEXTURE_MIN_FILTER = 0x2801,
    GL_TEXTURE_MAG_FILTER = 0x2800,
    GL_NEAREST = 0x2600,
    GL_LINEAR = 0x2601,
    GL_UNPACK_ALIGNMENT = 0x0CF5,
    GL_RGBA = 0x1908,
    GL_UNSIGNED_BYTE = 0x1401,
    GL_PROJECTION = 0x1701,
    GL_MODELVIEW = 0x1700,
    GL_DEPTH_TEST = 0x0B71,
    GL_SCISSOR_TEST = 0x0C11,
    GL_COLOR_BUFFER_BIT = 0x00004000,
    GL_QUADS = 0x0007,
    GL_TRIANGLE_FAN = 0x0006,
    GL_LINE_LOOP = 0x0002,
    GL_BLEND = 0x0BE2,
    GL_SRC_ALPHA = 0x0302,
    GL_ONE_MINUS_SRC_ALPHA = 0x0303,
    GL_ONE = 1,
    GL_DST_COLOR = 0x0306,
    GL_ONE_MINUS_SRC_COLOR = 0x0301,
}

function Backend.headers()
    return Backend.C
end

function Backend.runtime_t()
    return ffi.typeof("UiSdlGlRuntime")
end

function Backend.runtime_state_layout()
    return U.state_ffi("UiSdlGlRuntime")
end

local function sdl_ok(ok, where)
    if ok then return end
    error(("%s: %s"):format(where, ffi.string(Backend.FFI.SDL_GetError())), 3)
end

function Backend.ensure_rgba_texture(key, width, height, pixels, sampling)
    local cached = Backend.texture_cache[key]
    if cached then return cached end

    local C = Backend.headers()
    local GL = Backend.GL
    local tex = ffi.new("GLuint[1]", 0)
    local minmag = (sampling == "Nearest") and C.GL_NEAREST or C.GL_LINEAR
    local buffer = ffi.new("uint8_t[?]", #pixels, pixels)

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

function Backend.init_window(title, width, height)
    local C = Backend.headers()
    local SDL = Backend.FFI

    sdl_ok(SDL.SDL_Init(Backend.SDL_INIT_VIDEO), "SDL_Init")
    sdl_ok(SDL.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MAJOR_VERSION, 2), "SDL_GL_SetAttribute(MAJOR)")
    sdl_ok(SDL.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_MINOR_VERSION, 1), "SDL_GL_SetAttribute(MINOR)")
    sdl_ok(SDL.SDL_GL_SetAttribute(C.SDL_GL_CONTEXT_PROFILE_MASK, Backend.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY), "SDL_GL_SetAttribute(PROFILE)")

    local flags = Backend.SDL_WINDOW_OPENGL
        + Backend.SDL_WINDOW_RESIZABLE
        + Backend.SDL_WINDOW_HIGH_PIXEL_DENSITY

    local window = SDL.SDL_CreateWindow(title or "ui-luajit", width or 1280, height or 720, flags)
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

    local state = ffi.new("UiSdlGlRuntime")
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
        text_input = text_input,
        state = state,
    }
end

function Backend.release_unit(unit)
    if not unit then return end
    if unit.__state and unit.release then
        unit.release(unit.__state)
    elseif unit.__state and unit.state_t and unit.state_t ~= U.EMPTY and unit.state_t.release then
        unit.state_t.release(unit.__state)
    end
    unit.__state = nil
    unit.__payload_keep = nil
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

function Backend.swap_window(runtime)
    if not runtime or runtime.window == nil then return end
    sdl_ok(Backend.FFI.SDL_GL_SwapWindow(runtime.window), "SDL_GL_SwapWindow")
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
            unit.__state = unit.state_t.alloc()
            if unit.init then unit.init(unit.__state) end
        end
        unit.fn(unit.__state, runtime.state)
    else
        unit.fn(nil, runtime.state)
    end

    Backend.swap_window(runtime)
end

return Backend
