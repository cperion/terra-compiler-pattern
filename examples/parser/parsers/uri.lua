return function(P)
    local scheme = P.seq(
        P.alpha,
        P.star(P.alt(P.alnum, P.set("+-.")))
    )
    local authority = P.plus(P.seq(P.not_look(P.alt(P.lit("/"), P.lit("?"), P.lit("#"), P.eof)), P.any))
    local path = P.star(P.seq(P.not_look(P.alt(P.lit("?"), P.lit("#"), P.eof)), P.any))
    local query = P.seq(P.lit("?"), P.star(P.seq(P.not_look(P.alt(P.lit("#"), P.eof)), P.any)))
    local fragment = P.seq(P.lit("#"), P.star(P.seq(P.not_look(P.eof), P.any)))

    return P.grammar({
        P.rule("start", P.seq(
            scheme,
            P.lit(":"),
            P.alt(
                P.seq(P.lit("//"), authority, path),
                path
            ),
            P.opt(query),
            P.opt(fragment),
            P.eof
        ))
    }, "start")
end
