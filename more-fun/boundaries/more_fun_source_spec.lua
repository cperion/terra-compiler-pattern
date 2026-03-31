local U = require("unit")

return function(T, U, P)
    local function lowered_predicate_for(L, pred)
        return U.match(pred, {
            CallPred = function(v)
                return L.CallPred(v.fn)
            end,
            EqNumberPred = function(v)
                return L.EqNumberPred(v.rhs)
            end,
            GtNumberPred = function(v)
                return L.GtNumberPred(v.rhs)
            end,
            LtNumberPred = function(v)
                return L.LtNumberPred(v.rhs)
            end,
            ModEqNumberPred = function(v)
                return L.ModEqNumberPred(v.divisor, v.remainder)
            end,
        })
    end

    local function lowered_source_for(L, errs, source)
        return U.match(source, {
            ArraySource = function(v)
                return L.ArraySource(v.input)
            end,
            RangeSource = function(v)
                return L.RangeSource(v.start, v.stop, v.step)
            end,
            StringSource = function(v)
                return L.StringSource(v.input)
            end,
            ByteStringSource = function(v)
                return L.ByteStringSource(v.input)
            end,
            RawIterSource = function(v)
                return L.RawIterSource(v.gen, v.param, v.state0)
            end,
            ChainSource = function(v)
                local parts = errs:each(v.parts, function(part)
                    return lowered_source_for(L, errs, part)
                end)
                return L.ChainSource(parts)
            end,
        })
    end

    local function lowered_pipe_for(L, pipe)
        return U.match(pipe, {
            EndPipe = function()
                return L.EndPipe
            end,
            MapPipe = function(v)
                return L.MapPipe(v.fn, lowered_pipe_for(L, v.next))
            end,
            FilterPipe = function(v)
                return L.GuardPipe(lowered_predicate_for(L, v.pred), lowered_pipe_for(L, v.next))
            end,
            TakePipe = function(v)
                return L.TakePipe(v.count, lowered_pipe_for(L, v.next))
            end,
            DropPipe = function(v)
                return L.DropPipe(v.count, lowered_pipe_for(L, v.next))
            end,
        })
    end

    local function lowered_terminal_for(L, terminal)
        return U.match(terminal, {
            SumTerminal = function()
                return L.SumTerminal
            end,
            FoldlTerminal = function(v)
                return L.FoldlTerminal(v.reducer, v.init)
            end,
            ToTableTerminal = function()
                return L.ToTableTerminal
            end,
            HeadTerminal = function()
                return L.HeadTerminal
            end,
            NthTerminal = function(v)
                return L.NthTerminal(v.index)
            end,
            AnyTerminal = function(v)
                return L.AnyTerminal(lowered_predicate_for(L, v.pred))
            end,
            AllTerminal = function(v)
                return L.AllTerminal(lowered_predicate_for(L, v.pred))
            end,
            MinTerminal = function()
                return L.MinTerminal
            end,
            MaxTerminal = function()
                return L.MaxTerminal
            end,
        })
    end

    local lower_impl = U.transition("MoreFunSource.Spec:lower", function(spec)
        local L = T.MoreFunLowered
        local errs = U.errors()

        return L.Spec(
            lowered_source_for(L, errs, spec.source),
            lowered_pipe_for(L, spec.pipe),
            lowered_terminal_for(L, spec.terminal)
        ), errs:get()
    end)

    function T.MoreFunSource.Spec:lower()
        return lower_impl(self)
    end
end
