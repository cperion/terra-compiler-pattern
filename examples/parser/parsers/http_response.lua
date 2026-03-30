return function(P)
    return P.grammar({
        P.rule("start", P.seq(
            P.lit("HTTP/"),
            P.plus(P.alt(P.digit, P.lit("."))),
            P.lit(" "),
            P.plus(P.digit),
            P.lit(" "),
            P.star(P.seq(P.not_look(P.lit("\r\n")), P.any)),
            P.lit("\r\n"),
            P.star(P.ref("header")),
            P.lit("\r\n"),
            P.star(P.any),
            P.eof
        )),
        P.rule("header", P.seq(
            P.plus(P.seq(P.not_look(P.lit(":")), P.any)),
            P.lit(": "),
            P.star(P.seq(P.not_look(P.lit("\r\n")), P.any)),
            P.lit("\r\n")
        ))
    }, "start")
end
