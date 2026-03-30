-- parser_compile.lua
--
-- Canonical terminal: GrammarSource.Grammar -> compiled parser function
-- ----------------------------------------------------------------------------
-- This is the single parser compiler implementation kept by the example.
-- It incorporates the better-performing optimizations:
--
--   1. Pre-bind rule references through closure upvalues
--   2. Fuse repeat(seq(not_look(x), any)) scan patterns into tight loops
--   3. Pack CharSet into bit-indexed uint64 (4 words = 256 bits)
--   4. Specialize common pattern shapes for trace stability
--   5. Minimize table allocation in hot paths

local ffi = require("ffi")
local bit = require("bit")
local U = require("unit")

pcall(function() ffi.cdef[[ int memcmp(const void *s1, const void *s2, size_t n); ]] end)

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local function S(v)
    if v == nil then return nil end
    if type(v) == "cdata" then return ffi.string(v) end
    return tostring(v)
end
local function N(v) return tonumber(v) end

-- ═══════════════════════════════════════════════════════════════
-- Bit-packed character set: 4 × uint64 = 256 bits
-- ═══════════════════════════════════════════════════════════════

local function charset_build(chars_str, negated)
    local w = ffi.new("uint64_t[4]")
    for i = 1, #chars_str do
        local c = chars_str:byte(i)
        local wi = rshift(c, 6)
        local bi = band(c, 63)
        w[wi] = bor(w[wi], lshift(1ULL, bi))
    end
    if negated then
        for i = 0, 3 do w[i] = bit.bnot(w[i]) end
    end
    return w
end

-- ═══════════════════════════════════════════════════════════════
-- Pattern fusion: detect repeat(seq(not_look(literal), any))
-- ═══════════════════════════════════════════════════════════════

local function scan_shape(pattern)
    if pattern.kind ~= "Repeat" then return nil end

    local min = N(pattern.min)
    local max = N(pattern.max)
    if max >= 0 then return nil end
    if min ~= 0 and min ~= 1 then return nil end

    local inner = pattern.pattern
    if inner.kind ~= "Sequence" then return nil end
    if #inner.patterns ~= 2 then return nil end

    local look = inner.patterns[1]
    local any = inner.patterns[2]
    if any.kind ~= "Any" then return nil end
    if look.kind ~= "LookAhead" then return nil end

    local positive = look.positive
    if type(positive) ~= "boolean" then positive = positive ~= 0 and positive ~= false end
    if positive then return nil end

    local lit = look.pattern
    if lit.kind ~= "Literal" then return nil end

    local text = S(lit.text)
    local len = #text
    if len ~= 1 and len ~= 2 then return nil end

    return {
        min = min,
        len = len,
        c1 = text:byte(1),
        c2 = len == 2 and text:byte(2) or nil,
    }
end

local compile_pattern

compile_pattern = function(pattern, rules_map, deferred)
    local scan = scan_shape(pattern)
    if scan then
        local min = scan.min
        local len = scan.len
        local c1 = scan.c1
        local c2 = scan.c2

        if len == 1 then
            return function(buf, pos, limit, caps)
                local start = pos
                while pos < limit and buf[pos] ~= c1 do
                    pos = pos + 1
                end
                if min == 1 and pos == start then return nil end
                return pos
            end
        else
            return function(buf, pos, limit, caps)
                local start = pos
                while pos < limit do
                    if buf[pos] == c1 and pos + 1 < limit and buf[pos + 1] == c2 then
                        break
                    end
                    pos = pos + 1
                end
                if min == 1 and pos == start then return nil end
                return pos
            end
        end
    end

    return U.match(pattern, {
        Literal = function(p)
            local text = S(p.text)
            local len = #text
            if len == 0 then
                return function(buf, pos, limit, caps) return pos end
            elseif len == 1 then
                local c = text:byte(1)
                return function(buf, pos, limit, caps)
                    if pos < limit and buf[pos] == c then return pos + 1 end
                    return nil
                end
            elseif len == 2 then
                local c1, c2 = text:byte(1, 2)
                return function(buf, pos, limit, caps)
                    if pos + 1 < limit and buf[pos] == c1 and buf[pos + 1] == c2 then
                        return pos + 2
                    end
                    return nil
                end
            elseif len == 3 then
                local c1, c2, c3 = text:byte(1, 3)
                return function(buf, pos, limit, caps)
                    if pos + 2 < limit and buf[pos] == c1 and buf[pos + 1] == c2 and buf[pos + 2] == c3 then
                        return pos + 3
                    end
                    return nil
                end
            elseif len == 4 then
                local c1, c2, c3, c4 = text:byte(1, 4)
                return function(buf, pos, limit, caps)
                    if pos + 3 < limit and buf[pos] == c1 and buf[pos + 1] == c2
                        and buf[pos + 2] == c3 and buf[pos + 3] == c4 then
                        return pos + 4
                    end
                    return nil
                end
            else
                local lit = ffi.new("uint8_t[?]", len)
                ffi.copy(lit, text, len)
                return function(buf, pos, limit, caps)
                    if pos + len > limit then return nil end
                    if ffi.C.memcmp(buf + pos, lit, len) == 0 then
                        return pos + len
                    end
                    return nil
                end
            end
        end,

        CharRange = function(p)
            local lo, hi = N(p.low), N(p.high)
            return function(buf, pos, limit, caps)
                if pos >= limit then return nil end
                local c = buf[pos]
                if c >= lo and c <= hi then return pos + 1 end
                return nil
            end
        end,

        CharSet = function(p)
            local chars = S(p.chars)
            local negated = p.negated
            if type(negated) ~= "boolean" then negated = negated ~= 0 and negated ~= false end
            local w = charset_build(chars, negated)
            local w0, w1, w2, w3 = w[0], w[1], w[2], w[3]
            return function(buf, pos, limit, caps)
                if pos >= limit then return nil end
                local c = buf[pos]
                local wi = rshift(c, 6)
                local mask = lshift(1ULL, band(c, 63))
                local word
                if wi == 0 then word = w0
                elseif wi == 1 then word = w1
                elseif wi == 2 then word = w2
                else word = w3 end
                if band(word, mask) ~= 0 then return pos + 1 end
                return nil
            end
        end,

        Any = function()
            return function(buf, pos, limit, caps)
                if pos < limit then return pos + 1 end
                return nil
            end
        end,

        Sequence = function(p)
            local parts = {}
            for i = 1, #p.patterns do
                parts[i] = compile_pattern(p.patterns[i], rules_map, deferred)
            end
            local n = #parts
            if n == 0 then
                return function(buf, pos, limit, caps) return pos end
            elseif n == 1 then
                return parts[1]
            elseif n == 2 then
                local p1, p2 = parts[1], parts[2]
                return function(buf, pos, limit, caps)
                    pos = p1(buf, pos, limit, caps)
                    if pos then return p2(buf, pos, limit, caps) end
                    return nil
                end
            elseif n == 3 then
                local p1, p2, p3 = parts[1], parts[2], parts[3]
                return function(buf, pos, limit, caps)
                    pos = p1(buf, pos, limit, caps)
                    if not pos then return nil end
                    pos = p2(buf, pos, limit, caps)
                    if pos then return p3(buf, pos, limit, caps) end
                    return nil
                end
            elseif n == 4 then
                local p1, p2, p3, p4 = parts[1], parts[2], parts[3], parts[4]
                return function(buf, pos, limit, caps)
                    pos = p1(buf, pos, limit, caps)
                    if not pos then return nil end
                    pos = p2(buf, pos, limit, caps)
                    if not pos then return nil end
                    pos = p3(buf, pos, limit, caps)
                    if pos then return p4(buf, pos, limit, caps) end
                    return nil
                end
            else
                return function(buf, pos, limit, caps)
                    for i = 1, n do
                        pos = parts[i](buf, pos, limit, caps)
                        if not pos then return nil end
                    end
                    return pos
                end
            end
        end,

        Choice = function(p)
            local alts = {}
            for i = 1, #p.alternatives do
                alts[i] = compile_pattern(p.alternatives[i], rules_map, deferred)
            end
            local n = #alts
            if n == 0 then
                return function(buf, pos, limit, caps) return nil end
            elseif n == 1 then
                return alts[1]
            elseif n == 2 then
                local a1, a2 = alts[1], alts[2]
                return function(buf, pos, limit, caps)
                    return a1(buf, pos, limit, caps)
                        or a2(buf, pos, limit, caps)
                end
            elseif n == 3 then
                local a1, a2, a3 = alts[1], alts[2], alts[3]
                return function(buf, pos, limit, caps)
                    return a1(buf, pos, limit, caps)
                        or a2(buf, pos, limit, caps)
                        or a3(buf, pos, limit, caps)
                end
            else
                return function(buf, pos, limit, caps)
                    for i = 1, n do
                        local r = alts[i](buf, pos, limit, caps)
                        if r then return r end
                    end
                    return nil
                end
            end
        end,

        Repeat = function(p)
            local inner = compile_pattern(p.pattern, rules_map, deferred)
            local min, max = N(p.min), N(p.max)

            if min == 0 and max < 0 then
                return function(buf, pos, limit, caps)
                    local npos = inner(buf, pos, limit, caps)
                    while npos and npos ~= pos do
                        pos = npos
                        npos = inner(buf, pos, limit, caps)
                    end
                    return pos
                end
            elseif min == 1 and max < 0 then
                return function(buf, pos, limit, caps)
                    pos = inner(buf, pos, limit, caps)
                    if not pos then return nil end
                    local npos = inner(buf, pos, limit, caps)
                    while npos and npos ~= pos do
                        pos = npos
                        npos = inner(buf, pos, limit, caps)
                    end
                    return pos
                end
            else
                local unbounded = max < 0
                return function(buf, pos, limit, caps)
                    local count = 0
                    while unbounded or count < max do
                        local npos = inner(buf, pos, limit, caps)
                        if not npos or npos == pos then break end
                        pos = npos
                        count = count + 1
                    end
                    if count < min then return nil end
                    return pos
                end
            end
        end,

        Optional = function(p)
            local inner = compile_pattern(p.pattern, rules_map, deferred)
            return function(buf, pos, limit, caps)
                return inner(buf, pos, limit, caps) or pos
            end
        end,

        LookAhead = function(p)
            local inner = compile_pattern(p.pattern, rules_map, deferred)
            local positive = p.positive
            if type(positive) ~= "boolean" then positive = positive ~= 0 and positive ~= false end
            if positive then
                return function(buf, pos, limit, caps)
                    if inner(buf, pos, limit, caps) then return pos end
                    return nil
                end
            else
                return function(buf, pos, limit, caps)
                    if inner(buf, pos, limit, caps) then return nil end
                    return pos
                end
            end
        end,

        Capture = function(p)
            local inner = compile_pattern(p.pattern, rules_map, deferred)
            local name = S(p.name)
            return function(buf, pos, limit, caps)
                local start = pos
                local end_pos = inner(buf, pos, limit, caps)
                if not end_pos then return nil end
                caps[#caps + 1] = { name = name, start = start, len = end_pos - start }
                return end_pos
            end
        end,

        Reference = function(p)
            local name = S(p.rule_name)
            local resolved = nil
            deferred[#deferred + 1] = function()
                resolved = rules_map[name]
                if not resolved then
                    error("undefined rule: " .. name)
                end
            end
            return function(buf, pos, limit, caps)
                return resolved(buf, pos, limit, caps)
            end
        end,

        Action = function(p)
            local inner = compile_pattern(p.pattern, rules_map, deferred)
            local tag = S(p.tag)
            return function(buf, pos, limit, caps)
                local start = pos
                local end_pos = inner(buf, pos, limit, caps)
                if not end_pos then return nil end
                caps[#caps + 1] = { tag = tag, start = start, len = end_pos - start }
                return end_pos
            end
        end,

        EOF = function()
            return function(buf, pos, limit, caps)
                if pos >= limit then return pos end
                return nil
            end
        end,
    })
end

local function compile_grammar(grammar)
    local rules_map = {}
    local deferred = {}

    for i = 1, #grammar.rules do
        local rule = grammar.rules[i]
        local name = S(rule.name)
        rules_map[name] = compile_pattern(rule.body, rules_map, deferred)
    end

    for i = 1, #deferred do
        deferred[i]()
    end

    local start_name = S(grammar.start)
    local start_rule = rules_map[start_name]
    if not start_rule then
        error("start rule '" .. start_name .. "' not found")
    end

    return function(input)
        local buf = ffi.cast("const uint8_t*", input)
        local limit = #input
        local caps = {}
        local final_pos = start_rule(buf, 0, limit, caps)
        if not final_pos then return nil end
        return caps, final_pos
    end
end

return function(T)
    T.GrammarSource.Grammar.compile = U.terminal(
        "GrammarSource.Grammar:compile",
        function(grammar)
            return compile_grammar(grammar)
        end
    )
end
