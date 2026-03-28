local asdl = require("asdl")
local List = asdl.List

local Schema = require("examples.tasks.tasks_schema")
local RawText = require("examples.ui.backend_text_sdl_ttf")
local Backend = require("examples.ui.backend_sdl_gl")

local T = Schema.ctx

local function now_ns()
    return tonumber(Backend.FFI.SDL_GetTicksNS())
end

local function ms(ns)
    return (ns or 0) / 1000000.0
end

local function getenv_number(name, default)
    local raw = os.getenv(name)
    if raw == nil or raw == "" then return default end
    local n = tonumber(raw)
    return n or default
end

local function getenv_string(name, default)
    local raw = os.getenv(name)
    if raw == nil or raw == "" then return default end
    return raw
end

local function split_csv(raw)
    local out = {}
    raw = raw or ""
    for part in raw:gmatch("[^,]+") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed ~= "" then out[#out + 1] = trimmed end
    end
    return out
end

local function mean(xs)
    if #xs == 0 then return 0 end
    local total = 0
    for i = 1, #xs do total = total + xs[i] end
    return total / #xs
end

local function percentile(xs, p)
    if #xs == 0 then return 0 end
    local copy = {}
    for i = 1, #xs do copy[i] = xs[i] end
    table.sort(copy)
    local idx = math.max(1, math.min(#copy, math.floor((#copy - 1) * p + 1.5)))
    return copy[idx]
end

local function summarize(xs)
    return {
        mean = mean(xs),
        p50 = percentile(xs, 0.50),
        p95 = percentile(xs, 0.95),
        p99 = percentile(xs, 0.99),
        max = percentile(xs, 1.00),
    }
end

local function fmt_stats(xs)
    local s = summarize(xs)
    return ("mean=%.3fms p50=%.3fms p95=%.3fms p99=%.3fms max=%.3fms")
        :format(ms(s.mean), ms(s.p50), ms(s.p95), ms(s.p99), ms(s.max))
end

local function summary_stats(xs)
    local s = summarize(xs)
    return {
        mean_ns = s.mean,
        p50_ns = s.p50,
        p95_ns = s.p95,
        p99_ns = s.p99,
        max_ns = s.max,
    }
end

local function push(slot, value)
    slot[#slot + 1] = value
end

local function is_asdl_node(v)
    local mt = type(v) == "table" and getmetatable(v) or nil
    return mt and type(mt.__fields) == "table"
end

local function node_size(node, memo)
    if not is_asdl_node(node) then return 0 end
    memo = memo or {}
    if memo[node] then return memo[node] end

    local mt = getmetatable(node)
    local total = 1
    for _, field in ipairs(mt.__fields) do
        local value = node[field.name]
        if field.list then
            for _, item in ipairs(value or {}) do
                total = total + node_size(item, memo)
            end
        else
            total = total + node_size(value, memo)
        end
    end

    memo[node] = total
    return total
end

local function compare_reuse(old_node, new_node, memo)
    memo = memo or {}
    if not is_asdl_node(new_node) then
        return { total = 0, reused = 0 }
    end
    if old_node == new_node then
        local size = node_size(new_node, memo)
        return { total = size, reused = size }
    end
    if not is_asdl_node(old_node) then
        return { total = node_size(new_node, memo), reused = 0 }
    end

    local old_mt = getmetatable(old_node)
    local new_mt = getmetatable(new_node)
    if old_mt ~= new_mt then
        return { total = node_size(new_node, memo), reused = 0 }
    end

    local total = 1
    local reused = 0
    for _, field in ipairs(new_mt.__fields) do
        local a = old_node[field.name]
        local b = new_node[field.name]
        if field.list then
            local n = math.max(#(a or {}), #(b or {}))
            for i = 1, n do
                local s = compare_reuse((a or {})[i], (b or {})[i], memo)
                total = total + s.total
                reused = reused + s.reused
            end
        else
            local s = compare_reuse(a, b, memo)
            total = total + s.total
            reused = reused + s.reused
        end
    end
    return { total = total, reused = reused }
end

local function reuse_pct(old_node, new_node)
    local s = compare_reuse(old_node, new_node)
    return s.total == 0 and 0 or (100.0 * s.reused / s.total)
end

local function status_for(i)
    local m = (i - 1) % 4
    if m == 0 then return T.TaskCore.Todo() end
    if m == 1 then return T.TaskCore.InProgress() end
    if m == 2 then return T.TaskCore.Blocked() end
    return T.TaskCore.Done()
end

local function priority_for(i)
    local m = (i - 1) % 4
    if m == 0 then return T.TaskCore.NoPriority() end
    if m == 1 then return T.TaskCore.Low() end
    if m == 2 then return T.TaskCore.Medium() end
    return T.TaskCore.High()
end

local function tag_refs_for(i, tag_count)
    local refs = {}
    refs[#refs + 1] = T.TaskCore.TagRef(((i - 1) % tag_count) + 1)
    if i % 3 == 0 then refs[#refs + 1] = T.TaskCore.TagRef(((i + 1) % tag_count) + 1) end
    if i % 5 == 0 then refs[#refs + 1] = T.TaskCore.TagRef(((i + 3) % tag_count) + 1) end
    return List(refs)
end

local function make_tags(tag_count)
    local colors = {
        T.UiCore.Color(0.46, 0.67, 0.95, 1.0),
        T.UiCore.Color(0.58, 0.83, 0.54, 1.0),
        T.UiCore.Color(0.95, 0.63, 0.34, 1.0),
        T.UiCore.Color(0.84, 0.54, 0.95, 1.0),
        T.UiCore.Color(0.96, 0.80, 0.35, 1.0),
        T.UiCore.Color(0.35, 0.84, 0.83, 1.0),
    }
    local out = {}
    for i = 1, tag_count do
        out[#out + 1] = T.TaskDoc.Tag(
            T.TaskCore.TagRef(i),
            "tag-" .. tostring(i),
            colors[((i - 1) % #colors) + 1]
        )
    end
    return List(out)
end

local function task_title(i)
    return ("Task %d · Ship a cleaner compiler-shaped UI slice"):format(i)
end

local function task_notes(i)
    return (
        "This benchmark task exists to exercise text layout, list rows, detail panes, tags, and wrapping. " ..
        "Iteration %d verifies that the UI pipeline keeps behaving like a compiler and not an interpreter."
    ):format(i)
end

local function make_workspace(task_count, project_count, tag_count)
    local projects = {}
    local task_id = 1
    for p = 1, project_count do
        local tasks = {}
        local project_tasks = math.floor(task_count / project_count)
        if p <= (task_count % project_count) then
            project_tasks = project_tasks + 1
        end
        for _ = 1, project_tasks do
            tasks[#tasks + 1] = T.TaskDoc.Task(
                T.TaskCore.TaskRef(task_id),
                task_title(task_id),
                task_notes(task_id),
                status_for(task_id),
                priority_for(task_id),
                tag_refs_for(task_id, tag_count)
            )
            task_id = task_id + 1
        end
        projects[#projects + 1] = T.TaskDoc.Project(
            T.TaskCore.ProjectRef(p),
            p == 1 and "Inbox" or ("Project " .. tostring(p)),
            false,
            List(tasks)
        )
    end

    return T.TaskDoc.Workspace(
        1,
        "Terra Tasks Bench",
        List(projects),
        make_tags(tag_count)
    )
end

local function draft_for(tag_count)
    return T.TaskSession.Draft(
        "A newly captured task with a title long enough to wrap cleanly in the modal",
        "These draft notes intentionally span multiple sentences so the modal benchmark exercises wrapped text and a larger editor subtree.",
        T.TaskCore.InProgress(),
        T.TaskCore.High(),
        List {
            T.TaskCore.TagRef(1),
            T.TaskCore.TagRef(math.min(2, tag_count))
        }
    )
end

local function make_session(project_ref, task_ref, scenario, tag_count)
    local selection = task_ref
        and T.TaskSession.TaskSelected(project_ref, task_ref)
        or T.TaskSession.ProjectSelected(project_ref)

    local editor = (scenario == "modal")
        and T.TaskSession.CreatingTask(project_ref, draft_for(tag_count))
        or T.TaskSession.NoEditor()

    return T.TaskSession.State(
        selection,
        T.TaskSession.Filter("", List(), List(), true),
        T.TaskCore.ManualOrder(),
        editor
    )
end

local function make_state(task_count, scenario, project_count, tag_count, selected_task_value)
    local workspace = make_workspace(task_count, project_count, tag_count)
    local project_ref = workspace.projects[1].id
    local selected_task = selected_task_value and T.TaskCore.TaskRef(selected_task_value) or nil
    return T.TaskApp.State(
        workspace,
        make_session(project_ref, selected_task, scenario, tag_count),
        true
    )
end

local function materialize(state, assets, viewport)
    local t0 = now_ns()
    local screen = state:project_view()
    local t1 = now_ns()
    local document = screen:lower()
    local t2 = now_ns()
    local laid = document:layout(assets, viewport)
    local t3 = now_ns()
    local routed = laid:route()
    local t4 = now_ns()
    local batched = laid:batch()
    local t5 = now_ns()

    return {
        screen = screen,
        document = document,
        laid = laid,
        routed = routed,
        batched = batched,
        times = {
            project_view = t1 - t0,
            lower = t2 - t1,
            layout = t3 - t2,
            route = t4 - t3,
            batch = t5 - t4,
            total = t5 - t0,
        }
    }
end

local function print_scene_header(scene_name, task_count, viewport, warmup, iters)
    print(("scene=%s tasks=%d viewport=%dx%d warmup=%d iters=%d")
        :format(scene_name, task_count, viewport.w, viewport.h, warmup, iters))
end

local function parse_summary_line(line)
    if not line:match("^BENCH_SUMMARY%s") then return nil end
    local out = {}
    for key, value in line:gmatch("([%w_]+)=([^%s]+)") do
        local num = tonumber(value)
        out[key] = num or value
    end
    return out
end

local function print_bench_summary_line(summary)
    local keys = {}
    for key in pairs(summary) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = { "BENCH_SUMMARY" }
    for _, key in ipairs(keys) do
        parts[#parts + 1] = key .. "=" .. tostring(summary[key])
    end
    print(table.concat(parts, " "))
end

local function ratio_value(num, den)
    if den == nil or den <= 0 then return nil end
    return num / den
end

local function ratio_text(v)
    return v and ("%.1fx"):format(v) or "n/a"
end

local function run_external_clay(scene_name, task_count, viewport, warmup, iters, project_count, tag_count)
    local clay_cmd = os.getenv("BENCH_CLAY_CMD")
    if clay_cmd == nil or clay_cmd == "" then return end

    local shell = table.concat({
        "BENCH_SCENARIO=" .. string.format("%q", scene_name),
        "BENCH_TASKS=" .. tostring(task_count),
        "BENCH_VIEW_W=" .. tostring(viewport.w),
        "BENCH_VIEW_H=" .. tostring(viewport.h),
        "BENCH_WARMUP=" .. tostring(warmup),
        "BENCH_ITERS=" .. tostring(iters),
        "BENCH_PROJECTS=" .. tostring(project_count),
        "BENCH_TAGS=" .. tostring(tag_count),
        clay_cmd,
    }, " ")

    print("  clay command: " .. clay_cmd)
    local pipe = io.popen(shell .. " 2>&1")
    if not pipe then
        print("  clay: failed to launch BENCH_CLAY_CMD")
        return
    end

    local output = pipe:read("*a") or ""
    pipe:close()
    if output == "" then
        print("  clay: (no output)")
        return
    end

    output = output:gsub("%s+$", "")
    local summaries = {}
    for line in output:gmatch("[^\n]+") do
        print("  clay: " .. line)
        local summary = parse_summary_line(line)
        if summary and summary.mode then
            summaries[summary.mode] = summary
        end
    end
    return summaries
end

local function print_shape_counts(result)
    print((
        "  nodes screen=%d document=%d laid=%d batched=%d"
    ):format(
        node_size(result.screen),
        node_size(result.document),
        node_size(result.laid),
        node_size(result.batched)
    ))
end

local function print_phase_stats(prefix, phase_samples)
    print(("  %s project_view %s"):format(prefix, fmt_stats(phase_samples.project_view)))
    print(("  %s lower       %s"):format(prefix, fmt_stats(phase_samples.lower)))
    print(("  %s layout      %s"):format(prefix, fmt_stats(phase_samples.layout)))
    print(("  %s route       %s"):format(prefix, fmt_stats(phase_samples.route)))
    print(("  %s batch       %s"):format(prefix, fmt_stats(phase_samples.batch)))
    print(("  %s total       %s"):format(prefix, fmt_stats(phase_samples.total)))
end

local function benchmark_full_rebuild(task_count, scenario, assets, viewport, warmup, iters, project_count, tag_count)
    for i = 1, warmup do
        local state = make_state(task_count, scenario, project_count, tag_count, ((i - 1) % math.max(task_count, 1)) + 1)
        materialize(state, assets, viewport)
    end

    local samples = {
        project_view = {},
        lower = {},
        layout = {},
        route = {},
        batch = {},
        total = {},
    }

    local first_result = nil
    for i = 1, iters do
        local state = make_state(task_count, scenario, project_count, tag_count, ((i - 1) % math.max(task_count, 1)) + 1)
        local result = materialize(state, assets, viewport)
        if not first_result then first_result = result end
        for k, v in pairs(result.times) do push(samples[k], v) end
    end

    print("  mode=full-rebuild")
    print_shape_counts(first_result)
    print_phase_stats("full", samples)

    local total = summary_stats(samples.total)
    local summary = {
        engine = "terra",
        scene = scenario,
        tasks = task_count,
        mode = "full-rebuild",
        total_mean_ns = total.mean_ns,
        total_p50_ns = total.p50_ns,
        total_p95_ns = total.p95_ns,
        total_p99_ns = total.p99_ns,
        total_max_ns = total.max_ns,
        nodes_screen = node_size(first_result.screen),
        nodes_document = node_size(first_result.document),
        nodes_laid = node_size(first_result.laid),
        nodes_batched = node_size(first_result.batched),
    }
    print_bench_summary_line(summary)
    return summary
end

local function incremental_event(i, scenario)
    if scenario == "modal" then
        if i % 2 == 1 then
            return T.TaskEvent.UpdateDraftTitle(("Draft title edit %d keeps moving"):format(i))
        end
        return T.TaskEvent.UpdateDraftNotes((
            "Draft notes edit %d mutates one field while leaving most of the document structurally shared."
        ):format(i))
    end

    return T.TaskEvent.SelectTask(T.TaskCore.TaskRef((i % 2) + 1))
end

local function benchmark_incremental(task_count, scenario, assets, viewport, warmup, iters, project_count, tag_count)
    local base_selected = math.min(2, math.max(1, task_count))
    local state = make_state(task_count, scenario, project_count, tag_count, base_selected)
    local prev = materialize(state, assets, viewport)

    for i = 1, warmup do
        state = state:apply(incremental_event(i, scenario))
        prev = materialize(state, assets, viewport)
    end

    local apply_samples = {}
    local phase_samples = {
        project_view = {},
        lower = {},
        layout = {},
        route = {},
        batch = {},
        total = {},
    }
    local reuse_samples = {
        screen = {},
        document = {},
        laid = {},
        batched = {},
    }

    for i = 1, iters do
        local t0 = now_ns()
        state = state:apply(incremental_event(i + warmup, scenario))
        local t1 = now_ns()
        local next = materialize(state, assets, viewport)

        push(apply_samples, t1 - t0)
        for k, v in pairs(next.times) do push(phase_samples[k], v) end
        push(reuse_samples.screen, reuse_pct(prev.screen, next.screen))
        push(reuse_samples.document, reuse_pct(prev.document, next.document))
        push(reuse_samples.laid, reuse_pct(prev.laid, next.laid))
        push(reuse_samples.batched, reuse_pct(prev.batched, next.batched))
        prev = next
    end

    print("  mode=incremental-edit")
    print(("  incr apply       %s"):format(fmt_stats(apply_samples)))
    print_phase_stats("incr", phase_samples)
    local reuse_screen = mean(reuse_samples.screen)
    local reuse_document = mean(reuse_samples.document)
    local reuse_laid = mean(reuse_samples.laid)
    local reuse_batched = mean(reuse_samples.batched)
    print((
        "  reuse screen=%.1f%% document=%.1f%% laid=%.1f%% batched=%.1f%%"
    ):format(
        reuse_screen,
        reuse_document,
        reuse_laid,
        reuse_batched
    ))

    local apply = summary_stats(apply_samples)
    local total = summary_stats(phase_samples.total)
    local summary = {
        engine = "terra",
        scene = scenario,
        tasks = task_count,
        mode = "incremental-edit",
        apply_mean_ns = apply.mean_ns,
        apply_p50_ns = apply.p50_ns,
        apply_p95_ns = apply.p95_ns,
        apply_p99_ns = apply.p99_ns,
        apply_max_ns = apply.max_ns,
        total_mean_ns = total.mean_ns,
        total_p50_ns = total.p50_ns,
        total_p95_ns = total.p95_ns,
        total_p99_ns = total.p99_ns,
        total_max_ns = total.max_ns,
        reuse_screen_pct = reuse_screen,
        reuse_document_pct = reuse_document,
        reuse_laid_pct = reuse_laid,
        reuse_batched_pct = reuse_batched,
    }
    print_bench_summary_line(summary)
    return summary
end

local function main()
    local font_path = getenv_string("BENCH_FONT", "/usr/share/fonts/liberation-sans-fonts/LiberationSans-Regular.ttf")
    local viewport = T.UiCore.Size(
        getenv_number("BENCH_VIEW_W", 1100),
        getenv_number("BENCH_VIEW_H", 760)
    )
    local warmup = getenv_number("BENCH_WARMUP", 3)
    local iters = getenv_number("BENCH_ITERS", 20)
    local project_count = getenv_number("BENCH_PROJECTS", 1)
    local tag_count = getenv_number("BENCH_TAGS", 6)
    local task_counts_raw = split_csv(getenv_string("BENCH_TASK_COUNTS", "100,1000,5000"))
    local scenarios = split_csv(getenv_string("BENCH_SCENARIOS", "list,modal"))

    local task_counts = {}
    for _, raw in ipairs(task_counts_raw) do
        task_counts[#task_counts + 1] = tonumber(raw)
    end

    local font = T.UiCore.FontRef(1)
    local assets = T.UiAsset.Catalog(
        font,
        List { T.UiAsset.FontAsset(font, font_path) },
        List()
    )

    RawText.init(nil)

    print("ui benchmark: TaskApp.State -> TaskView.Screen -> UiDecl.Document -> UiLaid.Scene -> UiBatched.Scene")
    print("clay note: this file defines the scene + timing points for a fair clay.h comparison; it currently benchmarks our side directly.")
    print(("font=%s"):format(font_path))
    print("")

    for _, scenario in ipairs(scenarios) do
        for _, task_count in ipairs(task_counts) do
            print_scene_header(scenario, task_count, viewport, warmup, iters)
            local terra_full = benchmark_full_rebuild(task_count, scenario, assets, viewport, warmup, iters, project_count, tag_count)
            local terra_incr = benchmark_incremental(task_count, scenario, assets, viewport, warmup, iters, project_count, tag_count)
            local clay = run_external_clay(scenario, task_count, viewport, warmup, iters, project_count, tag_count)
            if clay and clay["full-rebuild"] and clay["incremental-edit"] then
                local clay_full = clay["full-rebuild"]
                local clay_incr = clay["incremental-edit"]
                local full_ratio = ratio_value(terra_full.total_mean_ns, clay_full.total_mean_ns)
                local incr_ratio = ratio_value(terra_incr.total_mean_ns, clay_incr.total_mean_ns)
                local apply_ratio = ratio_value(terra_incr.apply_mean_ns, clay_incr.apply_mean_ns)
                print((
                    "  ratio total terra/clay full=%s incr=%s apply=%s"
                ):format(
                    ratio_text(full_ratio),
                    ratio_text(incr_ratio),
                    ratio_text(apply_ratio)
                ))
                local summary = {
                    engine = "comparison",
                    scene = scenario,
                    tasks = task_count,
                    mode = "ratio",
                }
                if full_ratio then summary.full_total_ratio = full_ratio end
                if incr_ratio then summary.incr_total_ratio = incr_ratio end
                if apply_ratio then summary.incr_apply_ratio = apply_ratio end
                print_bench_summary_line(summary)
            end
            print("")
        end
    end

    RawText.shutdown(nil)
end

main()
