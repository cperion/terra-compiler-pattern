return [=[
-- ============================================================================
-- JS compiler ASDL
-- ----------------------------------------------------------------------------
-- Purpose:
--   Complete type language for a JS-subset → LuaJIT closure-tree compiler.
--
-- Architecture:
--   JsSource           parsed JS AST (the source program)
--   JsResolved         scope-resolved AST (names → slots)
--   JsClassified       trace-classification (hot vs cold)
--   JsMachine          compiled closure-tree machine description
--
-- The source ASDL IS the architecture. Every JS concept the compiler
-- handles must appear here as an explicit type.
-- ============================================================================


-- ============================================================================
-- JsCore: shared vocabulary across all phases
-- ============================================================================
module JsCore {

    BinOpKind
        = Add | Sub | Mul | Div | Mod | Exp
        | BitAnd | BitOr | BitXor | Shl | Shr | UShr
        | EqEq | NotEq | EqEqEq | NotEqEq
        | Lt | Le | Gt | Ge

    LogicalKind = LogAnd | LogOr

    UnaryKind = UNeg | UPos | UBitNot | ULogNot

    UpdateKind = Inc | Dec

    VarKind = Var | Let | Const
}


-- ============================================================================
-- JsSource: parsed JS AST — the source program
-- ----------------------------------------------------------------------------
-- This is the direct output of the parser. No derived data.
-- Every node represents independent authored structure.
-- ============================================================================
module JsSource {

    Program = (Stmt* body) unique

    Stmt
        = ExprStmt(Expr expr)
        | VarDecl(JsCore.VarKind var_kind, Declarator* decls)
        | FuncDecl(string name, string* params, Stmt* body)
        | Return(Expr? value)
        | If(Expr test, Stmt consequent, Stmt? alternate)
        | While(Expr test, Stmt body)
        | DoWhile(Stmt body, Expr test)
        | For(Stmt? init, Expr? test, Expr? update, Stmt body)
        | ForIn(JsCore.VarKind var_kind, string name, Expr right, Stmt body)
        | ForOf(JsCore.VarKind var_kind, string name, Expr right, Stmt body)
        | Switch(Expr discriminant, SwitchCase* cases)
        | Label(string name, Stmt body)
        | Block(Stmt* body)
        | Break(string? label)
        | Continue(string? label)
        | Throw(Expr argument)
        | Try(Stmt block, CatchClause? handler, Stmt? finalizer)
        | Empty

    Declarator = (string name, Expr? init) unique

    CatchClause = (string? param, Stmt body) unique

    SwitchCase = (Expr? test, Stmt* body) unique

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


-- ==========================================================================
-- JsSurface: parsed JS surface AST
-- ----------------------------------------------------------------------------
-- This is the direct parser result after lexing. It currently mirrors the
-- supported JS subset while giving the frontend a real lowering boundary.
-- ==========================================================================
module JsSurface {

    Program = (Stmt* body) unique

    Stmt
        = ExprStmt(Expr expr)
        | VarDecl(JsCore.VarKind var_kind, Declarator* decls)
        | FuncDecl(string name, string* params, Stmt* body)
        | Return(Expr? value)
        | If(Expr test, Stmt consequent, Stmt? alternate)
        | While(Expr test, Stmt body)
        | DoWhile(Stmt body, Expr test)
        | For(Stmt? init, Expr? test, Expr? update, Stmt body)
        | ForIn(JsCore.VarKind var_kind, string name, Expr right, Stmt body)
        | ForOf(JsCore.VarKind var_kind, string name, Expr right, Stmt body)
        | Switch(Expr discriminant, SwitchCase* cases)
        | Label(string name, Stmt body)
        | With(Expr object, Stmt body)
        | Import(string? default_name, string? namespace_name, ImportBinding* named, string? from)
        | ExportNamed(ExportBinding* bindings, string? from)
        | ExportAll(string? alias, string from)
        | ExportDefaultExpr(Expr expr)
        | ExportDefaultDecl(Stmt decl)
        | ExportDecl(Stmt decl)
        | ClassDecl(string name, Expr? super_class, ClassMember* items)
        | Block(Stmt* body)
        | Break(string? label)
        | Continue(string? label)
        | Throw(Expr argument)
        | Try(Stmt block, CatchClause? handler, Stmt? finalizer)
        | Empty

    Declarator = (string name, Expr? init) unique

    CatchClause = (string? param, Stmt body) unique

    SwitchCase = (Expr? test, Stmt* body) unique

    ImportBinding = (string imported_name, string local_name) unique

    ExportBinding = (string local_name, string exported_name) unique

    MethodKind = MethodNormal | MethodGet | MethodSet

    ClassMember
        = Method(string name, string* params, Stmt* body, boolean is_static, boolean is_private, MethodKind method_kind)
        | Field(string name, Expr? init, boolean is_static, boolean is_private)

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
        | ClassExpr(string? name, Expr? super_class, ClassMember* items)
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


-- ============================================================================
-- JsResolved: scope-resolved AST
-- ----------------------------------------------------------------------------
-- Meaning:
--   JsSource -> resolve -> JsResolved
--
-- This phase consumes:
--   - variable name → slot binding
--   - scope depth and slot indices
--   - free variable detection (globals)
--
-- After this phase, no name lookups remain. Every variable reference is a
-- typed slot address.
-- ============================================================================
module JsResolved {

    Program = (Stmt* body, Scope scope) unique

    Scope = (number depth, number slot_count, Binding* bindings) unique

    Binding = (string name, JsCore.VarKind kind, number slot) unique

    Slot = LocalSlot(number depth, number index, JsCore.VarKind binding_kind)
         | GlobalSlot(string name)

    Stmt
        = ExprStmt(Expr expr)
        | VarDecl(JsCore.VarKind var_kind, RDeclarator* decls)
        | FuncDecl(string name, Slot target, string* params, Stmt* body, Scope scope)
        | Return(Expr? value)
        | If(Expr test, Stmt consequent, Stmt? alternate)
        | While(Expr test, Stmt body, number* continue_targets)
        | DoWhile(Stmt body, Expr test, number* continue_targets)
        | For(Stmt? init, Expr? test, Expr? update, Stmt body, Scope? scope, number* continue_targets)
        | ForIn(JsCore.VarKind var_kind, Slot target, Expr right, Stmt body, Scope? scope, number* continue_targets)
        | ForOf(JsCore.VarKind var_kind, Slot target, Expr right, Stmt body, Scope? scope, number* continue_targets)
        | Switch(Expr discriminant, RSwitchCase* cases, Scope? scope)
        | Label(number target_id, Stmt body)
        | Block(Stmt* body, Scope scope)
        | Break(number? target_id)
        | Continue(number? target_id)
        | Throw(Expr argument)
        | Try(Stmt block, CatchClause? handler, Stmt? finalizer)
        | Empty

    RDeclarator = (Slot target, Expr? init) unique

    CatchClause = (Slot? param, Stmt body, Scope scope) unique

    RSwitchCase = (Expr? test, Stmt* body) unique

    Expr
        = NumLit(number value)
        | StrLit(string value)
        | BoolLit(boolean value)
        | NullLit
        | UndefinedLit
        | ArrayExpr(Expr* elements)
        | ObjectExpr(RObjProp* properties)
        | SlotRef(Slot slot)
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
        | Arrow(string* params, ArrowBody body, Scope scope)
        | FuncExpr(string? name, string* params, Stmt* body, Scope scope)
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

    RObjProp
        = PropInit(Expr key, Expr value, boolean computed)
        | PropSpread(Expr argument)

    TemplatePart
        = TemplateStr(string value)
        | TemplateExpr(Expr expr)
}


-- ==========================================================================
-- JsModuleSource: authored module inventory after surface lowering
-- --------------------------------------------------------------------------
-- This is an experimental scaffold for the future native module path.
-- It separates import/export declarations from the executable per-file body.
-- ==========================================================================
module JsModuleSource {

    ModuleId = (string value) unique

    Module = (
        ModuleId? self_id,
        ImportDecl* imports,
        ExportDecl* exports,
        JsSource.Stmt* eval_body
    ) unique

    ModuleGraph = (Module* modules, ModuleId? entry) unique

    ImportDecl
        = ImportModule(string specifier)
        | ImportDefault(string local_name, string specifier)
        | ImportNamespace(string local_name, string specifier)
        | ImportNamed(string imported_name, string local_name, string specifier)

    ExportDecl
        = ExportLocal(string local_name, string exported_name)
        | ExportDefaultExpr(JsSource.Expr expr)
        | ExportDefaultDecl(JsSource.Stmt decl, string local_name)
        | ExportFrom(string imported_name, string exported_name, string specifier)
        | ExportAll(string specifier)
        | ExportAllAs(string exported_name, string specifier)
}


-- ==========================================================================
-- JsModuleLinked: future graph-linked native module form
-- --------------------------------------------------------------------------
-- This phase is not implemented yet; it names the intended linked graph
-- shape for native ESM-like semantics with explicit binding identity.
-- ==========================================================================
module JsModuleResolved {

    Module = (
        JsModuleSource.ModuleId? self_id,
        ImportDecl* imports,
        ExportDecl* exports,
        JsResolved.Stmt* eval_body,
        JsResolved.Scope scope
    ) unique

    ModuleGraph = (Module* modules, JsModuleSource.ModuleId? entry) unique

    ImportDecl
        = ImportModule(string specifier)
        | ImportDefault(JsResolved.Slot local_slot, string specifier)
        | ImportNamespace(JsResolved.Slot local_slot, string specifier)
        | ImportNamed(string imported_name, JsResolved.Slot local_slot, string specifier)

    ExportDecl
        = ExportLocal(JsResolved.Slot local_slot, string exported_name)
        | ExportDefaultExpr(JsResolved.Expr expr)
        | ExportFrom(string imported_name, string exported_name, string specifier)
        | ExportAll(string specifier)
        | ExportAllAs(string exported_name, string specifier)
}


-- ==========================================================================
-- JsModuleLinked: future graph-linked native module form
-- --------------------------------------------------------------------------
-- This phase is not implemented yet; it names the intended linked graph
-- shape for native ESM-like semantics with explicit binding identity.
-- ==========================================================================
module JsModuleLinked {

    ModuleGraph = (LinkedModule* modules, JsModuleSource.ModuleId? entry) unique

    LinkedModule = (
        JsModuleSource.ModuleId id,
        LinkedImport* imports,
        LinkedExport* exports,
        JsResolved.Stmt* eval_body,
        JsResolved.Scope scope
    ) unique

    ImportBindingKind = ValueImport | NamespaceImport | SideEffectImport

    LinkedImport = (
        JsResolved.Slot? local_slot,
        JsModuleSource.ModuleId from_module,
        string import_name,
        ImportBindingKind kind,
        number import_cell
    ) unique

    LinkedExport = (string exported_name, ExportBinding binding) unique

    ExportBinding
        = LocalSlotExport(JsResolved.Slot slot, number cell)
        | ExprExport(JsResolved.Expr expr, number cell)
        | ReExportCell(JsModuleSource.ModuleId from_module, number cell)
        | NamespaceExport(JsModuleSource.ModuleId from_module)
}


-- ============================================================================
-- JsMachine: compiled closure-tree machine
-- ----------------------------------------------------------------------------
-- Meaning:
--   JsResolved -> compile -> JsMachine
--
-- This is the terminal output language. Each node compiles to a closure
-- (the gen) that takes a frame (the param/state) and produces a JS value.
--
-- The machine has:
--   gen   = the closure shape (monomorphic code path)
--   param = captured compile-time constants (upvalues)
--   state = frame array E (mutable local slots)
--
-- After compilation, no ASDL interpretation remains. The closure tree IS
-- the executable machine that LuaJIT traces through.
-- ============================================================================
module JsMachine {

    CompiledProgram = (
        number frame_size,
        number total_closures
    ) unique
}
]=]
