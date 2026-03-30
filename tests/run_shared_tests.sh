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
run luajit tests/unit_luajit_smoke.lua
run terra tests/unit_shared_terra_smoke.t

echo "run_shared_tests.sh: ok"
