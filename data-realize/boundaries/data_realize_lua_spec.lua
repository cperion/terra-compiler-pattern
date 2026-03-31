return function(T, U, P)
    local install_impl = U.terminal("DataRealizeLua.Spec:install", function(spec)
        error("scaffold: fill in DataRealizeLua.Spec:install()", 2)
    end)

    function T.DataRealizeLua.Spec:install()
        return install_impl(self)
    end
end
