local U = require("unit")

return function(T, U, P)

function T.FrontendMachine.Spec:package()
    return U.match(self, {
        StructuralFrontierMachine = function(self)
            error("scaffold: implement enum branch", 2)
        end,
        TokenFrontierMachine = function(self)
            error("scaffold: implement enum branch", 2)
        end,
    })
end

end
