local byte = string.byte
local sub = string.sub
local format = string.format

local BYTE_EQ = byte("=")
local BYTE_BAR = byte("|")
local BYTE_Q = byte("?")
local BYTE_STAR = byte("*")
local BYTE_COMMA = byte(",")
local BYTE_LPAREN = byte("(")
local BYTE_RPAREN = byte(")")
local BYTE_LBRACE = byte("{")
local BYTE_RBRACE = byte("}")
local BYTE_DOT = byte(".")
local BYTE_HASH = byte("#")
local BYTE_NL = byte("\n")

local M = {}

function M.new(text)
    local len = #text
    local pos = 1
    local state = {
        cur = nil,
        value = nil,
        start_byte = nil,
        end_byte = nil,
    }

    local function err(what)
        error(format(
            "asdl2_text.tokenize: expected %s but found '%s' here:\n%s",
            what,
            tostring(state.value),
            sub(text, 1, pos) .. "<--##    " .. sub(text, pos + 1, -1)
        ), 2)
    end

    local function set_token(kind, value, start_byte, end_byte)
        state.cur = kind
        state.value = value
        state.start_byte = start_byte
        state.end_byte = end_byte
    end

    local function next_token()
        while true do
            while pos <= len do
                local c = byte(text, pos)
                if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then break end
                pos = pos + 1
            end

            if pos > len then
                set_token("EOF", "EOF", len + 1, len + 1)
                return
            end

            if byte(text, pos) ~= BYTE_HASH then break end
            pos = pos + 1
            while pos <= len and byte(text, pos) ~= BYTE_NL do
                pos = pos + 1
            end
            if pos <= len then pos = pos + 1 end
        end

        local start = pos
        local c = byte(text, pos)
        if c == BYTE_EQ then
            pos = pos + 1
            set_token("=", "=", start, start)
            return
        elseif c == BYTE_BAR then
            pos = pos + 1
            set_token("|", "|", start, start)
            return
        elseif c == BYTE_Q then
            pos = pos + 1
            set_token("?", "?", start, start)
            return
        elseif c == BYTE_STAR then
            pos = pos + 1
            set_token("*", "*", start, start)
            return
        elseif c == BYTE_COMMA then
            pos = pos + 1
            set_token(",", ",", start, start)
            return
        elseif c == BYTE_LPAREN then
            pos = pos + 1
            set_token("(", "(", start, start)
            return
        elseif c == BYTE_RPAREN then
            pos = pos + 1
            set_token(")", ")", start, start)
            return
        elseif c == BYTE_LBRACE then
            pos = pos + 1
            set_token("{", "{", start, start)
            return
        elseif c == BYTE_RBRACE then
            pos = pos + 1
            set_token("}", "}", start, start)
            return
        elseif c == BYTE_DOT then
            pos = pos + 1
            set_token(".", ".", start, start)
            return
        end

        if c ~= 95 and (c < 65 or c > 90) and (c < 97 or c > 122) then
            state.value = sub(text, pos, pos)
            err("valid token")
        end

        pos = pos + 1
        while pos <= len do
            c = byte(text, pos)
            if c ~= 95 and (c < 48 or c > 57) and (c < 65 or c > 90) and (c < 97 or c > 122) then
                break
            end
            pos = pos + 1
        end

        local ident = sub(text, start, pos - 1)
        if ident == "attributes" or ident == "unique" or ident == "module" then
            set_token(ident, ident, start, pos - 1)
        else
            set_token("Ident", ident, start, pos - 1)
        end
    end

    local function expect(kind)
        if state.cur ~= kind then err(kind) end
        local v = state.value
        next_token()
        return v
    end

    state.err = err
    state.next_token = next_token
    state.expect = expect
    return state
end

return M
