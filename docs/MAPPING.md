# Mapping

The physical mapping is user-supplied and authoritative. The script uses these CC/note
numbers exactly.

## Grid (notes 11-88, bottom-left first)

`note = 10*(row+1) + col + 1`, row 0 = bottom, col 0 = left.

The LPP3's bottom-left pad (note 11) maps to MPC clip row 7 (bottom); the top-left pad
(note 81) maps to MPC clip row 0 (top). The script inverts the row so the grid is not
upside down.

While the MPC pads mode is open (CC 94) the grid belongs to that
mode and clip launch is suspended (see Pad modes below).

| Action | MPC call |
|---|---|
| Pad press | `aperture.SelectClip(col, 7-padRow)` then `aperture.TriggerClip(col, 7-padRow)` |
| Shift + pad | `aperture.SelectClip(col, 7-padRow)` only (no launch) |

### Clip states + follow (live grid)

The grid reads the aperture's live clip properties (`clipProperties[col][row]` ->
`Colour`/`State`/`Selected`), so the LEDs update immediately through property listeners:
each slot listens on Colour/State/Selected and any change repaints the whole grid
(MPK-style full refresh, so blink phases stay in sync). LED semantics:

| Clip State | LED |
|---|---|
| < 2 (empty slot) | dark; dim white (60,60,60) when the slot is Selected (ring substitute) |
| 2 (stopped clip) | the clip's own colour, solid (Colour is an ARGB int, alpha ignored) |
| 3-5 (playing/queued) | green |
| >= 6 (recording) | red |

Blinking follows the MPK semantics: transitions (State 3/5/6/8/9/11) blink fast,
playing/recording/overdubbing (4/7/10) blink slow. The RGB sysex used has no blink
channel, so blink is rendered by repainting the pad dim on the timer phase: fast = 2 Hz,
slow = 1 Hz. Without `clipProperties` the grid degrades to polling `mpc.clipMatrix` on
the timer (dim stopped / bright playing / blink queued).

Follow is **optional and off by default**: Shift + CC 93 (session) toggles it
(logs `follow: on/off`). When on, a `mpc.tracks.currentTrack.Index` listener
moves the window to that track — `SetActiveMatrix("Normal")` + `MoveToColumn(index)`, or
`SetActiveMatrix("Master")` + `MoveToColumn(index - SizeNormalTracks)` for the master
track — then re-registers the slot listeners for the new window and repaints. The track
row (CC 101-108) selects MPC's current track, so pressing a track button makes the grid
follow it. Manual scrolling (91/92 left/right, 80/70 up/down) moves the window freely
and re-registers the listeners too; the next current-track change snaps the window back
to that track's column.

## Track row (CC 101-108) + function buttons (CC 1-8)

Hold a function button (CC 1-3, 8), then press a track button (CC 101-108) to apply
that function to that track. Without a held function, a track button selects the track.
Volume, pan and sends (CC 4-6) are menus, not holds: press the button to enter the menu
and press it again to exit. Device (CC 7) is not a hold either: it toggles the Q-Link page
(see below).

| CC | Function | Shift |
|---|---|---|
| 1 | record arm | undo |
| 2 | mute | redo |
| 3 | solo | click/metronome |
| 4 | volume menu | — |
| 5 | pan menu | — |
| 6 | sends menu | tap again to cycle send 1-4 |
| 7 | Q-Link page | tempo page: up/down change BPM, hold to accelerate |
| 8 | stop clip | swing page: up/down change swing, hold to accelerate |

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
| 6 | tap tempo (Shift) | native: Shift press routes CC 6 to the MPC's own Tap Tempo control (`RemoveCCToScript` + `controlSurface.AddCCToControl(0, 6, "Tap Tempo")`), Shift release routes it back to the script; when that mapping is missing it falls back to averaging the last taps using `dev.timer.Now()` ms timestamps and setting integer `sequencer.SetBPM` |
| 7 | tempo page (Shift) | Shift + CC 7 toggles the tempo page (unshifted CC 7 opens the Q-Link page instead); the grid draws the BPM left-aligned as scaled 7-segment digits (a leading 1 takes 1 column, the tens and ones digits share the rest; a 2-digit BPM uses 4 columns each), coloured by position (ones white, tens orange, hundreds blue; blue/orange/white differ in hue and luminance for colourblind accessibility); up/down change BPM (hold accelerates) |
| 8 | swing page (Shift) | toggles the swing page; the grid draws the swing % left-aligned as scaled 7-segment digits (same layout and colourblind-safe colours as the tempo page); up/down change swing by 1 (50-75, hold accelerates) |

Undo/redo/metronome are guarded: a missing `commandManager` or `sequencer` logs once and
leaves the surface working. The same guard covers the Shift transport buttons (loop,
overdub, automation filter), track navigation, plugin presets and the native
tap tempo routing (the manual averager is the fallback when the routing is missing).

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

### Swing page (Shift + CC 8)

Shift + CC 8 toggles the swing page. The grid draws the swing percentage (50-75) with the
same left-aligned 7-segment renderer and colourblind-safe colours as the tempo page. MPC
swing is percent-based: 50% is straight timing (no swing), 66% is a perfect triplet feel
and 75% is the maximum. Up
(CC 80) and down (CC 70) change swing by 1; holding accelerates (300 ms, then 150 ms,
then 50 ms). The pads are inert on this page. The swing value is read/written through
`mpc.sequencer.quantiser.GetSwing()` / `SetSwing(50-75)`; the stop-clip button (CC 8) is
white while the page is open and the up/down arrows take the swing page colour (yellow).

### Q-Link page (CC 7)

Press device (CC 7) to toggle the Q-Link page. The grid shows the MPC Q-Links
(`mpc.controlSurface.qlinks`, 16 knobs, 0-based) as cyan bottom-up faders: bank 1 =
Q-Links 0-7, bank 2 = Q-Links 8-15. Each fader reads `GetPosition()` (0-127) and lights
`round(pos / 127 * 8)` pads. The page requires `controlSurface.qlinks`; without it the
button press is logged and ignored.

| Action | Effect |
|---|---|
| Grid pad in column `c`, row `r` | Sets Q-Link `qlinkPage * 8 + c` to `floor((8 - r) / 8 * 127 + 0.5)` |
| Device (CC 7) again | Cycle: page 1 -> page 2 -> exit |
| Up (CC 80) / down (CC 70) | Switch to page 2 / page 1 (secondary) |
| Shift + up / down | Nudge the last touched column's Q-Link by ±1 |

A pad set calls `Touch()` (if present; errors ignored), then drives `Twist(target -
GetPosition())` with the delta clamped to ±127, repeated at most twice to absorb the
`GetPosition` lag, then calls `Touch()` again; the script logs `qlink N = pos (value
string)`. If a qlink object has no `Twist`, the script falls back to `SetPosition(target)`
and logs `qlink N = pos (setpos)` — `SetPosition` alone updates the Q-Link's ValueString
but does not reach the MPC edit-mode value on 3.10.1 (device-verified; see LIMITATIONS).
All 16 Q-Links are reachable at **fixed slot positions**: columns 1-4 are always
the MPC's Q-Link page 1 slots (12,8,4,0), columns 5-8 its page 2 slots (13,9,5,1) —
Launchpad page 2 shows pages 3+4 the same way. There is no compaction or sliding:
an unassigned slot keeps its column as a dark gap exactly where the MPC screen
shows it. The page-open log lists the map with `-` for gaps
(`qlink page (N assigned): 1=-, 2=High, ...`).
The column order follows the MPC's Q-Link screen, which lists the 16 slots
**column-major with each bank reversed** (its page 1 = Q-Links 12,8,4,0; page 2 =
13,9,5,1; page 3 = 14,10,6,2; page 4 = 15,11,7,3) — raw index order would interleave
and reverse the MPC's pages.
Launchpad page 1 = the first 8 assigned Q-Links in that order, page 2 = the rest;
tapping Device cycles page 1 -> page 2 -> exit (page 2 is skipped when 8 or fewer
are assigned).
Each fader keeps its MPC Q-Link bank colour — bank 1 (Q-Links 0-3) cyan, bank 2
(4-7) magenta, bank 3 (8-11) yellow, bank 4 (12-15) blue — so the grouping stays
visible after compaction.

Flip/binary parameters (two value strings across a wide position span, e.g. Kill EQ
Thru/Kill) are learned as you use them: once learned, presses round to the extremes
(bottom half of the column = min, top half = max) and the column shows a single lit
extreme pad instead of a fill, making the on/off state obvious.

Q-Links with an empty target name (unassigned in the current Q-Link mode) stay fully
dark and their pads are inert — the grid only shows faders that control something.
The page is mutually exclusive with the fader menus, the tempo page and the swing page.
The device button is white while the page is open and light grey when
`controlSurface.qlinks` (or the tempo page's `sequencer.SetBPM`) exists; Shift + CC 7
stays the tempo page.

### MPC pads mode (CC 94)

CC 94 (note) hands a block of grid pads to the MPC so the pads are hardware-routed
(the notes no longer reach the script) and mirror MPC state on their LEDs. Entering it
closes the volume/pan/sends menus, the tempo/swing pages and armed clip ops (they all
need the grid); the scene column and the track row (CC 101-108) keep working, the rest
of the grid is dark and inert. Press the mode button again, press CC 93 (session), enter
another mode or page, or unload to exit: the 16 notes return to the script and the
normal clip grid is repainted.

Pad 0-15 maps to the bottom-left 4x4 quadrant (`col = pad % 4`, `padRow = pad // 4`,
`note = 10*(padRow+1)+col+1`, so pad 0 = note 11). Each note is unbound from the script
and bound with `mappings.pads.AddNoteToMpcPad`, so the pads play the MPC's own pad bank.
The quadrant LEDs mirror `mpc.controlSurface.pads[i]` colour — read via `GetColour()`
with the `Colour.value` property as fallback (ARGB int, alpha ignored, scaled to
0-127) — polled from the script timer every 100 ms; only changed colours are sent.
The note button is white while the mode is open, lighter grey when `controlSurface.pads`
and `mappings.pads` exist, off otherwise.

CC 96 (custom) is a stub (track mutes live on the CC 2 hold-function).

If the mappings are missing the mode button stays off and pressing it changes nothing
(the surface keeps today's behaviour).

### Quantize (CC 40)

CC 40 applies quantize to the selected clip/notes by pressing the MPC's own quantize
button: `mpc.controlSurface.quantizeApply.Press()` then `Release()`. The quantize button
is white when `controlSurface.quantizeApply` exists and off otherwise. The quantize
settings themselves live on `mpc.sequencer.quantiser` (`SetEnabled`, `SetStrength`,
`SetTimeDivision`, `SetWindow`, `SetShift`, `SetSwing`).

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
| 91 | < | window left (`MoveLeft`); Shift = previous track (`currentTrack.Previous`) |
| 92 | > | window right (`MoveRight`); Shift = next track (`currentTrack.Next`) |
| 93 | session | clip mode; Shift = toggle follow-current-track (off by default). LED: cyan while follow is on |
| 94 | note | MPC pads mode: the bottom-left 4x4 quadrant mirrors the MPC pad colours and plays the MPC pads; press again to exit. Shift = previous plugin preset (`currentTrack.PrevPluginPreset`) |
| 95 | chord | chord mode (stub); Shift = next plugin preset (`currentTrack.NextPluginPreset`) |
| 96 | custom | stub (track mutes live on the CC 2 hold-function) |
| 97 | sequencer | step mode (stub) |
| 98 | projects/save | save (stub) |

## Left column (CC 10-80)

| CC | Label | Script action |
|---|---|---|
| 10 | record/capture midi | `sequencer.Record`; Shift = overdub (`sequencer.Overdub`). LED: red while recording, orange while overdubbing |
| 20 | play | `IsPlaying` ? `Stop` : `Play`; Shift = loop toggle (`sequencer.Loop.value`). LED: green while playing, orange while loop is enabled, dim when stopped |
| 30 | fixed length | stub; Shift = cycle the global automation filter (`project.AdvanceGlobalAutomationFilterType`) |
| 40 | quantize/record quantize | applies quantize via `controlSurface.quantizeApply.Press()` then `Release()` |
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

- Grid: live clip states — empty slots dark (selected = dim white), stopped clips in their own colour (solid), playing/queued green, recording red; transitions blink fast (2 Hz), playing/recording/overdubbing blink slow (1 Hz). Updates arrive through property listeners (192 slot listeners + scene/track/transport + `currentTrack.Index`); the 50 ms timer repaint stays as the fallback/degrade path.
- Scene buttons: green when the row plays, blink when queued, dim otherwise.
- Track row (CC 101-108): the held function's state per track (mute = orange, solo = yellow, rec arm = red) or the track colour.
- Volume/pan/sends menu: every track column is a value bar (cyan volume, magenta pan, one colour per send: yellow/green/blue/orange), filled from the bottom. Columns beyond `SizeNormalTracks` (empty tracks) stay dark.
- Function buttons (CC 1-8): three states — off when the function is unavailable, a lighter grey when available, white when held/selected (the device button is white while the Q-Link page or tempo page is open).
- Top row: current mode white, others dim; Shift white while held; note (CC 94) shows pad-mode availability (lighter grey, off without the mappings) and turns white while the mode is open; custom (CC 96) stays off (stub).
- Left column: play green while playing, record red while recording; duplicate/clear white while available; quantize white when `controlSurface.quantizeApply` is available; up/down white while available and take the page colour while a fader menu, tempo page, swing page or Q-Link page is open (cyan volume, magenta pan, send colour, white tempo, yellow swing, cyan Q-Link). Fixed length is a stub and stays off.
- Right column: current mode white, others dim; logo cyan in probe mode.
- MPC pads mode mirrors the MPC pad colours on the bottom-left 4x4 quadrant (diff-only, polled every 100 ms, `GetColour()` first).

LEDs are sent as LPP3 sysex `F0 00 20 29 02 0E 03 <spec>... F7` (RGB type 3, 0-127),
cached per index, one message per paint cycle.

## Open questions (resolve on hardware)

1. Function buttons CC 1-8: confirm the physical row (the user says 1-8).
2. CC 30 (fixed length): absent from the learn artifact; does the unit emit it?
3. Top row: 8 or 9 buttons (CC 90 = Shift vs an extra mode button).
4. Shift = CC 90: confirm by pressing.
5. LPP3 mode: the script enters Programmer mode automatically (layout query + select 0x11) and restores the prior layout on unload; device-verified 2026-11-17.
