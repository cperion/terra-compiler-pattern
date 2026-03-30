# parser — Grammar-to-Closure Parser Compiler

A PEG grammar IS an ASDL. Each rule is a variant. Each alternative is a sum
 type. The parser compiler produces closures specialized for that grammar.
No interpreter. No virtual dispatch per rule. Just baked byte comparisons
that LuaJIT traces into native branch chains.

## Architecture

```
Grammar ASDL (PEG rules + patterns)
  -> compile (terminal: ASDL -> closure tree)
Compiled parser closure tree
  -> LuaJIT traces through hot parsing paths
```

This example now keeps **one canonical compiler implementation** only:

- `GrammarSource.Grammar:compile()`
- implemented in `examples/parser/parser_compile.lua`

The old baseline/opt split is gone. The kept implementation is the faster,
cleaner one: pre-bound references, scan fusion, and specialized hot paths.

## File structure

| File | Role |
|------|------|
| `parser_asdl.lua` | ASDL: `GrammarSource` and `GrammarCompiled` |
| `parser_schema.lua` | Pipeline contract |
| `parser_compile.lua` | Canonical terminal: grammar ASDL → parser closure tree |
| `parser_builder.lua` | DSL helpers: `P.lit`, `P.seq`, `P.alt`, `P.star`, etc. |
| `parser_demo.lua` | Smoke tests + JSON benchmark |
| `parser_bench.lua` | Head-to-head benchmark against LuaJIT alternatives |
| `parsers/` | Canonical authored grammars we want to reuse |

## Canonical parser set

These grammars live in `examples/parser/parsers/`:

- `json.lua`
- `csv.lua`
- `http.lua`
- `http_response.lua`
- `asdl.lua`
- `sql.lua`
- `ini.lua`
- `s_expr.lua`
- `uri.lua`
- `ecmascript.lua`

They are authored grammars, not special runtime cases.

## Usage

```lua
local spec = require("examples.parser.parser_schema")
local grammars = require("examples.parser.parsers")
local T = spec.ctx

local json = grammars.json(T)
local parser = json:compile()

local caps, pos = parser('{"x": 1}')
```

## Notes on the included grammars

- `json` is a validating/capturing JSON grammar.
- `csv` handles quoted fields and multiple rows.
- `http` recognizes an HTTP request line plus headers.
- `http_response` recognizes an HTTP status line, headers, and optional body.
- `asdl` recognizes a practical ASDL subset used in this repository.
- `sql` recognizes a canonical `SELECT ... FROM ... WHERE ...` subset with `=`, `IN`, and `IS [NOT] NULL` predicates.
- `ini` recognizes sectioned INI files with comments.
- `s_expr` recognizes atoms, strings, and nested lists.
- `uri` recognizes generic scheme-based URIs with optional authority, query, and fragment.
- `ecmascript` recognizes a broad canonical ECMAScript script/module surface grammar intended to replace the old minimal JS frontend.

## Performance

Typical result shape on this machine:

- JSON small/medium/large: competitive with or faster than LPeg
- large JSON: substantially faster than LPeg in repeated runs
- still pure LuaJIT, with no C parser engine on our side

## Run

```bash
luajit examples/parser/parser_demo.lua
luajit examples/parser/parser_bench.lua
```
