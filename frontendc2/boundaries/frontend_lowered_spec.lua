local ffi = require("ffi")

return function(T, U, P)
    local function S(v)
        if type(v) == "cdata" then return ffi.string(v) end
        return tostring(v)
    end

    local function N(v)
        return tonumber(v)
    end

    local function B(v)
        return v == true or ((tonumber(v) or 0) ~= 0)
    end

    local function builder_family_and_param_state(MT, builder_facet)
        if builder_facet.kind == "ValidateBuilderFacet" then
            return MT.ValidateBuilder, MT.ValidateBuilderParam, MT.ValidateBuilderState
        elseif builder_facet.kind == "AstArenaBuilderFacet" then
            local arena = builder_facet.arena
            return MT.AstArenaBuilder,
                MT.AstArenaBuilderParam(MT.ArenaLayout(
                    B(arena.keeps_source_spans),
                    B(arena.uses_list_ranges),
                    B(arena.interns_scalars)
                )),
                MT.AstArenaBuilderState(MT.ArenaState(true, true, B(arena.interns_scalars)))
        elseif builder_facet.kind == "DecodeBuilderFacet" then
            local decode = builder_facet.decode
            return MT.DecodeBuilder,
                MT.DecodeBuilderParam(MT.DecodeLayout(
                    B(decode.decodes_strings),
                    B(decode.decodes_numbers),
                    B(decode.builds_arrays),
                    B(decode.builds_objects)
                )),
                MT.DecodeBuilderState(MT.DecodeState(true, true, true))
        elseif builder_facet.kind == "ExecIRBuilderFacet" then
            local exec_ir = builder_facet.exec_ir
            return MT.ExecIRBuilder,
                MT.ExecIRBuilderParam(MT.ExecIRLayout(
                    B(exec_ir.appends_ops),
                    B(exec_ir.appends_consts),
                    B(exec_ir.uses_value_ids)
                )),
                MT.ExecIRBuilderState(MT.ExecIRState(true, true, true))
        end
        error("FrontendLowered.Spec:define_machine(): unknown BuilderFacet kind '" .. tostring(builder_facet.kind) .. "'", 2)
    end

    local function find_product_header(products, product_id)
        for i = 1, #products do
            local header = products[i]
            if N(header.id) == N(product_id) then return header end
        end
        return nil
    end

    local function define_machine_impl(spec)
        local MT = T.FrontendMachine

        if spec.kind == "TokenFrontier" then
            error("FrontendLowered.Spec:define_machine(): token frontier machine definition not implemented yet in frontendc2", 2)
        end

        local scan = spec.scan
        local products = {}

        local any_strings = #scan.string_plans > 0
        local any_numbers = #scan.number_plans > 0
        local any_keywords = #scan.keyword_dispatches > 0
        local any_containers = false
        for i = 1, #spec.exec_facets do
            local exec = spec.exec_facets[i]
            if exec.kind == "StructuralSeqExecFacet" then
                for j = 1, #exec.steps do
                    if exec.steps[j].kind == "StructuralDelimitedGroup" or exec.steps[j].kind == "StructuralSeparatedListGroup" then
                        any_containers = true
                        break
                    end
                end
            elseif exec.kind == "StructuralChoiceExecFacet" then
                for a = 1, #exec.arms do
                    local steps = exec.arms[a].steps
                    for j = 1, #steps do
                        if steps[j].kind == "StructuralDelimitedGroup" or steps[j].kind == "StructuralSeparatedListGroup" then
                            any_containers = true
                            break
                        end
                    end
                    if any_containers then break end
                end
            end
            if any_containers then break end
        end

        local lookahead_by_rule_id = {}
        for i = 1, #spec.lookahead_facets do
            local f = spec.lookahead_facets[i]
            lookahead_by_rule_id[N(f.rule_id)] = f
        end

        local function build_validate_program()
            local terminals = {}
            local choices = {}
            local ops = {}

            local function lower_validate_terminal(term)
                if term.kind == "ExpectFixedToken" then
                    return MT.ExpectFixedToken(S(term.text), term.boundary_policy)
                elseif term.kind == "ExpectQuotedString" then
                    return MT.ExpectQuotedString(N(term.string_id))
                elseif term.kind == "ExpectNumber" then
                    return MT.ExpectNumber(N(term.number_id))
                elseif term.kind == "ExpectByteRun" then
                    return MT.ExpectByteRun(term.allowed_bitset_words, term.cardinality)
                end
                error("FrontendLowered.Spec:define_machine(): unknown StructuralTerminal kind '" .. tostring(term.kind) .. "'", 2)
            end

            local function intern_terminal(term)
                terminals[#terminals + 1] = lower_validate_terminal(term)
                return #terminals
            end

            local emit_steps
            local emit_rule_body

            emit_steps = function(steps)
                local start_pc = #ops + 1
                local delayed = {}
                for i = 1, #steps do
                    local step = steps[i]
                    local idx = #ops + 1
                    if step.kind == "ExpectTerminal" then
                        ops[idx] = MT.ExpectTerminal(intern_terminal(step.terminal))
                    elseif step.kind == "StructuralCallRule" then
                        ops[idx] = MT.CallRule(N(step.header.id))
                    elseif step.kind == "StructuralOptionalGroup" then
                        ops[idx] = false
                        delayed[#delayed + 1] = { kind = "OptionalGroup", idx = idx, step = step }
                    elseif step.kind == "StructuralRepeatGroup" then
                        ops[idx] = false
                        delayed[#delayed + 1] = { kind = "RepeatGroup", idx = idx, step = step }
                    elseif step.kind == "StructuralDelimitedGroup" then
                        ops[idx] = false
                        delayed[#delayed + 1] = { kind = "DelimitedGroup", idx = idx, step = step }
                    elseif step.kind == "StructuralSeparatedListGroup" then
                        ops[idx] = false
                        delayed[#delayed + 1] = { kind = "SeparatedListGroup", idx = idx, step = step }
                    else
                        error("FrontendLowered.Spec:define_machine(): unknown StructuralStep kind '" .. tostring(step.kind) .. "'", 2)
                    end
                end
                local return_pc = #ops + 1
                ops[return_pc] = MT.Return
                for i = 1, #delayed do
                    local item = delayed[i]
                    local next_pc = item.idx + 1
                    if item.kind == "OptionalGroup" then
                        local body_pc = emit_steps(item.step.steps)
                        ops[item.idx] = MT.OptionalGroup(N(item.step.set_id), body_pc, next_pc)
                    elseif item.kind == "RepeatGroup" then
                        local body_pc = emit_steps(item.step.steps)
                        ops[item.idx] = MT.RepeatGroup(N(item.step.set_id), body_pc, next_pc)
                    elseif item.kind == "DelimitedGroup" then
                        local body_pc = emit_steps(item.step.inner_steps)
                        ops[item.idx] = MT.DelimitedGroup(N(item.step.open_byte), body_pc, N(item.step.close_byte), next_pc)
                    elseif item.kind == "SeparatedListGroup" then
                        local body_pc = emit_steps(item.step.item_steps)
                        ops[item.idx] = MT.SeparatedListGroup(
                            N(item.step.item_set_id),
                            body_pc,
                            N(item.step.separator_byte),
                            item.step.cardinality,
                            item.step.trailing_policy,
                            next_pc
                        )
                    end
                end
                return start_pc
            end

            emit_rule_body = function(exec)
                local start_pc = #ops + 1
                if exec.kind == "StructuralTerminalExecFacet" then
                    ops[start_pc] = MT.ExpectTerminal(intern_terminal(exec.terminal))
                    ops[start_pc + 1] = MT.Return
                    return start_pc
                elseif exec.kind == "StructuralSeqExecFacet" then
                    return emit_steps(exec.steps)
                elseif exec.kind == "StructuralChoiceExecFacet" then
                    local choice_pc = #ops + 1
                    ops[choice_pc] = false
                    local return_pc = choice_pc + 1
                    ops[return_pc] = MT.Return
                    local arms = {}
                    for a = 1, #exec.arms do
                        local arm = exec.arms[a]
                        arms[a] = MT.ValidateChoiceArm(N(arm.set_id), emit_steps(arm.steps))
                    end
                    local choice_id = #choices + 1
                    choices[choice_id] = MT.ValidateChoice(choice_id, arms)
                    ops[choice_pc] = MT.Choice(choice_id)
                    return choice_pc
                end
                error("FrontendLowered.Spec:define_machine(): unknown StructuralExecFacet kind '" .. tostring(exec.kind) .. "'", 2)
            end

            local rules = {}
            for i = 1, #spec.exec_facets do
                local exec = spec.exec_facets[i]
                local rule_id = N(exec.rule_id)
                local look = lookahead_by_rule_id[rule_id]
                if look == nil then
                    error("FrontendLowered.Spec:define_machine(): missing lookahead facet for rule id '" .. tostring(rule_id) .. "'", 2)
                end
                rules[i] = MT.ValidateRule(
                    rule_id,
                    N(look.first_set_id),
                    B(look.nullable),
                    emit_rule_body(exec)
                )
            end

            return terminals, choices, rules, ops
        end

        for i = 1, #spec.product_facets do
            local product_facet = spec.product_facets[i]
            local product_header = find_product_header(spec.grammar.products, product_facet.product_id)
            if product_header == nil then
                error("FrontendLowered.Spec:define_machine(): missing product header for product id '" .. tostring(N(product_facet.product_id)) .. "'", 2)
            end

            if product_facet.builder.kind == "ValidateBuilderFacet" then
                local terminals, choices, rules, ops = build_validate_program()
                products[i] = MT.StructuralValidateMachine(
                    product_header,
                    MT.ValidateParseMachine(
                        MT.ValidateParseGen(
                            scan.input,
                            any_strings,
                            any_numbers,
                            any_keywords,
                            any_containers,
                            false
                        ),
                        MT.ValidateParseParam(
                            N(product_facet.entry_rule_id),
                            scan.skips,
                            scan.string_plans,
                            scan.number_plans,
                            scan.first_byte_sets,
                            terminals,
                            choices,
                            rules,
                            ops
                        ),
                        MT.ValidateParseState(
                            MT.CursorState(false),
                            MT.ControlStackState(#spec.rules + 8),
                            MT.DiagnosticState(false, true, true)
                        )
                    )
                )
            else
                local builder_family, builder_param, builder_state = builder_family_and_param_state(MT, product_facet.builder)
                products[i] = MT.StructuralFrontierMachine(
                    product_header,
                    MT.StructuralParseMachine(
                        builder_family,
                        MT.StructuralParseGen(
                            scan.input,
                            any_strings,
                            any_numbers,
                            any_keywords,
                            any_containers,
                            false
                        ),
                        MT.StructuralParseParam(
                            N(product_facet.entry_rule_id),
                            scan.skips,
                            scan.byte_classes,
                            scan.keyword_dispatches,
                            scan.string_plans,
                            scan.number_plans,
                            scan.first_byte_sets,
                            spec.rules,
                            spec.lookahead_facets,
                            spec.exec_facets,
                            spec.result_facets,
                            builder_param
                        ),
                        MT.StructuralParseState(
                            MT.CursorState(false),
                            MT.ControlStackState(#spec.rules + 8),
                            MT.PayloadScratchState(false, any_strings, any_numbers, false),
                            builder_state,
                            MT.DiagnosticState(false, true, true)
                        )
                    )
                )
            end
        end

        local binding_plans = {}
        for i = 1, #spec.package_facet.bindings do
            local binding = spec.package_facet.bindings[i]
            local product_header = find_product_header(spec.grammar.products, binding.product_id)
            if product_header == nil then
                error("FrontendLowered.Spec:define_machine(): missing product header for binding product id '" .. tostring(N(binding.product_id)) .. "'", 2)
            end
            if binding.kind == "DirectBindingFacet" then
                binding_plans[i] = MT.DirectBindingPlan(product_header, binding.parse, binding.output)
            elseif binding.kind == "TokenizedBindingFacet" then
                binding_plans[i] = MT.TokenizedBindingPlan(product_header, binding.scan, binding.parse, binding.token_runtime, binding.output)
            else
                error("FrontendLowered.Spec:define_machine(): unknown BindingFacet kind '" .. tostring(binding.kind) .. "'", 2)
            end
        end

        return MT.Spec(products, MT.PackagePlan(binding_plans))
    end

    local define_machine_transition = U.transition(define_machine_impl)

    function T.FrontendLowered.Spec:define_machine()
        return U.match(self, {
            StructuralFrontier = function(x) return define_machine_transition(x) end,
            TokenFrontier = function(x) return define_machine_transition(x) end,
        })
    end

    function T.FrontendLowered.StructuralFrontier:define_machine()
        return define_machine_transition(self)
    end

    function T.FrontendLowered.TokenFrontier:define_machine()
        return define_machine_transition(self)
    end
end
