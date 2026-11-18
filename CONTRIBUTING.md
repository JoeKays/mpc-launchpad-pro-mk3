# Contributing / development notes

This file holds the local development and testing details that are **not** part of the
deliverable. The main docs describe the controller script; this file describes how to
reproduce the work on a development machine.

## Reference checkouts (not committed)

- `mpc-controllers` docs + ForceLink example: `<mpc-controllers-checkout>`
- Novation LPP3 programmer's reference text: `<lpp3-programmer-reference>`
- Extracted MPC 3.10.0.49 / 3.10.1 binaries and the shipped MPK mini IV pairs: `<kit-dir>`
- LPP3 learn artifact: `<parent-repo>/modules/ctrl-ce/port/midi/tests/learn-golden-lpp3.h` (parent repo)
- Example controllers: `references/` (gitignored)

## Signing

The checksum is `sha256(lua_bytes || 36-char salt)`. The salt is XOR-obfuscated in the
MPC binary; read it from your own copy, never publish it.

- `MPC_BIN=<kit-dir>/MPC-3.10.0.49 ./script/build.sh`
- `tools/verify_salt.py` checks the salt against the shipped MPK mini IV pairs under
  `<kit-dir>` (override with `XZT_DIR`).
- `tools/test-sign.sh` runs the signer tests; set `XZT_DIR` to your extracted kit dir.

## Tests

- `./tests/run-tests.sh` — `luac5.4 -p`, the ini regression gate (`tools/check-ini.sh`),
  `selene` (if present), and the mock tests.
- `selene` and `stylua` are optional; set `SELENE` to your selene binary.
- **Enable the pre-commit gate once per clone:**
  `git config core.hooksPath .githooks` — it blocks `.ini` regressions that the
  MPC loader refuses silently (no log, no load) and lua syntax errors. The same
  gate also runs inside `script/build.sh` and `tests/run-tests.sh`, so builds and
  tests fail loudly even in clones without the hook installed.

## Device

- SSH: `ssh root@<device-ip>` (passwordless key on this machine).
- Device path: `<user-root>/MPC Documents/Devices/LaunchpadProMK3/`.
- Restart MPC: `systemctl restart acvs` (closes the open project).
- Journal: `journalctl -u acvs -o cat --no-pager | grep LaunchpadProMK3`.

## Workflow artifacts

`dev/workflow.js` and `dev/workflow2.js` are the subagent orchestration scripts used to
build this project. They are gitignored and contain local paths.


## Device .ini constraints (MPC 3.10.1)

- `scriptVersion` must be a single-dot `MAJOR.MINOR` value. A semver string such as
  `1.2.0` makes the loader **silently skip the script** — no log line, no load.
  Additionally the loader can **reject a minor it doesn't know** the same silent
  way: `1.2` was accepted on one OS state and later silently refused (verified by
  probe scripts that loaded with `1.0` but not `1.2`). Use `1.0`, exactly like
  Akai's reference script. Device-verified.
- The loader matches `input=`/`output=` against connected port names and runs the
  script's chunk only when a port matches; keep one exact JUCE port name per line
  (e.g. `Launchpad Pro MK3 LPProMK3 MIDI`), like the reference ini.
