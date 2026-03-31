local M = {}

local bit = require("bit")

local function bits_for(pred)
    local words = { 0, 0, 0, 0, 0, 0, 0, 0 }
    for c = 0, 255 do
        if pred(c) then
            local wi = math.floor(c / 32) + 1
            words[wi] = bit.bor(words[wi], bit.lshift(1, c % 32))
        end
    end
    return words
end

local function base_components(T)
    local function Path(...)
        return T.FrontendMachine.Path({ ... })
    end

    local function Header(name, id, payload_shape)
        return T.FrontendChecked.TokenHeader(name, id, payload_shape)
    end

    local no_payload = T.FrontendChecked.NoTokenPayload
    local string_payload = T.FrontendChecked.StringTokenPayload
    local string_value = T.FrontendChecked.StringValue

    local module_header = Header("ModuleKw", 1, no_payload)
    local lbrace_header = Header("LBrace", 2, no_payload)
    local rbrace_header = Header("RBrace", 3, no_payload)
    local ident_header = Header("Ident", 4, string_payload)
    local eof_header = Header("Eof", 5, no_payload)

    local target = T.FrontendSource.Target(
        "TargetText.Spec",
        "tokenize",
        "TargetToken.Spec",
        "parse",
        "TargetToken.Spec",
        "TargetToken.Cell",
        "TargetToken.Span",
        "TargetSource.Spec"
    )

    local first_set_words = bits_for(function(c)
        return c == 1
    end)

    local target_ctx = {
        TargetText = { Spec = {} },
        TargetToken = {
            Span = function(start_byte, end_byte)
                return { start_byte = start_byte, end_byte = end_byte }
            end,
            Cell = function(token_id, text, span)
                return {
                    kind = "TokenCell",
                    token_id = token_id,
                    text = text,
                    span = span,
                }
            end,
            Spec = setmetatable({}, {
                __call = function(_, items)
                    return { kind = "TokenSpec", items = items, tokens = items }
                end,
            }),
        },
        TargetSource = {
            Spec = setmetatable({}, {
                __call = function(_, value)
                    return { kind = "SourceSpec", root = value }
                end,
            }),
            Document = function(name, inner)
                return { kind = "Document", name = name, inner = inner }
            end,
        },
    }

    return {
        Path = Path,
        no_payload = no_payload,
        string_payload = string_payload,
        string_value = string_value,
        module_header = module_header,
        lbrace_header = lbrace_header,
        rbrace_header = rbrace_header,
        ident_header = ident_header,
        eof_header = eof_header,
        target = target,
        first_set_words = first_set_words,
        target_ctx = target_ctx,
    }
end

function M.new_tokenize_machine_and_target_ctx(T)
    local c = base_components(T)
    local Path = c.Path

    local machine = T.FrontendMachine.Spec(
        T.FrontendMachine.TokenizeInstall(
            T.FrontendMachine.BoundaryHeader(Path("TargetText", "Spec"), "tokenize"),
            Path("TargetToken", "Spec"),
            Path("TargetToken", "Cell"),
            Path("TargetToken", "Span"),
            T.FrontendLowered.TokenizeMachine(
                c.eof_header,
                {
                    T.FrontendLowered.WhitespaceSkip,
                    T.FrontendLowered.LineCommentSkip("#"),
                },
                {
                    T.FrontendLowered.FixedDispatch(109, {
                        T.FrontendLowered.FixedCase("module", c.module_header, true),
                    }),
                    T.FrontendLowered.FixedDispatch(123, {
                        T.FrontendLowered.FixedCase("{", c.lbrace_header, false),
                    }),
                    T.FrontendLowered.FixedDispatch(125, {
                        T.FrontendLowered.FixedCase("}", c.rbrace_header, false),
                    }),
                },
                {
                    T.FrontendLowered.IdentDispatch(
                        c.ident_header,
                        bits_for(function(ch)
                            return ch == 95 or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122)
                        end),
                        bits_for(function(ch)
                            return ch == 95 or (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122)
                        end)
                    ),
                },
                {},
                {}
            )
        ),
        T.FrontendMachine.ParseInstall(
            T.FrontendMachine.BoundaryHeader(Path("TargetToken", "Spec"), "parse"),
            Path("TargetSource", "Spec"),
            {
                T.FrontendMachine.CtorRef(1, Path("TargetSource", "Document")),
            },
            T.FrontendLowered.ParseMachine(
                T.FrontendChecked.RuleHeader("entry", 1),
                {
                    T.FrontendLowered.ResultCtor(
                        1,
                        T.FrontendChecked.CtorTarget(
                            "TargetSource.Document",
                            {
                                T.FrontendChecked.TargetField("name", c.string_value),
                                T.FrontendChecked.TargetField("inner", c.string_value),
                            }
                        )
                    ),
                },
                {
                    T.FrontendLowered.FirstSetTable(1, c.first_set_words),
                },
                {
                    T.FrontendLowered.RulePlan(
                        T.FrontendChecked.RuleHeader("entry", 1),
                        T.FrontendLowered.SeqRuleKind,
                        {
                            T.FrontendLowered.ExpectToken(c.module_header, 0),
                            T.FrontendLowered.ExpectToken(c.ident_header, 1),
                            T.FrontendLowered.ExpectToken(c.lbrace_header, 0),
                            T.FrontendLowered.ExpectToken(c.ident_header, 2),
                            T.FrontendLowered.ExpectToken(c.rbrace_header, 0),
                        },
                        {},
                        T.FrontendLowered.ReturnCtor(1, {
                            T.FrontendLowered.ReadSlot(1),
                            T.FrontendLowered.ReadSlot(2),
                        })
                    ),
                }
            )
        )
    )

    return machine, c.target_ctx
end

function M.new_source_spec_and_target_ctx(T)
    local c = base_components(T)

    local source = T.FrontendSource.Spec(
        c.target,
        T.FrontendSource.Lexer(
            {
                T.FrontendSource.WhitespaceSkip,
                T.FrontendSource.LineCommentSkip("#"),
            },
            {
                T.FrontendSource.KeywordToken("ModuleKw", "module"),
                T.FrontendSource.PunctToken("LBrace", "{"),
                T.FrontendSource.PunctToken("RBrace", "}"),
                T.FrontendSource.IdentToken(
                    "Ident",
                    T.FrontendSource.Union({ T.FrontendSource.AsciiLetters, T.FrontendSource.Underscore }),
                    T.FrontendSource.Union({ T.FrontendSource.AsciiLetters, T.FrontendSource.AsciiDigits, T.FrontendSource.Underscore })
                ),
            }
        ),
        T.FrontendSource.Parser(
            "entry",
            {
                T.FrontendSource.Rule(
                    "entry",
                    T.FrontendSource.Seq({
                        T.FrontendSource.TokenRef("ModuleKw"),
                        T.FrontendSource.Capture("name", T.FrontendSource.TokenRef("Ident")),
                        T.FrontendSource.TokenRef("LBrace"),
                        T.FrontendSource.Capture("inner", T.FrontendSource.TokenRef("Ident")),
                        T.FrontendSource.TokenRef("RBrace"),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.Document",
                        {
                            T.FrontendSource.FieldResult("name", T.FrontendSource.CaptureSource("name")),
                            T.FrontendSource.FieldResult("inner", T.FrontendSource.CaptureSource("inner")),
                        }
                    )
                ),
            }
        )
    )

    return source, c.target_ctx
end

function M.new_lowered_spec_and_target_ctx(T)
    local c = base_components(T)

    local lowered = T.FrontendLowered.Spec(
        c.target,
        T.FrontendLowered.TokenizeMachine(
            c.eof_header,
            {
                T.FrontendLowered.WhitespaceSkip,
                T.FrontendLowered.LineCommentSkip("#"),
            },
            {
                T.FrontendLowered.FixedDispatch(109, {
                    T.FrontendLowered.FixedCase("module", c.module_header, true),
                }),
                T.FrontendLowered.FixedDispatch(123, {
                    T.FrontendLowered.FixedCase("{", c.lbrace_header, false),
                }),
                T.FrontendLowered.FixedDispatch(125, {
                    T.FrontendLowered.FixedCase("}", c.rbrace_header, false),
                }),
            },
            {
                T.FrontendLowered.IdentDispatch(
                    c.ident_header,
                    bits_for(function(ch)
                        return ch == 95 or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122)
                    end),
                    bits_for(function(ch)
                        return ch == 95 or (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122)
                    end)
                ),
            },
            {},
            {}
        ),
        T.FrontendLowered.ParseMachine(
            T.FrontendChecked.RuleHeader("entry", 1),
            {
                T.FrontendLowered.ResultCtor(
                    1,
                    T.FrontendChecked.CtorTarget(
                        "TargetSource.Document",
                        {
                            T.FrontendChecked.TargetField("name", c.string_value),
                            T.FrontendChecked.TargetField("inner", c.string_value),
                        }
                    )
                ),
            },
            {
                T.FrontendLowered.FirstSetTable(1, c.first_set_words),
            },
            {
                T.FrontendLowered.RulePlan(
                    T.FrontendChecked.RuleHeader("entry", 1),
                    T.FrontendLowered.SeqRuleKind,
                    {
                        T.FrontendLowered.ExpectToken(c.module_header, 0),
                        T.FrontendLowered.ExpectToken(c.ident_header, 1),
                        T.FrontendLowered.ExpectToken(c.lbrace_header, 0),
                        T.FrontendLowered.ExpectToken(c.ident_header, 2),
                        T.FrontendLowered.ExpectToken(c.rbrace_header, 0),
                    },
                    {},
                    T.FrontendLowered.ReturnCtor(1, {
                        T.FrontendLowered.ReadSlot(1),
                        T.FrontendLowered.ReadSlot(2),
                    })
                ),
            }
        )
    )

    return lowered, c.target_ctx
end

return M
