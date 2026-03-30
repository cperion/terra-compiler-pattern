return function(P)
    local nl = P.alt(P.lit("\r\n"), P.lit("\n"))
    local line_ws = P.star(P.set(" \t"))
    local line_comment = P.seq(
        P.set(";#"),
        P.star(P.seq(P.not_look(P.alt(nl, P.eof)), P.any))
    )
    local name_char = P.alt(P.word_char, P.set(".-/"))
    local name = P.plus(name_char)
    local section = P.seq(
        line_ws,
        P.lit("["),
        name,
        P.lit("]"),
        line_ws,
        P.opt(line_comment)
    )
    local value = P.star(P.seq(P.not_look(P.alt(nl, P.eof)), P.any))
    local pair = P.seq(
        line_ws,
        name,
        line_ws,
        P.lit("="),
        line_ws,
        value
    )
    local line = P.alt(section, pair, P.seq(line_ws, P.opt(line_comment)))

    return P.grammar({
        P.rule("start", P.seq(line, P.star(P.seq(nl, line)), P.opt(nl), P.eof))
    }, "start")
end
