local ffi = require("ffi")
local asdl = require("asdl")
local L = asdl.List

local function S(v)
    if type(v) == "cdata" then return ffi.string(v) end
    return v
end

local KEYWORDS = {}
for _, w in ipairs({
    "await", "break", "case", "catch", "class", "const", "continue",
    "debugger", "default", "delete", "do", "else", "export", "extends",
    "finally", "for", "function", "if", "import", "in", "instanceof",
    "let", "new", "return", "static", "super", "switch", "this",
    "throw", "try", "typeof", "var", "void", "while", "with", "yield",
    "async", "of", "null", "true", "false", "undefined",
}) do KEYWORDS[w] = true end

local PUNCT = {
    ">>>=", "!==", "===", ">>>", "<<=", ">>=", "**=",
    "&&=", "||=", "??=", "...", "?.", "=>",
    "++", "--", "**", "<<", ">>", "<=", ">=", "==", "!=",
    "+=", "-=", "*=", "/=", "%=", "&=", "^=", "|=", "&&", "||", "??",
    "{", "}", "[", "]", "(", ")", ".", ";", ",", ":", "?", "~",
    "+", "-", "*", "/", "%", "<", ">", "=", "!", "&", "|", "^", "#",
}

local function is_alpha(c)
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c == "$"
end

local function is_digit(c)
    return c >= "0" and c <= "9"
end

local function is_alnum(c)
    return is_alpha(c) or is_digit(c)
end

local function can_start_regex(prev)
    if not prev then return true end
    if prev.kind == "Punct" then
        local p = prev.text
        return p ~= ")" and p ~= "]" and p ~= "}" and p ~= "++" and p ~= "--"
    end
    return prev.kind ~= "Identifier" and prev.kind ~= "Keyword"
end

local function unescape_js_string(raw)
    raw = S(raw)
    local quote = raw:sub(1, 1)
    local body = raw:sub(2, -2)
    local out = {}
    local i = 1
    while i <= #body do
        local c = body:sub(i, i)
        if c == "\\" then
            local n = body:sub(i + 1, i + 1)
            if n == "n" then out[#out + 1] = "\n"
            elseif n == "r" then out[#out + 1] = "\r"
            elseif n == "t" then out[#out + 1] = "\t"
            elseif n == quote then out[#out + 1] = quote
            elseif n == "\\" then out[#out + 1] = "\\"
            else out[#out + 1] = n end
            i = i + 2
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

local function split_template_parts(raw)
    raw = S(raw)
    local body = raw:sub(2, -2)
    local parts = {}
    local current = {}
    local i = 1
    while i <= #body do
        local c = body:sub(i, i)
        local n = body:sub(i + 1, i + 1)
        if c == "\\" then
            current[#current + 1] = c
            current[#current + 1] = n
            i = i + 2
        elseif c == "$" and n == "{" then
            if #current > 0 then
                parts[#parts + 1] = { type = "str", value = table.concat(current) }
                current = {}
            end
            i = i + 2
            local depth = 1
            local start = i
            while i <= #body and depth > 0 do
                local ch = body:sub(i, i)
                if ch == "{" then depth = depth + 1
                elseif ch == "}" then depth = depth - 1 end
                i = i + 1
            end
            parts[#parts + 1] = { type = "expr", value = body:sub(start, i - 2) }
        else
            current[#current + 1] = c
            i = i + 1
        end
    end
    if #current > 0 then
        parts[#parts + 1] = { type = "str", value = table.concat(current) }
    end
    return parts
end

local function lex_source(T, source)
    local J = T.JsLex
    local tokens = L{}
    local pos = 1
    local len = #source
    local prev_significant = nil

    local function peek(offset)
        local i = pos + (offset or 0)
        if i > len then return "" end
        return source:sub(i, i)
    end

    local function add(tok)
        tokens[#tokens + 1] = tok
        if tok.kind ~= "Comment" then prev_significant = tok end
    end

    local function skip_space()
        while pos <= len do
            local c = peek()
            if c == " " or c == "\t" or c == "\r" or c == "\n" then
                pos = pos + 1
            else
                return
            end
        end
    end

    while true do
        skip_space()
        if pos > len then break end

        local c = peek()
        local start = pos

        if c == "/" and peek(1) == "/" then
            pos = pos + 2
            while pos <= len and peek() ~= "\n" do pos = pos + 1 end
            add(J.Comment(source:sub(start + 2, pos - 1), false, start, pos - 1))

        elseif c == "/" and peek(1) == "*" then
            pos = pos + 2
            while pos <= len do
                if peek() == "*" and peek(1) == "/" then
                    local stop = pos + 1
                    pos = pos + 2
                    add(J.Comment(source:sub(start + 2, stop - 1), true, start, stop))
                    break
                end
                pos = pos + 1
            end

        elseif (c == '"' or c == "'") then
            local quote = c
            pos = pos + 1
            while pos <= len do
                local ch = peek()
                if ch == "\\" then
                    pos = pos + 2
                elseif ch == quote then
                    local stop = pos
                    pos = pos + 1
                    add(J.String(source:sub(start, stop), start, stop))
                    break
                else
                    pos = pos + 1
                end
            end

        elseif c == "`" then
            pos = pos + 1
            while pos <= len do
                local ch = peek()
                if ch == "\\" then
                    pos = pos + 2
                elseif ch == "`" then
                    local stop = pos
                    pos = pos + 1
                    add(J.Template(source:sub(start, stop), start, stop))
                    break
                else
                    pos = pos + 1
                end
            end

        elseif c == "/" and can_start_regex(prev_significant) then
            pos = pos + 1
            while pos <= len do
                local ch = peek()
                if ch == "\\" then
                    pos = pos + 2
                elseif ch == "/" then
                    local pat_stop = pos - 1
                    pos = pos + 1
                    local flag_start = pos
                    while pos <= len and peek():match("[gimsuyd]") do pos = pos + 1 end
                    local flags = source:sub(flag_start, pos - 1)
                    local pattern = source:sub(start + 1, pat_stop)
                    add(J.Regex(pattern, flags, start, pos - 1))
                    break
                else
                    pos = pos + 1
                end
            end

        elseif is_digit(c) or (c == "." and is_digit(peek(1))) then
            if c == "0" and (peek(1) == "x" or peek(1) == "X") then
                pos = pos + 2
                while pos <= len and peek():match("[%da-fA-F]") do pos = pos + 1 end
            elseif c == "0" and (peek(1) == "o" or peek(1) == "O") then
                pos = pos + 2
                while pos <= len and peek():match("[0-7]") do pos = pos + 1 end
            elseif c == "0" and (peek(1) == "b" or peek(1) == "B") then
                pos = pos + 2
                while pos <= len and peek():match("[01]") do pos = pos + 1 end
            else
                while pos <= len and is_digit(peek()) do pos = pos + 1 end
                if peek() == "." then
                    pos = pos + 1
                    while pos <= len and is_digit(peek()) do pos = pos + 1 end
                end
                if peek() == "e" or peek() == "E" then
                    pos = pos + 1
                    if peek() == "+" or peek() == "-" then pos = pos + 1 end
                    while pos <= len and is_digit(peek()) do pos = pos + 1 end
                end
            end
            if peek() == "n" then pos = pos + 1 end
            add(J.Number(source:sub(start, pos - 1), start, pos - 1))

        elseif is_alpha(c) then
            pos = pos + 1
            while pos <= len and is_alnum(peek()) do pos = pos + 1 end
            local word = source:sub(start, pos - 1)
            if KEYWORDS[word] then
                add(J.Keyword(word, start, pos - 1))
            else
                add(J.Identifier(word, start, pos - 1))
            end

        else
            local matched = nil
            for i = 1, #PUNCT do
                local p = PUNCT[i]
                if source:sub(pos, pos + #p - 1) == p then
                    matched = p
                    break
                end
            end
            if not matched then
                error("js_lex: unknown character '" .. c .. "' at byte " .. start)
            end
            pos = pos + #matched
            add(J.Punct(matched, start, pos - 1))
        end
    end

    add(J.EOF(pos, pos))
    return J.TokenStream(tokens)
end

local function to_legacy_tokens(stream)
    local out = {}
    for i = 1, #stream.tokens do
        local tok = stream.tokens[i]
        if tok.kind == "Identifier" or tok.kind == "Keyword" then
            out[#out + 1] = { type = "ident", value = S(tok.text) }
        elseif tok.kind == "Number" then
            out[#out + 1] = { type = "number", value = tonumber(S(tok.raw)) }
        elseif tok.kind == "String" then
            out[#out + 1] = { type = "string", value = unescape_js_string(tok.raw) }
        elseif tok.kind == "Template" then
            out[#out + 1] = { type = "template", parts = split_template_parts(tok.raw) }
        elseif tok.kind == "Regex" then
            out[#out + 1] = { type = "regex", pattern = S(tok.pattern), flags = S(tok.flags) }
        elseif tok.kind == "Punct" then
            out[#out + 1] = { type = S(tok.text) }
        elseif tok.kind == "EOF" then
            out[#out + 1] = { type = "eof" }
        end
    end
    return out
end

return {
    install = function(T)
        T.JsLex.lex = function(source)
            return lex_source(T, source)
        end
        T.JsLex.to_legacy_tokens = to_legacy_tokens
    end,
}
