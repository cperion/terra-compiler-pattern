local U = require("unit")

return function(T, U, P)
    local LJ = T.MoreFunLuaJIT

    local _ffi = require("ffi")
    local _getenv = os.getenv
    local C = require("crochet")

    local function leaf(name)
        return U.terminal(name, function(self)
            error("scaffold: implement leaf terminal " .. name, 2)
        end)
    end

    local function N(v)
        return tonumber(v)
    end

    local function B(v)
        return v == true or ((tonumber(v) or 0) ~= 0)
    end

    local function S(v)
        if type(v) == "cdata" then return _ffi.string(v) end
        return v
    end

    local function predicate_expr(env, pred, value_name, prefix)
        prefix = prefix or "pred"
        return U.match(pred, {
            CallPred = function(v)
                local name = prefix .. "_fn"
                env[name] = v.fn.fn
                return "(" .. name .. "(" .. value_name .. "))"
            end,
            EqNumberPred = function(v)
                return "(" .. value_name .. " == " .. tostring(N(v.rhs)) .. ")"
            end,
            GtNumberPred = function(v)
                return "(" .. value_name .. " > " .. tostring(N(v.rhs)) .. ")"
            end,
            LtNumberPred = function(v)
                return "(" .. value_name .. " < " .. tostring(N(v.rhs)) .. ")"
            end,
            ModEqNumberPred = function(v)
                return "((" .. value_name .. " % " .. tostring(N(v.divisor)) .. ") == " .. tostring(N(v.remainder)) .. ")"
            end,
        })
    end

    local function proto_name_for_chunk(chunkname)
        local name = tostring(chunkname or "more-fun:leaf")
        if name:sub(1, 1) == "@" then
            name = name:sub(2)
        end
        return name
    end

    local function sorted_capture_keys(env)
        local keys = {}
        env = env or {}
        for k, _ in pairs(env) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        return keys
    end

    local function capture_list(env)
        local keys = sorted_capture_keys(env)
        local captures = {}
        for i = 1, #keys do
            local name = keys[i]
            captures[i] = C.capture(name, env[name])
        end
        return captures
    end

    local function default_text_proto_host()
        local mode = _getenv("MORE_FUN_PROTO_ARTIFACT")
        if mode == nil or mode == "" or mode == "closure" then
            return "closure"
        end
        if mode == "bytecode" then
            return C.host_bytecode()
        end
        error("unsupported MORE_FUN_PROTO_ARTIFACT: " .. tostring(mode), 2)
    end

    local function compile_proto_with_host(chunkname, env, body, host)
        local name = proto_name_for_chunk(chunkname)
        local artifact = C.compile(C.catalog({
            C.proto(name, { "_state" }, capture_list(env), body),
        }, name, host or "closure"))
        return artifact.entry
    end

    local function compile_proto(chunkname, env, body)
        return compile_proto_with_host(chunkname, env, body, default_text_proto_host())
    end

    local function compile_proto_bytecode(chunkname, env, body)
        return compile_proto_with_host(chunkname, env, body, C.host_bytecode())
    end

    -- Experimental direct closure-host path. Keep off the default hot leaves
    -- until the closure installer can match the source-realized loop speed.
    local function compile_closure_proto(chunkname, env, body)
        local name = proto_name_for_chunk(chunkname)
        local artifact = C.compile(C.catalog({
            C.closure_proto(name, { "_state" }, capture_list(env), body),
        }, name, C.host_closure()))
        return artifact.entry
    end

    local function code_nodes(text)
        local nodes = {}
        if text == nil or text == "" then
            return nodes
        end
        text = tostring(text)
        local start = 1
        while true do
            local idx = text:find("\n", start, true)
            if not idx then
                nodes[#nodes + 1] = C.stmt(text:sub(start))
                break
            end
            nodes[#nodes + 1] = C.stmt(text:sub(start, idx - 1))
            start = idx + 1
        end
        return nodes
    end

    local function append_nodes(dst, src)
        for i = 1, #src do
            dst[#dst + 1] = src[i]
        end
    end

    local function guard_nodes(env, guards)
        if #guards == 0 then return {}, false end
        local nodes = {
            C.stmt("local pass = true"),
        }
        for i = 1, #guards do
            nodes[#nodes + 1] = C.stmt("if pass and not ", predicate_expr(env, guards[i].pred, "v", "guard_" .. tostring(i)), " then pass = false end")
        end
        nodes[#nodes + 1] = C.clause("if pass then")
        return nodes, true
    end

    local function compile_linear_loop(opts)
        local env = opts.env or {}
        local maps = opts.maps or {}
        local guards = opts.guards or {}
        local drop_count = opts.drop_count or 0
        local take_count = opts.take_count or 0
        local bounded_take = opts.bounded_take == true

        local body = {}
        for i = 1, #(opts.header_lines or {}) do
            append_nodes(body, code_nodes(opts.header_lines[i]))
        end

        if opts.early_return then
            append_nodes(body, code_nodes(opts.early_return))
        else
            if drop_count > 0 then
                body[#body + 1] = C.stmt("local emitted = 0")
            end
            if bounded_take then
                body[#body + 1] = C.stmt("local taken = 0")
            end

            local inner = {}
            append_nodes(inner, code_nodes(opts.value_line))

            for i = 1, #maps do
                local name = "map_fn_" .. tostring(i)
                env[name] = maps[i].fn.fn
                inner[#inner + 1] = C.stmt("v = ", name, "(v)")
            end

            local local_guard_nodes, has_guards = guard_nodes(env, guards)
            append_nodes(inner, local_guard_nodes)

            if drop_count > 0 then
                inner[#inner + 1] = C.stmt("emitted = emitted + 1")
                inner[#inner + 1] = C.stmt("if emitted <= ", tostring(drop_count), " then goto continue end")
            end

            append_nodes(inner, code_nodes(opts.step_line))

            if bounded_take then
                inner[#inner + 1] = C.stmt("taken = taken + 1")
                inner[#inner + 1] = C.stmt("if taken >= ", tostring(take_count), " then break end")
            end

            if has_guards then
                inner[#inner + 1] = C.clause("end")
            end

            inner[#inner + 1] = C.stmt("::continue::")
            body[#body + 1] = C.nest(C.clause(opts.loop_line), C.body(inner), C.clause("end"))
            append_nodes(body, code_nodes(opts.result_line or "return acc"))
        end

        return compile_proto(opts.chunkname, env, C.body(body)), env
    end

    local function compile_array_body(self, chunkname, acc_init_line, step_line, result_line, extra_env)
        local control = self.body.control
        local take_count = N(control.take_count) or 0
        local bounded_take = B(control.bounded_take)
        local env = { values = self.loop.input.values }
        if extra_env then
            for k, v in pairs(extra_env) do
                env[k] = v
            end
        end
        local final_result = result_line or "return acc"
        local early_return = bounded_take and take_count <= 0 and final_result or nil
        return compile_linear_loop({
            chunkname = chunkname,
            env = env,
            maps = self.body.maps,
            guards = self.body.guards,
            drop_count = N(control.drop_count) or 0,
            take_count = take_count,
            bounded_take = bounded_take,
            header_lines = {
                "local xs = values",
                acc_init_line,
            },
            early_return = early_return,
            loop_line = "for i = 1, #xs do",
            value_line = "local v = xs[i]",
            step_line = step_line,
            result_line = final_result,
        })
    end

    local function compile_array_sum(self)
        local fn = compile_array_body(self, "@more-fun:ArraySum", "local acc = 0", "acc = acc + v")
        return fn
    end

    local function compile_range_body(self, chunkname, acc_init_line, step_line, result_line, extra_env)
        local control = self.body.control
        local take_count = N(control.take_count) or 0
        local bounded_take = B(control.bounded_take)
        local env = {}
        if extra_env then
            for k, v in pairs(extra_env) do
                env[k] = v
            end
        end
        local early_return
        local step = N(self.loop.step) or 0
        if step == 0 then
            early_return = result_line or "return acc"
        elseif bounded_take and take_count <= 0 then
            early_return = result_line or "return acc"
        end
        return compile_linear_loop({
            chunkname = chunkname,
            env = env,
            maps = self.body.maps,
            guards = self.body.guards,
            drop_count = N(control.drop_count) or 0,
            take_count = take_count,
            bounded_take = bounded_take,
            header_lines = {
                acc_init_line,
            },
            early_return = early_return,
            loop_line = "for i = " .. tostring(N(self.loop.start) or 0) .. ", " .. tostring(N(self.loop.stop) or 0) .. ", " .. tostring(step) .. " do",
            value_line = "local v = i",
            step_line = step_line,
            result_line = result_line or "return acc",
        })
    end

    local function compile_string_body(self, chunkname, acc_init_line, step_line, result_line, extra_env)
        local control = self.body.control
        local take_count = N(control.take_count) or 0
        local bounded_take = B(control.bounded_take)
        local env = {
            text = S(self.loop.input.text),
            sub = string.sub,
        }
        if extra_env then
            for k, v in pairs(extra_env) do
                env[k] = v
            end
        end
        return compile_linear_loop({
            chunkname = chunkname,
            env = env,
            maps = self.body.maps,
            guards = self.body.guards,
            drop_count = N(control.drop_count) or 0,
            take_count = take_count,
            bounded_take = bounded_take,
            header_lines = {
                "local s = text",
                acc_init_line,
            },
            early_return = bounded_take and take_count <= 0 and (result_line or "return acc") or nil,
            loop_line = "for i = 1, #s do",
            value_line = "local v = sub(s, i, i)",
            step_line = step_line,
            result_line = result_line or "return acc",
        })
    end

    local function compile_byte_string_body(self, chunkname, acc_init_line, step_line, result_line, extra_env)
        local control = self.body.control
        local take_count = N(control.take_count) or 0
        local bounded_take = B(control.bounded_take)
        local env = {
            text = S(self.loop.input.text),
            byte = string.byte,
        }
        if extra_env then
            for k, v in pairs(extra_env) do
                env[k] = v
            end
        end
        return compile_linear_loop({
            chunkname = chunkname,
            env = env,
            maps = self.body.maps,
            guards = self.body.guards,
            drop_count = N(control.drop_count) or 0,
            take_count = take_count,
            bounded_take = bounded_take,
            header_lines = {
                "local s = text",
                acc_init_line,
            },
            early_return = bounded_take and take_count <= 0 and (result_line or "return acc") or nil,
            loop_line = "for i = 1, #s do",
            value_line = "local v = byte(s, i)",
            step_line = step_line,
            result_line = result_line or "return acc",
        })
    end

    local function compile_seeded_loop(opts)
        local env = opts.env or {}
        local maps = opts.maps or {}
        local guards = opts.guards or {}
        local drop_count = opts.drop_count or 0
        local take_count = opts.take_count or 0
        local bounded_take = opts.bounded_take == true

        local body = {}
        for i = 1, #(opts.header_lines or {}) do
            append_nodes(body, code_nodes(opts.header_lines[i]))
        end

        if opts.early_return then
            append_nodes(body, code_nodes(opts.early_return))
        else
            if drop_count > 0 then
                body[#body + 1] = C.stmt("local emitted = 0")
            end
            if bounded_take then
                body[#body + 1] = C.stmt("local taken = 0")
            end
            body[#body + 1] = C.stmt("local acc = nil")

            do
                local inner = {}
                append_nodes(inner, code_nodes(opts.value_line))
                append_nodes(inner, code_nodes(opts.advance_line))

                for i = 1, #maps do
                    local name = "map_fn_" .. tostring(i)
                    env[name] = maps[i].fn.fn
                    inner[#inner + 1] = C.stmt("v = ", name, "(v)")
                end

                local local_guard_nodes, has_guards = guard_nodes(env, guards)
                append_nodes(inner, local_guard_nodes)

                if drop_count > 0 then
                    inner[#inner + 1] = C.stmt("emitted = emitted + 1")
                    inner[#inner + 1] = C.stmt("if emitted <= ", tostring(drop_count), " then goto seed_continue end")
                end

                inner[#inner + 1] = C.stmt("acc = v")

                if bounded_take then
                    inner[#inner + 1] = C.stmt("taken = taken + 1")
                    inner[#inner + 1] = C.stmt("if taken >= ", tostring(take_count), " then return acc end")
                end

                inner[#inner + 1] = C.stmt("break")

                if has_guards then
                    inner[#inner + 1] = C.clause("end")
                end

                inner[#inner + 1] = C.stmt("::seed_continue::")
                body[#body + 1] = C.nest(C.clause(opts.seed_loop_line), C.body(inner), C.clause("end"))
            end
            body[#body + 1] = C.stmt("if acc == nil then return nil end")

            do
                local inner = {}
                append_nodes(inner, code_nodes(opts.value_line))
                append_nodes(inner, code_nodes(opts.advance_line))

                for i = 1, #maps do
                    local name = "map_fn_" .. tostring(i)
                    env[name] = maps[i].fn.fn
                    inner[#inner + 1] = C.stmt("v = ", name, "(v)")
                end

                local local_guard_nodes, has_guards = guard_nodes(env, guards)
                append_nodes(inner, local_guard_nodes)

                if drop_count > 0 then
                    inner[#inner + 1] = C.stmt("emitted = emitted + 1")
                    inner[#inner + 1] = C.stmt("if emitted <= ", tostring(drop_count), " then goto continue end")
                end

                append_nodes(inner, code_nodes(opts.step_line))

                if bounded_take then
                    inner[#inner + 1] = C.stmt("taken = taken + 1")
                    inner[#inner + 1] = C.stmt("if taken >= ", tostring(take_count), " then break end")
                end

                if has_guards then
                    inner[#inner + 1] = C.clause("end")
                end

                inner[#inner + 1] = C.stmt("::continue::")
                body[#body + 1] = C.nest(C.clause(opts.loop_line), C.body(inner), C.clause("end"))
            end
            append_nodes(body, code_nodes(opts.result_line or "return acc"))
        end

        return compile_proto(opts.chunkname, env, C.body(body)), env
    end

    local function compile_array_extrema(self, chunkname, compare_op)
        local control = self.body.control
        local take_count = N(control.take_count) or 0
        local bounded_take = B(control.bounded_take)
        return compile_seeded_loop({
            chunkname = chunkname,
            env = { values = self.loop.input.values },
            maps = self.body.maps,
            guards = self.body.guards,
            drop_count = N(control.drop_count) or 0,
            take_count = take_count,
            bounded_take = bounded_take,
            header_lines = {
                "local xs = values",
                "local i = 1",
                "local n = #xs",
            },
            early_return = bounded_take and take_count <= 0 and "return nil" or nil,
            seed_loop_line = "while i <= n do",
            loop_line = "while i <= n do",
            value_line = "local v = xs[i]",
            advance_line = "i = i + 1",
            step_line = "if v " .. compare_op .. " acc then acc = v end",
            result_line = "return acc",
        })
    end

    local function compile_range_extrema(self, chunkname, compare_op)
        local control = self.body.control
        local take_count = N(control.take_count) or 0
        local bounded_take = B(control.bounded_take)
        local start = N(self.loop.start) or 0
        local stop = N(self.loop.stop) or 0
        local step = N(self.loop.step) or 0
        local cond
        if step > 0 then
            cond = "i <= " .. tostring(stop)
        elseif step < 0 then
            cond = "i >= " .. tostring(stop)
        end
        return compile_seeded_loop({
            chunkname = chunkname,
            env = {},
            maps = self.body.maps,
            guards = self.body.guards,
            drop_count = N(control.drop_count) or 0,
            take_count = take_count,
            bounded_take = bounded_take,
            header_lines = {
                "local i = " .. tostring(start),
            },
            early_return = (step == 0 or (bounded_take and take_count <= 0)) and "return nil" or nil,
            seed_loop_line = "while " .. cond .. " do",
            loop_line = "while " .. cond .. " do",
            value_line = "local v = i",
            advance_line = "i = i + " .. tostring(step),
            step_line = "if v " .. compare_op .. " acc then acc = v end",
            result_line = "return acc",
        })
    end

    local function compile_string_extrema(self, chunkname, compare_op)
        local control = self.body.control
        local take_count = N(control.take_count) or 0
        local bounded_take = B(control.bounded_take)
        return compile_seeded_loop({
            chunkname = chunkname,
            env = {
                text = S(self.loop.input.text),
                sub = string.sub,
            },
            maps = self.body.maps,
            guards = self.body.guards,
            drop_count = N(control.drop_count) or 0,
            take_count = take_count,
            bounded_take = bounded_take,
            header_lines = {
                "local s = text",
                "local i = 1",
                "local n = #s",
            },
            early_return = bounded_take and take_count <= 0 and "return nil" or nil,
            seed_loop_line = "while i <= n do",
            loop_line = "while i <= n do",
            value_line = "local v = sub(s, i, i)",
            advance_line = "i = i + 1",
            step_line = "if v " .. compare_op .. " acc then acc = v end",
            result_line = "return acc",
        })
    end

    local function compile_byte_string_extrema(self, chunkname, compare_op)
        local control = self.body.control
        local take_count = N(control.take_count) or 0
        local bounded_take = B(control.bounded_take)
        return compile_seeded_loop({
            chunkname = chunkname,
            env = {
                text = S(self.loop.input.text),
                byte = string.byte,
            },
            maps = self.body.maps,
            guards = self.body.guards,
            drop_count = N(control.drop_count) or 0,
            take_count = take_count,
            bounded_take = bounded_take,
            header_lines = {
                "local s = text",
                "local i = 1",
                "local n = #s",
            },
            early_return = bounded_take and take_count <= 0 and "return nil" or nil,
            seed_loop_line = "while i <= n do",
            loop_line = "while i <= n do",
            value_line = "local v = byte(s, i)",
            advance_line = "i = i + 1",
            step_line = "if v " .. compare_op .. " acc then acc = v end",
            result_line = "return acc",
        })
    end

    local function is_plain_fast_body(body)
        local control = body.control
        return #body.maps == 0
            and #body.guards == 0
            and (N(control.drop_count) or 0) == 0
            and not B(control.bounded_take)
    end

    local function compile_plain_array_extrema(self, chunkname, compare_op)
        return compile_proto(chunkname, {
            values = self.loop.input.values,
        }, C.body({
            C.stmt("local xs = values"),
            C.stmt("if #xs == 0 then return nil end"),
            C.stmt("local acc = xs[1]"),
            C.nest(C.clause("for i = 2, #xs do"), C.body({
                C.stmt("local v = xs[i]"),
                C.stmt("if v ", compare_op, " acc then acc = v end"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_range_extrema(self, chunkname, compare_op)
        local start = N(self.loop.start) or 0
        local stop = N(self.loop.stop) or 0
        local step = N(self.loop.step) or 0
        return compile_proto(chunkname, {
            start = start,
            stop = stop,
            step = step,
        }, C.body({
            C.stmt("if step == 0 then return nil end"),
            C.stmt("if step > 0 and start > stop then return nil end"),
            C.stmt("if step < 0 and start < stop then return nil end"),
            C.stmt("local acc = start"),
            C.nest(C.clause("for i = start + step, stop, step do"), C.body({
                C.stmt("if i ", compare_op, " acc then acc = i end"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_string_extrema(self, chunkname, compare_op)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            byte = string.byte,
            chr = string.char,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("if #s == 0 then return nil end"),
            C.stmt("local acc = byte(s, 1)"),
            C.nest(C.clause("for i = 2, #s do"), C.body({
                C.stmt("local v = byte(s, i)"),
                C.stmt("if v ", compare_op, " acc then acc = v end"),
            }), C.clause("end")),
            C.stmt("return chr(acc)"),
        }))
    end

    local function compile_plain_byte_string_extrema(self, chunkname, compare_op)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            byte = string.byte,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("if #s == 0 then return nil end"),
            C.stmt("local acc = byte(s, 1)"),
            C.nest(C.clause("for i = 2, #s do"), C.body({
                C.stmt("local v = byte(s, i)"),
                C.stmt("if v ", compare_op, " acc then acc = v end"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_array_sum(self, chunkname)
        return compile_proto(chunkname, {
            values = self.loop.input.values,
        }, C.body({
            C.stmt("local xs = values"),
            C.stmt("local acc = 0"),
            C.nest(C.clause("for i = 1, #xs do"), C.body({
                C.stmt("acc = acc + xs[i]"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_array_foldl(self, chunkname)
        return compile_proto(chunkname, {
            values = self.loop.input.values,
            reducer_fn = self.reducer.fn,
            init_value = self.init.value,
        }, C.body({
            C.stmt("local xs = values"),
            C.stmt("local acc = init_value"),
            C.nest(C.clause("for i = 1, #xs do"), C.body({
                C.stmt("acc = reducer_fn(acc, xs[i])"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_array_head(self, chunkname)
        return compile_proto(chunkname, {
            values = self.loop.input.values,
        }, C.body({
            C.stmt("return values[1]"),
        }))
    end

    local function compile_plain_range_sum(self, chunkname)
        local start = N(self.loop.start) or 0
        local stop = N(self.loop.stop) or 0
        local step = N(self.loop.step) or 0
        return compile_proto(chunkname, {
            start = start,
            stop = stop,
            step = step,
        }, C.body({
            C.stmt("if step == 0 then return 0 end"),
            C.stmt("local acc = 0"),
            C.nest(C.clause("for i = start, stop, step do"), C.body({
                C.stmt("acc = acc + i"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_range_foldl(self, chunkname)
        local start = N(self.loop.start) or 0
        local stop = N(self.loop.stop) or 0
        local step = N(self.loop.step) or 0
        return compile_proto(chunkname, {
            start = start,
            stop = stop,
            step = step,
            reducer_fn = self.reducer.fn,
            init_value = self.init.value,
        }, C.body({
            C.stmt("local acc = init_value"),
            C.stmt("if step == 0 then return acc end"),
            C.nest(C.clause("for i = start, stop, step do"), C.body({
                C.stmt("acc = reducer_fn(acc, i)"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_byte_string_sum(self, chunkname)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            byte = string.byte,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("local acc = 0"),
            C.nest(C.clause("for i = 1, #s do"), C.body({
                C.stmt("acc = acc + byte(s, i)"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_byte_string_foldl(self, chunkname)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            byte = string.byte,
            reducer_fn = self.reducer.fn,
            init_value = self.init.value,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("local acc = init_value"),
            C.nest(C.clause("for i = 1, #s do"), C.body({
                C.stmt("acc = reducer_fn(acc, byte(s, i))"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_array_nth(self, chunkname, target_index)
        return compile_proto(chunkname, {
            values = self.loop.input.values,
            target_index = target_index,
        }, C.body({
            C.stmt("if target_index <= 0 then return nil end"),
            C.stmt("return values[target_index]"),
        }))
    end

    local function compile_plain_range_head(self, chunkname)
        local start = N(self.loop.start) or 0
        local stop = N(self.loop.stop) or 0
        local step = N(self.loop.step) or 0
        return compile_proto(chunkname, {
            start = start,
            stop = stop,
            step = step,
        }, C.body({
            C.stmt("if step == 0 then return nil end"),
            C.stmt("if step > 0 and start > stop then return nil end"),
            C.stmt("if step < 0 and start < stop then return nil end"),
            C.stmt("return start"),
        }))
    end

    local function compile_plain_range_nth(self, chunkname, target_index)
        local start = N(self.loop.start) or 0
        local stop = N(self.loop.stop) or 0
        local step = N(self.loop.step) or 0
        return compile_proto(chunkname, {
            start = start,
            stop = stop,
            step = step,
            target_index = target_index,
        }, C.body({
            C.stmt("if target_index <= 0 then return nil end"),
            C.stmt("if step == 0 then return nil end"),
            C.stmt("local v = start + ((target_index - 1) * step)"),
            C.stmt("if step > 0 and v > stop then return nil end"),
            C.stmt("if step < 0 and v < stop then return nil end"),
            C.stmt("return v"),
        }))
    end

    local function compile_plain_string_foldl(self, chunkname)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            sub = string.sub,
            reducer_fn = self.reducer.fn,
            init_value = self.init.value,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("local acc = init_value"),
            C.nest(C.clause("for i = 1, #s do"), C.body({
                C.stmt("acc = reducer_fn(acc, sub(s, i, i))"),
            }), C.clause("end")),
            C.stmt("return acc"),
        }))
    end

    local function compile_plain_string_head(self, chunkname)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            byte = string.byte,
            chr = string.char,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("if #s == 0 then return nil end"),
            C.stmt("return chr(byte(s, 1))"),
        }))
    end

    local function compile_plain_string_nth(self, chunkname, target_index)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            target_index = target_index,
            byte = string.byte,
            chr = string.char,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("if target_index <= 0 or target_index > #s then return nil end"),
            C.stmt("return chr(byte(s, target_index))"),
        }))
    end

    local function compile_plain_byte_string_head(self, chunkname)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            byte = string.byte,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("if #s == 0 then return nil end"),
            C.stmt("return byte(s, 1)"),
        }))
    end

    local function compile_plain_byte_string_nth(self, chunkname, target_index)
        return compile_proto(chunkname, {
            text = S(self.loop.input.text),
            target_index = target_index,
            byte = string.byte,
        }, C.body({
            C.stmt("local s = text"),
            C.stmt("if target_index <= 0 or target_index > #s then return nil end"),
            C.stmt("return byte(s, target_index)"),
        }))
    end

    local function compile_plain_array_any_all(self, chunkname, is_all)
        local env = { values = self.loop.input.values }
        local pred_src = predicate_expr(env, self.pred, "v", is_all and "plain_all" or "plain_any")
        local test_line = is_all
            and ("if not " .. pred_src .. " then return false end")
            or ("if " .. pred_src .. " then return true end")
        local final_line = is_all and "return true" or "return false"
        return compile_proto(chunkname, env, C.body({
            C.stmt("local xs = values"),
            C.nest(C.clause("for i = 1, #xs do"), C.body({
                C.stmt("local v = xs[i]"),
                C.stmt(test_line),
            }), C.clause("end")),
            C.stmt(final_line),
        }))
    end

    local function compile_plain_range_any_all(self, chunkname, is_all)
        local env = {}
        local start = N(self.loop.start) or 0
        local stop = N(self.loop.stop) or 0
        local step = N(self.loop.step) or 0
        local pred_src = predicate_expr(env, self.pred, "i", is_all and "plain_all" or "plain_any")
        local test_line = is_all
            and ("if not " .. pred_src .. " then return false end")
            or ("if " .. pred_src .. " then return true end")
        local final_line = is_all and "return true" or "return false"
        return compile_proto(chunkname, {
            start = start,
            stop = stop,
            step = step,
            plain_any_fn = env.plain_any_fn,
            plain_all_fn = env.plain_all_fn,
        }, C.body({
            C.stmt("if step == 0 then return " .. (is_all and "true" or "false") .. " end"),
            C.nest(C.clause("for i = start, stop, step do"), C.body({
                C.stmt(test_line),
            }), C.clause("end")),
            C.stmt(final_line),
        }))
    end

    local function compile_plain_byte_string_any_all(self, chunkname, is_all)
        local env = {
            text = S(self.loop.input.text),
            byte = string.byte,
        }
        local pred_src = predicate_expr(env, self.pred, "v", is_all and "plain_all" or "plain_any")
        local test_line = is_all
            and ("if not " .. pred_src .. " then return false end")
            or ("if " .. pred_src .. " then return true end")
        local final_line = is_all and "return true" or "return false"
        return compile_proto(chunkname, env, C.body({
            C.stmt("local s = text"),
            C.nest(C.clause("for i = 1, #s do"), C.body({
                C.stmt("local v = byte(s, i)"),
                C.stmt(test_line),
            }), C.clause("end")),
            C.stmt(final_line),
        }))
    end

    local function compile_plain_string_any_all(self, chunkname, is_all)
        return U.match(self.pred, {
            CallPred = function(v)
                local final_line = is_all and "return true" or "return false"
                local test_line = is_all
                    and "if not pred_fn(chr(byte(s, i))) then return false end"
                    or "if pred_fn(chr(byte(s, i))) then return true end"
                return compile_proto(chunkname, {
                    text = S(self.loop.input.text),
                    byte = string.byte,
                    chr = string.char,
                    pred_fn = v.fn.fn,
                }, C.body({
                    C.stmt("local s = text"),
                    C.nest(C.clause("for i = 1, #s do"), C.body({
                        C.stmt(test_line),
                    }), C.clause("end")),
                    C.stmt(final_line),
                }))
            end,
            EqNumberPred = function() return nil end,
            GtNumberPred = function() return nil end,
            LtNumberPred = function() return nil end,
            ModEqNumberPred = function() return nil end,
        })
    end

    LJ.ArraySum.install = U.terminal("MoreFunLuaJIT.ArraySum:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_array_sum(self, "@more-fun:ArraySum")
        else
            fn = compile_array_sum(self)
        end
        return U.leaf(U.EMPTY, fn)
    end)

    LJ.ArrayFoldl.install = U.terminal("MoreFunLuaJIT.ArrayFoldl:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_array_foldl(self, "@more-fun:ArrayFoldl")
        else
            fn = compile_array_body(
                self,
                "@more-fun:ArrayFoldl",
                "local acc = init_value",
                "acc = reducer_fn(acc, v)",
                nil,
                {
                    reducer_fn = self.reducer.fn,
                    init_value = self.init.value,
                }
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ArrayToTable.install = U.terminal("MoreFunLuaJIT.ArrayToTable:install", function(self)
        local fn = compile_array_body(
            self,
            "@more-fun:ArrayToTable",
            "local acc = {}\nlocal n = 0",
            "n = n + 1\nacc[n] = v"
        )
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ArrayHead.install = U.terminal("MoreFunLuaJIT.ArrayHead:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_array_head(self, "@more-fun:ArrayHead")
        else
            fn = compile_array_body(
                self,
                "@more-fun:ArrayHead",
                "",
                "do return v end",
                "return nil"
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ArrayNth.install = U.terminal("MoreFunLuaJIT.ArrayNth:install", function(self)
        local target_index = N(self.index) or 0
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_array_nth(self, "@more-fun:ArrayNth", target_index)
        else
            if target_index <= 0 then
                return U.leaf(U.EMPTY, function(_state) return nil end)
            end
            fn = compile_array_body(
                self,
                "@more-fun:ArrayNth",
                "local seen = 0",
                "seen = seen + 1\nif seen == " .. tostring(target_index) .. " then do return v end end",
                "return nil"
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ArrayAny.install = U.terminal("MoreFunLuaJIT.ArrayAny:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_array_any_all(self, "@more-fun:ArrayAny", false)
        else
            local env = {}
            fn = compile_array_body(
                self,
                "@more-fun:ArrayAny",
                "",
                "if " .. predicate_expr(env, self.pred, "v", "terminal_any") .. " then do return true end end",
                "return false",
                env
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ArrayAll.install = U.terminal("MoreFunLuaJIT.ArrayAll:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_array_any_all(self, "@more-fun:ArrayAll", true)
        else
            local env = {}
            fn = compile_array_body(
                self,
                "@more-fun:ArrayAll",
                "",
                "if not " .. predicate_expr(env, self.pred, "v", "terminal_all") .. " then do return false end end",
                "return true",
                env
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ArrayMin.install = U.terminal("MoreFunLuaJIT.ArrayMin:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_array_extrema(self, "@more-fun:ArrayMin", "<")
        else
            fn = compile_array_extrema(self, "@more-fun:ArrayMin", "<")
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ArrayMax.install = U.terminal("MoreFunLuaJIT.ArrayMax:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_array_extrema(self, "@more-fun:ArrayMax", ">")
        else
            fn = compile_array_extrema(self, "@more-fun:ArrayMax", ">")
        end
        return U.leaf(U.EMPTY, fn)
    end)

    LJ.RangeSum.install = U.terminal("MoreFunLuaJIT.RangeSum:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_range_sum(self, "@more-fun:RangeSum")
        else
            fn = compile_range_body(self, "@more-fun:RangeSum", "  local acc = 0", "      acc = acc + v")
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.RangeFoldl.install = U.terminal("MoreFunLuaJIT.RangeFoldl:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_range_foldl(self, "@more-fun:RangeFoldl")
        else
            fn = compile_range_body(
                self,
                "@more-fun:RangeFoldl",
                "local acc = init_value",
                "acc = reducer_fn(acc, v)",
                nil,
                {
                    reducer_fn = self.reducer.fn,
                    init_value = self.init.value,
                }
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.RangeToTable.install = U.terminal("MoreFunLuaJIT.RangeToTable:install", function(self)
        local fn = compile_range_body(
            self,
            "@more-fun:RangeToTable",
            "local acc = {}\nlocal n = 0",
            "n = n + 1\nacc[n] = v"
        )
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.RangeHead.install = U.terminal("MoreFunLuaJIT.RangeHead:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_range_head(self, "@more-fun:RangeHead")
        else
            fn = compile_range_body(
                self,
                "@more-fun:RangeHead",
                "",
                "do return v end",
                "return nil"
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.RangeNth.install = U.terminal("MoreFunLuaJIT.RangeNth:install", function(self)
        local target_index = N(self.index) or 0
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_range_nth(self, "@more-fun:RangeNth", target_index)
        else
            if target_index <= 0 then
                return U.leaf(U.EMPTY, function(_state) return nil end)
            end
            fn = compile_range_body(
                self,
                "@more-fun:RangeNth",
                "local seen = 0",
                "seen = seen + 1\nif seen == " .. tostring(target_index) .. " then do return v end end",
                "return nil"
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.RangeAny.install = U.terminal("MoreFunLuaJIT.RangeAny:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_range_any_all(self, "@more-fun:RangeAny", false)
        else
            local env = {}
            fn = compile_range_body(
                self,
                "@more-fun:RangeAny",
                "",
                "if " .. predicate_expr(env, self.pred, "v", "terminal_any") .. " then do return true end end",
                "return false",
                env
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.RangeAll.install = U.terminal("MoreFunLuaJIT.RangeAll:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_range_any_all(self, "@more-fun:RangeAll", true)
        else
            local env = {}
            fn = compile_range_body(
                self,
                "@more-fun:RangeAll",
                "",
                "if not " .. predicate_expr(env, self.pred, "v", "terminal_all") .. " then do return false end end",
                "return true",
                env
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.RangeMin.install = U.terminal("MoreFunLuaJIT.RangeMin:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_range_extrema(self, "@more-fun:RangeMin", "<")
        else
            fn = compile_range_extrema(self, "@more-fun:RangeMin", "<")
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.RangeMax.install = U.terminal("MoreFunLuaJIT.RangeMax:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_range_extrema(self, "@more-fun:RangeMax", ">")
        else
            fn = compile_range_extrema(self, "@more-fun:RangeMax", ">")
        end
        return U.leaf(U.EMPTY, fn)
    end)

    LJ.StringFoldl.install = U.terminal("MoreFunLuaJIT.StringFoldl:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_string_foldl(self, "@more-fun:StringFoldl")
        else
            fn = compile_string_body(
                self,
                "@more-fun:StringFoldl",
                "  local acc = init_value",
                "      acc = reducer_fn(acc, v)",
                nil,
                {
                    reducer_fn = self.reducer.fn,
                    init_value = self.init.value,
                }
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.StringToTable.install = U.terminal("MoreFunLuaJIT.StringToTable:install", function(self)
        local fn = compile_string_body(self, "@more-fun:StringToTable", "  local acc = {}\n  local n = 0", "      n = n + 1\n      acc[n] = v")
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.StringHead.install = U.terminal("MoreFunLuaJIT.StringHead:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_string_head(self, "@more-fun:StringHead")
        else
            fn = compile_string_body(
                self,
                "@more-fun:StringHead",
                "",
                "do return v end",
                "return nil"
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.StringNth.install = U.terminal("MoreFunLuaJIT.StringNth:install", function(self)
        local target_index = N(self.index) or 0
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_string_nth(self, "@more-fun:StringNth", target_index)
        else
            if target_index <= 0 then
                return U.leaf(U.EMPTY, function(_state) return nil end)
            end
            fn = compile_string_body(
                self,
                "@more-fun:StringNth",
                "local seen = 0",
                "seen = seen + 1\nif seen == " .. tostring(target_index) .. " then do return v end end",
                "return nil"
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.StringAny.install = U.terminal("MoreFunLuaJIT.StringAny:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_string_any_all(self, "@more-fun:StringAny", false)
        end
        if not fn then
            local env = {}
            fn = compile_string_body(
                self,
                "@more-fun:StringAny",
                "",
                "if " .. predicate_expr(env, self.pred, "v", "terminal_any") .. " then do return true end end",
                "return false",
                env
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.StringAll.install = U.terminal("MoreFunLuaJIT.StringAll:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_string_any_all(self, "@more-fun:StringAll", true)
        end
        if not fn then
            local env = {}
            fn = compile_string_body(
                self,
                "@more-fun:StringAll",
                "",
                "if not " .. predicate_expr(env, self.pred, "v", "terminal_all") .. " then do return false end end",
                "return true",
                env
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.StringMin.install = U.terminal("MoreFunLuaJIT.StringMin:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_string_extrema(self, "@more-fun:StringMin", "<")
        else
            fn = compile_string_extrema(self, "@more-fun:StringMin", "<")
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.StringMax.install = U.terminal("MoreFunLuaJIT.StringMax:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_string_extrema(self, "@more-fun:StringMax", ">")
        else
            fn = compile_string_extrema(self, "@more-fun:StringMax", ">")
        end
        return U.leaf(U.EMPTY, fn)
    end)

    LJ.ByteStringSum.install = U.terminal("MoreFunLuaJIT.ByteStringSum:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_byte_string_sum(self, "@more-fun:ByteStringSum")
        else
            fn = compile_byte_string_body(self, "@more-fun:ByteStringSum", "  local acc = 0", "      acc = acc + v")
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ByteStringFoldl.install = U.terminal("MoreFunLuaJIT.ByteStringFoldl:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_byte_string_foldl(self, "@more-fun:ByteStringFoldl")
        else
            fn = compile_byte_string_body(
                self,
                "@more-fun:ByteStringFoldl",
                "  local acc = init_value",
                "      acc = reducer_fn(acc, v)",
                nil,
                {
                    reducer_fn = self.reducer.fn,
                    init_value = self.init.value,
                }
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ByteStringToTable.install = U.terminal("MoreFunLuaJIT.ByteStringToTable:install", function(self)
        local fn = compile_byte_string_body(self, "@more-fun:ByteStringToTable", "  local acc = {}\n  local n = 0", "      n = n + 1\n      acc[n] = v")
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ByteStringHead.install = U.terminal("MoreFunLuaJIT.ByteStringHead:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_byte_string_head(self, "@more-fun:ByteStringHead")
        else
            fn = compile_byte_string_body(
                self,
                "@more-fun:ByteStringHead",
                "",
                "do return v end",
                "return nil"
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ByteStringNth.install = U.terminal("MoreFunLuaJIT.ByteStringNth:install", function(self)
        local target_index = N(self.index) or 0
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_byte_string_nth(self, "@more-fun:ByteStringNth", target_index)
        else
            if target_index <= 0 then
                return U.leaf(U.EMPTY, function(_state) return nil end)
            end
            fn = compile_byte_string_body(
                self,
                "@more-fun:ByteStringNth",
                "local seen = 0",
                "seen = seen + 1\nif seen == " .. tostring(target_index) .. " then do return v end end",
                "return nil"
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ByteStringAny.install = U.terminal("MoreFunLuaJIT.ByteStringAny:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_byte_string_any_all(self, "@more-fun:ByteStringAny", false)
        else
            local env = {}
            fn = compile_byte_string_body(
                self,
                "@more-fun:ByteStringAny",
                "",
                "if " .. predicate_expr(env, self.pred, "v", "terminal_any") .. " then do return true end end",
                "return false",
                env
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ByteStringAll.install = U.terminal("MoreFunLuaJIT.ByteStringAll:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_byte_string_any_all(self, "@more-fun:ByteStringAll", true)
        else
            local env = {}
            fn = compile_byte_string_body(
                self,
                "@more-fun:ByteStringAll",
                "",
                "if not " .. predicate_expr(env, self.pred, "v", "terminal_all") .. " then do return false end end",
                "return true",
                env
            )
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ByteStringMin.install = U.terminal("MoreFunLuaJIT.ByteStringMin:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_byte_string_extrema(self, "@more-fun:ByteStringMin", "<")
        else
            fn = compile_byte_string_extrema(self, "@more-fun:ByteStringMin", "<")
        end
        return U.leaf(U.EMPTY, fn)
    end)
    LJ.ByteStringMax.install = U.terminal("MoreFunLuaJIT.ByteStringMax:install", function(self)
        local fn
        if is_plain_fast_body(self.body) then
            fn = compile_plain_byte_string_extrema(self, "@more-fun:ByteStringMax", ">")
        else
            fn = compile_byte_string_extrema(self, "@more-fun:ByteStringMax", ">")
        end
        return U.leaf(U.EMPTY, fn)
    end)

    LJ.GenericInstall.install = U.terminal("MoreFunLuaJIT.GenericInstall:install", function(self)
        local STOP = {}

        local function predicate_fn(pred)
            return U.match(pred, {
                CallPred = function(v)
                    local fn = v.fn.fn
                    return function(x) return fn(x) end
                end,
                EqNumberPred = function(v)
                    local rhs = N(v.rhs)
                    return function(x) return x == rhs end
                end,
                GtNumberPred = function(v)
                    local rhs = N(v.rhs)
                    return function(x) return x > rhs end
                end,
                LtNumberPred = function(v)
                    local rhs = N(v.rhs)
                    return function(x) return x < rhs end
                end,
                ModEqNumberPred = function(v)
                    local divisor = N(v.divisor)
                    local remainder = N(v.remainder)
                    return function(x) return (x % divisor) == remainder end
                end,
            })
        end

        local function wrap_maps(maps, i, sink)
            if i > #maps then return sink end
            local fn = maps[i].fn.fn
            local child = wrap_maps(maps, i + 1, sink)
            return function(v)
                return child(fn(v))
            end
        end

        local function wrap_guards(guards, i, sink)
            if i > #guards then return sink end
            local pred = predicate_fn(guards[i].pred)
            local child = wrap_guards(guards, i + 1, sink)
            return function(v)
                if pred(v) then
                    return child(v)
                end
                return nil
            end
        end

        local function wrap_drop(limit, sink)
            if limit <= 0 then return sink end
            local seen = 0
            return function(v)
                seen = seen + 1
                if seen > limit then
                    return sink(v)
                end
                return nil
            end
        end

        local function wrap_take(limit, bounded, sink)
            if not bounded then return sink end
            local seen = 0
            return function(v)
                seen = seen + 1
                if seen <= limit then
                    return sink(v)
                end
                return STOP
            end
        end

        local function sink_for_pipe(pipe, sink)
            return U.match(pipe, {
                EndPipe = function()
                    return sink
                end,
                MapPipe = function(v)
                    local child = sink_for_pipe(v.next, sink)
                    local fn = v.fn.fn
                    return function(x)
                        return child(fn(x))
                    end
                end,
                GuardPipe = function(v)
                    local child = sink_for_pipe(v.next, sink)
                    local pred = predicate_fn(v.pred)
                    return function(x)
                        if pred(x) then
                            return child(x)
                        end
                        return nil
                    end
                end,
                TakePipe = function(v)
                    local child = sink_for_pipe(v.next, sink)
                    local limit = N(v.count) or 0
                    local seen = 0
                    return function(x)
                        seen = seen + 1
                        if seen <= limit then
                            return child(x)
                        end
                        return STOP
                    end
                end,
                DropPipe = function(v)
                    local child = sink_for_pipe(v.next, sink)
                    local limit = N(v.count) or 0
                    local seen = 0
                    return function(x)
                        seen = seen + 1
                        if seen > limit then
                            return child(x)
                        end
                        return nil
                    end
                end,
            })
        end

        local function sink_for_body(body, terminal_sink)
            return U.match(body, {
                FastBody = function(v)
                    local control = v.control
                    local drop_count = N(control.drop_count) or 0
                    local take_count = N(control.take_count) or 0
                    local bounded_take = B(control.bounded_take)
                    local sink = terminal_sink
                    sink = wrap_take(take_count, bounded_take, sink)
                    sink = wrap_drop(drop_count, sink)
                    sink = wrap_guards(v.guards, 1, sink)
                    sink = wrap_maps(v.maps, 1, sink)
                    return sink
                end,
                GenericBody = function(v)
                    return sink_for_pipe(v.pipe, terminal_sink)
                end,
            })
        end

        local function loop_runner(loop, sink)
            local function chain_runner(parts, i)
                if i > #parts then
                    return function() return nil end
                end
                local head = loop_runner(parts[i], sink)
                local tail = chain_runner(parts, i + 1)
                return function()
                    if head() == STOP then return STOP end
                    return tail()
                end
            end

            return U.match(loop, {
                ArrayLoop = function(v)
                    local xs = v.input.values
                    return function()
                        for i = 1, #xs do
                            if sink(xs[i]) == STOP then return STOP end
                        end
                        return nil
                    end
                end,
                RangeLoop = function(v)
                    local start = N(v.start) or 0
                    local stop = N(v.stop) or 0
                    local step = N(v.step) or 0
                    return function()
                        if step == 0 then return nil end
                        for i = start, stop, step do
                            if sink(i) == STOP then return STOP end
                        end
                        return nil
                    end
                end,
                StringLoop = function(v)
                    local s = S(v.input.text)
                    return function()
                        for i = 1, #s do
                            if sink(string.sub(s, i, i)) == STOP then return STOP end
                        end
                        return nil
                    end
                end,
                ByteStringLoop = function(v)
                    local s = S(v.input.text)
                    return function()
                        for i = 1, #s do
                            if sink(string.byte(s, i)) == STOP then return STOP end
                        end
                        return nil
                    end
                end,
                RawWhileLoop = function(v)
                    local gen = v.gen.fn
                    local param = v.param.value
                    local state0 = v.state0.value
                    return function()
                        local state = state0
                        while true do
                            local new_state, value = gen(param, state)
                            if new_state == nil then return nil end
                            state = new_state
                            if sink(value) == STOP then return STOP end
                        end
                    end
                end,
                ChainLoop = function(v)
                    return chain_runner(v.parts, 1)
                end,
            })
        end

        local function terminal_runner(spec)
            return U.match(spec.terminal, {
                SumPlan = function()
                    local acc = 0
                    return function(v)
                        acc = acc + v
                        return nil
                    end, function()
                        return acc
                    end
                end,
                FoldlPlan = function(v)
                    local reducer = v.reducer.fn
                    local acc = v.init.value
                    return function(x)
                        acc = reducer(acc, x)
                        return nil
                    end, function()
                        return acc
                    end
                end,
                ToTablePlan = function()
                    local acc, n = {}, 0
                    return function(v)
                        n = n + 1
                        acc[n] = v
                        return nil
                    end, function()
                        return acc
                    end
                end,
                HeadPlan = function()
                    local out = nil
                    return function(v)
                        out = v
                        return STOP
                    end, function()
                        return out
                    end
                end,
                NthPlan = function(v)
                    local target = N(v.index) or 0
                    local seen = 0
                    local out = nil
                    return function(x)
                        seen = seen + 1
                        if seen == target then
                            out = x
                            return STOP
                        end
                        return nil
                    end, function()
                        return out
                    end
                end,
                AnyPlan = function(v)
                    local pred = predicate_fn(v.pred)
                    local out = false
                    return function(x)
                        if pred(x) then
                            out = true
                            return STOP
                        end
                        return nil
                    end, function()
                        return out
                    end
                end,
                AllPlan = function(v)
                    local pred = predicate_fn(v.pred)
                    local out = true
                    return function(x)
                        if not pred(x) then
                            out = false
                            return STOP
                        end
                        return nil
                    end, function()
                        return out
                    end
                end,
                MinPlan = function()
                    local seen = false
                    local acc = nil
                    return function(v)
                        if not seen or v < acc then acc = v end
                        seen = true
                        return nil
                    end, function()
                        return acc
                    end
                end,
                MaxPlan = function()
                    local seen = false
                    local acc = nil
                    return function(v)
                        if not seen or v > acc then acc = v end
                        seen = true
                        return nil
                    end, function()
                        return acc
                    end
                end,
            })
        end

        local spec = self.machine
        local terminal_sink, finish = terminal_runner(spec)
        local body_sink = sink_for_body(spec.body, terminal_sink)
        local run_loop = loop_runner(spec.loop, body_sink)

        return U.leaf(U.EMPTY, function(_state)
            run_loop()
            return finish()
        end)
    end)

    LJ.Plan.install = U.terminal("MoreFunLuaJIT.Plan:install", function(plan)
        return U.match(plan, {
            ArraySum = function(self) return LJ.ArraySum.install(self) end,
            ArrayFoldl = function(self) return LJ.ArrayFoldl.install(self) end,
            ArrayToTable = function(self) return LJ.ArrayToTable.install(self) end,
            ArrayHead = function(self) return LJ.ArrayHead.install(self) end,
            ArrayNth = function(self) return LJ.ArrayNth.install(self) end,
            ArrayAny = function(self) return LJ.ArrayAny.install(self) end,
            ArrayAll = function(self) return LJ.ArrayAll.install(self) end,
            ArrayMin = function(self) return LJ.ArrayMin.install(self) end,
            ArrayMax = function(self) return LJ.ArrayMax.install(self) end,
            RangeSum = function(self) return LJ.RangeSum.install(self) end,
            RangeFoldl = function(self) return LJ.RangeFoldl.install(self) end,
            RangeToTable = function(self) return LJ.RangeToTable.install(self) end,
            RangeHead = function(self) return LJ.RangeHead.install(self) end,
            RangeNth = function(self) return LJ.RangeNth.install(self) end,
            RangeAny = function(self) return LJ.RangeAny.install(self) end,
            RangeAll = function(self) return LJ.RangeAll.install(self) end,
            RangeMin = function(self) return LJ.RangeMin.install(self) end,
            RangeMax = function(self) return LJ.RangeMax.install(self) end,
            StringFoldl = function(self) return LJ.StringFoldl.install(self) end,
            StringToTable = function(self) return LJ.StringToTable.install(self) end,
            StringHead = function(self) return LJ.StringHead.install(self) end,
            StringNth = function(self) return LJ.StringNth.install(self) end,
            StringAny = function(self) return LJ.StringAny.install(self) end,
            StringAll = function(self) return LJ.StringAll.install(self) end,
            StringMin = function(self) return LJ.StringMin.install(self) end,
            StringMax = function(self) return LJ.StringMax.install(self) end,
            ByteStringSum = function(self) return LJ.ByteStringSum.install(self) end,
            ByteStringFoldl = function(self) return LJ.ByteStringFoldl.install(self) end,
            ByteStringToTable = function(self) return LJ.ByteStringToTable.install(self) end,
            ByteStringHead = function(self) return LJ.ByteStringHead.install(self) end,
            ByteStringNth = function(self) return LJ.ByteStringNth.install(self) end,
            ByteStringAny = function(self) return LJ.ByteStringAny.install(self) end,
            ByteStringAll = function(self) return LJ.ByteStringAll.install(self) end,
            ByteStringMin = function(self) return LJ.ByteStringMin.install(self) end,
            ByteStringMax = function(self) return LJ.ByteStringMax.install(self) end,
            GenericInstall = function(self) return LJ.GenericInstall.install(self) end,
        })
    end)
end
