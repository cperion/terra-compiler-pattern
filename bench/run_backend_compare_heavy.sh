#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

OUT_DIR=${BENCH_OUT_DIR:-"bench/out/$(date +%Y%m%d-%H%M%S)"}
TRIALS=${BENCH_TRIALS:-5}
mkdir -p "$OUT_DIR"

scenarios=(
  "block4k_chain8:4096:8:32:128:16"
  "block16k_chain8:16384:8:32:256:16"
  "block16k_chain32:16384:32:32:256:16"
)

run_one() {
  local scenario_name=$1
  local block=$2
  local chain_len=$3
  local warmup=$4
  local iters=$5
  local compile_iters=$6
  local backend=$7
  local trial=$8
  local out="$OUT_DIR/${scenario_name}.${backend}.${trial}.metrics"

  echo "> ${backend} ${scenario_name} trial=${trial}"
  BENCH_BLOCK="$block" \
  BENCH_CHAIN_LEN="$chain_len" \
  BENCH_WARMUP="$warmup" \
  BENCH_ITERS="$iters" \
  BENCH_COMPILE_ITERS="$compile_iters" \
    "$@"
}

for spec in "${scenarios[@]}"; do
  IFS=':' read -r scenario_name block chain_len warmup iters compile_iters <<<"$spec"
  for trial in $(seq 1 "$TRIALS"); do
    echo "> terra ${scenario_name} trial=${trial}"
    BENCH_BLOCK="$block" \
    BENCH_CHAIN_LEN="$chain_len" \
    BENCH_WARMUP="$warmup" \
    BENCH_ITERS="$iters" \
    BENCH_COMPILE_ITERS="$compile_iters" \
      terra bench/backend_terra.t > "$OUT_DIR/${scenario_name}.terra.${trial}.metrics"

    echo "> luajit ${scenario_name} trial=${trial}"
    BENCH_BLOCK="$block" \
    BENCH_CHAIN_LEN="$chain_len" \
    BENCH_WARMUP="$warmup" \
    BENCH_ITERS="$iters" \
    BENCH_COMPILE_ITERS="$compile_iters" \
      luajit bench/backend_luajit.lua > "$OUT_DIR/${scenario_name}.luajit.${trial}.metrics"
  done
  echo
 done

luajit bench/backend_compare_matrix.lua "$OUT_DIR" | tee "$OUT_DIR/summary.md"
echo
echo "Saved benchmark metrics to: $OUT_DIR"
