#!/bin/sh
# Run the host-side tests: Lua syntax, selene lint (if present), mock harness.
set -eu
cd "$(dirname "$0")/.."

echo "== luac -p =="
luac5.4 -p script/LaunchpadProMK3.lua
echo "luac: OK"

SELENE="${SELENE:-$(command -v selene || true)}"
if [ -n "$SELENE" ] && [ -x "$SELENE" ]; then
  echo "== selene =="
  "$SELENE" script/LaunchpadProMK3.lua || true
fi

for t in tests/test-*.lua; do
  echo "== $t =="
  lua5.4 "$t"
done

echo "ALL TESTS PASS"
