return [=[
-- ============================================================================
-- Parser compiler ASDL
-- ----------------------------------------------------------------------------
-- A PEG grammar IS an ASDL. Each rule is a product. Each pattern alternative
-- is a sum type. The compiler produces closures specialized for THAT grammar.
-- No interpreter. No virtual dispatch per rule. Just baked byte comparisons
-- that LuaJIT traces into native branch chains.
--
-- Phases:
--   GrammarSource     the authored grammar (rules + patterns)
--   GrammarCompiled   compiled closure tree description
-- ============================================================================


-- ============================================================================
-- GrammarSource: the authored grammar
-- ----------------------------------------------------------------------------
-- This IS the source program. The user authors rules and patterns.
-- Every pattern node is an independent authored choice.
-- ============================================================================
module GrammarSource {

    Grammar = (Rule* rules, string start) unique

    Rule = (string name, Pattern body) unique

    Pattern
        = Literal(string text)
        | CharRange(number low, number high)
        | CharSet(string chars, boolean negated)
        | Any
        | Sequence(Pattern* patterns)
        | Choice(Pattern* alternatives)
        | Repeat(Pattern pattern, number min, number max)
        | Optional(Pattern pattern)
        | LookAhead(Pattern pattern, boolean positive)
        | Capture(string name, Pattern pattern)
        | Reference(string rule_name)
        | Action(string tag, Pattern pattern)
        | EOF
}


-- ============================================================================
-- GrammarCompiled: compiled parser description
-- ----------------------------------------------------------------------------
-- Terminal output. The closure tree IS the compiled machine.
-- This phase records only metadata for inspection.
-- ============================================================================
module GrammarCompiled {

    Parser = (
        number rule_count,
        number pattern_count
    ) unique
}
]=]
