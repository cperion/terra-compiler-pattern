#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

TERRA_OUT=$(mktemp)
LJ_OUT=$(mktemp)
trap 'rm -f "$TERRA_OUT" "$LJ_OUT"' EXIT

BENCH_BLOCK=1024 BENCH_WARMUP=4 BENCH_ITERS=8 BENCH_COMPILE_ITERS=4 terra bench/backend_terra.t > "$TERRA_OUT"
BENCH_BLOCK=1024 BENCH_WARMUP=4 BENCH_ITERS=8 BENCH_COMPILE_ITERS=4 luajit bench/backend_luajit.lua > "$LJ_OUT"
luajit bench/backend_compare_report.lua "$TERRA_OUT" "$LJ_OUT" >/dev/null

grep -q '^METRIC exec_biquad_ns_per_sample ' "$TERRA_OUT"
grep -q '^METRIC exec_biquad_ns_per_sample ' "$LJ_OUT"
grep -q '^METRIC compile_chain_edit_avg_ns ' "$TERRA_OUT"
grep -q '^METRIC compile_chain_edit_avg_ns ' "$LJ_OUT"
grep -q '^METRIC exec_chain_small_ns_per_sample ' "$TERRA_OUT"
grep -q '^METRIC exec_chain_small_ns_per_sample ' "$LJ_OUT"

echo "unit_backend_bench_smoke.sh: ok"
