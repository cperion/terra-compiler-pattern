local ffi = require("ffi")
local bit = require("bit")

local band = bit.band
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

    local function B(v)
        return v == true or ((tonumber(v) or 0) ~= 0)
    end

    local lower_impl = U.transition(function(spec)
        local LT = T.FrontendLowered
        local CT = T.FrontendChecked

        local max_token_id = 0
        local ident_continue_any = {}
        local ident_dispatches = {}
        local quoted_string_dispatches = {}
        local number_dispatches = {}

        for i = 1, #spec.lexer.tokens do
            local token = spec.lexer.tokens[i]
            max_token_id = math.max(max_token_id, N(token.header.token_id))
            if token.kind == "IdentToken" then
                local start_words = token.start_set.bitset_words
                local continue_words = token.continue_set.bitset_words
                for c = 0, 255 do
                    local wi = math.floor(c / 32) + 1
                    if band(N(continue_words[wi] or 0), lshift(1, c % 32)) ~= 0 then
                        ident_continue_any[c] = true
                    end
                end
                ident_dispatches[#ident_dispatches + 1] = LT.IdentDispatch(
                    token.header,
                    start_words,
                    continue_words
                )
            elseif token.kind == "QuotedStringToken" then
                local quote_char = S(token.quote_char)
                if #quote_char ~= 1 then
                    error("FrontendChecked.Spec:lower(): QuotedStringToken requires one-byte quote_char", 2)
                end
                quoted_string_dispatches[#quoted_string_dispatches + 1] = LT.QuotedStringDispatch(
                    token.header,
                    byte(quote_char, 1),
                    B(token.backslash_escapes)
                )
            elseif token.kind == "NumberToken" then
                number_dispatches[#number_dispatches + 1] = LT.NumberDispatch(token.header)
            end
        end

        local eof_header = CT.TokenHeader("Eof", max_token_id + 1, CT.NoTokenPayload)

        local fixed_dispatch_by_first = {}
        for i = 1, #spec.lexer.tokens do
            local token = spec.lexer.tokens[i]
            if token.kind == "KeywordToken" or token.kind == "PunctToken" then
                local text = S(token.text)
                if #text > 0 then
                    local first = byte(text, 1)
                    local cases = fixed_dispatch_by_first[first]
                    if cases == nil then
                        cases = {}
                        fixed_dispatch_by_first[first] = cases
                    end
                    local last = byte(text, #text)
                    cases[#cases + 1] = LT.FixedCase(text, token.header, ident_continue_any[last] == true)
                end
            end
        end

        local fixed_dispatches = {}
        for first, cases in pairs(fixed_dispatch_by_first) do
            sort(cases, function(a, b) return #S(a.text) > #S(b.text) end)
            fixed_dispatches[#fixed_dispatches + 1] = LT.FixedDispatch(first, cases)
        end
        sort(fixed_dispatches, function(a, b) return N(a.first_byte) < N(b.first_byte) end)

        local first_set_cache = {}
        local first_sets = {}
        local function intern_first_set_token_ids(token_ids)
            local ids = {}
            for i = 1, #token_ids do ids[i] = N(token_ids[i]) end
            sort(ids)
            local key = table.concat(ids, ",")
            local existing = first_set_cache[key]
            if existing ~= nil then return existing end
            local words = { 0, 0, 0, 0, 0, 0, 0, 0 }
            for i = 1, #ids do
                local id = ids[i]
                local wi = math.floor(id / 32) + 1
                words[wi] = bor(words[wi], lshift(1, id % 32))
            end
            local set_id = #first_sets + 1
            first_sets[set_id] = LT.FirstSetTable(set_id, words)
            first_set_cache[key] = set_id
            return set_id
        end

        local rule_by_id = {}
        local max_rule_id = 0
        for i = 1, #spec.parser.rules do
            local rule = spec.parser.rules[i]
            rule_by_id[N(rule.header.rule_id)] = rule
            max_rule_id = math.max(max_rule_id, N(rule.header.rule_id))
        end

        local result_info_by_rule = {}
        for i = 1, #spec.parser.rules do
            local rule = spec.parser.rules[i]
            result_info_by_rule[N(rule.header.rule_id)] = {
                value_kind = "unknown",
                is_list = false,
                nullable = false,
            }
        end

        local function clone_info(info)
            return {
                value_kind = info.value_kind,
                is_list = info.is_list and true or false,
                nullable = info.nullable and true or false,
            }
        end

        local function same_info(a, b)
            return a.value_kind == b.value_kind
                and (a.is_list and true or false) == (b.is_list and true or false)
                and (a.nullable and true or false) == (b.nullable and true or false)
        end

        local function token_value_info(header)
            return {
                value_kind = header.payload_shape.kind == "StringTokenPayload" and "string" or "none",
                is_list = false,
                nullable = false,
            }
        end

        local function choice_info(infos)
            local out = nil
            for i = 1, #infos do
                local info = infos[i]
                if out == nil then
                    out = clone_info(info)
                else
                    if out.value_kind ~= info.value_kind or (out.is_list and true or false) ~= (info.is_list and true or false) then
                        out.value_kind = "none"
                        out.is_list = false
                    end
                    out.nullable = out.nullable or info.nullable
                end
            end
            return out or { value_kind = "none", is_list = false, nullable = false }
        end

        local function analyze_expr_value_info(expr, capture_info_by_slot)
            if expr.kind == "TokenRef" then
                return token_value_info(expr.header)
            elseif expr.kind == "RuleRef" then
                return clone_info(result_info_by_rule[N(expr.header.rule_id)])
            elseif expr.kind == "Seq" then
                for i = 1, #expr.items do
                    analyze_expr_value_info(expr.items[i], capture_info_by_slot)
                end
                return { value_kind = "none", is_list = false, nullable = false }
            elseif expr.kind == "Choice" then
                local infos = {}
                for i = 1, #expr.alts do
                    infos[i] = analyze_expr_value_info(expr.alts[i], capture_info_by_slot)
                end
                return choice_info(infos)
            elseif expr.kind == "Optional" then
                local inner = analyze_expr_value_info(expr.inner, capture_info_by_slot)
                local out = clone_info(inner)
                out.nullable = true
                return out
            elseif expr.kind == "Many" then
                local inner = analyze_expr_value_info(expr.inner, capture_info_by_slot)
                return {
                    value_kind = inner.value_kind,
                    is_list = true,
                    nullable = true,
                }
            elseif expr.kind == "OneOrMore" then
                local inner = analyze_expr_value_info(expr.inner, capture_info_by_slot)
                return {
                    value_kind = inner.value_kind,
                    is_list = true,
                    nullable = false,
                }
            elseif expr.kind == "Capture" then
                local inner = analyze_expr_value_info(expr.inner, capture_info_by_slot)
                capture_info_by_slot[N(expr.header.slot_id)] = clone_info(inner)
                return inner
            elseif expr.kind == "Build" then
                local build_capture_info_by_slot = {}
                analyze_expr_value_info(expr.inner, build_capture_info_by_slot)
                if expr.result.kind == "ReturnEmpty" then
                    return { value_kind = "none", is_list = false, nullable = true }
                elseif expr.result.kind == "ReturnCtor" then
                    return { value_kind = "node", is_list = false, nullable = false }
                elseif expr.result.kind == "ReturnCapture" then
                    local info = build_capture_info_by_slot[N(expr.result.header.slot_id)]
                    if info == nil then
                        error("FrontendChecked.Spec:lower(): missing capture info for Build", 2)
                    end
                    return clone_info(info)
                end
            end
            error("FrontendChecked.Spec:lower(): unknown CheckedExpr kind '" .. tostring(expr.kind) .. "'", 2)
        end

        local function infer_rule_result_info(rule)
            local capture_info_by_slot = {}
            analyze_expr_value_info(rule.expr, capture_info_by_slot)
            if rule.result.kind == "ReturnEmpty" then
                return { value_kind = "none", is_list = false, nullable = true }
            elseif rule.result.kind == "ReturnCtor" then
                return { value_kind = "node", is_list = false, nullable = false }
            elseif rule.result.kind == "ReturnCapture" then
                local info = capture_info_by_slot[N(rule.result.header.slot_id)]
                if info == nil then
                    error("FrontendChecked.Spec:lower(): missing capture info for rule '" .. S(rule.header.name) .. "'", 2)
                end
                return clone_info(info)
            end
            error("FrontendChecked.Spec:lower(): unknown CheckedResult kind '" .. tostring(rule.result.kind) .. "'", 2)
        end

        local changed_result_info = true
        local passes = 0
        while changed_result_info and passes < 32 do
            changed_result_info = false
            passes = passes + 1
            for i = 1, #spec.parser.rules do
                local rule = spec.parser.rules[i]
                local next_info = infer_rule_result_info(rule)
                local rule_id = N(rule.header.rule_id)
                if not same_info(result_info_by_rule[rule_id], next_info) then
                    result_info_by_rule[rule_id] = next_info
                    changed_result_info = true
                end
            end
        end

        local function expr_value_info(expr)
            return analyze_expr_value_info(expr, {})
        end

        local function expr_props(expr)
            if expr.kind == "TokenRef" then
                return { token_ids = { N(expr.header.token_id) }, nullable = false }
            elseif expr.kind == "RuleRef" then
                local rule = rule_by_id[N(expr.header.rule_id)]
                return { token_ids = rule.first_set.token_ids, nullable = rule.nullable and true or false }
            elseif expr.kind == "Seq" then
                local ids, nullable = {}, true
                for i = 1, #expr.items do
                    local p = expr_props(expr.items[i])
                    for j = 1, #p.token_ids do ids[#ids + 1] = N(p.token_ids[j]) end
                    if not p.nullable then
                        nullable = false
                        break
                    end
                end
                return { token_ids = ids, nullable = nullable }
            elseif expr.kind == "Choice" then
                local ids, nullable = {}, false
                for i = 1, #expr.alts do
                    local p = expr_props(expr.alts[i])
                    for j = 1, #p.token_ids do ids[#ids + 1] = N(p.token_ids[j]) end
                    nullable = nullable or p.nullable
                end
                return { token_ids = ids, nullable = nullable }
            elseif expr.kind == "Optional" then
                local p = expr_props(expr.inner)
                return { token_ids = p.token_ids, nullable = true }
            elseif expr.kind == "Many" then
                local p = expr_props(expr.inner)
                return { token_ids = p.token_ids, nullable = true }
            elseif expr.kind == "OneOrMore" then
                return expr_props(expr.inner)
            elseif expr.kind == "Capture" then
                return expr_props(expr.inner)
            elseif expr.kind == "Build" then
                return expr_props(expr.inner)
            end
            error("FrontendChecked.Spec:lower(): unknown CheckedExpr kind '" .. tostring(expr.kind) .. "'", 2)
        end

        local result_ctor_by_fqname = {}
        local result_ctors = {}
        local function result_ctor_id_for(ctor)
            local fqname = S(ctor.ctor_fqname)
            local existing = result_ctor_by_fqname[fqname]
            if existing ~= nil then return existing end
            local ctor_id = #result_ctors + 1
            result_ctors[ctor_id] = LT.ResultCtor(ctor_id, ctor)
            result_ctor_by_fqname[fqname] = ctor_id
            return ctor_id
        end

        local function lower_arg_source(source)
            if source.kind == "CaptureSource" then return LT.ReadSlot(N(source.header.slot_id)) end
            if source.kind == "PresentSource" then return LT.ReadPresent(N(source.header.slot_id)) end
            if source.kind == "JoinedListSource" then return LT.ReadJoined(N(source.header.slot_id), S(source.separator)) end
            if source.kind == "ConstBoolSource" then return LT.ReadConstBool(B(source.value)) end
            error("FrontendChecked.Spec:lower(): unknown ResultSource kind '" .. tostring(source.kind) .. "'", 2)
        end

        local function lower_result(result)
            if result.kind == "ReturnEmpty" then return LT.ReturnEmpty end
            if result.kind == "ReturnCapture" then return LT.ReturnSlot(N(result.header.slot_id)) end
            if result.kind == "ReturnCtor" then
                local args = {}
                for i = 1, #result.fields do
                    args[i] = lower_arg_source(result.fields[i].source)
                end
                return LT.ReturnCtor(result_ctor_id_for(result.ctor), args)
            end
            error("FrontendChecked.Spec:lower(): unknown CheckedResult kind '" .. tostring(result.kind) .. "'", 2)
        end

        local rules_out = {}
        local function fresh_rule_header(prefix)
            max_rule_id = max_rule_id + 1
            return CT.RuleHeader(prefix .. tostring(max_rule_id), max_rule_id)
        end

        local lower_expr_steps
        local emit_value_rule
        local emit_rule_for_expr

        local function lower_value_steps(expr, slot)
            if expr.kind == "TokenRef" then
                return { LT.ExpectToken(expr.header, slot) }
            elseif expr.kind == "RuleRef" then
                return { LT.CallRule(expr.header, slot) }
            elseif expr.kind == "Seq" then
                local meaningful_index = nil
                local count = 0
                for i = 1, #expr.items do
                    local info = expr_value_info(expr.items[i])
                    if info.value_kind ~= "none" or info.is_list then
                        count = count + 1
                        meaningful_index = i
                    end
                end
                if count > 1 then
                    error("FrontendChecked.Spec:lower(): captured Seq with multiple meaningful children is not supported yet", 2)
                end
                local steps = {}
                for i = 1, #expr.items do
                    local child = (i == meaningful_index)
                        and lower_value_steps(expr.items[i], slot)
                        or lower_expr_steps(expr.items[i])
                    for j = 1, #child do steps[#steps + 1] = child[j] end
                end
                return steps
            elseif expr.kind == "Choice" then
                local helper = fresh_rule_header("capture_choice_")
                local helper_rule = emit_value_rule(helper, expr)
                rules_out[#rules_out + 1] = helper_rule
                return { LT.CallRule(helper, slot) }
            elseif expr.kind == "Optional" then
                local p = expr_props(expr.inner)
                return { LT.OptionalGroup(intern_first_set_token_ids(p.token_ids), lower_value_steps(expr.inner, slot)) }
            elseif expr.kind == "Many" then
                local p = expr_props(expr.inner)
                return { LT.RepeatGroup(intern_first_set_token_ids(p.token_ids), lower_value_steps(expr.inner, slot)) }
            elseif expr.kind == "OneOrMore" then
                local p = expr_props(expr.inner)
                local steps = lower_value_steps(expr.inner, slot)
                steps[#steps + 1] = LT.RepeatGroup(intern_first_set_token_ids(p.token_ids), lower_value_steps(expr.inner, slot))
                return steps
            elseif expr.kind == "Capture" then
                return lower_value_steps(expr.inner, slot)
            elseif expr.kind == "Build" then
                local helper = fresh_rule_header("build_")
                local helper_rule = emit_rule_for_expr(helper, expr.inner, lower_result(expr.result))
                rules_out[#rules_out + 1] = helper_rule
                return { LT.CallRule(helper, slot) }
            end
            error("FrontendChecked.Spec:lower(): unsupported value expr '" .. tostring(expr.kind) .. "'", 2)
        end

        emit_value_rule = function(header, expr)
            local slot = 1
            local result = LT.ReturnSlot(slot)
            if expr.kind == "TokenRef" then
                return LT.RulePlan(
                    header,
                    LT.TokenRuleKind,
                    { LT.ExpectToken(expr.header, slot) },
                    {},
                    result
                )
            elseif expr.kind == "Choice" then
                local arms = {}
                for i = 1, #expr.alts do
                    local alt = expr.alts[i]
                    local p = expr_props(alt)
                    arms[i] = LT.ChoiceArm(
                        intern_first_set_token_ids(p.token_ids),
                        lower_value_steps(alt, slot)
                    )
                end
                return LT.RulePlan(header, LT.ChoiceRuleKind, {}, arms, result)
            end
            return LT.RulePlan(header, LT.SeqRuleKind, lower_value_steps(expr, slot), {}, result)
        end

        local function lower_capture_expr(header, inner)
            local slot = N(header.slot_id)
            if inner.kind == "TokenRef" then
                return { LT.ExpectToken(inner.header, slot) }
            elseif inner.kind == "RuleRef" then
                return { LT.CallRule(inner.header, slot) }
            elseif inner.kind == "Optional" then
                local p = expr_props(inner.inner)
                return { LT.OptionalGroup(intern_first_set_token_ids(p.token_ids), lower_capture_expr(header, inner.inner)) }
            elseif inner.kind == "Many" then
                local p = expr_props(inner.inner)
                return { LT.RepeatGroup(intern_first_set_token_ids(p.token_ids), lower_capture_expr(header, inner.inner)) }
            elseif inner.kind == "OneOrMore" then
                local p = expr_props(inner.inner)
                local once = lower_capture_expr(header, inner.inner)
                local many = LT.RepeatGroup(intern_first_set_token_ids(p.token_ids), lower_capture_expr(header, inner.inner))
                local steps = {}
                for i = 1, #once do steps[#steps + 1] = once[i] end
                steps[#steps + 1] = many
                return steps
            elseif inner.kind == "Seq" or inner.kind == "Choice" or inner.kind == "Build" then
                local helper = fresh_rule_header("capture_")
                if inner.kind == "Build" then
                    local helper_rule = emit_rule_for_expr(helper, inner.inner, lower_result(inner.result))
                    rules_out[#rules_out + 1] = helper_rule
                else
                    local helper_rule = emit_value_rule(helper, inner)
                    rules_out[#rules_out + 1] = helper_rule
                end
                return { LT.CallRule(helper, slot) }
            end
            error("FrontendChecked.Spec:lower(): unsupported captured expr '" .. tostring(inner.kind) .. "'", 2)
        end

        emit_rule_for_expr = function(header, expr, result)
            if expr.kind == "Choice" then
                local arms = {}
                for i = 1, #expr.alts do
                    local alt = expr.alts[i]
                    local p = expr_props(alt)
                    arms[i] = LT.ChoiceArm(
                        intern_first_set_token_ids(p.token_ids),
                        lower_expr_steps(alt)
                    )
                end
                return LT.RulePlan(header, LT.ChoiceRuleKind, {}, arms, result)
            end
            return LT.RulePlan(header, LT.SeqRuleKind, lower_expr_steps(expr), {}, result)
        end

        lower_expr_steps = function(expr)
            if expr.kind == "TokenRef" then
                return { LT.ExpectToken(expr.header, 0) }
            elseif expr.kind == "RuleRef" then
                return { LT.CallRule(expr.header, 0) }
            elseif expr.kind == "Seq" then
                local steps = {}
                for i = 1, #expr.items do
                    local child = lower_expr_steps(expr.items[i])
                    for j = 1, #child do steps[#steps + 1] = child[j] end
                end
                return steps
            elseif expr.kind == "Optional" then
                local p = expr_props(expr.inner)
                return { LT.OptionalGroup(intern_first_set_token_ids(p.token_ids), lower_expr_steps(expr.inner)) }
            elseif expr.kind == "Many" then
                local p = expr_props(expr.inner)
                return { LT.RepeatGroup(intern_first_set_token_ids(p.token_ids), lower_expr_steps(expr.inner)) }
            elseif expr.kind == "OneOrMore" then
                local p = expr_props(expr.inner)
                local steps = lower_expr_steps(expr.inner)
                steps[#steps + 1] = LT.RepeatGroup(intern_first_set_token_ids(p.token_ids), lower_expr_steps(expr.inner))
                return steps
            elseif expr.kind == "Capture" then
                return lower_capture_expr(expr.header, expr.inner)
            elseif expr.kind == "Build" then
                local helper = fresh_rule_header("build_")
                local helper_rule = emit_rule_for_expr(helper, expr.inner, lower_result(expr.result))
                rules_out[#rules_out + 1] = helper_rule
                return { LT.CallRule(helper, 0) }
            elseif expr.kind == "Choice" then
                local helper = fresh_rule_header("choice_")
                local helper_rule = emit_rule_for_expr(helper, expr, LT.ReturnEmpty)
                rules_out[#rules_out + 1] = helper_rule
                return { LT.CallRule(helper, 0) }
            end
            error("FrontendChecked.Spec:lower(): unsupported expr '" .. tostring(expr.kind) .. "'", 2)
        end

        for i = 1, #spec.parser.rules do
            local rule = spec.parser.rules[i]
            local main_rule = emit_rule_for_expr(rule.header, rule.expr, lower_result(rule.result))
            rules_out[#rules_out + 1] = main_rule
        end

        sort(rules_out, function(a, b) return N(a.header.rule_id) < N(b.header.rule_id) end)

        local lowered_skips = {}
        for i = 1, #spec.lexer.skips do
            local skip = spec.lexer.skips[i]
            if skip.kind == "WhitespaceSkip" then
                lowered_skips[i] = LT.WhitespaceSkip
            elseif skip.kind == "LineCommentSkip" then
                lowered_skips[i] = LT.LineCommentSkip(S(skip.opener))
            else
                error("FrontendChecked.Spec:lower(): unknown SkipRule kind '" .. tostring(skip.kind) .. "'", 2)
            end
        end

        return LT.Spec(
            spec.target,
            LT.TokenizeMachine(
                eof_header,
                lowered_skips,
                fixed_dispatches,
                ident_dispatches,
                quoted_string_dispatches,
                number_dispatches
            ),
            LT.ParseMachine(
                spec.parser.entry_rule,
                result_ctors,
                first_sets,
                rules_out
            )
        )
    end)

    function T.FrontendChecked.Spec:lower()
        return lower_impl(self)
    end
end
