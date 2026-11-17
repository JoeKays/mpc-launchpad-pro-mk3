-- tests/test-qlink.lua: Q-Link page (CC 7 device).
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

local function lastSetPosition()
	local calls = mock.find("SetPosition")
	return calls[#calls]
end

L.OnLoad()

-- Press CC 7 (device) to enter the Q-Link page.
L.HandleMIDICC(0, 7, 127)
assert_eq(mock.count("SetPosition"), 0, "no SetPosition yet")

-- Top pad in column 0: Q-Link 0 = 127.
L.HandleMIDINoteOn(0, 81, 100)
local c = lastSetPosition()
assert_eq(c.args[1], 0, "qlink 0")
assert_eq(c.args[2], 127, "qlink 0 = 127")

-- Bottom pad in column 1: Q-Link 1 = 16 (1/8 of 127).
L.HandleMIDINoteOn(0, 12, 100)
c = lastSetPosition()
assert_eq(c.args[1], 1, "qlink 1")
assert_eq(c.args[2], 16, "qlink 1 = 16")

-- Up arrow switches to bank 2 (Q-Links 8-15).
L.HandleMIDICC(0, 80, 127)
L.HandleMIDINoteOn(0, 81, 100)
c = lastSetPosition()
assert_eq(c.args[1], 8, "qlink 8")
assert_eq(c.args[2], 127, "qlink 8 = 127")

-- Shift+up nudges the selected Q-Link by +1 (clamped at 127).
L.HandleMIDICC(0, 90, 127) -- shift on
L.HandleMIDICC(0, 80, 127) -- shift+up
c = lastSetPosition()
assert_eq(c.args[1], 8, "qlink 8 nudge")
assert_eq(c.args[2], 127, "qlink 8 clamped at 127")
L.HandleMIDICC(0, 90, 0) -- shift off

-- Shift+down nudges by -1.
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 70, 127) -- shift+down
c = lastSetPosition()
assert_eq(c.args[1], 8, "qlink 8 nudge down")
assert_eq(c.args[2], 126, "qlink 8 = 126")
L.HandleMIDICC(0, 90, 0)

-- Press CC 7 again to exit; a pad now launches a clip.
L.HandleMIDICC(0, 7, 127)
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch after exit")

-- The device button is white while the Q-Link page is open.
L.HandleMIDICC(0, 7, 127)
assert_eq(mock.leds[7][1], 127, "device button white on qlink page")
L.HandleMIDICC(0, 7, 127)
assert_eq(mock.leds[7][1], 60, "device button available after exit")

L.OnUnload()
print("test-qlink: PASS")
