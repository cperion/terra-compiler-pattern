#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

run() {
  echo "> $*"
  "$@"
}

run luajit tests/unit_core_test.lua
run luajit tests/unit_inspect_core_test.lua
run luajit tests/unit_schema_project_test.lua
run luajit tests/asdl2_text_lexer_test.lua
run luajit tests/asdl2_token_spec_test.lua
run luajit tests/asdl2_text_spec_test.lua
run luajit tests/frontend_machine_install_generated_test.lua
run luajit tests/frontend_machine_emit_lua_test.lua
run luajit tests/frontend_machine_emit_lua_build_test.lua
run luajit tests/frontend_result_sources_test.lua
run luajit tests/frontend_emit_lua_result_sources_test.lua
run luajit tests/frontend_const_bool_source_test.lua
run luajit tests/frontend_repeated_node_rule_refs_test.lua
run luajit tests/frontend_repeated_build_nodes_test.lua
run luajit tests/frontend_json_frontend_test.lua
run luajit tests/frontend_source_check_test.lua
run luajit tests/frontend_checked_lower_test.lua
run luajit tests/frontend_rule_ref_string_shape_test.lua
run luajit tests/frontend_captured_seq_choice_test.lua
run luajit tests/frontend_build_expr_test.lua
run luajit tests/frontend_build_scope_test.lua
run luajit tests/frontend_nested_rule_parse_test.lua
run luajit tests/frontend_lowered_define_machine_test.lua
run luajit tests/frontendc2_source_check_test.lua
run luajit tests/frontendc2_checked_lower_test.lua
run luajit tests/frontendc2_lowered_define_machine_test.lua
run luajit tests/frontendc2_structural_validate_runtime_test.lua
run luajit tests/data_realize_source_check_test.lua
run luajit tests/data_realize_checked_define_machine_test.lua
run luajit tests/unit_luajit_smoke.lua
run terra tests/unit_shared_terra_smoke.t

echo "run_shared_tests.sh: ok"
