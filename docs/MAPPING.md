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

Hold a function button (CC 1-3, 7-8), then press a track button (CC 101-108) to apply
that function to that track. Without a held function, a track button selects the track.
Volume, pan and sends (CC 4-6) are menus, not holds: press the button to enter the menu
and press it again to exit.

| CC | Function | Shift |
|---|---|---|
| 1 | record arm | undo |
| 2 | mute | redo |
| 3 | solo | click/metronome |
| 4 | volume menu | — |
| 5 | pan menu | — |
| 6 | sends menu | tap again to cycle send 1-4 |
| 7 | device (stub) | tempo (stub) |
| 8 | stop clip | swing (stub) |

Track row CC 101-108: track 0 = CC 101, ..., track 7 = CC 108. The track index follows
the grid window: after scrolling right by one, CC 101 controls the track now in the first
grid column (global track 1), not global track 0. The track buttons show the held
function's state (mute = orange, solo = yellow, rec arm = red) or the track colour.

## Shift functions (Shift + CC 1-8)

Shift is CC 90. While Shift is held, the function buttons (CC 1-8) run the shift
function instead of holding a track function. Shift is checked before the held-function
state, so a shift function works even while another function button is held; the held
function is preserved (releasing the shift-function button does not clear it).

| Shift + CC | Action | MPC call |
|---|---|---|
| 1 | undo | `commandManager.Undo()` |
| 2 | redo | `commandManager.Redo()` |
| 3 | click/metronome | `sequencer.SetMetronomeEnabled(not MetronomeEnabled)` |
| 4 | — | — |
| 5 | — | — |
| 6 | tap tempo (stub) | logs `tap tempo: TODO` |
| 7 | tempo (stub) | logs `tempo: TODO` |
| 8 | swing (stub) | logs `swing: TODO` |

Undo/redo/metronome are guarded: a missing `commandManager` or `sequencer` logs once and
leaves the surface working.

### Volume / pan / sends menus

Press volume (CC 4), pan (CC 5) or sends (CC 6) to open a fader menu. The grid becomes
a bank of faders aligned with the clip view: each grid column is a track, each row is a
level. The fader fills from the bottom (row 7 = 0.0) to the top (row 0 = 1.0). Press a
pad in a column to set that track's value to `(8 - row) / 8`. Press volume or pan again
to exit the menu; tapping sends cycles send 1-4.

| Action | Effect |
|---|---|
| Grid pad in column `c`, row `r` | Sets global track `c`'s value to `(8 - r) / 8` |
| Double-tap the bottom pad | Sets the true minimum (0.0) |
| Up (CC 80) | Nudges the last touched track's value by +1/8, clamped to 0..1 |
| Down (CC 70) | Nudges the last touched track's value by -1/8, clamped to 0..1 |
| Tap sends (CC 6) while the sends menu is open | Cycles send 1-4 |

Volume and pan write `mpc.tracks.normalTracks[i].Volume.value` / `.Pan.value` (0..1,
pan 0.5 = centre). Sends write `.Send1`..`.Send4.value` (0..1). The faders are cyan
(volume), magenta (pan) and yellow (sends); the active function button is white.

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
| 50 | duplicate/double | arm duplicate, press the origin clip pad, then the target clip pad (`clipMatrix.CopyClip`) |
| 60 | clear | arm clear, press the clip pad (`clipMatrix.DeleteClip`) |
| 70 | down | window down (`MoveDown`); Shift = 8 |
| 80 | up | window up (`MoveUp`); Shift = 8 |

CC 50/60 use `mpc.clipMatrix.CopyClip(fromColumn, fromRow, toColumn, toRow)` and
`mpc.clipMatrix.DeleteClip(column, row)`. Press CC 50 to arm duplicate, press the origin
clip pad, then the target clip pad. Press CC 60 to arm clear, then press the clip pad.
The op stays armed after each clip, so you can clear or duplicate several clips while
holding the button; duplicate resets the origin after each copy. The API row is
`7 - visual row` (the API counts from the bottom). The calls are guarded: if the API is
missing the script logs the attempted call and leaves the surface working.

## LED feedback

- Grid: clip colour, dim when stopped, bright when playing/recording, blink when queued.
- Scene buttons: green when the row plays, blink when queued, dim otherwise.
- Track row (CC 101-108): the held function's state per track (mute = orange, solo = yellow, rec arm = red) or the track colour.
- Volume/pan/sends menu: every track column is a value bar (cyan volume, magenta pan, yellow sends), filled from the bottom.
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
