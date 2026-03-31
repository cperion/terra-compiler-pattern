local M = {}

local function flatten_spine(node, head_key, tail_key)
    if node == nil then return {} end
    local out = {}
    local cur = node
    while cur do
        out[#out + 1] = cur[head_key]
        cur = cur[tail_key]
    end
    return out
end

local function make_target_ctx(T)
    return {
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
                    return { kind = "JsonSpec", root = value }
                end,
            }),
            Pair = function(key, value)
                return { kind = "JsonPair", key = key, value = value }
            end,
            PairListNode = function(head, tail)
                return { kind = "JsonPairList", head = head, tail = tail }
            end,
            ValueListNode = function(head, tail)
                return { kind = "JsonValueList", head = head, tail = tail }
            end,
            Object = function(entries)
                return {
                    kind = "JsonObject",
                    entries = flatten_spine(entries, "head", "tail"),
                }
            end,
            Array = function(items)
                return {
                    kind = "JsonArray",
                    items = flatten_spine(items, "head", "tail"),
                }
            end,
            StringValue = function(value)
                return { kind = "JsonString", value = value }
            end,
            NumberValue = function(text)
                return { kind = "JsonNumber", text = text, value = tonumber(text) }
            end,
            TrueValue = function()
                return { kind = "JsonBool", value = true }
            end,
            FalseValue = function()
                return { kind = "JsonBool", value = false }
            end,
            NullValue = function()
                return { kind = "JsonNull" }
            end,
        },
    }
end

function M.new_source_spec_and_target_ctx(T)
    local target_ctx = make_target_ctx(T)

    local source = T.FrontendSource.Spec(
        T.FrontendSource.Target(
            "TargetText.Spec",
            "tokenize",
            "TargetToken.Spec",
            "parse",
            "TargetToken.Spec",
            "TargetToken.Cell",
            "TargetToken.Span",
            "TargetSource.Spec"
        ),
        T.FrontendSource.Lexer(
            {
                T.FrontendSource.WhitespaceSkip,
            },
            {
                T.FrontendSource.KeywordToken("TrueKw", "true"),
                T.FrontendSource.KeywordToken("FalseKw", "false"),
                T.FrontendSource.KeywordToken("NullKw", "null"),
                T.FrontendSource.PunctToken("LBrace", "{"),
                T.FrontendSource.PunctToken("RBrace", "}"),
                T.FrontendSource.PunctToken("LBracket", "["),
                T.FrontendSource.PunctToken("RBracket", "]"),
                T.FrontendSource.PunctToken("Colon", ":"),
                T.FrontendSource.PunctToken("Comma", ","),
                T.FrontendSource.QuotedStringToken("String", '"', true),
                T.FrontendSource.NumberToken("Number"),
            }
        ),
        T.FrontendSource.Parser(
            "value",
            {
                T.FrontendSource.Rule(
                    "value",
                    T.FrontendSource.Capture(
                        "value",
                        T.FrontendSource.Choice({
                            T.FrontendSource.RuleRef("object"),
                            T.FrontendSource.RuleRef("array"),
                            T.FrontendSource.RuleRef("string"),
                            T.FrontendSource.RuleRef("number"),
                            T.FrontendSource.RuleRef("true_lit"),
                            T.FrontendSource.RuleRef("false_lit"),
                            T.FrontendSource.RuleRef("null_lit"),
                        })
                    ),
                    T.FrontendSource.ReturnCapture("value")
                ),
                T.FrontendSource.Rule(
                    "object",
                    T.FrontendSource.Capture(
                        "value",
                        T.FrontendSource.Build(
                            T.FrontendSource.Seq({
                                T.FrontendSource.TokenRef("LBrace"),
                                T.FrontendSource.Capture("entries", T.FrontendSource.Optional(T.FrontendSource.RuleRef("pair_list"))),
                                T.FrontendSource.TokenRef("RBrace"),
                            }),
                            T.FrontendSource.ReturnCtor(
                                "TargetSource.Object",
                                {
                                    T.FrontendSource.FieldResult("entries", T.FrontendSource.CaptureSource("entries")),
                                }
                            )
                        )
                    ),
                    T.FrontendSource.ReturnCapture("value")
                ),
                T.FrontendSource.Rule(
                    "pair_list",
                    T.FrontendSource.Capture(
                        "value",
                        T.FrontendSource.Build(
                            T.FrontendSource.Seq({
                                T.FrontendSource.Capture("head", T.FrontendSource.RuleRef("pair")),
                                T.FrontendSource.Capture("tail", T.FrontendSource.Optional(T.FrontendSource.RuleRef("pair_list_tail"))),
                            }),
                            T.FrontendSource.ReturnCtor(
                                "TargetSource.PairListNode",
                                {
                                    T.FrontendSource.FieldResult("head", T.FrontendSource.CaptureSource("head")),
                                    T.FrontendSource.FieldResult("tail", T.FrontendSource.CaptureSource("tail")),
                                }
                            )
                        )
                    ),
                    T.FrontendSource.ReturnCapture("value")
                ),
                T.FrontendSource.Rule(
                    "pair_list_tail",
                    T.FrontendSource.Capture(
                        "value",
                        T.FrontendSource.Build(
                            T.FrontendSource.Seq({
                                T.FrontendSource.TokenRef("Comma"),
                                T.FrontendSource.Capture("tail", T.FrontendSource.RuleRef("pair_list")),
                            }),
                            T.FrontendSource.ReturnCapture("tail")
                        )
                    ),
                    T.FrontendSource.ReturnCapture("value")
                ),
                T.FrontendSource.Rule(
                    "pair",
                    T.FrontendSource.Capture(
                        "value",
                        T.FrontendSource.Build(
                            T.FrontendSource.Seq({
                                T.FrontendSource.Capture("key", T.FrontendSource.TokenRef("String")),
                                T.FrontendSource.TokenRef("Colon"),
                                T.FrontendSource.Capture("value", T.FrontendSource.RuleRef("value")),
                            }),
                            T.FrontendSource.ReturnCtor(
                                "TargetSource.Pair",
                                {
                                    T.FrontendSource.FieldResult("key", T.FrontendSource.CaptureSource("key")),
                                    T.FrontendSource.FieldResult("value", T.FrontendSource.CaptureSource("value")),
                                }
                            )
                        )
                    ),
                    T.FrontendSource.ReturnCapture("value")
                ),
                T.FrontendSource.Rule(
                    "array",
                    T.FrontendSource.Capture(
                        "value",
                        T.FrontendSource.Build(
                            T.FrontendSource.Seq({
                                T.FrontendSource.TokenRef("LBracket"),
                                T.FrontendSource.Capture("items", T.FrontendSource.Optional(T.FrontendSource.RuleRef("value_list"))),
                                T.FrontendSource.TokenRef("RBracket"),
                            }),
                            T.FrontendSource.ReturnCtor(
                                "TargetSource.Array",
                                {
                                    T.FrontendSource.FieldResult("items", T.FrontendSource.CaptureSource("items")),
                                }
                            )
                        )
                    ),
                    T.FrontendSource.ReturnCapture("value")
                ),
                T.FrontendSource.Rule(
                    "value_list",
                    T.FrontendSource.Capture(
                        "value",
                        T.FrontendSource.Build(
                            T.FrontendSource.Seq({
                                T.FrontendSource.Capture("head", T.FrontendSource.RuleRef("value")),
                                T.FrontendSource.Capture("tail", T.FrontendSource.Optional(T.FrontendSource.RuleRef("value_list_tail"))),
                            }),
                            T.FrontendSource.ReturnCtor(
                                "TargetSource.ValueListNode",
                                {
                                    T.FrontendSource.FieldResult("head", T.FrontendSource.CaptureSource("head")),
                                    T.FrontendSource.FieldResult("tail", T.FrontendSource.CaptureSource("tail")),
                                }
                            )
                        )
                    ),
                    T.FrontendSource.ReturnCapture("value")
                ),
                T.FrontendSource.Rule(
                    "value_list_tail",
                    T.FrontendSource.Capture(
                        "value",
                        T.FrontendSource.Build(
                            T.FrontendSource.Seq({
                                T.FrontendSource.TokenRef("Comma"),
                                T.FrontendSource.Capture("tail", T.FrontendSource.RuleRef("value_list")),
                            }),
                            T.FrontendSource.ReturnCapture("tail")
                        )
                    ),
                    T.FrontendSource.ReturnCapture("value")
                ),
                T.FrontendSource.Rule(
                    "string",
                    T.FrontendSource.Seq({
                        T.FrontendSource.Capture("text", T.FrontendSource.TokenRef("String")),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.StringValue",
                        {
                            T.FrontendSource.FieldResult("value", T.FrontendSource.CaptureSource("text")),
                        }
                    )
                ),
                T.FrontendSource.Rule(
                    "number",
                    T.FrontendSource.Seq({
                        T.FrontendSource.Capture("text", T.FrontendSource.TokenRef("Number")),
                    }),
                    T.FrontendSource.ReturnCtor(
                        "TargetSource.NumberValue",
                        {
                            T.FrontendSource.FieldResult("text", T.FrontendSource.CaptureSource("text")),
                        }
                    )
                ),
                T.FrontendSource.Rule(
                    "true_lit",
                    T.FrontendSource.Seq({ T.FrontendSource.TokenRef("TrueKw") }),
                    T.FrontendSource.ReturnCtor("TargetSource.TrueValue", {})
                ),
                T.FrontendSource.Rule(
                    "false_lit",
                    T.FrontendSource.Seq({ T.FrontendSource.TokenRef("FalseKw") }),
                    T.FrontendSource.ReturnCtor("TargetSource.FalseValue", {})
                ),
                T.FrontendSource.Rule(
                    "null_lit",
                    T.FrontendSource.Seq({ T.FrontendSource.TokenRef("NullKw") }),
                    T.FrontendSource.ReturnCtor("TargetSource.NullValue", {})
                ),
            }
        )
    )

    return source, target_ctx
end

return M
