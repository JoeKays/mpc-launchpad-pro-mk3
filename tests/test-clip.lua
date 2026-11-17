-- tests/test-clip.lua: clip-mode mapping + LED wire assertions.
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

L.OnLoad()
assert_eq(mock.count("SetColumns"), 1, "SetColumns")
assert_eq(mock.count("SetRows"), 1, "SetRows")
assert_eq(mock.count("Show"), 1, "Show")
assert_eq(mock.count("timer.Start"), 1, "timer.Start")
assert_eq(mock.count("AddNoteToScript"), 64, "grid notes registered")
assert(mock.count("AddCCToScript") >= 40, "edge CCs registered")

-- initial grid paint: 64 pads
local painted = 0
for i = 11, 88 do
	if mock.leds[i] then
		painted = painted + 1
	end
end
assert(painted >= 64, "grid painted")

-- clip states: the mock's slots are State 2 (stopped) with colour 0xFF0000 ->
-- the top-left slot (clip row 0) shows the clip's own colour, solid
assert_eq(mock.leds[81][1], 127, "stopped clip shows its own colour (red)")

-- pad press -> TriggerClip(0,0)
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "TriggerClip")
assert_eq(mock.find("TriggerClip")[1].args[1], 0, "TriggerClip col")
assert_eq(mock.find("TriggerClip")[1].args[2], 7, "TriggerClip row (bottom pad -> MPC row 7)")

-- scene press -> TriggerRow(0)
L.HandleMIDICC(0, 89, 127)
assert_eq(mock.count("TriggerRow"), 1, "TriggerRow")
assert_eq(mock.find("TriggerRow")[1].args[1], 0, "TriggerRow row")

-- hold recArm (101) + track 0 (CC 1) -> SetRecArm
L.HandleMIDICC(0, 1, 127)
L.HandleMIDICC(0, 101, 127)
assert_eq(mock.count("SetRecArm"), 1, "SetRecArm")
assert_eq(mock.find("SetRecArm")[1].args[1], 0, "SetRecArm track")
assert_eq(mock.find("SetRecArm")[1].args[2], true, "SetRecArm value")
L.HandleMIDICC(0, 1, 0)

-- shift + pad -> SelectClip, no extra TriggerClip
L.HandleMIDICC(0, 90, 127)
L.HandleMIDINoteOn(0, 12, 100)
assert_eq(mock.count("SelectClip"), 2, "SelectClip")
assert_eq(mock.count("TriggerClip"), 1, "no extra TriggerClip")
L.HandleMIDICC(0, 90, 0)

-- window move
L.HandleMIDICC(0, 91, 127)
assert_eq(mock.count("MoveLeft"), 1, "MoveLeft")
L.HandleMIDICC(0, 92, 127)
assert_eq(mock.count("MoveRight"), 1, "MoveRight")
L.HandleMIDICC(0, 80, 127)
assert_eq(mock.count("MoveUp"), 1, "MoveUp")
L.HandleMIDICC(0, 70, 127)
assert_eq(mock.count("MoveDown"), 1, "MoveDown")

-- LED budget: one sysex message per paint cycle
assert(mock.count("SendMIDISysex") >= 1, "sysex sent")

L.OnUnload()
assert_eq(mock.count("timer.Stop"), 1, "timer.Stop")
assert_eq(mock.count("Hide"), 1, "Hide")
-- every listener stopped: 192 slots + scene/track/sequencer + currentTrack.Index
assert(mock.count("stopListening") >= 228, "removeListeners stops all listeners")

print("test-clip: PASS")
