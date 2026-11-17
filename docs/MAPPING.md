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
| 7 | tempo page (Shift) | tempo page: up/down change BPM, hold to accelerate |
| 8 | stop clip | swing (stub) |

Hold CC 8 and press a track button (CC 101-108) to stop that track's clips, or hold CC 8
and press a clip pad to stop the clips on that pad's track. The clip pad does not launch
while stop clip is held.

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
| 6 | tap tempo (Shift) | averages the last taps using `dev.timer.Now()` ms timestamps and sets integer `sequencer.SetBPM` |
| 7 | tempo page (Shift) | toggles the tempo page; the grid draws the BPM left-aligned as scaled 7-segment digits (a leading 1 takes 1 column, the tens and ones digits share the rest; a 2-digit BPM uses 4 columns each), coloured by position (ones green, tens yellow, hundreds cyan); up/down change BPM (hold accelerates) |
| 8 | swing (stub) | logs `swing: TODO` |

Undo/redo/metronome are guarded: a missing `commandManager` or `sequencer` logs once and
leaves the surface working.

### Volume / pan / sends menus

Press volume (CC 4), pan (CC 5) or sends (CC 6) to open a fader menu. The grid becomes
a bank of faders aligned with the clip view: each grid column is a track, each row is a
level. Press a pad in a column to set that track's value. Press volume or pan again to
exit the menu; tapping sends cycles send 1-4.

Volume uses clean dB steps, bottom (row 7) to top (row 0):

| Row | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| Volume | -inf | -30 dB | -20 dB | -9 dB | -3 dB | 0 dB | +3 dB | +6 dB |

Pan and sends use `(8 - row) / 8` (0..1).

| Action | Effect |
|---|---|
| Grid pad in column `c`, row `r` | Sets global track `c`'s value (volume: the dB step for `r`) |
| Double-tap the bottom pad | Sets the true minimum (0.0) for pan/sends |
| Up (CC 80) | Nudges the last touched track's value one step up |
| Down (CC 70) | Nudges the last touched track's value one step down |
| Tap sends (CC 6) while the sends menu is open | Cycles send 1-4 |

Volume writes `mpc.tracks.normalTracks[i].VolumeDB.value` (dB) and falls back to
`.Volume.value` if `VolumeDB` is read-only. The fallback inverts the measured MPC fader
curve `dB = 40*log10(gain) + 6` (so 0 dB = gain 0.708, +6 dB = gain 1.0, -inf = gain 0).
Pan writes `.Pan.value` (0..1, 0.5 = centre). Sends write `.Send1`..`.Send4.value` (0..1).
The faders are cyan (volume), magenta (pan) and one colour per send
(yellow/green/blue/orange); the active function button is white.

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
| 50 | duplicate/double | hold duplicate, press the origin clip pad, then one or more target clip pads (`clipMatrix.CopyClip`) |
| 60 | clear | hold clear, press one or more clip pads (`clipMatrix.DeleteClip`) |
| 70 | down | window down (`MoveDown`); Shift = 8 |
| 80 | up | window up (`MoveUp`); Shift = 8 |

CC 50/60 use `mpc.clipMatrix.CopyClip(fromColumn, fromRow, toColumn, toRow)` and
`mpc.clipMatrix.DeleteClip(column, row)`. Both are **hold-to-arm**: the op is active only
while CC 50/60 is held and is disarmed on release. Hold CC 50, press the origin clip pad,
then press any number of target pads — the origin stays fixed so one source can be copied
to many targets. Hold CC 60 and press each clip pad to clear it. Clip ops use the **global**
matrix position (`aperture.ToGlobalColumn/ToGlobalRow`), the same coordinates as
`HasClip`/`TriggerClip`, so they stay correct when the window is scrolled. The calls are
guarded: if the API is missing the script logs the attempted call and leaves the surface
working.

## LED feedback

- Grid: clip colour, dim when stopped, bright when playing/recording, blink when queued.
- Scene buttons: green when the row plays, blink when queued, dim otherwise.
- Track row (CC 101-108): the held function's state per track (mute = orange, solo = yellow, rec arm = red) or the track colour.
- Volume/pan/sends menu: every track column is a value bar (cyan volume, magenta pan, one colour per send: yellow/green/blue/orange), filled from the bottom. Columns beyond `SizeNormalTracks` (empty tracks) stay dark.
- Function buttons (CC 1-8): three states — off when the function is unavailable, a lighter grey when available, white when held/selected.
- Top row: current mode white, others dim; Shift white while held.
- Left column: play green while playing, record red while recording; duplicate/clear white while available; up/down white while available and take the page colour while a fader menu is open (cyan volume, magenta pan, send colour). Fixed length and quantize are stubs and stay off.
- Right column: current mode white, others dim; logo cyan in probe mode.

LEDs are sent as LPP3 sysex `F0 00 20 29 02 0E 03 <spec>... F7` (RGB type 3, 0-127),
cached per index, one message per paint cycle.

## Open questions (resolve on hardware)

1. Function buttons CC 1-8: confirm the physical row (the user says 1-8).
2. CC 30 (fixed length): absent from the learn artifact; does the unit emit it?
3. Top row: 8 or 9 buttons (CC 90 = Shift vs an extra mode button).
4. Shift = CC 90: confirm by pressing.
5. LPP3 mode: the script enters Programmer mode automatically (layout query + select 0x11) and restores the prior layout on unload; device-verified 2026-11-17.
