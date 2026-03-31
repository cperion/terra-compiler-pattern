local ffi = require("ffi")
local U = require("unit")

local _loadstring = loadstring
local _setfenv = setfenv
local _load = load
local _string_dump = string.dump
local _setmetatable = setmetatable
local _unpack = table.unpack or unpack

local function S(v)
    if type(v) == "cdata" then
        return ffi.string(v)
    end
    return tostring(v)
end

local function load_in_env(source, chunkname, env)
    if _loadstring then
        local fn, err = _loadstring(source, chunkname)
        if not fn then
            return nil, err
        end
        if env then
            _setfenv(fn, env)
        end
        return fn
    end
    return _load(source, chunkname, "bt", env)
end

return function(T, U, P)
    local function install_mode_name(mode)
        return U.match(mode, {
            SourceArtifact = function()
                return "source"
            end,
            ClosureArtifact = function()
                return "closure"
            end,
            BytecodeArtifact = function()
                return "bytecode"
            end,
        })
    end

    local function proto_name(proto)
        return U.match(proto, {
            SourceInstall = function(v) return S(v.name) end,
            ClosureInstall = function(v) return S(v.name) end,
            BytecodeInstall = function(v) return S(v.name) end,
        })
    end

    local function proto_id(proto)
        return U.match(proto, {
            SourceInstall = function(v) return v.proto_id end,
            ClosureInstall = function(v) return v.proto_id end,
            BytecodeInstall = function(v) return v.proto_id end,
        })
    end

    local function proto_artifact_key(proto)
        return U.match(proto, {
            SourceInstall = function(v) return S(v.artifact_key) end,
            ClosureInstall = function(v) return S(v.artifact_key) end,
            BytecodeInstall = function(v) return S(v.artifact_key) end,
        })
    end

    local function proto_chunk_name(proto)
        return U.match(proto, {
            SourceInstall = function(v) return S(v.chunk_name) end,
            ClosureInstall = function(v) return "@crochet-realize-closure:" .. S(v.name) end,
            BytecodeInstall = function(v) return S(v.chunk_name) end,
        })
    end

    local function proto_source(proto)
        return U.match(proto, {
            SourceInstall = function(v) return S(v.source) end,
            ClosureInstall = function()
                return nil
            end,
            BytecodeInstall = function(v) return S(v.source) end,
        })
    end

    local function proto_captures(proto)
        return U.match(proto, {
            SourceInstall = function()
                return {}
            end,
            ClosureInstall = function(v)
                return v.captures
            end,
            BytecodeInstall = function(v)
                return v.captures
            end,
        })
    end

    local function compile_closure_proto(proto)
        local captures_by_id = U.fold(proto.captures, function(acc, capture)
            acc[capture.capture_id] = capture.value.value
            return acc
        end, {})

        local compile_expr
        local compile_block

        local function compile_unary(op, value_fn)
            return U.match(op, {
                NotOp = function()
                    return function(ctx)
                        return not value_fn(ctx)
                    end
                end,
                NegOp = function()
                    return function(ctx)
                        return -value_fn(ctx)
                    end
                end,
                LenOp = function()
                    return function(ctx)
                        return #value_fn(ctx)
                    end
                end,
            })
        end

        local function compile_binary(op, lhs_fn, rhs_fn)
            return U.match(op, {
                AddOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) + rhs_fn(ctx)
                    end
                end,
                SubOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) - rhs_fn(ctx)
                    end
                end,
                MulOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) * rhs_fn(ctx)
                    end
                end,
                DivOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) / rhs_fn(ctx)
                    end
                end,
                ModOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) % rhs_fn(ctx)
                    end
                end,
                EqOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) == rhs_fn(ctx)
                    end
                end,
                NeOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) ~= rhs_fn(ctx)
                    end
                end,
                LtOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) < rhs_fn(ctx)
                    end
                end,
                LeOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) <= rhs_fn(ctx)
                    end
                end,
                GtOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) > rhs_fn(ctx)
                    end
                end,
                GeOp = function()
                    return function(ctx)
                        return lhs_fn(ctx) >= rhs_fn(ctx)
                    end
                end,
                AndOp = function()
                    return function(ctx)
                        local lhs = lhs_fn(ctx)
                        if not lhs then return lhs end
                        return rhs_fn(ctx)
                    end
                end,
                OrOp = function()
                    return function(ctx)
                        local lhs = lhs_fn(ctx)
                        if lhs then return lhs end
                        return rhs_fn(ctx)
                    end
                end,
            })
        end

        compile_expr = function(expr)
            return U.match(expr, {
                ParamExpr = function(v)
                    local param_id = v.param_id
                    return function(ctx)
                        return ctx.params[param_id]
                    end
                end,
                CaptureExpr = function(v)
                    local capture = captures_by_id[v.capture_id]
                    return function(_ctx)
                        return capture
                    end
                end,
                LocalExpr = function(v)
                    local local_id = v.local_id
                    return function(ctx)
                        return ctx.locals[local_id]
                    end
                end,
                LiteralExpr = function(v)
                    local value = v.value.value
                    return function(_ctx)
                        return value
                    end
                end,
                CallExpr = function(v)
                    local fn_eval = compile_expr(v.fn)
                    local arg_evals = U.map(v.args, compile_expr)
                    return function(ctx)
                        local args = U.map(arg_evals, function(eval_arg)
                            return eval_arg(ctx)
                        end)
                        return fn_eval(ctx)(_unpack(args))
                    end
                end,
                IndexExpr = function(v)
                    local base_eval = compile_expr(v.base)
                    local key_eval = compile_expr(v.key)
                    return function(ctx)
                        return base_eval(ctx)[key_eval(ctx)]
                    end
                end,
                UnaryExpr = function(v)
                    return compile_unary(v.op, compile_expr(v.value))
                end,
                BinaryExpr = function(v)
                    return compile_binary(v.op, compile_expr(v.lhs), compile_expr(v.rhs))
                end,
            })
        end

        local function compile_stmt(stmt)
            return U.match(stmt, {
                LetInstall = function(v)
                    local local_id = v.local_info.local_id
                    local value_eval = compile_expr(v.value)
                    return function(ctx)
                        ctx.locals[local_id] = value_eval(ctx)
                        return false, nil
                    end
                end,
                SetInstall = function(v)
                    local local_id = v.local_id
                    local value_eval = compile_expr(v.value)
                    return function(ctx)
                        ctx.locals[local_id] = value_eval(ctx)
                        return false, nil
                    end
                end,
                EffectInstall = function(v)
                    local value_eval = compile_expr(v.expr)
                    return function(ctx)
                        value_eval(ctx)
                        return false, nil
                    end
                end,
                ReturnInstall = function(v)
                    local value_eval = compile_expr(v.value)
                    return function(ctx)
                        return true, value_eval(ctx)
                    end
                end,
                IfInstall = function(v)
                    local cond_eval = compile_expr(v.cond)
                    local then_exec = compile_block(v.then_body)
                    local else_exec = compile_block(v.else_body)
                    return function(ctx)
                        if cond_eval(ctx) then
                            return then_exec(ctx)
                        end
                        return else_exec(ctx)
                    end
                end,
                ForRangeInstall = function(v)
                    local local_id = v.local_info.local_id
                    local start_eval = compile_expr(v.start)
                    local stop_eval = compile_expr(v.stop)
                    local step_eval = compile_expr(v.step)
                    local body_exec = compile_block(v.body)
                    return function(ctx)
                        local start = start_eval(ctx)
                        local stop = stop_eval(ctx)
                        local step = step_eval(ctx)
                        for i = start, stop, step do
                            ctx.locals[local_id] = i
                            local returned, value = body_exec(ctx)
                            if returned then
                                return true, value
                            end
                        end
                        return false, nil
                    end
                end,
                WhileInstall = function(v)
                    local cond_eval = compile_expr(v.cond)
                    local body_exec = compile_block(v.body)
                    return function(ctx)
                        while cond_eval(ctx) do
                            local returned, value = body_exec(ctx)
                            if returned then
                                return true, value
                            end
                        end
                        return false, nil
                    end
                end,
            })
        end

        compile_block = function(block)
            local stmt_execs = U.map(block.stmts, compile_stmt)
            return function(ctx)
                for i = 1, #stmt_execs do
                    local returned, value = stmt_execs[i](ctx)
                    if returned then
                        return true, value
                    end
                end
                return false, nil
            end
        end

        local run_block = compile_block(proto.body)
        return function(...)
            local ctx = {
                params = { ... },
                locals = {},
            }
            local _, value = run_block(ctx)
            return value
        end
    end

    local install_impl = U.terminal("CrochetRealizeLua.Catalog:install", function(catalog)
        local mode_name = install_mode_name(catalog.artifact_mode)
        local proto_specs = catalog.protos
        local proto_by_name = U.fold(proto_specs, function(acc, proto)
            acc[proto_name(proto)] = proto
            return acc
        end, {})
        local proto_by_id = U.fold(proto_specs, function(acc, proto)
            acc[proto_id(proto)] = proto
            return acc
        end, {})

        local function build_env(proto)
            local env = U.fold(proto_captures(proto), function(acc, capture)
                acc[S(capture.name)] = capture.value.value
                return acc
            end, {})
            return _setmetatable(env, { __index = _G })
        end

        local function compile_from_source(proto)
            local env = build_env(proto)
            local chunk, err = load_in_env(proto_source(proto), proto_chunk_name(proto), env)
            assert(chunk, err)
            return chunk(), env
        end

        local artifact = {
            mode = mode_name,
            entry_proto_id = catalog.entry_proto_id,
            protos = {},
            closure_cache = {},
            bytecode_cache = {},
        }

        function artifact:realize(name_or_id)
            local proto = nil
            if type(name_or_id) == "number" then
                proto = proto_by_id[name_or_id]
            else
                proto = proto_by_name[S(name_or_id)]
            end
            assert(proto ~= nil, "unknown proto: " .. tostring(name_or_id))

            local key = proto_artifact_key(proto)
            local cached = self.closure_cache[key]
            if cached then
                return cached
            end

            local fn = nil
            local bytecode = nil
            local source = proto_source(proto)

            if proto.kind == "ClosureInstall" then
                fn = compile_closure_proto(proto)
            else
                fn = select(1, compile_from_source(proto))
                if proto.kind == "BytecodeInstall" then
                    bytecode = _string_dump(fn)
                    self.bytecode_cache[key] = bytecode
                    local restored, err = load_in_env(bytecode, proto_chunk_name(proto) .. ":bytecode", build_env(proto))
                    assert(restored, err)
                    fn = restored
                end
            end

            self.closure_cache[key] = fn
            self.protos[proto_name(proto)] = {
                name = proto_name(proto),
                proto_id = proto_id(proto),
                chunk_name = proto_chunk_name(proto),
                artifact_key = key,
                source = source,
                bytecode = bytecode,
                fn = fn,
            }
            return fn
        end

        if mode_name ~= "source" then
            U.each(proto_specs, function(proto)
                artifact:realize(proto_name(proto))
            end)
        end

        local entry_fn = artifact:realize(catalog.entry_proto_id)
        artifact.entry = function(...)
            return entry_fn(...)
        end

        return U.leaf(U.EMPTY, function(_state)
            return artifact
        end)
    end)

    function T.CrochetRealizeLua.Catalog:install()
        return install_impl(self)
    end
end
