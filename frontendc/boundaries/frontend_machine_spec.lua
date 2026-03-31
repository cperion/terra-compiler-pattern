local ffi = require("ffi")
local bit = require("bit")

local band = bit.band
local bor = bit.bor
local lshift = bit.lshift
local byte = string.byte
local sub = string.sub
local sort = table.sort

return function(T, U, P)
    local _loadstring = loadstring
    local _load = load
    local _setfenv = setfenv

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

    local function load_chunk(source, chunkname, env)
        if _loadstring then
            local fn, err = _loadstring(source, chunkname)
            if not fn then error(err, 2) end
            if env then _setfenv(fn, env) end
            return fn()
        end
        local fn, err = _load(source, chunkname, "t", env)
        if not fn then error(err, 2) end
        return fn()
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

    local function snake_part(part)
        local s = tostring(part)
        s = s:gsub("(%u)(%u%l)", "%1_%2")
        s = s:gsub("(%l%d)(%u)", "%1_%2")
        s = s:gsub("(%l)(%u)", "%1_%2")
        s = s:gsub("[^%w]+", "_")
        return s:lower()
    end

    local function emitted_boundary_path(receiver_fqname)
        local parts = {}
        for part in S(receiver_fqname):gmatch("[^.]+") do
            parts[#parts + 1] = snake_part(part)
        end
        return "boundaries/" .. table.concat(parts, "_") .. ".lua"
    end

    local function lua_quote(v)
        return string.format("%q", S(v))
    end

    local function lua_bool(v)
        return v and "true" or "false"
    end

    local function lua_num(v)
        return tostring(N(v))
    end

    local function lua_number_list(xs)
        local parts = {}
        for i = 1, #xs do
            parts[i] = lua_num(xs[i])
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end

    local function path_expr(root, path)
        local out = root
        local parts = path.parts or path
        for i = 1, #parts do
            out = out .. "." .. S(parts[i])
        end
        return out
    end

    local function token_ids_from_words(words)
        local ids = {}
        for wi = 1, #words do
            local word = N(words[wi] or 0) or 0
            for bit_index = 0, 31 do
                if band(word, lshift(1, bit_index)) ~= 0 then
                    ids[#ids + 1] = (wi - 1) * 32 + bit_index
                end
            end
        end
        return ids
    end

    local function first_set_expr_from_words(words, token_var)
        local ids = token_ids_from_words(words)
        if #ids == 0 then return "false" end
        local parts = {}
        for i = 1, #ids do
            parts[i] = token_var .. " == " .. tostring(ids[i])
        end
        return "(" .. table.concat(parts, " or ") .. ")"
    end

    local function collect_slots_from_steps(steps, seen)
        seen = seen or {}
        for i = 1, #steps do
            local step = steps[i]
            if step.kind == "ExpectToken" or step.kind == "CallRule" then
                local slot_id = N(step.capture_slot)
                if slot_id and slot_id > 0 then seen[slot_id] = true end
            elseif step.kind == "OptionalGroup" or step.kind == "RepeatGroup" then
                collect_slots_from_steps(step.body, seen)
            else
                error("FrontendMachine.Spec:emit_lua(): unknown Step kind '" .. tostring(step.kind) .. "'", 2)
            end
        end
        return seen
    end

    local function collect_slots_from_result(plan, seen)
        seen = seen or {}
        if plan.kind == "ReturnSlot" then
            local slot_id = N(plan.slot_id)
            if slot_id and slot_id > 0 then seen[slot_id] = true end
        elseif plan.kind == "ReturnCtor" then
            for i = 1, #plan.args do
                local arg = plan.args[i]
                if arg.kind == "ReadSlot" or arg.kind == "ReadPresent" or arg.kind == "ReadJoined" then
                    local slot_id = N(arg.slot_id)
                    if slot_id and slot_id > 0 then seen[slot_id] = true end
                elseif arg.kind ~= "ReadConstBool" then
                    error("FrontendMachine.Spec:emit_lua(): unknown ArgSource kind '" .. tostring(arg.kind) .. "'", 2)
                end
            end
        elseif plan.kind ~= "ReturnEmpty" then
            error("FrontendMachine.Spec:emit_lua(): unknown ResultPlan kind '" .. tostring(plan.kind) .. "'", 2)
        end
        return seen
    end

    local function sorted_slot_ids(seen)
        local out = {}
        for slot_id in pairs(seen) do
            out[#out + 1] = slot_id
        end
        table.sort(out)
        return out
    end

    local function emit_capture_lines(lines, indent, slot_id, value_expr)
        slot_id = N(slot_id)
        if slot_id == nil or slot_id <= 0 then return end
        local slot_name = "slot_" .. tostring(slot_id)
        lines[#lines + 1] = indent .. "if " .. slot_name .. " == nil then"
        lines[#lines + 1] = indent .. "    " .. slot_name .. " = " .. value_expr
        lines[#lines + 1] = indent .. "elseif type(" .. slot_name .. ") == \"table\" and " .. slot_name .. ".__capture_list then"
        lines[#lines + 1] = indent .. "    " .. slot_name .. "[#" .. slot_name .. " + 1] = " .. value_expr
        lines[#lines + 1] = indent .. "else"
        lines[#lines + 1] = indent .. "    " .. slot_name .. " = { " .. slot_name .. ", " .. value_expr .. ", __capture_list = true }"
        lines[#lines + 1] = indent .. "end"
    end

    local function result_expr_lua(plan)
        if plan.kind == "ReturnEmpty" then
            return "nil"
        elseif plan.kind == "ReturnSlot" then
            return "slot_" .. tostring(N(plan.slot_id))
        elseif plan.kind == "ReturnCtor" then
            local args = {}
            for i = 1, #plan.args do
                local arg = plan.args[i]
                if arg.kind == "ReadSlot" then
                    args[i] = "slot_" .. tostring(N(arg.slot_id))
                elseif arg.kind == "ReadPresent" then
                    args[i] = "(slot_" .. tostring(N(arg.slot_id)) .. " ~= nil)"
                elseif arg.kind == "ReadJoined" then
                    args[i] = "join_capture(slot_" .. tostring(N(arg.slot_id)) .. ", " .. lua_quote(arg.separator) .. ")"
                elseif arg.kind == "ReadConstBool" then
                    args[i] = lua_bool(B(arg.value))
                else
                    error("FrontendMachine.Spec:emit_lua(): unknown ArgSource kind '" .. tostring(arg.kind) .. "'", 2)
                end
            end
            return "ctor_" .. tostring(N(plan.ctor_id)) .. "(" .. table.concat(args, ", ") .. ")"
        end
        error("FrontendMachine.Spec:emit_lua(): unknown ResultPlan kind '" .. tostring(plan.kind) .. "'", 2)
    end

    local function emit_steps_lua(lines, steps, indent, first_set_expr_by_id)
        for i = 1, #steps do
            local step = steps[i]
            if step.kind == "ExpectToken" then
                lines[#lines + 1] = indent .. "do"
                lines[#lines + 1] = indent .. "    local tok = tokens[pos]"
                lines[#lines + 1] = indent .. "    if tok == nil or tok.token_id ~= " .. lua_num(step.header.token_id) .. " then"
                lines[#lines + 1] = indent .. "        error(\"generated parse machine expected token '" .. S(step.header.name) .. "'\", 2)"
                lines[#lines + 1] = indent .. "    end"
                if N(step.capture_slot) > 0 then
                    lines[#lines + 1] = indent .. "    local captured = token_value(tok)"
                    emit_capture_lines(lines, indent .. "    ", step.capture_slot, "captured")
                end
                lines[#lines + 1] = indent .. "    pos = pos + 1"
                lines[#lines + 1] = indent .. "end"
            elseif step.kind == "CallRule" then
                lines[#lines + 1] = indent .. "do"
                lines[#lines + 1] = indent .. "    local value"
                lines[#lines + 1] = indent .. "    value, pos = rule_" .. tostring(N(step.header.rule_id)) .. "(tokens, pos)"
                if N(step.capture_slot) > 0 then
                    emit_capture_lines(lines, indent .. "    ", step.capture_slot, "value")
                end
                lines[#lines + 1] = indent .. "end"
            elseif step.kind == "OptionalGroup" then
                lines[#lines + 1] = indent .. "do"
                lines[#lines + 1] = indent .. "    local tok = tokens[pos]"
                lines[#lines + 1] = indent .. "    local tok_id = tok and tok.token_id"
                lines[#lines + 1] = indent .. "    if " .. first_set_expr_by_id[N(step.set_id)] .. " then"
                emit_steps_lua(lines, step.body, indent .. "        ", first_set_expr_by_id)
                lines[#lines + 1] = indent .. "    end"
                lines[#lines + 1] = indent .. "end"
            elseif step.kind == "RepeatGroup" then
                lines[#lines + 1] = indent .. "while true do"
                lines[#lines + 1] = indent .. "    local tok = tokens[pos]"
                lines[#lines + 1] = indent .. "    local tok_id = tok and tok.token_id"
                lines[#lines + 1] = indent .. "    if not (" .. first_set_expr_by_id[N(step.set_id)] .. ") then break end"
                emit_steps_lua(lines, step.body, indent .. "    ", first_set_expr_by_id)
                lines[#lines + 1] = indent .. "end"
            else
                error("FrontendMachine.Spec:emit_lua(): unknown Step kind '" .. tostring(step.kind) .. "'", 2)
            end
        end
    end

    local function emit_rule_function(lines, plan, first_set_expr_by_id)
        local seen = collect_slots_from_steps(plan.body, {})
        collect_slots_from_result(plan.result, seen)
        for i = 1, #plan.choice_arms do
            collect_slots_from_steps(plan.choice_arms[i].body, seen)
        end
        local slot_ids = sorted_slot_ids(seen)
        local rule_id = N(plan.header.rule_id)
        local rule_kind = S(plan.kind.kind)

        lines[#lines + 1] = "    rule_" .. tostring(rule_id) .. " = function(tokens, pos)"
        if #slot_ids > 0 then
            local names = {}
            for i = 1, #slot_ids do
                names[i] = "slot_" .. tostring(slot_ids[i])
            end
            lines[#lines + 1] = "        local " .. table.concat(names, ", ")
        end

        if rule_kind == "ChoiceRuleKind" then
            lines[#lines + 1] = "        local tok = tokens[pos]"
            lines[#lines + 1] = "        if tok == nil then error(\"generated parse machine unexpected eof in choice rule\", 2) end"
            lines[#lines + 1] = "        local tok_id = tok.token_id"
            for i = 1, #plan.choice_arms do
                local arm = plan.choice_arms[i]
                local prefix = (i == 1) and "        if " or "        elseif "
                lines[#lines + 1] = prefix .. first_set_expr_by_id[N(arm.set_id)] .. " then"
                emit_steps_lua(lines, arm.body, "            ", first_set_expr_by_id)
                lines[#lines + 1] = "            return " .. result_expr_lua(plan.result) .. ", pos"
            end
            lines[#lines + 1] = "        end"
            lines[#lines + 1] = "        error(\"generated parse machine no choice arm matched token id '\" .. tostring(tok_id) .. \"'\", 2)"
        else
            emit_steps_lua(lines, plan.body, "        ", first_set_expr_by_id)
            lines[#lines + 1] = "        return " .. result_expr_lua(plan.result) .. ", pos"
        end

        lines[#lines + 1] = "    end"
    end

    local function combined_ident_continue_words(machine)
        local out = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for i = 1, #machine.ident_dispatches do
            local words = machine.ident_dispatches[i].continue_bitset_words
            for wi = 1, math.max(#out, #words) do
                out[wi] = bor(N(out[wi] or 0), N(words[wi] or 0))
            end
        end
        return out
    end

    local function sorted_line_comment_openers(machine)
        local out = {}
        for i = 1, #machine.skips do
            local skip = machine.skips[i]
            if skip.kind == "LineCommentSkip" then
                out[#out + 1] = S(skip.opener)
            end
        end
        table.sort(out, function(a, b) return #a > #b end)
        return out
    end

    local function emit_tokenize_file(spec)
        local receiver_fqname = path_expr("T", spec.tokenize.header.receiver_path):sub(3)
        local verb = S(spec.tokenize.header.verb)
        local machine = spec.tokenize.machine
        local lines = {
            "local ffi = require(\"ffi\")",
            "local bit = require(\"bit\")",
            "",
            "local band = bit.band",
            "local lshift = bit.lshift",
            "local byte = string.byte",
            "local sub = string.sub",
            "",
            "return function(T, U, P)",
            "    local function S(v)",
            "        if type(v) == \"cdata\" then return ffi.string(v) end",
            "        return tostring(v)",
            "    end",
            "",
            "    local output_spec_ctor = " .. path_expr("T", spec.tokenize.output_spec_ctor_path),
            "    local token_cell_ctor = " .. path_expr("T", spec.tokenize.token_cell_ctor_path),
            "    local span_ctor = " .. path_expr("T", spec.tokenize.span_ctor_path),
            "    local eof_token_id = " .. lua_num(machine.eof_header.token_id),
            "    local ident_continue_words = " .. lua_number_list(combined_ident_continue_words(machine)),
        }

        for i = 1, #machine.ident_dispatches do
            local dispatch = machine.ident_dispatches[i]
            lines[#lines + 1] = "    local ident_start_words_" .. tostring(i) .. " = " .. lua_number_list(dispatch.start_bitset_words)
            lines[#lines + 1] = "    local ident_continue_words_" .. tostring(i) .. " = " .. lua_number_list(dispatch.continue_bitset_words)
        end

        lines[#lines + 1] = ""
        lines[#lines + 1] = "    local function bitset_has(words, c)"
        lines[#lines + 1] = "        local wi = math.floor(c / 32) + 1"
        lines[#lines + 1] = "        return band(words[wi] or 0, lshift(1, c % 32)) ~= 0"
        lines[#lines + 1] = "    end"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "    local function scan_quoted_string(text, len, start, quote_byte, backslash_escapes)"
        lines[#lines + 1] = "        local i = start + 1"
        lines[#lines + 1] = "        local pieces = nil"
        lines[#lines + 1] = "        local chunk_start = i"
        lines[#lines + 1] = "        while i <= len do"
        lines[#lines + 1] = "            local c = byte(text, i)"
        lines[#lines + 1] = "            if c == quote_byte then"
        lines[#lines + 1] = "                if pieces == nil then return sub(text, chunk_start, i - 1), i end"
        lines[#lines + 1] = "                pieces[#pieces + 1] = sub(text, chunk_start, i - 1)"
        lines[#lines + 1] = "                return table.concat(pieces), i"
        lines[#lines + 1] = "            elseif c == 92 and backslash_escapes then"
        lines[#lines + 1] = "                pieces = pieces or {}"
        lines[#lines + 1] = "                pieces[#pieces + 1] = sub(text, chunk_start, i - 1)"
        lines[#lines + 1] = "                i = i + 1"
        lines[#lines + 1] = "                if i > len then error(\"generated tokenize machine unterminated escape sequence\", 2) end"
        lines[#lines + 1] = "                local esc = byte(text, i)"
        lines[#lines + 1] = "                if esc == 34 then pieces[#pieces + 1] = '\"'"
        lines[#lines + 1] = "                elseif esc == 92 then pieces[#pieces + 1] = '\\\\'"
        lines[#lines + 1] = "                elseif esc == 47 then pieces[#pieces + 1] = '/'"
        lines[#lines + 1] = "                elseif esc == 98 then pieces[#pieces + 1] = '\\b'"
        lines[#lines + 1] = "                elseif esc == 102 then pieces[#pieces + 1] = '\\f'"
        lines[#lines + 1] = "                elseif esc == 110 then pieces[#pieces + 1] = '\\n'"
        lines[#lines + 1] = "                elseif esc == 114 then pieces[#pieces + 1] = '\\r'"
        lines[#lines + 1] = "                elseif esc == 116 then pieces[#pieces + 1] = '\\t'"
        lines[#lines + 1] = "                else error(\"generated tokenize machine unsupported string escape\", 2) end"
        lines[#lines + 1] = "                i = i + 1"
        lines[#lines + 1] = "                chunk_start = i"
        lines[#lines + 1] = "            elseif c < 32 then"
        lines[#lines + 1] = "                error(\"generated tokenize machine control char in string\", 2)"
        lines[#lines + 1] = "            else"
        lines[#lines + 1] = "                i = i + 1"
        lines[#lines + 1] = "            end"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        error(\"generated tokenize machine unterminated string\", 2)"
        lines[#lines + 1] = "    end"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "    local function scan_number(text, len, start)"
        lines[#lines + 1] = "        local i = start"
        lines[#lines + 1] = "        local c = byte(text, i)"
        lines[#lines + 1] = "        if c == 45 then"
        lines[#lines + 1] = "            i = i + 1"
        lines[#lines + 1] = "            if i > len then error(\"generated tokenize machine invalid number\", 2) end"
        lines[#lines + 1] = "            c = byte(text, i)"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        if c == 48 then"
        lines[#lines + 1] = "            i = i + 1"
        lines[#lines + 1] = "        elseif c and c >= 49 and c <= 57 then"
        lines[#lines + 1] = "            i = i + 1"
        lines[#lines + 1] = "            while i <= len do"
        lines[#lines + 1] = "                c = byte(text, i)"
        lines[#lines + 1] = "                if c < 48 or c > 57 then break end"
        lines[#lines + 1] = "                i = i + 1"
        lines[#lines + 1] = "            end"
        lines[#lines + 1] = "        else"
        lines[#lines + 1] = "            error(\"generated tokenize machine invalid number\", 2)"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        if i <= len and byte(text, i) == 46 then"
        lines[#lines + 1] = "            i = i + 1"
        lines[#lines + 1] = "            if i > len then error(\"generated tokenize machine invalid number\", 2) end"
        lines[#lines + 1] = "            c = byte(text, i)"
        lines[#lines + 1] = "            if c < 48 or c > 57 then error(\"generated tokenize machine invalid number\", 2) end"
        lines[#lines + 1] = "            repeat"
        lines[#lines + 1] = "                i = i + 1"
        lines[#lines + 1] = "                c = i <= len and byte(text, i) or nil"
        lines[#lines + 1] = "            until not c or c < 48 or c > 57"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        if i <= len then"
        lines[#lines + 1] = "            c = byte(text, i)"
        lines[#lines + 1] = "            if c == 69 or c == 101 then"
        lines[#lines + 1] = "                i = i + 1"
        lines[#lines + 1] = "                if i <= len then"
        lines[#lines + 1] = "                    c = byte(text, i)"
        lines[#lines + 1] = "                    if c == 43 or c == 45 then i = i + 1 end"
        lines[#lines + 1] = "                end"
        lines[#lines + 1] = "                if i > len then error(\"generated tokenize machine invalid number\", 2) end"
        lines[#lines + 1] = "                c = byte(text, i)"
        lines[#lines + 1] = "                if c < 48 or c > 57 then error(\"generated tokenize machine invalid number\", 2) end"
        lines[#lines + 1] = "                repeat"
        lines[#lines + 1] = "                    i = i + 1"
        lines[#lines + 1] = "                    c = i <= len and byte(text, i) or nil"
        lines[#lines + 1] = "                until not c or c < 48 or c > 57"
        lines[#lines + 1] = "            end"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        return sub(text, start, i - 1), i - 1"
        lines[#lines + 1] = "    end"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "    local impl = U.transition(" .. lua_quote(receiver_fqname .. ":" .. verb) .. ", function(input)"
        lines[#lines + 1] = "        local text = S(input.text)"
        lines[#lines + 1] = "        local len = #text"
        lines[#lines + 1] = "        local pos = 1"
        lines[#lines + 1] = "        local items = {}"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "        while true do"
        lines[#lines + 1] = "            while true do"
        lines[#lines + 1] = "                local moved = false"
        lines[#lines + 1] = "                while pos <= len do"
        lines[#lines + 1] = "                    local c = byte(text, pos)"
        lines[#lines + 1] = "                    if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then break end"
        lines[#lines + 1] = "                    pos = pos + 1"
        lines[#lines + 1] = "                    moved = true"
        lines[#lines + 1] = "                end"

        local openers = sorted_line_comment_openers(machine)
        if #openers > 0 then
            lines[#lines + 1] = "                if pos <= len then"
            for i = 1, #openers do
                local opener = openers[i]
                local prefix = (i == 1) and "                    if " or "                    elseif "
                lines[#lines + 1] = prefix .. "sub(text, pos, pos + " .. tostring(#opener - 1) .. ") == " .. lua_quote(opener) .. " then"
                lines[#lines + 1] = "                        pos = pos + " .. tostring(#opener)
                lines[#lines + 1] = "                        while pos <= len and byte(text, pos) ~= 10 do pos = pos + 1 end"
                lines[#lines + 1] = "                        if pos <= len then pos = pos + 1 end"
                lines[#lines + 1] = "                        moved = true"
            end
            lines[#lines + 1] = "                    end"
            lines[#lines + 1] = "                end"
        end

        lines[#lines + 1] = "                if not moved then break end"
        lines[#lines + 1] = "            end"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "            if pos > len then"
        lines[#lines + 1] = "                items[#items + 1] = token_cell_ctor(eof_token_id, nil, span_ctor(len + 1, len + 1))"
        lines[#lines + 1] = "                break"
        lines[#lines + 1] = "            end"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "            local start = pos"
        lines[#lines + 1] = "            local c = byte(text, start)"
        lines[#lines + 1] = ""

        for i = 1, #machine.fixed_dispatches do
            local dispatch = machine.fixed_dispatches[i]
            local prefix = (i == 1) and "            if " or "            elseif "
            lines[#lines + 1] = prefix .. "c == " .. lua_num(dispatch.first_byte) .. " then"
            for j = 1, #dispatch.cases do
                local case = dispatch.cases[j]
                lines[#lines + 1] = "                do"
                lines[#lines + 1] = "                    local stop = start + " .. tostring(#S(case.text) - 1)
                lines[#lines + 1] = "                    if stop <= len and sub(text, start, stop) == " .. lua_quote(case.text) .. " then"
                lines[#lines + 1] = "                        local next_pos = stop + 1"
                if B(case.requires_word_boundary) then
                    lines[#lines + 1] = "                        if next_pos > len or not bitset_has(ident_continue_words, byte(text, next_pos)) then"
                    lines[#lines + 1] = "                            pos = next_pos"
                    lines[#lines + 1] = "                            items[#items + 1] = token_cell_ctor(" .. lua_num(case.header.token_id) .. ", nil, span_ctor(start, stop))"
                    lines[#lines + 1] = "                            goto continue"
                    lines[#lines + 1] = "                        end"
                else
                    lines[#lines + 1] = "                        pos = next_pos"
                    lines[#lines + 1] = "                        items[#items + 1] = token_cell_ctor(" .. lua_num(case.header.token_id) .. ", nil, span_ctor(start, stop))"
                    lines[#lines + 1] = "                        goto continue"
                end
                lines[#lines + 1] = "                    end"
                lines[#lines + 1] = "                end"
            end
        end
        if #machine.fixed_dispatches > 0 then
            lines[#lines + 1] = "            end"
            lines[#lines + 1] = ""
        end

        for i = 1, #machine.quoted_string_dispatches do
            local dispatch = machine.quoted_string_dispatches[i]
            lines[#lines + 1] = "            if c == " .. lua_num(dispatch.quote_byte) .. " then"
            lines[#lines + 1] = "                local value, stop = scan_quoted_string(text, len, start, " .. lua_num(dispatch.quote_byte) .. ", " .. lua_bool(B(dispatch.backslash_escapes)) .. ")"
            lines[#lines + 1] = "                pos = stop + 1"
            lines[#lines + 1] = "                items[#items + 1] = token_cell_ctor(" .. lua_num(dispatch.header.token_id) .. ", value, span_ctor(start, stop))"
            lines[#lines + 1] = "                goto continue"
            lines[#lines + 1] = "            end"
        end
        if #machine.quoted_string_dispatches > 0 then
            lines[#lines + 1] = ""
        end

        for i = 1, #machine.ident_dispatches do
            local dispatch = machine.ident_dispatches[i]
            lines[#lines + 1] = "            if bitset_has(ident_start_words_" .. tostring(i) .. ", c) then"
            lines[#lines + 1] = "                local stop = start"
            lines[#lines + 1] = "                while stop + 1 <= len and bitset_has(ident_continue_words_" .. tostring(i) .. ", byte(text, stop + 1)) do"
            lines[#lines + 1] = "                    stop = stop + 1"
            lines[#lines + 1] = "                end"
            lines[#lines + 1] = "                pos = stop + 1"
            local payload_expr = (S(dispatch.header.payload_shape.kind) == "StringTokenPayload") and "sub(text, start, stop)" or "nil"
            lines[#lines + 1] = "                items[#items + 1] = token_cell_ctor(" .. lua_num(dispatch.header.token_id) .. ", " .. payload_expr .. ", span_ctor(start, stop))"
            lines[#lines + 1] = "                goto continue"
            lines[#lines + 1] = "            end"
        end
        if #machine.ident_dispatches > 0 then
            lines[#lines + 1] = ""
        end

        if #machine.number_dispatches > 0 then
            local dispatch = machine.number_dispatches[1]
            lines[#lines + 1] = "            if c == 45 or (c >= 48 and c <= 57) then"
            lines[#lines + 1] = "                local value, stop = scan_number(text, len, start)"
            lines[#lines + 1] = "                pos = stop + 1"
            lines[#lines + 1] = "                items[#items + 1] = token_cell_ctor(" .. lua_num(dispatch.header.token_id) .. ", value, span_ctor(start, stop))"
            lines[#lines + 1] = "                goto continue"
            lines[#lines + 1] = "            end"
            lines[#lines + 1] = ""
        end

        lines[#lines + 1] = "            error(\"generated tokenize machine invalid token at byte \" .. tostring(start), 2)"
        lines[#lines + 1] = "            ::continue::"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "        return output_spec_ctor(items)"
        lines[#lines + 1] = "    end)"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "    " .. path_expr("T", spec.tokenize.header.receiver_path) .. "." .. verb .. " = impl"
        lines[#lines + 1] = "end"
        lines[#lines + 1] = ""

        return T.FrontendLua.BoundaryFile(
            emitted_boundary_path(receiver_fqname),
            receiver_fqname,
            verb,
            table.concat(lines, "\n")
        )
    end

    local function emit_parse_file(spec)
        local receiver_fqname = path_expr("T", spec.parse.header.receiver_path):sub(3)
        local verb = S(spec.parse.header.verb)
        local parse_machine = spec.parse.machine
        local lines = {
            "return function(T, U, P)",
            "    local output_spec_ctor = " .. path_expr("T", spec.parse.output_spec_ctor_path),
        }

        for i = 1, #spec.parse.result_ctors do
            local ctor = spec.parse.result_ctors[i]
            lines[#lines + 1] = "    local ctor_" .. tostring(N(ctor.ctor_id)) .. " = " .. path_expr("T", ctor.ctor_path)
        end

        local first_set_expr_by_id = {}
        for i = 1, #parse_machine.first_sets do
            local row = parse_machine.first_sets[i]
            first_set_expr_by_id[N(row.set_id)] = first_set_expr_from_words(row.bitset_words, "tok_id")
        end

        lines[#lines + 1] = ""
        lines[#lines + 1] = "    local function token_value(tok)"
        lines[#lines + 1] = "        if tok.text ~= nil then return tok.text end"
        lines[#lines + 1] = "        return tok"
        lines[#lines + 1] = "    end"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "    local function join_capture(v, sep)"
        lines[#lines + 1] = "        if v == nil then return \"\" end"
        lines[#lines + 1] = "        if type(v) == \"table\" and v.__capture_list then"
        lines[#lines + 1] = "            local xs = {}"
        lines[#lines + 1] = "            for i = 1, #v do xs[i] = tostring(v[i]) end"
        lines[#lines + 1] = "            return table.concat(xs, sep)"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        return tostring(v)"
        lines[#lines + 1] = "    end"
        lines[#lines + 1] = ""

        local rule_ids = {}
        for i = 1, #parse_machine.rules do
            rule_ids[i] = N(parse_machine.rules[i].header.rule_id)
            lines[#lines + 1] = "    local rule_" .. tostring(rule_ids[i])
        end
        if #rule_ids > 0 then lines[#lines + 1] = "" end

        for i = 1, #parse_machine.rules do
            emit_rule_function(lines, parse_machine.rules[i], first_set_expr_by_id)
            lines[#lines + 1] = ""
        end

        lines[#lines + 1] = "    local impl = U.transition(" .. lua_quote(receiver_fqname .. ":" .. verb) .. ", function(input)"
        lines[#lines + 1] = "        local tokens = input.items or input.tokens"
        lines[#lines + 1] = "        local value, pos = rule_" .. tostring(N(parse_machine.entry_rule.rule_id)) .. "(tokens, 1)"
        lines[#lines + 1] = "        local tail = tokens[pos]"
        lines[#lines + 1] = "        if tail == nil or tail.token_id ~= " .. lua_num(spec.tokenize.machine.eof_header.token_id) .. " then"
        lines[#lines + 1] = "            error(\"generated parse machine expected eof\", 2)"
        lines[#lines + 1] = "        end"
        lines[#lines + 1] = "        return output_spec_ctor(value)"
        lines[#lines + 1] = "    end)"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "    " .. path_expr("T", spec.parse.header.receiver_path) .. "." .. verb .. " = impl"
        lines[#lines + 1] = "end"
        lines[#lines + 1] = ""

        return T.FrontendLua.BoundaryFile(
            emitted_boundary_path(receiver_fqname),
            receiver_fqname,
            verb,
            table.concat(lines, "\n")
        )
    end

    local emit_lua_impl = U.transition(function(spec)
        return T.FrontendLua.Spec({
            emit_tokenize_file(spec),
            emit_parse_file(spec),
        })
    end)

    function T.FrontendMachine.Spec:emit_lua()
        return emit_lua_impl(self)
    end

    local install_generated_impl = U.terminal(function(spec, ctx)
        local out = emit_lua_impl(spec)
        for i = 1, #out.files do
            local file = out.files[i]
            local installer = load_chunk(S(file.lua_source), "@" .. S(file.path), _G)
            installer(ctx, U, P)
        end
        return ctx
    end)

    function T.FrontendMachine.Spec:install_generated(ctx)
        return install_generated_impl(self, ctx)
    end
end
