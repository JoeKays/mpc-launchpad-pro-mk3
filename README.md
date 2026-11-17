# mpc-launchpad-pro-mk3

A Novation Launchpad Pro MK3 controller script for Akai MPC 3.10.1 (Gen2, MPC Live III).

Built from the documented Lua controller-script layer in
[open-mpc/mpc-controllers](https://github.com/open-mpc/mpc-controllers), with the
ForceLink controller as the worked example and the APC mini mk2 / Korg nanoKONTROL
scripts as additional patterns.

## Status

Phase 1 (clip mode) + transport + track row/function buttons + clip clear/duplicate +
track volume/pan/sends + tap tempo + tempo page + swing page + quantize + Q-Link page +
live clip states (listener-driven LEDs, optional current-track follow) + MPC pads mode +
the Shift transport buttons (loop/overdub/automation filter) +
track navigation, plugin presets and the firmware probe are implemented and host-tested.

## What it does

- **Clip mode**: the 8x8 grid is a window onto the MPC clip matrix. Pad press launches the
  clip under it; Shift+pad selects it without launching. LEDs show the live clip state via
  property listeners (no polling): empty slots dark (selected = dim white), stopped clips
  in their own colour (solid), playing/queued green, recording red; transitions blink fast
  (2 Hz), playing/recording blink slow (1 Hz). The bottom-left pad maps to MPC row 7
  (bottom); the top-left pad maps to MPC row 0 (top).
- **Scene launch**: right column CC 89-19 launches scene rows 0-7 (89 = top row, 19 = bottom).
  Shift + those = the label functions (patterns/steps/pattern settings/velocity/probability/
  mutation/micro step/print to clip).
- **Window scrolling**: 91/92 left/right, 80/70 up/down; Shift + 80/70 moves by 8,
  Shift + 91/92 = previous/next track. Scrolling re-registers the slot listeners for the
  new window.
- **Follow current track** (optional, off by default; Shift + CC 93 toggles): the grid
  follows MPC's current track (`currentTrack.Index` listener moves the window; the
  master track shows the Master matrix).
- **Transport**: 20 play/stop toggle, 10 record; Shift + CC 1/2 = undo/redo,
  Shift + 20 = loop on/off, Shift + 10 = overdub, Shift + 30 = automation filter cycle.
  The play LED shows loop state (green playing, orange loop armed) and the record LED
  shows overdub (red recording, orange overdubbing).
- **Track row**: CC 101-108 selects the track under that grid column (follows the window).
  Shift + < / > (CC 91/92) = previous/next track; Shift + note/chord (CC 94/95) =
  previous/next plugin preset on the current track.
- **Function buttons**: CC 1-8 = record arm/mute/solo/volume/pan/sends/device/stop clip.
  Hold CC 1-3/8, then press a track button (CC 101-108) to apply it to that track.
  CC 4-6 open fader menus, CC 7 toggles the Q-Link page. Shift + CC 1/2/3/6/7/8 =
  undo/redo/click/tap/tempo/swing.
- **Clip edits**: CC 60 clear (arm, then press the clip pad), CC 50 duplicate (arm, press
  the origin pad, then the target pad); CC 40 quantize applies quantize via
  `controlSurface.quantizeApply`.
- **Track controls**: press volume/pan/sends (CC 4/5/6) to open a fader menu aligned with
  the clip view; press a grid pad to set a track's value, up/down (CC 80/70, ±1/8) to
  nudge, and press the function button again to exit; tapping CC 6 cycles sends. Volume/pan/sends write `normalTracks[i].Volume/Pan/Send1-4.value`.
- **Tempo/swing**: Shift + CC 6 = tap tempo (native: while Shift is held CC 6 drives the
  MPC's own Tap Tempo control and is restored to the script on Shift release; manual
  averager fallback when that routing is missing); Shift + CC 7 = tempo page (BPM digits on the
  grid, up/down + hold to accelerate); Shift + CC 8 = swing page (swing % on the grid,
  50-75 where 50% is straight timing, up/down + hold to accelerate; reads/writes
  `sequencer.quantiser.GetSwing`/`SetSwing`).
- **Q-Link page**: CC 7 (device) opens the Q-Link page; only assigned Q-Links get
  fader columns, compacted left-to-right with no gaps (the page-open log lists the
  map); tapping Device cycles page 1 -> page 2 -> exit. Each fader keeps its MPC
  Q-Link bank colour (cyan/magenta/yellow/blue). Press a pad to set that Q-Link
  (Touch + Twist), Shift+up/down nudges the last touched column by 1. Flip/binary
  parameters are learned while you play: presses round to the extremes and the column
  shows a single lit extreme pad. Unassigned Q-Links stay dark. Shift + CC 7 remains
  the tempo page.
- **MPC pads mode**: tapping CC 94 iterates clip grid -> drum (bottom-left 4x4 =
  MPC pad bank A, colours mirrored) -> chromatic (full grid in perfect 4ths via
  virtual pads, octave shifted by up/down, C notes marked) -> clip grid (CC 93 also
  exits at any point).
- **Modes**: 93 session = clip (Shift = toggle follow), 94 note = MPC pads mode,
  95 chord = cycles the MPC's keyboard/chord pad modes inside pads mode, 96 custom =
  stub, 97 sequencer = opens the MPC step seq view (Shift = next bar); Shift + 98 =
  save; Shift + right-column 89/79/69 = clip/step/track modes.
  Pad modes, fader menus and tempo/swing pages are mutually exclusive.
- **Probe mode**: Shift + 99 (Novation logo) logs every incoming note/CC and lights the
  pressed control white — use it to verify the physical mapping on your unit.

## Layout

| Path | What |
|---|---|
| `docs/API-CONTRACT.md` | the MPC 3.10.1 Lua API surface this script relies on |
| `docs/LPP3-LAYOUT.md` | Launchpad Pro MK3 Programmer-mode note/CC map + LED protocol |
| `docs/PATTERNS.md` | reusable patterns from the reference controllers |
| `docs/MAPPING.md` | the button/pad mapping this script implements |
| `docs/INSTALL.md` | install + signing procedure |
| `docs/DEVICE-TEST-PLAN.md` | on-hardware test steps |
| `docs/LIMITATIONS.md` | what the script cannot do |
| `docs/REVIEW.md` | review of the implementation against the API contract |
| `script/` | `LaunchpadProMK3.lua`, `.ini.in`, `build.sh` |
| `tools/` | `sign_script.py` (salt read from the owner's own MPC binary) |
| `tests/` | Lua mock harness + wire assertions |
| `references/` | non-committed example repos (gitignored) |

## Quick start

```sh
# 1. Build + sign (salt read from your own MPC binary; never written)
MPC_BIN=/path/to/MPC ./script/build.sh

# 2. Host tests (no hardware)
./tests/run-tests.sh

# 3. Copy LaunchpadProMK3.ini + LaunchpadProMK3.lua to the MPC's Devices folder
#    (see docs/INSTALL.md for the search dirs)
```

## Verification

- `luac5.4 -p script/LaunchpadProMK3.lua` — syntax.
- `selene script/LaunchpadProMK3.lua` — lint (0 errors, 0 warnings; optional, install selene
  or use the bundled path).
- `stylua --check script/LaunchpadProMK3.lua` — formatting (optional).
- `./tests/run-tests.sh` — mock MPC + LPP3 wire assertions; it runs selene when present.
- On hardware: `docs/DEVICE-TEST-PLAN.md`, plus the script's probe mode.

## Ground rules

- Akai binaries and the signing salt are never committed. The signer reads the salt
  from the owner's own MPC binary at run time.
- Claims are firmware-specific: MPC 3.10.1.8 (build 38fdde70994) unless stated.
- Degrade, never break: every optional API call is guarded; a missing feature disables
  its surface, never crashes the host app.
