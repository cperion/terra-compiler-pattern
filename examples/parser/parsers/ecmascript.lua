return function(P)
    -- Canonical ECMAScript surface grammar.
    --
    -- This is a broad syntax recognizer intended to replace the old minimal JS
    -- frontend with a parser-compiler-authored grammar.

    local function list(item, sep)
        return P.seq(item, P.star(P.seq(sep, item)), P.opt(sep))
    end

    local function choice(xs)
        return P.alt(unpack(xs))
    end

    local nl = P.alt(P.lit("\r\n"), P.lit("\n"), P.lit("\r"))
    local hspace = P.set(" \t")
    local ws_char = P.alt(hspace, nl)
    local line_comment = P.seq(
        P.lit("//"),
        P.star(P.seq(P.not_look(P.alt(nl, P.eof)), P.any)),
        P.opt(nl)
    )
    local block_comment = P.seq(
        P.lit("/*"),
        P.star(P.seq(P.not_look(P.lit("*/")), P.any)),
        P.lit("*/")
    )
    local skip = P.star(P.alt(ws_char, line_comment, block_comment))

    local function tok(p)
        return P.seq(skip, p, skip)
    end

    local raw_ident_start = P.alt(P.alpha, P.lit("_"), P.lit("$"))
    local raw_ident_continue = P.alt(raw_ident_start, P.digit)
    local raw_name = P.seq(raw_ident_start, P.star(raw_ident_continue))

    local reserved = {
        "await", "break", "case", "catch", "class", "const", "continue",
        "debugger", "default", "delete", "do", "else", "export", "extends",
        "finally", "for", "function", "if", "import", "in", "instanceof",
        "let", "new", "return", "static", "super", "switch", "this",
        "throw", "try", "typeof", "var", "void", "while", "with", "yield",
        "async", "of", "null", "true", "false", "undefined",
    }
    local reserved_raw = {}
    for i = 1, #reserved do
        reserved_raw[i] = P.seq(P.lit(reserved[i]), P.not_look(raw_ident_continue))
    end
    local reserved_word = P.alt(unpack(reserved_raw))

    local function kw(s)
        return tok(P.seq(P.lit(s), P.not_look(raw_ident_continue)))
    end

    local function sym(s)
        return tok(P.lit(s))
    end

    local identifier = tok(P.seq(P.not_look(reserved_word), raw_name))
    local property_ident = tok(raw_name)
    local private_identifier = tok(P.seq(P.lit("#"), raw_name))

    local sq_char = P.alt(
        P.seq(P.lit("\\"), P.any),
        P.seq(P.not_look(P.alt(P.lit("'"), nl)), P.any)
    )
    local dq_char = P.alt(
        P.seq(P.lit("\\"), P.any),
        P.seq(P.not_look(P.alt(P.lit('"'), nl)), P.any)
    )
    local string_literal = tok(P.alt(
        P.seq(P.lit("'"), P.star(sq_char), P.lit("'")),
        P.seq(P.lit('"'), P.star(dq_char), P.lit('"'))
    ))

    local decimal_digits = P.plus(P.digit)
    local hex_digit = P.alt(P.digit, P.range("a", "f"), P.range("A", "F"))
    local oct_digit = P.range("0", "7")
    local bin_digit = P.set("01")
    local exponent = P.seq(P.set("eE"), P.opt(P.set("+-")), P.plus(P.digit))
    local bigint_literal = P.alt(
        P.seq(P.lit("0x"), P.plus(hex_digit), P.lit("n")),
        P.seq(P.lit("0X"), P.plus(hex_digit), P.lit("n")),
        P.seq(P.lit("0o"), P.plus(oct_digit), P.lit("n")),
        P.seq(P.lit("0O"), P.plus(oct_digit), P.lit("n")),
        P.seq(P.lit("0b"), P.plus(bin_digit), P.lit("n")),
        P.seq(P.lit("0B"), P.plus(bin_digit), P.lit("n")),
        P.seq(decimal_digits, P.lit("n"))
    )
    local int_literal = P.alt(
        P.seq(P.lit("0x"), P.plus(hex_digit)),
        P.seq(P.lit("0X"), P.plus(hex_digit)),
        P.seq(P.lit("0o"), P.plus(oct_digit)),
        P.seq(P.lit("0O"), P.plus(oct_digit)),
        P.seq(P.lit("0b"), P.plus(bin_digit)),
        P.seq(P.lit("0B"), P.plus(bin_digit)),
        decimal_digits
    )
    local frac_literal = P.alt(
        P.seq(P.opt(decimal_digits), P.lit("."), P.plus(P.digit), P.opt(exponent)),
        P.seq(decimal_digits, exponent)
    )
    local number_literal = tok(P.alt(bigint_literal, frac_literal, int_literal))

    local regex_flag = P.set("gimsuyd")
    local regex_char = P.alt(
        P.seq(P.lit("\\"), P.any),
        P.seq(P.not_look(P.alt(P.lit("/"), nl)), P.any)
    )
    local regex_literal = tok(P.seq(P.lit("/"), P.star(regex_char), P.lit("/"), P.star(regex_flag)))

    local template_char = P.alt(
        P.seq(P.lit("\\"), P.any),
        P.seq(P.not_look(P.alt(P.lit("`"), P.lit("${"))), P.any)
    )
    local template_chunk = P.alt(
        P.plus(template_char),
        P.seq(P.lit("${"), skip, P.ref("expression"), skip, P.lit("}"))
    )
    local template_literal = tok(P.seq(P.lit("`"), P.star(template_chunk), P.lit("`")))

    local comma = sym(",")
    local semi = sym(";")
    local colon = sym(":")
    local lparen, rparen = sym("("), sym(")")
    local lbrace, rbrace = sym("{"), sym("}")
    local lbrack, rbrack = sym("["), sym("]")
    local arrow = sym("=>")

    local binding_pattern = P.alt(P.ref("object_pattern"), P.ref("array_pattern"), identifier)
    local rest_binding = P.seq(sym("..."), binding_pattern)
    local binding_element = P.seq(P.alt(rest_binding, binding_pattern), P.opt(P.seq(sym("="), P.ref("assignment_expression"))))
    local object_pattern_property = P.alt(
        P.seq(sym("..."), binding_pattern),
        P.seq(P.ref("property_name"), P.opt(P.seq(colon, binding_pattern)), P.opt(P.seq(sym("="), P.ref("assignment_expression"))))
    )
    local object_pattern = P.seq(lbrace, P.opt(list(object_pattern_property, comma)), rbrace)
    local array_pattern = P.seq(lbrack, P.opt(list(P.alt(rest_binding, binding_pattern), comma)), rbrack)

    local parameter = binding_element
    local formal_parameters = P.seq(lparen, P.opt(list(parameter, comma)), rparen)
    local argument = P.alt(P.seq(sym("..."), P.ref("assignment_expression")), P.ref("assignment_expression"))
    local arguments = P.seq(lparen, P.opt(list(argument, comma)), rparen)

    local property_name = P.alt(
        P.seq(lbrack, P.ref("expression"), rbrack),
        string_literal,
        number_literal,
        property_ident,
        private_identifier
    )
    local property_definition = P.alt(
        P.seq(sym("..."), P.ref("assignment_expression")),
        P.seq(kw("get"), P.ref("property_name"), lparen, rparen, P.ref("block_statement")),
        P.seq(kw("set"), P.ref("property_name"), lparen, P.ref("parameter"), rparen, P.ref("block_statement")),
        P.seq(P.opt(kw("async")), P.opt(sym("*")), P.ref("property_name"), P.ref("formal_parameters"), P.ref("block_statement")),
        P.seq(P.ref("property_name"), colon, P.ref("assignment_expression")),
        property_ident
    )
    local object_literal = P.seq(lbrace, P.opt(list(property_definition, comma)), rbrace)
    local array_literal = P.seq(lbrack, P.opt(list(argument, comma)), rbrack)

    local import_specifier = P.seq(identifier, P.opt(P.seq(kw("as"), identifier)))
    local named_imports = P.seq(lbrace, P.opt(list(import_specifier, comma)), rbrace)
    local namespace_import = P.seq(sym("*"), kw("as"), identifier)
    local import_clause = P.alt(
        P.seq(identifier, P.opt(P.seq(comma, P.alt(named_imports, namespace_import)))),
        named_imports,
        namespace_import
    )
    local export_specifier = P.seq(identifier, P.opt(P.seq(kw("as"), identifier)))
    local export_clause = P.seq(lbrace, P.opt(list(export_specifier, comma)), rbrace)

    local variable_declarator = P.seq(binding_pattern, P.opt(P.seq(sym("="), P.ref("assignment_expression"))))
    local variable_declaration_no_semi = P.seq(P.alt(kw("var"), kw("let"), kw("const")), list(variable_declarator, comma))
    local variable_statement = P.seq(variable_declaration_no_semi, P.opt(semi))

    local function_declaration = P.seq(P.opt(kw("async")), kw("function"), P.opt(sym("*")), identifier, formal_parameters, P.ref("block_statement"))
    local function_expression = P.seq(P.opt(kw("async")), kw("function"), P.opt(sym("*")), P.opt(identifier), formal_parameters, P.ref("block_statement"))

    local class_element_name = P.alt(P.ref("property_name"), identifier, private_identifier)
    local class_field = P.seq(class_element_name, P.opt(P.seq(sym("="), P.ref("assignment_expression"))), P.opt(semi))
    local class_method = P.alt(
        P.seq(kw("get"), P.ref("class_element_name"), lparen, rparen, P.ref("block_statement")),
        P.seq(kw("set"), P.ref("class_element_name"), lparen, P.ref("parameter"), rparen, P.ref("block_statement")),
        P.seq(P.opt(kw("async")), P.opt(sym("*")), P.ref("class_element_name"), P.ref("formal_parameters"), P.ref("block_statement"))
    )
    local class_element = P.alt(
        semi,
        P.seq(kw("static"), P.ref("block_statement")),
        P.seq(P.opt(kw("static")), P.alt(class_method, class_field))
    )
    local class_body = P.seq(lbrace, P.star(P.ref("class_element")), rbrace)
    local class_declaration = P.seq(kw("class"), identifier, P.opt(P.seq(kw("extends"), P.ref("left_hand_side_expression"))), P.ref("class_body"))
    local class_expression = P.seq(kw("class"), P.opt(identifier), P.opt(P.seq(kw("extends"), P.ref("left_hand_side_expression"))), P.ref("class_body"))

    local parenthesized_expression = P.seq(lparen, P.opt(P.ref("expression")), rparen)
    local arrow_parameters = P.alt(P.seq(P.opt(kw("async")), identifier), P.seq(P.opt(kw("async")), P.ref("formal_parameters")))
    local arrow_body = P.alt(P.ref("block_statement"), P.ref("assignment_expression"))
    local arrow_expression = P.seq(P.ref("arrow_parameters"), arrow, P.ref("arrow_body"))

    local literal = P.alt(
        kw("null"), kw("undefined"), kw("true"), kw("false"),
        number_literal, string_literal, regex_literal, template_literal
    )
    local primary_expression = P.alt(
        literal,
        P.ref("object_literal"),
        P.ref("array_literal"),
        parenthesized_expression,
        P.ref("class_expression"),
        P.ref("function_expression"),
        P.ref("arrow_expression"),
        P.seq(kw("import"), P.ref("arguments")),
        kw("this"),
        kw("super"),
        identifier
    )

    local member_suffix = P.alt(
        P.seq(sym("?."), lbrack, P.ref("expression"), rbrack),
        P.seq(sym("?."), property_ident),
        P.seq(sym("?."), P.ref("arguments")),
        P.seq(sym("."), property_ident),
        P.seq(lbrack, P.ref("expression"), rbrack),
        P.ref("arguments"),
        template_literal
    )
    local left_hand_side_expression = P.seq(P.ref("primary_expression"), P.star(P.ref("member_suffix")))
    local postfix_expression = P.seq(P.ref("left_hand_side_expression"), P.opt(P.alt(sym("++"), sym("--"))))

    local unary_expression = P.alt(
        P.seq(sym("++"), P.ref("unary_expression")),
        P.seq(sym("--"), P.ref("unary_expression")),
        P.seq(sym("+"), P.ref("unary_expression")),
        P.seq(sym("-"), P.ref("unary_expression")),
        P.seq(sym("!"), P.ref("unary_expression")),
        P.seq(sym("~"), P.ref("unary_expression")),
        P.seq(kw("typeof"), P.ref("unary_expression")),
        P.seq(kw("void"), P.ref("unary_expression")),
        P.seq(kw("delete"), P.ref("unary_expression")),
        P.seq(kw("await"), P.ref("unary_expression")),
        P.seq(kw("yield"), P.opt(sym("*")), P.opt(P.ref("assignment_expression"))),
        P.seq(kw("new"), P.ref("unary_expression")),
        P.ref("postfix_expression")
    )

    local exponent_expression = P.seq(P.ref("unary_expression"), P.opt(P.seq(sym("**"), P.ref("exponent_expression"))))
    local multiplicative_expression = P.seq(P.ref("exponent_expression"), P.star(P.seq(P.alt(sym("*"), sym("/"), sym("%")), P.ref("exponent_expression"))))
    local additive_expression = P.seq(P.ref("multiplicative_expression"), P.star(P.seq(P.alt(sym("+"), sym("-")), P.ref("multiplicative_expression"))))
    local shift_expression = P.seq(P.ref("additive_expression"), P.star(P.seq(P.alt(sym(">>>"), sym(">>"), sym("<<")), P.ref("additive_expression"))))
    local relational_expression = P.seq(P.ref("shift_expression"), P.star(P.seq(P.alt(sym("<="), sym(">="), sym("<"), sym(">"), kw("instanceof"), kw("in")), P.ref("shift_expression"))))
    local equality_expression = P.seq(P.ref("relational_expression"), P.star(P.seq(P.alt(sym("!=="), sym("==="), sym("!="), sym("==")), P.ref("relational_expression"))))
    local bitwise_and_expression = P.seq(P.ref("equality_expression"), P.star(P.seq(sym("&"), P.ref("equality_expression"))))
    local bitwise_xor_expression = P.seq(P.ref("bitwise_and_expression"), P.star(P.seq(sym("^"), P.ref("bitwise_and_expression"))))
    local bitwise_or_expression = P.seq(P.ref("bitwise_xor_expression"), P.star(P.seq(sym("|"), P.ref("bitwise_xor_expression"))))
    local logical_and_expression = P.seq(P.ref("bitwise_or_expression"), P.star(P.seq(sym("&&"), P.ref("bitwise_or_expression"))))
    local logical_or_expression = P.seq(P.ref("logical_and_expression"), P.star(P.seq(sym("||"), P.ref("logical_and_expression"))))
    local nullish_expression = P.seq(P.ref("logical_or_expression"), P.star(P.seq(sym("??"), P.ref("logical_or_expression"))))
    local conditional_expression = P.seq(P.ref("nullish_expression"), P.opt(P.seq(sym("?"), P.ref("assignment_expression"), colon, P.ref("assignment_expression"))))

    local assignment_operator = P.alt(
        sym(">>>="), sym(">>="), sym("<<="), sym("**="),
        sym("&&="), sym("||="), sym("??="),
        sym("+="), sym("-="), sym("*="), sym("/="), sym("%="),
        sym("&="), sym("^="), sym("|="),
        sym("=")
    )
    local assignment_expression = P.alt(
        P.ref("arrow_expression"),
        P.seq(P.ref("left_hand_side_expression"), P.ref("assignment_operator"), P.ref("assignment_expression")),
        P.ref("conditional_expression")
    )
    local expression = P.seq(P.ref("assignment_expression"), P.star(P.seq(comma, P.ref("assignment_expression"))))

    local expression_statement = P.seq(P.ref("expression"), P.opt(semi))
    local empty_statement = semi
    local block_statement = P.seq(lbrace, P.star(P.ref("statement_item")), rbrace)
    local return_statement = P.seq(kw("return"), P.opt(P.ref("expression")), P.opt(semi))
    local throw_statement = P.seq(kw("throw"), P.ref("expression"), P.opt(semi))
    local break_statement = P.seq(kw("break"), P.opt(identifier), P.opt(semi))
    local continue_statement = P.seq(kw("continue"), P.opt(identifier), P.opt(semi))
    local debugger_statement = P.seq(kw("debugger"), P.opt(semi))
    local with_statement = P.seq(kw("with"), lparen, P.ref("expression"), rparen, P.ref("statement"))
    local if_statement = P.seq(kw("if"), lparen, P.ref("expression"), rparen, P.ref("statement"), P.opt(P.seq(kw("else"), P.ref("statement"))))
    local while_statement = P.seq(kw("while"), lparen, P.ref("expression"), rparen, P.ref("statement"))
    local do_while_statement = P.seq(kw("do"), P.ref("statement"), kw("while"), lparen, P.ref("expression"), rparen, P.opt(semi))
    local case_clause = P.alt(
        P.seq(kw("case"), P.ref("expression"), colon, P.star(P.ref("statement"))),
        P.seq(kw("default"), colon, P.star(P.ref("statement")))
    )
    local switch_statement = P.seq(kw("switch"), lparen, P.ref("expression"), rparen, lbrace, P.star(P.ref("case_clause")), rbrace)
    local catch_clause = P.seq(kw("catch"), P.opt(P.seq(lparen, binding_pattern, rparen)), P.ref("block_statement"))
    local finally_clause = P.seq(kw("finally"), P.ref("block_statement"))
    local try_statement = P.alt(
        P.seq(kw("try"), P.ref("block_statement"), P.ref("catch_clause"), P.opt(P.ref("finally_clause"))),
        P.seq(kw("try"), P.ref("block_statement"), P.ref("finally_clause"))
    )

    local for_binding = P.alt(P.ref("variable_declaration_no_semi"), P.ref("left_hand_side_expression"))
    local for_of_statement = P.seq(kw("for"), lparen, P.ref("for_binding"), kw("of"), P.ref("expression"), rparen, P.ref("statement"))
    local for_in_statement = P.seq(kw("for"), lparen, P.ref("for_binding"), kw("in"), P.ref("expression"), rparen, P.ref("statement"))
    local for_statement = P.seq(
        kw("for"), lparen,
        P.opt(P.alt(P.ref("variable_declaration_no_semi"), P.ref("expression"))), semi,
        P.opt(P.ref("expression")), semi,
        P.opt(P.ref("expression")),
        rparen,
        P.ref("statement")
    )
    local label_statement = P.seq(identifier, colon, P.ref("statement"))

    local import_statement = P.alt(
        P.seq(kw("import"), string_literal, P.opt(semi)),
        P.seq(kw("import"), P.ref("import_clause"), kw("from"), string_literal, P.opt(semi))
    )
    local export_statement = P.alt(
        P.seq(kw("export"), kw("default"), P.alt(P.ref("function_declaration"), P.ref("class_declaration"), P.ref("expression")), P.opt(semi)),
        P.seq(kw("export"), P.alt(P.ref("function_declaration"), P.ref("class_declaration"), P.ref("variable_statement"))),
        P.seq(kw("export"), sym("*"), P.opt(P.seq(kw("as"), identifier)), kw("from"), string_literal, P.opt(semi)),
        P.seq(kw("export"), P.ref("export_clause"), P.opt(P.seq(kw("from"), string_literal)), P.opt(semi))
    )

    local statement = P.alt(
        P.ref("block_statement"),
        P.ref("empty_statement"),
        P.ref("if_statement"),
        P.ref("switch_statement"),
        P.ref("for_of_statement"),
        P.ref("for_in_statement"),
        P.ref("for_statement"),
        P.ref("do_while_statement"),
        P.ref("while_statement"),
        P.ref("try_statement"),
        P.ref("with_statement"),
        P.ref("break_statement"),
        P.ref("continue_statement"),
        P.ref("return_statement"),
        P.ref("throw_statement"),
        P.ref("debugger_statement"),
        P.ref("label_statement"),
        P.ref("variable_statement"),
        P.ref("expression_statement")
    )
    local statement_item = P.alt(
        P.ref("import_statement"),
        P.ref("export_statement"),
        P.ref("function_declaration"),
        P.ref("class_declaration"),
        P.ref("statement")
    )

    local rules = {
        P.rule("start", P.seq(skip, P.star(P.ref("statement_item")), skip, P.eof)),
        P.rule("statement_item", statement_item),
        P.rule("statement", statement),
        P.rule("block_statement", block_statement),
        P.rule("empty_statement", empty_statement),
        P.rule("expression_statement", expression_statement),
        P.rule("return_statement", return_statement),
        P.rule("throw_statement", throw_statement),
        P.rule("break_statement", break_statement),
        P.rule("continue_statement", continue_statement),
        P.rule("debugger_statement", debugger_statement),
        P.rule("with_statement", with_statement),
        P.rule("if_statement", if_statement),
        P.rule("while_statement", while_statement),
        P.rule("do_while_statement", do_while_statement),
        P.rule("case_clause", case_clause),
        P.rule("switch_statement", switch_statement),
        P.rule("catch_clause", catch_clause),
        P.rule("finally_clause", finally_clause),
        P.rule("try_statement", try_statement),
        P.rule("for_binding", for_binding),
        P.rule("for_of_statement", for_of_statement),
        P.rule("for_in_statement", for_in_statement),
        P.rule("for_statement", for_statement),
        P.rule("label_statement", label_statement),
        P.rule("import_statement", import_statement),
        P.rule("import_clause", import_clause),
        P.rule("export_statement", export_statement),
        P.rule("export_clause", export_clause),
        P.rule("variable_declarator", variable_declarator),
        P.rule("variable_declaration_no_semi", variable_declaration_no_semi),
        P.rule("variable_statement", variable_statement),
        P.rule("function_declaration", function_declaration),
        P.rule("function_expression", function_expression),
        P.rule("class_declaration", class_declaration),
        P.rule("class_expression", class_expression),
        P.rule("class_body", class_body),
        P.rule("class_element", class_element),
        P.rule("class_element_name", class_element_name),
        P.rule("parameter", parameter),
        P.rule("formal_parameters", formal_parameters),
        P.rule("argument", argument),
        P.rule("arguments", arguments),
        P.rule("binding_pattern", binding_pattern),
        P.rule("object_pattern", object_pattern),
        P.rule("array_pattern", array_pattern),
        P.rule("property_name", property_name),
        P.rule("object_literal", object_literal),
        P.rule("array_literal", array_literal),
        P.rule("arrow_parameters", arrow_parameters),
        P.rule("arrow_body", arrow_body),
        P.rule("arrow_expression", arrow_expression),
        P.rule("primary_expression", primary_expression),
        P.rule("member_suffix", member_suffix),
        P.rule("left_hand_side_expression", left_hand_side_expression),
        P.rule("postfix_expression", postfix_expression),
        P.rule("unary_expression", unary_expression),
        P.rule("exponent_expression", exponent_expression),
        P.rule("multiplicative_expression", multiplicative_expression),
        P.rule("additive_expression", additive_expression),
        P.rule("shift_expression", shift_expression),
        P.rule("relational_expression", relational_expression),
        P.rule("equality_expression", equality_expression),
        P.rule("bitwise_and_expression", bitwise_and_expression),
        P.rule("bitwise_xor_expression", bitwise_xor_expression),
        P.rule("bitwise_or_expression", bitwise_or_expression),
        P.rule("logical_and_expression", logical_and_expression),
        P.rule("logical_or_expression", logical_or_expression),
        P.rule("nullish_expression", nullish_expression),
        P.rule("conditional_expression", conditional_expression),
        P.rule("assignment_operator", assignment_operator),
        P.rule("assignment_expression", assignment_expression),
        P.rule("expression", expression),
    }

    return P.grammar(rules, "start")
end
