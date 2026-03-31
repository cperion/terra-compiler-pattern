local ffi = require("ffi")
local bit = require("bit")

local bor = bit.bor
local band = bit.band
local bnot = bit.bnot
local lshift = bit.lshift

return function(T, U, P)
    local function S(v)
        if type(v) == "cdata" then return ffi.string(v) end
        return tostring(v)
    end

    local function N(v)
        return tonumber(v)
    end

    local CT = T.FrontendChecked
    local ST = T.FrontendSource

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

    local function info(value_kind, is_list, nullable)
        return {
            value_kind = value_kind,
            is_list = is_list and true or false,
            nullable = nullable and true or false,
        }
    end

    local function is_meaningful(i)
        return i.is_list or (i.value_kind ~= "none" and i.value_kind ~= "unit")
    end

    local function value_shape_from_info(i)
        if i == nil then return nil end
        if i.is_list then return ST.ListValue end
        if i.value_kind == "node" then return ST.NodeValue end
        if i.value_kind == "string" then return ST.StringValue end
        if i.value_kind == "bool" then return ST.BoolValue end
        if i.value_kind == "number" then return ST.NumberValue end
        if i.value_kind == "null" then return ST.NullValue end
        if i.value_kind == "bytes" then return ST.BytesValue end
        return ST.UnitValue
    end

    local function infer_capture_slot_shape(i)
        if i.is_list then return CT.ListSlot end
        if i.nullable and (i.value_kind == "none" or i.value_kind == "unit") then
            return CT.PresenceSlot
        end
        return CT.SingleSlot
    end

    local function choice_info(infos)
        local out = nil
        for i = 1, #infos do
            local cur = infos[i]
            if out == nil then
                out = clone_info(cur)
            else
                if out.value_kind ~= cur.value_kind or (out.is_list and true or false) ~= (cur.is_list and true or false) then
                    out.value_kind = "none"
                    out.is_list = false
                end
                out.nullable = out.nullable or cur.nullable
            end
        end
        return out or info("none", false, false)
    end

    local function build_byteset_lookup(byteset, lookup)
        lookup = lookup or {}
        local kind = byteset.kind
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
        if kind == "ByteLiteral" then
            local value = N(byteset.value)
            if value < 0 or value > 255 then
                error("FrontendSource.Spec:check(): ByteLiteral out of range", 2)
            end
            lookup[value] = true
            return lookup
        end
        if kind == "ByteRange" then
            local lo = N(byteset.lo)
            local hi = N(byteset.hi)
            if lo < 0 or hi > 255 or lo > hi then
                error("FrontendSource.Spec:check(): invalid ByteRange", 2)
            end
            for c = lo, hi do lookup[c] = true end
            return lookup
        end
        if kind == "Union" then
            for i = 1, #byteset.parts do
                build_byteset_lookup(byteset.parts[i], lookup)
            end
            return lookup
        end
        if kind == "Except" then
            local tmp = {}
            build_byteset_lookup(byteset.base, tmp)
            local remove = {}
            build_byteset_lookup(byteset.remove, remove)
            for c = 0, 255 do
                if tmp[c] and not remove[c] then lookup[c] = true end
            end
            return lookup
        end
        error("FrontendSource.Spec:check(): unknown ByteSet kind '" .. tostring(kind) .. "'", 2)
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

    local function checked_byteset(byteset)
        return CT.CheckedByteSet(lookup_to_words(build_byteset_lookup(byteset)))
    end

    local function token_payload_shape(token_kind)
        local kind = token_kind.kind
        if kind == "FixedToken" then return CT.NoTokenPayload end
        if kind == "IdentToken" then return CT.StringPayload end
        if kind == "QuotedStringToken" then return CT.StringPayload end
        if kind == "NumberToken" then return CT.NumberPayload end
        if kind == "ByteRunToken" then return CT.BytesPayload end
        error("FrontendSource.Spec:check(): unknown TokenKind '" .. tostring(kind) .. "'", 2)
    end

    local function token_value_info(token_kind)
        local kind = token_kind.kind
        if kind == "FixedToken" then return info("none", false, false) end
        if kind == "IdentToken" then return info("string", false, false) end
        if kind == "QuotedStringToken" then return info("string", false, false) end
        if kind == "NumberToken" then return info("number", false, false) end
        if kind == "ByteRunToken" then return info("bytes", false, false) end
        error("FrontendSource.Spec:check(): unknown TokenKind '" .. tostring(kind) .. "'", 2)
    end

    local check_impl = U.transition(function(spec)
        local frontend = spec.frontend
        local grammar = frontend.grammar

        local token_header_by_name = {}
        local token_kind_by_name = {}
        local checked_tokens = {}

        for i = 1, #grammar.tokens do
            local token = grammar.tokens[i]
            local id = N(token.id)
            local name = S(token.name)
            if token_header_by_name[name] ~= nil then
                error("FrontendSource.Spec:check(): duplicate token name '" .. name .. "'", 2)
            end
            token_header_by_name[name] = CT.TokenHeader(id, name, token_payload_shape(token.kind))
            token_kind_by_name[name] = token.kind
        end

        for i = 1, #grammar.tokens do
            local token = grammar.tokens[i]
            local header = token_header_by_name[S(token.name)]
            local kind = token.kind
            local checked_kind
            if kind.kind == "FixedToken" then
                checked_kind = CT.FixedToken(S(kind.text), kind.boundary_policy)
            elseif kind.kind == "IdentToken" then
                checked_kind = CT.IdentToken(checked_byteset(kind.start_set), checked_byteset(kind.continue_set))
            elseif kind.kind == "QuotedStringToken" then
                local quote_char = S(kind.format.quote_char)
                if #quote_char ~= 1 then
                    error("FrontendSource.Spec:check(): QuotedStringToken requires a one-byte quote_char", 2)
                end
                checked_kind = CT.QuotedStringToken(kind.format)
            elseif kind.kind == "NumberToken" then
                checked_kind = CT.NumberToken(kind.format)
            elseif kind.kind == "ByteRunToken" then
                checked_kind = CT.ByteRunToken(checked_byteset(kind.allowed_set), kind.cardinality)
            else
                error("FrontendSource.Spec:check(): unknown TokenKind '" .. tostring(kind.kind) .. "'", 2)
            end
            checked_tokens[i] = CT.Token(header, checked_kind)
        end

        local checked_skips = {}
        for i = 1, #grammar.skips do
            local skip = grammar.skips[i]
            if skip.kind == "WhitespaceSkip" then
                checked_skips[i] = CT.WhitespaceSkip
            elseif skip.kind == "LineCommentSkip" then
                checked_skips[i] = CT.LineCommentSkip(S(skip.opener))
            elseif skip.kind == "BlockCommentSkip" then
                checked_skips[i] = CT.BlockCommentSkip(S(skip.opener), S(skip.closer))
            elseif skip.kind == "ByteSkip" then
                checked_skips[i] = CT.ByteSkip(checked_byteset(skip.set))
            else
                error("FrontendSource.Spec:check(): unknown SkipRule kind '" .. tostring(skip.kind) .. "'", 2)
            end
        end

        local constructor_header_by_name = {}
        local constructor_by_name = {}
        local checked_constructors = {}
        for i = 1, #frontend.constructors do
            local ctor = frontend.constructors[i]
            local id = N(ctor.id)
            local name = S(ctor.name)
            if constructor_header_by_name[name] ~= nil then
                error("FrontendSource.Spec:check(): duplicate constructor name '" .. name .. "'", 2)
            end
            local seen_fields = {}
            for j = 1, #ctor.fields do
                local field_name = S(ctor.fields[j].name)
                if seen_fields[field_name] then
                    error("FrontendSource.Spec:check(): duplicate field '" .. field_name .. "' in constructor '" .. name .. "'", 2)
                end
                seen_fields[field_name] = true
            end
            local header = CT.ConstructorHeader(id, name)
            constructor_header_by_name[name] = header
            constructor_by_name[name] = ctor
            checked_constructors[i] = CT.Constructor(header, ctor.fields)
        end

        local rule_header_by_name = {}
        local source_rule_by_name = {}
        for i = 1, #grammar.rules do
            local rule = grammar.rules[i]
            local id = N(rule.id)
            local name = S(rule.name)
            if rule_header_by_name[name] ~= nil then
                error("FrontendSource.Spec:check(): duplicate rule name '" .. name .. "'", 2)
            end
            rule_header_by_name[name] = CT.RuleHeader(id, name, rule.mode)
            source_rule_by_name[name] = rule
        end

        local product_header_by_id = {}
        local checked_products = {}
        for i = 1, #frontend.products do
            local product = frontend.products[i]
            local id = N(product.id)
            local name = S(product.name)
            if product_header_by_id[id] ~= nil then
                error("FrontendSource.Spec:check(): duplicate product id '" .. tostring(id) .. "'", 2)
            end
            local entry_rule = rule_header_by_name[S(product.entry_rule_name)]
            if entry_rule == nil then
                error("FrontendSource.Spec:check(): unknown entry rule '" .. S(product.entry_rule_name) .. "' in product '" .. name .. "'", 2)
            end
            local header = CT.ProductHeader(id, name)
            product_header_by_id[id] = header
            checked_products[i] = CT.Product(header, entry_rule, product.kind, product.source_refs)
        end

        local checked_bindings = {}
        for i = 1, #spec.package.bindings do
            local binding = spec.package.bindings[i]
            local product = product_header_by_id[N(binding.product_id)]
            if product == nil then
                error("FrontendSource.Spec:check(): unknown product id '" .. tostring(N(binding.product_id)) .. "' in binding", 2)
            end
            local checked_binding_kind
            if binding.kind.kind == "TokenizedBinding" then
                checked_binding_kind = CT.TokenizedBinding(
                    binding.kind.scan,
                    binding.kind.parse,
                    binding.kind.token_runtime,
                    binding.kind.output
                )
            elseif binding.kind.kind == "DirectBinding" then
                checked_binding_kind = CT.DirectBinding(
                    binding.kind.parse,
                    binding.kind.output
                )
            else
                error("FrontendSource.Spec:check(): unknown BindingKind '" .. tostring(binding.kind.kind) .. "'", 2)
            end
            checked_bindings[i] = CT.Binding(CT.BindingHeader(N(binding.id)), product, checked_binding_kind)
        end

        local result_info_by_rule = {}
        for i = 1, #grammar.rules do
            result_info_by_rule[S(grammar.rules[i].name)] = info("unknown", false, false)
        end

        local infer_result_info_from_result
        local infer_scalar_info

        local function analyze_expr_info(expr, capture_info_by_name, rule_name)
            if expr.kind == "TokenRef" then
                local name = S(expr.token_name)
                local token_kind = token_kind_by_name[name]
                if token_kind == nil then
                    error("FrontendSource.Spec:check(): unknown token ref '" .. name .. "' in rule '" .. rule_name .. "'", 2)
                end
                return token_value_info(token_kind)
            elseif expr.kind == "RuleRef" then
                local name = S(expr.rule_name)
                if rule_header_by_name[name] == nil then
                    error("FrontendSource.Spec:check(): unknown rule ref '" .. name .. "' in rule '" .. rule_name .. "'", 2)
                end
                return clone_info(result_info_by_rule[name])
            elseif expr.kind == "Seq" then
                local infos = {}
                for i = 1, #expr.items do
                    infos[i] = analyze_expr_info(expr.items[i], capture_info_by_name, rule_name)
                end
                local out = nil
                local count = 0
                for i = 1, #infos do
                    if is_meaningful(infos[i]) then
                        count = count + 1
                        out = clone_info(infos[i])
                    end
                end
                if count == 1 then return out end
                return info("none", false, false)
            elseif expr.kind == "Choice" then
                local infos = {}
                for i = 1, #expr.alts do
                    infos[i] = analyze_expr_info(expr.alts[i], capture_info_by_name, rule_name)
                end
                return choice_info(infos)
            elseif expr.kind == "Optional" then
                local out = clone_info(analyze_expr_info(expr.inner, capture_info_by_name, rule_name))
                out.nullable = true
                return out
            elseif expr.kind == "Many" then
                local inner = analyze_expr_info(expr.inner, capture_info_by_name, rule_name)
                return info(inner.value_kind, true, true)
            elseif expr.kind == "OneOrMore" then
                local inner = analyze_expr_info(expr.inner, capture_info_by_name, rule_name)
                return info(inner.value_kind, true, inner.nullable)
            elseif expr.kind == "Capture" then
                local capture_name = S(expr.capture_name)
                if capture_info_by_name[capture_name] ~= nil then
                    error("FrontendSource.Spec:check(): duplicate capture '" .. capture_name .. "' in rule '" .. rule_name .. "'", 2)
                end
                local inner = analyze_expr_info(expr.inner, capture_info_by_name, rule_name)
                capture_info_by_name[capture_name] = clone_info(inner)
                return inner
            elseif expr.kind == "Build" then
                local build_capture_info_by_name = {}
                analyze_expr_info(expr.inner, build_capture_info_by_name, rule_name)
                return infer_result_info_from_result(expr.result, build_capture_info_by_name, "Build in rule '" .. rule_name .. "'")
            elseif expr.kind == "Delimited" then
                local open_name = S(expr.open_token_name)
                local close_name = S(expr.close_token_name)
                if token_kind_by_name[open_name] == nil then
                    error("FrontendSource.Spec:check(): unknown open token '" .. open_name .. "' in rule '" .. rule_name .. "'", 2)
                end
                if token_kind_by_name[close_name] == nil then
                    error("FrontendSource.Spec:check(): unknown close token '" .. close_name .. "' in rule '" .. rule_name .. "'", 2)
                end
                return analyze_expr_info(expr.inner, capture_info_by_name, rule_name)
            elseif expr.kind == "SeparatedList" then
                if token_kind_by_name[S(expr.separator_token_name)] == nil then
                    error("FrontendSource.Spec:check(): unknown separator token '" .. S(expr.separator_token_name) .. "' in rule '" .. rule_name .. "'", 2)
                end
                local inner = analyze_expr_info(expr.item, capture_info_by_name, rule_name)
                return info(inner.value_kind, true, expr.cardinality.kind == "ZeroOrMore")
            elseif expr.kind == "Precedence" then
                local atom = analyze_expr_info(expr.atom, capture_info_by_name, rule_name)
                for i = 1, #expr.tiers do
                    local tier = expr.tiers[i]
                    for j = 1, #tier.cases do
                        local token_name = S(tier.cases[j].token_name)
                        if token_kind_by_name[token_name] == nil then
                            error("FrontendSource.Spec:check(): unknown precedence token '" .. token_name .. "' in rule '" .. rule_name .. "'", 2)
                        end
                    end
                end
                return atom
            end
            error("FrontendSource.Spec:check(): unknown Expr kind '" .. tostring(expr.kind) .. "'", 2)
        end

        infer_scalar_info = function(source, capture_info_by_name, where)
            if source.kind == "CaptureScalar" then
                local info0 = capture_info_by_name[S(source.capture_name)]
                if info0 == nil then
                    error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                end
                if info0.is_list then
                    error("FrontendSource.Spec:check(): capture scalar source requires non-list capture in " .. where, 2)
                end
                return clone_info(info0)
            elseif source.kind == "ConstString" then
                return info("string", false, false)
            elseif source.kind == "ConstBool" then
                return info("bool", false, false)
            elseif source.kind == "ConstNull" then
                return info("null", false, false)
            elseif source.kind == "DecodeNumber" then
                local info0 = capture_info_by_name[S(source.capture_name)]
                if info0 == nil then
                    error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                end
                return info("number", false, false)
            end
            error("FrontendSource.Spec:check(): unknown ScalarSource kind '" .. tostring(source.kind) .. "'", 2)
        end

        infer_result_info_from_result = function(result, capture_info_by_name, where)
            if result.kind == "ReturnEmpty" then
                return info("unit", false, false)
            elseif result.kind == "ReturnCtor" then
                local ctor_name = S(result.ctor_name)
                if constructor_header_by_name[ctor_name] == nil then
                    error("FrontendSource.Spec:check(): unknown constructor '" .. ctor_name .. "' in " .. where, 2)
                end
                return info("node", false, false)
            elseif result.kind == "ReturnCapture" then
                local out = capture_info_by_name[S(result.capture_name)]
                if out == nil then
                    error("FrontendSource.Spec:check(): unknown capture '" .. S(result.capture_name) .. "' in " .. where, 2)
                end
                return clone_info(out)
            elseif result.kind == "ReturnList" then
                local out = capture_info_by_name[S(result.capture_name)]
                if out == nil then
                    error("FrontendSource.Spec:check(): unknown capture '" .. S(result.capture_name) .. "' in " .. where, 2)
                end
                if not out.is_list then
                    error("FrontendSource.Spec:check(): ReturnList requires list capture in " .. where, 2)
                end
                return clone_info(out)
            elseif result.kind == "ReturnScalar" then
                return infer_scalar_info(result.source, capture_info_by_name, where)
            end
            error("FrontendSource.Spec:check(): unknown Result kind '" .. tostring(result.kind) .. "'", 2)
        end

        local changed = true
        local passes = 0
        while changed and passes < 64 do
            changed = false
            passes = passes + 1
            for i = 1, #grammar.rules do
                local rule = grammar.rules[i]
                local capture_info_by_name = {}
                analyze_expr_info(rule.expr, capture_info_by_name, S(rule.name))
                local next_info = infer_result_info_from_result(rule.result, capture_info_by_name, "rule '" .. S(rule.name) .. "'")
                local name = S(rule.name)
                if not same_info(result_info_by_rule[name], next_info) then
                    result_info_by_rule[name] = next_info
                    changed = true
                end
            end
        end

        for i = 1, #grammar.rules do
            local name = S(grammar.rules[i].name)
            if result_info_by_rule[name].value_kind == "unknown" then
                error("FrontendSource.Spec:check(): could not resolve result shape for rule '" .. name .. "'", 2)
            end
        end

        local prelim_rules = {}

        for i = 1, #grammar.rules do
            local rule = grammar.rules[i]
            local rule_name = S(rule.name)
            local header = rule_header_by_name[rule_name]
            local next_slot = 1
            local capture_info_by_name = {}

            local function define_capture(name, capture_info)
                if capture_info_by_name[name] ~= nil then
                    error("FrontendSource.Spec:check(): duplicate capture '" .. name .. "' in rule '" .. rule_name .. "'", 2)
                end
                local capture_header = CT.CaptureHeader(
                    name,
                    next_slot,
                    infer_capture_slot_shape(capture_info),
                    value_shape_from_info(capture_info)
                )
                next_slot = next_slot + 1
                capture_info_by_name[name] = {
                    header = capture_header,
                    info = clone_info(capture_info),
                }
                return capture_header
            end

            local lower_result
            local lower_result_source
            local lower_scalar_source

            local function lower_expr(expr, current_capture_info_by_name, current_define_capture)
                if expr.kind == "TokenRef" then
                    local token_name = S(expr.token_name)
                    local header0 = token_header_by_name[token_name]
                    if header0 == nil then
                        error("FrontendSource.Spec:check(): unknown token ref '" .. token_name .. "' in rule '" .. rule_name .. "'", 2)
                    end
                    return CT.TokenRef(header0), token_value_info(token_kind_by_name[token_name])
                elseif expr.kind == "RuleRef" then
                    local ref_name = S(expr.rule_name)
                    local header0 = rule_header_by_name[ref_name]
                    if header0 == nil then
                        error("FrontendSource.Spec:check(): unknown rule ref '" .. ref_name .. "' in rule '" .. rule_name .. "'", 2)
                    end
                    return CT.RuleRef(header0), clone_info(result_info_by_rule[ref_name])
                elseif expr.kind == "Seq" then
                    local items = {}
                    local infos = {}
                    for j = 1, #expr.items do
                        items[j], infos[j] = lower_expr(expr.items[j], current_capture_info_by_name, current_define_capture)
                    end
                    local out = nil
                    local count = 0
                    for j = 1, #infos do
                        if is_meaningful(infos[j]) then
                            count = count + 1
                            out = clone_info(infos[j])
                        end
                    end
                    if count == 1 then return CT.Seq(items), out end
                    return CT.Seq(items), info("none", false, false)
                elseif expr.kind == "Choice" then
                    local alts = {}
                    local infos = {}
                    for j = 1, #expr.alts do
                        alts[j], infos[j] = lower_expr(expr.alts[j], current_capture_info_by_name, current_define_capture)
                    end
                    return CT.Choice(alts), choice_info(infos)
                elseif expr.kind == "Optional" then
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    local out = clone_info(inner_info)
                    out.nullable = true
                    return CT.Optional(inner), out
                elseif expr.kind == "Many" then
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    return CT.Many(inner), info(inner_info.value_kind, true, true)
                elseif expr.kind == "OneOrMore" then
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    return CT.OneOrMore(inner), info(inner_info.value_kind, true, inner_info.nullable)
                elseif expr.kind == "Capture" then
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    local capture_header = current_define_capture(S(expr.capture_name), inner_info)
                    return CT.Capture(capture_header, inner), inner_info
                elseif expr.kind == "Build" then
                    local build_capture_info_by_name = {}
                    local build_next_slot = 1
                    local function define_build_capture(name, capture_info)
                        if build_capture_info_by_name[name] ~= nil then
                            error("FrontendSource.Spec:check(): duplicate capture '" .. name .. "' in Build of rule '" .. rule_name .. "'", 2)
                        end
                        local capture_header = CT.CaptureHeader(
                            name,
                            build_next_slot,
                            infer_capture_slot_shape(capture_info),
                            value_shape_from_info(capture_info)
                        )
                        build_next_slot = build_next_slot + 1
                        build_capture_info_by_name[name] = {
                            header = capture_header,
                            info = clone_info(capture_info),
                        }
                        return capture_header
                    end
                    local inner = select(1, lower_expr(expr.inner, build_capture_info_by_name, define_build_capture))
                    local checked_build_result = lower_result(expr.result, "Build in rule '" .. rule_name .. "'", build_capture_info_by_name)
                    local build_info_map = {}
                    for name, rec in pairs(build_capture_info_by_name) do
                        build_info_map[name] = rec.info
                    end
                    local build_info = infer_result_info_from_result(expr.result, build_info_map, "Build in rule '" .. rule_name .. "'")
                    return CT.Build(inner, checked_build_result), build_info
                elseif expr.kind == "Delimited" then
                    local open_header = token_header_by_name[S(expr.open_token_name)]
                    local close_header = token_header_by_name[S(expr.close_token_name)]
                    if open_header == nil or close_header == nil then
                        error("FrontendSource.Spec:check(): unknown delimited token in rule '" .. rule_name .. "'", 2)
                    end
                    local inner, inner_info = lower_expr(expr.inner, current_capture_info_by_name, current_define_capture)
                    return CT.Delimited(open_header, inner, close_header), inner_info
                elseif expr.kind == "SeparatedList" then
                    local sep_header = token_header_by_name[S(expr.separator_token_name)]
                    if sep_header == nil then
                        error("FrontendSource.Spec:check(): unknown separator token '" .. S(expr.separator_token_name) .. "' in rule '" .. rule_name .. "'", 2)
                    end
                    local item, item_info = lower_expr(expr.item, current_capture_info_by_name, current_define_capture)
                    return CT.SeparatedList(item, sep_header, expr.cardinality, expr.trailing_policy), info(item_info.value_kind, true, expr.cardinality.kind == "ZeroOrMore")
                elseif expr.kind == "Precedence" then
                    local atom, atom_info = lower_expr(expr.atom, current_capture_info_by_name, current_define_capture)
                    local tiers = {}
                    for ti = 1, #expr.tiers do
                        local tier = expr.tiers[ti]
                        local cases = {}
                        for ci = 1, #tier.cases do
                            local case = tier.cases[ci]
                            local token_header = token_header_by_name[S(case.token_name)]
                            if token_header == nil then
                                error("FrontendSource.Spec:check(): unknown precedence token '" .. S(case.token_name) .. "' in rule '" .. rule_name .. "'", 2)
                            end
                            cases[ci] = CT.CheckedOperatorCase(token_header, lower_result(case.result, "precedence case in rule '" .. rule_name .. "'", current_capture_info_by_name))
                        end
                        tiers[ti] = CT.CheckedOperatorTier(tier.associativity, cases)
                    end
                    return CT.Precedence(atom, tiers), atom_info
                end
                error("FrontendSource.Spec:check(): unknown Expr kind '" .. tostring(expr.kind) .. "'", 2)
            end

            lower_scalar_source = function(source, current_capture_info_by_name, where)
                if source.kind == "CaptureScalar" then
                    local rec = current_capture_info_by_name[S(source.capture_name)]
                    if rec == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                    end
                    if rec.info.is_list then
                        error("FrontendSource.Spec:check(): CaptureScalar requires non-list capture in " .. where, 2)
                    end
                    return CT.CaptureScalar(rec.header), value_shape_from_info(rec.info)
                elseif source.kind == "ConstString" then
                    return CT.ConstString(S(source.value)), ST.StringValue
                elseif source.kind == "ConstBool" then
                    return CT.ConstBool(source.value == true), ST.BoolValue
                elseif source.kind == "ConstNull" then
                    return CT.ConstNull, ST.NullValue
                elseif source.kind == "DecodeNumber" then
                    local rec = current_capture_info_by_name[S(source.capture_name)]
                    if rec == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.DecodeNumber(rec.header, source.mode), ST.NumberValue
                end
                error("FrontendSource.Spec:check(): unknown ScalarSource kind '" .. tostring(source.kind) .. "'", 2)
            end

            lower_result_source = function(source, current_capture_info_by_name, where)
                if source.kind == "CaptureSource" then
                    local rec = current_capture_info_by_name[S(source.capture_name)]
                    if rec == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.CaptureSource(rec.header), value_shape_from_info(rec.info)
                elseif source.kind == "PresentSource" then
                    local rec = current_capture_info_by_name[S(source.capture_name)]
                    if rec == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.PresentSource(rec.header), ST.BoolValue
                elseif source.kind == "JoinedListSource" then
                    local rec = current_capture_info_by_name[S(source.capture_name)]
                    if rec == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(source.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.JoinedListSource(rec.header, S(source.separator)), ST.StringValue
                elseif source.kind == "ScalarResultSource" then
                    local scalar, shape = lower_scalar_source(source.scalar, current_capture_info_by_name, where)
                    return CT.ScalarResultSource(scalar), shape
                end
                error("FrontendSource.Spec:check(): unknown ResultSource kind '" .. tostring(source.kind) .. "'", 2)
            end

            lower_result = function(result, where, current_capture_info_by_name)
                current_capture_info_by_name = current_capture_info_by_name or capture_info_by_name
                if result.kind == "ReturnEmpty" then
                    return CT.ReturnEmpty
                elseif result.kind == "ReturnCapture" then
                    local rec = current_capture_info_by_name[S(result.capture_name)]
                    if rec == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(result.capture_name) .. "' in " .. where, 2)
                    end
                    return CT.ReturnCapture(rec.header)
                elseif result.kind == "ReturnList" then
                    local rec = current_capture_info_by_name[S(result.capture_name)]
                    if rec == nil then
                        error("FrontendSource.Spec:check(): unknown capture '" .. S(result.capture_name) .. "' in " .. where, 2)
                    end
                    if not rec.info.is_list then
                        error("FrontendSource.Spec:check(): ReturnList requires list capture in " .. where, 2)
                    end
                    return CT.ReturnList(rec.header)
                elseif result.kind == "ReturnScalar" then
                    return CT.ReturnScalar(select(1, lower_scalar_source(result.source, current_capture_info_by_name, where)))
                elseif result.kind == "ReturnCtor" then
                    local ctor_name = S(result.ctor_name)
                    local ctor_header = constructor_header_by_name[ctor_name]
                    local ctor = constructor_by_name[ctor_name]
                    if ctor_header == nil then
                        error("FrontendSource.Spec:check(): unknown constructor '" .. ctor_name .. "' in " .. where, 2)
                    end
                    local source_by_field = {}
                    for j = 1, #result.fields do
                        local field_result = result.fields[j]
                        local field_name = S(field_result.field_name)
                        if source_by_field[field_name] ~= nil then
                            error("FrontendSource.Spec:check(): duplicate result field '" .. field_name .. "' in " .. where, 2)
                        end
                        source_by_field[field_name] = field_result.source
                    end
                    local checked_fields = {}
                    for j = 1, #ctor.fields do
                        local field = ctor.fields[j]
                        local field_name = S(field.name)
                        local source0 = source_by_field[field_name]
                        if source0 == nil then
                            error("FrontendSource.Spec:check(): missing result field '" .. field_name .. "' in " .. where, 2)
                        end
                        local checked_source, actual_shape = lower_result_source(source0, current_capture_info_by_name, where)
                        if field.shape.kind ~= actual_shape.kind then
                            error("FrontendSource.Spec:check(): field shape mismatch for '" .. field_name .. "' in " .. where .. ": expected " .. tostring(field.shape.kind) .. ", got " .. tostring(actual_shape.kind), 2)
                        end
                        checked_fields[j] = CT.FieldResult(field, checked_source)
                    end
                    for field_name, _ in pairs(source_by_field) do
                        local found = false
                        for j = 1, #ctor.fields do
                            if S(ctor.fields[j].name) == field_name then
                                found = true
                                break
                            end
                        end
                        if not found then
                            error("FrontendSource.Spec:check(): unknown result field '" .. field_name .. "' in " .. where, 2)
                        end
                    end
                    return CT.ReturnCtor(ctor_header, checked_fields)
                end
                error("FrontendSource.Spec:check(): unknown Result kind '" .. tostring(result.kind) .. "'", 2)
            end

            local checked_expr, expr_info = lower_expr(rule.expr, capture_info_by_name, define_capture)
            local checked_result = lower_result(rule.result, "rule '" .. rule_name .. "'", capture_info_by_name)

            prelim_rules[i] = CT.Rule(
                header,
                checked_expr,
                checked_result,
                CT.FirstSet({}, false),
                false,
                value_shape_from_info(infer_result_info_from_result(rule.result, (function()
                    local out = {}
                    for name, rec in pairs(capture_info_by_name) do out[name] = rec.info end
                    return out
                end)(), "rule '" .. rule_name .. "'"))
            )
        end

        local props = {}
        for i = 1, #prelim_rules do
            local rule = prelim_rules[i]
            props[N(rule.header.id)] = { token_ids = {}, nullable = false }
        end

        local function sorted_unique(ids)
            local seen, out = {}, {}
            for i = 1, #ids do
                local id = N(ids[i])
                if id ~= nil and not seen[id] then
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

        local function analyze_checked_expr(expr)
            if expr.kind == "TokenRef" then
                return { N(expr.header.id) }, false
            elseif expr.kind == "RuleRef" then
                local p = props[N(expr.header.id)]
                return p.token_ids, p.nullable
            elseif expr.kind == "Seq" then
                local ids = {}
                local nullable = true
                for i = 1, #expr.items do
                    local child_ids, child_nullable = analyze_checked_expr(expr.items[i])
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
                    local child_ids, child_nullable = analyze_checked_expr(expr.alts[i])
                    ids = union_ids(ids, child_ids)
                    nullable = nullable or child_nullable
                end
                return ids, nullable
            elseif expr.kind == "Optional" then
                local child_ids = select(1, analyze_checked_expr(expr.inner))
                return child_ids, true
            elseif expr.kind == "Many" then
                local child_ids = select(1, analyze_checked_expr(expr.inner))
                return child_ids, true
            elseif expr.kind == "OneOrMore" then
                return analyze_checked_expr(expr.inner)
            elseif expr.kind == "Capture" then
                return analyze_checked_expr(expr.inner)
            elseif expr.kind == "Build" then
                return analyze_checked_expr(expr.inner)
            elseif expr.kind == "Delimited" then
                return { N(expr.open_header.id) }, false
            elseif expr.kind == "SeparatedList" then
                local item_ids, item_nullable = analyze_checked_expr(expr.item)
                return item_ids, expr.cardinality.kind == "ZeroOrMore" or item_nullable
            elseif expr.kind == "Precedence" then
                return analyze_checked_expr(expr.atom)
            end
            error("FrontendSource.Spec:check(): unknown CheckedExpr kind '" .. tostring(expr.kind) .. "'", 2)
        end

        local changed_first = true
        while changed_first do
            changed_first = false
            for i = 1, #prelim_rules do
                local rule = prelim_rules[i]
                local ids, nullable = analyze_checked_expr(rule.expr)
                ids = sorted_unique(ids)
                local p = props[N(rule.header.id)]
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
            local p = props[N(rule.header.id)]
            checked_rules[i] = CT.Rule(
                rule.header,
                rule.expr,
                rule.result,
                CT.FirstSet(p.token_ids, p.nullable and true or false),
                p.nullable and true or false,
                rule.value_shape
            )
        end

        return CT.Spec(
            CT.Frontend(
                CT.Grammar(grammar.input, grammar.trivia_policy, checked_skips, checked_tokens, checked_rules),
                checked_constructors,
                checked_products
            ),
            CT.Package(checked_bindings),
            spec.diagnostics
        )
    end)

    function T.FrontendSource.Spec:check()
        return check_impl(self)
    end
end
