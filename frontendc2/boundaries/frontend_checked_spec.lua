local ffi = require("ffi")
local bit = require("bit")

local bor = bit.bor
local band = bit.band
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

    local LT = T.FrontendLowered

    local function words_from_lookup(lookup)
        local words = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for c = 0, 255 do
            if lookup[c] then
                local wi = math.floor(c / 32) + 1
                words[wi] = bor(words[wi], lshift(1, c % 32))
            end
        end
        return words
    end

    local function word_set_from_token_ids(token_ids)
        local words = { 0, 0, 0, 0, 0, 0, 0, 0 }
        for i = 1, #token_ids do
            local id = N(token_ids[i])
            local wi = math.floor(id / 32) + 1
            words[wi] = bor(words[wi], lshift(1, id % 32))
        end
        return words
    end

    local lower_impl = U.transition(function(spec)
        local token_by_id = {}
        local token_by_name = {}
        local rule_by_id = {}
        local product_by_id = {}

        for i = 1, #spec.frontend.grammar.tokens do
            local tok = spec.frontend.grammar.tokens[i]
            token_by_id[N(tok.header.id)] = tok
            token_by_name[S(tok.header.name)] = tok
        end
        for i = 1, #spec.frontend.grammar.rules do
            local rule = spec.frontend.grammar.rules[i]
            rule_by_id[N(rule.header.id)] = rule
        end
        for i = 1, #spec.frontend.products do
            local product = spec.frontend.products[i]
            product_by_id[N(product.header.id)] = product
        end

        local all_direct = true
        for i = 1, #spec.package.bindings do
            if spec.package.bindings[i].kind.kind ~= "DirectBinding" then
                all_direct = false
                break
            end
        end
        if not all_direct then
            error("FrontendChecked.Spec:lower(): tokenized lowering not implemented yet in frontendc2", 2)
        end

        local function token_start_lookup(token)
            local lookup = {}
            local kind = token.kind.kind
            if kind == "FixedToken" then
                local text = S(token.kind.text)
                if #text == 0 then
                    error("FrontendChecked.Spec:lower(): FixedToken requires non-empty text", 2)
                end
                lookup[byte(text, 1)] = true
                return lookup
            elseif kind == "IdentToken" then
                local words = token.kind.start_set.bitset_words
                for c = 0, 255 do
                    local wi = math.floor(c / 32) + 1
                    if band(N(words[wi] or 0), lshift(1, c % 32)) ~= 0 then lookup[c] = true end
                end
                return lookup
            elseif kind == "QuotedStringToken" then
                local quote_char = S(token.kind.format.quote_char)
                if #quote_char ~= 1 then
                    error("FrontendChecked.Spec:lower(): QuotedStringToken requires one-byte quote_char", 2)
                end
                lookup[byte(quote_char, 1)] = true
                return lookup
            elseif kind == "NumberToken" then
                local fmt = token.kind.format
                for c = 48, 57 do lookup[c] = true end
                if fmt.allow_sign == true or N(fmt.allow_sign) == 1 then lookup[45] = true end
                return lookup
            elseif kind == "ByteRunToken" then
                local words = token.kind.allowed_set.bitset_words
                for c = 0, 255 do
                    local wi = math.floor(c / 32) + 1
                    if band(N(words[wi] or 0), lshift(1, c % 32)) ~= 0 then lookup[c] = true end
                end
                return lookup
            end
            error("FrontendChecked.Spec:lower(): unknown token kind '" .. tostring(kind) .. "'", 2)
        end

        local token_start_lookup_by_id = {}
        for _, token in pairs(token_by_id) do
            token_start_lookup_by_id[N(token.header.id)] = token_start_lookup(token)
        end

        local byte_class_lookup = {}
        for c = 0, 255 do byte_class_lookup[c] = 0 end

        local lowered_skips = {}
        for i = 1, #spec.frontend.grammar.skips do
            local skip = spec.frontend.grammar.skips[i]
            if skip.kind == "WhitespaceSkip" then
                lowered_skips[i] = LT.WhitespaceSkip
                for _, c in ipairs({ 9, 10, 13, 32 }) do
                    byte_class_lookup[c] = bor(byte_class_lookup[c], 1)
                end
            elseif skip.kind == "LineCommentSkip" then
                lowered_skips[i] = LT.LineCommentSkip(S(skip.opener))
            elseif skip.kind == "BlockCommentSkip" then
                lowered_skips[i] = LT.BlockCommentSkip(S(skip.opener), S(skip.closer))
            elseif skip.kind == "ByteSkip" then
                lowered_skips[i] = LT.ByteSkip(skip.set.bitset_words)
                local words = skip.set.bitset_words
                for c = 0, 255 do
                    local wi = math.floor(c / 32) + 1
                    if band(N(words[wi] or 0), lshift(1, c % 32)) ~= 0 then
                        byte_class_lookup[c] = bor(byte_class_lookup[c], 1)
                    end
                end
            else
                error("FrontendChecked.Spec:lower(): unknown skip kind '" .. tostring(skip.kind) .. "'", 2)
            end
        end

        local keyword_cases_by_first = {}
        local string_plans = {}
        local string_id_by_token_id = {}
        local number_plans = {}
        local number_id_by_token_id = {}

        for i = 1, #spec.frontend.grammar.tokens do
            local token = spec.frontend.grammar.tokens[i]
            local token_id = N(token.header.id)
            local kind = token.kind.kind
            if kind == "FixedToken" then
                local text = S(token.kind.text)
                local first = byte(text, 1)
                if first ~= nil and text:match("^[A-Za-z_]") then
                    local cases = keyword_cases_by_first[first]
                    if cases == nil then
                        cases = {}
                        keyword_cases_by_first[first] = cases
                    end
                    local keyword_kind
                    if text == "true" then keyword_kind = LT.TrueKeyword
                    elseif text == "false" then keyword_kind = LT.FalseKeyword
                    elseif text == "null" then keyword_kind = LT.NullKeyword
                    else keyword_kind = LT.FixedWordKeyword(token.header) end
                    cases[#cases + 1] = LT.StructuralWordCase(text, keyword_kind)
                end
                byte_class_lookup[first] = bor(byte_class_lookup[first] or 0, 2)
            elseif kind == "QuotedStringToken" then
                local string_id = #string_plans + 1
                string_id_by_token_id[token_id] = string_id
                string_plans[string_id] = LT.StructuralStringPlan(string_id, token.kind.format)
                local quote_char = S(token.kind.format.quote_char)
                byte_class_lookup[byte(quote_char, 1)] = bor(byte_class_lookup[byte(quote_char, 1)] or 0, 4)
            elseif kind == "NumberToken" then
                local number_id = #number_plans + 1
                number_id_by_token_id[token_id] = number_id
                number_plans[number_id] = LT.StructuralNumberPlan(number_id, token.kind.format)
                for c = 48, 57 do byte_class_lookup[c] = bor(byte_class_lookup[c], 8) end
                if token.kind.format.allow_sign == true or N(token.kind.format.allow_sign) == 1 then
                    byte_class_lookup[45] = bor(byte_class_lookup[45], 8)
                end
            elseif kind == "ByteRunToken" then
                local words = token.kind.allowed_set.bitset_words
                for c = 0, 255 do
                    local wi = math.floor(c / 32) + 1
                    if band(N(words[wi] or 0), lshift(1, c % 32)) ~= 0 then
                        byte_class_lookup[c] = bor(byte_class_lookup[c], 16)
                    end
                end
            elseif kind == "IdentToken" then
                local words = token.kind.start_set.bitset_words
                for c = 0, 255 do
                    local wi = math.floor(c / 32) + 1
                    if band(N(words[wi] or 0), lshift(1, c % 32)) ~= 0 then
                        byte_class_lookup[c] = bor(byte_class_lookup[c], 32)
                    end
                end
            end
        end

        local keyword_dispatches = {}
        for first, cases in pairs(keyword_cases_by_first) do
            sort(cases, function(a, b) return #S(a.text) > #S(b.text) end)
            keyword_dispatches[#keyword_dispatches + 1] = LT.StructuralKeywordDispatch(first, cases)
        end
        sort(keyword_dispatches, function(a, b) return N(a.first_byte) < N(b.first_byte) end)

        local first_byte_set_cache = {}
        local first_byte_sets = {}
        local function intern_first_byte_lookup(lookup)
            local ids = {}
            for c = 0, 255 do if lookup[c] then ids[#ids + 1] = c end end
            local key = table.concat(ids, ",")
            local existing = first_byte_set_cache[key]
            if existing ~= nil then return existing end
            local set_id = #first_byte_sets + 1
            first_byte_sets[set_id] = LT.FirstByteSetTable(set_id, words_from_lookup(lookup))
            first_byte_set_cache[key] = set_id
            return set_id
        end

        local function union_lookup(a, b)
            local out = {}
            for c = 0, 255 do
                out[c] = (a and a[c]) or (b and b[c]) or false
            end
            return out
        end

        local rule_nullable_by_id = {}
        local rule_first_lookup_by_id = {}
        for i = 1, #spec.frontend.grammar.rules do
            local rule = spec.frontend.grammar.rules[i]
            rule_nullable_by_id[N(rule.header.id)] = rule.nullable == true or N(rule.nullable) == 1
            local lookup = {}
            for j = 1, #rule.first_set.token_ids do
                local token_id = N(rule.first_set.token_ids[j])
                lookup = union_lookup(lookup, token_start_lookup_by_id[token_id])
            end
            rule_first_lookup_by_id[N(rule.header.id)] = lookup
        end

        local function expr_first_lookup(expr)
            if expr.kind == "TokenRef" then
                return token_start_lookup_by_id[N(expr.header.id)] or {}
            elseif expr.kind == "RuleRef" then
                return rule_first_lookup_by_id[N(expr.header.id)] or {}
            elseif expr.kind == "Seq" then
                local out = {}
                for i = 1, #expr.items do
                    out = union_lookup(out, expr_first_lookup(expr.items[i]))
                    local child = expr.items[i]
                    local child_nullable = false
                    if child.kind == "RuleRef" then child_nullable = rule_nullable_by_id[N(child.header.id)]
                    elseif child.kind == "Optional" or child.kind == "Many" then child_nullable = true
                    elseif child.kind == "OneOrMore" then
                        local inner = child.inner
                        child_nullable = inner.kind == "RuleRef" and rule_nullable_by_id[N(inner.header.id)] or false
                    elseif child.kind == "Capture" or child.kind == "Build" then
                        child_nullable = (child.kind == "Capture") and false or false
                    elseif child.kind == "Delimited" then child_nullable = false
                    elseif child.kind == "SeparatedList" then child_nullable = child.cardinality.kind == "ZeroOrMore"
                    elseif child.kind == "Choice" then
                        local _, nullable = expr_first_lookup(child), false
                        for j = 1, #child.alts do
                            local alt = child.alts[j]
                            if alt.kind == "RuleRef" and rule_nullable_by_id[N(alt.header.id)] then nullable = true end
                            if alt.kind == "Optional" or alt.kind == "Many" then nullable = true end
                        end
                        child_nullable = nullable
                    elseif child.kind == "TokenRef" then child_nullable = false
                    end
                    if not child_nullable then break end
                end
                return out
            elseif expr.kind == "Choice" then
                local out = {}
                for i = 1, #expr.alts do out = union_lookup(out, expr_first_lookup(expr.alts[i])) end
                return out
            elseif expr.kind == "Optional" or expr.kind == "Many" or expr.kind == "OneOrMore" then
                return expr_first_lookup(expr.inner)
            elseif expr.kind == "Capture" or expr.kind == "Build" then
                return expr_first_lookup(expr.inner)
            elseif expr.kind == "Delimited" then
                return token_start_lookup_by_id[N(expr.open_header.id)] or {}
            elseif expr.kind == "SeparatedList" then
                return expr_first_lookup(expr.item)
            elseif expr.kind == "Precedence" then
                return expr_first_lookup(expr.atom)
            end
            error("FrontendChecked.Spec:lower(): unknown CheckedExpr kind '" .. tostring(expr.kind) .. "'", 2)
        end

        local grammar_spine = LT.GrammarSpine(
            U.map(spec.frontend.grammar.tokens, function(token) return token.header end),
            U.map(spec.frontend.grammar.rules, function(rule) return rule.header end),
            U.map(spec.frontend.constructors, function(ctor) return ctor.header end),
            U.map(spec.frontend.products, function(product) return product.header end)
        )

        local function rule_kind_for_expr(expr)
            if expr.kind == "TokenRef" then return LT.TerminalRuleKind end
            if expr.kind == "Choice" then return LT.ChoiceRuleKind end
            if expr.kind == "SeparatedList" then return LT.SeparatedListRuleKind end
            if expr.kind == "Precedence" then return LT.PrecedenceRuleKind end
            return LT.SeqRuleKind
        end

        local rule_spines = {}
        local lookahead_facets = {}
        for i = 1, #spec.frontend.grammar.rules do
            local rule = spec.frontend.grammar.rules[i]
            rule_spines[i] = LT.RuleSpine(rule.header, rule_kind_for_expr(rule.expr))
            lookahead_facets[i] = LT.RuleLookaheadFacet(
                N(rule.header.id),
                intern_first_byte_lookup(rule_first_lookup_by_id[N(rule.header.id)]),
                rule.nullable == true or N(rule.nullable) == 1
            )
        end

        local function fixed_token_byte(header, role)
            local token = token_by_id[N(header.id)]
            if token == nil or token.kind.kind ~= "FixedToken" then
                error("FrontendChecked.Spec:lower(): " .. role .. " requires FixedToken", 2)
            end
            local text = S(token.kind.text)
            if #text ~= 1 then
                error("FrontendChecked.Spec:lower(): " .. role .. " requires one-byte FixedToken", 2)
            end
            return byte(text, 1)
        end

        local function terminal_for_token(header)
            local token = token_by_id[N(header.id)]
            if token == nil then
                error("FrontendChecked.Spec:lower(): missing token for header", 2)
            end
            local kind = token.kind.kind
            if kind == "FixedToken" then
                return LT.ExpectFixedToken(header, S(token.kind.text), token.kind.boundary_policy)
            elseif kind == "QuotedStringToken" then
                return LT.ExpectQuotedString(header, string_id_by_token_id[N(header.id)])
            elseif kind == "NumberToken" then
                return LT.ExpectNumber(header, number_id_by_token_id[N(header.id)])
            elseif kind == "ByteRunToken" then
                return LT.ExpectByteRun(header, token.kind.allowed_set.bitset_words, token.kind.cardinality)
            elseif kind == "IdentToken" then
                error("FrontendChecked.Spec:lower(): structural frontier does not support IdentToken yet", 2)
            end
            error("FrontendChecked.Spec:lower(): unknown token kind '" .. tostring(kind) .. "'", 2)
        end

        local function lower_scalar_source(source)
            if source.kind == "CaptureScalar" then
                return LT.ReadScalarSlot(N(source.header.slot_id))
            elseif source.kind == "ConstString" then
                return LT.ReadConstString(S(source.value))
            elseif source.kind == "ConstBool" then
                return LT.ReadConstBool(source.value == true or N(source.value) == 1)
            elseif source.kind == "ConstNull" then
                return LT.ReadConstNull
            elseif source.kind == "DecodeNumber" then
                return LT.ReadDecodedNumber(N(source.header.slot_id), source.mode)
            end
            error("FrontendChecked.Spec:lower(): unknown CheckedScalarSource kind '" .. tostring(source.kind) .. "'", 2)
        end

        local function lower_result_plan(result)
            if result.kind == "ReturnEmpty" then
                return LT.ReturnEmpty
            elseif result.kind == "ReturnCapture" then
                return LT.ReturnSlot(N(result.header.slot_id))
            elseif result.kind == "ReturnList" then
                return LT.ReturnListRange(N(result.header.slot_id))
            elseif result.kind == "ReturnScalar" then
                return LT.ReturnScalar(lower_scalar_source(result.source))
            elseif result.kind == "ReturnCtor" then
                local args = {}
                for i = 1, #result.fields do
                    local source = result.fields[i].source
                    if source.kind == "CaptureSource" then
                        args[i] = LT.ReadSlot(N(source.header.slot_id))
                    elseif source.kind == "PresentSource" then
                        args[i] = LT.ReadPresent(N(source.header.slot_id))
                    elseif source.kind == "JoinedListSource" then
                        args[i] = LT.ReadJoined(N(source.header.slot_id), S(source.separator))
                    elseif source.kind == "ScalarResultSource" then
                        args[i] = LT.ReadScalar(lower_scalar_source(source.scalar))
                    else
                        error("FrontendChecked.Spec:lower(): unknown ResultSource kind '" .. tostring(source.kind) .. "'", 2)
                    end
                end
                return LT.ReturnCtor(N(result.ctor.id), args)
            end
            error("FrontendChecked.Spec:lower(): unknown CheckedResult kind '" .. tostring(result.kind) .. "'", 2)
        end

        local function lower_choice_arms(expr)
            local arms = {}
            for i = 1, #expr.alts do
                local alt = expr.alts[i]
                arms[i] = LT.StructuralChoiceArm(
                    intern_first_byte_lookup(expr_first_lookup(alt)),
                    nil -- placeholder
                )
            end
            return arms
        end

        local function lower_steps(expr)
            if expr.kind == "TokenRef" then
                return { LT.ExpectTerminal(terminal_for_token(expr.header), 0) }
            elseif expr.kind == "RuleRef" then
                return { LT.StructuralCallRule(expr.header, 0) }
            elseif expr.kind == "Seq" then
                local out = {}
                for i = 1, #expr.items do
                    local steps = lower_steps(expr.items[i])
                    for j = 1, #steps do out[#out + 1] = steps[j] end
                end
                return out
            elseif expr.kind == "Optional" then
                return { LT.StructuralOptionalGroup(intern_first_byte_lookup(expr_first_lookup(expr.inner)), lower_steps(expr.inner)) }
            elseif expr.kind == "Many" then
                return { LT.StructuralRepeatGroup(intern_first_byte_lookup(expr_first_lookup(expr.inner)), lower_steps(expr.inner)) }
            elseif expr.kind == "OneOrMore" then
                local out = lower_steps(expr.inner)
                out[#out + 1] = LT.StructuralRepeatGroup(intern_first_byte_lookup(expr_first_lookup(expr.inner)), lower_steps(expr.inner))
                return out
            elseif expr.kind == "Capture" then
                if expr.inner.kind == "TokenRef" then
                    return { LT.ExpectTerminal(terminal_for_token(expr.inner.header), N(expr.header.slot_id)) }
                elseif expr.inner.kind == "RuleRef" then
                    return { LT.StructuralCallRule(expr.inner.header, N(expr.header.slot_id)) }
                elseif expr.inner.kind == "SeparatedList" then
                    local sep = fixed_token_byte(expr.inner.separator_header, "SeparatedList separator")
                    return {
                        LT.StructuralSeparatedListGroup(
                            intern_first_byte_lookup(expr_first_lookup(expr.inner.item)),
                            lower_steps(expr.inner.item),
                            sep,
                            expr.inner.cardinality,
                            expr.inner.trailing_policy,
                            N(expr.header.slot_id)
                        )
                    }
                end
                error("FrontendChecked.Spec:lower(): structural frontier only supports Capture over TokenRef, RuleRef, or SeparatedList for now", 2)
            elseif expr.kind == "Build" then
                return lower_steps(expr.inner)
            elseif expr.kind == "Delimited" then
                return {
                    LT.StructuralDelimitedGroup(
                        fixed_token_byte(expr.open_header, "Delimited opener"),
                        lower_steps(expr.inner),
                        fixed_token_byte(expr.close_header, "Delimited closer")
                    )
                }
            elseif expr.kind == "SeparatedList" then
                return {
                    LT.StructuralSeparatedListGroup(
                        intern_first_byte_lookup(expr_first_lookup(expr.item)),
                        lower_steps(expr.item),
                        fixed_token_byte(expr.separator_header, "SeparatedList separator"),
                        expr.cardinality,
                        expr.trailing_policy,
                        0
                    )
                }
            elseif expr.kind == "Choice" then
                error("FrontendChecked.Spec:lower(): nested structural Choice is not implemented yet; use top-level Choice rule shape", 2)
            elseif expr.kind == "Precedence" then
                error("FrontendChecked.Spec:lower(): structural precedence lowering not implemented yet", 2)
            end
            error("FrontendChecked.Spec:lower(): unknown CheckedExpr kind '" .. tostring(expr.kind) .. "'", 2)
        end

        local structural_exec_facets = {}
        local rule_result_facets = {}
        for i = 1, #spec.frontend.grammar.rules do
            local rule = spec.frontend.grammar.rules[i]
            local rule_id = N(rule.header.id)
            if rule.expr.kind == "TokenRef" then
                structural_exec_facets[i] = LT.StructuralTerminalExecFacet(rule_id, terminal_for_token(rule.expr.header))
            elseif rule.expr.kind == "Choice" then
                local arms = {}
                for ai = 1, #rule.expr.alts do
                    local alt = rule.expr.alts[ai]
                    arms[ai] = LT.StructuralChoiceArm(
                        intern_first_byte_lookup(expr_first_lookup(alt)),
                        lower_steps(alt)
                    )
                end
                structural_exec_facets[i] = LT.StructuralChoiceExecFacet(rule_id, arms)
            else
                structural_exec_facets[i] = LT.StructuralSeqExecFacet(rule_id, lower_steps(rule.expr))
            end
            rule_result_facets[i] = LT.RuleResultFacet(rule_id, lower_result_plan(rule.result))
        end

        local product_facets = {}
        for i = 1, #spec.frontend.products do
            local product = spec.frontend.products[i]
            local builder
            if product.kind.kind == "ValidateProduct" then
                builder = LT.ValidateBuilderFacet
            elseif product.kind.kind == "AstArenaProduct" then
                builder = LT.AstArenaBuilderFacet(LT.ArenaFacet(product.source_refs.kind == "KeepSourceSpans", true, false))
            elseif product.kind.kind == "DecodeProduct" then
                builder = LT.DecodeBuilderFacet(LT.DecodeFacet(true, true, true, true))
            elseif product.kind.kind == "ExecIRProduct" then
                builder = LT.ExecIRBuilderFacet(LT.ExecIRFacet(true, true, true))
            else
                error("FrontendChecked.Spec:lower(): unknown ProductKind '" .. tostring(product.kind.kind) .. "'", 2)
            end
            product_facets[i] = LT.ProductFacet(N(product.header.id), N(product.entry_rule.id), builder)
        end

        local binding_facets = {}
        for i = 1, #spec.package.bindings do
            local binding = spec.package.bindings[i]
            if binding.kind.kind == "DirectBinding" then
                binding_facets[i] = LT.DirectBindingFacet(
                    N(binding.header.id),
                    N(binding.product.id),
                    binding.kind.parse,
                    binding.kind.output
                )
            else
                error("FrontendChecked.Spec:lower(): tokenized binding lowering not implemented yet in frontendc2", 2)
            end
        end

        return LT.StructuralFrontier(
            grammar_spine,
            LT.StructuralScanFacet(
                spec.frontend.grammar.input,
                spec.frontend.grammar.trivia_policy,
                lowered_skips,
                LT.StructuralByteClassTable((function()
                    local xs = {}
                    for c = 0, 255 do xs[#xs + 1] = byte_class_lookup[c] or 0 end
                    return xs
                end)()),
                keyword_dispatches,
                string_plans,
                number_plans,
                first_byte_sets
            ),
            rule_spines,
            lookahead_facets,
            structural_exec_facets,
            rule_result_facets,
            product_facets,
            LT.PackageFacet(binding_facets)
        )
    end)

    function T.FrontendChecked.Spec:lower()
        return lower_impl(self)
    end
end
