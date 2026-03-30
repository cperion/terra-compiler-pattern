-- parser_builder.lua
--
-- Grammar builder DSL: readable PEG-like syntax → ASDL nodes
-- ----------------------------------------------------------------------------
-- This is NOT the compiler. It is a convenience layer that constructs
-- GrammarSource ASDL nodes from a readable API.
--
--   P.lit("hello")           -> Literal("hello")
--   P.seq(a, b, c)           -> Sequence([a, b, c])
--   P.alt(a, b)              -> Choice([a, b])
--   P.star(p)                -> Repeat(p, 0, -1)
--   P.plus(p)                -> Repeat(p, 1, -1)
--   P.opt(p)                 -> Optional(p)
--   P.cap("name", p)         -> Capture("name", p)
--   P.ref("rule")            -> Reference("rule")
--   P.range("a", "z")        -> CharRange(97, 122)
--   P.set("+-")              -> CharSet("+-", false)
--   P.set("+-", true)        -> CharSet("+-", true)  (negated)
--   P.any                    -> Any
--   P.eof                    -> EOF
--   P.look(p)                -> LookAhead(p, true)
--   P.not_look(p)            -> LookAhead(p, false)
--   P.action("tag", p)       -> Action("tag", p)

local asdl = require("asdl")
local L = asdl.List

return function(T)
    local G = T.GrammarSource
    local P = {}

    -- Primitives
    function P.lit(s)       return G.Literal(s) end
    P.any                   = G.Any
    P.eof                   = G.EOF

    -- Character classes
    function P.range(lo, hi)
        return G.CharRange(lo:byte(1), hi:byte(1))
    end

    function P.set(chars, negated)
        return G.CharSet(chars, negated or false)
    end

    -- Combinators
    function P.seq(...)
        local args = { ... }
        if #args == 1 then return args[1] end
        return G.Sequence(L(args))
    end

    function P.alt(...)
        local args = { ... }
        if #args == 1 then return args[1] end
        return G.Choice(L(args))
    end

    function P.star(p)     return G.Repeat(p, 0, -1) end
    function P.plus(p)     return G.Repeat(p, 1, -1) end
    function P.rep(p, min, max)
        return G.Repeat(p, min or 0, max or -1)
    end
    function P.opt(p)      return G.Optional(p) end

    -- Lookahead
    function P.look(p)     return G.LookAhead(p, true) end
    function P.not_look(p) return G.LookAhead(p, false) end

    -- Captures
    function P.cap(name, p)    return G.Capture(name, p) end
    function P.action(tag, p)  return G.Action(tag, p) end

    -- References
    function P.ref(name)   return G.Reference(name) end

    -- Grammar construction
    function P.rule(name, body)
        return G.Rule(name, body)
    end

    function P.grammar(rules, start)
        return G.Grammar(L(rules), start)
    end

    -- ── Shorthand character classes ──
    P.digit     = P.range("0", "9")
    P.lower     = P.range("a", "z")
    P.upper     = P.range("A", "Z")
    P.alpha     = P.alt(P.lower, P.upper)
    P.alnum     = P.alt(P.alpha, P.digit)
    P.space     = P.set(" \t\n\r")
    P.ws        = P.star(P.space)
    P.letter    = P.alt(P.alpha, P.lit("_"))
    P.word_char = P.alt(P.alnum, P.lit("_"))

    -- Install on T for access by other modules
    T._parser_builder = P
end
