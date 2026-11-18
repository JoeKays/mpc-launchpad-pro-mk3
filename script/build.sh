#!/bin/sh
# Build the deployable controller script into build/:
#   build/LaunchpadProMK3.lua — minified artifact (comments/indentation stripped)
#   build/LaunchpadProMK3.ini — signed ini; its checksum covers the artifact
# The checksum is sha256(lua_bytes || salt); the salt is read from the owner's own
# MPC binary at run time. Set MPC_BIN to your own MPC binary (see CONTRIBUTING.md).
set -eu
cd "$(dirname "$0")"
: "${MPC_BIN:?set MPC_BIN to your own MPC binary (see CONTRIBUTING.md)}"
mkdir -p ../build
../tools/minify-lua.sh LaunchpadProMK3.lua > ../build/LaunchpadProMK3.lua
if command -v luac5.4 >/dev/null 2>&1; then
	luac5.4 -p ../build/LaunchpadProMK3.lua
else
	echo "build.sh: warning: luac5.4 not found; skipped the syntax check" >&2
fi
cp LaunchpadProMK3.ini.in ../build/LaunchpadProMK3.ini
python3 ../tools/sign_script.py "$MPC_BIN" ../build/LaunchpadProMK3.lua ../build/LaunchpadProMK3.ini >/dev/null
../tools/check-ini.sh LaunchpadProMK3.ini.in template
../tools/check-ini.sh ../build/LaunchpadProMK3.ini artifact
wc -c ../build/LaunchpadProMK3.lua LaunchpadProMK3.lua | sed '$d'
grep '^checksum=' ../build/LaunchpadProMK3.ini
