local U = require("unit")

return function(T, U, P)
    function T.Demo.Expr:lower()
        return U.match(self, {
            Add = function(v) return v end,
            Mul = function(v) return v end,
        })
    end
end
