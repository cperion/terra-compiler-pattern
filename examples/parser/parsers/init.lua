local function build(name, T)
    return require("examples.parser.parsers." .. name)(T._parser_builder)
end

return {
    names = {
        "json", "csv", "http", "http_response",
        "asdl", "sql", "ini", "s_expr", "uri",
        "ecmascript",
    },

    json = function(T) return build("json", T) end,
    csv  = function(T) return build("csv", T) end,
    http = function(T) return build("http", T) end,
    http_response = function(T) return build("http_response", T) end,
    asdl = function(T) return build("asdl", T) end,
    sql  = function(T) return build("sql", T) end,
    ini  = function(T) return build("ini", T) end,
    s_expr = function(T) return build("s_expr", T) end,
    uri  = function(T) return build("uri", T) end,
    ecmascript = function(T) return build("ecmascript", T) end,
}
