return [=[
-- ==========================================================================
-- JS surface ASDL
-- --------------------------------------------------------------------------
-- Parsed ECMAScript surface tree before lowering into the narrower JsSource
-- execution-oriented AST.
--
-- For now this mirrors the currently supported JS subset so we can split the
-- frontend into real phases without breaking the existing runtime.
-- ==========================================================================

module JsSurface {

    Program = (Stmt* body) unique

    Stmt
        = ExprStmt(Expr expr)
        | VarDecl(JsCore.VarKind var_kind, Declarator* decls)
        | FuncDecl(string name, string* params, Stmt* body)
        | Return(Expr? value)
        | If(Expr test, Stmt* consequent, Stmt* alternate)
        | While(Expr test, Stmt* body)
        | For(Stmt? init, Expr? test, Expr? update, Stmt* body)
        | ForIn(string name, Expr right, Stmt* body)
        | ForOf(string name, Expr right, Stmt* body)
        | Block(Stmt* body)
        | Break
        | Continue
        | Throw(Expr argument)
        | Try(Stmt* block, CatchClause? handler, Stmt* finalizer)
        | Empty

    Declarator = (string name, Expr? init) unique

    CatchClause = (string? param, Stmt* body) unique

    Expr
        = NumLit(number value)
        | StrLit(string value)
        | BoolLit(boolean value)
        | NullLit
        | UndefinedLit
        | ArrayExpr(Expr* elements)
        | ObjectExpr(ObjProp* properties)
        | Ident(string name)
        | BinOp(JsCore.BinOpKind op, Expr left, Expr right)
        | LogicalOp(JsCore.LogicalKind op, Expr left, Expr right)
        | UnaryOp(JsCore.UnaryKind op, Expr argument)
        | UpdateOp(JsCore.UpdateKind op, Expr argument, boolean prefix)
        | Assign(Expr left, Expr right)
        | CompoundAssign(JsCore.BinOpKind op, Expr left, Expr right)
        | Member(Expr object, Expr property, boolean computed)
        | Optional(Expr object, Expr property, boolean computed)
        | Call(Expr callee, Expr* arguments)
        | New(Expr callee, Expr* arguments)
        | Cond(Expr test, Expr consequent, Expr alternate)
        | Arrow(string* params, ArrowBody body)
        | FuncExpr(string? name, string* params, Stmt* body)
        | Spread(Expr argument)
        | Template(TemplatePart* parts)
        | Typeof(Expr argument)
        | Instanceof(Expr left, Expr right)
        | Void(Expr argument)
        | Delete(Expr object, Expr property, boolean computed)
        | This
        | Sequence(Expr* exprs)
        | NullishCoalesce(Expr left, Expr right)

    ArrowBody
        = ArrowExpr(Expr expr)
        | ArrowBlock(Stmt* body)

    ObjProp
        = PropInit(Expr key, Expr value, boolean computed)
        | PropSpread(Expr argument)

    TemplatePart
        = TemplateStr(string value)
        | TemplateExpr(Expr expr)
}
]=]