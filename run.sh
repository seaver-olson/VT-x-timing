#!/usr/bin/env bash
# Run from this directory after make. Redirection happens as your normal user.
set -euo pipefail
cpu=${1:-3}
samples=${2:-10000}
msr=${3:-0xe8}
mkdir -p results
output="results/rdmsr-$(date -u +%Y%m%dT%H%M%S)-$$.csv"
sudo insmod ./build/rdmsr_bench.ko cpu="$cpu" samples="$samples" msr="$msr"
trap 'sudo rmmod rdmsr_bench' EXIT
sudo cat /proc/rdmsr_bench > "$output"
python3 summarize.py "$output"
echo "Raw samples: $output"
