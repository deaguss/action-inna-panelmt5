#!/usr/bin/env bash
# Builds and runs ActionInna's native tests: the MQL5 sources compiled with g++ against mql.h.
#   tests/native/run.sh [seeds] [rounds] [fuzz-iterations] [fuzz-seed]
# Needs node and g++ (C++17). Build output goes to tests/native/out (not tracked).
set -euo pipefail
cd "$(dirname "$0")"
seeds="${1:-3}"
rounds="${2:-1}"
fuzz="${3:-300}"
fuzzSeed="${4:-20261021}"

node mql2cpp.js
flags=(-std=c++17 -O2 -Wall -Wno-unused-variable -Wno-unused-but-set-variable -Wno-sign-compare -Wno-unused-function -I out/src/Include -I .)
g++ "${flags[@]}" suites.cpp -o out/suites
g++ "${flags[@]}" app.cpp -o out/app
g++ "${flags[@]}" bridge.cpp -o out/bridge

status=0
./out/suites "$seeds" "$rounds" || status=1
./out/app "$fuzz" "$fuzzSeed" || status=1
./out/bridge 20000 "$fuzzSeed" || status=1
if [ "$status" -eq 0 ]; then echo "native tests: all passed"; else echo "native tests: FAILED"; fi
exit "$status"
