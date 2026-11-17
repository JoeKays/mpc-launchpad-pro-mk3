# MPC 3.10.1 Lua Controller-Script API Contract (Launchpad Pro MK3)

Target: MPC 3.10.1.8 (build 38fdde70994), MPC Live III. Every claim carries a citation.
Citation keys:
- **FL.lua** = the ForceLink example in the mpc-controllers checkout (see CONTRIBUTING.md) (worked example, device-verified on 3.10.0.49; 3.10.1 items where noted)
- **APC** = `references/mpc_tools/controllers/APC Mini mk2/apcMiniMk2.lua` (full 8x8 clip launcher; same API, device-run)
- **NK** = `references/KorgNanoKontrolMk1_4_AkaiForce/Devices/Korg/nanoKontrol.lua` (track volume/pan/mute/solo/transport)
- **FINDINGS** = the mpc-controllers findings doc (see CONTRIBUTING.md)
- **CAPS / LIMS** = the mpc-controllers capabilities/limitations docs (see CONTRIBUTING.md)
- **GOLDEN** = `modules/ctrl-ce/port/midi/tests/learn-golden-lpp3.h` (LPP3 learn artifact)

Unless marked **[3.10.1]**, verified on device at 3.10.0.49; FINDINGS 30 confirms the same script API/signing on 3.10.1.8.

## 0. Script skeleton & loading

- Pair `.ini` + `.lua`; `.ini` must start with an `[info]` line and holds `input=`/`output=` port-name matches (order = port index used by `midiOut.Send*`), `script=`, `checksum=`. Search dirs: `/usr/share/Akai/SME0/Devices` and `<user root>/MPC Documents/Devices` (Live III: `/nvme/MPC Documents/Devices/...`). (FINDINGS §1, §18)
- `checksum = sha256(lua_bytes || 36-char salt)`; salt read only from the owner's own MPC binary, never committed. Checksum skipped when hardware product code is 0. (FINDINGS §1; FINDINGS 30 — same salt valid on 3.10.1.8)
- Lua 5.4 (sol2). Device table named after the file (`local dev = <Name>`); MPC calls `<Name>.OnLoad`, `.OnUnload`, `.HandleMIDINoteOn(channel, note, velocity)`, `.HandleMIDINoteOff`, `.HandleMIDICC(channel, cc, value)`, `.HandleMIDISysex(bytes)`, `.HandleTimer`. (FL.lua:1216-1252, 1330-1422; APC:377-463)
- `print()` → MPC stdout / `journalctl -u acvs`. (FINDINGS §18)
- Input routing: only notes/CCs registered via `mappings.script.AddNoteToScript(channel, note)` / `AddCCToScript(channel, cc)` reach the handlers; unregister with `Remove*` at unload. (APC:170-184, 386-394; NK:429-470)
- Sysex to script needs `mappings.script.SetHandleSysex(true)`. (FL.lua:1141)

## 1. clipMatrixAperture (per-device 8x8 window)

Acquired as `dev.clipMatrixAperture` (fallbacks: `mpc.clipMatrix.clipMatrixAperture`). Members (FL.lua:1136-1140, 1421; FINDINGS §18; APC:22-31):

| Call / property | Signature | Notes |
|---|---|---|
| `SetColumns(n)` / `SetRows(n)` | fn, ≤16 | 8 for this script. FL.lua:1137-1138 |
| `TriggerClip(col, row)` | fn | local window coords, launches clip. FL.lua:1207 |
| `TriggerRow(row)` | fn | scene launch. FL.lua:1234 |
| `StopClipsOnTrack(col)` | fn | stops that window column. FL.lua:55 |
| `SelectClip(col, row)` | fn | select (moves MPC's selection/edit views). APC:424 |
| `SelectTrack(col)` | fn | **moves MPC's current track** (global column); no separate controller track (FINDINGS 33). FL.lua:1219-1222 |
| `MoveToColumn(c)` / `MoveToRow(r)` | fn | APC:437-438 |
| `MoveUp/Down/Left/Right(n)` | fn | window scroll. FL.lua:1040-1048 |
| `CanMoveUp/Down/Left/Right` | listenable property, `.value` bool | FL.lua:927-931 |
| `Show()` / `Hide()` | fn | draws/hides labelled box on MPC screen. FL.lua:1139, 1420 |
| `SetLabel(str)` | fn | FL.lua:1139 |
| `SetFollowsTUI(bool)` / `SetFollowsTUIActiveMatrix(bool)` | fn | detach from screen's window. FL.lua:1140; APC:435-436 |
| `ActiveMatrix.value = "Normal"` | property | APC:437 |
| `ToGlobalColumn(col)` / `ToGlobalRow(row)` / `ToLocalColumn(i)` / `ToLocalRow(i)` | fn → number | window↔global. FL.lua:67-71; APC:243 |
| `GetOriginX()` / `GetOriginY()` (also tried `GetColumn/GetX`, `GetRow/GetY`) | fn → number | **firmware-specific which getter exists**; probe in OnLoad (FL.lua:1364-1373). `OriginX`/`OriginY` may be listenable (APC:290-293, UNVERIFIED as listeners) |
| `clipProperties[col][row]` | property table | see below. FL.lua:1142-1143 |
| `sceneProperties[row].State` | listenable `.value` (clip-state enum) | covers whole scene row incl. columns outside the window. APC:267-277 |
| `trackProperties` | present on the aperture | FINDINGS §18 (structure unmapped; not needed for phase 1) |

Nil/absent behaviour: acquire with fallback chain, guard everything in `pcall`; a missing aperture means no clip surface, not a crash.

## 2. clipProperties[c][r]

- `clipProperties[col][row].Colour` — listenable property; number, 0x00RRGGBB-style ARGB (read via `.value`; decode with `argb()` shifting, FL.lua:59-62, 150).
- `clipProperties[col][row].State` — listenable property; number, clip-state enum (§3). FL.lua:470-474.
- `clipProperties[col][row].Selected` — listed in capability table (CAPS row 1); presence assumed, treat as optional.
- Listener pattern: `prop:listen(fn, deviceName)` / `prop:stopListening(deviceName)`; re-register on every OnLoad (they don't survive reload and moving the window rebinds globals). FL.lua:468-478; APC:280-300.

## 3. Clip-state enum (authoritative)

Order confirmed by APC (states referenced at APC:212-233) and the mpc-3-ce Gen1 enum:

```
0 NoSlot, 1 Empty, 2 Ready, 3 WillPlay, 4 Playing, 5 WillStopPlaying,
6 WillRecord, 7 Recording, 8 WillStopRecording,
9 WillOverdub, 10 Overdubbing, 11 WillStopOverdubbing
```
(Note FL.lua's `stateName` table guesses a different shorter enum at FL.lua:64-68 — superseded by the APC/Gen1 ordering; APC was device-run.)

## 4. mpc.clipMatrix (global matrix, read + actions)

Members seen in logs (FL.lua:511-513 report walk; FINDINGS §18):
- `HasClip(col, row)` → bool. FL.lua:141
- `ClipIsPlaying(col, row)`, `ClipIsRecording(col, row)`, `ClipIsStopped(col, row)` → bool. FL.lua:143-146
- `GetClipColour(col, row)` → colour number. FL.lua:150
- `GetColumns()` → number (track count). FL.lua:922
- `TriggerClip`, `StopTrackClips`, `StopAllClips`, `CreateClip(col, row)`, `GetSelectedClipColumn()`, `GetSelectedClipRow()`, `SelectClip`. FL.lua:511-513, 552-561, 1184
- `selectedClip.events` — `GetSize()` and create/move/delete only; **no indexing/iteration** (FINDINGS 18/25; not needed for clip-launch phases).
- Coordinates here are **global** matrix coords; combine with aperture `ToGlobalColumn/Row`.

## 5. mpc.tracks

- `mpc.tracks.normalTracks` — table indexed 0..N-1 (128 slots allocated whatever the project holds; guard with `.Count.value`, NK:89-94, APC:240-248). **Index = global clip-matrix column** (FINDINGS 30/33).
- Per-track object members: `Colour` (number, listenable), `Name` (string, listenable), `Mute` (bool prop), `Solo` (bool prop), `RecArm` (bool prop), `Pan` (0..1, 0.5 centre), `Volume` (0..1), `Send1-4`, `Type` (string, e.g. "Drum") — read/write via `.value`; setters `SetMute(bool)`, `SetSolo(bool)`, `SetRecArm(bool)`. (FL.lua:44-58 trk(); NK:171-206; CAPS; FINDINGS 33)
- `mpc.tracks.currentTrack` — has `Index` (number prop; counts normal tracks first, then master), `Name`, `Type`. APC:240-253; FL.lua:1290-1296.
- `mpc.tracks.GetCount()` → number. FL.lua:1305.
- **DO NOT USE**: `mpc.tracks.GetMute/SetMute/GetSolo/GetTrackRecordArmed/GetTrackInputPort/GetTrackInputChannel/GetTrackMonitorState` — registered on `mpc.tracks` but **error when called** in any form (`(self,i)`, `(i)`, `(i+1)`); use `normalTracks[i].<Prop>.value` / setters instead. (FINDINGS 30, 33; NK:135-155; FL.lua:1329-1336)

## 6. mpc.sequencer (transport)

- `Play()` / `TogglePlay()` / `Stop()` / `Record()` — FL.lua:1244-1247; NK:395-397; FINDINGS 30.
- `IsPlaying()` → bool (fn). FL.lua:577.
- `Playing` — listenable bool property. FL.lua:1396-1397.
- `RecordState`, `OverdubState` — listenable props. FL.lua:1399-1402.
- `PlayheadPosition()` → ticks (global sequence time, 960 PPQ; NOT clip-relative). FL.lua:544; FINDINGS 28.
- `GetTCPeriod()` → 240 (1/16 at 960 PPQ; bar = 3840). FL.lua:1304; FINDINGS 18.
- `GetEndOrLoop()` → ticks. FL.lua:549.
- `JumpToPulse(ticks)` — seek. FL.lua:1189; NK:400.
- `SetMetronomeEnabled(bool)` (+ `MetronomeEnabled` prop). FL.lua:1250-1251; FINDINGS 30.
- `MetronomeEnabled`/`Playing` etc.: read `.value`; guard with `pcall`.

## 7. commandManager

`mpc.commandManager.Undo()` / `.Redo()`. FL.lua:1249; NK:399; FINDINGS 30.

## 8. mpc.force.<name> (virtual Force buttons)

One control per Force button: `arp assignA assignB clip clipStop copy crossfader cursor* dataDial dec inc delete edit launch load master matrix menu mixer mute navigate note pads qlink(s) recArm rowLaunch1-8 save select shift solo stepSeq stop stopAll tap trackAssign1-8 trackSelect1-8 undo`. Each has `Press()`, `Release()`, `Hold()`, `DoublePress()`, `Help()`. (FINDINGS 30; FL.lua:38-44, 56-64, 1253-1256; NK:157-166.)
**[Firmware-specific]** No LED/light state for these from MPC (FINDINGS 30, LIMS) — derive lights from readable state or bright-while-held. On non-Force hardware some may be no-ops; guard every call.

## 9. mpc.controlSurface

- `pads` — 1-based indices 1-64: `Tap(idx, vel)`, `Press(idx, vel)` / `Release(idx)` (Press carries velocity; Tap may ignore it — FL.lua:718-731), `IsPressedVirtual`, `LightRGBColor(idx)` → hex string, `LightBrightness(idx)`, `Colour` per-pad property, `CurrentBank` prop, `LastHitPad()` (1-based, base confirmed empirically FL.lua:803-809), `EnsurePadVisible`. Mapping fns live under `dev.mappings.pads`: `AddNoteToMpcPad(ch,note,pad≤15)`, `AddNoteToForcePad(≤63)`, `AddNoteToVirtualPad(ch,note,pad≤127)`, `Remove*`, `Is*Mapped`. (FINDINGS 20, 18; FL.lua:632-668, 1392.)
- `qlinks` — `GetNumQLinks()`; `qlinks[i]` (0-based) with `TargetName` (str prop, listenable), `ValueString` (str prop, listenable), `GetPosition()` (0-127 **but lags one change**), `SetPosition`, `IsTouched`, `Rotate(delta)` (wraps at ends; cap steps). Mapping via `dev.mappings.controlSurface.qlinks` or `dev.mappings.control` : `AddInfiniteCCToQLink(ch, cc, qlink)` (cc 1-63 = cw, 64-127 = ccw), `RemoveInfiniteCCToQLink`, `SetQLinkFineAdjust(bool)`. Bank changes update all 16 at once (FINDINGS 26). **NOT in phase 1.**
- `stepSequencer` — `Tap/Press/Release/IsPressed/LightRGBColour/LightBrightness/GetCurrentMode/Help` (FL.lua:1145-1154; FINDINGS 18). Later phases.
- `padPerform` / `keyboardControl` — only the two hardware buttons; **scale/root invisible** (FINDINGS 29).

## 10. midiOut / input mapping

`dev.midiOut.SendMIDINoteOn(channel, note, velocity, outputIndex)`, `.SendMIDICC(channel, cc, value, outputIndex)`, `.SendMIDISysex(bytesWithoutF0F7, outputIndex)` (bytes exclude F0/F7 per FINDINGS §6; FL.lua sends full payloads incl. header via `string.char` — pass without framing). `outputIndex` = order of `output=` lines in the .ini (APC:19). FL.lua:87-89; APC:156-161; CAPS.

## 11. mappings (on the device table)

- `mappings.script`: `AddNoteToScript(ch, note)` / `RemoveNoteToScript`, `AddCCToScript` / `RemoveCCToScript`, `IsNoteMappedToScript`, `IsCCMappedToScript`, `SetHandleSysex(bool)`. FL.lua:1141, 1390-1396; FINDINGS 18.
- `mappings.pads`: see §9.
- `mappings.tracks`: `mutes.AddNoteToTrackMute` (FINDINGS 30) — later phase.

## 12. Misc

- `mpc.ui.ShowTUIFeedback(str)` — on-screen message. FL.lua:771, 1333; FINDINGS 18.
- `mpc.engineMode` — `RequestModeChange(name)`, `GetAvailableModes()` (table of strings, log them), `CurrentMode` (prop). Names undocumented; try candidate lists. FL.lua:1044-1056, 1280-1284; NK:276-297.
- `dev.timer.Start(ms)` / `.Stop()` — HandleTimer cadence. FL.lua:1418; APC:447.
- `popups.*` — listed in CAPS; treat optional/unguarded usage.
- `mpc.features.UseClipWorkflow.value` — gate the clip surface (APC:418-423).

## 13. Hard limits (design around, never work around in Lua)

1. **No state dump**: `#GetState` / `mpc.GetState` nil in scripts (FINDINGS 19, 25; LIMS).
2. **No per-track MIDI input**: no input port/channel/monitor on `normalTracks[i]`; the `mpc.tracks.Get*` getters error (FINDINGS 33).
3. **Cannot drive a non-current track**: `aperture.SelectTrack` moves MPC's current track; note editing only on `selectedClip` (FINDINGS 33).
4. `qlinks.GetPosition()` lags one change (FINDINGS 26) — n/a now, keep for later.
5. Q-link bank changes update all 16 at once (FINDINGS 26).
6. **No LED state for `mpc.force.*`** (FINDINGS 30).
7. Pad-perform scale/root invisible (FINDINGS 29).
8. Script cannot read sequence events (FINDINGS 18/25).

## 14. Do-not-use list (3.10.1)

| Do not use | Instead |
|---|---|
| `mpc.tracks.GetMute/SetMute/GetSolo/SetSolo/GetTrackRecordArmed/SetTrackRecordArmed` (any arg form) — **error** | `mpc.tracks.normalTracks[i].Mute.value` / `:SetMute(b)` etc. (FINDINGS 30, 33) |
| `mpc.tracks.GetTrackInputPort/Channel/MonitorState` — error (FINDINGS 33) | none from Lua |
| `#GetState`, `mpc.GetState` — nil (FINDINGS 25) | property listeners |
| `stateName` enum order from FL.lua:64-68 | §3 enum (APC/Gen1) |
| `sequence/clip events` indexing/`ipairs` | `GetSize` + create/delete only |
| `pads.Tap` for velocity-sensitive hits | `pads.Press` + timed `Release` (FL.lua:718-731) |
| aperture origin getters (build-specific) | probe `GetOriginX/GetColumn/GetX` chain at OnLoad (FL.lua:1364-1373) |

## 15. Degrade-never-break rules

- Every optional API behind `pcall` + a name check (`if f and type(f)=="function"`); log first failure per label once (APC:134-142 pattern).
- Missing clip workflow (`mpc.features.UseClipWorkflow` false) → clip surface disabled, transport still works (APC:418-423).
- Missing aperture/clipProperties → grid dark, buttons inert; transport/mute/solo/arm continue.
- OnUnload: stop listeners, remove mappings, dark all LEDs, `aperture.Hide()`; timer stopped first (APC:407-412).
