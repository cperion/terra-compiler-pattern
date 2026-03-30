local U = require("unit")

local int32 = terralib.types.int32
local double = terralib.types.double

local Layer0 = {}

local function stateful_unit(fn, state_t, init, release)
    local unit = U.new(fn, state_t)
    unit.init = init
    unit.release = release
    return unit
end

local function clear_runner(backend)
    local Runtime = backend.runtime_t()
    local C = backend.headers()

    local runner = terra(rt : &Runtime)
        rt.opacity = 1.0
        rt.opacity_top = 0
        rt.clip_enabled = 0
        rt.clip_top = 0

        C.glViewport(0, 0, rt.width, rt.height)
        C.glMatrixMode(C.GL_PROJECTION)
        C.glLoadIdentity()
        C.glOrtho(0.0, [double](rt.width), [double](rt.height), 0.0, -1.0, 1.0)
        C.glMatrixMode(C.GL_MODELVIEW)
        C.glLoadIdentity()
        C.glDisable(C.GL_DEPTH_TEST)
        C.glDisable(C.GL_SCISSOR_TEST)
        C.glClearColor(0.12, 0.12, 0.12, 1.0)
        C.glClear(C.GL_COLOR_BUFFER_BIT)
    end
    runner:compile()
    return U.new(runner, U.EMPTY)
end

function Layer0.new_clear_unit(backend)
    return clear_runner(backend)
end

function Layer0.new_box_unit(backend, box_count)
    box_count = math.max(0, math.floor(tonumber(box_count) or 0))

    local Runtime = backend.runtime_t()
    local C = backend.headers()

    local item_count = math.max(1, box_count)

    local BoxItem = terralib.types.newstruct("Ui3Layer0BoxItem_" .. tostring(box_count))
    BoxItem.entries:insert({ field = "x", type = double })
    BoxItem.entries:insert({ field = "y", type = double })
    BoxItem.entries:insert({ field = "w", type = double })
    BoxItem.entries:insert({ field = "h", type = double })
    BoxItem.entries:insert({ field = "r", type = double })
    BoxItem.entries:insert({ field = "g", type = double })
    BoxItem.entries:insert({ field = "b", type = double })
    BoxItem.entries:insert({ field = "a", type = double })

    local State = terralib.types.newstruct("Ui3Layer0BoxState_" .. tostring(box_count))
    State.entries:insert({ field = "phase", type = double })
    State.entries:insert({ field = "items", type = BoxItem[item_count] })

    local cols = math.max(1, math.floor(math.sqrt(math.max(1, box_count))))

    local init = terra(state : &State)
        state.phase = 0.0
        var i : int32 = 0
        while i < [int32](box_count) do
            var col = i % [int32](cols)
            var row = i / [int32](cols)
            state.items[i].x = 16.0 + [double](col) * 18.0
            state.items[i].y = 16.0 + [double](row) * 18.0
            state.items[i].w = 12.0
            state.items[i].h = 12.0
            state.items[i].r = 0.15 + [double](i % 7) * 0.09
            state.items[i].g = 0.25 + [double](i % 5) * 0.11
            state.items[i].b = 0.35 + [double](i % 3) * 0.14
            state.items[i].a = 0.90
            i = i + 1
        end
    end
    init:compile()

    local draw_box = terra(rt : &Runtime, item : &BoxItem, phase : double)
        var dx = item.x + phase
        C.glColor4d(item.r, item.g, item.b, item.a * rt.opacity)
        C.glBegin(C.GL_QUADS)
        C.glVertex2d(dx, item.y)
        C.glVertex2d(dx + item.w, item.y)
        C.glVertex2d(dx + item.w, item.y + item.h)
        C.glVertex2d(dx, item.y + item.h)
        C.glEnd()
    end
    draw_box:compile()

    local runner = terra(rt : &Runtime, state : &State)
        rt.opacity = 1.0
        rt.opacity_top = 0
        rt.clip_enabled = 0
        rt.clip_top = 0

        C.glViewport(0, 0, rt.width, rt.height)
        C.glMatrixMode(C.GL_PROJECTION)
        C.glLoadIdentity()
        C.glOrtho(0.0, [double](rt.width), [double](rt.height), 0.0, -1.0, 1.0)
        C.glMatrixMode(C.GL_MODELVIEW)
        C.glLoadIdentity()
        C.glDisable(C.GL_DEPTH_TEST)
        C.glDisable(C.GL_SCISSOR_TEST)
        C.glClearColor(0.08, 0.08, 0.10, 1.0)
        C.glClear(C.GL_COLOR_BUFFER_BIT)

        var i : int32 = 0
        while i < [int32](box_count) do
            draw_box(rt, &(state.items[i]), state.phase)
            i = i + 1
        end

        state.phase = state.phase + 0.25
        if state.phase > 10.0 then
            state.phase = 0.0
        end
    end
    runner:compile()

    return stateful_unit(runner, State, init, nil)
end

return Layer0
