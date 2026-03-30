return {
    layout = "flat",
    stubs = {
        ["FrontendSource.Spec"] = "check",
        ["FrontendChecked.Spec"] = "lower",
        ["FrontendLowered.Spec"] = "define_machine",
        ["FrontendMachine.Spec"] = { "emit_lua", "install_generated" },
    },
}
