-- tests/test-qlink.lua: Q-Link page (CC 7 device), driven by Twist on controlSurface.qlinks.
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

local function lastCall(name)
	local calls = mock.find(name)
	return calls[#calls]
end

local function touchesOf(i)
	local n = 0
	for _, t in ipairs(mock.find("Touch")) do
		if t.args[1] == i then
			n = n + 1
		end
	end
	return n
end

L.OnLoad()

-- Press CC 7 (device) to enter the Q-Link page; entering must not write any qlink.
L.HandleMIDICC(0, 7, 127)
assert_eq(mock.count("SetPosition"), 0, "no SetPosition on enter")
assert_eq(mock.count("Twist"), 0, "no Twist on enter")
assert_eq(mock.leds[7][1], 127, "device button white on qlink page")

-- Top pad in column 0: Q-Link 0 -> 127, one Twist(127) from position 0.
L.HandleMIDINoteOn(0, 81, 100)
local c = lastCall("Twist")
assert_eq(c.args[1], 0, "qlink 0")
assert_eq(c.args[2], 127, "qlink 0 delta 127")
assert_eq(mock.qlinks[0]:GetPosition(), 127, "qlink 0 position 127")
assert_eq(touchesOf(0), 2, "Touch before + after the twist burst")

-- Bottom pad in column 1: Q-Link 1 -> 16 (1/8 of 127).
L.HandleMIDINoteOn(0, 12, 100)
c = lastCall("Twist")
assert_eq(c.args[1], 1, "qlink 1")
assert_eq(c.args[2], 16, "qlink 1 delta 16")
assert_eq(mock.qlinks[1]:GetPosition(), 16, "qlink 1 position 16")

-- Up arrow switches to bank 2 (Q-Links 8-15); down goes back to bank 1.
L.HandleMIDICC(0, 80, 127)
L.HandleMIDINoteOn(0, 81, 100)
c = lastCall("Twist")
assert_eq(c.args[1], 8, "qlink 8 on bank 2")
assert_eq(c.args[2], 127, "qlink 8 delta 127")
assert_eq(mock.qlinks[8]:GetPosition(), 127, "qlink 8 position 127")
L.HandleMIDICC(0, 70, 127)
L.HandleMIDICC(0, 80, 127)

-- Shift+down nudges qlink 8 (last touched column) by -1; Shift+up nudges +1, no wrap past 127.
L.HandleMIDICC(0, 90, 127) -- shift on
L.HandleMIDICC(0, 70, 127) -- shift+down
c = lastCall("Twist")
assert_eq(c.args[1], 8, "qlink 8 nudge target")
assert_eq(c.args[2], -1, "nudge -1")
assert_eq(mock.qlinks[8]:GetPosition(), 126, "qlink 8 = 126")
L.HandleMIDICC(0, 80, 127) -- shift+up
assert_eq(mock.qlinks[8]:GetPosition(), 127, "qlink 8 back to 127")
L.HandleMIDICC(0, 80, 127) -- shift+up at 127 is skipped
assert_eq(mock.qlinks[8]:GetPosition(), 127, "no wrap past 127")
L.HandleMIDICC(0, 90, 0) -- shift off

-- Fallback: a qlink without Twist is driven with SetPosition.
L.HandleMIDICC(0, 70, 127) -- back to bank 1
local savedTwist = mock.qlinks[1].Twist
mock.qlinks[1].Twist = nil
L.HandleMIDINoteOn(0, 12, 100)
c = lastCall("SetPosition")
assert_eq(c.args[1], 1, "fallback qlink 1")
assert_eq(c.args[2], 16, "fallback position 16")
mock.qlinks[1].Twist = savedTwist

-- Shift+CC 7 opens the tempo page and closes the Q-Link page (mutual exclusion):
-- a pad press must neither launch a clip nor touch a qlink.
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 7, 127) -- shift + device = tempo page
L.HandleMIDICC(0, 90, 0)
local twistCount = mock.count("Twist")
local clipCount = mock.count("TriggerClip")
L.HandleMIDINoteOn(0, 81, 100)
assert_eq(mock.count("Twist"), twistCount, "no twist on tempo page")
assert_eq(mock.count("TriggerClip"), clipCount, "no clip launch on tempo page")

-- CC 7 re-enters the Q-Link page (and closes the tempo page); pads drive qlinks again.
L.HandleMIDICC(0, 7, 127)
L.HandleMIDINoteOn(0, 21, 100)
c = lastCall("Twist")
assert_eq(c.args[1], 0, "qlink 0 after re-enter")
assert_eq(c.args[2], -95, "qlink 0 delta to 32")
assert_eq(mock.qlinks[0]:GetPosition(), 32, "qlink 0 = 32")

-- Press CC 7 again to exit; a pad now launches a clip and the button shows available.
L.HandleMIDICC(0, 7, 127)
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), clipCount + 1, "clip launch after exit")
assert_eq(mock.leds[7][1], 60, "device button available after exit")
assert_eq(mock.leds[7][2], 60, "device button available (green)")
assert_eq(mock.leds[7][3], 60, "device button available (blue)")

L.OnUnload()
print("test-qlink: PASS")
