local ffi = require("ffi")
local bit = require("bit")

local band = bit.band
local lshift = bit.lshift
local byte = string.byte
local sub = string.sub
local sort = table.sort

return function(T, U, P)
    local function S(v)
        if type(v) == "cdata" then return ffi.string(v) end
        return tostring(v)
    end

    local function N(v)
        return tonumber(v)
    end

    local function resolve_path(ctx, path)
        local node = ctx
        local parts = path.parts or path
        local rendered = {}
        for i = 1, #parts do
            local part = S(parts[i])
            rendered[i] = part
            node = node and node[part] or nil
            if node == nil then
                error("FrontendMachine.Spec:install_generated(): missing target '" .. table.concat(rendered, ".") .. "'", 3)
            end
        end
        return node, table.concat(rendered, ".")
    end

    local function build_byte_lookup(words)
        local lookup = {}
        for c = 0, 255 do
            local word_index = math.floor(c / 32) + 1
            local bit_index = c % 32
            local word = N(words[word_index] or 0) or 0
            lookup[c] = band(word, lshift(1, bit_index)) ~= 0
        end
        return lookup
    end

    local function build_token_ctor_table(token_ctors, ctx)
        local by_id = {}
        for i = 1, #token_ctors do
            local ref = token_ctors[i]
            by_id[N(ref.ctor_id)] = resolve_path(ctx, ref.ctor_path)
        end
        return by_id
    end

    local function build_fixed_dispatch_table(fixed_dispatches, token_ctor_by_id)
        local by_first = {}
        for i = 1, #fixed_dispatches do
            local dispatch = fixed_dispatches[i]
            local first_byte = N(dispatch.first_byte)
            local cases = by_first[first_byte] or {}
            by_first[first_byte] = cases
            for j = 1, #dispatch.cases do
                local case = dispatch.cases[j]
                cases[#cases + 1] = {
                    text = S(case.text),
                    len = #S(case.text),
                    ctor = token_ctor_by_id[N(case.header.token_id)],
                    requires_word_boundary = case.requires_word_boundary and true or false,
                }
            end
            sort(cases, function(a, b) return a.len > b.len end)
        end
        return by_first
    end

    local function build_ident_dispatches(ident_dispatches, token_ctor_by_id)
        local out = {}
        local combined_continue = {}
        for i = 1, #ident_dispatches do
            local dispatch = ident_dispatches[i]
            local start_lookup = build_byte_lookup(dispatch.start_bitset_words)
            local continue_lookup = build_byte_lookup(dispatch.continue_bitset_words)
            out[#out + 1] = {
                ctor = token_ctor_by_id[N(dispatch.header.token_id)],
                start_lookup = start_lookup,
                continue_lookup = continue_lookup,
            }
            for c = 0, 255 do
                if continue_lookup[c] then combined_continue[c] = true end
            end
        end
        return out, combined_continue
    end

    local function build_skip_plans(skips)
        local has_whitespace = false
        local line_comments = {}
        for i = 1, #skips do
            local skip = skips[i]
            if skip.kind == "WhitespaceSkip" then
                has_whitespace = true
            elseif skip.kind == "LineCommentSkip" then
                line_comments[#line_comments + 1] = S(skip.opener)
            end
        end
        sort(line_comments, function(a, b) return #a > #b end)
        return has_whitespace, line_comments
    end

    local function build_token_id_by_kind(spec)
        local by_kind = {}
        for i = 1, #spec.tokenize.fixed_dispatches do
            local dispatch = spec.tokenize.fixed_dispatches[i]
            for j = 1, #dispatch.cases do
                local case = dispatch.cases[j]
                by_kind[S(case.header.name)] = N(case.header.token_id)
            end
        end
        for i = 1, #spec.tokenize.ident_dispatches do
            local dispatch = spec.tokenize.ident_dispatches[i]
            by_kind[S(dispatch.header.name)] = N(dispatch.header.token_id)
        end
        by_kind.Eof = N(spec.tokenize.eof_ctor_id)
        return by_kind
    end

    local function build_first_set_tables(first_sets)
        local by_id = {}
        for i = 1, #first_sets do
            local row = first_sets[i]
            by_id[N(row.set_id)] = build_byte_lookup(row.bitset_words)
        end
        return by_id
    end

    local function build_result_ctor_table(result_ctors, ctx)
        local by_id = {}
        for i = 1, #result_ctors do
            local ref = result_ctors[i]
            by_id[N(ref.ctor_id)] = resolve_path(ctx, ref.ctor_path)
        end
        return by_id
    end

    local function capture_put(slots, slot_id, value)
        slot_id = N(slot_id)
        if slot_id == nil or slot_id <= 0 then return end
        local existing = slots[slot_id]
        if existing == nil then
            slots[slot_id] = value
        elseif type(existing) == "table" and existing.__capture_list then
            existing[#existing + 1] = value
        else
            slots[slot_id] = { existing, value, __capture_list = true }
        end
    end

    local function token_value(tok)
        if tok.text ~= nil then return tok.text end
        return tok
    end

    local function compile_result_fn(plan, result_ctor_by_id)
        if plan.kind == "ReturnEmpty" then
            return function(_)
                return nil
            end
        end
        if plan.kind == "ReturnSlot" then
            local slot_id = N(plan.slot_id)
            return function(slots)
                return slots[slot_id]
            end
        end
        if plan.kind == "ReturnCtor" then
            local ctor = result_ctor_by_id[N(plan.ctor_id)]
            local arg_readers = {}
            for i = 1, #plan.args do
                local arg = plan.args[i]
                if arg.kind == "ReadSlot" then
                    local slot_id = N(arg.slot_id)
                    arg_readers[i] = function(slots) return slots[slot_id] end
                elseif arg.kind == "ReadPresent" then
                    local slot_id = N(arg.slot_id)
                    arg_readers[i] = function(slots) return slots[slot_id] ~= nil end
                elseif arg.kind == "ReadJoined" then
                    local slot_id = N(arg.slot_id)
                    local sep = S(arg.separator)
                    arg_readers[i] = function(slots)
                        local v = slots[slot_id]
                        if v == nil then return "" end
                        if type(v) == "table" and v.__capture_list then
                            local xs = {}
                            for j = 1, #v do xs[j] = tostring(v[j]) end
                            return table.concat(xs, sep)
                        end
                        return tostring(v)
                    end
                elseif arg.kind == "ReadConstBool" then
                    local value = arg.value and true or false
                    arg_readers[i] = function() return value end
                else
                    error("generated parse closure unknown ArgSource kind '" .. tostring(arg.kind) .. "'", 2)
                end
            end
            return function(slots)
                local args = {}
                for i = 1, #arg_readers do args[i] = arg_readers[i](slots) end
                return ctor(unpack(args))
            end
        end
        error("generated parse closure unknown ResultPlan kind '" .. tostring(plan.kind) .. "'", 2)
    end

    local function token_id_for(by_kind, tok)
        local id = by_kind[tok.kind]
        if id == nil then
            error("generated parse closure unknown token kind '" .. tostring(tok.kind) .. "'", 2)
        end
        return id
    end

    function T.FrontendMachine.Spec:emit_lua()
        error("scaffold: implement boundary", 2)
    end

    local install_generated_impl = U.terminal(function(spec, ctx)
        local tokenize_header = spec.tokenize.header
        local parse_header = spec.parse.header

        local tokenize_class, tokenize_receiver = resolve_path(ctx, tokenize_header.receiver_path)
        local parse_class, parse_receiver = resolve_path(ctx, parse_header.receiver_path)

        local tokenize_verb = S(tokenize_header.verb)
        local parse_verb = S(parse_header.verb)

        local tokenize_output_ctor = resolve_path(ctx, spec.tokenize.output_spec_ctor_path)
        local span_ctor = resolve_path(ctx, spec.tokenize.span_ctor_path)
        local token_ctor_by_id = build_token_ctor_table(spec.tokenize.token_ctors, ctx)
        local eof_ctor = token_ctor_by_id[N(spec.tokenize.eof_ctor_id)]
        local fixed_by_first = build_fixed_dispatch_table(spec.tokenize.fixed_dispatches, token_ctor_by_id)
        local ident_dispatches, ident_continue_lookup = build_ident_dispatches(spec.tokenize.ident_dispatches, token_ctor_by_id)
        local has_whitespace, line_comments = build_skip_plans(spec.tokenize.skips)

        tokenize_class[tokenize_verb] = U.transition(
            tokenize_receiver .. ":" .. tokenize_verb,
            function(input)
                local text = S(input.text)
                local len = #text
                local pos = 1
                local tokens = {}

                local function skip_ignored()
                    while true do
                        local moved = false

                        if has_whitespace then
                            while pos <= len do
                                local c = byte(text, pos)
                                if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then break end
                                pos = pos + 1
                                moved = true
                            end
                        end

                        local comment_hit = false
                        for i = 1, #line_comments do
                            local opener = line_comments[i]
                            local stop = pos + #opener - 1
                            if stop <= len and sub(text, pos, stop) == opener then
                                pos = stop + 1
                                while pos <= len and byte(text, pos) ~= 10 do
                                    pos = pos + 1
                                end
                                if pos <= len then pos = pos + 1 end
                                moved = true
                                comment_hit = true
                                break
                            end
                        end

                        if not moved and not comment_hit then return end
                    end
                end

                skip_ignored()

                while pos <= len do
                    local start = pos
                    local c = byte(text, pos)
                    local matched = false
                    local cases = fixed_by_first[c]

                    if cases then
                        for i = 1, #cases do
                            local case = cases[i]
                            local stop = start + case.len - 1
                            if stop <= len and sub(text, start, stop) == case.text then
                                local next_pos = stop + 1
                                if (not case.requires_word_boundary)
                                    or next_pos > len
                                    or not ident_continue_lookup[byte(text, next_pos)] then
                                    tokens[#tokens + 1] = case.ctor(span_ctor(start, stop))
                                    pos = next_pos
                                    matched = true
                                    break
                                end
                            end
                        end
                    end

                    if not matched then
                        for i = 1, #ident_dispatches do
                            local dispatch = ident_dispatches[i]
                            if dispatch.start_lookup[c] then
                                local stop = pos
                                while stop + 1 <= len and dispatch.continue_lookup[byte(text, stop + 1)] do
                                    stop = stop + 1
                                end
                                tokens[#tokens + 1] = dispatch.ctor(sub(text, start, stop), span_ctor(start, stop))
                                pos = stop + 1
                                matched = true
                                break
                            end
                        end
                    end

                    if not matched then
                        error("generated tokenize closure invalid token at byte " .. tostring(start), 2)
                    end

                    skip_ignored()
                end

                tokens[#tokens + 1] = eof_ctor(span_ctor(len + 1, len + 1))
                return tokenize_output_ctor(tokens)
            end
        )

        local parse_output_ctor = resolve_path(ctx, spec.parse.output_spec_ctor_path)
        local result_ctor_by_id = build_result_ctor_table(spec.parse.result_ctors, ctx)
        local first_set_by_id = build_first_set_tables(spec.parse.first_sets)
        local token_id_by_kind = build_token_id_by_kind(spec)
        local rule_fn_by_id = {}

        local function in_first_set(set_id, tok)
            local lookup = first_set_by_id[N(set_id)]
            if not lookup then return false end
            return lookup[token_id_for(token_id_by_kind, tok)] == true
        end

        local execute_steps

        local function compile_steps(steps)
            return function(tokens, pos, slots)
                return execute_steps(steps, tokens, pos, slots)
            end
        end

        execute_steps = function(steps, tokens, pos, slots)
            for i = 1, #steps do
                local step = steps[i]
                if step.kind == "ExpectToken" then
                    local tok = tokens[pos]
                    if tok == nil or token_id_for(token_id_by_kind, tok) ~= N(step.header.token_id) then
                        error("generated parse closure expected token '" .. S(step.header.name) .. "'", 2)
                    end
                    capture_put(slots, step.capture_slot, token_value(tok))
                    pos = pos + 1
                elseif step.kind == "CallRule" then
                    local fn = rule_fn_by_id[N(step.rule_id)]
                    if not fn then
                        error("generated parse closure missing rule '" .. tostring(N(step.rule_id)) .. "'", 2)
                    end
                    local value
                    value, pos = fn(tokens, pos)
                    capture_put(slots, step.capture_slot, value)
                elseif step.kind == "OptionalGroup" then
                    local tok = tokens[pos]
                    if tok and in_first_set(step.set_id, tok) then
                        pos = execute_steps(step.steps, tokens, pos, slots)
                    end
                elseif step.kind == "RepeatGroup" then
                    local tok = tokens[pos]
                    while tok and in_first_set(step.set_id, tok) do
                        pos = execute_steps(step.steps, tokens, pos, slots)
                        tok = tokens[pos]
                    end
                else
                    error("generated parse closure unknown Step kind '" .. tostring(step.kind) .. "'", 2)
                end
            end
            return pos
        end

        for i = 1, #spec.parse.rules do
            local plan = spec.parse.rules[i]
            local result_fn = compile_result_fn(plan.result, result_ctor_by_id)
            if plan.kind == "TokenRule" then
                local expected_id = N(plan.header.token_id)
                local capture_slot = N(plan.capture_slot)
                rule_fn_by_id[N(plan.rule_id)] = function(tokens, pos)
                    local tok = tokens[pos]
                    if tok == nil or token_id_for(token_id_by_kind, tok) ~= expected_id then
                        error("generated parse closure expected token '" .. S(plan.header.name) .. "'", 2)
                    end
                    local slots = {}
                    capture_put(slots, capture_slot, token_value(tok))
                    return result_fn(slots), pos + 1
                end
            elseif plan.kind == "SeqRule" then
                local run_steps = compile_steps(plan.steps)
                rule_fn_by_id[N(plan.rule_id)] = function(tokens, pos)
                    local slots = {}
                    local next_pos = run_steps(tokens, pos, slots)
                    return result_fn(slots), next_pos
                end
            elseif plan.kind == "ChoiceRule" then
                local arm_steps = {}
                for j = 1, #plan.arms do
                    arm_steps[j] = compile_steps(plan.arms[j].steps)
                end
                rule_fn_by_id[N(plan.rule_id)] = function(tokens, pos)
                    local tok = tokens[pos]
                    if tok == nil then
                        error("generated parse closure unexpected eof in choice rule", 2)
                    end
                    for j = 1, #plan.arms do
                        local arm = plan.arms[j]
                        if in_first_set(arm.set_id, tok) then
                            local slots = {}
                            local next_pos = arm_steps[j](tokens, pos, slots)
                            return result_fn(slots), next_pos
                        end
                    end
                    error("generated parse closure no choice arm matched token '" .. tostring(tok.kind) .. "'", 2)
                end
            else
                error("generated parse closure unknown RuleClosurePlan kind '" .. tostring(plan.kind) .. "'", 2)
            end
        end

        parse_class[parse_verb] = U.transition(
            parse_receiver .. ":" .. parse_verb,
            function(input)
                local tokens = input.tokens
                local entry = rule_fn_by_id[N(spec.parse.entry_rule_id)]
                if not entry then
                    error("generated parse closure missing entry rule '" .. tostring(N(spec.parse.entry_rule_id)) .. "'", 2)
                end
                local value, pos = entry(tokens, 1)
                local tail = tokens[pos]
                if tail == nil or tail.kind ~= "Eof" then
                    error("generated parse closure expected eof", 2)
                end
                return parse_output_ctor(value)
            end
        )

        return ctx
    end)

    function T.FrontendMachine.Spec:install_generated(ctx)
        return install_generated_impl(self, ctx)
    end
end
