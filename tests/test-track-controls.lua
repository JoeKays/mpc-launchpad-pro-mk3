-- tests/test-track-controls.lua: volume/pan/sends menu mode.
package.path = "./tests/?.lua;" .. package.path
local mock = require("mock-mpc")
_G.mpc = mock.mpc
_G.dev = mock.dev
_G.LaunchpadProMK3 = mock.dev
dofile("script/LaunchpadProMK3.lua")
local L = LaunchpadProMK3

local function assert_eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
	end
end

local function assert_near(a, b, msg)
	if math.abs(a - b) > 1e-6 then
		error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
	end
end

-- MPC fader curve: dB = 40*log10(gain) + 6; -inf is gain 0.
local function db_gain(db)
	if db <= -60 then
		return 0
	end
	return 10 ^ ((db - 6) / 40)
end

L.OnLoad()

-- Mapped function buttons CC 1-6 and CC 8 are available (lighter); CC 7 is off.
for cc = 1, 6 do
	assert_eq(mock.leds[cc][1], 60, "function button " .. cc .. " available")
end
assert_eq(mock.leds[7][1], 0, "device button off")
assert_eq(mock.leds[8][1], 60, "stopClip button available")

-- Volume menu: press CC 4.
L.HandleMIDICC(0, 4, 127)
-- The volume button is white.
assert_eq(mock.leds[4][1], 127, "volume button red")
assert_eq(mock.leds[4][2], 127, "volume button green")
assert_eq(mock.leds[4][3], 127, "volume button blue")
-- Up/down are cyan while a menu is open.
assert_eq(mock.leds[80][2], 127, "up lit in menu")
assert_eq(mock.leds[70][2], 127, "down lit in menu")
-- Grid pad col 0, top row (note 81) -> track 0 volume +6 dB.
L.HandleMIDINoteOn(0, 81, 100)
assert_near(mock.tracks[0].Volume.value, db_gain(6), "volume top row = +6 dB")
-- The fader fills from the bottom: the bottom pad (note 11) is lit.
assert_eq(mock.leds[11][1], 0, "fader bottom red")
assert_eq(mock.leds[11][2], 127, "fader bottom green")
assert_eq(mock.leds[11][3], 127, "fader bottom blue")
-- Grid pad col 0, bottom row (note 11) -> track 0 volume -inf.
L.HandleMIDINoteOn(0, 11, 100)
assert_near(mock.tracks[0].Volume.value, 0, "volume bottom row = -inf")
-- Up nudges one dB step: -inf -> -30 dB.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[0].Volume.value, db_gain(-30), "volume up -> -30 dB")
-- Down nudges back to -inf.
L.HandleMIDICC(0, 70, 127)
assert_near(mock.tracks[0].Volume.value, 0, "volume down -> -inf")
-- Up clamps at +6 dB.
for _ = 1, 10 do
	L.HandleMIDICC(0, 80, 127)
end
assert_near(mock.tracks[0].Volume.value, db_gain(6), "volume clamped at +6 dB")

-- Pan menu: press CC 5.
L.HandleMIDICC(0, 5, 127)
-- Up/down take the pan page colour (magenta).
assert_eq(mock.leds[80][1], 127, "pan up red")
assert_eq(mock.leds[80][2], 0, "pan up green")
assert_eq(mock.leds[80][3], 127, "pan up blue")
assert_eq(mock.leds[70][1], 127, "pan down red")
-- Grid pad col 1, row 4 (note 42) -> track 1 pan 4/8 = 0.5.
L.HandleMIDINoteOn(0, 42, 100)
assert_near(mock.tracks[1].Pan.value, 4 / 8, "pan row 4 = 0.5")
-- Up nudges +1/8.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[1].Pan.value, 5 / 8, "pan up 1/8")
-- Double-tap the bottom pad (note 12) to reach the true minimum 0.0.
L.HandleMIDINoteOn(0, 12, 100)
assert_near(mock.tracks[1].Pan.value, 1 / 8, "pan bottom row = 1/8")
L.HandleTimer()
L.HandleMIDINoteOn(0, 12, 100)
assert_near(mock.tracks[1].Pan.value, 0.0, "pan double-tap bottom = 0.0")

-- Sends menu: press CC 6.
L.HandleMIDICC(0, 6, 127)
-- Up/down take the send page colour (send 1 = yellow).
assert_eq(mock.leds[80][1], 127, "send up red")
assert_eq(mock.leds[80][2], 127, "send up green")
assert_eq(mock.leds[80][3], 0, "send up blue")
-- Grid pad col 2, top row (note 83) -> track 2 send 1 = 1.0.
L.HandleMIDINoteOn(0, 83, 100)
assert_near(mock.tracks[2].Send1.value, 1.0, "send 1 = 1.0")
-- Send 1 is yellow: the top pad is lit yellow.
assert_eq(mock.leds[83][1], 127, "send 1 red")
assert_eq(mock.leds[83][2], 127, "send 1 green")
assert_eq(mock.leds[83][3], 0, "send 1 blue")
-- Tapping CC 6 again cycles to send 2, which is green.
L.HandleMIDICC(0, 6, 127)
-- Grid pad col 2, row 3 (note 53) -> track 2 send 2 = 5/8.
L.HandleMIDINoteOn(0, 53, 100)
assert_near(mock.tracks[2].Send2.value, 5 / 8, "send 2 = 5/8")
-- Send 2 is green: the bottom pad of col 2 (note 13) is lit green.
assert_eq(mock.leds[13][1], 0, "send 2 red")
assert_eq(mock.leds[13][2], 127, "send 2 green")
assert_eq(mock.leds[13][3], 0, "send 2 blue")
-- Grid pad col 2, row 3 (note 53) -> track 2 send 2 = 5/8.
L.HandleMIDINoteOn(0, 53, 100)
assert_near(mock.tracks[2].Send2.value, 5 / 8, "send 2 = 5/8")
-- Up nudges the active send by +1/8.
L.HandleMIDICC(0, 80, 127)
assert_near(mock.tracks[2].Send2.value, 6 / 8, "send 2 up 1/8")

-- Exit the menu: press pan (CC 5) to switch, then pan again to exit.
L.HandleMIDICC(0, 5, 127)
L.HandleMIDICC(0, 5, 127)
-- A grid pad now launches a clip again.
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch after exit")

-- Scrolled window: after MoveRight(1), track 1 is in grid column 0.
L.HandleMIDICC(0, 92, 127) -- MoveRight(1)
L.HandleMIDICC(0, 4, 127) -- volume menu
L.HandleMIDINoteOn(0, 81, 100) -- grid column 0, top row
assert_near(mock.tracks[1].Volume.value, db_gain(6), "volume after scroll")

-- Empty tracks beyond SizeNormalTracks stay dark in the fader menus.
-- After MoveRight(1), grid col 4 = global track 5 (empty), col 3 = track 4.
mock.setNormalTrackCount(5)
L.HandleTimer() -- repaint the open volume menu
assert_eq(mock.leds[15][1], 0, "empty track 5 red")
assert_eq(mock.leds[15][2], 0, "empty track 5 green")
assert_eq(mock.leds[15][3], 0, "empty track 5 blue")
assert_eq(mock.leds[14][2], 127, "track 4 lit")
mock.setNormalTrackCount(8)

L.OnUnload()
print("test-track-controls: PASS")
