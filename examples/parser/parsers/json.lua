return function(P)
    return P.grammar({
        P.rule("start", P.seq(P.ws, P.ref("value"), P.ws, P.eof)),
        P.rule("value", P.alt(
            P.ref("string"),
            P.ref("number"),
            P.ref("object"),
            P.ref("array"),
            P.lit("true"),
            P.lit("false"),
            P.lit("null")
        )),
        P.rule("string", P.seq(
            P.lit('"'),
            P.star(P.alt(
                P.seq(P.lit('\\'), P.any),
                P.seq(P.not_look(P.lit('"')), P.any)
            )),
            P.lit('"')
        )),
        P.rule("number", P.seq(
            P.opt(P.lit("-")),
            P.alt(P.lit("0"), P.seq(P.range("1", "9"), P.star(P.digit))),
            P.opt(P.seq(P.lit("."), P.plus(P.digit))),
            P.opt(P.seq(P.set("eE"), P.opt(P.set("+-")), P.plus(P.digit)))
        )),
        P.rule("object", P.seq(
            P.lit("{"), P.ws,
            P.opt(P.seq(
                P.ref("pair"),
                P.star(P.seq(P.ws, P.lit(","), P.ws, P.ref("pair")))
            )),
            P.ws, P.lit("}")
        )),
        P.rule("pair", P.seq(
            P.ref("string"),
            P.ws, P.lit(":"), P.ws,
            P.ref("value")
        )),
        P.rule("array", P.seq(
            P.lit("["), P.ws,
            P.opt(P.seq(
                P.ref("value"),
                P.star(P.seq(P.ws, P.lit(","), P.ws, P.ref("value")))
            )),
            P.ws, P.lit("]")
        )),
    }, "start")
end
