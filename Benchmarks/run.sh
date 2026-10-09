#!/bin/sh
# Benchmarks parsing and rendering the fixtures in Fixtures/.
# Usage: ./run.sh [seconds per measurement]
set -e
cd "$(dirname "$0")"
OUT=.build/outputs
mkdir -p "$OUT"

swift build -c release --product SwiftBench >/dev/null
printf "%-10s %-34s %10s\n" "fixture" "measurement" "time"
.build/release/SwiftBench Fixtures "$OUT" "${1:-1}"
