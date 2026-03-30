local ffi = require("ffi")

return function(T, U, P)
    local function S(v)
        if type(v) == "cdata" then return ffi.string(v) end
        return tostring(v)
    end

    local function N(v)
        return tonumber(v)
    end

    local function split_path(Path, fqname)
        local parts = {}
        fqname = S(fqname)
        for part in fqname:gmatch("[^.]+") do
            parts[#parts + 1] = part
        end
        return Path(parts)
    end

    local define_machine_impl = U.transition(function(spec)
        local MT = T.FrontendMachine
        local target = spec.target

        local tokenize_header = MT.BoundaryHeader(
            split_path(MT.Path, target.tokenize_receiver_fqname),
            S(target.tokenize_verb)
        )

        local parse_header = MT.BoundaryHeader(
            split_path(MT.Path, target.parse_receiver_fqname),
            S(target.parse_verb)
        )

        local result_ctors = {}
        for i = 1, #spec.parse.result_ctors do
            local row = spec.parse.result_ctors[i]
            result_ctors[i] = MT.CtorRef(
                N(row.ctor_id),
                split_path(MT.Path, row.ctor.ctor_fqname)
            )
        end

        return MT.Spec(
            MT.TokenizeInstall(
                tokenize_header,
                split_path(MT.Path, target.token_spec_ctor_fqname),
                split_path(MT.Path, target.token_cell_ctor_fqname),
                split_path(MT.Path, target.token_span_ctor_fqname),
                spec.tokenize
            ),
            MT.ParseInstall(
                parse_header,
                split_path(MT.Path, target.source_spec_ctor_fqname),
                result_ctors,
                spec.parse
            )
        )
    end)

    function T.FrontendLowered.Spec:define_machine()
        return define_machine_impl(self)
    end
end
