#!/bin/sh
# Compares parsing and rendering the same page in StringCheese, Stencil,
# Mustache and Leaf.
# Usage: ./run.sh [seconds per measurement]
set -e
cd "$(dirname "$0")"
OUT=.build/outputs
mkdir -p "$OUT"

swift build -c release --product Compare >/dev/null
.build/release/Compare Fixtures "$OUT" "${1:-1}"
