return function(P)
    local line_comment = P.seq(
        P.lit(";"),
        P.star(P.seq(P.not_look(P.alt(P.lit("\n"), P.eof)), P.any)),
        P.opt(P.lit("\n"))
    )
    local ign = P.alt(P.space, line_comment)
    local ws = P.star(ign)
    local ws1 = P.plus(ign)

    local atom_char = P.seq(
        P.not_look(P.alt(P.set("()\""), ign, P.eof)),
        P.any
    )
    local atom = P.plus(atom_char)
    local string_lit = P.seq(
        P.lit('"'),
        P.star(P.alt(
            P.seq(P.lit('\\'), P.any),
            P.seq(P.not_look(P.lit('"')), P.any)
        )),
        P.lit('"')
    )
    local list = P.seq(
        P.lit("("), ws,
        P.opt(P.seq(P.ref("expr"), P.star(P.seq(ws1, P.ref("expr"))))),
        ws, P.lit(")")
    )

    return P.grammar({
        P.rule("start", P.seq(ws, P.ref("expr"), ws, P.eof)),
        P.rule("expr", P.alt(list, string_lit, atom)),
    }, "start")
end
