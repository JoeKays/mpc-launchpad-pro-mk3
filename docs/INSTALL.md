# Install + signing

Target: MPC 3.10.1.8 (build 38fdde70994), MPC Live III Gen2.

Citations to FINDINGS refer to the mpc-controllers findings doc (see CONTRIBUTING.md).

## 1. The pair

A controller script is a `.ini` + `.lua` pair:

- `LaunchpadProMK3.ini` — `[info]` first line, `input=` / `output=` port-name matches
  (order = port index used by `midiOut.Send*`), `script=`, `scriptVersion=`, `checksum=`.
- `LaunchpadProMK3.lua` — the script.

The `.ini` must start with `[info]`; otherwise MPC reads it but ignores it and never opens
the `.lua` (FINDINGS 18).

## 2. Sign

`checksum = sha256(lua_bytes || 36-char salt)`. The salt lives XOR-obfuscated in the MPC
binary; read it from your own copy, never publish it.

```sh
MPC_BIN=/path/to/your/MPC ./script/build.sh
```

`tools/sign_script.py` reads the salt from the 3.10.0.49 Gen2 binary at file offset
`0x5287C10` (build id `2209920bc0a`), XOR-decodes it with key `0x5F694973D3C78945`, and
rewrites the `checksum=` line. The same salt gives the correct checksum for Akai's shipped
`mpkMiniMkIV.lua` on 3.10.1.8 (verified: `tools/verify_salt.py` PASS on both builds).

If you have a different build, pass `MPC_SALT` (36 chars) instead of a binary.

## 3. Copy to the device

Search dirs (FINDINGS §1):

- `/usr/share/Akai/SME0/Devices` (read-only rootfs; not for user scripts)
- `<user root>/MPC Documents/Devices` — user root is `/storage`, `/data/UserData`, `/nvme`
  or `/sdcard` depending on the device. On the Live III it is normally
  `/nvme/MPC Documents/Devices/`.

```sh
mkdir -p "/nvme/MPC Documents/Devices/LaunchpadProMK3"
cp LaunchpadProMK3.ini LaunchpadProMK3.lua "/nvme/MPC Documents/Devices/LaunchpadProMK3/"
```

## 4. Verify it loaded

```sh
journalctl -u acvs -o cat --no-pager | grep LaunchpadProMK3
```

Expected first lines: `LaunchpadProMK3: aperture ok`, `clipProperties ok`, `loaded`.
If you see `aperture MISSING`, the clip surface is disabled but the script still runs
(transport/track row/function buttons continue).

## 5. Rollback

Remove the folder and restart MPC (or reload the device script list):

```sh
rm -rf "/nvme/MPC Documents/Devices/LaunchpadProMK3"
```

The script never writes to the MPC project; removing it restores the stock behaviour.

## 6. Notes

- The LPP3 boots into Live mode. The script sends the layout query
  `F0 00 20 29 02 0E 00 F7`, captures the prior layout from the response, then sends
  `F0 00 20 29 02 0E 00 11 00 00 F7` (layout 17 = Programmer) on the first timer tick.
  On unload it restores the captured layout (default 0x04 Note/Drum if the query did not
  answer). Journal lines: `prior layout 0x04 page 0`, `programmer mode`, `restored layout`.
- The checksum is skipped when the hardware product code is 0 (desktop MPC software).
- Never commit the salt or Akai binaries.
