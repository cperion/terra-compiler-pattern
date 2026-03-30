-- js_parse.lua
--
-- Parser: text -> JsSource
-- ----------------------------------------------------------------------------
-- Recursive descent parser for a practical JS subset.
-- Produces JsSource ASDL nodes directly.
--
-- This is the frontend. It converts text into the source program.
-- No semantic analysis happens here — that's the resolver's job.

local U = require("unit")
local asdl = require("asdl")
local L = asdl.List

-- ═══════════════════════════════════════════════════════════════
-- Lexer
-- ═══════════════════════════════════════════════════════════════

local KEYWORDS = {}
for _, w in ipairs({
    "var", "let", "const", "function", "return", "if", "else",
    "while", "do", "switch", "case", "default", "for", "in", "of",
    "break", "continue", "throw", "try", "catch", "finally", "new",
    "typeof", "instanceof", "void", "delete", "this", "null", "undefined",
    "true", "false", "class", "extends", "static", "import", "export",
    "from", "as", "with", "debugger", "async", "await", "yield", "super",
}) do KEYWORDS[w] = true end

local function is_alpha(c)
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c == "$"
end

local function is_digit(c)
    return c >= "0" and c <= "9"
end

local function is_alnum(c)
    return is_alpha(c) or is_digit(c)
end

local function tokenize(source)
    local tokens = {}
    local pos = 1
    local len = #source

    local function peek(offset)
        local i = pos + (offset or 0)
        if i > len then return "" end
        return source:sub(i, i)
    end

    local function advance()
        local c = peek()
        pos = pos + 1
        return c
    end

    local function skip_whitespace()
        while pos <= len do
            local c = peek()
            if c == " " or c == "\t" or c == "\r" or c == "\n" then
                pos = pos + 1
            elseif c == "/" and peek(1) == "/" then
                -- line comment
                pos = pos + 2
                while pos <= len and peek() ~= "\n" do pos = pos + 1 end
            elseif c == "/" and peek(1) == "*" then
                -- block comment
                pos = pos + 2
                while pos <= len do
                    if peek() == "*" and peek(1) == "/" then
                        pos = pos + 2
                        break
                    end
                    pos = pos + 1
                end
            else
                break
            end
        end
    end

    local function read_string(quote)
        local parts = {}
        while pos <= len do
            local c = advance()
            if c == quote then
                return table.concat(parts)
            elseif c == "\\" then
                local esc = advance()
                if esc == "n" then parts[#parts+1] = "\n"
                elseif esc == "t" then parts[#parts+1] = "\t"
                elseif esc == "r" then parts[#parts+1] = "\r"
                elseif esc == "\\" then parts[#parts+1] = "\\"
                elseif esc == quote then parts[#parts+1] = quote
                else parts[#parts+1] = esc
                end
            else
                parts[#parts+1] = c
            end
        end
        error("unterminated string")
    end

    local function read_template()
        -- Already consumed the opening backtick.
        -- Returns a list of { type="str"|"expr", value=... }
        local parts = {}
        local current = {}
        while pos <= len do
            local c = peek()
            if c == "`" then
                pos = pos + 1
                if #current > 0 then
                    parts[#parts+1] = { type = "str", value = table.concat(current) }
                end
                return parts
            elseif c == "$" and peek(1) == "{" then
                if #current > 0 then
                    parts[#parts+1] = { type = "str", value = table.concat(current) }
                    current = {}
                end
                pos = pos + 2
                -- Read tokens until matching }
                local depth = 1
                local expr_start = pos
                while pos <= len and depth > 0 do
                    local ec = peek()
                    if ec == "{" then depth = depth + 1
                    elseif ec == "}" then depth = depth - 1
                    end
                    if depth > 0 then pos = pos + 1 end
                end
                parts[#parts+1] = { type = "expr", value = source:sub(expr_start, pos - 1) }
                pos = pos + 1 -- skip }
            elseif c == "\\" then
                pos = pos + 1
                local esc = advance()
                if esc == "n" then current[#current+1] = "\n"
                elseif esc == "t" then current[#current+1] = "\t"
                else current[#current+1] = esc
                end
            else
                current[#current+1] = c
                pos = pos + 1
            end
        end
        error("unterminated template literal")
    end

    local function read_number()
        local start = pos
        if peek() == "0" and (peek(1) == "x" or peek(1) == "X") then
            pos = pos + 2
            while pos <= len and (is_digit(peek()) or
                (peek() >= "a" and peek() <= "f") or
                (peek() >= "A" and peek() <= "F")) do
                pos = pos + 1
            end
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
        return tonumber(source:sub(start, pos - 1))
    end

    while true do
        skip_whitespace()
        if pos > len then break end

        local c = peek()

        -- Numbers
        if is_digit(c) or (c == "." and is_digit(peek(1))) then
            local num = read_number()
            tokens[#tokens+1] = { type = "number", value = num }

        -- Identifiers / keywords
        elseif is_alpha(c) then
            local start = pos
            while pos <= len and is_alnum(peek()) do pos = pos + 1 end
            local word = source:sub(start, pos - 1)
            tokens[#tokens+1] = { type = "ident", value = word }

        -- Strings
        elseif c == '"' or c == "'" then
            pos = pos + 1
            local s = read_string(c)
            tokens[#tokens+1] = { type = "string", value = s }

        -- Template literals
        elseif c == "`" then
            pos = pos + 1
            local parts = read_template()
            tokens[#tokens+1] = { type = "template", parts = parts }

        -- Arrow =>
        elseif c == "=" and peek(1) == ">" then
            pos = pos + 2
            tokens[#tokens+1] = { type = "=>" }

        -- Three-char operators
        elseif c == "=" and peek(1) == "=" and peek(2) == "=" then
            pos = pos + 3
            tokens[#tokens+1] = { type = "===" }
        elseif c == "!" and peek(1) == "=" and peek(2) == "=" then
            pos = pos + 3
            tokens[#tokens+1] = { type = "!==" }
        elseif c == ">" and peek(1) == ">" and peek(2) == ">" then
            pos = pos + 3
            tokens[#tokens+1] = { type = ">>>" }
        elseif c == "." and peek(1) == "." and peek(2) == "." then
            pos = pos + 3
            tokens[#tokens+1] = { type = "..." }
        elseif c == "?" and peek(1) == "?" then
            pos = pos + 2
            tokens[#tokens+1] = { type = "??" }
        elseif c == "?" and peek(1) == "." then
            pos = pos + 2
            tokens[#tokens+1] = { type = "?." }

        -- Two-char operators
        elseif c == "=" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = "==" }
        elseif c == "!" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = "!=" }
        elseif c == "<" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = "<=" }
        elseif c == ">" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = ">=" }
        elseif c == "&" and peek(1) == "&" then
            pos = pos + 2; tokens[#tokens+1] = { type = "&&" }
        elseif c == "|" and peek(1) == "|" then
            pos = pos + 2; tokens[#tokens+1] = { type = "||" }
        elseif c == "+" and peek(1) == "+" then
            pos = pos + 2; tokens[#tokens+1] = { type = "++" }
        elseif c == "-" and peek(1) == "-" then
            pos = pos + 2; tokens[#tokens+1] = { type = "--" }
        elseif c == "*" and peek(1) == "*" then
            pos = pos + 2; tokens[#tokens+1] = { type = "**" }
        elseif c == "<" and peek(1) == "<" then
            pos = pos + 2; tokens[#tokens+1] = { type = "<<" }
        elseif c == ">" and peek(1) == ">" then
            pos = pos + 2; tokens[#tokens+1] = { type = ">>" }
        elseif c == "+" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = "+=" }
        elseif c == "-" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = "-=" }
        elseif c == "*" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = "*=" }
        elseif c == "/" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = "/=" }
        elseif c == "%" and peek(1) == "=" then
            pos = pos + 2; tokens[#tokens+1] = { type = "%=" }

        -- Single-char
        else
            pos = pos + 1
            tokens[#tokens+1] = { type = c }
        end
    end

    tokens[#tokens+1] = { type = "eof" }
    return tokens
end

-- ═══════════════════════════════════════════════════════════════
-- Parser
-- ═══════════════════════════════════════════════════════════════

local function parser(tokens, T, S)
    local pos = 1

    local function peek()
        return tokens[pos]
    end

    local function advance()
        local tok = tokens[pos]
        pos = pos + 1
        return tok
    end

    local function expect(typ)
        local tok = advance()
        if tok.type ~= typ then
            error("expected '" .. typ .. "' but got '" .. tok.type
                .. "' (value: " .. tostring(tok.value) .. ")")
        end
        return tok
    end

    local function at(typ)
        return peek().type == typ
    end

    local function at_ident(name)
        local tok = peek()
        return tok.type == "ident" and tok.value == name
    end

    local function eat(typ)
        if at(typ) then advance(); return true end
        return false
    end

    local function eat_semi()
        eat(";")
    end

    -- Forward declarations
    local parse_expr
    local parse_assignment_expr
    local parse_stmt
    local parse_stmts
    local parse_stmt_body
    local parse_function_decl
    local parse_named_imports
    local parse_named_exports
    local parse_class_members
    local parse_class_decl_or_expr

    local function expect_ident_value()
        return expect("ident").value
    end

    parse_stmt_body = function()
        if at("{") then
            advance()
            local body = parse_stmts("}")
            expect("}")
            return S.Block(body)
        end
        return parse_stmt()
    end

    parse_function_decl = function(require_name)
        advance() -- function
        local name = nil
        if at("ident") and (require_name or not KEYWORDS[peek().value]) then
            name = advance().value
        elseif require_name then
            error("expected function name")
        end
        expect("(")
        local params = L{}
        if not at(")") then
            params[#params+1] = expect_ident_value()
            while eat(",") do
                params[#params+1] = expect_ident_value()
            end
        end
        expect(")")
        expect("{")
        local body = parse_stmts("}")
        expect("}")
        return name, params, body
    end

    parse_named_imports = function()
        local items = L{}
        expect("{")
        if not at("}") then
            local function one()
                local imported = expect_ident_value()
                local local_name = imported
                if at_ident("as") then
                    advance()
                    local_name = expect_ident_value()
                end
                items[#items+1] = S.ImportBinding(imported, local_name)
            end
            one()
            while eat(",") do
                if at("}") then break end
                one()
            end
        end
        expect("}")
        return items
    end

    parse_named_exports = function()
        local items = L{}
        expect("{")
        if not at("}") then
            local function one()
                local local_name = expect_ident_value()
                local exported_name = local_name
                if at_ident("as") then
                    advance()
                    exported_name = expect_ident_value()
                end
                items[#items+1] = S.ExportBinding(local_name, exported_name)
            end
            one()
            while eat(",") do
                if at("}") then break end
                one()
            end
        end
        expect("}")
        return items
    end

    parse_class_members = function()
        local members = L{}
        expect("{")
        while not at("}") do
            if eat(";") then goto continue end
            local is_static = false
            local is_private = false
            local kind = S.MethodNormal

            if at_ident("static") then
                advance()
                is_static = true
            end

            if at_ident("get") then
                local look = tokens[pos + 1]
                if look and (look.type == "ident" or look.type == "#") then
                    advance()
                    kind = S.MethodGet
                end
            elseif at_ident("set") then
                local look = tokens[pos + 1]
                if look and (look.type == "ident" or look.type == "#") then
                    advance()
                    kind = S.MethodSet
                end
            end

            if eat("#") then is_private = true end
            local name = expect_ident_value()

            if at("(") then
                expect("(")
                local params = L{}
                if not at(")") then
                    params[#params+1] = expect_ident_value()
                    while eat(",") do
                        params[#params+1] = expect_ident_value()
                    end
                end
                expect(")")
                expect("{")
                local body = parse_stmts("}")
                expect("}")
                members[#members+1] = S.Method(name, params, body, is_static, is_private, kind)
            else
                local init = nil
                if eat("=") then init = parse_assignment_expr() end
                eat_semi()
                members[#members+1] = S.Field(name, init, is_static, is_private)
            end

            ::continue::
        end
        expect("}")
        return members
    end

    parse_class_decl_or_expr = function(require_name)
        advance() -- class
        local name = nil
        if at("ident") and (require_name or not KEYWORDS[peek().value]) then
            name = advance().value
        elseif require_name then
            error("expected class name")
        end
        local super_class = nil
        if at_ident("extends") then
            advance()
            super_class = parse_assignment_expr()
        end
        local items = parse_class_members()
        return name, super_class, items
    end

    -- ── Expression parsing (precedence climbing) ──

    local function parse_primary()
        local tok = peek()

        if tok.type == "number" then
            advance()
            return S.NumLit(tok.value)
        end

        if tok.type == "string" then
            advance()
            return S.StrLit(tok.value)
        end

        if tok.type == "template" then
            advance()
            local parts = L{}
            for _, p in ipairs(tok.parts) do
                if p.type == "str" then
                    parts[#parts+1] = S.TemplateStr(p.value)
                else
                    -- Re-parse the expression
                    local expr_tokens = tokenize(p.value)
                    local sub_parser = parser(expr_tokens, T, S)
                    local expr = sub_parser.parse_expression()
                    parts[#parts+1] = S.TemplateExpr(expr)
                end
            end
            return S.Template(parts)
        end

        if tok.type == "ident" then
            if tok.value == "true" then advance(); return S.BoolLit(true) end
            if tok.value == "false" then advance(); return S.BoolLit(false) end
            if tok.value == "null" then advance(); return S.NullLit end
            if tok.value == "undefined" then advance(); return S.UndefinedLit end
            if tok.value == "this" then advance(); return S.This end

            if tok.value == "typeof" then
                advance()
                local arg = parse_expr(15) -- unary precedence
                return S.Typeof(arg)
            end

            if tok.value == "void" then
                advance()
                local arg = parse_expr(15)
                return S.Void(arg)
            end

            if tok.value == "delete" then
                advance()
                local obj_expr = parse_expr(15)
                -- delete must target a member expression
                if obj_expr.kind == "Member" then
                    return S.Delete(obj_expr.object, obj_expr.property, obj_expr.computed)
                end
                error("delete requires member expression")
            end

            if tok.value == "new" then
                advance()
                local callee = parse_primary()
                -- Handle member chains after new
                while at(".") or at("[") do
                    if eat(".") then
                        local prop = expect("ident")
                        callee = S.Member(callee, S.StrLit(prop.value), false)
                    elseif eat("[") then
                        local prop = parse_expr(0)
                        expect("]")
                        callee = S.Member(callee, prop, true)
                    end
                end
                local args = L{}
                if eat("(") then
                    if not at(")") then
                        args[#args+1] = parse_assignment_expr()
                        while eat(",") do
                            args[#args+1] = parse_assignment_expr()
                        end
                    end
                    expect(")")
                end
                return S.New(callee, args)
            end

            -- Check for arrow function: (params) => or ident =>
            if peek(1) and tokens[pos + 1] and tokens[pos + 1].type == "=>" then
                local name = advance().value
                advance() -- skip =>
                local body
                if at("{") then
                    advance()
                    local stmts = parse_stmts("}")
                    expect("}")
                    body = S.ArrowBlock(stmts)
                else
                    body = S.ArrowExpr(parse_assignment_expr())
                end
                return S.Arrow(L{name}, body)
            end

            if tok.value == "function" then
                local name, params, body = parse_function_decl(false)
                return S.FuncExpr(name, params, body)
            end

            if tok.value == "class" and S.ClassExpr then
                local name, super_class, items = parse_class_decl_or_expr(false)
                return S.ClassExpr(name, super_class, items)
            end

            advance()
            return S.Ident(tok.value)
        end

        if tok.type == "(" then
            advance()
            -- Could be arrow: (a, b) => ...
            -- or grouping: (expr)
            -- Try to detect arrow params
            local saved_pos = pos
            local is_arrow = false
            local params = L{}

            if at(")") then
                -- () => ...
                advance()
                if at("=>") then
                    advance()
                    is_arrow = true
                else
                    pos = saved_pos
                end
            elseif at("ident") then
                -- Try reading comma-separated idents
                local temp_params = { peek().value }
                local temp_pos = pos + 1
                local ok = true
                while temp_pos <= #tokens do
                    local t = tokens[temp_pos]
                    if t.type == "," then
                        temp_pos = temp_pos + 1
                        if tokens[temp_pos] and tokens[temp_pos].type == "ident" then
                            temp_params[#temp_params+1] = tokens[temp_pos].value
                            temp_pos = temp_pos + 1
                        else
                            ok = false; break
                        end
                    elseif t.type == ")" then
                        temp_pos = temp_pos + 1
                        if tokens[temp_pos] and tokens[temp_pos].type == "=>" then
                            temp_pos = temp_pos + 1
                            break
                        else
                            ok = false; break
                        end
                    else
                        ok = false; break
                    end
                end

                if ok and tokens[temp_pos - 1] and tokens[temp_pos - 1].type == "=>" then
                    -- It is an arrow function
                    for _, p in ipairs(temp_params) do
                        params[#params+1] = p
                    end
                    pos = temp_pos
                    is_arrow = true
                end
            end

            if is_arrow then
                local body
                if at("{") then
                    advance()
                    local stmts = parse_stmts("}")
                    expect("}")
                    body = S.ArrowBlock(stmts)
                else
                    body = S.ArrowExpr(parse_assignment_expr())
                end
                return S.Arrow(params, body)
            end

            -- Regular grouping
            local expr = parse_expr(0)
            expect(")")
            return expr
        end

        if tok.type == "[" then
            advance()
            local elems = L{}
            if not at("]") then
                if at("...") then
                    advance()
                    elems[#elems+1] = S.Spread(parse_assignment_expr())
                else
                    elems[#elems+1] = parse_assignment_expr()
                end
                while eat(",") do
                    if at("]") then break end
                    if at("...") then
                        advance()
                        elems[#elems+1] = S.Spread(parse_assignment_expr())
                    else
                        elems[#elems+1] = parse_assignment_expr()
                    end
                end
            end
            expect("]")
            return S.ArrayExpr(elems)
        end

        if tok.type == "{" then
            advance()
            local props = L{}
            if not at("}") then
                local function parse_prop()
                    if at("...") then
                        advance()
                        return S.PropSpread(parse_assignment_expr())
                    end
                    local computed = false
                    local key
                    if eat("[") then
                        computed = true
                        key = parse_expr(0)
                        expect("]")
                    elseif at("string") then
                        key = S.StrLit(advance().value)
                    elseif at("number") then
                        key = S.NumLit(advance().value)
                    elseif at("ident") then
                        local name = advance().value
                        -- Shorthand property: { x } means { x: x }
                        if not at(":") then
                            return S.PropInit(
                                S.StrLit(name),
                                S.Ident(name),
                                false
                            )
                        end
                        key = S.StrLit(name)
                    else
                        error("expected property name, got " .. peek().type)
                    end
                    expect(":")
                    return S.PropInit(key, parse_assignment_expr(), computed)
                end
                props[#props+1] = parse_prop()
                while eat(",") do
                    if at("}") then break end
                    props[#props+1] = parse_prop()
                end
            end
            expect("}")
            return S.ObjectExpr(props)
        end

        -- Prefix unary
        if tok.type == "-" then
            advance()
            return S.UnaryOp(T.JsCore.UNeg, parse_expr(15))
        end
        if tok.type == "+" then
            advance()
            return S.UnaryOp(T.JsCore.UPos, parse_expr(15))
        end
        if tok.type == "!" then
            advance()
            return S.UnaryOp(T.JsCore.ULogNot, parse_expr(15))
        end
        if tok.type == "~" then
            advance()
            return S.UnaryOp(T.JsCore.UBitNot, parse_expr(15))
        end
        if tok.type == "++" then
            advance()
            return S.UpdateOp(T.JsCore.Inc, parse_expr(15), true)
        end
        if tok.type == "--" then
            advance()
            return S.UpdateOp(T.JsCore.Dec, parse_expr(15), true)
        end

        error("unexpected token: " .. tok.type .. " (value: " .. tostring(tok.value) .. ")")
    end

    -- Postfix and infix with precedence climbing
    local binop_info = {
        ["||"]  = { prec = 4,  assoc = "left", op = function() return T.JsCore.LogOr end, logical = true },
        ["&&"]  = { prec = 5,  assoc = "left", op = function() return T.JsCore.LogAnd end, logical = true },
        ["|"]   = { prec = 6,  assoc = "left", op = function() return T.JsCore.BitOr end },
        ["^"]   = { prec = 7,  assoc = "left", op = function() return T.JsCore.BitXor end },
        ["&"]   = { prec = 8,  assoc = "left", op = function() return T.JsCore.BitAnd end },
        ["=="]  = { prec = 9,  assoc = "left", op = function() return T.JsCore.EqEq end },
        ["!="]  = { prec = 9,  assoc = "left", op = function() return T.JsCore.NotEq end },
        ["==="] = { prec = 9,  assoc = "left", op = function() return T.JsCore.EqEqEq end },
        ["!=="] = { prec = 9,  assoc = "left", op = function() return T.JsCore.NotEqEq end },
        ["<"]   = { prec = 10, assoc = "left", op = function() return T.JsCore.Lt end },
        ["<="]  = { prec = 10, assoc = "left", op = function() return T.JsCore.Le end },
        [">"]   = { prec = 10, assoc = "left", op = function() return T.JsCore.Gt end },
        [">="]  = { prec = 10, assoc = "left", op = function() return T.JsCore.Ge end },
        ["<<"]  = { prec = 11, assoc = "left", op = function() return T.JsCore.Shl end },
        [">>"]  = { prec = 11, assoc = "left", op = function() return T.JsCore.Shr end },
        [">>>"] = { prec = 11, assoc = "left", op = function() return T.JsCore.UShr end },
        ["+"]   = { prec = 12, assoc = "left", op = function() return T.JsCore.Add end },
        ["-"]   = { prec = 12, assoc = "left", op = function() return T.JsCore.Sub end },
        ["*"]   = { prec = 13, assoc = "left", op = function() return T.JsCore.Mul end },
        ["/"]   = { prec = 13, assoc = "left", op = function() return T.JsCore.Div end },
        ["%"]   = { prec = 13, assoc = "left", op = function() return T.JsCore.Mod end },
        ["**"]  = { prec = 14, assoc = "right", op = function() return T.JsCore.Exp end },
    }

    local compound_assign_ops = {
        ["+=" ] = function() return T.JsCore.Add end,
        ["-=" ] = function() return T.JsCore.Sub end,
        ["*=" ] = function() return T.JsCore.Mul end,
        ["/=" ] = function() return T.JsCore.Div end,
        ["%=" ] = function() return T.JsCore.Mod end,
    }

    local instanceof_info = { prec = 10, assoc = "left" }

    parse_expr = function(min_prec)
        local left = parse_primary()

        while true do
            local tok = peek()

            -- Postfix: member access, call, computed access, optional chaining
            if tok.type == "." then
                advance()
                local prop = expect("ident")
                left = S.Member(left, S.StrLit(prop.value), false)
            elseif tok.type == "[" then
                advance()
                local prop = parse_expr(0)
                expect("]")
                left = S.Member(left, prop, true)
            elseif tok.type == "(" then
                advance()
                local args = L{}
                if not at(")") then
                    if at("...") then
                        advance()
                        args[#args+1] = S.Spread(parse_assignment_expr())
                    else
                        args[#args+1] = parse_assignment_expr()
                    end
                    while eat(",") do
                        if at("...") then
                            advance()
                            args[#args+1] = S.Spread(parse_assignment_expr())
                        else
                            args[#args+1] = parse_assignment_expr()
                        end
                    end
                end
                expect(")")
                left = S.Call(left, args)
            elseif tok.type == "?." then
                advance()
                if at("[") then
                    advance()
                    local prop = parse_expr(0)
                    expect("]")
                    left = S.Optional(left, prop, true)
                else
                    local prop = expect("ident")
                    left = S.Optional(left, S.StrLit(prop.value), false)
                end
            elseif tok.type == "++" then
                if min_prec > 16 then break end
                advance()
                left = S.UpdateOp(T.JsCore.Inc, left, false)
            elseif tok.type == "--" then
                if min_prec > 16 then break end
                advance()
                left = S.UpdateOp(T.JsCore.Dec, left, false)

            -- instanceof
            elseif tok.type == "ident" and tok.value == "instanceof" then
                if instanceof_info.prec < min_prec then break end
                advance()
                local right = parse_expr(instanceof_info.prec + 1)
                left = S.Instanceof(left, right)

            -- in
            elseif tok.type == "ident" and tok.value == "in" then
                -- 'in' as binary operator in expressions is not supported
                -- in this subset (only in for-in)
                break

            -- Nullish coalescing
            elseif tok.type == "??" then
                if 3 < min_prec then break end
                advance()
                local right = parse_expr(4)
                left = S.NullishCoalesce(left, right)

            -- Ternary
            elseif tok.type == "?" then
                if 2 < min_prec then break end
                advance()
                local cons = parse_assignment_expr()
                expect(":")
                local alt = parse_assignment_expr()
                left = S.Cond(left, cons, alt)

            -- Binary / logical ops
            elseif binop_info[tok.type] then
                local info = binop_info[tok.type]
                if info.prec < min_prec then break end
                advance()
                local next_prec = info.assoc == "right" and info.prec or (info.prec + 1)
                local right = parse_expr(next_prec)
                if info.logical then
                    left = S.LogicalOp(info.op(), left, right)
                else
                    left = S.BinOp(info.op(), left, right)
                end

            else
                break
            end
        end

        return left
    end

    parse_assignment_expr = function()
        local left = parse_expr(0)

        -- Assignment
        if at("=") then
            advance()
            local right = parse_assignment_expr()
            return S.Assign(left, right)
        end

        -- Compound assignment
        local ca = compound_assign_ops[peek().type]
        if ca then
            advance()
            local right = parse_assignment_expr()
            return S.CompoundAssign(ca(), left, right)
        end

        return left
    end

    -- ── Statement parsing ──

    parse_stmt = function()
        local tok = peek()

        if tok.type == ";" then
            advance()
            return S.Empty
        end

        if tok.type == "ident" then
            if tok.value == "var" or tok.value == "let" or tok.value == "const" then
                advance()
                local kind
                if tok.value == "var" then kind = T.JsCore.Var
                elseif tok.value == "let" then kind = T.JsCore.Let
                else kind = T.JsCore.Const
                end
                local decls = L{}
                local function parse_declarator()
                    local name = expect("ident").value
                    local init = nil
                    if eat("=") then
                        init = parse_assignment_expr()
                    end
                    decls[#decls+1] = S.Declarator(name, init)
                end
                parse_declarator()
                while eat(",") do parse_declarator() end
                eat_semi()
                return S.VarDecl(kind, decls)
            end

            if tok.value == "function" then
                local name, params, body = parse_function_decl(true)
                return S.FuncDecl(name, params, body)
            end

            if tok.value == "class" and S.ClassDecl then
                local name, super_class, items = parse_class_decl_or_expr(true)
                return S.ClassDecl(name, super_class, items)
            end

            if tok.value == "import" and S.Import then
                advance()
                if at("string") then
                    local from = advance().value
                    eat_semi()
                    return S.Import(nil, nil, L{}, from)
                end
                local default_name, namespace_name = nil, nil
                local named = L{}
                if at("ident") then
                    default_name = advance().value
                    if eat(",") then
                        if eat("*") then
                            if at_ident("as") then advance() end
                            namespace_name = expect_ident_value()
                        elseif at("{") then
                            named = parse_named_imports()
                        end
                    end
                elseif eat("*") then
                    if at_ident("as") then advance() end
                    namespace_name = expect_ident_value()
                elseif at("{") then
                    named = parse_named_imports()
                end
                if at_ident("from") then advance() end
                local from = at("string") and advance().value or nil
                eat_semi()
                return S.Import(default_name, namespace_name, named, from)
            end

            if tok.value == "export" and S.ExportNamed then
                advance()
                if at_ident("default") then
                    advance()
                    if at_ident("function") then
                        local name, params, body = parse_function_decl(false)
                        return S.ExportDefaultDecl(S.FuncDecl(name or "default", params, body))
                    elseif at_ident("class") and S.ClassDecl then
                        local name, super_class, items = parse_class_decl_or_expr(false)
                        return S.ExportDefaultDecl(S.ClassDecl(name or "default", super_class, items))
                    else
                        local expr = parse_assignment_expr()
                        eat_semi()
                        return S.ExportDefaultExpr(expr)
                    end
                elseif eat("*") then
                    local alias = nil
                    if at_ident("as") then
                        advance()
                        alias = expect_ident_value()
                    end
                    if at_ident("from") then advance() end
                    local from = advance().value
                    eat_semi()
                    return S.ExportAll(alias, from)
                elseif at("{") then
                    local bindings = parse_named_exports()
                    local from = nil
                    if at_ident("from") then
                        advance()
                        from = advance().value
                    end
                    eat_semi()
                    return S.ExportNamed(bindings, from)
                elseif at_ident("function") then
                    local name, params, body = parse_function_decl(true)
                    return S.ExportDecl(S.FuncDecl(name, params, body))
                elseif at_ident("class") and S.ClassDecl then
                    local name, super_class, items = parse_class_decl_or_expr(true)
                    return S.ExportDecl(S.ClassDecl(name, super_class, items))
                end
            end

            if tok.value == "return" then
                advance()
                if at(";") or at("}") or at("eof") then
                    eat_semi()
                    return S.Return(nil)
                end
                local val = parse_assignment_expr()
                eat_semi()
                return S.Return(val)
            end

            if tok.value == "if" then
                advance()
                expect("(")
                local test = parse_expr(0)
                expect(")")
                local cons = parse_stmt_body()
                local alt = nil
                if at_ident("else") then
                    advance()
                    alt = parse_stmt_body()
                end
                return S.If(test, cons, alt)
            end

            if tok.value == "while" then
                advance()
                expect("(")
                local test = parse_expr(0)
                expect(")")
                local body = parse_stmt_body()
                return S.While(test, body)
            end

            if tok.value == "do" and S.DoWhile then
                advance()
                local body = parse_stmt_body()
                if at_ident("while") then advance() else error("expected while after do-body") end
                expect("(")
                local test = parse_expr(0)
                expect(")")
                eat_semi()
                return S.DoWhile(body, test)
            end

            if tok.value == "switch" and S.Switch then
                advance()
                expect("(")
                local disc = parse_expr(0)
                expect(")")
                expect("{")
                local cases = L{}
                while not at("}") do
                    local test = nil
                    if at_ident("case") then
                        advance()
                        test = parse_expr(0)
                    elseif at_ident("default") then
                        advance()
                    else
                        error("expected case/default in switch")
                    end
                    expect(":")
                    local body = L{}
                    while not at("}") and not at_ident("case") and not at_ident("default") do
                        body[#body + 1] = parse_stmt()
                    end
                    cases[#cases + 1] = S.SwitchCase(test, body)
                end
                expect("}")
                return S.Switch(disc, cases)
            end

            if tok.value == "with" and S.With then
                advance()
                expect("(")
                local obj = parse_expr(0)
                expect(")")
                return S.With(obj, parse_stmt_body())
            end

            if tok.value == "debugger" then
                advance(); eat_semi()
                return S.Empty
            end

            if tok.value == "for" then
                advance()
                expect("(")
                -- for (let x of/in ...) or for (init; test; update)
                if at_ident("let") or at_ident("var") or at_ident("const") then
                    local saved = pos
                    local kw = advance().value
                    if at("ident") then
                        local name = peek().value
                        advance()
                        local var_kind = (kw == "var") and T.JsCore.Var or ((kw == "const") and T.JsCore.Const or T.JsCore.Let)
                        if at_ident("of") then
                            advance()
                            local right = parse_expr(0)
                            expect(")")
                            local body = parse_stmt_body()
                            return S.ForOf(var_kind, name, right, body)
                        elseif at_ident("in") then
                            advance()
                            local right = parse_expr(0)
                            expect(")")
                            local body = parse_stmt_body()
                            return S.ForIn(var_kind, name, right, body)
                        else
                            pos = saved
                        end
                    else
                        pos = saved
                    end
                end
                -- Regular for
                local init = nil
                if not at(";") then
                    init = parse_stmt()
                else
                    advance()
                end
                local test = nil
                if not at(";") then test = parse_expr(0) end
                expect(";")
                local update = nil
                if not at(")") then update = parse_assignment_expr() end
                expect(")")
                local body = parse_stmt_body()
                return S.For(init, test, update, body)
            end

            if tok.value == "break" then
                advance()
                local label = nil
                if at("ident") and not KEYWORDS[peek().value] then
                    label = advance().value
                end
                eat_semi()
                return S.Break(label)
            end

            if tok.value == "continue" then
                advance()
                local label = nil
                if at("ident") and not KEYWORDS[peek().value] then
                    label = advance().value
                end
                eat_semi()
                return S.Continue(label)
            end

            if tok.value == "throw" then
                advance()
                local arg = parse_assignment_expr()
                eat_semi()
                return S.Throw(arg)
            end

            if tok.value == "try" then
                advance()
                expect("{")
                local block = S.Block(parse_stmts("}"))
                expect("}")
                local handler = nil
                if at_ident("catch") then
                    advance()
                    local param = nil
                    if eat("(") then
                        param = expect("ident").value
                        expect(")")
                    end
                    expect("{")
                    local catch_body = S.Block(parse_stmts("}"))
                    expect("}")
                    handler = S.CatchClause(param, catch_body)
                end
                local finalizer = nil
                if at_ident("finally") then
                    advance()
                    expect("{")
                    finalizer = S.Block(parse_stmts("}"))
                    expect("}")
                end
                return S.Try(block, handler, finalizer)
            end

            if S.Label and not KEYWORDS[tok.value] and tokens[pos + 1] and tokens[pos + 1].type == ":" then
                local name = advance().value
                expect(":")
                return S.Label(name, parse_stmt_body())
            end
        end

        if tok.type == "{" then
            advance()
            local body = parse_stmts("}")
            expect("}")
            return S.Block(body)
        end

        -- Expression statement
        local expr = parse_assignment_expr()
        eat_semi()
        return S.ExprStmt(expr)
    end

    parse_stmts = function(until_type)
        local stmts = L{}
        while not at(until_type) and not at("eof") do
            stmts[#stmts+1] = parse_stmt()
        end
        return stmts
    end

    local function parse_program()
        local body = parse_stmts("eof")
        return S.Program(body)
    end

    return {
        parse_program = parse_program,
        parse_expression = function() return parse_assignment_expr() end,
    }
end

-- ═══════════════════════════════════════════════════════════════
-- Public parse function
-- ═══════════════════════════════════════════════════════════════

local function parse_js(T, source, S)
    local tokens
    if T.JsLex and T.JsLex.lex and T.JsLex.to_legacy_tokens then
        local stream = T.JsLex.lex(source)
        tokens = T.JsLex.to_legacy_tokens(stream)
    else
        tokens = tokenize(source)
    end
    local p = parser(tokens, T, S)
    return p.parse_program()
end

-- ═══════════════════════════════════════════════════════════════
-- Install on T
-- ═══════════════════════════════════════════════════════════════
return function(T)
    T.JsSurface.parse = function(source)
        return parse_js(T, source, T.JsSurface)
    end

    T.JsSource.parse = function(source)
        return T.JsSurface.parse(source):lower()
    end
end
