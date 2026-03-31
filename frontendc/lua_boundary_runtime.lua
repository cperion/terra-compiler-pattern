local bit = require("bit")

local band = bit.band
local lshift = bit.lshift
local byte = string.byte
local sub = string.sub
local sort = table.sort

local M = {}

local function N(v)
    return tonumber(v)
end

local function B(v)
    return v == true or ((tonumber(v) or 0) ~= 0)
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

local function build_first_set_checkers(first_sets)
    local by_id = {}
    for i = 1, #first_sets do
        local row = first_sets[i]
        local words = row.bitset_words
        by_id[N(row.set_id)] = function(token_id)
            local wi = math.floor(token_id / 32) + 1
            local word = N(words[wi] or 0) or 0
            return band(word, lshift(1, token_id % 32)) ~= 0
        end
    end
    return by_id
end

local function build_skip_plans(skips)
    local has_whitespace = false
    local line_comments = {}
    for i = 1, #skips do
        local skip = skips[i]
        if skip.kind == "WhitespaceSkip" then
            has_whitespace = true
        elseif skip.kind == "LineCommentSkip" then
            line_comments[#line_comments + 1] = skip.opener
        end
    end
    sort(line_comments, function(a, b) return #a > #b end)
    return has_whitespace, line_comments
end

local function build_fixed_dispatch_table(fixed_dispatches)
    local by_first = {}
    for i = 1, #fixed_dispatches do
        local dispatch = fixed_dispatches[i]
        local first_byte = N(dispatch.first_byte)
        local cases = by_first[first_byte] or {}
        by_first[first_byte] = cases
        for j = 1, #dispatch.cases do
            local case = dispatch.cases[j]
            cases[#cases + 1] = {
                text = case.text,
                len = #case.text,
                token_id = N(case.token_id),
                requires_word_boundary = case.requires_word_boundary and true or false,
            }
        end
        sort(cases, function(a, b) return a.len > b.len end)
    end
    return by_first
end

local function build_ident_dispatches(ident_dispatches)
    local out = {}
    local combined_continue = {}
    for i = 1, #ident_dispatches do
        local dispatch = ident_dispatches[i]
        local start_lookup = build_byte_lookup(dispatch.start_bitset_words)
        local continue_lookup = build_byte_lookup(dispatch.continue_bitset_words)
        out[#out + 1] = {
            token_id = N(dispatch.token_id),
            start_lookup = start_lookup,
            continue_lookup = continue_lookup,
            captures_text = dispatch.captures_text and true or false,
        }
        for c = 0, 255 do
            if continue_lookup[c] then combined_continue[c] = true end
        end
    end
    return out, combined_continue
end

local function build_quoted_string_dispatches(quoted_string_dispatches)
    local out = {}
    for i = 1, #quoted_string_dispatches do
        local dispatch = quoted_string_dispatches[i]
        out[#out + 1] = {
            token_id = N(dispatch.token_id),
            quote_byte = N(dispatch.quote_byte),
            backslash_escapes = dispatch.backslash_escapes and true or false,
        }
    end
    return out
end

local function build_number_dispatches(number_dispatches)
    local out = {}
    for i = 1, #number_dispatches do
        out[#out + 1] = {
            token_id = N(number_dispatches[i].token_id),
        }
    end
    return out
end

local function scan_quoted_string(text, len, start, quote_byte, backslash_escapes)
    local i = start + 1
    local pieces = nil
    local chunk_start = i
    while i <= len do
        local c = byte(text, i)
        if c == quote_byte then
            if pieces == nil then
                return sub(text, chunk_start, i - 1), i
            end
            pieces[#pieces + 1] = sub(text, chunk_start, i - 1)
            return table.concat(pieces), i
        elseif c == 92 and backslash_escapes then
            pieces = pieces or {}
            pieces[#pieces + 1] = sub(text, chunk_start, i - 1)
            i = i + 1
            if i > len then error("generated tokenize machine unterminated escape sequence", 2) end
            local esc = byte(text, i)
            if esc == 34 then pieces[#pieces + 1] = '"'
            elseif esc == 92 then pieces[#pieces + 1] = '\\'
            elseif esc == 47 then pieces[#pieces + 1] = '/'
            elseif esc == 98 then pieces[#pieces + 1] = '\b'
            elseif esc == 102 then pieces[#pieces + 1] = '\f'
            elseif esc == 110 then pieces[#pieces + 1] = '\n'
            elseif esc == 114 then pieces[#pieces + 1] = '\r'
            elseif esc == 116 then pieces[#pieces + 1] = '\t'
            else
                error("generated tokenize machine unsupported string escape", 2)
            end
            i = i + 1
            chunk_start = i
            goto continue
        elseif c < 32 then
            error("generated tokenize machine control char in string", 2)
        end
        i = i + 1
        ::continue::
    end
    error("generated tokenize machine unterminated string", 2)
end

local function scan_number(text, len, start)
    local i = start
    local c = byte(text, i)
    if c == 45 then
        i = i + 1
        if i > len then error("generated tokenize machine invalid number", 2) end
        c = byte(text, i)
    end
    if c == 48 then
        i = i + 1
    elseif c and c >= 49 and c <= 57 then
        i = i + 1
        while i <= len do
            c = byte(text, i)
            if c < 48 or c > 57 then break end
            i = i + 1
        end
    else
        error("generated tokenize machine invalid number", 2)
    end
    if i <= len and byte(text, i) == 46 then
        i = i + 1
        if i > len then error("generated tokenize machine invalid number", 2) end
        c = byte(text, i)
        if c < 48 or c > 57 then error("generated tokenize machine invalid number", 2) end
        repeat
            i = i + 1
            c = i <= len and byte(text, i) or nil
        until not c or c < 48 or c > 57
    end
    if i <= len then
        c = byte(text, i)
        if c == 69 or c == 101 then
            i = i + 1
            if i <= len then
                c = byte(text, i)
                if c == 43 or c == 45 then i = i + 1 end
            end
            if i > len then error("generated tokenize machine invalid number", 2) end
            c = byte(text, i)
            if c < 48 or c > 57 then error("generated tokenize machine invalid number", 2) end
            repeat
                i = i + 1
                c = i <= len and byte(text, i) or nil
            until not c or c < 48 or c > 57
        end
    end
    return sub(text, start, i - 1), i - 1
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

local function compile_result_fn(plan, ctor_by_id)
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
        local ctor = ctor_by_id[N(plan.ctor_id)]
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
                local sep = arg.separator
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
                local value = B(arg.value)
                arg_readers[i] = function() return value end
            else
                error("generated parse machine unknown ArgSource kind '" .. tostring(arg.kind) .. "'", 2)
            end
        end
        return function(slots)
            local args = {}
            for i = 1, #arg_readers do args[i] = arg_readers[i](slots) end
            return ctor(unpack(args))
        end
    end
    error("generated parse machine unknown ResultPlan kind '" .. tostring(plan.kind) .. "'", 2)
end

function M.build_tokenize(U, spec)
    local fixed_by_first = build_fixed_dispatch_table(spec.fixed_dispatches)
    local ident_dispatches, ident_continue_lookup = build_ident_dispatches(spec.ident_dispatches)
    local quoted_string_dispatches = build_quoted_string_dispatches(spec.quoted_string_dispatches or {})
    local number_dispatches = build_number_dispatches(spec.number_dispatches or {})
    local has_whitespace, line_comments = build_skip_plans(spec.skips)

    local iter_machine = U.machine_iter(
        function(param, _, cursor)
            local text = cursor.text
            local len = cursor.len

            local function skip_ignored()
                while true do
                    local moved = false

                    if param.has_whitespace then
                        while cursor.pos <= len do
                            local c = byte(text, cursor.pos)
                            if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then break end
                            cursor.pos = cursor.pos + 1
                            moved = true
                        end
                    end

                    local comment_hit = false
                    for i = 1, #param.line_comments do
                        local opener = param.line_comments[i]
                        local stop = cursor.pos + #opener - 1
                        if stop <= len and sub(text, cursor.pos, stop) == opener then
                            cursor.pos = stop + 1
                            while cursor.pos <= len and byte(text, cursor.pos) ~= 10 do
                                cursor.pos = cursor.pos + 1
                            end
                            if cursor.pos <= len then cursor.pos = cursor.pos + 1 end
                            moved = true
                            comment_hit = true
                            break
                        end
                    end

                    if not moved and not comment_hit then return end
                end
            end

            skip_ignored()

            if cursor.pos > len then
                if cursor.emitted_eof then return nil end
                cursor.emitted_eof = true
                local span = param.span_ctor(len + 1, len + 1)
                return cursor, param.token_cell_ctor(param.eof_token_id, nil, span)
            end

            local start = cursor.pos
            local c = byte(text, start)
            local cases = param.fixed_by_first[c]

            if cases then
                for i = 1, #cases do
                    local case = cases[i]
                    local stop = start + case.len - 1
                    if stop <= len and sub(text, start, stop) == case.text then
                        local next_pos = stop + 1
                        if (not case.requires_word_boundary)
                            or next_pos > len
                            or not param.ident_continue_lookup[byte(text, next_pos)] then
                            cursor.pos = next_pos
                            return cursor, param.token_cell_ctor(
                                case.token_id,
                                nil,
                                param.span_ctor(start, stop)
                            )
                        end
                    end
                end
            end

            for i = 1, #param.quoted_string_dispatches do
                local dispatch = param.quoted_string_dispatches[i]
                if c == dispatch.quote_byte then
                    local value, stop = scan_quoted_string(text, len, start, dispatch.quote_byte, dispatch.backslash_escapes)
                    cursor.pos = stop + 1
                    return cursor, param.token_cell_ctor(
                        dispatch.token_id,
                        value,
                        param.span_ctor(start, stop)
                    )
                end
            end

            for i = 1, #param.ident_dispatches do
                local dispatch = param.ident_dispatches[i]
                if dispatch.start_lookup[c] then
                    local stop = start
                    while stop + 1 <= len and dispatch.continue_lookup[byte(text, stop + 1)] do
                        stop = stop + 1
                    end
                    cursor.pos = stop + 1
                    return cursor, param.token_cell_ctor(
                        dispatch.token_id,
                        dispatch.captures_text and sub(text, start, stop) or nil,
                        param.span_ctor(start, stop)
                    )
                end
            end

            for i = 1, #param.number_dispatches do
                if c == 45 or (c >= 48 and c <= 57) then
                    local value, stop = scan_number(text, len, start)
                    cursor.pos = stop + 1
                    return cursor, param.token_cell_ctor(
                        param.number_dispatches[i].token_id,
                        value,
                        param.span_ctor(start, stop)
                    )
                end
            end

            error("generated tokenize machine invalid token at byte " .. tostring(start), 2)
        end,
        function(_, _, input)
            local text = tostring(input.text)
            return {
                text = text,
                len = #text,
                pos = 1,
                emitted_eof = false,
            }
        end,
        {
            output_spec_ctor = spec.output_spec_ctor,
            token_cell_ctor = spec.token_cell_ctor,
            span_ctor = spec.span_ctor,
            eof_token_id = spec.eof_token_id,
            fixed_by_first = fixed_by_first,
            ident_dispatches = ident_dispatches,
            ident_continue_lookup = ident_continue_lookup,
            has_whitespace = has_whitespace,
            line_comments = line_comments,
            quoted_string_dispatches = quoted_string_dispatches,
            number_dispatches = number_dispatches,
        },
        nil,
        "frontend_tokenize"
    )

    return U.transition(function(input)
        local items = U.map(U.machine_iterate(iter_machine, nil, input), function(cell)
            return cell
        end)
        return spec.output_spec_ctor(items)
    end)
end

function M.build_parse(U, spec)
    local first_set_by_id = build_first_set_checkers(spec.first_sets)
    local rule_fn_by_id = {}
    local ctor_by_id = {}
    for i = 1, #spec.result_ctors do
        local row = spec.result_ctors[i]
        ctor_by_id[N(row.ctor_id)] = row.ctor
    end

    local function in_first_set(set_id, tok)
        local checker = first_set_by_id[N(set_id)]
        if not checker or tok == nil then return false end
        return checker(N(tok.token_id))
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
                if tok == nil or N(tok.token_id) ~= N(step.header.token_id) then
                    error("generated parse machine expected token '" .. tostring(step.header.name) .. "'", 2)
                end
                capture_put(slots, step.capture_slot, token_value(tok))
                pos = pos + 1
            elseif step.kind == "CallRule" then
                local fn = rule_fn_by_id[N(step.header.rule_id)]
                if not fn then
                    error("generated parse machine missing rule '" .. tostring(N(step.header.rule_id)) .. "'", 2)
                end
                local value
                value, pos = fn(tokens, pos)
                capture_put(slots, step.capture_slot, value)
            elseif step.kind == "OptionalGroup" then
                if in_first_set(step.set_id, tokens[pos]) then
                    pos = execute_steps(step.body, tokens, pos, slots)
                end
            elseif step.kind == "RepeatGroup" then
                while in_first_set(step.set_id, tokens[pos]) do
                    pos = execute_steps(step.body, tokens, pos, slots)
                end
            else
                error("generated parse machine unknown Step kind '" .. tostring(step.kind) .. "'", 2)
            end
        end
        return pos
    end

    for i = 1, #spec.rules do
        local plan = spec.rules[i]
        local result_fn = compile_result_fn(plan.result, ctor_by_id)
        local rule_id = N(plan.header.rule_id)
        local rule_kind = plan.kind.kind or plan.kind

        if rule_kind == "TokenRuleKind" then
            local token_step = plan.body[1]
            if token_step == nil or token_step.kind ~= "ExpectToken" then
                error("generated parse machine token rule must lower to one ExpectToken step", 2)
            end
            local expected_id = N(token_step.header.token_id)
            local capture_slot = N(token_step.capture_slot)
            rule_fn_by_id[rule_id] = function(tokens, pos)
                local tok = tokens[pos]
                if tok == nil or N(tok.token_id) ~= expected_id then
                    error("generated parse machine expected token '" .. tostring(token_step.header.name) .. "'", 2)
                end
                local slots = {}
                capture_put(slots, capture_slot, token_value(tok))
                return result_fn(slots), pos + 1
            end
        elseif rule_kind == "SeqRuleKind" then
            local run_steps = compile_steps(plan.body)
            rule_fn_by_id[rule_id] = function(tokens, pos)
                local slots = {}
                local next_pos = run_steps(tokens, pos, slots)
                return result_fn(slots), next_pos
            end
        elseif rule_kind == "ChoiceRuleKind" then
            local arm_steps = {}
            for j = 1, #plan.choice_arms do
                arm_steps[j] = compile_steps(plan.choice_arms[j].body)
            end
            rule_fn_by_id[rule_id] = function(tokens, pos)
                local tok = tokens[pos]
                if tok == nil then
                    error("generated parse machine unexpected eof in choice rule", 2)
                end
                for j = 1, #plan.choice_arms do
                    local arm = plan.choice_arms[j]
                    if in_first_set(arm.set_id, tok) then
                        local slots = {}
                        local next_pos = arm_steps[j](tokens, pos, slots)
                        return result_fn(slots), next_pos
                    end
                end
                error("generated parse machine no choice arm matched token id '" .. tostring(tok.token_id) .. "'", 2)
            end
        else
            error("generated parse machine unknown RulePlan kind '" .. tostring(rule_kind) .. "'", 2)
        end
    end

    local step_machine = U.machine_step(function(param, _, input)
        local tokens = input.items or input.tokens
        local entry = rule_fn_by_id[param.entry_rule_id]
        if not entry then
            error("generated parse machine missing entry rule '" .. tostring(param.entry_rule_id) .. "'", 2)
        end
        local value, pos = entry(tokens, 1)
        local tail = tokens[pos]
        if tail == nil or N(tail.token_id) ~= param.eof_token_id then
            error("generated parse machine expected eof", 2)
        end
        return value
    end, {
        entry_rule_id = spec.entry_rule_id,
        eof_token_id = spec.eof_token_id,
    }, nil, "frontend_parse")

    return U.transition(function(input)
        return spec.output_spec_ctor(U.machine_run(step_machine, nil, input))
    end)
end

return M
