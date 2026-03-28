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
run terra unit.t status examples/inspect/spec_demo.t
run terra unit.t scaffold examples/inspect/spec_demo.t Demo.Expr:lower

echo "run_example_smokes.sh: ok"
