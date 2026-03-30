#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

run() {
  echo "> $*"
  "$@"
}

run luajit examples/luajit/luajit_synth.lua
run luajit examples/luajit/luajit_biquad.lua
run luajit examples/luajit/luajit_app_demo.lua
run terra unit.t status examples/inspect/demo_project
run terra unit.t scaffold-file examples/inspect/demo_project Demo.Expr
run terra unit.t status examples/ui3
run terra unit.t path examples/ui3 UiDecl.Document
run terra unit.t scaffold-file examples/ui3 UiDecl.Document
run terra unit.t status examples/tasks_ui3

echo "run_example_smokes.sh: ok"
