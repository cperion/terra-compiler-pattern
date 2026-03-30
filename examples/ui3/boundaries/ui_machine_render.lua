return function(T)
    if rawget(_G, "terralib") then
        require("examples.ui3.backends.terra_machine_render")(T)
    end
end
