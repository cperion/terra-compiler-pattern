#!/usr/bin/env luajit

package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    package.path,
}, ";")

local F = require("more-fun")

local function same_array(a, b)
    assert(#a == #b, string.format("length mismatch: %d ~= %d", #a, #b))
    for i = 1, #a do
        assert(a[i] == b[i], string.format("mismatch at %d: %s ~= %s", i, tostring(a[i]), tostring(b[i])))
    end
end

local function test_range_map_filter_collect()
    local xs = F.range(1, 10)
        :map(function(x) return x * 2 end)
        :filter(function(x) return x % 4 == 0 end)
        :collect()

    same_array(xs, { 4, 8, 12, 16, 20 })
end

local function test_take_drop_order()
    local xs = F.from({ 10, 20, 30, 40, 50, 60 })
        :skip(2)
        :take(3)
        :collect()

    same_array(xs, { 30, 40, 50 })
end

local function test_fold_sum_and_count()
    local it = F.from({ 1, 2, 3, 4 })
        :map(function(x) return x + 1 end)

    assert(it:fold(function(acc, x) return acc + x end, 0) == 14)
    assert(it:sum() == 14)
    assert(it:count() == 4)
end

local function test_min_max_and_reuse()
    local it = F.of(7, 2, 9, 4, 1, 8)

    assert(it:min() == 1)
    assert(it:max() == 9)
    assert(it:min() == 1)
    assert(it:max() == 9)
end

local function test_head_nth_any_all()
    local it = F.range(1, 20)
        :filter(function(x) return x % 3 == 0 end)

    assert(it:head() == 3)
    assert(it:nth(3) == 9)
    assert(it:any(function(x) return x == 12 end) == true)
    assert(it:any(function(x) return x == 11 end) == false)
    assert(it:all(function(x) return x % 3 == 0 end) == true)
    assert(it:all(function(x) return x < 10 end) == false)
end

local function test_chain_respects_global_take()
    local xs = F.concat(
        F.of(1, 2, 3),
        F.of(4, 5, 6),
        F.range(7, 9)
    ):take(5):collect()

    same_array(xs, { 1, 2, 3, 4, 5 })
end

local function test_chain_terminal_compilation()
    local it = F.chain(
        F.of(1, 2, 3):map(function(x) return x * 2 end),
        F.range(4, 6),
        F.of(7, 8)
    ):filter(function(x) return x % 2 == 0 end)

    assert(it:sum() == 30)
    assert(it:head() == 2)
    assert(it:nth(3) == 6)
    assert(it:any(function(x) return x == 8 end) == true)
    assert(it:all(function(x) return x % 2 == 0 end) == true)
    assert(it:min() == 2)
    assert(it:max() == 8)
end

local function test_generate_source()
    local function gen(param, state)
        state = state + 1
        if state > #param then
            return nil
        end
        return state, param[state] * 3
    end

    local xs = F.generate(gen, { 1, 2, 3, 4 }, 0):collect()
    same_array(xs, { 3, 6, 9, 12 })
end

local function test_chars_source()
    local xs = F.chars("abcd")
        :drop(1)
        :take(2)
        :collect()

    same_array(xs, { "b", "c" })
end

local function test_plain_string_terminals()
    local it = F.chars("dbca")

    assert(it:head() == "d")
    assert(it:nth(3) == "c")
    assert(it:any(function(x) return x == "c" end) == true)
    assert(it:all(function(x) return x >= "a" end) == true)
    assert(it:min() == "a")
    assert(it:max() == "d")
end

local function test_argful_terminal_cache_reuses_compiled_executor()
    local it = F.of(1, 2, 3, 4)

    assert(it:any(function(x) return x == 4 end) == true)
    local any_exec = it._terminal_cache.any
    assert(type(any_exec) == "function")

    assert(it:any(function(x) return x == 5 end) == false)
    assert(it._terminal_cache.any == any_exec)

    assert(it:fold(function(acc, x) return acc + x end, 0) == 10)
    local fold_exec = it._terminal_cache.fold
    assert(type(fold_exec) == "function")

    assert(it:fold(function(acc, x) return acc + x * 2 end, 1) == 21)
    assert(it._terminal_cache.fold == fold_exec)

    assert(it:nth(2) == 2)
    local nth_exec = it._terminal_cache.nth
    assert(type(nth_exec) == "function")
    assert(it:nth(4) == 4)
    assert(it._terminal_cache.nth == nth_exec)
end

local function test_shape_classification()
    local array_shape = F.from({ 1, 2, 3 }):map(function(x) return x + 1 end):filter(function(x) return x > 0 end):shape()
    assert(array_shape.root_name == "array")
    assert(array_shape.root_proto == "array_source")
    assert(array_shape.pipe.name == "map_filter")
    assert(array_shape.pipe_proto == "map_filter_pipe")
    assert(array_shape.exec_name == "general")
    assert(array_shape.exec_proto == "general_exec")
    assert(array_shape.shape_key == "array:map_filter:general")
    assert(array_shape.pipe.map_count == 1)
    assert(array_shape.pipe.filter_count == 1)

    local string_shape = F.chars("abcd"):shape()
    assert(string_shape.root_name == "string")
    assert(string_shape.root_proto == "char_source")
    assert(string_shape.pipe.name == "plain")
    assert(string_shape.exec_name == "string_plain")

    local chain_shape = F.chain(F.of(1), F.of(2)):shape()
    assert(chain_shape.root_name == "chain")
    assert(chain_shape.exec_name == "chain")

    local control_shape = F.from({ 1, 2, 3, 4 }):drop(1):take(2):shape()
    assert(control_shape.pipe.name == "control_only")

    local byte_shape = F.bytes("abcd"):shape()
    assert(byte_shape.root_name == "bytes")
    assert(byte_shape.root_proto == "byte_source")
    assert(byte_shape.exec_name == "general")
end

local function test_proto_plan_layer()
    local p = F.of(1, 2, 3):map(function(x) return x + 1 end):filter(function(x) return x > 0 end)
    local plan = p:plan("sum")

    assert(plan.terminal_kind == "sum")
    assert(plan.source.proto == "array_source")
    assert(plan.pipe.proto == "map_filter_pipe")
    assert(plan.exec.proto == "general_exec")
    assert(plan.terminal.proto == "sum_terminal")
    assert(plan.install.proto == "generated_install")
    assert(plan.shape_key == "array:map_filter:general")
    assert(plan.artifact_key == "array:map_filter:general:sum:generated")
    assert(p:plan("sum") == plan)

    local string_plan = F.chars("abcd"):plan("max")
    assert(string_plan.install.kind == "string_plain")
    assert(string_plan.install.proto == "string_plain_install")

    local empty_plan = F.empty():plan("sum")
    assert(empty_plan.install.kind == "empty")
end

local function test_empty_source_is_empty()
    assert(F.empty():head() == nil)
    assert(F.empty():count() == 0)
    assert(F.empty():sum() == 0)
    assert(F.empty():all(function() return false end) == true)
    assert(F.empty():any(function() return true end) == false)
    assert(F.empty():min() == nil)
    assert(F.empty():max() == nil)
end

local function test_exported_terminal_functions()
    local xs = { 3, 1, 4, 1, 5 }
    assert(F.sum(xs) == 14)
    assert(F.min(xs) == 1)
    assert(F.max(xs) == 5)
    assert(F.head(xs) == 3)
    assert(F.nth(3, xs) == 4)
    assert(F.count(xs) == 5)
    assert(F.collect(F.range(1, 3))[3] == 3)
    assert(F.plan("sum", xs).terminal.proto == "sum_terminal")
    assert(F.shape(xs).root_proto == "array_source")

    local sum_exec = F.compile("sum", xs)
    assert(type(sum_exec) == "function")
    assert(sum_exec() == 14)
end

local function test_byte_source()
    local it = F.bytes("Az")
    local xs = it:collect()
    same_array(xs, { string.byte("A"), string.byte("z") })
    assert(it:sum() == string.byte("A") + string.byte("z"))
    assert(it:head() == string.byte("A"))
    assert(it:nth(2) == string.byte("z"))
    assert(it:max() == string.byte("z"))
end

local function test_compat_aliases_still_work()
    local xs = F.iter({ 1, 2, 3 }):map(function(x) return x + 1 end):totable()
    same_array(xs, { 2, 3, 4 })
    assert(F.wrap(function(param, state)
        state = state + 1
        if state > #param then return nil end
        return state, param[state]
    end, { 5, 6 }, 0):length() == 2)
end

local tests = {
    test_range_map_filter_collect,
    test_take_drop_order,
    test_fold_sum_and_count,
    test_min_max_and_reuse,
    test_head_nth_any_all,
    test_chain_respects_global_take,
    test_chain_terminal_compilation,
    test_generate_source,
    test_chars_source,
    test_plain_string_terminals,
    test_argful_terminal_cache_reuses_compiled_executor,
    test_shape_classification,
    test_proto_plan_layer,
    test_empty_source_is_empty,
    test_exported_terminal_functions,
    test_byte_source,
    test_compat_aliases_still_work,
}

for _, test in ipairs(tests) do
    test()
end

print("ok - more_fun_test")
