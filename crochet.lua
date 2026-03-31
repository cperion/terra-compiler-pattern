-- crochet.lua
-- Tiny structural proto-authoring and code-assembly library with explicit
-- symbols and fast flattening.
--
-- Philosophy:
--   - compose structure, not concatenated strings
--   - treat symbols as identities, not raw names
--   - render in one predictable pass
--   - make proto families explicit instead of hiding install structure
--
-- Core pieces:
--   - fragments: text, line, block, indent, join, blank
--   - symbols: fixed, keyed, temp
--   - rendering: render(node[, opts]) -> string
--
-- This module is intentionally small. It is for code generation, unrolling,
-- inlining, small backend emitters, and lightweight proto authoring.
--
-- Proto surface:
--   - text/source/bytecode proto family: proto/catalog with host_source() or
--     host_bytecode()
--   - direct closure proto family: closure_proto/closure_body with
--     host_closure()
--   - proto pipeline: check -> lower -> prepare -> install -> compile
--
-- Host-selection rule of thumb:
--   - host_source()   : use when generated source is the honest installed
--                       artifact
--   - host_bytecode() : use when serialized/restorable bytecode is the honest
--                       install artifact
--   - host_closure()  : use when direct closure installation is the honest
--                       host contract
--
-- Bytecode is mainly an installation artifact choice, not a hot-loop speed
-- choice. Source kernels loaded via load/loadstring remain a valid proto path
-- when exact LuaJIT code shape is itself the artifact.

local Crochet = {}
local _unpack = table.unpack or unpack

-- ============================================================================
-- Internal tagging helpers
-- ============================================================================

local function tag(kind, t)
  t.kind = kind
  return t
end

local function is_node(x)
  return type(x) == "table" and type(x.kind) == "string"
end

local function is_symbol(x)
  return type(x) == "table" and x.__crochet_symbol == true
end

local function list_copy(xs)
  local out = {}
  for i = 1, #xs do
    out[i] = xs[i]
  end
  return out
end

-- ============================================================================
-- Symbol environment
-- ============================================================================

local Symbols = {}
Symbols.__index = Symbols

local function make_symbol(name, family, key, class)
  return {
    __crochet_symbol = true,
    name = name,
    family = family,
    key = key,
    class = class,
  }
end

--- Create a new symbol environment.
function Crochet.symbols(opts)
  opts = opts or {}
  return setmetatable({
    keyed_cache = {},
    temp_counters = {},
    compact = opts.compact == true,
  }, Symbols)
end

--- Stable fixed symbol by explicit name.
function Symbols:fixed(name)
  assert(type(name) == "string" and name ~= "", "fixed(name): name must be non-empty string")
  return make_symbol(name, "fixed", name, "fixed")
end

--- Stable keyed symbol: same family+key => same symbol object/name.
function Symbols:keyed(family, key)
  assert(type(family) == "string" and family ~= "", "keyed(family, key): family must be non-empty string")
  local fam = self.keyed_cache[family]
  if fam == nil then
    fam = {}
    self.keyed_cache[family] = fam
  end
  local sym = fam[key]
  if sym ~= nil then
    return sym
  end

  local suffix = tostring(key)
  local name
  if self.compact then
    name = family:sub(1, 1) .. "_" .. suffix
  else
    name = family .. "_" .. suffix
  end

  sym = make_symbol(name, family, key, "keyed")
  fam[key] = sym
  return sym
end

--- Fresh temporary symbol.
function Symbols:temp(family)
  family = family or "tmp"
  assert(type(family) == "string" and family ~= "", "temp([family]): family must be non-empty string")
  local n = (self.temp_counters[family] or 0) + 1
  self.temp_counters[family] = n

  local name
  if self.compact then
    name = family:sub(1, 1) .. "_" .. tostring(n)
  else
    name = family .. "_" .. tostring(n)
  end

  return make_symbol(name, family, n, "temp")
end

--- Render symbol name.
function Symbols:name(sym)
  assert(is_symbol(sym), "name(sym): expected Crochet symbol")
  return sym.name
end

Crochet.Symbols = Symbols

-- ============================================================================
-- Fragment constructors
-- ============================================================================

local function normalize_part(x)
  if x == nil then
    return nil
  end
  local tx = type(x)
  if tx == "string" or tx == "number" or tx == "boolean" then
    return tostring(x)
  end
  if is_symbol(x) or is_node(x) then
    return x
  end
  error("unsupported fragment part type: " .. tx, 3)
end

local function normalize_parts(args)
  local out = {}
  for i = 1, #args do
    local v = normalize_part(args[i])
    if v ~= nil then
      out[#out + 1] = v
    end
  end
  return out
end

--- Raw text fragment. Does not append a newline.
function Crochet.text(...)
  local parts = normalize_parts({...})
  return tag("text", { parts = parts })
end

--- Line fragment. Appends one newline during rendering.
function Crochet.line(...)
  local parts = normalize_parts({...})
  return tag("line", { parts = parts })
end

--- Blank line fragment. Emits exactly one newline.
function Crochet.blank()
  return tag("blank", {})
end

--- Block fragment. Children render in sequence.
function Crochet.block(children)
  assert(type(children) == "table", "block(children): children must be table")
  return tag("block", { children = list_copy(children) })
end

--- Indentation fragment. Indents all child lines by one level.
function Crochet.indent(node, levels)
  assert(node ~= nil, "indent(node[, levels]): node is required")
  levels = levels or 1
  assert(type(levels) == "number" and levels >= 0, "indent(node[, levels]): levels must be non-negative number")
  return tag("indent", { node = node, levels = levels })
end

--- Join nodes with separator.
function Crochet.join(nodes, sep)
  assert(type(nodes) == "table", "join(nodes, sep): nodes must be table")
  local sep_node
  if sep == nil or sep == "" then
    sep_node = nil
  elseif is_node(sep) then
    sep_node = sep
  else
    sep_node = Crochet.text(sep)
  end

  local parts = {}
  for i = 1, #nodes do
    local n = nodes[i]
    if n ~= nil then
      if #parts > 0 and sep_node ~= nil then
        parts[#parts + 1] = sep_node
      end
      parts[#parts + 1] = n
    end
  end
  return Crochet.block(parts)
end

--- Conditionally include a node.
function Crochet.maybe(cond, node)
  if cond then
    return node
  end
  return Crochet.block({})
end

--- Interleave nodes with a separator node or string.
function Crochet.intersperse(nodes, sep)
  assert(type(nodes) == "table", "intersperse(nodes, sep): nodes must be table")
  local sep_node = is_node(sep) and sep or Crochet.text(sep or "")
  local out = {}
  for i = 1, #nodes do
    if nodes[i] ~= nil then
      if #out > 0 then
        out[#out + 1] = sep_node
      end
      out[#out + 1] = nodes[i]
    end
  end
  return Crochet.block(out)
end

-- ============================================================================
-- Rendering
-- ============================================================================

local Renderer = {}
Renderer.__index = Renderer

local function default_symbol_renderer(sym)
  return sym.name
end

local function make_renderer(opts)
  opts = opts or {}
  return setmetatable({
    buf = {},
    indent_text = opts.indent or "  ",
    level = 0,
    at_line_start = true,
    symbol_renderer = opts.symbol_renderer or default_symbol_renderer,
  }, Renderer)
end

function Renderer:push_raw(s)
  self.buf[#self.buf + 1] = s
end

function Renderer:push_indent_if_needed()
  if self.at_line_start then
    for _ = 1, self.level do
      self.buf[#self.buf + 1] = self.indent_text
    end
    self.at_line_start = false
  end
end

function Renderer:push_text(s)
  if s == "" then
    return
  end
  self:push_indent_if_needed()
  self.buf[#self.buf + 1] = s
end

function Renderer:newline()
  self.buf[#self.buf + 1] = "\n"
  self.at_line_start = true
end

function Renderer:render_parts(parts)
  for i = 1, #parts do
    self:render_node(parts[i])
  end
end

function Renderer:render_node(node)
  if node == nil then
    return
  end

  if is_symbol(node) then
    self:push_text(self.symbol_renderer(node))
    return
  end

  local t = type(node)
  if t == "string" or t == "number" or t == "boolean" then
    self:push_text(tostring(node))
    return
  end

  if not is_node(node) then
    error("render_node: expected fragment node or symbol, got " .. t)
  end

  local kind = node.kind

  if kind == "text" then
    self:render_parts(node.parts)
    return
  end

  if kind == "line" then
    self:render_parts(node.parts)
    self:newline()
    return
  end

  if kind == "blank" then
    self:newline()
    return
  end

  if kind == "block" then
    for i = 1, #node.children do
      self:render_node(node.children[i])
    end
    return
  end

  if kind == "indent" then
    self.level = self.level + node.levels
    self:render_node(node.node)
    self.level = self.level - node.levels
    return
  end

  error("unknown Crochet node kind: " .. tostring(kind))
end

--- Render a fragment tree to a string.
function Crochet.render(node, opts)
  local r = make_renderer(opts)
  r:render_node(node)
  return table.concat(r.buf)
end

-- ============================================================================
-- Utility helpers for common codegen patterns
-- ============================================================================

--- Render a comma-separated list from plain values or fragments.
function Crochet.csv(items)
  local parts = {}
  for i = 1, #items do
    parts[#parts + 1] = Crochet.text(items[i])
  end
  return Crochet.intersperse(parts, ", ")
end

--- Render a parenthesized comma-separated argument list.
function Crochet.args(items)
  return Crochet.text("(", Crochet.csv(items), ")")
end

--- Simple local assignment line.
function Crochet.assign(lhs, rhs, local_kw)
  if local_kw == nil then
    local_kw = true
  end
  if local_kw then
    return Crochet.line("local ", lhs, " = ", rhs)
  end
  return Crochet.line(lhs, " = ", rhs)
end

--- Simple function definition block.
function Crochet.fn(name, params, body)
  assert(type(params) == "table", "fn(name, params, body): params must be table")
  local param_frags = {}
  for i = 1, #params do
    param_frags[i] = params[i]
  end
  return Crochet.block({
    Crochet.line("function ", name, "(", Crochet.csv(param_frags), ")"),
    Crochet.indent(body),
    Crochet.line("end"),
  })
end

-- ============================================================================
-- Realization API
-- ============================================================================

local _loadstring = loadstring
local _setfenv = setfenv
local _load = load
local _string_dump = string.dump
local _setmetatable = setmetatable

local function realize_kind(kind, fields, mt)
  fields.kind = kind
  return _setmetatable(fields, mt)
end

local function realize_plain_table(x)
  return type(x) == "table" and getmetatable(x) == nil
end

local function realize_string(v)
  if is_symbol(v) then
    return v.name
  end
  return tostring(v)
end

local function realize_copy(xs)
  local out = {}
  for i = 1, #xs do
    out[i] = xs[i]
  end
  return out
end

local realize_rt = {}
local realize_source = {}
local realize_checked = {}
local realize_plan = {}
local realize_lua = {}

local source_catalog_mt = { __index = {} }
local checked_catalog_mt = { __index = {} }
local plan_catalog_mt = { __index = {} }
local lua_catalog_mt = { __index = {} }

local function source_mode(kind)
  return realize_kind(kind, {})
end

realize_source.SourceMode = source_mode("SourceMode")
realize_source.ClosureMode = source_mode("ClosureMode")
realize_source.BytecodeMode = source_mode("BytecodeMode")

realize_checked.SourceMode = source_mode("SourceMode")
realize_checked.ClosureMode = source_mode("ClosureMode")
realize_checked.BytecodeMode = source_mode("BytecodeMode")

realize_plan.SourceMode = source_mode("SourceMode")
realize_plan.ClosureMode = source_mode("ClosureMode")
realize_plan.BytecodeMode = source_mode("BytecodeMode")

realize_lua.SourceArtifact = source_mode("SourceArtifact")
realize_lua.ClosureArtifact = source_mode("ClosureArtifact")
realize_lua.BytecodeArtifact = source_mode("BytecodeArtifact")

function realize_rt.ValueRef(debug_name, value)
  return realize_kind("ValueRef", {
    debug_name = realize_string(debug_name),
    value = value,
  })
end

function realize_source.Capture(name, value)
  return realize_kind("Capture", {
    name = realize_string(name),
    value = value,
  })
end

function realize_source.TextPart(text)
  return realize_kind("TextPart", { text = realize_string(text) })
end

function realize_source.ParamRef(name)
  return realize_kind("ParamRef", { name = realize_string(name) })
end

function realize_source.CaptureRef(name)
  return realize_kind("CaptureRef", { name = realize_string(name) })
end

function realize_source.Line(parts)
  return realize_kind("Line", { parts = realize_copy(parts) })
end

function realize_source.LineNode(parts)
  return realize_kind("LineNode", { parts = realize_copy(parts) })
end

realize_source.BlankNode = realize_kind("BlankNode", {})

function realize_source.Block(nodes)
  return realize_kind("Block", { nodes = realize_copy(nodes) })
end

function realize_source.NestNode(opener, body, closer)
  return realize_kind("NestNode", {
    opener = opener,
    body = body,
    closer = closer,
  })
end

function realize_source.Proto(name, params, captures, body)
  return realize_kind("Proto", {
    name = realize_string(name),
    params = realize_copy(params),
    captures = realize_copy(captures),
    body = body,
  })
end

function realize_source.Catalog(protos, entry_name, package)
  return realize_kind("Catalog", {
    protos = realize_copy(protos),
    entry_name = realize_string(entry_name),
    package = package,
  }, source_catalog_mt)
end

function realize_checked.ProtoHeader(name, proto_id)
  return realize_kind("ProtoHeader", {
    name = realize_string(name),
    proto_id = proto_id,
  })
end

function realize_checked.Param(name, param_id)
  return realize_kind("Param", {
    name = realize_string(name),
    param_id = param_id,
  })
end

function realize_checked.Capture(name, capture_id, value)
  return realize_kind("Capture", {
    name = realize_string(name),
    capture_id = capture_id,
    value = value,
  })
end

function realize_checked.TextPart(text)
  return realize_kind("TextPart", { text = realize_string(text) })
end

function realize_checked.ParamRef(param_id)
  return realize_kind("ParamRef", { param_id = param_id })
end

function realize_checked.CaptureRef(capture_id)
  return realize_kind("CaptureRef", { capture_id = capture_id })
end

function realize_checked.Line(parts)
  return realize_kind("Line", { parts = realize_copy(parts) })
end

function realize_checked.LineNode(parts)
  return realize_kind("LineNode", { parts = realize_copy(parts) })
end

realize_checked.BlankNode = realize_kind("BlankNode", {})

function realize_checked.Block(nodes)
  return realize_kind("Block", { nodes = realize_copy(nodes) })
end

function realize_checked.NestNode(opener, body, closer)
  return realize_kind("NestNode", {
    opener = opener,
    body = body,
    closer = closer,
  })
end

function realize_checked.Proto(header, params, captures, body)
  return realize_kind("Proto", {
    header = header,
    params = realize_copy(params),
    captures = realize_copy(captures),
    body = body,
  })
end

function realize_checked.Catalog(protos, entry_proto_id, package)
  return realize_kind("Catalog", {
    protos = realize_copy(protos),
    entry_proto_id = entry_proto_id,
    package = package,
  }, checked_catalog_mt)
end

function realize_plan.CapturePlan(name, capture_id, value, bind_index)
  return realize_kind("CapturePlan", {
    name = realize_string(name),
    capture_id = capture_id,
    value = value,
    bind_index = bind_index,
  })
end

function realize_plan.ProtoPlan(name, proto_id, chunk_name, shape_key, artifact_key, source, captures)
  return realize_kind("ProtoPlan", {
    name = realize_string(name),
    proto_id = proto_id,
    chunk_name = realize_string(chunk_name),
    shape_key = realize_string(shape_key),
    artifact_key = realize_string(artifact_key),
    source = realize_string(source),
    captures = realize_copy(captures),
  })
end

function realize_plan.Catalog(protos, entry_proto_id, package)
  return realize_kind("Catalog", {
    protos = realize_copy(protos),
    entry_proto_id = entry_proto_id,
    package = package,
  }, plan_catalog_mt)
end

function realize_lua.CaptureInstall(name, capture_id, bind_index, value)
  return realize_kind("CaptureInstall", {
    name = realize_string(name),
    capture_id = capture_id,
    bind_index = bind_index,
    value = value,
  })
end

function realize_lua.SourceInstall(name, proto_id, chunk_name, artifact_key, source)
  return realize_kind("SourceInstall", {
    name = realize_string(name),
    proto_id = proto_id,
    chunk_name = realize_string(chunk_name),
    artifact_key = realize_string(artifact_key),
    source = realize_string(source),
  })
end

function realize_lua.ClosureInstall(name, proto_id, chunk_name, artifact_key, source, captures)
  return realize_kind("ClosureInstall", {
    name = realize_string(name),
    proto_id = proto_id,
    chunk_name = realize_string(chunk_name),
    artifact_key = realize_string(artifact_key),
    source = realize_string(source),
    captures = realize_copy(captures),
  })
end

function realize_lua.BytecodeInstall(name, proto_id, chunk_name, artifact_key, source, captures)
  return realize_kind("BytecodeInstall", {
    name = realize_string(name),
    proto_id = proto_id,
    chunk_name = realize_string(chunk_name),
    artifact_key = realize_string(artifact_key),
    source = realize_string(source),
    captures = realize_copy(captures),
  })
end

function realize_lua.Catalog(protos, entry_proto_id, artifact_mode)
  return realize_kind("Catalog", {
    protos = realize_copy(protos),
    entry_proto_id = entry_proto_id,
    artifact_mode = artifact_mode,
  }, lua_catalog_mt)
end

local realize_types_value = {
  CrochetRealizeRuntime = realize_rt,
  CrochetRealizeSource = realize_source,
  CrochetRealizeChecked = realize_checked,
  CrochetRealizePlan = realize_plan,
  CrochetRealizeLua = realize_lua,
}

local function realize_types()
  return realize_types_value
end

local function realize_match(value, arms)
  local arm = arms[value.kind]
  if not arm then
    error("unhandled realize variant: " .. tostring(value.kind), 2)
  end
  return arm(value)
end

local function realize_find(xs, pred)
  for i = 1, #xs do
    if pred(xs[i]) then return xs[i] end
  end
  return nil
end

local function realize_fold(xs, fn, init)
  for i = 1, #xs do
    init = fn(init, xs[i])
  end
  return init
end

local function realize_map(xs, fn)
  local out = {}
  for i = 1, #xs do
    out[i] = fn(xs[i], i)
  end
  return out
end

local function realize_name_map(items, name_of, label)
  local out = {}
  for i = 1, #items do
    local item = items[i]
    local name = name_of(item)
    assert(out[name] == nil, label .. " name must be unique: " .. name)
    out[name] = item
  end
  return out
end

local function realize_part(v)
  if v == nil then return nil end
  if is_symbol(v) then
    return realize_source.TextPart(v.name)
  end
  if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
    return realize_source.TextPart(tostring(v))
  end
  if type(v) == "table" and (v.kind == "TextPart" or v.kind == "ParamRef" or v.kind == "CaptureRef") then
    return v
  end
  error("unsupported Crochet realize part: " .. type(v), 3)
end

local function realize_parts(args)
  local out = {}
  local items = args
  if #args == 1 and realize_plain_table(args[1]) then
    items = args[1]
  end
  for i = 1, #items do
    local part = realize_part(items[i])
    if part ~= nil then
      out[#out + 1] = part
    end
  end
  return out
end

local function realize_line(value)
  if type(value) == "table" and value.kind == "Line" then
    return value
  end
  if type(value) == "string" or type(value) == "number" or type(value) == "boolean" or is_symbol(value) then
    return realize_source.Line({ realize_source.TextPart(realize_string(value)) })
  end
  if realize_plain_table(value) then
    return realize_source.Line(realize_parts({ value }))
  end
  error("expected Crochet realize line", 3)
end

local function realize_package_mode(mode)
  if type(mode) == "table" and mode.kind then
    return mode
  end
  if mode == nil or mode == "source" then return realize_source.SourceMode end
  if mode == "closure" then return realize_source.ClosureMode end
  if mode == "bytecode" then return realize_source.BytecodeMode end
  error("unknown Crochet package mode: " .. tostring(mode), 3)
end

local function realize_install_mode_name(mode)
  return realize_match(mode, {
    SourceArtifact = function() return "source" end,
    ClosureArtifact = function() return "closure" end,
    BytecodeArtifact = function() return "bytecode" end,
  })
end

local function realize_source_mode_for_checked(mode)
  return realize_match(mode, {
    SourceMode = function() return realize_checked.SourceMode end,
    ClosureMode = function() return realize_checked.ClosureMode end,
    BytecodeMode = function() return realize_checked.BytecodeMode end,
  })
end

local function realize_plan_mode_for_checked(mode)
  return realize_match(mode, {
    SourceMode = function() return realize_plan.SourceMode end,
    ClosureMode = function() return realize_plan.ClosureMode end,
    BytecodeMode = function() return realize_plan.BytecodeMode end,
  })
end

local function realize_lua_mode_for_plan(mode)
  return realize_match(mode, {
    SourceMode = function() return realize_lua.SourceArtifact end,
    ClosureMode = function() return realize_lua.ClosureArtifact end,
    BytecodeMode = function() return realize_lua.BytecodeArtifact end,
  })
end

local function realize_by_id(items, id_field)
  local out = {}
  for i = 1, #items do
    out[items[i][id_field]] = items[i]
  end
  return out
end

local function realize_checked_params(params)
  local out = {}
  for i = 1, #params do
    out[i] = realize_checked.Param(realize_string(params[i]), i)
  end
  return out
end

local function realize_checked_captures(captures)
  local out = {}
  for i = 1, #captures do
    local cap = captures[i]
    out[i] = realize_checked.Capture(realize_string(cap.name), i, cap.value)
  end
  return out
end

local function realize_checked_part(proto, part, params_by_name, captures_by_name)
  return realize_match(part, {
    TextPart = function(v)
      return realize_checked.TextPart(v.text)
    end,
    ParamRef = function(v)
      local param = params_by_name[v.name]
      assert(param ~= nil, "unknown param ref: " .. v.name .. " in proto " .. proto.name)
      return realize_checked.ParamRef(param.param_id)
    end,
    CaptureRef = function(v)
      local capture = captures_by_name[v.name]
      assert(capture ~= nil, "unknown capture ref: " .. v.name .. " in proto " .. proto.name)
      return realize_checked.CaptureRef(capture.capture_id)
    end,
  })
end

local function realize_checked_line(proto, line, params_by_name, captures_by_name)
  return realize_checked.Line(realize_map(line.parts, function(part)
    return realize_checked_part(proto, part, params_by_name, captures_by_name)
  end))
end

local function realize_checked_block(proto, block, params_by_name, captures_by_name)
  return realize_checked.Block(realize_map(block.nodes, function(node)
    return realize_match(node, {
      LineNode = function(v)
        return realize_checked.LineNode(realize_map(v.parts, function(part)
          return realize_checked_part(proto, part, params_by_name, captures_by_name)
        end))
      end,
      BlankNode = function()
        return realize_checked.BlankNode
      end,
      NestNode = function(v)
        return realize_checked.NestNode(
          realize_checked_line(proto, v.opener, params_by_name, captures_by_name),
          realize_checked_block(proto, v.body, params_by_name, captures_by_name),
          realize_checked_line(proto, v.closer, params_by_name, captures_by_name)
        )
      end,
    })
  end))
end

local function realize_check_catalog(catalog)
  local protos = {}
  for i = 1, #catalog.protos do
    local proto = catalog.protos[i]
    local params = realize_checked_params(proto.params)
    local captures = realize_checked_captures(proto.captures)
    local params_by_name = realize_name_map(params, function(item) return item.name end, "param")
    local captures_by_name = realize_name_map(captures, function(item) return item.name end, "capture")
    protos[i] = realize_checked.Proto(
      realize_checked.ProtoHeader(proto.name, i),
      params,
      captures,
      realize_checked_block(proto, proto.body, params_by_name, captures_by_name)
    )
  end

  realize_name_map(protos, function(proto) return proto.header.name end, "proto")

  local entry = realize_find(protos, function(proto)
    return proto.header.name == catalog.entry_name
  end)
  assert(entry ~= nil, "entry proto not found: " .. catalog.entry_name)

  return realize_checked.Catalog(protos, entry.header.proto_id, realize_source_mode_for_checked(catalog.package))
end

function source_catalog_mt.__index:check_realize()
  return realize_check_catalog(self)
end

local function realize_render_part(part, params_by_id, captures_by_id)
  return realize_match(part, {
    TextPart = function(v)
      return v.text
    end,
    ParamRef = function(v)
      return params_by_id[v.param_id].name
    end,
    CaptureRef = function(v)
      return captures_by_id[v.capture_id].name
    end,
  })
end

local function realize_render_line_fragment(line, params_by_id, captures_by_id)
  return Crochet.line(Crochet.join(realize_map(line.parts, function(part)
    return Crochet.text(realize_render_part(part, params_by_id, captures_by_id))
  end), ""))
end

local function realize_render_block_fragment(block, params_by_id, captures_by_id)
  return Crochet.block(realize_map(block.nodes, function(node)
    return realize_match(node, {
      LineNode = function(v)
        return Crochet.line(Crochet.join(realize_map(v.parts, function(part)
          return Crochet.text(realize_render_part(part, params_by_id, captures_by_id))
        end), ""))
      end,
      BlankNode = function()
        return Crochet.blank()
      end,
      NestNode = function(v)
        return Crochet.block({
          realize_render_line_fragment(v.opener, params_by_id, captures_by_id),
          Crochet.indent(realize_render_block_fragment(v.body, params_by_id, captures_by_id)),
          realize_render_line_fragment(v.closer, params_by_id, captures_by_id),
        })
      end,
    })
  end))
end

local function realize_capture_signature(captures)
  local parts = {}
  for i = 1, #captures do
    parts[i] = tostring(captures[i].capture_id) .. ":" .. captures[i].name
  end
  return table.concat(parts, ",")
end

local function realize_proto_plan(proto)
  local params_by_id = realize_by_id(proto.params, "param_id")
  local captures_by_id = realize_by_id(proto.captures, "capture_id")
  local source = Crochet.render(Crochet.block({
    Crochet.line("return function(", Crochet.csv(realize_map(proto.params, function(param)
      return param.name
    end)), ")"),
    Crochet.indent(realize_render_block_fragment(proto.body, params_by_id, captures_by_id)),
    Crochet.line("end"),
  }))
  local shape_key = proto.header.name .. "|" .. source
  local artifact_key = shape_key .. "|captures=" .. realize_capture_signature(proto.captures)
  local capture_plans = {}
  for i = 1, #proto.captures do
    local capture = proto.captures[i]
    capture_plans[i] = realize_plan.CapturePlan(capture.name, capture.capture_id, capture.value, i)
  end
  return realize_plan.ProtoPlan(
    proto.header.name,
    proto.header.proto_id,
    "@crochet:" .. proto.header.name,
    shape_key,
    artifact_key,
    source,
    capture_plans
  )
end

local function realize_lower_catalog(catalog)
  return realize_plan.Catalog(
    realize_map(catalog.protos, realize_proto_plan),
    catalog.entry_proto_id,
    realize_plan_mode_for_checked(catalog.package)
  )
end

function checked_catalog_mt.__index:lower_realize()
  return realize_lower_catalog(self)
end

local function realize_capture_install(capture)
  return realize_lua.CaptureInstall(capture.name, capture.capture_id, capture.bind_index, capture.value)
end

local function realize_prepare_install_proto(mode, proto)
  return realize_match(mode, {
    SourceMode = function()
      return realize_lua.SourceInstall(proto.name, proto.proto_id, proto.chunk_name, proto.artifact_key, proto.source)
    end,
    ClosureMode = function()
      return realize_lua.ClosureInstall(proto.name, proto.proto_id, proto.chunk_name, proto.artifact_key, proto.source, realize_map(proto.captures, realize_capture_install))
    end,
    BytecodeMode = function()
      return realize_lua.BytecodeInstall(proto.name, proto.proto_id, proto.chunk_name, proto.artifact_key, proto.source, realize_map(proto.captures, realize_capture_install))
    end,
  })
end

local function realize_prepare_catalog(catalog)
  return realize_lua.Catalog(
    realize_map(catalog.protos, function(proto)
      return realize_prepare_install_proto(catalog.package, proto)
    end),
    catalog.entry_proto_id,
    realize_lua_mode_for_plan(catalog.package)
  )
end

function plan_catalog_mt.__index:prepare_install()
  return realize_prepare_catalog(self)
end

local function load_in_env(source, chunkname, env)
  if _loadstring then
    local fn, err = _loadstring(source, chunkname)
    if not fn then
      return nil, err
    end
    if env then
      _setfenv(fn, env)
    end
    return fn
  end
  return _load(source, chunkname, "bt", env)
end

local function realize_proto_name(proto) return proto.name end
local function realize_proto_id(proto) return proto.proto_id end
local function realize_proto_chunk_name(proto) return proto.chunk_name end
local function realize_proto_artifact_key(proto) return proto.artifact_key end
local function realize_proto_source(proto) return proto.source end
local function realize_proto_captures(proto) return proto.captures or {} end

local function realize_install_catalog(catalog)
  local proto_by_name = {}
  local proto_by_id = {}
  for i = 1, #catalog.protos do
    local proto = catalog.protos[i]
    proto_by_name[realize_proto_name(proto)] = proto
    proto_by_id[realize_proto_id(proto)] = proto
  end

  local artifact = {
    mode = realize_install_mode_name(catalog.artifact_mode),
    entry_proto_id = catalog.entry_proto_id,
    protos = {},
    closure_cache = {},
    bytecode_cache = {},
  }

  local function build_env(proto)
    local env = {}
    local captures = realize_proto_captures(proto)
    for i = 1, #captures do
      env[captures[i].name] = captures[i].value.value
    end
    return _setmetatable(env, { __index = _G })
  end

  local function compile_from_source(proto)
    local env = build_env(proto)
    local chunk, err = load_in_env(realize_proto_source(proto), realize_proto_chunk_name(proto), env)
    assert(chunk, err)
    return chunk(), env
  end

  function artifact:realize(name_or_id)
    local proto = type(name_or_id) == "number" and proto_by_id[name_or_id] or proto_by_name[realize_string(name_or_id)]
    assert(proto ~= nil, "unknown proto: " .. tostring(name_or_id))

    local key = realize_proto_artifact_key(proto)
    local cached = self.closure_cache[key]
    if cached then
      return cached
    end

    local fn, env = compile_from_source(proto)
    local bytecode = nil
    if proto.kind == "BytecodeInstall" then
      bytecode = _string_dump(fn)
      self.bytecode_cache[key] = bytecode
      local restored, err = load_in_env(bytecode, realize_proto_chunk_name(proto) .. ":bytecode", env)
      assert(restored, err)
      fn = restored
    end

    self.closure_cache[key] = fn
    self.protos[realize_proto_name(proto)] = {
      name = realize_proto_name(proto),
      proto_id = realize_proto_id(proto),
      chunk_name = realize_proto_chunk_name(proto),
      artifact_key = key,
      source = realize_proto_source(proto),
      bytecode = bytecode,
      fn = fn,
    }
    return fn
  end

  if artifact.mode ~= "source" then
    for i = 1, #catalog.protos do
      artifact:realize(catalog.protos[i].name)
    end
  end

  local entry_fn = artifact:realize(catalog.entry_proto_id)
  artifact.entry = function(...)
    return entry_fn(...)
  end

  return artifact
end

function lua_catalog_mt.__index:install()
  return realize_install_catalog(self)
end

local DIRECT_CLOSURE_MODE = realize_kind("DirectClosureMode", {})
local BUNDLE_CLOSURE_MODE = realize_kind("ClosureBundleMode", {})
local LUA_SOURCE_HOST = realize_kind("LuaSourceHost", {})
local LUA_BYTECODE_HOST = realize_kind("LuaBytecodeHost", {})

local function lua_closure_host(mode)
  return realize_kind("LuaClosureHost", { mode = mode or DIRECT_CLOSURE_MODE })
end

local function is_text_proto(proto)
  return type(proto) == "table" and proto.kind == "TextProto"
end

local function is_closure_proto(proto)
  return type(proto) == "table" and proto.kind == "ClosureProto"
end

local function all_text_protos(protos)
  for i = 1, #protos do
    if not is_text_proto(protos[i]) then return false end
  end
  return true
end

local function all_closure_protos(protos)
  for i = 1, #protos do
    if not is_closure_proto(protos[i]) then return false end
  end
  return true
end

local function project_realize_part(v)
  if v == nil then return nil end
  if is_symbol(v) then
    return realize_source.TextPart(v.name)
  end
  if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
    return realize_source.TextPart(tostring(v))
  end
  if type(v) == "table" and (v.kind == "TextPart" or v.kind == "ParamRef" or v.kind == "CaptureRef") then
    return v
  end
  error("unsupported Crochet realize part: " .. type(v), 3)
end

local function project_realize_parts(args)
  local out = {}
  local items = args
  if #args == 1 and realize_plain_table(args[1]) then
    items = args[1]
  end
  for i = 1, #items do
    local part = project_realize_part(items[i])
    if part ~= nil then out[#out + 1] = part end
  end
  return out
end

local function project_realize_line(value)
  if type(value) == "table" and value.kind == "Line" then return value end
  if type(value) == "string" or type(value) == "number" or type(value) == "boolean" or is_symbol(value) then
    return realize_source.Line({ realize_source.TextPart(realize_string(value)) })
  end
  if realize_plain_table(value) then
    return realize_source.Line(project_realize_parts({ value }))
  end
  error("expected Crochet realize line", 3)
end

local function source_unary_op(name)
  if name == "not" then return realize_kind("NotOp", {}) end
  if name == "neg" then return realize_kind("NegOp", {}) end
  if name == "len" then return realize_kind("LenOp", {}) end
  error("unknown Crochet unary op: " .. tostring(name), 3)
end

local function source_binary_op(name)
  if name == "+" or name == "add" then return realize_kind("AddOp", {}) end
  if name == "-" or name == "sub" then return realize_kind("SubOp", {}) end
  if name == "*" or name == "mul" then return realize_kind("MulOp", {}) end
  if name == "/" or name == "div" then return realize_kind("DivOp", {}) end
  if name == "%" or name == "mod" then return realize_kind("ModOp", {}) end
  if name == "==" or name == "eq" then return realize_kind("EqOp", {}) end
  if name == "~=" or name == "ne" then return realize_kind("NeOp", {}) end
  if name == "<" or name == "lt" then return realize_kind("LtOp", {}) end
  if name == "<=" or name == "le" then return realize_kind("LeOp", {}) end
  if name == ">" or name == "gt" then return realize_kind("GtOp", {}) end
  if name == ">=" or name == "ge" then return realize_kind("GeOp", {}) end
  if name == "and" then return realize_kind("AndOp", {}) end
  if name == "or" then return realize_kind("OrOp", {}) end
  error("unknown Crochet binary op: " .. tostring(name), 3)
end

local closure_source_catalog_mt = { __index = {} }
local closure_checked_catalog_mt = { __index = {} }
local closure_plan_catalog_mt = { __index = {} }
local closure_install_catalog_mt = { __index = {} }

local function closure_catalog(protos, entry_name, host)
  return realize_kind("ClosureCatalog", {
    protos = realize_copy(protos),
    entry_name = realize_string(entry_name),
    host = host or lua_closure_host(DIRECT_CLOSURE_MODE),
  }, closure_source_catalog_mt)
end

local function closure_checked_catalog(protos, entry_proto_id, host)
  return realize_kind("ClosureCheckedCatalog", {
    protos = protos,
    entry_proto_id = entry_proto_id,
    host = host,
  }, closure_checked_catalog_mt)
end

local function closure_plan_catalog(protos, entry_proto_id, host)
  return realize_kind("ClosurePlanCatalog", {
    protos = protos,
    entry_proto_id = entry_proto_id,
    host = host,
  }, closure_plan_catalog_mt)
end

local function closure_install_catalog(protos, entry_proto_id)
  return realize_kind("ClosureInstallCatalog", {
    protos = protos,
    entry_proto_id = entry_proto_id,
    artifact_mode = realize_lua.ClosureArtifact,
  }, closure_install_catalog_mt)
end

local function map_assoc(items, key_fn)
  local out = {}
  for i = 1, #items do
    out[key_fn(items[i])] = items[i]
  end
  return out
end

local function assoc_copy(tbl, key, value)
  local out = {}
  for k, v in pairs(tbl) do out[k] = v end
  out[key] = value
  return out
end

local function closure_check_catalog(catalog)
  local function checked_params(params)
    local out = {}
    for i = 1, #params do
      out[i] = { kind = "Param", name = realize_string(params[i]), param_id = i }
    end
    return out
  end

  local function checked_captures(captures)
    local out = {}
    for i = 1, #captures do
      out[i] = { kind = "Capture", name = realize_string(captures[i].name), capture_id = i, value = captures[i].value }
    end
    return out
  end

  local function next_local_env(env, name)
    local local_id = env.next_local_id
    return { kind = "LocalHeader", name = name, local_id = local_id }, {
      params_by_name = env.params_by_name,
      captures_by_name = env.captures_by_name,
      locals_by_name = assoc_copy(env.locals_by_name, name, local_id),
      next_local_id = local_id + 1,
    }
  end

  local check_expr
  local check_block

  check_expr = function(proto_name, expr, env)
    local k = expr.kind
    if k == "ParamExpr" then
      local p = env.params_by_name[realize_string(expr.name)]
      assert(p, "unknown param expr: " .. realize_string(expr.name) .. " in proto " .. proto_name)
      return { kind = "ParamExpr", param_id = p.param_id }
    elseif k == "CaptureExpr" then
      local c = env.captures_by_name[realize_string(expr.name)]
      assert(c, "unknown capture expr: " .. realize_string(expr.name) .. " in proto " .. proto_name)
      return { kind = "CaptureExpr", capture_id = c.capture_id }
    elseif k == "LocalExpr" then
      local id = env.locals_by_name[realize_string(expr.name)]
      assert(id, "unknown local expr: " .. realize_string(expr.name) .. " in proto " .. proto_name)
      return { kind = "LocalExpr", local_id = id }
    elseif k == "LiteralExpr" then
      return { kind = "LiteralExpr", value = expr.value }
    elseif k == "CallExpr" then
      local args = {}
      for i = 1, #expr.args do args[i] = check_expr(proto_name, expr.args[i], env) end
      return { kind = "CallExpr", fn = check_expr(proto_name, expr.fn, env), args = args }
    elseif k == "IndexExpr" then
      return { kind = "IndexExpr", base = check_expr(proto_name, expr.base, env), key = check_expr(proto_name, expr.key, env) }
    elseif k == "UnaryExpr" then
      return { kind = "UnaryExpr", op = expr.op, value = check_expr(proto_name, expr.value, env) }
    elseif k == "BinaryExpr" then
      return { kind = "BinaryExpr", op = expr.op, lhs = check_expr(proto_name, expr.lhs, env), rhs = check_expr(proto_name, expr.rhs, env) }
    end
    error("unknown closure expr kind: " .. tostring(k), 2)
  end

  local function check_stmt(proto_name, stmt, env)
    local k = stmt.kind
    if k == "LetStmt" then
      local local_header, next_env = next_local_env(env, realize_string(stmt.name))
      return { kind = "LetStmt", local_header = local_header, value = check_expr(proto_name, stmt.value, env) }, next_env
    elseif k == "SetStmt" then
      local id = env.locals_by_name[realize_string(stmt.name)]
      assert(id, "unknown local set: " .. realize_string(stmt.name) .. " in proto " .. proto_name)
      return { kind = "SetStmt", local_id = id, value = check_expr(proto_name, stmt.value, env) }, env
    elseif k == "EffectStmt" then
      return { kind = "EffectStmt", expr = check_expr(proto_name, stmt.expr, env) }, env
    elseif k == "ReturnStmt" then
      return { kind = "ReturnStmt", value = check_expr(proto_name, stmt.value, env) }, env
    elseif k == "IfStmt" then
      return { kind = "IfStmt", cond = check_expr(proto_name, stmt.cond, env), then_body = check_block(proto_name, stmt.then_body, env), else_body = check_block(proto_name, stmt.else_body, env) }, env
    elseif k == "ForRangeStmt" then
      local local_header, body_env = next_local_env(env, realize_string(stmt.name))
      return {
        kind = "ForRangeStmt",
        local_header = local_header,
        start = check_expr(proto_name, stmt.start, env),
        stop = check_expr(proto_name, stmt.stop, env),
        step = check_expr(proto_name, stmt.step, env),
        body = check_block(proto_name, stmt.body, body_env),
      }, env
    elseif k == "WhileStmt" then
      return { kind = "WhileStmt", cond = check_expr(proto_name, stmt.cond, env), body = check_block(proto_name, stmt.body, env) }, env
    end
    error("unknown closure stmt kind: " .. tostring(k), 2)
  end

  check_block = function(proto_name, block, env)
    local stmts = {}
    local cur = env
    for i = 1, #block.stmts do
      local s, next_env = check_stmt(proto_name, block.stmts[i], cur)
      stmts[i] = s
      cur = next_env
    end
    return { kind = "ClosureBlock", stmts = stmts }
  end

  local checked_protos = {}
  local entry_proto_id = nil
  for i = 1, #catalog.protos do
    local proto = catalog.protos[i]
    local params = checked_params(proto.params)
    local captures = checked_captures(proto.captures)
    local env = {
      params_by_name = map_assoc(params, function(p) return p.name end),
      captures_by_name = map_assoc(captures, function(c) return c.name end),
      locals_by_name = {},
      next_local_id = 1,
    }
    checked_protos[i] = {
      kind = "ClosureProto",
      header = { kind = "ProtoHeader", name = realize_string(proto.name), proto_id = i },
      params = params,
      captures = captures,
      body = check_block(realize_string(proto.name), proto.body, env),
    }
    if realize_string(proto.name) == realize_string(catalog.entry_name) then
      entry_proto_id = i
    end
  end
  assert(entry_proto_id, "entry proto not found: " .. realize_string(catalog.entry_name))
  return closure_checked_catalog(checked_protos, entry_proto_id, catalog.host)
end

local function closure_lower_catalog(catalog)
  local function capture_sig(captures)
    local parts = {}
    for i = 1, #captures do parts[i] = tostring(captures[i].capture_id) .. ":" .. realize_string(captures[i].name) end
    return table.concat(parts, ",")
  end

  local function expr_sig(expr)
    local k = expr.kind
    if k == "ParamExpr" then return "p" .. tostring(expr.param_id) end
    if k == "CaptureExpr" then return "c" .. tostring(expr.capture_id) end
    if k == "LocalExpr" then return "l" .. tostring(expr.local_id) end
    if k == "LiteralExpr" then return "lit(" .. realize_string(expr.value.debug_name) .. ")" end
    if k == "CallExpr" then
      local xs = {}
      for i = 1, #expr.args do xs[i] = expr_sig(expr.args[i]) end
      return "call(" .. expr_sig(expr.fn) .. "," .. table.concat(xs, ",") .. ")"
    end
    if k == "IndexExpr" then return "idx(" .. expr_sig(expr.base) .. "," .. expr_sig(expr.key) .. ")" end
    if k == "UnaryExpr" then return "un(" .. expr.op.kind .. "," .. expr_sig(expr.value) .. ")" end
    return "bin(" .. expr.op.kind .. "," .. expr_sig(expr.lhs) .. "," .. expr_sig(expr.rhs) .. ")"
  end

  local stmt_sig
  local function block_sig(block)
    local xs = {}
    for i = 1, #block.stmts do xs[i] = stmt_sig(block.stmts[i]) end
    return "{" .. table.concat(xs, ";") .. "}"
  end

  stmt_sig = function(stmt)
    local k = stmt.kind
    if k == "LetStmt" then return "let(" .. stmt.local_header.local_id .. "," .. expr_sig(stmt.value) .. ")" end
    if k == "SetStmt" then return "set(" .. stmt.local_id .. "," .. expr_sig(stmt.value) .. ")" end
    if k == "EffectStmt" then return "effect(" .. expr_sig(stmt.expr) .. ")" end
    if k == "ReturnStmt" then return "ret(" .. expr_sig(stmt.value) .. ")" end
    if k == "IfStmt" then return "if(" .. expr_sig(stmt.cond) .. "," .. block_sig(stmt.then_body) .. "," .. block_sig(stmt.else_body) .. ")" end
    if k == "ForRangeStmt" then return "for(" .. stmt.local_header.local_id .. "," .. expr_sig(stmt.start) .. "," .. expr_sig(stmt.stop) .. "," .. expr_sig(stmt.step) .. "," .. block_sig(stmt.body) .. ")" end
    return "while(" .. expr_sig(stmt.cond) .. "," .. block_sig(stmt.body) .. ")"
  end

  local protos = {}
  for i = 1, #catalog.protos do
    local proto = catalog.protos[i]
    local name = realize_string(proto.header.name)
    local captures = {}
    for j = 1, #proto.captures do
      local c = proto.captures[j]
      captures[j] = { kind = "CapturePlan", name = c.name, capture_id = c.capture_id, value = c.value, bind_index = j }
    end
    local params = {}
    for j = 1, #proto.params do
      local p = proto.params[j]
      params[j] = { kind = "ParamPlan", name = p.name, param_id = p.param_id }
    end
    local shape_key = "closure|" .. name .. "|" .. block_sig(proto.body)
    protos[i] = {
      kind = "ClosureProtoPlan",
      name = name,
      proto_id = proto.header.proto_id,
      shape_key = shape_key,
      artifact_key = shape_key .. "|captures=" .. capture_sig(proto.captures),
      params = params,
      captures = captures,
      body = proto.body,
    }
  end
  return closure_plan_catalog(protos, catalog.entry_proto_id, catalog.host)
end

local function closure_prepare_catalog(catalog)
  local protos = {}
  for i = 1, #catalog.protos do
    local proto = catalog.protos[i]
    protos[i] = {
      kind = "ClosureInstall",
      name = proto.name,
      proto_id = proto.proto_id,
      artifact_key = proto.artifact_key,
      params = proto.params,
      captures = proto.captures,
      body = proto.body,
    }
  end
  return closure_install_catalog(protos, catalog.entry_proto_id)
end

local function compile_closure_install(proto)
  local captures_by_id = {}
  for i = 1, #proto.captures do captures_by_id[proto.captures[i].capture_id] = proto.captures[i].value.value end

  local compile_expr
  local compile_block

  local function compile_unary(op, value_fn)
    local k = op.kind
    if k == "NotOp" then return function(ctx) return not value_fn(ctx) end end
    if k == "NegOp" then return function(ctx) return -value_fn(ctx) end end
    return function(ctx) return #value_fn(ctx) end
  end

  local function compile_binary(op, lhs_fn, rhs_fn)
    local k = op.kind
    if k == "AddOp" then return function(ctx) return lhs_fn(ctx) + rhs_fn(ctx) end end
    if k == "SubOp" then return function(ctx) return lhs_fn(ctx) - rhs_fn(ctx) end end
    if k == "MulOp" then return function(ctx) return lhs_fn(ctx) * rhs_fn(ctx) end end
    if k == "DivOp" then return function(ctx) return lhs_fn(ctx) / rhs_fn(ctx) end end
    if k == "ModOp" then return function(ctx) return lhs_fn(ctx) % rhs_fn(ctx) end end
    if k == "EqOp" then return function(ctx) return lhs_fn(ctx) == rhs_fn(ctx) end end
    if k == "NeOp" then return function(ctx) return lhs_fn(ctx) ~= rhs_fn(ctx) end end
    if k == "LtOp" then return function(ctx) return lhs_fn(ctx) < rhs_fn(ctx) end end
    if k == "LeOp" then return function(ctx) return lhs_fn(ctx) <= rhs_fn(ctx) end end
    if k == "GtOp" then return function(ctx) return lhs_fn(ctx) > rhs_fn(ctx) end end
    if k == "GeOp" then return function(ctx) return lhs_fn(ctx) >= rhs_fn(ctx) end end
    if k == "AndOp" then return function(ctx) local l=lhs_fn(ctx); if not l then return l end; return rhs_fn(ctx) end end
    return function(ctx) local l=lhs_fn(ctx); if l then return l end; return rhs_fn(ctx) end
  end

  compile_expr = function(expr)
    local k = expr.kind
    if k == "ParamExpr" then local id=expr.param_id; return function(ctx) return ctx.params[id] end end
    if k == "CaptureExpr" then local v=captures_by_id[expr.capture_id]; return function() return v end end
    if k == "LocalExpr" then local id=expr.local_id; return function(ctx) return ctx.locals[id] end end
    if k == "LiteralExpr" then local v=expr.value.value; return function() return v end end
    if k == "CallExpr" then
      local fn_eval = compile_expr(expr.fn)
      local arg_evals = {}
      for i = 1, #expr.args do arg_evals[i] = compile_expr(expr.args[i]) end
      return function(ctx)
        local args = {}
        for i = 1, #arg_evals do args[i] = arg_evals[i](ctx) end
        return fn_eval(ctx)(_unpack(args))
      end
    end
    if k == "IndexExpr" then local b=compile_expr(expr.base); local key=compile_expr(expr.key); return function(ctx) return b(ctx)[key(ctx)] end end
    if k == "UnaryExpr" then return compile_unary(expr.op, compile_expr(expr.value)) end
    return compile_binary(expr.op, compile_expr(expr.lhs), compile_expr(expr.rhs))
  end

  local function compile_stmt(stmt)
    local k = stmt.kind
    if k == "LetStmt" then local id=stmt.local_header.local_id; local ev=compile_expr(stmt.value); return function(ctx) ctx.locals[id]=ev(ctx); return false,nil end end
    if k == "SetStmt" then local id=stmt.local_id; local ev=compile_expr(stmt.value); return function(ctx) ctx.locals[id]=ev(ctx); return false,nil end end
    if k == "EffectStmt" then local ev=compile_expr(stmt.expr); return function(ctx) ev(ctx); return false,nil end end
    if k == "ReturnStmt" then local ev=compile_expr(stmt.value); return function(ctx) return true, ev(ctx) end end
    if k == "IfStmt" then local cond=compile_expr(stmt.cond); local tb=compile_block(stmt.then_body); local eb=compile_block(stmt.else_body); return function(ctx) if cond(ctx) then return tb(ctx) else return eb(ctx) end end end
    if k == "ForRangeStmt" then
      local id=stmt.local_header.local_id; local s=compile_expr(stmt.start); local stop=compile_expr(stmt.stop); local step=compile_expr(stmt.step); local body=compile_block(stmt.body)
      return function(ctx)
        for i = s(ctx), stop(ctx), step(ctx) do
          ctx.locals[id] = i
          local returned, value = body(ctx)
          if returned then return true, value end
        end
        return false, nil
      end
    end
    local cond=compile_expr(stmt.cond); local body=compile_block(stmt.body)
    return function(ctx)
      while cond(ctx) do
        local returned, value = body(ctx)
        if returned then return true, value end
      end
      return false, nil
    end
  end

  compile_block = function(block)
    local execs = {}
    for i = 1, #block.stmts do execs[i] = compile_stmt(block.stmts[i]) end
    return function(ctx)
      for i = 1, #execs do
        local returned, value = execs[i](ctx)
        if returned then return true, value end
      end
      return false, nil
    end
  end

  local run = compile_block(proto.body)
  return function(...)
    local ctx = { params = { ... }, locals = {} }
    local _, value = run(ctx)
    return value
  end
end

local function closure_install(catalog)
  local artifact = {
    mode = "closure",
    entry_proto_id = catalog.entry_proto_id,
    protos = {},
    closure_cache = {},
    bytecode_cache = {},
  }
  local proto_by_name, proto_by_id = {}, {}
  for i = 1, #catalog.protos do
    local p = catalog.protos[i]
    proto_by_name[p.name] = p
    proto_by_id[p.proto_id] = p
  end
  function artifact:realize(name_or_id)
    local proto = type(name_or_id) == "number" and proto_by_id[name_or_id] or proto_by_name[realize_string(name_or_id)]
    assert(proto, "unknown proto: " .. tostring(name_or_id))
    local key = proto.artifact_key
    if self.closure_cache[key] then return self.closure_cache[key] end
    local fn = compile_closure_install(proto)
    self.closure_cache[key] = fn
    self.protos[proto.name] = { name = proto.name, proto_id = proto.proto_id, artifact_key = key, source = nil, bytecode = nil, fn = fn }
    return fn
  end
  for i = 1, #catalog.protos do artifact:realize(catalog.protos[i].name) end
  local entry_fn = artifact:realize(catalog.entry_proto_id)
  artifact.entry = function(...) return entry_fn(...) end
  return artifact
end

function closure_source_catalog_mt.__index:check_realize()
  return closure_check_catalog(self)
end

function closure_checked_catalog_mt.__index:lower_realize()
  return closure_lower_catalog(self)
end

function closure_plan_catalog_mt.__index:prepare_install()
  return closure_prepare_catalog(self)
end

function closure_install_catalog_mt.__index:install()
  return closure_install(self)
end

function Crochet.types()
  local types = realize_types()
  types.CrochetRealizeSource.ClosureProto = function(name, params, captures, body)
    return Crochet.closure_proto(name, params, captures, body)
  end
  return types
end

-- Select the source-artifact proto family.
-- Use when generated source is itself the honest installed artifact.
function Crochet.host_source()
  return LUA_SOURCE_HOST
end

-- Select the bytecode-artifact proto family.
-- Use when serialized/restorable bytecode is the honest install artifact.
-- This is useful for artifact caching and delayed restore, not because it
-- automatically makes hot code faster.
function Crochet.host_bytecode()
  return LUA_BYTECODE_HOST
end

-- Select the direct-closure proto family.
-- Use when source rendering is not the host contract and the honest installed
-- artifact is already a closure family.
function Crochet.host_closure(mode)
  if mode == nil or mode == "direct" then return lua_closure_host(DIRECT_CLOSURE_MODE) end
  if mode == "bundle" then return lua_closure_host(BUNDLE_CLOSURE_MODE) end
  if type(mode) == "table" and (mode.kind == "DirectClosureMode" or mode.kind == "ClosureBundleMode") then
    return lua_closure_host(mode)
  end
  error("unknown Crochet closure host mode: " .. tostring(mode), 2)
end

function Crochet.literal(text)
  return realize_source.TextPart(realize_string(text))
end

function Crochet.param(name)
  return realize_source.ParamRef(realize_string(name))
end

function Crochet.capture_ref(name)
  return realize_source.CaptureRef(realize_string(name))
end

function Crochet.clause(...)
  return realize_source.Line(project_realize_parts({...}))
end

function Crochet.stmt(...)
  return realize_source.LineNode(project_realize_parts({...}))
end

function Crochet.stmt_blank()
  return realize_source.BlankNode
end

function Crochet.body(nodes)
  assert(type(nodes) == "table", "body(nodes): nodes must be table")
  return realize_source.Block(nodes)
end

function Crochet.nest(opener, body, closer)
  return realize_source.NestNode(project_realize_line(opener), body, project_realize_line(closer))
end

function Crochet.value(name, value)
  if value == nil then value = name; name = "value" end
  if type(value) == "table" and value.kind == "ValueRef" then return value end
  return realize_rt.ValueRef(realize_string(name), value)
end

function Crochet.capture(name, value)
  return realize_source.Capture(realize_string(name), Crochet.value(name, value))
end

function Crochet.proto(name, params, captures, body)
  assert(type(params) == "table", "proto(name, params, captures, body): params must be table")
  assert(type(captures) == "table", "proto(name, params, captures, body): captures must be table")
  return realize_kind("TextProto", {
    name = realize_string(name),
    params = realize_copy(params),
    captures = realize_copy(captures),
    body = body,
  })
end

function Crochet.closure_body(stmts)
  assert(type(stmts) == "table", "closure_body(stmts): stmts must be table")
  return realize_kind("ClosureBlock", { stmts = realize_copy(stmts) })
end

function Crochet.param_expr(name)
  return realize_kind("ParamExpr", { name = realize_string(name) })
end

function Crochet.capture_expr(name)
  return realize_kind("CaptureExpr", { name = realize_string(name) })
end

function Crochet.local_expr(name)
  return realize_kind("LocalExpr", { name = realize_string(name) })
end

function Crochet.literal_expr(name, value)
  if value == nil then value = name; name = "literal" end
  return realize_kind("LiteralExpr", { value = Crochet.value(name, value) })
end

function Crochet.call_expr(fn, args)
  assert(type(args) == "table", "call_expr(fn, args): args must be table")
  return realize_kind("CallExpr", { fn = fn, args = realize_copy(args) })
end

function Crochet.index_expr(base, key)
  return realize_kind("IndexExpr", { base = base, key = key })
end

function Crochet.unary_expr(op, value)
  return realize_kind("UnaryExpr", { op = source_unary_op(op), value = value })
end

function Crochet.binary_expr(op, lhs, rhs)
  return realize_kind("BinaryExpr", { op = source_binary_op(op), lhs = lhs, rhs = rhs })
end

function Crochet.let_stmt(name, value)
  return realize_kind("LetStmt", { name = realize_string(name), value = value })
end

function Crochet.set_stmt(name, value)
  return realize_kind("SetStmt", { name = realize_string(name), value = value })
end

function Crochet.effect_stmt(expr)
  return realize_kind("EffectStmt", { expr = expr })
end

function Crochet.return_stmt(value)
  return realize_kind("ReturnStmt", { value = value })
end

function Crochet.if_stmt(cond, then_body, else_body)
  return realize_kind("IfStmt", { cond = cond, then_body = then_body, else_body = else_body or Crochet.closure_body({}) })
end

function Crochet.for_range_stmt(name, start, stop, step, body)
  return realize_kind("ForRangeStmt", { name = realize_string(name), start = start, stop = stop, step = step, body = body })
end

function Crochet.while_stmt(cond, body)
  return realize_kind("WhileStmt", { cond = cond, body = body })
end

Crochet.const = Crochet.literal_expr
Crochet.call = Crochet.call_expr
Crochet.index = Crochet.index_expr
Crochet.unary = Crochet.unary_expr
Crochet.binary = Crochet.binary_expr
Crochet.let = Crochet.let_stmt
Crochet.set = Crochet.set_stmt
Crochet.effect = Crochet.effect_stmt
Crochet.ret = Crochet.return_stmt
Crochet.if_ = Crochet.if_stmt
Crochet.for_range = Crochet.for_range_stmt
Crochet.while_ = Crochet.while_stmt

function Crochet.closure_proto(name, params, captures, body)
  assert(type(params) == "table", "closure_proto(name, params, captures, body): params must be table")
  assert(type(captures) == "table", "closure_proto(name, params, captures, body): captures must be table")
  return realize_kind("ClosureProto", {
    name = realize_string(name),
    params = realize_copy(params),
    captures = realize_copy(captures),
    body = body,
  })
end

function Crochet.catalog(protos, entry_name, mode)
  assert(type(protos) == "table", "catalog(protos, entry_name, mode): protos must be table")
  if type(mode) == "table" and mode.kind == "LuaClosureHost" and all_text_protos(protos) then
    return realize_source.Catalog(protos, realize_string(entry_name), realize_source.ClosureMode)
  end
  if (mode == "closure" or (type(mode) == "table" and mode.kind == "LuaClosureHost")) and all_closure_protos(protos) then
    return closure_catalog(protos, entry_name, type(mode) == "table" and mode or lua_closure_host(DIRECT_CLOSURE_MODE))
  end
  if type(mode) == "table" and mode.kind == "LuaSourceHost" then
    return realize_source.Catalog(protos, realize_string(entry_name), realize_source.SourceMode)
  end
  if type(mode) == "table" and mode.kind == "LuaBytecodeHost" then
    return realize_source.Catalog(protos, realize_string(entry_name), realize_source.BytecodeMode)
  end
  return realize_source.Catalog(protos, realize_string(entry_name), realize_package_mode(mode))
end

-- Check authored proto input into validated proto structure.
function Crochet.check(catalog)
  if catalog.kind == "ClosureCatalog" then return closure_check_catalog(catalog) end
  return catalog:check_realize()
end

-- Lower checked proto into install-oriented proto plans.
function Crochet.lower(checked)
  if checked.kind == "ClosureCheckedCatalog" then return closure_lower_catalog(checked) end
  return checked:lower_realize()
end

-- Prepare Lua-hosted install artifacts from proto plans.
function Crochet.prepare(plan)
  if plan.kind == "ClosurePlanCatalog" then return closure_prepare_catalog(plan) end
  return plan:prepare_install()
end

-- Install prepared proto artifacts into callable runtime artifacts.
function Crochet.install(lua_catalog)
  if lua_catalog.kind == "ClosureInstallCatalog" then return closure_install(lua_catalog) end
  return lua_catalog:install()
end

-- Full proto compiler pipeline: source proto -> checked -> plan -> install.
function Crochet.compile(catalog)
  return Crochet.install(Crochet.prepare(Crochet.lower(Crochet.check(catalog))))
end

return Crochet
