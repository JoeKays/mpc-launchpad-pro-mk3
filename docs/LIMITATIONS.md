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
| **`qlinks.GetPosition()` lags one change** | FINDINGS 26 | The Q-Link page recomputes the delta per Twist (max 2 calls per set) so a pad set lands even when the read lags. |
| **Q-link bank changes update all 16 at once** | FINDINGS 26 | The Q-Link page shows 8 at a time (banks 0-7 / 8-15) and repaints on every paint cycle. |
| **No LED state for `mpc.force.*`** | FINDINGS 30 | The script derives lights from readable state. |
| **No USB access** from Lua | FINDINGS 2 | No Push 2 display, no bulk USB. |
| **Gen 2 (Live III) has no stock root** | FINDINGS 2, 7, 30 | Out of scope here. |

## Script-specific limits (phase 1)

| Limit | Status |
|---|---|
| **Q-Link page** | Implemented (CC 7 device): Q-Links 0-7 (up/down switches to 8-15) as cyan bottom-up faders, press a pad to set that Q-Link, Shift+up/down nudges the last touched column by ±1. Changes go through `Touch()` + `Twist(delta)` on `mpc.controlSurface.qlinks[i]`; if `Twist` is missing the script falls back to `SetPosition` and logs `setpos`. |
| **Twist, not SetPosition** | Device-verified: `SetPosition` changes the qlink's ValueString but the MPC edit-mode value does not move (an earlier SetPosition-driven page was reverted for exactly this). The page therefore drives `Twist` deltas (target − `GetPosition()`, clamped ±127, ≤ 2 calls) with `Touch()` around the burst; `Twist`'s exact signature is undocumented, so every call is pcall-guarded and a missing `Twist` degrades to the `SetPosition` fallback. |
| **Volume/pan/sends menus** | Grid pads set 8 discrete values; volume uses clean dB steps (-inf, -30, -20, -9, -3, 0, +3, +6 dB) via the measured fader curve `dB = 40*log10(gain) + 6`, pan/sends use `(8 - row) / 8`; up/down nudge one step. No finer control. |
| **Track device (CC 7)** | Implemented as the Q-Link page above; Shift + CC 7 remains the tempo page. Device hold for track functions is no longer available (it was unsupported anyway). |
| **Velocity/probability/mutation/micro-step/print-to-clip pages** | Stubbed with `TODO` logs. |
| **Chord mode (CC 95)** | Stubbed with a `TODO` log. Shift + CC 94/95 doubles as plugin preset prev/next. |
| **MPC pads mode (CC 94)** | Implemented: the bottom-left 4x4 grid quadrant is hardware-routed to the MPC pads (`mappings.pads.AddNoteToMpcPad`; the notes no longer reach the script) and mirrors `controlSurface.pads[i].Colour` (ARGB, alpha ignored). The mirror is polled from the timer every ~100 ms (there are no pad-colour listeners), so a colour change can lag up to ~100 ms; only changed colours are sent. The rest of the grid is dark and inert while the mode is open. |
| **Track mute mode (CC 96)** | Implemented: the bottom two grid rows are hardware-routed to the track mutes (`mappings.tracks.mutes.AddNoteToTrackMute`), always tracks 0-15, independent of the grid window. Unmuted pads show the track colour, muted pads dim grey; tracks beyond `SizeNormalTracks` stay dark. |
| **Pad modes vs pages** | CC 94/96, the volume/pan/sends menus and the tempo/swing pages are mutually exclusive: entering any of them closes the others (and armed clip ops); CC 93 (session) or another mode also leaves a pad mode. |
| **Save** | Stubbed with a `TODO` log. |
| **Quantize** | CC 40 applies quantize via `mpc.controlSurface.quantizeApply.Press()`/`Release()`; the quantize button is white when the control exists. The quantize settings live on `mpc.sequencer.quantiser` (`SetEnabled`, `SetStrength`, `SetTimeDivision`, `SetWindow`, `SetShift`, `SetSwing`). |
| **Duplicate/clear** | Implemented via `mpc.clipMatrix.CopyClip`/`DeleteClip`: hold CC 50/60, then press the origin/target or clip pads. The op is active only while the button is held; duplicate keeps the origin so one source can be copied to many targets. If the API is missing the script logs the attempted call and does nothing. |
| **`mpc.clipMatrix.CopyClip`/`DeleteClip`** | Present in the 3.10.1 binary; confirm on hardware. |
| **Clip state colours / blink** | With `clipProperties` the grid shows live states (empty dark, selected empty dim white, stopped = clip colour solid, playing/queued green, recording red). The MPK's hardware fast/slow blink channels are rendered as 2 Hz / 1 Hz repaints alternating full colour with dim — the RGB sysex used has no blink channel. Selection shows on empty slots only (single-pad ring substitute). |
| **Follow current track** | The grid follows `mpc.tracks.currentTrack.Index` (`SetActiveMatrix` Normal/Master + `aperture.MoveToColumn`) and rebinds its slot listeners on every window move (manual scrolling included). Guarded: without `SetActiveMatrix`/`MoveToColumn` the follow degrades to manual scrolling only. |
| **Track volume/pan/sends** | Implemented as menus: press CC 4/5/6, press a grid pad to set a track's value, up/down to nudge; tapping CC 6 cycles sends. Volume writes `VolumeDB` (dB) with a `Volume` fallback; sends 1-4 use different colours. |
| **Stop clip** | Hold CC 8 + a track button (CC 101-108) or a clip pad stops that track's clips (`aperture.StopClipsOnTrack`); the clip pad does not launch while stop clip is held. |
| **Empty tracks** | Fader menus only light tracks below `mpc.tracks.SizeNormalTracks`; empty tracks stay dark. |
| **Swing/tap tempo/tempo** | Shift + CC 6 = tap tempo (native: while Shift is held CC 6 is routed to the MPC's own Tap Tempo control via `RemoveCCToScript` + `controlSurface.AddCCToControl(0, 6, "Tap Tempo")` and restored to the script on Shift release; when that mapping is missing it falls back to `dev.timer.Now()` millisecond timestamps, averaging the last 5 taps, setting integer `sequencer.SetBPM`); Shift + CC 7 = tempo page (grid draws the BPM left-aligned as scaled 7-segment digits, coloured by position: ones white, tens orange, hundreds blue — blue/orange/white differ in hue and luminance for colourblind accessibility; up/down change BPM, hold accelerates); Shift + CC 8 = swing page (same 7-segment renderer, `quantiser.GetSwing`/`SetSwing` 50-75 — 50% is straight timing, up/down change swing, hold accelerates). |
| **Shift functions** | Shift + CC 1/2 = undo/redo, Shift + CC 3 = click/metronome, Shift + CC 6 = tap tempo, Shift + CC 7 = tempo page, Shift + CC 8 = swing page, Shift + CC 20 = loop on/off, Shift + CC 10 = overdub, Shift + CC 40 = quantiser on/off, Shift + CC 30 = automation filter cycle, Shift + CC 91/92 = current track prev/next, Shift + CC 94/95 = plugin preset prev/next. Shift functions work while a function button is held; the held function is preserved. |
| **Transport shift buttons** | Loop/overdub/quantiser/automation-filter need `sequencer.Loop`/`Overdub`/`quantiser.Enabled` and `project.AdvanceGlobalAutomationFilterType` (device-verified API facts on 3.10.1); a missing API logs once and the button stays inert. |
| **Track navigation + plugin presets** | Shift + < / > (CC 91/92) and Shift + note/chord (CC 94/95) call `mpc.tracks.currentTrack.Previous/Next/PrevPluginPreset/NextPluginPreset`; these exist on track objects in 3.10.1 — confirm on hardware. Missing methods log once. Shift + CC 91/92 replaces the old shift = move-window-by-8 (CC 80/70 keep shift = 8). |
| **Firmware probe** | OnLoad sends the universal device inquiry (F0 7E 7F 06 01 F7, payload without F0/F7); the Novation identity reply (7E … 06 02 00 20 29 …) is parsed once and logged (`firmware: <ver>`), log-only — it never gates anything. |
| **Scene launch on right column CC 89-19** | Implemented; confirm the physical row on hardware. |
| **CC 30 (fixed length)** | Registered, but absent from the learn artifact; may not arrive. Shift + CC 30 = automation filter cycle if it does. |
| **LPP3 mode** | The script enters Programmer mode automatically (layout query + select 0x11) and restores the prior layout on unload. |
| **LED budget** | One sysex message per paint cycle; the LPP3 accepts up to 106 specs. |

## Degrade behaviour

- Missing aperture → clip surface disabled, transport/track row/function buttons continue.
- Missing clipProperties → the grid falls back to timer polling of `mpc.clipMatrix` (stopped/playing/queued granularity, 2 s full resend); slot listeners, live state colours and follow are off; clip launch still works via `mpc.clipMatrix`.
- Missing sequencer → transport buttons and Shift + CC 3 metronome inert, no crash.
- Missing commandManager → Shift + CC 1/2 undo/redo inert, no crash.
- Missing `mpc.clipMatrix.CopyClip`/`DeleteClip` → duplicate/clear log the attempted call, no crash.
- Missing `mpc.controlSurface.qlinks` → CC 7 logs once and does not open the Q-Link page; Shift + CC 7 (tempo page) and everything else continue.
- Every optional API is behind `pcall`/nil checks; failures log once and continue.
- Missing `mappings.pads` / `mappings.tracks.mutes` → the CC 94/96 mode buttons stay off and the modes do not enter; no crash.
