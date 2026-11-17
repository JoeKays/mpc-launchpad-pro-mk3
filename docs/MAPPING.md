# Mapping

The physical mapping is user-supplied and authoritative. The script uses these CC/note
numbers exactly.

## Grid (notes 11-88, bottom-left first)

`note = 10*(row+1) + col + 1`, row 0 = bottom, col 0 = left.

The LPP3's bottom-left pad (note 11) maps to MPC clip row 7 (bottom); the top-left pad
(note 81) maps to MPC clip row 0 (top). The script inverts the row so the grid is not
upside down.

| Action | MPC call |
|---|---|
| Pad press | `aperture.SelectClip(col, 7-padRow)` then `aperture.TriggerClip(col, 7-padRow)` |
| Shift + pad | `aperture.SelectClip(col, 7-padRow)` only (no launch) |

## Track row (CC 101-108) + function buttons (CC 1-8)

Hold a function button (CC 1-8), then press a track button (CC 101-108) to apply that
function to that track. Without a held function, a track button selects the track.

| CC | Function | Shift |
|---|---|---|
| 1 | record arm | undo |
| 2 | mute | redo |
| 3 | solo | click/metronome |
| 4 | volume (stub) | — |
| 5 | pan (stub) | — |
| 6 | sends (stub) | tap tempo (stub) |
| 7 | device (stub) | tempo (stub) |
| 8 | stop clip | swing (stub) |

Track row CC 101-108: track 0 = CC 101, ..., track 7 = CC 108. The track index follows
the grid window: after scrolling right by one, CC 101 controls the track now in the first
grid column (global track 1), not global track 0. The track buttons show the held
function's state (mute = orange, solo = yellow, rec arm = red) or the track colour.

## Right column (CC 19-89 + 99)

Primary = row trigger (scene launch); Shift = the label functions.

| CC | Primary | Shift |
|---|---|---|
| 99 | status/home | probe mode |
| 89 | `TriggerRow(0)` (top row) | patterns → clip mode |
| 79 | `TriggerRow(1)` | steps → step mode (stub) |
| 69 | `TriggerRow(2)` | pattern settings → track mode (stub) |
| 59 | `TriggerRow(3)` | velocity (stub) |
| 49 | `TriggerRow(4)` | probability (stub) |
| 39 | `TriggerRow(5)` | mutation (stub) |
| 29 | `TriggerRow(6)` | micro step (stub) |
| 19 | `TriggerRow(7)` (bottom row) | print to clip (stub) |

## Top row (CC 90-98)

| CC | Label | Script action |
|---|---|---|
| 90 | shift | shift modifier |
| 91 | < | window left (`MoveLeft`); Shift = 8 |
| 92 | > | window right (`MoveRight`); Shift = 8 |
| 93 | session | clip mode |
| 94 | note | note mode (stub) |
| 95 | chord | chord mode (stub) |
| 96 | custom | custom mode (stub) |
| 97 | sequencer | step mode (stub) |
| 98 | projects/save | save (stub) |

## Left column (CC 10-80)

| CC | Label | Script action |
|---|---|---|
| 10 | record/capture midi | `sequencer.Record` |
| 20 | play | `IsPlaying` ? `Stop` : `Play` |
| 30 | fixed length | stub |
| 40 | quantize/record quantize | stub (no clip-quantize API in the 3.10.1 contract) |
| 50 | duplicate/double | `mpc.force.copy.Press()`/`Release()` on the selected clip; TODO if unavailable |
| 60 | clear | `mpc.force.delete.Press()`/`Release()` on the selected clip; TODO if unavailable |
| 70 | down | window down (`MoveDown`); Shift = 8 |
| 80 | up | window up (`MoveUp`); Shift = 8 |

CC 50/60 use the virtual Force COPY/DELETE buttons (`mpc.force.copy`/`mpc.force.delete`),
which act on MPC's current selection. The 3.10.1 contract has no clip-level duplicate/clear
call. If `mpc.force` is absent (or the button lacks `Press`/`Release`), the script logs a
TODO naming the missing API and does nothing. On non-Force hardware the buttons may be
no-ops. The script only presses the buttons; the copy/paste and delete semantics are MPC's
own.

## LED feedback

- Grid: clip colour, dim when stopped, bright when playing/recording, blink when queued.
- Scene buttons: green when the row plays, blink when queued, dim otherwise.
- Track row (CC 101-108): the held function's state per track (mute = orange, solo = yellow, rec arm = red) or the track colour.
- Function buttons (CC 1-8): the held one white, others dim.
- Top row: current mode white, others dim; Shift white while held.
- Left column: play green while playing, record red while recording.
- Right column: current mode white, others dim; logo cyan in probe mode.

LEDs are sent as LPP3 sysex `F0 00 20 29 02 0E 03 <spec>... F7` (RGB type 3, 0-127),
cached per index, one message per paint cycle.

## Open questions (resolve on hardware)

1. Function buttons CC 1-8: confirm the physical row (the user says 1-8).
2. CC 30 (fixed length): absent from the learn artifact; does the unit emit it?
3. Top row: 8 or 9 buttons (CC 90 = Shift vs an extra mode button).
4. Shift = CC 90: confirm by pressing.
5. LPP3 mode: the script enters Programmer mode automatically (layout query + select 0x11) and restores the prior layout on unload; device-verified 2026-11-17.
