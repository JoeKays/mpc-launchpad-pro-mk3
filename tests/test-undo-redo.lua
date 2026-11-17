-- tests/test-undo-redo.lua: Shift + CC 1/2 = undo/redo, plus the other shift functions.
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

-- capture the script's log output so the stub/degrade paths can be asserted
local logs = {}
local realPrint = print
_G.print = function(msg)
	logs[#logs + 1] = tostring(msg)
end

local function lastLog()
	return logs[#logs] or ""
end

L.OnLoad()

-- Shift + CC 1 = undo, Shift + CC 2 = redo
L.HandleMIDICC(0, 90, 127) -- shift on
L.HandleMIDICC(0, 1, 127) -- shift + rec arm = undo
assert_eq(mock.count("Undo"), 1, "Undo")
L.HandleMIDICC(0, 2, 127) -- shift + mute = redo
assert_eq(mock.count("Redo"), 1, "Redo")
L.HandleMIDICC(0, 90, 0) -- shift off

-- Shift + CC 1/2 still work while another function button is held, and the
-- held function survives the shift press/release (releasing the shift-function
-- button must not clear the hold).
L.HandleMIDICC(0, 1, 127) -- hold rec arm
L.HandleMIDICC(0, 90, 127) -- shift on
L.HandleMIDICC(0, 2, 127) -- shift + mute = redo
assert_eq(mock.count("Redo"), 2, "Redo while rec arm held")
L.HandleMIDICC(0, 2, 0) -- release CC 2: must not clear the held rec arm
L.HandleMIDICC(0, 90, 0) -- shift off
L.HandleMIDICC(0, 101, 127) -- held rec arm applies to track 0
assert_eq(mock.count("SetRecArm"), 1, "held rec arm survives shift redo")
assert_eq(mock.find("SetRecArm")[1].args[1], 0, "held rec arm track 0")
assert_eq(mock.count("SelectTrack"), 0, "no track select while rec arm held")
L.HandleMIDICC(0, 1, 0) -- release rec arm

L.HandleMIDICC(0, 2, 127) -- hold mute
L.HandleMIDICC(0, 90, 127) -- shift on
L.HandleMIDICC(0, 1, 127) -- shift + rec arm = undo
assert_eq(mock.count("Undo"), 2, "Undo while mute held")
L.HandleMIDICC(0, 1, 0) -- release CC 1: must not clear the held mute
L.HandleMIDICC(0, 90, 0) -- shift off
L.HandleMIDICC(0, 101, 127) -- held mute applies to track 0
assert_eq(mock.count("SetMute"), 1, "held mute survives shift undo")
assert_eq(mock.find("SetMute")[1].args[1], 0, "held mute track 0")
L.HandleMIDICC(0, 2, 0) -- release mute

-- Shift + CC 3 = click/metronome (toggle from the MetronomeEnabled property)
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 3, 127)
assert_eq(mock.count("SetMetronomeEnabled"), 1, "metronome on")
assert_eq(mock.find("SetMetronomeEnabled")[1].args[1], true, "metronome enabled")
mock.sequencer.MetronomeEnabled:set(true) -- the mock records the setter; mirror MPC state
L.HandleMIDICC(0, 3, 0)
L.HandleMIDICC(0, 3, 127)
assert_eq(mock.count("SetMetronomeEnabled"), 2, "metronome off")
assert_eq(mock.find("SetMetronomeEnabled")[2].args[1], false, "metronome disabled")
L.HandleMIDICC(0, 3, 0)

-- Shift + CC 6 = tap tempo: two taps 500 ms apart set 120 BPM.
L.HandleMIDICC(0, 6, 127)
assert_eq(lastLog(), "LaunchpadProMK3: tap tempo: first tap", "tap tempo first tap")
L.HandleMIDICC(0, 6, 0)
L.HandleTimer()
L.HandleTimer() -- 2 ticks = 500 ms
L.HandleMIDICC(0, 6, 127)
assert_eq(mock.count("SetBPM"), 1, "tap tempo SetBPM")
assert_eq(mock.find("SetBPM")[1].args[1], 120, "tap tempo 120 BPM")
L.HandleMIDICC(0, 6, 0)
L.HandleMIDICC(0, 7, 127)
assert_eq(lastLog(), "LaunchpadProMK3: tempo: TODO", "tempo stub")
L.HandleMIDICC(0, 7, 0)
L.HandleMIDICC(0, 8, 127)
assert_eq(lastLog(), "LaunchpadProMK3: swing: TODO", "swing stub")
L.HandleMIDICC(0, 8, 0)
L.HandleMIDICC(0, 90, 0)

-- Degrade: a missing commandManager/sequencer leaves the shift functions inert,
-- logs once, and does not crash.
mock.mpc.commandManager = nil
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 1, 127)
assert_eq(lastLog(), "LaunchpadProMK3: Undo unavailable: commandManager.Undo missing", "undo degrade log")
L.HandleMIDICC(0, 1, 0)
L.HandleMIDICC(0, 2, 127)
assert_eq(lastLog(), "LaunchpadProMK3: Redo unavailable: commandManager.Redo missing", "redo degrade log")
L.HandleMIDICC(0, 2, 0)
mock.mpc.sequencer = nil
L.HandleMIDICC(0, 3, 127)
assert_eq(
	lastLog(),
	"LaunchpadProMK3: metronome unavailable: sequencer.SetMetronomeEnabled missing",
	"metronome degrade log"
)
L.HandleMIDICC(0, 3, 0)
L.HandleMIDICC(0, 90, 0)

L.OnUnload()
_G.print = realPrint
print("test-undo-redo: PASS")
