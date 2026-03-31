local ffi = require("ffi")

local function S(v)
    if type(v) == "cdata" then
        return ffi.string(v)
    end
    return tostring(v)
end

return function(T, U, P)
    local function machine_package(mode)
        return U.match(mode, {
            SourceMode = function()
                return T.DataRealizeMachine.SourceMode
            end,
            ClosureMode = function()
                return T.DataRealizeMachine.ClosureMode
            end,
            BytecodeMode = function()
                return T.DataRealizeMachine.BytecodeMode
            end,
        })
    end

    local function input_plan(input)
        return U.match(input, {
            InlineText = function(v)
                return T.DataRealizeMachine.InlineText(S(v.text))
            end,
            FileText = function(v)
                return T.DataRealizeMachine.FileText(S(v.path))
            end,
        })
    end

    local function decode_machine(language)
        return U.match(language, {
            JsonLanguage = function()
                return T.DataRealizeMachine.JsonToTableMachine
            end,
            TomlLanguage = function()
                return T.DataRealizeMachine.TomlToTableMachine
            end,
            JsonLinesLanguage = function()
                return T.DataRealizeMachine.JsonLinesToTableMachine
            end,
        })
    end

    local function install_contract(contract)
        return U.match(contract, {
            ReturnValueContract = function()
                return T.DataRealizeMachine.ReturnValueContract
            end,
            AssignGlobalContract = function(v)
                return T.DataRealizeMachine.AssignGlobalContract(S(v.variable_name))
            end,
            PatchGlobalContract = function(v)
                return T.DataRealizeMachine.PatchGlobalContract(S(v.variable_name))
            end,
        })
    end

    local function binding_machine(binding)
        return T.DataRealizeMachine.BindingMachine(
            T.DataRealizeMachine.BindingHeader(binding.header.id, S(binding.header.name)),
            input_plan(binding.input),
            decode_machine(binding.language),
            install_contract(binding.contract)
        )
    end

    local define_machine_impl = U.transition("DataRealizeChecked.Spec:define_machine", function(spec)
        return T.DataRealizeMachine.Spec(
            U.map(spec.bindings, binding_machine),
            machine_package(spec.package)
        )
    end)

    function T.DataRealizeChecked.Spec:define_machine()
        return define_machine_impl(self)
    end
end
