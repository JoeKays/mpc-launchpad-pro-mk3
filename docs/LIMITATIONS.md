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
| **Volume/pan/sends menus** | Grid pads set 8 discrete values; volume uses clean dB steps (-inf, -30, -20, -9, -3, 0, +3, +6 dB) via the measured fader curve `dB = 40*log10(gain) + 6`, pan/sends use `(8 - row) / 8`; up/down nudge one step. No finer control. |
| **Track device** | Stubbed with `TODO` logs (later phase). |
| **Velocity/probability/mutation/micro-step/print-to-clip pages** | Stubbed with `TODO` logs. |
| **Chord mode (CC 95)** | Stubbed with a `TODO` log. |
| **MPC pads mode (CC 94)** | Implemented: the bottom-left 4x4 grid quadrant is hardware-routed to the MPC pads (`mappings.pads.AddNoteToMpcPad`; the notes no longer reach the script) and mirrors `controlSurface.pads[i].Colour` (ARGB, alpha ignored). The mirror is polled from the timer every ~100 ms (there are no pad-colour listeners), so a colour change can lag up to ~100 ms; only changed colours are sent. The rest of the grid is dark and inert while the mode is open. |
| **Track mute mode (CC 96)** | Implemented: the bottom two grid rows are hardware-routed to the track mutes (`mappings.tracks.mutes.AddNoteToTrackMute`), always tracks 0-15, independent of the grid window. Unmuted pads show the track colour, muted pads dim grey; tracks beyond `SizeNormalTracks` stay dark. |
| **Pad modes vs pages** | CC 94/96, the volume/pan/sends menus and the tempo/swing pages are mutually exclusive: entering any of them closes the others (and armed clip ops); CC 93 (session) or another mode also leaves a pad mode. |
| **Save** | Stubbed with a `TODO` log. |
| **Quantize** | CC 40 applies quantize via `mpc.controlSurface.quantizeApply.Press()`/`Release()`; the quantize button is white when the control exists. The quantize settings live on `mpc.sequencer.quantiser` (`SetEnabled`, `SetStrength`, `SetTimeDivision`, `SetWindow`, `SetShift`, `SetSwing`). |
| **Duplicate/clear** | Implemented via `mpc.clipMatrix.CopyClip`/`DeleteClip`: hold CC 50/60, then press the origin/target or clip pads. The op is active only while the button is held; duplicate keeps the origin so one source can be copied to many targets. If the API is missing the script logs the attempted call and does nothing. |
| **`mpc.clipMatrix.CopyClip`/`DeleteClip`** | Present in the 3.10.1 binary; confirm on hardware. |
| **Track volume/pan/sends** | Implemented as menus: press CC 4/5/6, press a grid pad to set a track's value, up/down to nudge; tapping CC 6 cycles sends. Volume writes `VolumeDB` (dB) with a `Volume` fallback; sends 1-4 use different colours. |
| **Stop clip** | Hold CC 8 + a track button (CC 101-108) or a clip pad stops that track's clips (`aperture.StopClipsOnTrack`); the clip pad does not launch while stop clip is held. |
| **Empty tracks** | Fader menus only light tracks below `mpc.tracks.SizeNormalTracks`; empty tracks stay dark. |
| **Swing/tap tempo/tempo** | Shift + CC 6 = tap tempo (uses `dev.timer.Now()` millisecond timestamps, averages the last 5 taps, sets integer `sequencer.SetBPM`); Shift + CC 7 = tempo page (grid draws the BPM left-aligned as scaled 7-segment digits, coloured by position: ones white, tens orange, hundreds blue — blue/orange/white differ in hue and luminance for colourblind accessibility; up/down change BPM, hold accelerates); Shift + CC 8 = swing page (same 7-segment renderer, `quantiser.GetSwing`/`SetSwing` 50-75 — 50% is straight timing, up/down change swing, hold accelerates). |
| **Shift functions** | Shift + CC 1/2 = undo/redo, Shift + CC 3 = click/metronome, Shift + CC 6 = tap tempo, Shift + CC 7 = tempo page, Shift + CC 8 = swing page. Shift functions work while a function button is held; the held function is preserved. |
| **Scene launch on right column CC 89-19** | Implemented; confirm the physical row on hardware. |
| **CC 30 (fixed length)** | Registered, but absent from the learn artifact; may not arrive. |
| **LPP3 mode** | The script enters Programmer mode automatically (layout query + select 0x11) and restores the prior layout on unload. |
| **LED budget** | One sysex message per paint cycle; the LPP3 accepts up to 106 specs. |

## Degrade behaviour

- Missing aperture → clip surface disabled, transport/track row/function buttons continue.
- Missing clipProperties → grid dark, clip launch still works via `mpc.clipMatrix`.
- Missing sequencer → transport buttons and Shift + CC 3 metronome inert, no crash.
- Missing commandManager → Shift + CC 1/2 undo/redo inert, no crash.
- Missing `mpc.clipMatrix.CopyClip`/`DeleteClip` → duplicate/clear log the attempted call, no crash.
- Every optional API is behind `pcall`/nil checks; failures log once and continue.
- Missing `mappings.pads` / `mappings.tracks.mutes` → the CC 94/96 mode buttons stay off and the modes do not enter; no crash.
