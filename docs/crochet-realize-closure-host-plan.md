# crochet-realize closure-host plan

This document proposes the next ASDL revision for `crochet-realize/` so realization can support a true **closure host contract**, not only a textual-source proto body that later happens to produce a closure.

---

## 1. Domain summary

### Nouns

- host contract
- proto
- parameter
- capture
- textual proto body
- closure proto body
- expression
- statement
- artifact mode
- shape key
- artifact key
- install catalog

### Identity nouns

The stable realization identity noun remains:

- `Proto`

A proto is still the correct memo/install/cache boundary.

### Sum types

The important domain sums are:

- **host contract**
  - textual Lua host
  - closure host
  - bytecode-oriented Lua host

- **proto family**
  - text proto
  - closure proto

- **closure statement**
  - local bind
  - local set
  - effect
  - return
  - if
  - for-range
  - while

- **closure expression**
  - param ref
  - capture ref
  - local ref
  - literal value
  - call
  - index
  - unary op
  - binary op

### Containment

The proposed authored containment is:

```text
Catalog
├── HostContract
├── Proto*
│   ├── params*
│   ├── captures*
│   └── Body
│       ├── TextBlock        -- textual realization family
│       └── ClosureBlock     -- closure-host family
```

### Coupling points

- host contract ↔ which proto body family is legal
- closure statements ↔ closure installer strategy
- package/artifact mode ↔ whether source/blob materialization matters
- capture binding ↔ artifact key
- body family ↔ shape key

---

## 2. Core diagnosis

Current `crochet-realize` is structurally rich, but its body language is still fundamentally a **textual source language**:

- `LineNode`
- `BlankNode`
- `NestNode`
- `TextPart`
- `ParamRef`
- `CaptureRef`

That means current `ClosureMode` is still basically:

```text
structured text proto
-> render source
-> load source
-> closure artifact
```

That is a valid realization path, but it is **not** yet a true closure-host realization language.

The missing language is:

> a small closure-body language whose leaves can be realized directly as host closures.

---

## 3. ASDL proposal

### 3.1 Source phase

```asdl
module CrochetRealizeRuntime {
    ValueRef = (
        string debug_name,
        any value
    ) unique
}

module CrochetRealizeSource {
    Catalog = (
        Proto* protos,
        string entry_name,
        HostContract host
    ) unique

    Proto
        = TextProto(
              string name,
              string* params,
              Capture* captures,
              TextBlock body
          )
        | ClosureProto(
              string name,
              string* params,
              Capture* captures,
              ClosureBlock body
          )

    Capture = (
        string name,
        CrochetRealizeRuntime.ValueRef value
    ) unique

    TextBlock = (
        TextNode* nodes
    ) unique

    TextNode
        = LineNode(TextPart* parts)
        | BlankNode()
        | NestNode(TextLine opener, TextBlock body, TextLine closer)

    TextLine = (
        TextPart* parts
    ) unique

    TextPart
        = TextPart(string text)
        | ParamRef(string name)
        | CaptureRef(string name)

    ClosureBlock = (
        ClosureStmt* stmts
    ) unique

    ClosureStmt
        = LetStmt(string name, ClosureExpr value)
        | SetStmt(string name, ClosureExpr value)
        | EffectStmt(ClosureExpr expr)
        | ReturnStmt(ClosureExpr value)
        | IfStmt(ClosureExpr cond, ClosureBlock then_body, ClosureBlock else_body)
        | ForRangeStmt(string name, ClosureExpr start, ClosureExpr stop, ClosureExpr step, ClosureBlock body)
        | WhileStmt(ClosureExpr cond, ClosureBlock body)

    ClosureExpr
        = ParamExpr(string name)
        | CaptureExpr(string name)
        | LocalExpr(string name)
        | LiteralExpr(CrochetRealizeRuntime.ValueRef value)
        | CallExpr(ClosureExpr fn, ClosureExpr* args)
        | IndexExpr(ClosureExpr base, ClosureExpr key)
        | UnaryExpr(UnaryOp op, ClosureExpr value)
        | BinaryExpr(BinaryOp op, ClosureExpr lhs, ClosureExpr rhs)

    UnaryOp
        = NotOp()
        | NegOp()
        | LenOp()

    BinaryOp
        = AddOp()
        | SubOp()
        | MulOp()
        | DivOp()
        | ModOp()
        | EqOp()
        | NeOp()
        | LtOp()
        | LeOp()
        | GtOp()
        | GeOp()
        | AndOp()
        | OrOp()

    HostContract
        = LuaTextHost(PackageMode package)
        | LuaClosureHost(ClosureMode mode)
        | LuaBytecodeHost(PackageMode package)

    PackageMode
        = SourceMode()
        | ClosureMode()
        | BytecodeMode()

    ClosureMode
        = DirectClosureMode()
        | ClosureBundleMode()
}
```

### 3.2 Checked phase

The checked phase should keep the same family split, but resolve names to IDs.

```asdl
module CrochetRealizeChecked {
    Catalog = (
        Proto* protos,
        number entry_proto_id,
        HostContract host
    ) unique

    Proto
        = TextProto(
              ProtoHeader header,
              Param* params,
              Capture* captures,
              TextBlock body
          )
        | ClosureProto(
              ProtoHeader header,
              Param* params,
              Capture* captures,
              ClosureBlock body
          )

    ProtoHeader = (
        string name,
        number proto_id
    ) unique

    Param = (
        string name,
        number param_id
    ) unique

    Capture = (
        string name,
        number capture_id,
        CrochetRealizeRuntime.ValueRef value
    ) unique

    TextBlock = (
        TextNode* nodes
    ) unique

    TextNode
        = LineNode(TextPart* parts)
        | BlankNode()
        | NestNode(TextLine opener, TextBlock body, TextLine closer)

    TextLine = (
        TextPart* parts
    ) unique

    TextPart
        = TextPart(string text)
        | ParamRef(number param_id)
        | CaptureRef(number capture_id)

    ClosureBlock = (
        ClosureStmt* stmts
    ) unique

    ClosureStmt
        = LetStmt(LocalHeader local_header, ClosureExpr value)
        | SetStmt(number local_id, ClosureExpr value)
        | EffectStmt(ClosureExpr expr)
        | ReturnStmt(ClosureExpr value)
        | IfStmt(ClosureExpr cond, ClosureBlock then_body, ClosureBlock else_body)
        | ForRangeStmt(LocalHeader local_header, ClosureExpr start, ClosureExpr stop, ClosureExpr step, ClosureBlock body)
        | WhileStmt(ClosureExpr cond, ClosureBlock body)

    LocalHeader = (
        string name,
        number local_id
    ) unique

    ClosureExpr
        = ParamExpr(number param_id)
        | CaptureExpr(number capture_id)
        | LocalExpr(number local_id)
        | LiteralExpr(CrochetRealizeRuntime.ValueRef value)
        | CallExpr(ClosureExpr fn, ClosureExpr* args)
        | IndexExpr(ClosureExpr base, ClosureExpr key)
        | UnaryExpr(UnaryOp op, ClosureExpr value)
        | BinaryExpr(BinaryOp op, ClosureExpr lhs, ClosureExpr rhs)

    UnaryOp
        = NotOp()
        | NegOp()
        | LenOp()

    BinaryOp
        = AddOp()
        | SubOp()
        | MulOp()
        | DivOp()
        | ModOp()
        | EqOp()
        | NeOp()
        | LtOp()
        | LeOp()
        | GtOp()
        | GeOp()
        | AndOp()
        | OrOp()

    HostContract
        = LuaTextHost(PackageMode package)
        | LuaClosureHost(ClosureMode mode)
        | LuaBytecodeHost(PackageMode package)

    PackageMode
        = SourceMode()
        | ClosureMode()
        | BytecodeMode()

    ClosureMode
        = DirectClosureMode()
        | ClosureBundleMode()
}
```

### 3.3 Plan phase

The plan phase should stop pretending that all protos collapse to one textual source blob shape.

```asdl
module CrochetRealizePlan {
    Catalog = (
        ProtoPlan* protos,
        number entry_proto_id,
        HostContract host
    ) unique

    ProtoPlan
        = TextProtoPlan(
              string name,
              number proto_id,
              string chunk_name,
              string shape_key,
              string artifact_key,
              string source,
              CapturePlan* captures
          )
        | ClosureProtoPlan(
              string name,
              number proto_id,
              string artifact_name,
              string shape_key,
              string artifact_key,
              ClosurePlanBlock body,
              CapturePlan* captures
          )

    CapturePlan = (
        string name,
        number capture_id,
        CrochetRealizeRuntime.ValueRef value,
        number bind_index
    ) unique

    ClosurePlanBlock = (
        ClosurePlanStmt* stmts
    ) unique

    ClosurePlanStmt
        = LetPlan(number local_id, ClosurePlanExpr value)
        | SetPlan(number local_id, ClosurePlanExpr value)
        | EffectPlan(ClosurePlanExpr expr)
        | ReturnPlan(ClosurePlanExpr value)
        | IfPlan(ClosurePlanExpr cond, ClosurePlanBlock then_body, ClosurePlanBlock else_body)
        | ForRangePlan(number local_id, ClosurePlanExpr start, ClosurePlanExpr stop, ClosurePlanExpr step, ClosurePlanBlock body)
        | WhilePlan(ClosurePlanExpr cond, ClosurePlanBlock body)

    ClosurePlanExpr
        = ParamExpr(number param_id)
        | CaptureExpr(number capture_id)
        | LocalExpr(number local_id)
        | LiteralExpr(CrochetRealizeRuntime.ValueRef value)
        | CallExpr(ClosurePlanExpr fn, ClosurePlanExpr* args)
        | IndexExpr(ClosurePlanExpr base, ClosurePlanExpr key)
        | UnaryExpr(UnaryOp op, ClosurePlanExpr value)
        | BinaryExpr(BinaryOp op, ClosurePlanExpr lhs, ClosurePlanExpr rhs)

    UnaryOp
        = NotOp()
        | NegOp()
        | LenOp()

    BinaryOp
        = AddOp()
        | SubOp()
        | MulOp()
        | DivOp()
        | ModOp()
        | EqOp()
        | NeOp()
        | LtOp()
        | LeOp()
        | GtOp()
        | GeOp()
        | AndOp()
        | OrOp()

    HostContract
        = LuaTextHost(PackageMode package)
        | LuaClosureHost(ClosureMode mode)
        | LuaBytecodeHost(PackageMode package)

    PackageMode
        = SourceMode()
        | ClosureMode()
        | BytecodeMode()

    ClosureMode
        = DirectClosureMode()
        | ClosureBundleMode()
}
```

### 3.4 Install phase

Install should now reflect two different artifact worlds explicitly:

```asdl
module CrochetRealizeLua {
    Catalog = (
        ProtoInstall* protos,
        number entry_proto_id,
        InstallMode artifact_mode
    ) unique

    ProtoInstall
        = SourceInstall(
              string name,
              number proto_id,
              string chunk_name,
              string artifact_key,
              string source
          )
        | ClosureInstall(
              string name,
              number proto_id,
              string artifact_key,
              CaptureInstall* captures,
              ClosureInstallPlan plan
          )
        | BytecodeInstall(
              string name,
              number proto_id,
              string chunk_name,
              string artifact_key,
              string source,
              CaptureInstall* captures
          )

    ClosureInstallPlan = (
        CrochetRealizePlan.ClosurePlanBlock body
    ) unique

    CaptureInstall = (
        string name,
        number capture_id,
        number bind_index,
        CrochetRealizeRuntime.ValueRef value
    ) unique

    InstallMode
        = SourceArtifact()
        | ClosureArtifact()
        | BytecodeArtifact()
}
```

---

## 4. Phase plan

### Phase 1 — `check_realize`
Verb: **check**

Consumes:
- string refs for params/captures/locals
- host/body consistency

Produces:
- ID-resolved checked protos
- validated host contract

### Phase 2 — `lower_realize`
Verb: **plan**

Consumes:
- checked textual or closure body
- capture ordering decisions
- artifact identity decisions

Produces:
- `TextProtoPlan` or `ClosureProtoPlan`
- `shape_key`
- `artifact_key`

### Phase 3 — `prepare_install`
Verb: **prepare**

Consumes:
- plan family
- host contract

Produces:
- mode-specific install variants

### Phase 4 — `install`
Verb: **install**

Consumes:
- install variant

Produces:
- source artifact
- closure artifact
- bytecode artifact

---

## 5. Boundary inventory

If this revision is implemented, these boundaries change.

### `crochet-realize/boundaries/crochet_realize_source_catalog.lua`
- `CrochetRealizeSource.Catalog:check_realize()`
- must validate host/body compatibility
- must resolve closure locals as well as param/capture refs

### `crochet-realize/boundaries/crochet_realize_checked_catalog.lua`
- `CrochetRealizeChecked.Catalog:lower_realize()`
- must branch structurally on `TextProto` vs `ClosureProto`
- textual path still renders source
- closure path lowers to closure plan IR

### `crochet-realize/boundaries/crochet_realize_plan_catalog.lua`
- `CrochetRealizePlan.Catalog:prepare_install()`
- must distinguish `TextProtoPlan` vs `ClosureProtoPlan`
- must install against host contract, not only package mode

### `crochet-realize/boundaries/crochet_realize_lua_catalog.lua`
- `CrochetRealizeLua.Catalog:install()`
- source path: current load/render flow remains honest
- closure path: direct closure builder / host installer
- bytecode path: current source+dump path can remain transitional

---

## 6. Leaf-driven constraints

The closure-host leaf should be able to say:

- I already know I am realizing a `ClosureProtoPlan`
- all refs are numeric IDs, not unresolved names
- captures arrive in a stable bind order
- my control forms are explicit statements, not textual indentation tricks
- I do not have to rediscover whether this is text or closure at install time

The textual leaf should be able to say:

- I am only rendering textual proto bodies
- I own source/chunk naming policy
- bytecode packaging decisions are host/install policy, not semantic policy

That is the main reason to split the proto families rather than keeping a giant mixed installer.

---

## 7. Why this is the right split

This split preserves a key rule from `realization-as-host-contract.md`:

> if installation has honest nouns, model them

The existing textual proto body is still valid.
It remains the right language for source-oriented and bytecode-oriented host contracts.

But a direct closure host has different honest nouns:

- local bind
- local set
- effect
- control statement
- closure artifact plan

Those nouns deserve their own realization language.

---

## 8. Recommended implementation sequence

Do not switch everything at once.

### Step 1
Add the new ASDL families without removing the textual path.

### Step 2
Implement checked resolution for the closure family only for a tiny honest subset:
- `LetStmt`
- `ReturnStmt`
- `CallExpr`
- `ParamExpr`
- `CaptureExpr`
- `LocalExpr`
- `LiteralExpr`

### Step 3
Implement a direct closure installer for that subset.

### Step 4
Add control forms:
- `IfStmt`
- `ForRangeStmt`
- `WhileStmt`
- `SetStmt`

### Step 5
Only after closure-host leaves are clean should `crochet.lua` decide how much of that should surface directly in the ergonomic API.

---

## 9. Quality gates for the revision

Before calling the revision done:

- closure-host protos must no longer require textual source rendering in their primary path
- text-host protos must remain supported cleanly
- `shape_key` must distinguish text vs closure body families honestly
- `artifact_key` must include capture binding identity honestly
- tests must cover both text and closure host contracts
- installer code must not rediscover semantic structure through string parsing or textual hacks

---

## 10. Short thesis

The revision is:

> keep textual realization as one honest host contract, but add a separate closure-host proto family so closure artifacts are realized from a real closure language instead of being treated as source rendering in disguise.
