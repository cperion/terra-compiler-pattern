local ffi = require("ffi")

local function S(v)
    if type(v) == "cdata" then
        return ffi.string(v)
    end
    return tostring(v)
end

return function(T, U, P)
    local function checked_package(mode)
        return U.match(mode, {
            SourceMode = function()
                return T.DataRealizeChecked.SourceMode
            end,
            ClosureMode = function()
                return T.DataRealizeChecked.ClosureMode
            end,
            BytecodeMode = function()
                return T.DataRealizeChecked.BytecodeMode
            end,
        })
    end

    local function checked_input(input)
        return U.match(input, {
            InlineText = function(v)
                return T.DataRealizeChecked.InlineText(S(v.text))
            end,
            FileText = function(v)
                local path = S(v.path)
                assert(path ~= "", "DataRealizeSource.Spec:check(): FileText path must be non-empty")
                return T.DataRealizeChecked.FileText(path)
            end,
        })
    end

    local function checked_language(language)
        return U.match(language, {
            JsonLanguage = function()
                return T.DataRealizeChecked.JsonLanguage
            end,
            TomlLanguage = function()
                return T.DataRealizeChecked.TomlLanguage
            end,
            JsonLinesLanguage = function()
                return T.DataRealizeChecked.JsonLinesLanguage
            end,
        })
    end

    local function checked_contract(contract)
        return U.match(contract, {
            ReturnValueContract = function()
                return T.DataRealizeChecked.ReturnValueContract
            end,
            AssignGlobalContract = function(v)
                local name = S(v.variable_name)
                assert(name ~= "", "DataRealizeSource.Spec:check(): AssignGlobalContract variable_name must be non-empty")
                return T.DataRealizeChecked.AssignGlobalContract(name)
            end,
            PatchGlobalContract = function(v)
                local name = S(v.variable_name)
                assert(name ~= "", "DataRealizeSource.Spec:check(): PatchGlobalContract variable_name must be non-empty")
                return T.DataRealizeChecked.PatchGlobalContract(name)
            end,
        })
    end

    local function unique_map(items, key_of, label)
        return U.fold(items, function(acc, item)
            local key = key_of(item)
            assert(acc[key] == nil, "DataRealizeSource.Spec:check(): duplicate " .. label .. ": " .. tostring(key))
            acc[key] = item
            return acc
        end, {})
    end

    local function checked_binding(binding)
        local name = S(binding.name)
        assert(name ~= "", "DataRealizeSource.Spec:check(): binding name must be non-empty")
        return T.DataRealizeChecked.Binding(
            T.DataRealizeChecked.BindingHeader(binding.id, name),
            checked_input(binding.input),
            checked_language(binding.language),
            checked_contract(binding.contract)
        )
    end

    local check_impl = U.transition("DataRealizeSource.Spec:check", function(spec)
        local bindings = U.map(spec.bindings, checked_binding)

        unique_map(bindings, function(binding)
            return binding.header.id
        end, "binding id")

        unique_map(bindings, function(binding)
            return S(binding.header.name)
        end, "binding name")

        return T.DataRealizeChecked.Spec(
            bindings,
            checked_package(spec.package)
        )
    end)

    function T.DataRealizeSource.Spec:check()
        return check_impl(self)
    end
end
