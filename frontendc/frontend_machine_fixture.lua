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

    local function Header(name, id, value_shape)
        return T.FrontendChecked.TokenHeader(name, id, value_shape)
    end

    local no_value = T.FrontendChecked.NoValue
    local string_value = T.FrontendChecked.StringValue

    local module_header = Header("ModuleKw", 1, no_value)
    local lbrace_header = Header("LBrace", 2, no_value)
    local rbrace_header = Header("RBrace", 3, no_value)
    local ident_header = Header("Ident", 4, no_value)
    local eof_header = Header("Eof", 5, no_value)

    local target = T.FrontendSource.BoundaryTarget(
        "TargetText.Spec",
        "tokenize",
        "TargetToken.Spec",
        "parse",
        "TargetToken",
        "TargetToken.Spec",
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
            Spec = setmetatable({}, {
                __call = function(_, tokens)
                    return { kind = "TokenSpec", tokens = tokens }
                end,
            }),
            ModuleKw = function(span)
                return { kind = "ModuleKw", span = span }
            end,
            LBrace = function(span)
                return { kind = "LBrace", span = span }
            end,
            RBrace = function(span)
                return { kind = "RBrace", span = span }
            end,
            Ident = function(text, span)
                return { kind = "Ident", text = text, span = span }
            end,
            Eof = function(span)
                return { kind = "Eof", span = span }
            end,
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
        no_value = no_value,
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

    local tokenize_header = T.FrontendMachine.BoundaryHeader(Path("TargetText", "Spec"), "tokenize")
    local parse_header = T.FrontendMachine.BoundaryHeader(Path("TargetToken", "Spec"), "parse")

    local machine = T.FrontendMachine.Spec(
        T.FrontendMachine.TokenizeBoundary(
            tokenize_header,
            Path("TargetToken", "Spec"),
            Path("TargetToken", "Span"),
            {
                T.FrontendMachine.CtorRef(1, Path("TargetToken", "ModuleKw")),
                T.FrontendMachine.CtorRef(2, Path("TargetToken", "LBrace")),
                T.FrontendMachine.CtorRef(3, Path("TargetToken", "RBrace")),
                T.FrontendMachine.CtorRef(4, Path("TargetToken", "Ident")),
                T.FrontendMachine.CtorRef(5, Path("TargetToken", "Eof")),
            },
            5,
            {
                T.FrontendLowered.WhitespaceSkip,
                T.FrontendLowered.LineCommentSkip("#"),
            },
            {
                T.FrontendMachine.FixedDispatch(109, {
                    T.FrontendMachine.FixedCase("module", c.module_header, true),
                }),
                T.FrontendMachine.FixedDispatch(123, {
                    T.FrontendMachine.FixedCase("{", c.lbrace_header, false),
                }),
                T.FrontendMachine.FixedDispatch(125, {
                    T.FrontendMachine.FixedCase("}", c.rbrace_header, false),
                }),
            },
            {
                T.FrontendMachine.IdentDispatch(
                    c.ident_header,
                    bits_for(function(ch)
                        return ch == 95 or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122)
                    end),
                    bits_for(function(ch)
                        return ch == 95 or (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122)
                    end)
                ),
            }
        ),
        T.FrontendMachine.ParseBoundary(
            parse_header,
            Path("TargetSource", "Spec"),
            {
                T.FrontendMachine.CtorRef(1, Path("TargetSource", "Document")),
            },
            {
                T.FrontendMachine.FirstSetTable(1, c.first_set_words),
            },
            {
                T.FrontendMachine.SeqRule(
                    1,
                    {
                        T.FrontendMachine.ExpectToken(c.module_header, 0),
                        T.FrontendMachine.ExpectToken(c.ident_header, 1),
                        T.FrontendMachine.ExpectToken(c.lbrace_header, 0),
                        T.FrontendMachine.ExpectToken(c.ident_header, 2),
                        T.FrontendMachine.ExpectToken(c.rbrace_header, 0),
                    },
                    T.FrontendMachine.ReturnCtor(1, {
                        T.FrontendMachine.ReadSlot(1),
                        T.FrontendMachine.ReadSlot(2),
                    })
                ),
            },
            1
        )
    )

    return machine, c.target_ctx
end

function M.new_lowered_spec_and_target_ctx(T)
    local c = base_components(T)

    local lowered = T.FrontendLowered.Spec(
        c.target,
        T.FrontendLowered.Tokenizer(
            {
                T.FrontendLowered.WhitespaceSkip,
                T.FrontendLowered.LineCommentSkip("#"),
            },
            {
                T.FrontendLowered.FixedToken(c.module_header, "module"),
                T.FrontendLowered.FixedToken(c.lbrace_header, "{"),
                T.FrontendLowered.FixedToken(c.rbrace_header, "}"),
                T.FrontendLowered.IdentToken(
                    c.ident_header,
                    T.FrontendSource.Union({ T.FrontendSource.AsciiLetters, T.FrontendSource.Underscore }),
                    T.FrontendSource.Union({ T.FrontendSource.AsciiLetters, T.FrontendSource.AsciiDigits, T.FrontendSource.Underscore })
                ),
                T.FrontendLowered.FixedToken(c.eof_header, ""),
            }
        ),
        T.FrontendLowered.Parser(
            T.FrontendChecked.RuleHeader("entry", 1),
            {
                T.FrontendLowered.RulePlan(
                    T.FrontendChecked.RuleHeader("entry", 1),
                    {
                        T.FrontendLowered.ExpectToken(c.module_header, 0),
                        T.FrontendLowered.ExpectToken(c.ident_header, 1),
                        T.FrontendLowered.ExpectToken(c.lbrace_header, 0),
                        T.FrontendLowered.ExpectToken(c.ident_header, 2),
                        T.FrontendLowered.ExpectToken(c.rbrace_header, 0),
                    },
                    T.FrontendLowered.ReturnCtor(
                        T.FrontendChecked.CtorTarget(
                            "TargetSource.Document",
                            {
                                T.FrontendChecked.TargetField("name", c.string_value),
                                T.FrontendChecked.TargetField("inner", c.string_value),
                            }
                        ),
                        {
                            T.FrontendLowered.FieldPlan("name", T.FrontendLowered.ReadSlot(1)),
                            T.FrontendLowered.FieldPlan("inner", T.FrontendLowered.ReadSlot(2)),
                        }
                    )
                ),
            }
        )
    )

    return lowered, c.target_ctx
end

return M
