-- tests/test-transport.lua: transport + undo/redo mapping.
package.path = "./tests/?.lua;" .. package.path
local mock = require("mock-mpc")
_G.mpc = mock.mpc
_G.dev = mock.dev
_G.LaunchpadProMK3 = mock.dev
dofile(os.getenv("LPP3_LUA") or "script/LaunchpadProMK3.lua")
local L = LaunchpadProMK3

local function assert_eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
	end
end

L.OnLoad()
L.HandleMIDICC(0, 20, 127) -- play
assert_eq(mock.count("Play"), 1, "Play")
mock.sequencer.IsPlaying = function()
	return true
end
L.HandleMIDICC(0, 20, 127) -- play while playing -> stop
assert_eq(mock.count("Stop"), 1, "Stop")
L.HandleMIDICC(0, 10, 127) -- record
assert_eq(mock.count("Record"), 1, "Record")
L.HandleMIDICC(0, 90, 127) -- shift on
L.HandleMIDICC(0, 1, 127) -- shift + rec arm = undo
assert_eq(mock.count("Undo"), 1, "Undo")
L.HandleMIDICC(0, 2, 127) -- shift + mute = redo
assert_eq(mock.count("Redo"), 1, "Redo")
L.HandleMIDICC(0, 90, 0)
L.OnUnload()
print("test-transport: PASS")
