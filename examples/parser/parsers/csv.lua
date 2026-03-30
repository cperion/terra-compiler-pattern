return function(P)
    return P.grammar({
        P.rule("start", P.seq(
            P.ref("row"),
            P.star(P.seq(P.lit("\n"), P.ref("row"))),
            P.eof
        )),
        P.rule("row", P.seq(
            P.cap("field", P.ref("field")),
            P.star(P.seq(P.lit(","), P.cap("field", P.ref("field"))))
        )),
        P.rule("field", P.alt(
            P.ref("quoted"),
            P.star(P.seq(P.not_look(P.alt(P.lit(","), P.lit("\n"), P.eof)), P.any))
        )),
        P.rule("quoted", P.seq(
            P.lit('"'),
            P.star(P.alt(P.lit('""'), P.seq(P.not_look(P.lit('"')), P.any))),
            P.lit('"')
        )),
    }, "start")
end
