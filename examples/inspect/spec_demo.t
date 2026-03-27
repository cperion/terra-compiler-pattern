local U = require("unit")

return U.spec {
    text = [[
module Demo {
    Expr = Add(number x)
         | Mul(number y)

    Node = (
        Expr expr
    ) unique
}
]],

    phases = { "Demo" },

    install = function(T)
        function T.Demo.Expr:lower()
            return U.match(self, {
                Add = function(v) return v end,
                Mul = function(v) return v end,
            })
        end

        function T.Demo.Node:lower()
            return self.expr:lower()
        end
    end,
}
