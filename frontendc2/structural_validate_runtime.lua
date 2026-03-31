local ffi = require("ffi")
local bit = require("bit")

local band = bit.band
local lshift = bit.lshift
local byte = string.byte

local M = {}

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

local function is_word_continue_byte(c)
    if c == nil then return false end
    return c == 95
        or (c >= 48 and c <= 57)
        or (c >= 65 and c <= 90)
        or (c >= 97 and c <= 122)
end

local function build_byte_lookup(words)
    local lookup = {}
    for c = 0, 255 do
        local wi = math.floor(c / 32) + 1
        lookup[c] = band(N(words[wi] or 0), lshift(1, c % 32)) ~= 0
    end
    return lookup
end

local function prefix_eq(text, pos, len, needle)
    local n = #needle
    if pos + n - 1 > len then return false end
    for i = 1, n do
        if byte(text, pos + i - 1) ~= byte(needle, i) then return false end
    end
    return true
end

local function input_text(input)
    if type(input) == "string" then return input end
    if type(input) == "table" then
        if type(input.text) == "string" then return input.text end
        if type(input.bytes) == "string" then return input.bytes end
    end
    error("structural validate runtime expected input string or { text = string }", 3)
end

function M.scan_number(text, len, start, format)
    local i = start
    local c = byte(text, i)
    if c == nil then return nil, "unexpected eof" end

    local allow_sign = B(format.allow_sign)
    local allow_fraction = B(format.allow_fraction)
    local allow_exponent = B(format.allow_exponent)
    local allow_leading_zero = B(format.allow_leading_zero)

    if c == 45 then
        if not allow_sign then return nil, "sign not allowed" end
        i = i + 1
        c = byte(text, i)
        if c == nil then return nil, "invalid number" end
    end

    if c == 48 then
        i = i + 1
        if not allow_leading_zero then
            local next_c = byte(text, i)
            if next_c and next_c >= 48 and next_c <= 57 then
                return nil, "leading zero not allowed"
            end
        end
    elseif c and c >= 49 and c <= 57 then
        i = i + 1
        while i <= len do
            c = byte(text, i)
            if c < 48 or c > 57 then break end
            i = i + 1
        end
    else
        return nil, "invalid number"
    end

    if i <= len and byte(text, i) == 46 then
        if not allow_fraction then return nil, "fraction not allowed" end
        i = i + 1
        c = byte(text, i)
        if c == nil or c < 48 or c > 57 then return nil, "invalid fraction" end
        repeat
            i = i + 1
            c = byte(text, i)
        until c == nil or c < 48 or c > 57
    end

    if i <= len then
        c = byte(text, i)
        if c == 69 or c == 101 then
            if not allow_exponent then return nil, "exponent not allowed" end
            i = i + 1
            c = byte(text, i)
            if c == 43 or c == 45 then
                i = i + 1
                c = byte(text, i)
            end
            if c == nil or c < 48 or c > 57 then return nil, "invalid exponent" end
            repeat
                i = i + 1
                c = byte(text, i)
            until c == nil or c < 48 or c > 57
        end
    end

    return i
end

function M.scan_quoted_string(text, len, start, format)
    local quote_char = S(format.quote_char)
    local quote = byte(quote_char, 1)
    if byte(text, start) ~= quote then return nil, "missing opening quote" end
    local i = start + 1
    while i <= len do
        local c = byte(text, i)
        if c == quote then
            return i + 1
        elseif c == 92 and B(format.backslash_escapes) then
            i = i + 1
            local esc = byte(text, i)
            if esc == nil then return nil, "unterminated escape" end
            if esc == 34 or esc == 92 or esc == 47 or esc == 98 or esc == 102 or esc == 110 or esc == 114 or esc == 116 then
                i = i + 1
            else
                return nil, "unsupported escape"
            end
        else
            if c < 32 and not B(format.multiline) then return nil, "control char in string" end
            i = i + 1
        end
    end
    return nil, "unterminated string"
end

function M.skip_trivia(skip_plans, text, len, start)
    local pos = start
    while true do
        local moved = false
        for i = 1, #skip_plans do
            local skip = skip_plans[i]
            if skip.kind == "WhitespaceSkip" then
                while pos <= len do
                    local c = byte(text, pos)
                    if c ~= 9 and c ~= 10 and c ~= 13 and c ~= 32 then break end
                    pos = pos + 1
                    moved = true
                end
            elseif skip.kind == "LineCommentSkip" then
                local opener = skip.opener
                if #opener > 0 and prefix_eq(text, pos, len, opener) then
                    pos = pos + #opener
                    while pos <= len do
                        local c = byte(text, pos)
                        pos = pos + 1
                        if c == 10 then break end
                    end
                    moved = true
                end
            elseif skip.kind == "BlockCommentSkip" then
                local opener = skip.opener
                local closer = skip.closer
                if #opener > 0 and prefix_eq(text, pos, len, opener) then
                    pos = pos + #opener
                    while pos <= len and not prefix_eq(text, pos, len, closer) do
                        pos = pos + 1
                    end
                    if pos > len then return nil, "unterminated block comment" end
                    pos = pos + #closer
                    moved = true
                end
            elseif skip.kind == "ByteSkip" then
                local lookup = skip.lookup
                while pos <= len and lookup[byte(text, pos)] do
                    pos = pos + 1
                    moved = true
                end
            else
                return nil, "unknown skip plan '" .. tostring(skip.kind) .. "'"
            end
        end
        if not moved then return pos end
    end
end

local function compile_skip_plans(skips)
    local out = {}
    for i = 1, #skips do
        local skip = skips[i]
        if skip.kind == "WhitespaceSkip" then
            out[i] = { kind = "WhitespaceSkip" }
        elseif skip.kind == "LineCommentSkip" then
            out[i] = { kind = "LineCommentSkip", opener = S(skip.opener) }
        elseif skip.kind == "BlockCommentSkip" then
            out[i] = { kind = "BlockCommentSkip", opener = S(skip.opener), closer = S(skip.closer) }
        elseif skip.kind == "ByteSkip" then
            out[i] = { kind = "ByteSkip", lookup = build_byte_lookup(skip.bitset_words) }
        else
            error("compile_skip_plans: unknown skip kind '" .. tostring(skip.kind) .. "'", 2)
        end
    end
    return out
end

local FRAME_RULE = 1
local FRAME_NEXT = 2
local FRAME_REPEAT = 3
local FRAME_CLOSE = 4
local FRAME_SEPLIST = 5

local function compile_validate(parse_machine)
    local param = parse_machine.param
    local skip_plans = compile_skip_plans(param.skips)

    local first_byte_lookup_by_set_id = {}
    for i = 1, #param.first_byte_sets do
        local row = param.first_byte_sets[i]
        first_byte_lookup_by_set_id[N(row.set_id)] = build_byte_lookup(row.bitset_words)
    end

    local terminal_fns = {}
    for i = 1, #param.terminals do
        local term = param.terminals[i]
        if term.kind == "ExpectFixedToken" then
            local needle = S(term.text)
            local requires_boundary = term.boundary_policy.kind == "RequiresWordBoundary"
            terminal_fns[i] = function(text, len, pos, skip)
                local next_pos, err = skip(text, len, pos)
                if next_pos == nil then return nil, err end
                pos = next_pos
                if pos > len then return nil, "unexpected eof" end
                if not prefix_eq(text, pos, len, needle) then return nil, "expected '" .. needle .. "'" end
                local out = pos + #needle
                if requires_boundary and is_word_continue_byte(byte(text, out)) then
                    return nil, "keyword boundary"
                end
                return out
            end
        elseif term.kind == "ExpectQuotedString" then
            local plan = param.string_plans[N(term.string_id)]
            terminal_fns[i] = function(text, len, pos, skip)
                local next_pos, err = skip(text, len, pos)
                if next_pos == nil then return nil, err end
                pos = next_pos
                if pos > len then return nil, "unexpected eof" end
                return M.scan_quoted_string(text, len, pos, plan.format)
            end
        elseif term.kind == "ExpectNumber" then
            local plan = param.number_plans[N(term.number_id)]
            terminal_fns[i] = function(text, len, pos, skip)
                local next_pos, err = skip(text, len, pos)
                if next_pos == nil then return nil, err end
                pos = next_pos
                if pos > len then return nil, "unexpected eof" end
                return M.scan_number(text, len, pos, plan.format)
            end
        elseif term.kind == "ExpectByteRun" then
            local lookup = build_byte_lookup(term.allowed_bitset_words)
            local min_count = N(term.cardinality.min_count)
            local max_count = N(term.cardinality.max_count)
            terminal_fns[i] = function(text, len, pos, skip)
                local next_pos, err = skip(text, len, pos)
                if next_pos == nil then return nil, err end
                pos = next_pos
                if pos > len then return nil, "unexpected eof" end
                local j = pos
                while j <= len and lookup[byte(text, j)] do j = j + 1 end
                local count = j - pos
                if count < min_count then return nil, "byte run too short" end
                if max_count >= 0 and count > max_count then return nil, "byte run too long" end
                return j
            end
        else
            error("compile_validate: unknown ValidateTerminal kind '" .. tostring(term.kind) .. "'", 2)
        end
    end

    local rule_entry_by_id = {}
    for i = 1, #param.rules do
        local rule = param.rules[i]
        rule_entry_by_id[N(rule.rule_id)] = N(rule.entry_pc)
    end

    local choice_by_id = {}
    for i = 1, #param.choices do
        local choice = param.choices[i]
        local arms = {}
        for j = 1, #choice.arms do
            arms[j] = {
                set_id = N(choice.arms[j].set_id),
                target_pc = N(choice.arms[j].target_pc),
            }
        end
        choice_by_id[N(choice.choice_id)] = arms
    end

    local ops = param.ops

    local function skip(text, len, pos)
        return M.skip_trivia(skip_plans, text, len, pos)
    end

    local function matches_set(set_id, text, len, pos)
        local next_pos, err = skip(text, len, pos)
        if next_pos == nil then return nil, err end
        if next_pos > len then return false, next_pos end
        local lookup = first_byte_lookup_by_set_id[set_id]
        return lookup and lookup[byte(text, next_pos)] or false, next_pos
    end

    return {
        entry_rule_id = N(param.entry_rule_id),
        rule_entry_by_id = rule_entry_by_id,
        choice_by_id = choice_by_id,
        first_byte_lookup_by_set_id = first_byte_lookup_by_set_id,
        terminal_fns = terminal_fns,
        ops = ops,
        skip = skip,
        matches_set = matches_set,
    }
end

function M.compile_validate_machine(U, parse_machine)
    local compiled = compile_validate(parse_machine)
    return U.machine_step(function(param, _, input)
        local text = input_text(input)
        local len = #text
        local pos = 1
        local pc = param.rule_entry_by_id[param.entry_rule_id]
        local stack_kind, stack_a, stack_b, stack_c, stack_d, stack_e = {}, {}, {}, {}, {}, {}
        local sp = 0

        while true do
            local op = param.ops[pc]
            if op == nil then return false, "invalid pc" end

            if op.kind == "ExpectTerminal" then
                local next_pos, err = param.terminal_fns[N(op.terminal_id)](text, len, pos, param.skip)
                if next_pos == nil then return false, err end
                pos = next_pos
                pc = pc + 1

            elseif op.kind == "CallRule" then
                sp = sp + 1
                stack_kind[sp] = FRAME_RULE
                stack_a[sp] = pc + 1
                pc = param.rule_entry_by_id[N(op.rule_id)]

            elseif op.kind == "Choice" then
                local arms = param.choice_by_id[N(op.choice_id)]
                local next_pos, err = param.skip(text, len, pos)
                if next_pos == nil then return false, err end
                pos = next_pos
                if pos > len then return false, "unexpected eof" end
                local c = byte(text, pos)
                local matched = false
                for i = 1, #arms do
                    local lookup = param.first_byte_lookup_by_set_id[arms[i].set_id]
                    if lookup and lookup[c] then
                        sp = sp + 1
                        stack_kind[sp] = FRAME_NEXT
                        stack_a[sp] = pc + 1
                        pc = arms[i].target_pc
                        matched = true
                        break
                    end
                end
                if not matched then return false, "no choice arm matched" end

            elseif op.kind == "OptionalGroup" then
                local matched, next_pos = param.matches_set(N(op.set_id), text, len, pos)
                if matched == nil then return false, next_pos end
                if matched then
                    sp = sp + 1
                    stack_kind[sp] = FRAME_NEXT
                    stack_a[sp] = N(op.next_pc)
                    pos = next_pos
                    pc = N(op.body_pc)
                else
                    pos = next_pos
                    pc = N(op.next_pc)
                end

            elseif op.kind == "RepeatGroup" then
                local matched, next_pos = param.matches_set(N(op.set_id), text, len, pos)
                if matched == nil then return false, next_pos end
                if matched then
                    sp = sp + 1
                    stack_kind[sp] = FRAME_REPEAT
                    stack_a[sp] = N(op.set_id)
                    stack_b[sp] = N(op.body_pc)
                    stack_c[sp] = N(op.next_pc)
                    pos = next_pos
                    pc = N(op.body_pc)
                else
                    pos = next_pos
                    pc = N(op.next_pc)
                end

            elseif op.kind == "DelimitedGroup" then
                local next_pos, err = param.skip(text, len, pos)
                if next_pos == nil then return false, err end
                pos = next_pos
                if pos > len or byte(text, pos) ~= N(op.open_byte) then return false, "expected delimiter open" end
                pos = pos + 1
                sp = sp + 1
                stack_kind[sp] = FRAME_CLOSE
                stack_a[sp] = N(op.close_byte)
                stack_b[sp] = N(op.next_pc)
                pc = N(op.body_pc)

            elseif op.kind == "SeparatedListGroup" then
                local matched, next_pos = param.matches_set(N(op.item_set_id), text, len, pos)
                if matched == nil then return false, next_pos end
                if not matched then
                    if op.cardinality.kind == "ZeroOrMore" then
                        pos = next_pos
                        pc = N(op.next_pc)
                    else
                        return false, "expected list item"
                    end
                else
                    sp = sp + 1
                    stack_kind[sp] = FRAME_SEPLIST
                    stack_a[sp] = N(op.item_set_id)
                    stack_b[sp] = N(op.body_pc)
                    stack_c[sp] = N(op.separator_byte)
                    stack_d[sp] = op.trailing_policy.kind == "OptionalTrailingSeparator" and 1 or 0
                    stack_e[sp] = N(op.next_pc)
                    pos = next_pos
                    pc = N(op.body_pc)
                end

            elseif op.kind == "Return" then
                if sp == 0 then
                    local next_pos, err = param.skip(text, len, pos)
                    if next_pos == nil then return false, err end
                    if next_pos <= len then return false, "unexpected trailing input" end
                    return true
                end

                local frame_kind = stack_kind[sp]
                if frame_kind == FRAME_RULE then
                    pc = stack_a[sp]
                    sp = sp - 1
                elseif frame_kind == FRAME_NEXT then
                    pc = stack_a[sp]
                    sp = sp - 1
                elseif frame_kind == FRAME_REPEAT then
                    local matched, next_pos = param.matches_set(stack_a[sp], text, len, pos)
                    if matched == nil then return false, next_pos end
                    if matched then
                        pos = next_pos
                        pc = stack_b[sp]
                    else
                        pos = next_pos
                        pc = stack_c[sp]
                        sp = sp - 1
                    end
                elseif frame_kind == FRAME_CLOSE then
                    local next_pos, err = param.skip(text, len, pos)
                    if next_pos == nil then return false, err end
                    pos = next_pos
                    if pos > len or byte(text, pos) ~= stack_a[sp] then return false, "expected delimiter close" end
                    pos = pos + 1
                    pc = stack_b[sp]
                    sp = sp - 1
                elseif frame_kind == FRAME_SEPLIST then
                    local next_pos, err = param.skip(text, len, pos)
                    if next_pos == nil then return false, err end
                    pos = next_pos
                    if pos <= len and byte(text, pos) == stack_c[sp] then
                        local after_sep = pos + 1
                        local matched, next_item_pos = param.matches_set(stack_a[sp], text, len, after_sep)
                        if matched == nil then return false, next_item_pos end
                        if matched then
                            pos = next_item_pos
                            pc = stack_b[sp]
                        else
                            if stack_d[sp] == 1 then
                                pos = after_sep
                                pc = stack_e[sp]
                                sp = sp - 1
                            else
                                return false, "expected list item after separator"
                            end
                        end
                    else
                        pc = stack_e[sp]
                        sp = sp - 1
                    end
                else
                    return false, "unknown frame kind"
                end
            else
                return false, "unknown op kind '" .. tostring(op.kind) .. "'"
            end
        end
    end, compiled, nil, "frontendc2_structural_validate")
end

return M
