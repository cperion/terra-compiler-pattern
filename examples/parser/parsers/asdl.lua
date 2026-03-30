return function(P)
    local function list1(item, sep)
        return P.seq(item, P.star(P.seq(sep, item)))
    end

    local space_char = P.set(" \t\r\n")
    local line_comment = P.seq(
        P.lit("--"),
        P.star(P.seq(P.not_look(P.lit("\n")), P.any)),
        P.opt(P.lit("\n"))
    )
    local ws = P.star(P.alt(space_char, line_comment))
    local ws1 = P.plus(P.alt(space_char, line_comment))

    local ident = P.seq(P.letter, P.star(P.word_char))
    local type_ref = P.seq(ident, P.opt(P.lit("*")))
    local field = P.seq(type_ref, ws1, ident)
    local fields = P.seq(
        P.lit("("), ws,
        P.opt(list1(field, P.seq(ws, P.lit(","), ws))),
        ws, P.lit(")")
    )
    local constructor = P.seq(ident, P.opt(P.seq(ws, fields)))
    local sum_def = P.seq(
        ident, ws, P.lit("="), ws,
        constructor,
        P.star(P.seq(ws, P.lit("|"), ws, constructor))
    )
    local product_def = P.seq(
        ident, ws, P.lit("="), ws,
        fields,
        P.opt(P.seq(ws1, P.lit("unique")))
    )
    local definition = P.alt(product_def, sum_def)
    local module_def = P.seq(
        P.lit("module"), ws1, ident, ws,
        P.lit("{"), ws,
        P.star(P.seq(definition, ws)),
        P.lit("}")
    )

    return P.grammar({
        P.rule("start", P.seq(ws, P.plus(P.seq(module_def, ws)), P.eof)),
    }, "start")
end
