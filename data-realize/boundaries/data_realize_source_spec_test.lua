return function(T, U, P)
    local tests = {}

    local function sample_spec(package_mode)
        return T.DataRealizeSource.Spec({
            T.DataRealizeSource.Binding(
                1,
                "settings",
                T.DataRealizeSource.InlineText('{"volume": 0.8}'),
                T.DataRealizeSource.JsonLanguage,
                T.DataRealizeSource.ReturnValueContract
            ),
            T.DataRealizeSource.Binding(
                2,
                "theme",
                T.DataRealizeSource.FileText("theme.json"),
                T.DataRealizeSource.JsonLanguage,
                T.DataRealizeSource.AssignGlobalContract("THEME")
            ),
        }, package_mode)
    end

    function tests.test_check_preserves_binding_identity_and_contracts()
        local out = sample_spec(T.DataRealizeSource.BytecodeMode):check()

        assert(#out.bindings == 2)
        assert(out.package.kind == "BytecodeMode")

        assert(out.bindings[1].header.id == 1)
        assert(out.bindings[1].header.name == "settings")
        assert(out.bindings[1].input.kind == "InlineText")
        assert(out.bindings[1].input.text == '{"volume": 0.8}')
        assert(out.bindings[1].language.kind == "JsonLanguage")
        assert(out.bindings[1].contract.kind == "ReturnValueContract")

        assert(out.bindings[2].header.id == 2)
        assert(out.bindings[2].header.name == "theme")
        assert(out.bindings[2].input.kind == "FileText")
        assert(out.bindings[2].input.path == "theme.json")
        assert(out.bindings[2].contract.kind == "AssignGlobalContract")
        assert(out.bindings[2].contract.variable_name == "THEME")
    end

    function tests.test_check_rejects_duplicate_binding_names()
        local spec = T.DataRealizeSource.Spec({
            T.DataRealizeSource.Binding(
                1,
                "settings",
                T.DataRealizeSource.InlineText("{}"),
                T.DataRealizeSource.JsonLanguage,
                T.DataRealizeSource.ReturnValueContract
            ),
            T.DataRealizeSource.Binding(
                2,
                "settings",
                T.DataRealizeSource.InlineText("{}"),
                T.DataRealizeSource.JsonLanguage,
                T.DataRealizeSource.ReturnValueContract
            ),
        }, T.DataRealizeSource.SourceMode)

        local ok, err = pcall(function()
            spec:check()
        end)

        assert(ok == false)
        assert(tostring(err):match("duplicate binding name"))
    end

    return tests
end
