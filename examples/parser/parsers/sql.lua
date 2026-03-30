return function(P)
    local function ci_char(ch)
        local lo, up = ch:lower(), ch:upper()
        if lo == up then return P.lit(ch) end
        return P.alt(P.lit(lo), P.lit(up))
    end

    local function kw(s)
        local parts = {}
        for i = 1, #s do parts[#parts + 1] = ci_char(s:sub(i, i)) end
        return P.seq(unpack(parts))
    end

    local function list1(item, sep)
        return P.seq(item, P.star(P.seq(sep, item)))
    end

    local ws1 = P.plus(P.space)
    local ident = P.seq(P.letter, P.star(P.word_char))
    local qident = P.seq(ident, P.star(P.seq(P.lit("."), ident)))
    local quoted = P.seq(
        P.lit("'"),
        P.star(P.alt(P.lit("''"), P.seq(P.not_look(P.lit("'")), P.any))),
        P.lit("'")
    )
    local number = P.seq(
        P.opt(P.lit("-")),
        P.plus(P.digit),
        P.opt(P.seq(P.lit("."), P.plus(P.digit)))
    )
    local scalar = P.alt(
        quoted,
        number,
        kw("NULL"),
        kw("TRUE"),
        kw("FALSE"),
        qident
    )
    local scalar_list = list1(scalar, P.seq(P.ws, P.lit(","), P.ws))
    local relop = P.alt(
        P.lit("<="), P.lit(">="), P.lit("<>"), P.lit("!="),
        P.lit("="), P.lit("<"), P.lit(">")
    )
    local predicate = P.alt(
        P.seq(qident, ws1, kw("IS"), ws1, P.opt(P.seq(kw("NOT"), ws1)), kw("NULL")),
        P.seq(qident, ws1, kw("IN"), P.ws, P.lit("("), P.ws, scalar_list, P.ws, P.lit(")")),
        P.seq(qident, P.ws, relop, P.ws, scalar)
    )
    local where_expr = P.seq(
        predicate,
        P.star(P.seq(P.ws, P.alt(kw("AND"), kw("OR")), P.ws, predicate))
    )
    local select_item = P.alt(P.lit("*"), qident, quoted, number)
    local select_list = list1(select_item, P.seq(P.ws, P.lit(","), P.ws))

    local select_stmt = P.seq(
        kw("SELECT"), ws1, select_list,
        ws1, kw("FROM"), ws1, qident,
        P.opt(P.seq(ws1, kw("WHERE"), ws1, where_expr))
    )

    return P.grammar({
        P.rule("start", P.seq(P.ws, select_stmt, P.ws, P.opt(P.lit(";")), P.ws, P.eof))
    }, "start")
end
