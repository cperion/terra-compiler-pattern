local U = require("unit")

return function(T, U, P)
    function T.Demo.Node:lower()
        return self.expr:lower()
    end
end
