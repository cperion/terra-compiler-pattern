return {
    layout = "flat",
    stubs = {
        ["MoreFunSource.Spec"] = "lower",
        ["MoreFunLowered.Spec"] = "define_machine",
        ["MoreFunMachine.Spec"] = "lower_luajit",
        ["MoreFunLuaJIT.Plan"] = "install",
    },
}
