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

-- Shift + CC 6 = tap tempo. Native Tap Tempo routing is covered in
-- test-buttons.lua; strip the controlSurface mapping so this section exercises
-- the manual averager fallback (two taps 500 ms apart set 120 BPM).
local savedControlSurface = mock.dev.mappings.controlSurface
mock.dev.mappings.controlSurface = nil
L.HandleMIDICC(0, 90, 0) -- shift off: give CC 6 back to the script
L.HandleMIDICC(0, 90, 127) -- shift on without the mapping -> manual fallback
assert_eq(lastLog(), "LaunchpadProMK3: tap tempo: manual fallback", "tap tempo manual fallback")
mock.setNow(0)
L.HandleMIDICC(0, 6, 127)
assert_eq(lastLog(), "LaunchpadProMK3: tap tempo: first tap", "tap tempo first tap")
L.HandleMIDICC(0, 6, 0)
mock.setNow(500)
L.HandleMIDICC(0, 6, 127)
assert_eq(mock.count("SetBPM"), 1, "tap tempo SetBPM")
assert_eq(mock.find("SetBPM")[1].args[1], 120, "tap tempo 120 BPM")
-- A 499 ms interval gives 120.24 BPM, rounded to the integer 120.
mock.setNow(5000)
L.HandleMIDICC(0, 6, 127) -- gap > 2 s resets the sequence
L.HandleMIDICC(0, 6, 0)
mock.setNow(5499)
L.HandleMIDICC(0, 6, 127)
assert_eq(mock.find("SetBPM")[2].args[1], 120, "tap tempo rounds to int BPM")
L.HandleMIDICC(0, 6, 0)
mock.dev.mappings.controlSurface = savedControlSurface
-- Shift + CC 7 = tempo page: up/down change BPM, holding accelerates.
L.HandleMIDICC(0, 7, 127) -- enter tempo page
assert_eq(lastLog(), "LaunchpadProMK3: tempo page: 120 BPM", "tempo page on")
-- The grid draws the BPM left-aligned: 120 = "1" (col 0, blue), "2" (cols 1-3, orange), "0" (cols 4-7, white).
assert_eq(mock.leds[81][3], 127, "tempo digit 1 blue")
assert_eq(mock.leds[82][1], 127, "tempo digit 2 orange")
assert_eq(mock.leds[85][1], 127, "tempo digit 0 white")
L.HandleMIDICC(0, 7, 0)
L.HandleMIDICC(0, 80, 127) -- up: +1 BPM
assert_eq(mock.find("SetBPM")[3].args[1], 121, "tempo up")
L.HandleMIDICC(0, 80, 0)
L.HandleMIDICC(0, 70, 127) -- down: -1 BPM
assert_eq(mock.find("SetBPM")[4].args[1], 120, "tempo down")
L.HandleMIDICC(0, 70, 0)
-- holding up auto-repeats (accelerating after a short delay)
L.HandleMIDICC(0, 80, 127)
local before = mock.count("SetBPM")
for _ = 1, 20 do
	L.HandleTimer()
end
assert(mock.count("SetBPM") > before + 1, "tempo hold auto-repeats")
L.HandleMIDICC(0, 80, 0)
L.HandleMIDICC(0, 7, 127) -- exit tempo page
assert_eq(lastLog(), "LaunchpadProMK3: tempo page off", "tempo page off")
L.HandleMIDICC(0, 7, 0)
L.HandleMIDICC(0, 8, 127)
assert_eq(lastLog(), "LaunchpadProMK3: swing page: 50%", "swing page opens")
L.HandleMIDICC(0, 80, 127) -- up
assert_eq(lastLog(), "LaunchpadProMK3: swing: 51%", "swing up")
L.HandleMIDICC(0, 80, 0)
L.HandleMIDICC(0, 70, 127) -- down
assert_eq(lastLog(), "LaunchpadProMK3: swing: 50%", "swing down")
L.HandleMIDICC(0, 70, 0)
L.HandleMIDICC(0, 8, 127) -- exit swing page
assert_eq(lastLog(), "LaunchpadProMK3: swing page off", "swing page off")
L.HandleMIDICC(0, 8, 0)
L.HandleMIDICC(0, 90, 0) -- shift off: the quantize press below is the plain one
L.HandleMIDICC(0, 40, 127)
assert_eq(lastLog(), "LaunchpadProMK3: quantize applied", "quantize applied")
L.HandleMIDICC(0, 40, 0)

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
