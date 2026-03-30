return [=[
-- ==========================================================================
-- JS lexer ASDL
-- --------------------------------------------------------------------------
-- Frontend phase split foundation:
--   text -> JsLex.TokenStream -> surface parse -> JsSource -> ...
--
-- This module captures the lexical vocabulary as typed tokens so later
-- frontend phases no longer need to rediscover character-level structure.
-- ==========================================================================

module JsLex {

    TokenStream = (Token* tokens) unique

    Token
        = Identifier(string text, number start, number stop)
        | Keyword(string text, number start, number stop)
        | Number(string raw, number start, number stop)
        | String(string raw, number start, number stop)
        | Template(string raw, number start, number stop)
        | Regex(string pattern, string flags, number start, number stop)
        | Punct(string text, number start, number stop)
        | Comment(string text, boolean block, number start, number stop)
        | EOF(number start, number stop)
}
]=]