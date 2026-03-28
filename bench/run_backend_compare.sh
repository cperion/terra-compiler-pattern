#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

TERRA_OUT=$(mktemp)
LJ_OUT=$(mktemp)
trap 'rm -f "$TERRA_OUT" "$LJ_OUT"' EXIT

echo "> terra bench/backend_terra.t"
terra bench/backend_terra.t | tee "$TERRA_OUT"
echo
echo "> luajit bench/backend_luajit.lua"
luajit bench/backend_luajit.lua | tee "$LJ_OUT"
echo
echo "> luajit bench/backend_compare_report.lua"
luajit bench/backend_compare_report.lua "$TERRA_OUT" "$LJ_OUT"
