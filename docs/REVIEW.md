# Review — LaunchpadProMK3.lua vs the API contract

Reviewer: parent session (after the subagent lanes). Target: MPC 3.10.1.8.
Device-verified 2026-11-17 on the MPC Live III (MPC 3.10.1, LPP3 on ALSA card 2).

## 1. API usage

| Item | Verdict | Evidence |
|---|---|---|
| Aperture acquisition with fallbacks | PASS | OnLoad: `dev.clipMatrixAperture or mpc.clipMatrix.clipMatrixAperture` |
| `SetColumns/SetRows/SetLabel/SetFollowsTUI/Show/Hide` guarded | PASS | `call(aperture.SetColumns, 8)` etc. |
| `TriggerClip/TriggerRow/StopClipsOnTrack/SelectClip/SelectTrack` | PASS | `doClip`, `doScene`, `applyFunction("stopClip")` |
| `MoveLeft/Right/Up/Down` | PASS | `moveWindow` |
| `ToGlobalColumn/ToGlobalRow` | PASS | `globalPos` |
| `clipProperties[c][r].Colour/State` listeners | PASS | `listenAll` |
| `sceneProperties[row].State` listener | PASS | `listenAll` |
| `mpc.tracks.normalTracks[i].Mute/Solo/RecArm` + setters | PASS | `paintTrack`, `applyFunction` |
| `mpc.sequencer.Play/Stop/Record/IsPlaying/Playing/RecordState/OverdubState` | PASS | `doTransport`, `paintLeft` |
| `commandManager.Undo/Redo` | PASS | `doShiftFunction` |
| `mpc.sequencer.SetMetronomeEnabled` | PASS | `doShiftFunction("solo")` |
| `mappings.script.AddNoteToScript/AddCCToScript/Remove*/SetHandleSysex` | PASS | OnLoad/OnUnload |
| `midiOut.SendMIDISysex` | PASS | `flushLEDs`, `sendLayout`, `queryLayout` |
| `dev.timer.Start/Stop` | PASS | OnLoad/OnUnload |
| Layout query/select | PASS | `queryLayout`, `sendLayout(0x11,0)`; device-verified `prior layout 0x04 page 0`, `programmer mode` |

## 2. Do-not-use list

| Item | Verdict | Evidence |
|---|---|---|
| `mpc.tracks.GetMute/SetMute/GetSolo/GetTrackRecordArmed` | PASS — not used | `applyFunction` uses `normalTracks[i]` |
| `mpc.GetState` / `#GetState` | PASS — not used | no reference |
| `pads.Tap` for velocity hits | PASS — not used | no pad mapping in phase 1 |
| `qlinks.GetPosition` | PASS — not used | Q-links stubbed |

## 3. Clip mode

| Item | Verdict | Evidence |
|---|---|---|
| 8x8 grid window | PASS | `paintGrid`, 10-note block formula |
| Pad press launches | PASS | `doClip` → `TriggerClip(col, 7-padRow)` |
| Shift+pad selects only | PASS | `doClip` checks `shift` |
| Grid row orientation | PASS | bottom-left note 11 → MPC row 7; top-left note 81 → MPC row 0; device-verified |
| Clip colours + state | PASS | `clipStatus`, `clipColour` |
| Scene launch right column | PASS | `doScene`, `SCENE = {89,79,...,19}` |
| Window scroll 91/92/80/70 | PASS | `moveWindow` |
| Shift page by 8 | PASS | `moveWindow(dir, shift and 8 or 1)` |

## 4. Transport + track row/function buttons

| Item | Verdict | Evidence |
|---|---|---|
| 20 play/stop toggle | PASS | `doTransport("play")` checks `IsPlaying` |
| 10 record | PASS | `doTransport("record")` |
| Track row CC 101-108 follows the grid | PASS | `globalPos(col,0)`; test covers scroll |
| Hold function CC 1-8 + track CC 101-108 | PASS | `applyFunction`; test covers rec arm/mute/solo/stop clip |
| Shift + CC 1/2/3/6/7/8 | PASS | `doShiftFunction` |
| 4-7 stubs | PASS (stub) | `applyFunction` logs TODO |

## 5. LED protocol

| Item | Verdict | Evidence |
|---|---|---|
| LPP3 sysex header `00 20 29 02 0E 03` | PASS | `flushLEDs` |
| RGB type 3, 0-127 | PASS | `ledRGB` clamps 0-127 |
| Cache per index | PASS | `padCache` |
| One message per paint cycle | PASS | `flushLEDs` sends once |
| Full repaint every 2 s | PASS | `HandleTimer` resets `padCache` every 40 ticks (50 ms tick) |

## 6. Degrade-never-break

| Item | Verdict | Evidence |
|---|---|---|
| Missing aperture | PASS | `logOnce("noaperture", ...)`, clip surface disabled |
| Missing clipProperties | PASS | `logOnce("noclips", ...)` |
| Missing sequencer | PASS | `paintLeft` guards `sq`; `doTransport` guards |
| Missing commandManager | PASS | `call(mpc.commandManager and ...)` |
| Missing timer | PASS | `call(dev.timer and ...)` |
| Missing mappings | PASS | `if m then ... end` |

## 7. Tests

| Item | Verdict | Evidence |
|---|---|---|
| Syntax | PASS | `luac5.4 -p` |
| Lint | PASS | `selene` 0 errors, 0 warnings |
| Formatting | PASS | `stylua --check` |
| Clip mapping | PASS | `tests/test-clip.lua` |
| Transport mapping | PASS | `tests/test-transport.lua` |
| Track mapping + scroll | PASS | `tests/test-track.lua` |
| Degrade | PASS | `tests/test-degrade.lua` |

## 8. Docs

| Item | Verdict | Evidence |
|---|---|---|
| Install/sign procedure | PASS | `docs/INSTALL.md` |
| Salt never committed | PASS | `tools/sign_script.py` reads it at run time; `.gitignore` |
| Mapping matches script | PASS | `docs/MAPPING.md` vs `script/LaunchpadProMK3.lua` |
| Limitations | PASS | `docs/LIMITATIONS.md` |

## 9. Phase 2 lanes (clip ops, undo/redo, track controls)

| Lane | Verdict | Evidence |
|---|---|---|
| Clip clear/duplicate | PASS (guarded) | `pressForce`, `doEdit`; `tests/test-clip-ops.lua`; `mpc.force.*` may be a no-op on non-Force hardware |
| Undo/redo shift functions | PASS | `doShiftFunction` guards; held-function release fix; `tests/test-undo-redo.lua` |
| Track volume/pan/sends | PASS | `enterAdjust`/`handleAdjustPad`/`nudgeAdjust`; `tests/test-track-controls.lua` |

## 10. Prioritized fix list

1. **Confirm the physical mapping on hardware** (probe mode): function buttons CC 1-8,
   track row CC 101-108, CC 30, top row 8 vs 9, Shift = CC 90.
2. **Device-test clip clear/duplicate** (CC 50/60): `mpc.clipMatrix.CopyClip`/`DeleteClip`
   are present in the 3.10.1 binary; confirm they work on the Live III.
3. **Track device** (CC 7) remains a stub; Q-links are a later phase.
4. **Clip edits**: quantize (CC 40), note editing on the selected clip.
5. **Stop all clips**: a dedicated button (`clipMatrix.StopAllClips`).
