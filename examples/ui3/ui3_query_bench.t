local asdl = require("asdl")
local L = asdl.List
local Backend = require("examples.ui.backends.terra_sdl_gl")
local Schema = require("unit").load_inspect_spec("examples/ui3")

local T = Schema.ctx

local function C(ctor, ...)
    if type(ctor) == "cdata" then return ctor end
    return ctor(...)
end

local function getenv_number(name, default)
    local raw = os.getenv(name)
    if not raw or raw == "" then return default end
    local n = tonumber(raw)
    if not n then return default end
    return n
end

local function now_ns()
    return tonumber(Backend.FFI.SDL_GetTicksNS())
end

local function ms_between(t0, t1)
    return (t1 - t0) / 1000000.0
end

local function bench_avg_ms(iters, fn)
    local t0 = now_ns()
    for _ = 1, iters do fn() end
    local t1 = now_ns()
    return ms_between(t0, t1) / iters
end

local function size(w, h)
    return T.UiCore.Size(w, h)
end

local function font_ref(n)
    return T.UiCore.FontRef(n)
end

local function build_assets()
    local font = font_ref(1)
    return T.UiAsset.Catalog(
        font,
        L {
            T.UiAsset.FontAsset(font, "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf")
        },
        L {}
    )
end

local function layout(position, flow, gap)
    return T.UiBound.Layout(
        T.UiDecl.Layout(
            T.UiCore.SizeSpec(C(T.UiCore.Auto), C(T.UiCore.Auto), C(T.UiCore.Auto)),
            T.UiCore.SizeSpec(C(T.UiCore.Auto), C(T.UiCore.Auto), C(T.UiCore.Auto)),
            C(T.UiCore.InFlow),
            flow or C(T.UiCore.None),
            nil,
            nil,
            C(T.UiCore.Start),
            C(T.UiCore.CrossStart),
            T.UiCore.Insets(0, 0, 0, 0),
            T.UiCore.Insets(0, 0, 0, 0),
            gap or 0,
            C(T.UiCore.Visible),
            C(T.UiCore.Visible),
            nil
        ),
        position
    )
end

local function node_header(index, id, debug_name, role, parent_index, first_child_index, child_count, subtree_count, semantic_ref)
    return T.UiFlatShape.NodeHeader(
        index,
        parent_index,
        first_child_index,
        child_count or 0,
        subtree_count or 1,
        T.UiCore.ElementId(id),
        semantic_ref,
        debug_name,
        role
    )
end

local function hidden_accessibility()
    return T.UiFlat.AccessibilityFacet(C(T.UiBound.Hidden))
end

local function no_content()
    return T.UiFlat.ContentFacet(C(T.UiBound.NoContent))
end

local function no_paint()
    return T.UiFlat.PaintFacet(T.UiDecl.Paint(L {}))
end

local function behavior_source(hit, focus, pointer, scroll, keys, edit, drag_drop)
    return T.UiFlat.BehaviorFacet(
        T.UiDecl.Behavior(
            hit,
            focus,
            L(pointer or {}),
            scroll,
            L(keys or {}),
            edit,
            L(drag_drop or {})
        )
    )
end

local function append_node(rows, role, debug_name, position, flow, gap, visible, enabled, behavior, accessibility, parent_index, first_child_index, child_count, subtree_count)
    local index = #rows.headers
    rows.headers[#rows.headers + 1] = node_header(
        index,
        rows.node_id_base + index,
        debug_name,
        role,
        parent_index,
        first_child_index,
        child_count,
        subtree_count,
        T.UiCore.SemanticRef(7, rows.node_id_base + index)
    )
    rows.visibility[#rows.visibility + 1] = T.UiFlat.VisibilityFacet(visible)
    rows.interactivity[#rows.interactivity + 1] = T.UiFlat.InteractivityFacet(enabled)
    rows.layout[#rows.layout + 1] = T.UiFlat.LayoutFacet(layout(position, flow, gap))
    rows.content[#rows.content + 1] = no_content()
    rows.paint[#rows.paint + 1] = no_paint()
    rows.behavior[#rows.behavior + 1] = behavior
    rows.accessibility[#rows.accessibility + 1] = accessibility
end

local function default_behavior()
    return behavior_source(C(T.UiDecl.HitNone), C(T.UiDecl.NotFocusable), {}, nil, {}, nil, {})
end

local function hit_press_behavior(i)
    return behavior_source(
        C(T.UiDecl.HitSelf),
        C(T.UiDecl.NotFocusable),
        {
            T.UiDecl.Press(C(T.UiCore.Primary), 1, T.UiCore.CommandRef(1000 + i))
        },
        nil,
        {},
        nil,
        {}
    )
end

local function focus_key_behavior(i)
    return behavior_source(
        C(T.UiDecl.HitSelf),
        T.UiDecl.Focusable(C(T.UiCore.ClickFocus), i),
        {
            T.UiDecl.Hover(nil, T.UiCore.CommandRef(2000 + i), T.UiCore.CommandRef(3000 + i))
        },
        nil,
        {
            T.UiDecl.KeyRule(
                T.UiCore.KeyChord(false, false, false, false, 13 + (i % 3)),
                C(T.UiCore.KeyDown),
                T.UiCore.CommandRef(4000 + i),
                (i % 2) == 0
            )
        },
        nil,
        {}
    )
end

local function scroll_drag_behavior(i)
    return behavior_source(
        C(T.UiDecl.HitSelfAndChildren),
        C(T.UiDecl.NotFocusable),
        {},
        T.UiDecl.ScrollRule(C(T.UiCore.Vertical), T.UiCore.ScrollRef(5000 + i)),
        {},
        nil,
        {
            T.UiDecl.Draggable(
                T.UiCore.Opaque(11, 6000 + i),
                T.UiCore.CommandRef(7000 + i),
                T.UiCore.CommandRef(8000 + i)
            )
        }
    )
end

local function edit_behavior(i)
    return behavior_source(
        C(T.UiDecl.HitSelf),
        T.UiDecl.Focusable(C(T.UiCore.TextFocus), i),
        {},
        nil,
        {},
        T.UiDecl.EditRule(T.UiCore.TextModelRef(9000 + i), false, false, T.UiCore.CommandRef(9100 + i)),
        {}
    )
end

local function exposed_accessibility(i)
    return T.UiFlat.AccessibilityFacet(
        T.UiBound.Exposed(C(T.UiCore.AccButton), "item-" .. tostring(i), nil, i)
    )
end

local function add_root(rows, scenario, child_count)
    local flow = (scenario == "focuskeys" and C(T.UiCore.Row)) or C(T.UiCore.Column)
    append_node(
        rows,
        C(T.UiCore.View),
        "root",
        C(T.UiBound.InFlow),
        flow,
        4,
        true,
        true,
        default_behavior(),
        hidden_accessibility(),
        nil,
        1,
        child_count,
        1 + child_count
    )
end

local function child_spec_for(i, scenario)
    if scenario == "hits" then
        return {
            role = C(T.UiCore.View),
            position = C(T.UiBound.InFlow),
            visible = true,
            enabled = true,
            behavior = hit_press_behavior(i),
            accessibility = hidden_accessibility(),
        }
    end

    if scenario == "focuskeys" then
        return {
            role = C(T.UiCore.View),
            position = C(T.UiBound.InFlow),
            visible = true,
            enabled = true,
            behavior = focus_key_behavior(i),
            accessibility = exposed_accessibility(i),
        }
    end

    local k = i % 5
    return {
        role = (k == 3) and C(T.UiCore.InputField) or C(T.UiCore.View),
        position = (k == 4) and T.UiBound.Absolute(T.UiCore.EdgePx(12 + (i % 20)), T.UiCore.EdgePx(8 + (i % 16)), C(T.UiCore.Unset), C(T.UiCore.Unset)) or C(T.UiBound.InFlow),
        visible = (i % 11) ~= 0,
        enabled = (i % 7) ~= 0,
        behavior = ({
            hit_press_behavior(i),
            focus_key_behavior(i),
            scroll_drag_behavior(i),
            edit_behavior(i),
            default_behavior(),
        })[k + 1],
        accessibility = (k == 1 or k == 3) and exposed_accessibility(i) or hidden_accessibility(),
    }
end

local function build_flat(box_count, scenario, seed, width, height)
    local root_id = 970000 + seed * 10000
    local rows = {
        node_id_base = root_id + 1000,
        headers = {},
        visibility = {},
        interactivity = {},
        layout = {},
        content = {},
        paint = {},
        behavior = {},
        accessibility = {},
    }

    add_root(rows, scenario, box_count)

    local i = 0
    while i < box_count do
        local spec = child_spec_for(i, scenario)
        append_node(
            rows,
            spec.role,
            "item",
            spec.position,
            C(T.UiCore.None),
            0,
            spec.visible,
            spec.enabled,
            spec.behavior,
            spec.accessibility,
            0
        )
        i = i + 1
    end

    return T.UiFlat.Scene(
        size(width, height),
        L {
            T.UiFlat.Region(
                T.UiFlatShape.RegionHeader(T.UiCore.ElementId(root_id), scenario, 0),
                T.UiFlat.RenderRegionFacet(0),
                T.UiFlat.QueryRegionFacet(scenario == "mixed", scenario ~= "hits"),
                L(rows.headers),
                L(rows.visibility),
                L(rows.interactivity),
                L(rows.layout),
                L(rows.content),
                L(rows.paint),
                L(rows.behavior),
                L(rows.accessibility)
            )
        }
    )
end

local width = getenv_number("UI3_QUERY_WIDTH", 1280)
local height = getenv_number("UI3_QUERY_HEIGHT", 720)
local warmup = math.max(0, math.floor(getenv_number("UI3_QUERY_WARMUP", 5)))
local iters = math.max(1, math.floor(getenv_number("UI3_QUERY_ITERS", 60)))
local box_count = math.max(0, math.floor(getenv_number("UI3_QUERY_BOXES", 1000)))
local scenario = os.getenv("UI3_QUERY_SCENARIO") or "mixed"
local assets = build_assets()

local seq = 0
local function fresh_flat()
    seq = seq + 1
    return build_flat(box_count, scenario, seq, width, height)
end

local flat = fresh_flat()
local geometry = flat:lower_geometry(assets):solve()

local build_scene_avg_ms = bench_avg_ms(iters, function()
    fresh_flat()
end)

local lower_t0 = now_ns()
local query_facts = flat:lower_query_facts()
local lower_query_ms = ms_between(lower_t0, now_ns())

local lower_query_existing_scene_avg_ms = bench_avg_ms(iters, function()
    flat:lower_query_facts()
end)

local build_plus_lower_query_avg_ms = bench_avg_ms(iters, function()
    fresh_flat():lower_query_facts()
end)

local project_t0 = now_ns()
local query_scene = geometry:project_query_scene(query_facts)
local project_query_ms = ms_between(project_t0, now_ns())

local project_query_existing_inputs_avg_ms = bench_avg_ms(iters, function()
    geometry:project_query_scene(query_facts)
end)

local build_plus_project_query_avg_ms = bench_avg_ms(iters, function()
    local built = fresh_flat()
    local built_geometry = built:lower_geometry(assets):solve()
    local built_facts = built:lower_query_facts()
    built_geometry:project_query_scene(built_facts)
end)

local organize_t0 = now_ns()
local query_ir = query_scene:organize_query_machine_ir()
local organize_query_ms = ms_between(organize_t0, now_ns())

local organize_existing_scene_avg_ms = bench_avg_ms(iters, function()
    query_scene:organize_query_machine_ir()
end)

local build_plus_organize_query_avg_ms = bench_avg_ms(iters, function()
    local built = fresh_flat()
    local built_geometry = built:lower_geometry(assets):solve()
    local built_facts = built:lower_query_facts()
    local built_scene = built_geometry:project_query_scene(built_facts)
    built_scene:organize_query_machine_ir()
end)

for _ = 1, warmup do
    query_scene:organize_query_machine_ir()
end

print(string.format(
    "ui3 query bench scenario=%s width=%d height=%d warmup=%d iters=%d boxes=%d",
    scenario,
    width,
    height,
    warmup,
    iters,
    box_count
))
print(string.format("  build_scene_avg_ms: %.3f", build_scene_avg_ms))
print(string.format("  lower_query_ms: %.3f", lower_query_ms))
print(string.format("  lower_query_existing_scene_avg_ms: %.3f", lower_query_existing_scene_avg_ms))
print(string.format("  build_plus_lower_query_avg_ms: %.3f", build_plus_lower_query_avg_ms))
print(string.format("  project_query_ms: %.3f", project_query_ms))
print(string.format("  project_query_existing_inputs_avg_ms: %.3f", project_query_existing_inputs_avg_ms))
print(string.format("  build_plus_project_query_avg_ms: %.3f", build_plus_project_query_avg_ms))
print(string.format("  organize_query_ms: %.3f", organize_query_ms))
print(string.format("  organize_existing_scene_avg_ms: %.3f", organize_existing_scene_avg_ms))
print(string.format("  build_plus_organize_query_avg_ms: %.3f", build_plus_organize_query_avg_ms))
print(string.format("  regions: %d", #query_ir.input.regions))
print(string.format("  hits: %d", #query_ir.input.hits))
print(string.format("  focus: %d", #query_ir.input.focus))
print(string.format("  focus_order: %d", #query_ir.input.focus_order))
print(string.format("  key_buckets: %d", #query_ir.input.key_buckets))
print(string.format("  key_routes: %d", #query_ir.input.key_routes))
print(string.format("  scroll_hosts: %d", #query_ir.input.scroll_hosts))
print(string.format("  edit_hosts: %d", #query_ir.input.edit_hosts))
print(string.format("  accessibility: %d", #query_ir.input.accessibility))
