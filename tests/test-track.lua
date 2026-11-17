-- tests/test-track.lua: hold a function button + a track button (CC 1-8) applies it.
package.path = "./tests/?.lua;" .. package.path
local mock = require("mock-mpc")
_G.mpc = mock.mpc
_G.LaunchpadProMK3 = mock.dev
dofile("script/LaunchpadProMK3.lua")
local L = LaunchpadProMK3

local function assert_eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
	end
end

L.OnLoad()

-- hold recArm (101) + track 0 (CC 1)
L.HandleMIDICC(0, 1, 127)
assert_eq(mock.count("SetRecArm"), 0, "no SetRecArm on hold")
L.HandleMIDICC(0, 101, 127)
assert_eq(mock.count("SetRecArm"), 1, "SetRecArm")
assert_eq(mock.find("SetRecArm")[1].args[1], 0, "track 0")
assert_eq(mock.find("SetRecArm")[1].args[2], true, "value true")
L.HandleMIDICC(0, 1, 0)

-- hold mute (102) + track 1 (CC 2)
L.HandleMIDICC(0, 2, 127)
L.HandleMIDICC(0, 102, 127)
assert_eq(mock.count("SetMute"), 1, "SetMute")
assert_eq(mock.find("SetMute")[1].args[1], 1, "track 1")
assert_eq(mock.find("SetMute")[1].args[2], true, "mute true")
L.HandleMIDICC(0, 2, 0)

-- hold solo (103) + track 2 (CC 3)
L.HandleMIDICC(0, 3, 127)
L.HandleMIDICC(0, 103, 127)
assert_eq(mock.count("SetSolo"), 1, "SetSolo")
assert_eq(mock.find("SetSolo")[1].args[1], 2, "track 2")
assert_eq(mock.find("SetSolo")[1].args[2], true, "solo true")
L.HandleMIDICC(0, 3, 0)

-- hold stop clip (108) + track 3 (CC 4)
L.HandleMIDICC(0, 8, 127)
L.HandleMIDICC(0, 104, 127)
assert_eq(mock.count("StopClipsOnTrack"), 1, "StopClipsOnTrack")
assert_eq(mock.find("StopClipsOnTrack")[1].args[1], 3, "track 3")
L.HandleMIDICC(0, 8, 0)

-- track select without a held function
L.HandleMIDICC(0, 101, 127)
assert_eq(mock.count("SelectTrack"), 1, "SelectTrack")
assert_eq(mock.find("SelectTrack")[1].args[1], 0, "track 0")

-- after scrolling right by 1, CC 101 (first grid column) controls global track 1
L.HandleMIDICC(0, 92, 127) -- MoveRight(1)
L.HandleMIDICC(0, 2, 127) -- hold mute
L.HandleMIDICC(0, 101, 127) -- track button 0 -> global track 1
assert_eq(mock.count("SetMute"), 2, "SetMute after scroll")
assert_eq(mock.find("SetMute")[2].args[1], 1, "track 1 after scroll")
L.HandleMIDICC(0, 2, 0)

L.OnUnload()
print("test-track: PASS")
