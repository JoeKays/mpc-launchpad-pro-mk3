-- tests/test-track-controls.lua: volume/pan/sends adjustment mode.
package.path = "./tests/?.lua;" .. package.path
local mock = require("mock-mpc")
_G.mpc = mock.mpc
_G.dev = mock.dev
_G.LaunchpadProMK3 = mock.dev
dofile("script/LaunchpadProMK3.lua")
local L = LaunchpadProMK3

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end
end

local function assert_near(a, b, msg)
  if math.abs(a - b) > 1e-6 then
    error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
  end
end

L.OnLoad()

-- Volume: hold CC 4 + track button CC 101 (track 0) enters adjustment mode.
L.HandleMIDICC(0, 4, 127)
L.HandleMIDICC(0, 101, 127)
assert_eq(mock.count("SelectTrack"), 1, "SelectTrack on enter")
assert_eq(mock.find("SelectTrack")[1].args[1], 0, "track 0 selected")
L.HandleMIDICC(0, 4, 0) -- release volume; adjustment mode persists

-- LED feedback: the volume button is white and the adjusted track button is cyan.
assert_eq(mock.leds[4][1], 127, "volume button red")
assert_eq(mock.leds[4][2], 127, "volume button green")
assert_eq(mock.leds[4][3], 127, "volume button blue")
assert_eq(mock.leds[101][1], 0, "adjusted track button red")
assert_eq(mock.leds[101][2], 127, "adjusted track button green")
assert_eq(mock.leds[101][3], 127, "adjusted track button blue")

-- Grid pad in the track's column sets the value by row: bottom row (row 7) -> 1.0.
L.HandleMIDINoteOn(0, 11, 100)
assert_near(mock.tracks[0].Volume.value, 1.0, "volume row 7 = 1.0")
-- The adjusted track's column is painted as a cyan value bar.
assert_eq(mock.leds[11][1], 0, "adjust bar red")
assert_eq(mock.leds[11][2], 127, "adjust bar green")
assert_eq(mock.leds[11][3], 127, "adjust bar blue")
-- Top row (row 0) -> 0.0.
L.HandleMIDINoteOn(0, 81, 100)
assert_near(mock.tracks[0].Volume.value, 0.0, "volume row 0 = 0.0")
-- Up nudges +1/8.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[0].Volume.value, 0.125, "volume up 1/8")
-- Down nudges -1/8 and clamps at 0.
L.HandleMIDICC(0, 70, 127)
assert_near(mock.tracks[0].Volume.value, 0.0, "volume down 1/8")
L.HandleMIDICC(0, 70, 127)
assert_near(mock.tracks[0].Volume.value, 0.0, "volume clamped at 0")
-- Up clamps at 1.
for _ = 1, 10 do L.HandleMIDICC(0, 80, 127) end
assert_near(mock.tracks[0].Volume.value, 1.0, "volume clamped at 1")

-- Pan: hold CC 5 + track button CC 102 (track 1).
L.HandleMIDICC(0, 5, 127)
L.HandleMIDICC(0, 102, 127)
assert_eq(mock.find("SelectTrack")[2].args[1], 1, "track 1 selected")
L.HandleMIDICC(0, 5, 0)
-- Grid pad col 1, row 4 -> 4/7.
L.HandleMIDINoteOn(0, 42, 100)
assert_near(mock.tracks[1].Pan.value, 4 / 7, "pan row 4 = 4/7")
-- Up nudges +1/8.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[1].Pan.value, 4 / 7 + 1 / 8, "pan up 1/8")

-- Sends: hold CC 6 + track button CC 103 (track 2) enters sends mode.
L.HandleMIDICC(0, 6, 127)
L.HandleMIDICC(0, 103, 127)
assert_eq(mock.find("SelectTrack")[3].args[1], 2, "track 2 selected")
L.HandleMIDICC(0, 6, 0)
-- Grid column 0 row 7 selects send 1 and sets it to 1.0.
L.HandleMIDINoteOn(0, 11, 100)
assert_near(mock.tracks[2].Sends1.value, 1.0, "send 1 = 1.0")
-- Grid column 1 row 3 selects send 2 and sets it to 3/7.
L.HandleMIDINoteOn(0, 52, 100)
assert_near(mock.tracks[2].Sends2.value, 3 / 7, "send 2 = 3/7")
-- Shift + sends cycles to send 3.
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 6, 127)
L.HandleMIDICC(0, 90, 0)
-- Grid column 2 row 7 selects send 3 and sets it to 1.0.
L.HandleMIDINoteOn(0, 13, 100)
assert_near(mock.tracks[2].Sends3.value, 1.0, "send 3 = 1.0")
-- Up nudges the active send by +1/8, clamped at 1.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[2].Sends3.value, 1.0, "send 3 clamped at 1")
-- Down nudges the active send by -1/8.
L.HandleMIDICC(0, 70, 127)
assert_near(mock.tracks[2].Sends3.value, 0.875, "send 3 down 1/8")

-- Exit adjustment mode: a track button without a held function selects the track.
L.HandleMIDICC(0, 101, 127)
assert_eq(mock.count("SelectTrack"), 4, "SelectTrack on exit")
-- A grid pad now launches a clip again.
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch after exit")

-- Scrolled window: after MoveRight(1), track 1 is in grid column 0.
L.HandleMIDICC(0, 92, 127) -- MoveRight(1)
L.HandleMIDICC(0, 4, 127) -- hold volume
L.HandleMIDICC(0, 101, 127) -- track button 0 -> global track 1
assert_eq(mock.find("SelectTrack")[5].args[1], 1, "track 1 selected after scroll")
L.HandleMIDICC(0, 4, 0)
L.HandleMIDINoteOn(0, 11, 100) -- grid column 0, row 7
assert_near(mock.tracks[1].Volume.value, 1.0, "volume after scroll")

L.OnUnload()
print("test-track-controls: PASS")
