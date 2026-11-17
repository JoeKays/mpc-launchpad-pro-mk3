-- tests/test-buttons.lua: the Shift transport buttons (CC 20/10/40/30), track
-- navigation + plugin presets (Shift + CC 91/92/94/95), native tap tempo
-- routing (Shift + CC 6), and the firmware identity probe.
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

-- capture the script's log output so the log strings can be asserted
local logs = {}
local realPrint = print
_G.print = function(msg)
	logs[#logs + 1] = tostring(msg)
end

local function lastLog()
	return logs[#logs] or ""
end

local function logCount(prefix)
	local n = 0
	for _, l in ipairs(logs) do
		if l:sub(1, #prefix) == prefix then
			n = n + 1
		end
	end
	return n
end

L.OnLoad()

-- Firmware probe: OnLoad sent the device-inquiry sysex (payload without F0/F7).
local inquiries = 0
for _, c in ipairs(mock.find("SendMIDISysex")) do
	if c.args[1] == string.char(0x7E, 0x7F, 0x06, 0x01) and c.args[2] == 0 then
		inquiries = inquiries + 1
	end
end
assert_eq(inquiries, 1, "device inquiry sent once")
-- identity reply (Novation): 7E <dev> 06 02 <00 20 29> <family 2> <model 2> <version 1.1.8>
L.HandleMIDISysex(string.char(0x7E, 0x00, 0x06, 0x02, 0x00, 0x20, 0x29, 0x43, 0x00, 0x00, 0x01, 0x01, 0x01, 0x08))
assert_eq(lastLog(), "LaunchpadProMK3: firmware: 1.1.8", "firmware version logged")
L.HandleMIDISysex(string.char(0x7E, 0x00, 0x06, 0x02, 0x00, 0x20, 0x29, 0x43, 0x00, 0x00, 0x01, 0x01, 0x01, 0x08))
assert_eq(logCount("LaunchpadProMK3: firmware:"), 1, "firmware logged once")
-- a non-Novation identity reply is ignored
L.HandleMIDISysex(string.char(0x7E, 0x00, 0x06, 0x02, 0x47, 0x00, 0x5D, 0x00, 0x00, 0x00, 0x01, 0x02, 0x41))
assert_eq(logCount("LaunchpadProMK3: firmware:"), 1, "non-Novation reply ignored")

-- Shift + CC 6 = native tap tempo: Shift press routes CC 6 to the MPC control
mock.reset()
L.HandleMIDICC(0, 90, 127)
assert_eq(lastLog(), "LaunchpadProMK3: tap tempo: native", "native tap tempo bound")
local adds = mock.find("AddCCToControl")
assert_eq(#adds, 1, "AddCCToControl once")
assert_eq(adds[1].args[1], 0, "AddCCToControl channel 0")
assert_eq(adds[1].args[2], 6, "AddCCToControl CC 6")
assert_eq(adds[1].args[3], "Tap Tempo", "AddCCToControl control name")
assert_eq(mock.count("RemoveCCToScript"), 1, "CC 6 left the script")
assert_eq(mock.find("RemoveCCToScript")[1].args[2], 6, "RemoveCCToScript CC 6")
-- while native, a CC 6 press must not run the manual averager
mock.setNow(0)
L.HandleMIDICC(0, 6, 127)
assert_eq(mock.count("SetBPM"), 0, "manual averager skipped while native")
L.HandleMIDICC(0, 6, 0)
-- Shift release routes CC 6 back to the script
L.HandleMIDICC(0, 90, 0)
local removes = mock.find("RemoveCCToControl")
assert_eq(#removes, 1, "RemoveCCToControl once")
assert_eq(removes[1].args[1], 0, "RemoveCCToControl channel 0")
assert_eq(removes[1].args[2], 6, "RemoveCCToControl CC 6")
assert_eq(mock.count("AddCCToScript"), 1, "CC 6 back on the script")
assert_eq(mock.find("AddCCToScript")[1].args[2], 6, "AddCCToScript CC 6")

-- manual fallback: without the controlSurface mapping the averager still runs
local savedControlSurface = mock.dev.mappings.controlSurface
mock.dev.mappings.controlSurface = nil
L.HandleMIDICC(0, 90, 127)
assert_eq(lastLog(), "LaunchpadProMK3: tap tempo: manual fallback", "tap tempo manual fallback")
mock.setNow(0)
L.HandleMIDICC(0, 6, 127)
L.HandleMIDICC(0, 6, 0)
mock.setNow(500)
L.HandleMIDICC(0, 6, 127)
assert_eq(mock.find("SetBPM")[1].args[1], 120, "manual tap tempo 120 BPM")
L.HandleMIDICC(0, 6, 0)
L.HandleMIDICC(0, 90, 0)
mock.dev.mappings.controlSurface = savedControlSurface

-- Shift + CC 20/10/40/30: loop, overdub, quantiser, automation filter
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 20, 127) -- shift + play = loop toggle
assert_eq(lastLog(), "LaunchpadProMK3: loop: on", "loop on")
assert_eq(mock.sequencer.Loop.value, true, "Loop.value true")
L.HandleMIDICC(0, 20, 0)
L.HandleMIDICC(0, 20, 127)
assert_eq(lastLog(), "LaunchpadProMK3: loop: off", "loop off")
assert_eq(mock.sequencer.Loop.value, false, "Loop.value false")
L.HandleMIDICC(0, 20, 0)

L.HandleMIDICC(0, 10, 127) -- shift + record = overdub
assert_eq(mock.count("Overdub"), 1, "Overdub called")
assert_eq(lastLog(), "LaunchpadProMK3: overdub", "overdub logged")
L.HandleMIDICC(0, 10, 0)

L.HandleMIDICC(0, 40, 127) -- shift + quantize = quantiser toggle
assert_eq(lastLog(), "LaunchpadProMK3: quantiser: off", "quantiser off")
assert_eq(mock.sequencer.quantiser.Enabled.value, false, "Enabled.value false")
L.HandleMIDICC(0, 40, 0)
L.HandleMIDICC(0, 40, 127)
assert_eq(lastLog(), "LaunchpadProMK3: quantiser: on", "quantiser on")
assert_eq(mock.sequencer.quantiser.Enabled.value, true, "Enabled.value true")
L.HandleMIDICC(0, 40, 0)

L.HandleMIDICC(0, 30, 127) -- shift + fixed length = automation filter cycle
assert_eq(mock.count("AdvanceGlobalAutomationFilterType"), 1, "filter cycle called")
assert_eq(lastLog(), "LaunchpadProMK3: automation filter: cycled", "automation filter logged")
L.HandleMIDICC(0, 30, 0)

-- Shift + CC 91/92 = current track prev/next (not a window move)
L.HandleMIDICC(0, 91, 127)
assert_eq(mock.count("currentTrack.Previous"), 1, "track prev")
assert_eq(lastLog(), "LaunchpadProMK3: track: prev", "track prev logged")
L.HandleMIDICC(0, 91, 0)
L.HandleMIDICC(0, 92, 127)
assert_eq(mock.count("currentTrack.Next"), 1, "track next")
assert_eq(lastLog(), "LaunchpadProMK3: track: next", "track next logged")
L.HandleMIDICC(0, 92, 0)
assert_eq(mock.count("MoveLeft"), 0, "shift + < is not a window move")
assert_eq(mock.count("MoveRight"), 0, "shift + > is not a window move")

-- Shift + CC 94/95 = plugin preset prev/next on the current track
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("currentTrack.PrevPluginPreset"), 1, "preset prev")
assert_eq(lastLog(), "LaunchpadProMK3: preset: prev", "preset prev logged")
L.HandleMIDICC(0, 94, 0)
L.HandleMIDICC(0, 95, 127)
assert_eq(mock.count("currentTrack.NextPluginPreset"), 1, "preset next")
assert_eq(lastLog(), "LaunchpadProMK3: preset: next", "preset next logged")
L.HandleMIDICC(0, 95, 0)
L.HandleMIDICC(0, 90, 0)

-- without Shift the buttons keep their primary functions
L.HandleMIDICC(0, 20, 127)
assert_eq(mock.count("Play"), 1, "play without shift")
L.HandleMIDICC(0, 20, 0)
L.HandleMIDICC(0, 10, 127)
assert_eq(mock.count("Record"), 1, "record without shift")
L.HandleMIDICC(0, 10, 0)
L.HandleMIDICC(0, 91, 127)
assert_eq(mock.count("MoveLeft"), 1, "window left without shift")
L.HandleMIDICC(0, 91, 0)
L.HandleMIDICC(0, 30, 127)
assert_eq(lastLog(), "LaunchpadProMK3: unmapped CC 30 value 127", "fixed length stays a stub without shift")
L.HandleMIDICC(0, 30, 0)

-- Degrade: missing APIs log once and leave the surface working
L.HandleMIDICC(0, 90, 127)
local savedProject = mock.mpc.project
mock.mpc.project = nil
L.HandleMIDICC(0, 30, 127)
assert_eq(
	lastLog(),
	"LaunchpadProMK3: automation filter unavailable: project.AdvanceGlobalAutomationFilterType missing",
	"automation filter degrade"
)
L.HandleMIDICC(0, 30, 0)
mock.mpc.project = savedProject

local savedLoop = mock.mpc.sequencer.Loop
mock.mpc.sequencer.Loop = nil
L.HandleMIDICC(0, 20, 127)
assert_eq(lastLog(), "LaunchpadProMK3: loop unavailable: sequencer.Loop missing", "loop degrade")
L.HandleMIDICC(0, 20, 0)
mock.mpc.sequencer.Loop = savedLoop

local savedOverdub = mock.mpc.sequencer.Overdub
mock.mpc.sequencer.Overdub = nil
L.HandleMIDICC(0, 10, 127)
assert_eq(lastLog(), "LaunchpadProMK3: overdub unavailable: sequencer.Overdub missing", "overdub degrade")
L.HandleMIDICC(0, 10, 0)
mock.mpc.sequencer.Overdub = savedOverdub

local savedEnabled = mock.mpc.sequencer.quantiser.Enabled
mock.mpc.sequencer.quantiser.Enabled = nil
L.HandleMIDICC(0, 40, 127)
assert_eq(lastLog(), "LaunchpadProMK3: quantiser unavailable: sequencer.quantiser.Enabled missing", "quantiser degrade")
L.HandleMIDICC(0, 40, 0)
mock.mpc.sequencer.quantiser.Enabled = savedEnabled

local savedNext = mock.mpc.tracks.currentTrack.Next
mock.mpc.tracks.currentTrack.Next = nil
L.HandleMIDICC(0, 92, 127)
assert_eq(lastLog(), "LaunchpadProMK3: track nav unavailable: currentTrack.Next missing", "track nav degrade")
L.HandleMIDICC(0, 92, 0)
mock.mpc.tracks.currentTrack.Next = savedNext

local savedPrevPreset = mock.mpc.tracks.currentTrack.PrevPluginPreset
mock.mpc.tracks.currentTrack.PrevPluginPreset = nil
L.HandleMIDICC(0, 94, 127)
assert_eq(lastLog(), "LaunchpadProMK3: preset unavailable: currentTrack.PrevPluginPreset missing", "preset degrade")
L.HandleMIDICC(0, 94, 0)
mock.mpc.tracks.currentTrack.PrevPluginPreset = savedPrevPreset
L.HandleMIDICC(0, 90, 0)

L.OnUnload()
_G.print = realPrint
print("test-buttons: PASS")
