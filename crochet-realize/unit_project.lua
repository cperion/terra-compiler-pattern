return {
    layout = "flat",
    stubs = {
        ["CrochetRealizeSource.Catalog"] = "check_realize",
        ["CrochetRealizeChecked.Catalog"] = "lower_realize",
        ["CrochetRealizePlan.Catalog"] = "prepare_install",
        ["CrochetRealizeLua.Catalog"] = "install",
    },
}
