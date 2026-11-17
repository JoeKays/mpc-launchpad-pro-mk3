# Limitations

Firmware: MPC 3.10.1.8 (build 38fdde70994). The hard walls are from
`open-mpc/mpc-controllers/docs/limitations.md`; the script-specific limits are marked
**[script]**.

## Hard walls (Lua cannot cross)

| Limit | Evidence | Consequence |
|---|---|---|
| **No state dump**: `#GetState` / `mpc.GetState` are nil | FINDINGS 19, 25 | The script reads state through property listeners, never a snapshot. |
| **No per-track MIDI input**: `normalTracks[i]` has no input port/channel/monitor; the `mpc.tracks.Get*` getters error | FINDINGS 33 | Track input routing must be set by hand in MPC. |
| **Cannot drive a non-current track**: `aperture.SelectTrack` moves MPC's current track; no separate controller track | FINDINGS 33 | Track functions act on the selected track. |
| **Note editing only on the selected clip** | FINDINGS 33 | No per-clip event editing from the surface. |
| **Scale/root of pad perform is invisible** | FINDINGS 29 | The script cannot show the MPC's scale/root. |
| **`qlinks.GetPosition()` lags one change**; `Twist` wraps | FINDINGS 26 | Q-links are not implemented in phase 1. |
| **Q-link bank changes update all 16 at once** | FINDINGS 26 | Q-links are not implemented in phase 1. |
| **No LED state for `mpc.force.*`** | FINDINGS 30 | The script derives lights from readable state. |
| **No USB access** from Lua | FINDINGS 2 | No Push 2 display, no bulk USB. |
| **Gen 2 (Live III) has no stock root** | FINDINGS 2, 7, 30 | Out of scope here. |

## Script-specific limits (phase 1)

| Limit | Status |
|---|---|
| **Q-links** | Not implemented (later phase). |
| **Track volume/pan/sends** | Implemented as a hold + track-button adjustment mode (grid rows / up-down nudges); no physical faders. |
| **Track adjustment mode** | Grid pads set 8 discrete values (`row / 7`); up/down nudge by 1/8. No finer control. |
| **Track device** | Stubbed with `TODO` logs (later phase). |
| **Velocity/probability/mutation/micro-step/print-to-clip pages** | Stubbed with `TODO` logs. |
| **Note/chord/custom modes** | Stubbed; the script only switches the mode label. |
| **Save/quantize/duplicate/clear** | Stubbed with `TODO` logs. |
| **Swing/tempo** | Stubbed with `TODO` logs. |
| **Scene launch on right column CC 89-19** | Implemented; confirm the physical row on hardware. |
| **CC 30 (fixed length)** | Registered, but absent from the learn artifact; may not arrive. |
| **LPP3 mode** | The script enters Programmer mode automatically (layout query + select 0x11) and restores the prior layout on unload. |
| **LED budget** | One sysex message per paint cycle; the LPP3 accepts up to 106 specs. |

## Degrade behaviour

- Missing aperture → clip surface disabled, transport/track row/function buttons continue.
- Missing clipProperties → grid dark, clip launch still works via `mpc.clipMatrix`.
- Missing sequencer → transport buttons inert, no crash.
- Missing commandManager → undo/redo inert, no crash.
- Every optional API is behind `pcall`/nil checks; failures log once and continue.
