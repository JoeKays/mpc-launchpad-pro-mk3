-- tests/test-track-controls.lua: volume/pan/sends menu mode.
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

-- Volume menu: press CC 4.
L.HandleMIDICC(0, 4, 127)
-- The volume button is white.
assert_eq(mock.leds[4][1], 127, "volume button red")
assert_eq(mock.leds[4][2], 127, "volume button green")
assert_eq(mock.leds[4][3], 127, "volume button blue")
-- Grid pad col 0, top row (note 81) -> track 0 volume 1.0.
L.HandleMIDINoteOn(0, 81, 100)
assert_near(mock.tracks[0].Volume.value, 1.0, "volume top row = 1.0")
-- The fader fills from the bottom: the bottom pad (note 11) is lit.
assert_eq(mock.leds[11][1], 0, "fader bottom red")
assert_eq(mock.leds[11][2], 127, "fader bottom green")
assert_eq(mock.leds[11][3], 127, "fader bottom blue")
-- Grid pad col 0, bottom row (note 11) -> track 0 volume 1/8.
L.HandleMIDINoteOn(0, 11, 100)
assert_near(mock.tracks[0].Volume.value, 1 / 8, "volume bottom row = 1/8")
-- Up nudges +1/8.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[0].Volume.value, 2 / 8, "volume up 1/8")
-- Down nudges -1/8 and clamps at 0.
L.HandleMIDICC(0, 70, 127)
assert_near(mock.tracks[0].Volume.value, 1 / 8, "volume down 1/8")
L.HandleMIDICC(0, 70, 127)
assert_near(mock.tracks[0].Volume.value, 0.0, "volume clamped at 0")
-- Up clamps at 1.
for _ = 1, 10 do L.HandleMIDICC(0, 80, 127) end
assert_near(mock.tracks[0].Volume.value, 1.0, "volume clamped at 1")

-- Pan menu: press CC 5.
L.HandleMIDICC(0, 5, 127)
-- Grid pad col 1, row 4 (note 42) -> track 1 pan 4/8 = 0.5.
L.HandleMIDINoteOn(0, 42, 100)
assert_near(mock.tracks[1].Pan.value, 4 / 8, "pan row 4 = 0.5")
-- Up nudges +1/8.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[1].Pan.value, 5 / 8, "pan up 1/8")

-- Sends menu: press CC 6.
L.HandleMIDICC(0, 6, 127)
-- Grid pad col 2, top row (note 83) -> track 2 send 1 = 1.0.
L.HandleMIDINoteOn(0, 83, 100)
assert_near(mock.tracks[2].Send1.value, 1.0, "send 1 = 1.0")
-- Shift + CC 6 cycles to send 2.
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 6, 127)
L.HandleMIDICC(0, 90, 0)
-- Grid pad col 2, row 3 (note 53) -> track 2 send 2 = 5/8.
L.HandleMIDINoteOn(0, 53, 100)
assert_near(mock.tracks[2].Send2.value, 5 / 8, "send 2 = 5/8")
-- Up nudges the active send by +1/8.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[2].Send2.value, 6 / 8, "send 2 up 1/8")

-- Exit the menu: press CC 6 again.
L.HandleMIDICC(0, 6, 127)
-- A grid pad now launches a clip again.
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch after exit")

-- Scrolled window: after MoveRight(1), track 1 is in grid column 0.
L.HandleMIDICC(0, 92, 127) -- MoveRight(1)
L.HandleMIDICC(0, 4, 127) -- volume menu
L.HandleMIDINoteOn(0, 81, 100) -- grid column 0, top row
assert_near(mock.tracks[1].Volume.value, 1.0, "volume after scroll")

L.OnUnload()
print("test-track-controls: PASS")
