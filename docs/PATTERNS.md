# PATTERNS — reusable MPC controller-script patterns

Extracted from three proven scripts. Reuse the **logic**, not the wire format
(see [Wire formats](#wire-formats-dont-copy) at the end).

Source abbreviations used below:

| Ref | File |
|-----|------|
| `APC` | `references/mpc_tools/controllers/APC Mini mk2/apcMiniMk2.lua` (463 lines) |
| `NANO` | `references/KorgNanoKontrolMk1_4_AkaiForce/Devices/Korg/nanoKontrol.lua` (527 lines) |
| `FL` | the ForceLink example in the mpc-controllers checkout (see CONTRIBUTING.md) (1422 lines) |

---

## 1. Clip grid

### Aperture acquisition (FL:1369–1372, APC:146)

The per-device clip-matrix aperture lives in several places depending on firmware
version — probe all of them in `OnLoad`, never at file top level:

```lua
-- FL OnLoad
aperture   = dev.clipMatrixAperture or (mpc.clipMatrix and mpc.clipMatrix.clipMatrixAperture)
clipProps  = (aperture and aperture.clipProperties) or dev.clipProperties or
             (mpc.clipMatrix and mpc.clipMatrix.clipProperties)
```

```lua
-- APC (device table member; MPC exposes the table named after the script file)
local function aperture() return apcMiniMk2.clipMatrixAperture; end
```

### Size / window setup (APC:435–444, FL:1378–1383)

```lua
local a = aperture();
a.SetColumns(8);
a.SetRows(8);
a.SetFollowsTUI(false);          -- our own window, not the screen's (FL guards with pcall)
a.SetFollowsTUIActiveMatrix(false);
a.ActiveMatrix.value = "Normal"; -- keep normal-track indexing aligned with columns
a.SetLabel("APC mini mk2");
a.MoveToColumn(0);
a.MoveToRow(0);
a.Show();                        -- wrap in try()/pcall; Hide() at teardown
```

### Trigger / stop / select (APC:344–361, FL:99–104)

```lua
-- APC pad press: select always (so MPC edit views follow), launch only without Shift
a.SelectClip(col, row);                      -- always, as the stock MPK script does
if not shiftHeld then a.TriggerClip(col, row); end   -- shift + pad: select only

-- scene row: launch the whole row; stop variant for the stop-row buttons
a.TriggerRow(row);

-- lower-row / column functions (FL)
aperture.StopClipsOnTrack(col)               -- stop every clip on window column `col`
mpc.clipMatrix.SelectTrack(idx)              -- make global column idx MPC's current track
```

### Window scrolling (APC:335–339)

```lua
-- Move the window by one row or column. At the edge of the matrix they do nothing.
local function page(dir)
  local a = aperture();
  if dir == "left" then a.MoveLeft(1); elseif dir == "right" then a.MoveRight(1);
  elseif dir == "up" then a.MoveUp(1); elseif dir == "down" then a.MoveDown(1); end
  refreshAll();
end
```

`MoveToColumn(0)` / `MoveToRow(0)` reset to the matrix origin (APC:442–443).
Can-move queries for LED arrows: `aperture.CanMoveUp/Down/Left/Right` (FL:736–737).

### Local <-> global coordinates (FL:90–100, APC:216, APC:142–143)

```lua
-- FL: ToGlobal* with polling fallback (OriginX/Y are UNVERIFIED as listenable)
local function globalPos(col, row)
    if aperture and aperture.ToGlobalColumn then
        local ok1, gc = pcall(aperture.ToGlobalColumn, col)
        local ok2, gr = pcall(aperture.ToGlobalRow, row)
        if ok1 and ok2 then return gc, gr end
    end
    return col + (originCol or 0), row + (originRow or 0)
end
-- origin getters differ per firmware; try each in a timer until one returns a number (FL:1236–1246):
for _, n in ipairs({"GetOriginX", "GetColumn", "GetX"}) do ... end   -- same for Y: GetOriginY/GetRow/GetY
```

```lua
-- APC: local column of a global normal-track index, for faders
local global = aperture().ToLocalColumn(index);
```

Note the row-direction trap (APC:142): **hardware pad rows count from the bottom,
aperture rows from the top**:

```lua
local function padNote(col, apertureRow) return col + (rows - 1 - apertureRow) * cols; end
local function padPosition(note) return note % cols, rows - 1 - note // cols; end
```

### Origin getters

`aperture.OriginX` / `OriginY` were attempted as listenable properties (APC:291–292,
marked UNVERIFIED); the reliable path is re-reading after each scroll plus the polling
getter chain above. APC listens to them anyway inside `try()` so a working firmware
gets push updates; FL falls back to a timer poll.

---

## 2. Colours

### Colour + state sources (APC:166, FL:813–814)

Per-clip properties hang off the aperture (see §1 acquisition):

```lua
local function clip(col, row) return aperture().clipProperties[col][row]; end
-- c.Colour.value = 0x00RRGGBB argb number; c.State.value = clip-state enum
```

Fallback when `clipProperties` is missing: `mpc.clipMatrix.GetClipColour(gc, gr)` (FL:143).

### Clip state enum (APC:41–44)

```lua
-- Clip states (order confirmed by the stock MPK script and mpc-3-ce's Gen1 enum).
local S = { NoSlot = 0, Empty = 1, Ready = 2, WillPlay = 3, Playing = 4, WillStopPlaying = 5,
            WillRecord = 6, Recording = 7, WillStopRecording = 8,
            WillOverdub = 9, Overdubbing = 10, WillStopOverdubbing = 11 };
```

FL (line 124) could **not** decode per-clip State on its firmware and instead derived a
4-way status from the global matrix — keep this fallback in mind:

```lua
-- FL:125–137: 0 = no clip, 1 = stopped, 2 = playing/recording, 3 = queued (neither)
local ok, has = pcall(m.HasClip, gc, gr)
if m.ClipIsPlaying(gc, gr) or m.ClipIsRecording(gc, gr) then return 2 end
if m.ClipIsStopped(gc, gr) then return 1 end
return 3
```

Scene rows reuse the same enum: `aperture().sceneProperties[row].State` covers the whole
scene including tracks outside the window (APC:241–249).

### argb decode (FL:73–77)

```lua
local function argb(c)
    c = c or 0
    return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256  -- r, g, b
end
```

### Dim / bright / blink (FL:79, FL:144; APC:40)

```lua
local FULL, DIM = 0.8, 0.15   -- playing / stopped clip brightness
-- status 2 = playing -> FULL, 1 = stopped -> DIM, 3 = queued -> blink (toggled in the timer)
local k = status == 2 and FULL or status == 1 and DIM or (blinkOn and FULL or DIM)
r, g, b = cr * k, cg * k, cb * k
```

`blinkOn` flips every timer tick (`HandleTimer`, FL:1213); APC instead uses hardware
behaviour channels: `L = { solid = 6, pulse4th = 9, blink16th = 12, blink8th = 13 }`
(APC:40) — blink/pulse carried in the MIDI channel, velocity = colour.

### Nearest-palette mapping (APC:48–57, 80–102)

Two-level lookup: exact table of the MPC's 27 clip/track colours -> palette velocity
(`mpcColourVelocity`, taken from Akai's own mpkMiniMkIV.lua), then a cached nearest-hue
search over the device palette for anything else:

```lua
local velocity = mpcColourVelocity[rgb];
if velocity then return L.solid, velocity; end
velocity = nearestPaletteVelocity(rgb);
```

```lua
-- nearestPaletteVelocity: scale so the brightest component is FF (brightness isn't readable
-- on pads), skip dark palette entries (top < 0x50), distance = 2:4:3 weighted squared RGB.
local best, bestDistance = 3, nil;   -- white, if nothing qualifies
for velocity = 1, 127 do
  local pr, pg, pb = (p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF;
  if math.max(pr, pg, pb) >= 0x50 then
    local d = 2 * (r - pr) ^ 2 + 4 * (g - pg) ^ 2 + 3 * (b - pb) ^ 2;
    if bestDistance == nil or d < bestDistance then best, bestDistance = velocity, d; end
  end
end
```

Log an unknown colour only the first time (`unknownColoursLogged[rgb]`, APC:66–69).
A "ready" clip with colour 0 must show white, never look empty (APC:64–66).
Track colours: `mpc.tracks.normalTracks[gi].Colour.value` -> argb; zero -> grey
(FL:711–714). Selected-pad fallback: pad's own `Colour.value` when computed colour is
black (FL:362, 536).
