return function(T, U, P)
    local function N(v)
        return tonumber(v)
    end

    local function B(v)
        return v == true or ((tonumber(v) or 0) ~= 0)
    end

    local function luajit_predicate_for(LJ, pred)
        return U.match(pred, {
            CallPred = function(v)
                return LJ.CallPred(v.fn)
            end,
            EqNumberPred = function(v)
                return LJ.EqNumberPred(v.rhs)
            end,
            GtNumberPred = function(v)
                return LJ.GtNumberPred(v.rhs)
            end,
            LtNumberPred = function(v)
                return LJ.LtNumberPred(v.rhs)
            end,
            ModEqNumberPred = function(v)
                return LJ.ModEqNumberPred(v.divisor, v.remainder)
            end,
        })
    end

    local function fast_body_to_luajit(LJ, body)
        local maps = {}
        for i = 1, #body.maps do
            maps[i] = LJ.MapStep(body.maps[i].fn)
        end

        local guards = {}
        for i = 1, #body.guards do
            guards[i] = LJ.GuardStep(luajit_predicate_for(LJ, body.guards[i].pred))
        end

        local control = LJ.Control(
            N(body.control.drop_count),
            N(body.control.take_count),
            B(body.control.bounded_take)
        )

        return LJ.BodyPlan(maps, guards, control)
    end

    local lower_luajit_impl = U.transition("MoreFunMachine.Spec:lower_luajit", function(spec)
        local LJ = T.MoreFunLuaJIT

        return U.match(spec.loop, {
            ArrayLoop = function(loop)
                local lj_loop = LJ.ArrayLoop(loop.input)
                return U.match(spec.body, {
                    FastBody = function(body)
                        local lj_body = fast_body_to_luajit(LJ, body)
                        return U.match(spec.terminal, {
                            SumPlan = function()
                                return LJ.ArraySum(lj_loop, lj_body)
                            end,
                            FoldlPlan = function(terminal)
                                return LJ.ArrayFoldl(lj_loop, lj_body, terminal.reducer, terminal.init)
                            end,
                            ToTablePlan = function()
                                return LJ.ArrayToTable(lj_loop, lj_body)
                            end,
                            HeadPlan = function()
                                return LJ.ArrayHead(lj_loop, lj_body)
                            end,
                            NthPlan = function(terminal)
                                return LJ.ArrayNth(lj_loop, lj_body, terminal.index)
                            end,
                            AnyPlan = function(terminal)
                                return LJ.ArrayAny(lj_loop, lj_body, luajit_predicate_for(LJ, terminal.pred))
                            end,
                            AllPlan = function(terminal)
                                return LJ.ArrayAll(lj_loop, lj_body, luajit_predicate_for(LJ, terminal.pred))
                            end,
                            MinPlan = function()
                                return LJ.ArrayMin(lj_loop, lj_body)
                            end,
                            MaxPlan = function()
                                return LJ.ArrayMax(lj_loop, lj_body)
                            end,
                        })
                    end,
                    GenericBody = function()
                        return LJ.GenericInstall(spec)
                    end,
                })
            end,
            RangeLoop = function(loop)
                local lj_loop = LJ.RangeLoop(loop.start, loop.stop, loop.step)
                return U.match(spec.body, {
                    FastBody = function(body)
                        local lj_body = fast_body_to_luajit(LJ, body)
                        return U.match(spec.terminal, {
                            SumPlan = function()
                                return LJ.RangeSum(lj_loop, lj_body)
                            end,
                            FoldlPlan = function(terminal)
                                return LJ.RangeFoldl(lj_loop, lj_body, terminal.reducer, terminal.init)
                            end,
                            ToTablePlan = function()
                                return LJ.RangeToTable(lj_loop, lj_body)
                            end,
                            HeadPlan = function()
                                return LJ.RangeHead(lj_loop, lj_body)
                            end,
                            NthPlan = function(terminal)
                                return LJ.RangeNth(lj_loop, lj_body, terminal.index)
                            end,
                            AnyPlan = function(terminal)
                                return LJ.RangeAny(lj_loop, lj_body, luajit_predicate_for(LJ, terminal.pred))
                            end,
                            AllPlan = function(terminal)
                                return LJ.RangeAll(lj_loop, lj_body, luajit_predicate_for(LJ, terminal.pred))
                            end,
                            MinPlan = function()
                                return LJ.RangeMin(lj_loop, lj_body)
                            end,
                            MaxPlan = function()
                                return LJ.RangeMax(lj_loop, lj_body)
                            end,
                        })
                    end,
                    GenericBody = function()
                        return LJ.GenericInstall(spec)
                    end,
                })
            end,
            StringLoop = function(loop)
                local lj_loop = LJ.StringLoop(loop.input)
                return U.match(spec.body, {
                    FastBody = function(body)
                        local lj_body = fast_body_to_luajit(LJ, body)
                        return U.match(spec.terminal, {
                            SumPlan = function()
                                return LJ.GenericInstall(spec)
                            end,
                            FoldlPlan = function(terminal)
                                return LJ.StringFoldl(lj_loop, lj_body, terminal.reducer, terminal.init)
                            end,
                            ToTablePlan = function()
                                return LJ.StringToTable(lj_loop, lj_body)
                            end,
                            HeadPlan = function()
                                return LJ.StringHead(lj_loop, lj_body)
                            end,
                            NthPlan = function(terminal)
                                return LJ.StringNth(lj_loop, lj_body, terminal.index)
                            end,
                            AnyPlan = function(terminal)
                                return LJ.StringAny(lj_loop, lj_body, luajit_predicate_for(LJ, terminal.pred))
                            end,
                            AllPlan = function(terminal)
                                return LJ.StringAll(lj_loop, lj_body, luajit_predicate_for(LJ, terminal.pred))
                            end,
                            MinPlan = function()
                                return LJ.StringMin(lj_loop, lj_body)
                            end,
                            MaxPlan = function()
                                return LJ.StringMax(lj_loop, lj_body)
                            end,
                        })
                    end,
                    GenericBody = function()
                        return LJ.GenericInstall(spec)
                    end,
                })
            end,
            ByteStringLoop = function(loop)
                local lj_loop = LJ.ByteStringLoop(loop.input)
                return U.match(spec.body, {
                    FastBody = function(body)
                        local lj_body = fast_body_to_luajit(LJ, body)
                        return U.match(spec.terminal, {
                            SumPlan = function()
                                return LJ.ByteStringSum(lj_loop, lj_body)
                            end,
                            FoldlPlan = function(terminal)
                                return LJ.ByteStringFoldl(lj_loop, lj_body, terminal.reducer, terminal.init)
                            end,
                            ToTablePlan = function()
                                return LJ.ByteStringToTable(lj_loop, lj_body)
                            end,
                            HeadPlan = function()
                                return LJ.ByteStringHead(lj_loop, lj_body)
                            end,
                            NthPlan = function(terminal)
                                return LJ.ByteStringNth(lj_loop, lj_body, terminal.index)
                            end,
                            AnyPlan = function(terminal)
                                return LJ.ByteStringAny(lj_loop, lj_body, luajit_predicate_for(LJ, terminal.pred))
                            end,
                            AllPlan = function(terminal)
                                return LJ.ByteStringAll(lj_loop, lj_body, luajit_predicate_for(LJ, terminal.pred))
                            end,
                            MinPlan = function()
                                return LJ.ByteStringMin(lj_loop, lj_body)
                            end,
                            MaxPlan = function()
                                return LJ.ByteStringMax(lj_loop, lj_body)
                            end,
                        })
                    end,
                    GenericBody = function()
                        return LJ.GenericInstall(spec)
                    end,
                })
            end,
            RawWhileLoop = function()
                return LJ.GenericInstall(spec)
            end,
            ChainLoop = function()
                return LJ.GenericInstall(spec)
            end,
        })
    end)

    function T.MoreFunMachine.Spec:lower_luajit()
        return lower_luajit_impl(self)
    end
end
