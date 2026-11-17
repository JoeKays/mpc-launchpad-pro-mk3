# Launchpad Pro MK3 Layout & Protocol (Programmer Mode)

Sources: the Novation LPP3 programmer's reference (see CONTRIBUTING.md) and the pinned learn artifact `modules/ctrl-ce/port/midi/tests/learn-golden-lpp3.h` (probe run 2026-11-06, USB 1235:0123, ALSA "Launchpad Pro MK3" port "LPProMK3 MIDI", 104 controls).

## 1. Programmer-mode layout (LPP3 doc "Programmer mode layout", p.19; GOLDEN)

- **Grid 8x8**: notes 11-88, bottom-left first. `note = 10*(row+1) + col + 1`, row 0 = bottom, col 0 = left. (GOLDEN PAD01-64; LPP3 example "lower left pad = note 11" p.11.)
- **Right column** (scene launch): CC 19,29,39,49,59,69,79,89, bottom first. (GOLDEN SCENE01-08)
- **Bottom row** (track control): CC 1-8. (GOLDEN BTN01-08)
- **Second bottom row**: CC 101-108 — track select (user-confirmed; NOT 10-80). (GOLDEN BTN101-108)
- **Left column**: CC 10,20,30,40,50,60,70,80 bottom-up. **CC 30 is absent from the learned codec** (GOLDEN has BTN10,20,40,... — no BTN30); its physical button still exists but emits nothing in this capture — resolve on hardware.
- **Top row**: CC 90-98 (Shift = CC 90, then 8 scene/mode buttons 91-98). (GOLDEN BTN90-98)

## 2. LED protocol (LPP3 doc pp.8-13)

Notes and CCs both work in Programmer mode; the device sends the indicated type on press.

| Channel (note / CC) | Behaviour |
|---|---|
| 1 (144 / 176) | static |
| 2 (145 / 177) | flashing (50% duty vs the pad's static colour, synced to MIDI clock / 120 bpm) |
| 3 (146 / 178) | pulsing (2-beat sine-ish swell) |

- Note On velocity / CC value = palette index; velocity 0 (or Note Off 80h-8Fh) = off.
- **LED sysex**: `F0 00 20 29 02 0E 03 <spec>... F7`, spec = `<type> <led-index> <data>`; types 0 = static palette (1 byte), 1 = flashing (2 bytes: colour B, colour A), 2 = pulsing (1 byte palette), 3 = RGB (3 bytes R,G,B, 0-127). Up to **106 specs per message** — use for full-surface repaints; individual notes/CCs are fine for incremental updates.
- LED indices in sysex = the same Programmer-mode indices (notes for grid, CC numbers for edge buttons).
- **Pace sysex**: burst-sending drops frames (Force capture evidence, FINDINGS 12.4 — analog behaviour, ≥3 ms/drain rule); on LPP3 unverified, but chunk updates rather than one giant burst at load.

## 3. Palette & nearest colour

The 128-entry palette (LPP3 "Colour palette" p.9; numerically the Akai/Novation family that the APC mini mk2 script encodes, `apcMiniMk2.lua:60-84`):

```lua
-- index -> 0xRRGGBB (from apcMiniMk2.lua palette table)
0x000000,0x1E1E1E,0x7F7F7F,0xFFFFFF,0xFF4C4C,0xFF0000,0x590000,0x190000,
0xFFBD6C,0xFF5400,0x591D00,0x271B00,0xFFFF4C,0xFFFF00,0x595900,0x191900,
0x88FF4C,0x54FF00,0x1D5900,0x142B00,0x4CFF4C,0x00FF00,0x005900,0x001900,
0x4CFF5E,0x00FF19,0x00590D,0x001902,0x4CFF88,0x00FF55,0x00591D,0x001F12,
0x4CFFB7,0x00FF99,0x005935,0x001912,0x4CC3FF,0x00A9FF,0x004152,0x001019,
0x4C88FF,0x0055FF,0x001D59,0x000819,0x4C4CFF,0x0000FF,0x000059,0x000019,
0x874CFF,0x5400FF,0x190064,0x0F0030,0xFF4CFF,0xFF00FF,0x590059,0x190019,
0xFF4C87,0xFF0054,0x59001D,0x220013,0xFF1500,0x993500,0x795100,0x436400,
0x033900,0x005735,0x00547F,0x0000FF,0x00454F,0x2500CC,0x7F7F7F,0x202020,
0xFF0000,0xBDFF2D,0xAFED06,0x64FF09,0x108B00,0x00FF87,0x00A9FF,0x002AFF,
0x3F00FF,0x7A00FF,0xB21A7D,0x402100,0xFF4A00,0x88E106,0x72FF15,0x00FF00,
0x3BFF26,0x59FF71,0x38FFCC,0x5B8AFF,0x3151C6,0x877FE9,0xD31DFF,0xFF005D,
0xFF7F00,0xB9B000,0x90FF00,0x835D07,0x392B00,0x144C10,0x0D5038,0x15152A,
0x16205A,0x693C1C,0xA8000A,0xDE513D,0xD86A1C,0xFFE126,0x9EE12F,0x67B50F,
0x1E1E30,0xDCFF6B,0x80FFBD,0x9A99FF,0x8E66FF,0x404040,0x757575,0xE0FFFF,
0xA00000,0x350000,0x1AD000,0x074200,0xB9B000,0x3F3100,0xB35F00,0x4B1502
```

MPC's 27 fixed track colours → palette (hand-picked by Akai for the MPK mini IV, same palette family), `apcMiniMk2.lua:51-55`; fallback nearest colour: normalise so the brightest channel is 255, skip dark entries (max < 0x50), weighted squared distance 2:4:3 (R:G:B), cache results — `nearestPaletteVelocity`, `apcMiniMk2.lua:86-105`. MPC clip colours are 0x00RRGGBB numbers from `clipProperties[c][r].Colour.value` (API-CONTRACT §2).

Alternatively use sysex type 3 (RGB 0-127) for exact clip colours: RGB = `clipColour * 127 / 255` per channel (ForceLink pattern, FL.lua:152-155).

## 4. Actual LPP3 mapping (user-supplied, authoritative)

The user supplied the physical mapping. Use these CC numbers exactly.

| Control | CC/note | Primary | Shift |
|---|---|---|---|
| Grid 8x8 | notes 11-88 (10-note blocks: 11-18, 21-28, ..., 81-88) | clip launch (`TriggerClip(col, 7-padRow)`) | select clip (`SelectClip`) |
| Track row | CC 101-108 | track select (`SelectTrack(globalPos(col,0))`) | — |
| Function buttons | CC 1-8 | 1 record arm, 2 mute, 3 solo, 4 volume, 5 pan, 6 sends, 7 device, 8 stop clip | 1 undo, 2 redo, 3 click, 6 cycle send, 7 tempo, 8 swing |
| Right column | CC 19-89, 99 | 99 novation logo; 89-19 = `TriggerRow(0..7)` (89 = top, 19 = bottom) | 89 patterns → clip mode, 79 steps → step mode, 69 pattern settings → track mode, 59/49/39/29/19 = velocity/probability/mutation/micro step/print to clip (stub) |
| Top row | CC 90-98 | 90 shift, 91 <, 92 >, 93 session, 94 note, 95 chord, 96 custom, 97 sequencer, 98 projects/save | — |
| Left column | CC 10-80 | 10 record/capture midi, 20 play/stop toggle, 30 fixed length, 40 quantize/record quantize, 50 duplicate/double, 60 clear, 70 down, 80 up | — |

MPC action mapping (phase 1 clip mode first):
- Grid: `TriggerClip(col, 7-padRow)`; Shift+pad = `SelectClip(col, 7-padRow)`. The bottom-left pad (note 11) maps to MPC row 7 (bottom); the top-left (note 81) to MPC row 0 (top).
- 91/92: window left/right (`MoveLeft/Right`); Shift = page by 8.
- 80/70: window up/down (`MoveUp/Down`); Shift = page by 8.
- 93 session: clip mode; 97 sequencer: step mode (stub); 98 projects/save: save (stub).
- 20 play: `IsPlaying` ? `Stop` : `Play`; 10 record: `Record`; 40 quantize / 50 duplicate / 60 clear: stubs.
- Track row CC 101-108: `SelectTrack(globalPos(col,0))`; hold a function button (CC 1-8) then press a track button to apply it to that track.
- Function buttons CC 1-8: record arm/mute/solo/volume/pan/sends/device/stop clip; Shift variants undo/redo/click/cycle send/tempo/swing.
- 89/79/69 (Shift): clip/step/track modes; 59/49/39/29/19 (Shift): later phases (stub).
- 99 novation logo: status/home; Shift = probe mode.
- Track volume/pan/sends: hold CC 4/5/6 + a track button, then use grid rows / up-down to adjust (see docs/MAPPING.md).
- Q-links: later phase (stub).

LED feedback (phase 1): grid = clip state per API-CONTRACT §3 — Ready = track colour solid; Playing = green pulse (ch3); WillPlay = flash (ch2); Recording = red pulse; queued states flash; Empty/NoSlot dark. Track row: the held function's state per track (mute = orange, solo = yellow, rec arm = red) or the track colour. Function buttons: the held or active menu one white, others dim; the volume/pan/sends menu paints every track column as a value bar (cyan volume, magenta pan, yellow sends), filled from the bottom. Shift: lit while held. LED cache per control; full repaint every ~2 s via timer (FL.lua:1378-1380 pattern).

## 5. Open questions (resolve on hardware, script must not assume)

1. Physical positions of CC 10-80 vs CC 101-108 rows (which printed row is which under the pads).
2. Whether CC 30 exists on this unit (absent from learn capture) and what its button does.
3. Top row: 8 or 9 buttons (CC 90 = Shift vs an extra mode button); GOLDEN shows 90-98 = 9 controls.
4. Whether Shift is CC 90 (learn capture says yes; confirm by pressing).
5. LPP3 mode management: implemented. The script queries the current layout
   (`F0 00 20 29 02 0E 00 F7`), captures the prior layout from the select-layout echo,
   enters Programmer mode (`... 00 11 00 00 F7`) on the first timer tick, and restores
   the captured layout on unload (default 0x04 Note/Drum). Device-verified 2026-11-17:
   `prior layout 0x04 page 0`, `programmer mode`.
