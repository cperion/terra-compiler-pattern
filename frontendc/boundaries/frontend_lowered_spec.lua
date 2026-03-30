local ffi = require("ffi")
local bit = require("bit")

local bor = bit.bor
local lshift = bit.lshift
local byte = string.byte
local sort = table.sort

return function(T, U, P)
    local function S(v)
        if type(v) == "cdata" then return ffi.string(v) end
        return tostring(v)
    end

    local function N(v)
        return tonumber(v)
    end

    local function split_path(Path, fqname)
        local parts = {}
        fqname = S(fqname)
        for part in fqname:gmatch("[^.]+") do
            parts[#parts + 1] = part
        end
        return Path(parts)
    end

    local function build_charset_lookup(charset, lookup)
        lookup = lookup or {}
        local kind = charset.kind
        if kind == "AsciiLetters" then
            for c = 65, 90 do lookup[c] = true end
            for c = 97, 122 do lookup[c] = true end
            return lookup
        end
        if kind == "AsciiDigits" then
            for c = 48, 57 do lookup[c] = true end
            return lookup
        end
        if kind == "Underscore" then
            lookup[95] = true
            return lookup
        end
        if kind == "Union" then
            for i = 1, #charset.parts do
                build_charset_lookup(charset.parts[i], lookup)
            end
            return lookup
        end
        error("FrontendLowered.Spec:define_machine(): unknown CharSet kind '" .. tostring(kind) .. "'", 2)
    end

    local function lookup_to_words(lookup)
        local words = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for c = 0, 255 do
            if lookup[c] then
                local wi = math.floor(c / 32) + 1
                words[wi] = bor(words[wi], lshift(1, c % 32))
            end
        end
        return words
    end

    local function first_set_words(headers)
        local lookup = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for i = 1, #headers do
            local token_id = N(headers[i].token_id)
            local wi = math.floor(token_id / 32) + 1
            lookup[wi] = bor(lookup[wi], lshift(1, token_id % 32))
        end
        return lookup
    end

    local function intern_first_set(MT, cache, rows, headers)
        local ids = {}
        for i = 1, #headers do ids[i] = N(headers[i].token_id) end
        sort(ids)
        local key = table.concat(ids, ",")
        local existing = cache[key]
        if existing ~= nil then return existing end
        local set_id = #rows + 1
        rows[set_id] = MT.FirstSetTable(set_id, first_set_words(headers))
        cache[key] = set_id
        return set_id
    end

    local function lower_arg_source(MT, source)
        local kind = source.kind
        if kind == "ReadSlot" then return MT.ReadSlot(N(source.slot_id)) end
        if kind == "ReadPresent" then return MT.ReadPresent(N(source.slot_id)) end
        if kind == "ReadJoined" then return MT.ReadJoined(N(source.slot_id), source.separator) end
        if kind == "ReadConstBool" then return MT.ReadConstBool(source.value and true or false) end
        error("FrontendLowered.Spec:define_machine(): unknown SlotSource kind '" .. tostring(kind) .. "'", 2)
    end

    local define_machine_impl = U.transition(function(spec)
        local MT = T.FrontendMachine
        local target = spec.target

        local tokenize_header = MT.BoundaryHeader(
            split_path(MT.Path, target.tokenize_receiver_fqname),
            S(target.tokenize_verb)
        )
        local parse_header = MT.BoundaryHeader(
            split_path(MT.Path, target.parse_receiver_fqname),
            S(target.parse_verb)
        )

        local token_ctors = {}
        local fixed_dispatch_by_first = {}
        local ident_dispatches = {}
        local eof_ctor_id = nil
        local ident_continue_any = {}

        for i = 1, #spec.tokenizer.tokens do
            local plan = spec.tokenizer.tokens[i]
            local header = plan.header
            local token_id = N(header.token_id)
            local name = S(header.name)
            token_ctors[#token_ctors + 1] = MT.CtorRef(
                token_id,
                MT.Path({ S(target.token_phase_name), name })
            )
            if name == "Eof" then eof_ctor_id = token_id end

            if plan.kind == "FixedToken" then
                local text = S(plan.text)
                if #text > 0 then
                    local first = byte(text, 1)
                    local cases = fixed_dispatch_by_first[first]
                    if cases == nil then
                        cases = {}
                        fixed_dispatch_by_first[first] = cases
                    end
                    local requires_word_boundary = false
                    local last = byte(text, #text)
                    requires_word_boundary = ident_continue_any[last] == true
                    cases[#cases + 1] = MT.FixedCase(text, header, requires_word_boundary)
                end
            elseif plan.kind == "IdentToken" then
                local start_lookup = build_charset_lookup(plan.start_set)
                local continue_lookup = build_charset_lookup(plan.continue_set)
                for c = 0, 255 do
                    if continue_lookup[c] then ident_continue_any[c] = true end
                end
                ident_dispatches[#ident_dispatches + 1] = MT.IdentDispatch(
                    header,
                    lookup_to_words(start_lookup),
                    lookup_to_words(continue_lookup)
                )
            else
                error("FrontendLowered.Spec:define_machine(): unknown TokenPlan kind '" .. tostring(plan.kind) .. "'", 2)
            end
        end

        local fixed_dispatches = {}
        for first, cases in pairs(fixed_dispatch_by_first) do
            sort(cases, function(a, b) return #S(a.text) > #S(b.text) end)
            fixed_dispatches[#fixed_dispatches + 1] = MT.FixedDispatch(first, cases)
        end
        sort(fixed_dispatches, function(a, b) return N(a.first_byte) < N(b.first_byte) end)

        for i = 1, #fixed_dispatches do
            local dispatch = fixed_dispatches[i]
            for j = 1, #dispatch.cases do
                local case = dispatch.cases[j]
                if #S(case.text) > 0 then
                    local last = byte(S(case.text), #S(case.text))
                    dispatch.cases[j] = MT.FixedCase(
                        S(case.text),
                        case.header,
                        ident_continue_any[last] == true
                    )
                end
            end
        end

        if eof_ctor_id == nil then
            error("FrontendLowered.Spec:define_machine(): tokenizer must define Eof token", 2)
        end

        local result_ctor_by_fqname = {}
        local result_ctors = {}
        local function result_ctor_id_for(ctor)
            local fqname = S(ctor.ctor_fqname)
            local existing = result_ctor_by_fqname[fqname]
            if existing ~= nil then return existing end
            local ctor_id = #result_ctors + 1
            result_ctors[ctor_id] = MT.CtorRef(ctor_id, split_path(MT.Path, fqname))
            result_ctor_by_fqname[fqname] = ctor_id
            return ctor_id
        end

        local function lower_result_plan(plan)
            if plan.kind == "ReturnEmpty" then
                return MT.ReturnEmpty
            end
            if plan.kind == "ReturnSlot" then
                return MT.ReturnSlot(N(plan.slot_id))
            end
            if plan.kind == "ReturnCtor" then
                local args = {}
                for i = 1, #plan.fields do
                    args[i] = lower_arg_source(MT, plan.fields[i].source)
                end
                return MT.ReturnCtor(result_ctor_id_for(plan.ctor), args)
            end
            error("FrontendLowered.Spec:define_machine(): unknown ResultPlan kind '" .. tostring(plan.kind) .. "'", 2)
        end

        local first_set_cache = {}
        local first_sets = {}

        local function lower_step(op)
            local kind = op.kind
            if kind == "ExpectToken" then
                return MT.ExpectToken(op.header, N(op.capture_slot))
            end
            if kind == "CallRule" then
                return MT.CallRule(N(op.header.rule_id), N(op.capture_slot))
            end
            if kind == "OptionalIfFirst" then
                local steps = {}
                for i = 1, #op.ops do steps[i] = lower_step(op.ops[i]) end
                return MT.OptionalGroup(intern_first_set(MT, first_set_cache, first_sets, op.first_set), steps)
            end
            if kind == "RepeatWhileFirst" then
                local steps = {}
                for i = 1, #op.ops do steps[i] = lower_step(op.ops[i]) end
                return MT.RepeatGroup(intern_first_set(MT, first_set_cache, first_sets, op.first_set), steps)
            end
            if kind == "BeginSeq" or kind == "EndSeq" then
                return nil
            end
            error("FrontendLowered.Spec:define_machine(): unsupported ParseOp kind '" .. tostring(kind) .. "'", 2)
        end

        local rules = {}
        for i = 1, #spec.parser.rules do
            local rule = spec.parser.rules[i]
            local ops = rule.ops
            local result = lower_result_plan(rule.result)

            if #ops == 1 and ops[1].kind == "ExpectToken" then
                rules[#rules + 1] = MT.TokenRule(
                    N(rule.header.rule_id),
                    ops[1].header,
                    N(ops[1].capture_slot),
                    result
                )
            elseif #ops == 1 and ops[1].kind == "Branch" then
                local arms = {}
                for j = 1, #ops[1].arms do
                    local arm = ops[1].arms[j]
                    local steps = {}
                    for k = 1, #arm.ops do
                        local step = lower_step(arm.ops[k])
                        if step ~= nil then steps[#steps + 1] = step end
                    end
                    arms[j] = MT.ChoiceArm(
                        intern_first_set(MT, first_set_cache, first_sets, arm.first_set),
                        steps
                    )
                end
                rules[#rules + 1] = MT.ChoiceRule(
                    N(rule.header.rule_id),
                    arms,
                    result
                )
            else
                local steps = {}
                for j = 1, #ops do
                    local step = lower_step(ops[j])
                    if step ~= nil then steps[#steps + 1] = step end
                end
                rules[#rules + 1] = MT.SeqRule(
                    N(rule.header.rule_id),
                    steps,
                    result
                )
            end
        end
        sort(rules, function(a, b) return N(a.rule_id) < N(b.rule_id) end)

        return MT.Spec(
            MT.TokenizeBoundary(
                tokenize_header,
                split_path(MT.Path, target.token_spec_ctor_fqname),
                MT.Path({ S(target.token_phase_name), "Span" }),
                token_ctors,
                eof_ctor_id,
                spec.tokenizer.skips,
                fixed_dispatches,
                ident_dispatches
            ),
            MT.ParseBoundary(
                parse_header,
                split_path(MT.Path, target.source_spec_ctor_fqname),
                result_ctors,
                first_sets,
                rules,
                N(spec.parser.entry_rule.rule_id)
            )
        )
    end)

    function T.FrontendLowered.Spec:define_machine()
        return define_machine_impl(self)
    end
end
