#!/bin/sh
# Build the Launchpad Pro MK3 controller script: copy the .ini template and sign it.
# The checksum is sha256(lua_bytes || salt); the salt is read from the owner's own MPC
# binary at run time. Set MPC_BIN to your own MPC binary (see CONTRIBUTING.md).
set -eu
cd "$(dirname "$0")"
: "${MPC_BIN:?set MPC_BIN to your own MPC binary (see CONTRIBUTING.md)}"
cp LaunchpadProMK3.ini.in LaunchpadProMK3.ini
python3 ../tools/sign_script.py "$MPC_BIN" LaunchpadProMK3.lua LaunchpadProMK3.ini >/dev/null
grep '^checksum=' LaunchpadProMK3.ini
