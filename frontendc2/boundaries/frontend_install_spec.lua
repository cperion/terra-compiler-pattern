local U = require("unit")

return function(T, U, P)

function T.FrontendInstall.Spec:emit_lua()
    return U.match(self, {
        StructuralFrontierInstall = function(self)
            error("scaffold: implement enum branch", 2)
        end,
        TokenFrontierInstall = function(self)
            error("scaffold: implement enum branch", 2)
        end,
    })
end

function T.FrontendInstall.Spec:install_generated()
    return U.match(self, {
        StructuralFrontierInstall = function(self)
            error("scaffold: implement enum branch", 2)
        end,
        TokenFrontierInstall = function(self)
            error("scaffold: implement enum branch", 2)
        end,
    })
end

end
