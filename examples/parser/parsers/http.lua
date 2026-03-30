return function(P)
    return P.grammar({
        P.rule("start", P.seq(
            P.cap("method", P.plus(P.alpha)),
            P.lit(" "),
            P.cap("path", P.plus(P.seq(P.not_look(P.lit(" ")), P.any))),
            P.lit(" "),
            P.cap("version", P.seq(P.lit("HTTP/"), P.plus(P.alt(P.digit, P.lit("."))))),
            P.lit("\r\n"),
            P.star(P.cap("header", P.ref("header"))),
            P.lit("\r\n")
        )),
        P.rule("header", P.seq(
            P.cap("hname", P.plus(P.seq(P.not_look(P.lit(":")), P.any))),
            P.lit(": "),
            P.cap("hvalue", P.plus(P.seq(P.not_look(P.lit("\r\n")), P.any))),
            P.lit("\r\n")
        )),
    }, "start")
end
