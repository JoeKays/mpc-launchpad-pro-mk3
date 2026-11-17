# Device test plan

Target: MPC 3.10.1.8 (build 38fdde70994), MPC Live III Gen2, Launchpad Pro MK3 in
Programmer mode.

Capture the journal while testing:

```sh
journalctl -u acvs -o cat --no-pager | grep LaunchpadProMK3
```

## 0. Load

1. Copy `LaunchpadProMK3.ini` + `LaunchpadProMK3.lua` to
   `/nvme/MPC Documents/Devices/LaunchpadProMK3/`.
2. Restart MPC (or reload the device list).
3. Expect: `aperture ok`, `clipProperties ok`, `loaded`.
4. The LPP3 surface should light: grid colours, scene row dim, track row dim, function
   buttons dim, top row mode buttons, left column transport.

## 1. Probe mode (verify the physical mapping)

1. Hold Shift (CC 90) and press the Novation logo (CC 99).
2. Expect: `probe mode true`; the logo lights cyan.
3. Press every pad and button once. Each press logs
   `PROBE note=.. cc=.. value=..` and lights the pressed control white.
4. Compare the log to `docs/MAPPING.md`. This resolves the open questions:
   - function buttons CC 1-8 vs track row CC 101-108
   - CC 30 existence
   - top row 8 vs 9 buttons
   - Shift = CC 90
5. Shift + logo again to exit probe mode.

## 2. Clip grid

1. Press the bottom-left pad (note 11). Expect `TriggerClip(0,7)` — the bottom row, not the top.
2. Press the top-left pad (note 81). Expect `TriggerClip(0,0)` — the top row.
3. Press a pad with no clip. Expect no launch (or MPC's empty-slot behaviour).
4. Shift + pad. Expect `SelectClip(col,7-padRow)` and no launch.
5. Watch the grid colours: stopped = dim, playing = bright, queued = blink.

## 3. Scene launch

1. Press right-column CC 89 (top). Expect `TriggerRow(0)` and the top scene launches.
2. Press right-column CC 19 (bottom). Expect `TriggerRow(7)` and the bottom scene launches.
3. Shift + CC 89/79/69. Expect `mode -> clip` / `mode -> step` / `mode -> track`.
4. Watch the scene button colour: green when playing, blink when queued.

## 4. Window scrolling

1. Press 91/92. Expect `MoveLeft(1)` / `MoveRight(1)` and the grid window moves.
2. Press 80/70. Expect `MoveUp(1)` / `MoveDown(1)`.
3. Shift + 91/92/80/70. Expect the move by 8.

## 5. Track functions

1. Hold CC 1 (record arm), press CC 101 (track 0). Expect `hold recArm`, then
   `SetRecArm(true) track 0`.
2. Hold CC 2 (mute), press CC 102 (track 1). Expect `hold mute`, then `SetMute(true) track 1`.
3. Hold CC 3 (solo), press CC 103 (track 2). Expect `hold solo`, then `SetSolo(true) track 2`.
4. Hold CC 8 (stop clip), press CC 104 (track 3). Expect `hold stopClip`, then
   `StopClipsOnTrack(3)`.
5. Press CC 101 without a held function. Expect `SelectTrack(0)`.
6. Shift + CC 1/2. Expect `Undo` / `Redo`.
7. Shift + CC 3. Expect `Metronome true/false`.
8. Scroll right (92), then hold CC 2 (mute) + press CC 101. Expect `SetMute(...) track 1`
   (the track now in the first grid column), not track 0.

## 5b. Track volume / pan / sends

1. Hold CC 4 (volume), press CC 101 (track 0). Expect `SelectTrack(0)` and
   `adjust volume track 0`. Release CC 4.
2. Press the bottom-left pad (note 11). Expect `Volume track 0 = 1.000`.
3. Press the top-left pad (note 81). Expect `Volume track 0 = 0.000`.
4. Press CC 80 (up). Expect `Volume track 0 = 0.125`; CC 70 (down) returns to 0.
5. Hold CC 5 (pan), press CC 102 (track 1). Press the pad in column 1, row 4
   (note 42). Expect `Pan track 1 = 0.571`.
6. Hold CC 6 (sends), press CC 103 (track 2). Press the pad in column 0, row 7
   (note 11). Expect `send 1`, `Sends1 track 2 = 1.000`.
7. Press the pad in column 1, row 3 (note 52). Expect `send 2`,
   `Sends2 track 2 = 0.429`.
8. Shift + CC 6. Expect `send 3`. Press the pad in column 2, row 7 (note 13).
   Expect `Sends3 track 2 = 1.000`.
9. Press CC 101 without a held function. Expect `adjust off` and `SelectTrack(0)`.

## 6. Transport

1. Press 20. Expect `Play` and MPC plays; the play button lights green.
2. Press 10. Expect `Record` and MPC records; the record button lights red.
3. Press 20 again. Expect `Stop` and MPC stops (the script checks `IsPlaying`).

## 7. Teardown

1. Remove the script folder and restart MPC.
2. Expect `unloaded` and the LPP3 surface dark.
3. The MPC project is untouched.

## 8. Degrade checks

1. If the aperture is missing (e.g. a different firmware), expect
   `aperture MISSING: clip surface disabled` and the script still loads.
2. Transport and track row/function buttons should still work.

## Expected journal lines

```
LaunchpadProMK3: aperture ok
LaunchpadProMK3: clipProperties ok
LaunchpadProMK3: loaded
LaunchpadProMK3: TriggerClip(0,7)
LaunchpadProMK3: TriggerRow(0)
LaunchpadProMK3: hold recArm
LaunchpadProMK3: SetRecArm(true) track 0
LaunchpadProMK3: hold mute
LaunchpadProMK3: SetMute(true) track 1
LaunchpadProMK3: hold solo
LaunchpadProMK3: SetSolo(true) track 2
LaunchpadProMK3: hold stopClip
LaunchpadProMK3: StopClipsOnTrack(3)
LaunchpadProMK3: SelectTrack(0)
LaunchpadProMK3: adjust volume track 0
LaunchpadProMK3: Volume track 0 = 1.000
LaunchpadProMK3: Play
LaunchpadProMK3: Stop
LaunchpadProMK3: Record
LaunchpadProMK3: Undo
LaunchpadProMK3: Redo
LaunchpadProMK3: unloaded
```
