return function(T, U, P)
    local function B(v)
        return v == true or ((tonumber(v) or 0) ~= 0)
    end

    local function prepend(xs, x)
        local out = { x }
        for i = 1, #xs do
            out[i + 1] = xs[i]
        end
        return out
    end

    local function machine_predicate_for(MT, pred)
        return U.match(pred, {
            CallPred = function(v)
                return MT.CallPred(v.fn)
            end,
            EqNumberPred = function(v)
                return MT.EqNumberPred(v.rhs)
            end,
            GtNumberPred = function(v)
                return MT.GtNumberPred(v.rhs)
            end,
            LtNumberPred = function(v)
                return MT.LtNumberPred(v.rhs)
            end,
            ModEqNumberPred = function(v)
                return MT.ModEqNumberPred(v.divisor, v.remainder)
            end,
        })
    end

    local function machine_pipe_for(MT, pipe)
        return U.match(pipe, {
            EndPipe = function()
                return MT.EndPipe
            end,
            MapPipe = function(v)
                return MT.MapPipe(v.fn, machine_pipe_for(MT, v.next))
            end,
            GuardPipe = function(v)
                return MT.GuardPipe(machine_predicate_for(MT, v.pred), machine_pipe_for(MT, v.next))
            end,
            TakePipe = function(v)
                return MT.TakePipe(v.count, machine_pipe_for(MT, v.next))
            end,
            DropPipe = function(v)
                return MT.DropPipe(v.count, machine_pipe_for(MT, v.next))
            end,
        })
    end

    local function classify_pipe(MT, pipe)
        return U.match(pipe, {
            EndPipe = function()
                return {
                    fast = true,
                    can_prepend_guard = true,
                    can_prepend_drop = true,
                    can_prepend_take = true,
                    maps = {},
                    guards = {},
                    drop_count = 0,
                    take_count = 0,
                    bounded_take = false,
                }
            end,
            MapPipe = function(v)
                local child = classify_pipe(MT, v.next)
                if not child.fast then return child end
                return {
                    fast = true,
                    can_prepend_guard = false,
                    can_prepend_drop = false,
                    can_prepend_take = false,
                    maps = prepend(child.maps, MT.MapStep(v.fn)),
                    guards = child.guards,
                    drop_count = child.drop_count,
                    take_count = child.take_count,
                    bounded_take = child.bounded_take,
                }
            end,
            GuardPipe = function(v)
                local child = classify_pipe(MT, v.next)
                if not child.fast or not child.can_prepend_guard then
                    return {
                        fast = false,
                        pipe = machine_pipe_for(MT, pipe),
                    }
                end
                return {
                    fast = true,
                    can_prepend_guard = true,
                    can_prepend_drop = false,
                    can_prepend_take = false,
                    maps = child.maps,
                    guards = prepend(child.guards, MT.GuardStep(machine_predicate_for(MT, v.pred))),
                    drop_count = child.drop_count,
                    take_count = child.take_count,
                    bounded_take = child.bounded_take,
                }
            end,
            DropPipe = function(v)
                local child = classify_pipe(MT, v.next)
                if not child.fast or not child.can_prepend_drop then
                    return {
                        fast = false,
                        pipe = machine_pipe_for(MT, pipe),
                    }
                end
                return {
                    fast = true,
                    can_prepend_guard = true,
                    can_prepend_drop = true,
                    can_prepend_take = false,
                    maps = child.maps,
                    guards = child.guards,
                    drop_count = child.drop_count + tonumber(v.count),
                    take_count = child.take_count,
                    bounded_take = child.bounded_take,
                }
            end,
            TakePipe = function(v)
                local child = classify_pipe(MT, v.next)
                if not child.fast or not child.can_prepend_take then
                    return {
                        fast = false,
                        pipe = machine_pipe_for(MT, pipe),
                    }
                end
                local count = tonumber(v.count)
                local take_count = child.bounded_take and math.min(child.take_count, count) or count
                return {
                    fast = true,
                    can_prepend_guard = true,
                    can_prepend_drop = true,
                    can_prepend_take = true,
                    maps = child.maps,
                    guards = child.guards,
                    drop_count = child.drop_count,
                    take_count = take_count,
                    bounded_take = true,
                }
            end,
        })
    end

    local define_machine_impl = U.transition("MoreFunLowered.Spec:define_machine", function(spec)
        local MT = T.MoreFunMachine
        local errs = U.errors()
        local classified = classify_pipe(MT, spec.pipe)

        local body
        if classified.fast then
            body = MT.FastBody(
                classified.maps,
                classified.guards,
                MT.Control(classified.drop_count, classified.take_count, B(classified.bounded_take))
            )
        else
            body = MT.GenericBody(classified.pipe)
        end

        local loop = U.match(spec.source, {
            ArraySource = function(source)
                return MT.ArrayLoop(source.input)
            end,
            RangeSource = function(source)
                return MT.RangeLoop(source.start, source.stop, source.step)
            end,
            StringSource = function(source)
                return MT.StringLoop(source.input)
            end,
            ByteStringSource = function(source)
                return MT.ByteStringLoop(source.input)
            end,
            RawIterSource = function(source)
                return MT.RawWhileLoop(source.gen, source.param, source.state0)
            end,
            ChainSource = function(source)
                local parts = errs:each(source.parts, function(part)
                    return U.match(part, {
                        ArraySource = function(v) return MT.ArrayLoop(v.input) end,
                        RangeSource = function(v) return MT.RangeLoop(v.start, v.stop, v.step) end,
                        StringSource = function(v) return MT.StringLoop(v.input) end,
                        ByteStringSource = function(v) return MT.ByteStringLoop(v.input) end,
                        RawIterSource = function(v) return MT.RawWhileLoop(v.gen, v.param, v.state0) end,
                        ChainSource = function()
                            error("MoreFunLowered.Spec:define_machine(): nested ChainSource not yet supported", 2)
                        end,
                    })
                end)
                return MT.ChainLoop(parts)
            end,
        })

        local terminal = U.match(spec.terminal, {
            SumTerminal = function()
                return MT.SumPlan
            end,
            FoldlTerminal = function(terminal)
                return MT.FoldlPlan(terminal.reducer, terminal.init)
            end,
            ToTableTerminal = function()
                return MT.ToTablePlan
            end,
            HeadTerminal = function()
                return MT.HeadPlan
            end,
            NthTerminal = function(terminal)
                return MT.NthPlan(terminal.index)
            end,
            AnyTerminal = function(terminal)
                return MT.AnyPlan(machine_predicate_for(MT, terminal.pred))
            end,
            AllTerminal = function(terminal)
                return MT.AllPlan(machine_predicate_for(MT, terminal.pred))
            end,
            MinTerminal = function()
                return MT.MinPlan
            end,
            MaxTerminal = function()
                return MT.MaxPlan
            end,
        })

        return MT.Spec(loop, body, terminal), errs:get()
    end)

    function T.MoreFunLowered.Spec:define_machine()
        return define_machine_impl(self)
    end
end
