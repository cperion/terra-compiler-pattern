local ffi = require("ffi")
local bit = require("bit")

local bor = bit.bor
local lshift = bit.lshift

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

    local CT = T.FrontendChecked

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
        error("FrontendSource.Spec:check(): unknown CharSet kind '" .. tostring(kind) .. "'", 2)
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

    local function checked_charset(source_charset)
        return CT.CheckedCharSet(lookup_to_words(build_charset_lookup(source_charset)))
    end

    local function token_header_value_shape(token_def)
        if token_def.kind == "IdentToken"
            or token_def.kind == "QuotedStringToken"
            or token_def.kind == "NumberToken" then
            return CT.StringTokenPayload
        end
        return CT.NoTokenPayload
    end

    local function clone_info(info)
        return {
            value_kind = info.value_kind,
            is_list = info.is_list and true or false,
            nullable = info.nullable and true or false,
        }
    end

    local function same_info(a, b)
        if a == nil or b == nil then return a == b end
        return a.value_kind == b.value_kind
            and (a.is_list and true or false) == (b.is_list and true or false)
            and (a.nullable and true or false) == (b.nullable and true or false)
    end

    local function infer_capture_shape(info)
        if info.is_list then return CT.ListSlot end
        if info.nullable and info.value_kind == "none" then return CT.PresenceSlot end
        return CT.SingleSlot
    end

    local function infer_value_shape_from_info(info)
        if info == nil then return nil end
        if info.is_list then return CT.ListValue end
        if info.value_kind == "string" then return CT.StringValue end
        if info.value_kind == "node" then return CT.NodeValue end
        if info.value_kind == "bool" then return CT.BoolValue end
        return nil
    end

    local function token_info_from_def(token_def)
        return {
            value_kind = (
                token_def.kind == "IdentToken"
                or token_def.kind == "QuotedStringToken"
                or token_def.kind == "NumberToken"
            ) and "string" or "none",
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

    local check_impl = U.transition(function(spec)
        local token_header_by_name = {}
        local token_def_by_name = {}
        local checked_tokens = {}

        for i = 1, #spec.lexer.tokens do
            local token = spec.lexer.tokens[i]
            local name = S(token.name)
            if token_header_by_name[name] ~= nil then
                error("FrontendSource.Spec:check(): duplicate token '" .. name .. "'", 2)
            end

            token_def_by_name[name] = token
            local header = CT.TokenHeader(name, i, token_header_value_shape(token))
            token_header_by_name[name] = header

            if token.kind == "KeywordToken" then
                checked_tokens[i] = CT.KeywordToken(header, S(token.text))
            elseif token.kind == "PunctToken" then
                checked_tokens[i] = CT.PunctToken(header, S(token.text))
            elseif token.kind == "IdentToken" then
                checked_tokens[i] = CT.IdentToken(header, checked_charset(token.start_set), checked_charset(token.continue_set))
            elseif token.kind == "QuotedStringToken" then
                local quote_char = S(token.quote_char)
                if #quote_char ~= 1 then
                    error("FrontendSource.Spec:check(): QuotedStringToken requires a one-byte quote_char", 2)
                end
                checked_tokens[i] = CT.QuotedStringToken(header, quote_char, B(token.backslash_escapes))
            elseif token.kind == "NumberToken" then
                checked_tokens[i] = CT.NumberToken(header)
            else
                error("FrontendSource.Spec:check(): unknown TokenDef kind '" .. tostring(token.kind) .. "'", 2)
            end
        end

        local checked_skips = {}
        for i = 1, #spec.lexer.skips do
            local skip = spec.lexer.skips[i]
            if skip.kind == "WhitespaceSkip" then
                checked_skips[i] = CT.WhitespaceSkip
            elseif skip.kind == "LineCommentSkip" then
                checked_skips[i] = CT.LineCommentSkip(S(skip.opener))
            else
                error("FrontendSource.Spec:check(): unknown SkipRule kind '" .. tostring(skip.kind) .. "'", 2)
            end
        end

        local rule_header_by_name = {}
        local source_rule_by_name = {}
        for i = 1, #spec.parser.rules do
            local rule = spec.parser.rules[i]
            local name = S(rule.name)
            if rule_header_by_name[name] ~= nil then
                error("FrontendSource.Spec:check(): duplicate rule '" .. name .. "'", 2)
            end
            rule_header_by_name[name] = CT.RuleHeader(name, i)
            source_rule_by_name[name] = rule
        end

        local entry_rule = rule_header_by_name[S(spec.parser.entry_rule_name)]
        if entry_rule == nil then
            error("FrontendSource.Spec:check(): unknown entry rule '" .. S(spec.parser.entry_rule_name) .. "'", 2)
        end

        local result_info_by_rule = {}
        for i = 1, #spec.parser.rules do
            local rule = spec.parser.rules[i]
            result_info_by_rule[S(rule.name)] = {
                value_kind = "unknown",
                is_list = false,
                nullable = false,
            }
        end

        local infer_result_info_from_source_result

        local function analyze_expr_info(expr, capture_info_by_name, rule_name)
            if expr.kind == "TokenRef" then
                local token_name = S(expr.token_name)
                local token_def = token_def_by_name[token_name]
                if token_def == nil then
                    error("FrontendSource.Spec:check(): unknown token ref '" .. token_name .. "' in rule '" .. rule_name .. "'", 2)
                end
                return token_info_from_def(token_def)
            elseif expr.kind == "RuleRef" then
                local ref_name = S(expr.rule_name)
                if rule_header_by_name[ref_name] == nil then
                    error("FrontendSource.Spec:check(): unknown rule ref '" .. ref_name .. "' in rule '" .. rule_name .. "'", 2)
                end
                return clone_info(result_info_by_rule[ref_name])
            elseif expr.kind == "Seq" then
                local infos = {}
                for i = 1, #expr.items do
                    infos[i] = analyze_expr_info(expr.items[i], capture_info_by_name, rule_name)
                end
                local out = nil
                local count = 0
                for i = 1, #infos do
                    local info = infos[i]
                    if info.value_kind ~= "none" or info.is_list then
                        count = count + 1
                        out = clone_info(info)
                    end
                end
                if count == 1 then
                    return out
                end
                return { value_kind = "none", is_list = false, nullable = false }
            elseif expr.kind == "Choice" then
                local infos = {}
                for i = 1, #expr.alts do
                    infos[i] = analyze_expr_info(expr.alts[i], capture_info_by_name, rule_name)
                end
                return choice_info(infos)
            elseif expr.kind == "Optional" then
                local inner_info = analyze_expr_info(expr.inner, capture_info_by_name, rule_name)
                local out = clone_info(inner_info)
                out.nullable = true
                return out
            elseif expr.kind == "Many" then
                local inner_info = analyze_expr_info(expr.inner, capture_info_by_name, rule_name)
                return {
                    value_kind = inner_info.value_kind,
                    is_list = true,
                    nullable = true,
                }
            elseif expr.kind == "OneOrMore" then
                local inner_info = analyze_expr_info(expr.inner, capture_info_by_name, rule_name)
                return {
                    value_kind = inner_info.value_kind,
                    is_list = true,
                    nullable = false,
                }
            elseif expr.kind == "Capture" then
                local capture_name = S(expr.capture_name)
                if capture_info_by_name[capture_name] ~= nil then
                    error("FrontendSource.Spec:check(): duplicate capture '" .. capture_name .. "' in rule '" .. rule_name .. "'", 2)
                end
                local inner_info = analyze_expr_info(expr.inner, capture_info_by_name, rule_name)
                capture_info_by_name[capture_name] = clone_info(inner_info)
                return inner_info
            elseif expr.kind == "Build" then
                local build_capture_info_by_name = {}
                analyze_expr_info(expr.inner, build_capture_info_by_name, rule_name)
                return infer_result_info_from_source_result(expr.result, build_capture_info_by_name, "Build in rule '" .. rule_name .. "'")
            end
            error("FrontendSource.Spec:check(): unknown Expr kind '" .. tostring(expr.kind) .. "'", 2)
        end

        infer_result_info_from_source_result = function(result, capture_info_by_name, where)
            if result.kind == "ReturnEmpty" then
                return { value_kind = "none", is_list = false, nullable = true }
            elseif result.kind == "ReturnCtor" then
                return { value_kind = "node", is_list = false, nullable = false }
            elseif result.kind == "ReturnCapture" then
                local info = capture_info_by_name[S(result.capture_name)]
                if info == nil then
                    error("FrontendSource.Spec:check(): unknown capture '" .. S(result.capture_name) .. "' in " .. where, 2)
                end
                return clone_info(info)
            end
            error("FrontendSource.Spec:check(): unknown Result kind '" .. tostring(result.kind) .. "'", 2)
        end

        local function infer_rule_result_info(rule, capture_info_by_name)
            return infer_result_info_from_source_result(rule.result, capture_info_by_name, "rule '" .. S(rule.name) .. "'")
        end

        local changed = true
        local passes = 0
        while changed and passes < 32 do
            passes = passes + 1
            changed = false
            for i = 1, #spec.parser.rules do
                local rule = spec.parser.rules[i]
                local capture_info_by_name = {}
                analyze_expr_info(rule.expr, capture_info_by_name, S(rule.name))
                local next_info = infer_rule_result_info(rule, capture_info_by_name)
                local name = S(rule.name)
                if not same_info(result_info_by_rule[name], next_info) then
                    result_info_by_rule[name] = next_info
                    changed = true
                end
            end
        end

        for i = 1, #spec.parser.rules do
            local name = S(spec.parser.rules[i].name)
            if result_info_by_rule[name].value_kind == "unknown" then
                error("FrontendSource.Spec:check(): could not resolve result shape for rule '" .. name .. "'", 2)
            end
        end

        local prelim_rules = {}

        for i = 1, #spec.parser.rules do
            local rule = spec.parser.rules[i]
            local rule_name = S(rule.name)
            local header = rule_header_by_name[rule_name]
            local next_slot = 1
            local capture_info_by_name = {}

            local function define_capture(name, info)
                if capture_info_by_name[name] ~= nil then
                    error("FrontendSource.Spec:check(): duplicate capture '" .. name .. "' in rule '" .. rule_name .. "'", 2)
                end
                local capture_header = CT.CaptureHeader(name, next_slot, infer_capture_shape(info))
                next_slot = next_slot + 1
                capture_info_by_name[name] = {
                    header = capture_header,
                    info = clone_info(info),
                }
                return capture_header
            end

            local resolve_result_source
            local lower_result

            local function lower_expr(expr, current_capture_info_by_name, current_define_capture)
                if expr.kind == "TokenRef" then
                    local token_name = S(expr.token_name)
                    local token_header = token_header_by_name[token_name]
                    if token_header == nil then
                        error("FrontendSource.Spec:check(): unknown token ref '" .. token_name .. "' in rule '" .. rule_name .. "'", 2)
                    end
                    return CT.TokenRef(token_header), token_info_from_def(token_def_by_name[token_name])
                elseif expr.kind == "RuleRef" then
                    local ref_name = S(expr.rule_name)
                    local rule_header = rule_header_by_name[ref_name]
                    if rule_header == nil then
                        error("FrontendSource.Spec:check(): unknown rule ref '" .. ref_name .. "' in rule '" .. rule_name .. "'", 2)
                    end
                    return CT.RuleRef(rule_header), clone_info(result_info_by_rule[ref_name])
                elseif expr.kind == "Seq" then
                    local items = {}
                    local infos = {}
                    for j = 1, #expr.items do
                        local item, info = lower_expr(expr.items[j], current_capture_info_by_name, current_define_capture)
                        items[j] = item
                        infos[j] = info
                    end
                    local out = nil
                    local count = 0
                    for j = 1, #infos do
                        local info = infos[j]
                        if info.value_kind ~= "none" or info.is_list then
                            count = count + 1
                            out = clone_info(info)
                        end
                    end
                    if count == 1 then
                        return CT.Seq(items), out
                    end
                    return CT.Seq(items), { value_kind = "none", is_list = false, nullable = false }
                elseif expr.kind == "Choice" then
                    local alts = {}
                    local infos = {}
                    for j = 1, #expr.alts do
                        local alt, info = lower_expr(expr.alts[j], current_capture_info_by_name, current_define_capture)
                        alts[j] = alt
                        infos[j] = info
                    end
                    return CT.Choice(alts), choice_info(infos)
                elseif expr.kind == "Optional" then
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    local out = clone_info(inner_info)
                    out.nullable = true
                    return CT.Optional(inner), out
                elseif expr.kind == "Many" then
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    return CT.Many(inner), {
                        value_kind = inner_info.value_kind,
                        is_list = true,
                        nullable = true,
                    }
                elseif expr.kind == "OneOrMore" then
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    return CT.OneOrMore(inner), {
                        value_kind = inner_info.value_kind,
                        is_list = true,
                        nullable = false,
                    }
                elseif expr.kind == "Capture" then
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    local capture_header = current_define_capture(S(expr.capture_name), inner_info)
                    return CT.Capture(capture_header, inner), inner_info
                elseif expr.kind == "Build" then
                    local build_capture_info_by_name = {}
                    local build_next_slot = 1
                    local function define_build_capture(name, info)
                        if build_capture_info_by_name[name] ~= nil then
                            error("FrontendSource.Spec:check(): duplicate capture '" .. name .. "' in Build of rule '" .. rule_name .. "'", 2)
                        end
                        local capture_header = CT.CaptureHeader(name, build_next_slot, infer_capture_shape(info))
                        build_next_slot = build_next_slot + 1
                        build_capture_info_by_name[name] = {
                            header = capture_header,
                            info = clone_info(info),
                        }
                        return capture_header
                    end
                    local inner = select(1, lower_expr(expr.inner, build_capture_info_by_name, define_build_capture))
                    local checked_build_result = lower_result(expr.result, "Build in rule '" .. rule_name .. "'", build_capture_info_by_name)
                    local build_info_map = {}
                    for name, info in pairs(build_capture_info_by_name) do
                        build_info_map[name] = info.info
                    end
                    local build_info = infer_result_info_from_source_result(expr.result, build_info_map, "Build in rule '" .. rule_name .. "'")
                    return CT.Build(inner, checked_build_result), build_info
                end
                error("FrontendSource.Spec:check(): unknown Expr kind '" .. tostring(expr.kind) .. "'", 2)
            end

            resolve_result_source = function(source, current_capture_info_by_name, where)
                if source.kind == "CaptureSource" then
                    local info = current_capture_info_by_name[S(source.capture_name)]
                    if info == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.CaptureSource(info.header), infer_value_shape_from_info(info.info)
                elseif source.kind == "PresentSource" then
                    local info = current_capture_info_by_name[S(source.capture_name)]
                    if info == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.PresentSource(info.header), CT.BoolValue
                elseif source.kind == "JoinedListSource" then
                    local info = current_capture_info_by_name[S(source.capture_name)]
                    if info == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.JoinedListSource(info.header, S(source.separator)), CT.StringValue
                elseif source.kind == "ConstBoolSource" then
                    return CT.ConstBoolSource(B(source.value)), CT.BoolValue
                end
                error("FrontendSource.Spec:check(): unknown ResultSource kind '" .. tostring(source.kind) .. "'", 2)
            end

            lower_result = function(result, where, current_capture_info_by_name)
                current_capture_info_by_name = current_capture_info_by_name or capture_info_by_name
                if result.kind == "ReturnEmpty" then
                    return CT.ReturnEmpty
                elseif result.kind == "ReturnCapture" then
                    local info = current_capture_info_by_name[S(result.capture_name)]
                    if info == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(result.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.ReturnCapture(info.header)
                elseif result.kind == "ReturnCtor" then
                    local target_fields = {}
                    local checked_fields = {}
                    for j = 1, #result.fields do
                        local field = result.fields[j]
                        local checked_source, expected_shape = resolve_result_source(field.source, current_capture_info_by_name, where)
                        if expected_shape == nil then
                            error("FrontendSource.Spec:check(): could not infer field shape for '" .. S(field.field_name) .. "' in " .. where, 2)
                        end
                        local target_field = CT.TargetField(S(field.field_name), expected_shape)
                        target_fields[j] = target_field
                        checked_fields[j] = CT.FieldResult(target_field, checked_source)
                    end
                    return CT.ReturnCtor(
                        CT.CtorTarget(S(result.ctor_fqname), target_fields),
                        checked_fields
                    )
                end
                error("FrontendSource.Spec:check(): unknown Result kind '" .. tostring(result.kind) .. "'", 2)
            end

            local checked_expr = select(1, lower_expr(rule.expr, capture_info_by_name, define_capture))
            local checked_result = lower_result(rule.result, "rule '" .. rule_name .. "'", capture_info_by_name)

            prelim_rules[i] = CT.Rule(header, checked_expr, checked_result, CT.FirstSet({}, false), false)
        end

        local props = {}
        for i = 1, #prelim_rules do
            local rule = prelim_rules[i]
            props[N(rule.header.rule_id)] = { token_ids = {}, nullable = false }
        end

        local function sorted_unique(ids)
            local seen, out = {}, {}
            for i = 1, #ids do
                local id = N(ids[i])
                if not seen[id] then
                    seen[id] = true
                    out[#out + 1] = id
                end
            end
            table.sort(out)
            return out
        end

        local function union_ids(a, b)
            local out = {}
            for i = 1, #a do out[#out + 1] = N(a[i]) end
            for i = 1, #b do out[#out + 1] = N(b[i]) end
            return sorted_unique(out)
        end

        local function analyze_expr(expr)
            if expr.kind == "TokenRef" then
                return { N(expr.header.token_id) }, false
            elseif expr.kind == "RuleRef" then
                local p = props[N(expr.header.rule_id)]
                return p.token_ids, p.nullable
            elseif expr.kind == "Seq" then
                local ids = {}
                local nullable = true
                for i = 1, #expr.items do
                    local child_ids, child_nullable = analyze_expr(expr.items[i])
                    ids = union_ids(ids, child_ids)
                    if not child_nullable then
                        nullable = false
                        break
                    end
                end
                return ids, nullable
            elseif expr.kind == "Choice" then
                local ids = {}
                local nullable = false
                for i = 1, #expr.alts do
                    local child_ids, child_nullable = analyze_expr(expr.alts[i])
                    ids = union_ids(ids, child_ids)
                    nullable = nullable or child_nullable
                end
                return ids, nullable
            elseif expr.kind == "Optional" then
                local child_ids = analyze_expr(expr.inner)
                return child_ids, true
            elseif expr.kind == "Many" then
                local child_ids = analyze_expr(expr.inner)
                return child_ids, true
            elseif expr.kind == "OneOrMore" then
                return analyze_expr(expr.inner)
            elseif expr.kind == "Capture" then
                return analyze_expr(expr.inner)
            elseif expr.kind == "Build" then
                return analyze_expr(expr.inner)
            end
            error("FrontendSource.Spec:check(): unknown CheckedExpr kind '" .. tostring(expr.kind) .. "'", 2)
        end

        local changed_first = true
        while changed_first do
            changed_first = false
            for i = 1, #prelim_rules do
                local rule = prelim_rules[i]
                local ids, nullable = analyze_expr(rule.expr)
                ids = sorted_unique(ids)
                local p = props[N(rule.header.rule_id)]
                local same_nullable = p.nullable == nullable
                local same_ids = #p.token_ids == #ids
                if same_ids then
                    for j = 1, #ids do
                        if N(p.token_ids[j]) ~= N(ids[j]) then
                            same_ids = false
                            break
                        end
                    end
                end
                if not same_nullable or not same_ids then
                    p.nullable = nullable
                    p.token_ids = ids
                    changed_first = true
                end
            end
        end

        local checked_rules = {}
        for i = 1, #prelim_rules do
            local rule = prelim_rules[i]
            local p = props[N(rule.header.rule_id)]
            checked_rules[i] = CT.Rule(
                rule.header,
                rule.expr,
                rule.result,
                CT.FirstSet(p.token_ids, p.nullable and true or false),
                p.nullable and true or false
            )
        end

        return CT.Spec(
            spec.target,
            CT.Lexer(checked_tokens, checked_skips),
            CT.Parser(entry_rule, checked_rules)
        )
    end)

    function T.FrontendSource.Spec:check()
        return check_impl(self)
    end
end
