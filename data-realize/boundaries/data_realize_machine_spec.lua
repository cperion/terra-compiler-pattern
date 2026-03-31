return function(T, U, P)
    local prepare_install_impl = U.transition("DataRealizeMachine.Spec:prepare_install", function(spec)
        error("scaffold: fill in DataRealizeMachine.Spec:prepare_install()", 2)
    end)

    function T.DataRealizeMachine.Spec:prepare_install()
        return prepare_install_impl(self)
    end
end
