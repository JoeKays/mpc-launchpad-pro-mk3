-- tests/test-buttons.lua: the Shift transport buttons (CC 20/10/40/30), track
-- navigation + plugin presets (Shift + CC 91/92/94/95), native tap tempo
-- routing (Shift + CC 6), and the firmware identity probe.
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

-- Shift + CC 20/10/40/30: loop, capture MIDI, quantiser, automation filter
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

L.HandleMIDICC(0, 40, 127) -- quantize applies (no Shift variant)
assert_eq(lastLog(), "LaunchpadProMK3: quantize applied", "quantize applied")
L.HandleMIDICC(0, 40, 0)

-- No project: project-scoped actions refuse with a log instead of calling into
-- the MPC (an empty project with 0 tracks must still work).
local savedSeq, savedTracks = mock.mpc.currentSequence, mock.mpc.tracks
local savedGetBPM = mock.sequencer.GetBPM
mock.mpc.currentSequence = nil
mock.mpc.tracks = nil
mock.sequencer.GetBPM = nil
local beforeQ = mock.count("quantizeApply.Press")
L.HandleMIDICC(0, 40, 127)
assert_eq(lastLog(), "LaunchpadProMK3: quantize: no project loaded", "quantize guarded without a project")
assert_eq(mock.count("quantizeApply.Press"), beforeQ, "quantizeApply not pressed without a project")
L.HandleMIDICC(0, 40, 0)
-- An open dialog (e.g. the New Project page) blocks project-scoped actions:
-- the MPC's native side crashes there, so the script must not call into it.
mock.mpc.engineMode.CurrentPopup:set("New Project")
local beforeP = mock.count("quantizeApply.Press")
L.HandleMIDICC(0, 40, 127)
assert_eq(lastLog(), "LaunchpadProMK3: quantize: dialog open (New Project)", "quantize guarded while a dialog is open")
assert_eq(mock.count("quantizeApply.Press"), beforeP, "quantizeApply not pressed while a dialog is open")
L.HandleMIDICC(0, 40, 0)
mock.mpc.engineMode.CurrentPopup:set("No Popup")

-- While a dialog is open every project-scoped page refuses to open.
mock.mpc.engineMode.CurrentPopup:set("New Project")
L.HandleMIDICC(0, 90, 0) -- shift off: test the plain page buttons
mock.reset()
L.HandleMIDICC(0, 7, 127) -- device = Q-Link page
assert_eq(lastLog(), "LaunchpadProMK3: qlink page: dialog open (New Project)", "qlink page guarded")
L.HandleMIDICC(0, 7, 0)
L.HandleMIDICC(0, 94, 127) -- note = pads mode
assert_eq(lastLog(), "LaunchpadProMK3: pads mode: dialog open (New Project)", "pads mode guarded")
L.HandleMIDICC(0, 94, 0)
L.HandleMIDICC(0, 4, 127) -- function button = volume menu
assert_eq(lastLog(), "LaunchpadProMK3: volume menu: dialog open (New Project)", "volume menu guarded")
L.HandleMIDICC(0, 4, 0)
mock.mpc.engineMode.CurrentPopup:set("No Popup")
L.HandleMIDICC(0, 90, 127) -- shift back on for the following shift-function tests

-- empty project (0 tracks) is still a project: quantize runs
mock.mpc.currentSequence = savedSeq
mock.mpc.tracks = savedTracks
mock.mpc.tracks.GetCount = function()
	return 0
end
mock.sequencer.GetBPM = savedGetBPM
L.HandleMIDICC(0, 40, 127)
assert_eq(lastLog(), "LaunchpadProMK3: quantize applied", "empty project still quantizes")
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

-- CC 96 (custom) is a stub.
mock.reset()
L.HandleMIDICC(0, 96, 127)
assert_eq(mock.count("InsertRowAndCapture"), 0, "custom button does not capture")
L.HandleMIDICC(0, 96, 0)

-- without Shift the buttons keep their primary functions
L.HandleMIDICC(0, 20, 127)
assert_eq(mock.count("Play"), 1, "play without shift")
L.HandleMIDICC(0, 20, 0)
L.HandleMIDICC(0, 10, 127)
assert_eq(mock.count("record.Press"), 1, "record without shift arms via the MPC REC button")
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

-- Loop/overdub LED indicators: play orange while loop is on, record orange while overdubbing.
mock.sequencer.RecordState:set(false) -- earlier record presses left recording armed
mock.sequencer.Loop:set(true)
assert_eq(mock.leds[20][1], 127, "play button orange while loop enabled")
assert_eq(mock.leds[20][2], 60, "play button orange g while loop enabled")
mock.sequencer.OverdubState:set(true)
assert_eq(mock.leds[10][1], 127, "record button orange while overdubbing")
assert_eq(mock.leds[10][2], 60, "record button orange g while overdubbing")
mock.sequencer.Loop:set(false)
mock.sequencer.OverdubState:set(false)
assert_eq(mock.leds[20][1], 12, "play button dim with loop off, stopped")
assert_eq(mock.leds[10][1], 12, "record button dim with overdub off")

-- RecordState on the device is a NUMBER (0 = off) and Lua treats 0 as true:
-- an unarmed record button must stay dim, an armed one red.
mock.sequencer.RecordState:set(0)
assert_eq(mock.leds[10][1], 12, "record button dim with numeric RecordState 0")
assert_eq(mock.leds[10][2], 12, "record button dim g with numeric RecordState 0")
mock.sequencer.RecordState:set(1)
assert_eq(mock.leds[10][1], 127, "record button red with numeric RecordState 1")
assert_eq(mock.leds[10][2], 0, "record button red g with numeric RecordState 1")
mock.sequencer.RecordState:set(false)

-- Quantize LED: cyan when the quantiser is on, white when available but off.
mock.sequencer.quantiser.Enabled:set(true)
assert_eq(mock.leds[40][1], 0, "quantize cyan r while quantiser on")
assert_eq(mock.leds[40][2], 127, "quantize cyan g while quantiser on")
assert_eq(mock.leds[40][3], 127, "quantize cyan b while quantiser on")
mock.sequencer.quantiser.Enabled:set(false)
assert_eq(mock.leds[40][1], 127, "quantize white while quantiser off")
assert_eq(mock.leds[40][2], 127, "quantize white g while quantiser off")
mock.sequencer.quantiser.Enabled:set(true)

-- Shift + CC 93 toggles follow mode (off by default).
local function logHas(s)
	for _, l in ipairs(logs) do
		if l == "LaunchpadProMK3: " .. s then
			return true
		end
	end
	return false
end
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 93, 127)
assert_eq(logHas("follow: on") and true or false, true, "follow toggle on")
assert_eq(mock.leds[93][3], 127, "session button cyan while follow is on")
assert_eq(mock.leds[93][1], 0, "session button cyan r while follow is on")
L.HandleMIDICC(0, 93, 127)
assert_eq(lastLog(), "LaunchpadProMK3: follow: off", "follow toggle off")
assert_eq(mock.leds[93][1], 127, "session button white again after follow off")
L.HandleMIDICC(0, 90, 0)

-- Shift + CC 98 = save via controlSurface.save.
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 98, 127)
assert_eq(mock.count("save.Press"), 1, "save pressed")
assert_eq(lastLog(), "LaunchpadProMK3: save", "save logged")
L.HandleMIDICC(0, 98, 0)
L.HandleMIDICC(0, 90, 0)
-- Unshifted CC 98 stays a stub.
mock.reset()
L.HandleMIDICC(0, 98, 127)
assert_eq(mock.count("save.Press"), 0, "no save without Shift")
assert_eq(lastLog(), "LaunchpadProMK3: projects: TODO", "projects stub log")

-- CC 97 opens the step seq view; Shift + CC 97 steps to the next bar.
mock.reset()
L.HandleMIDICC(0, 97, 127)
assert_eq(mock.count("stepSeq.Press"), 1, "stepSeq pressed")
assert_eq(lastLog(), "LaunchpadProMK3: step seq view", "step seq view logged")
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 97, 127)
assert_eq(mock.count("stepSeqNext.Press"), 1, "stepSeqNext pressed")
assert_eq(lastLog(), "LaunchpadProMK3: step seq: next", "step seq next logged")
L.HandleMIDICC(0, 90, 0)

local savedLoop = mock.mpc.sequencer.Loop
mock.mpc.sequencer.Loop = nil
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 20, 127)
assert_eq(lastLog(), "LaunchpadProMK3: loop unavailable: sequencer.Loop missing", "loop degrade")
L.HandleMIDICC(0, 20, 0)
L.HandleMIDICC(0, 90, 0)
mock.mpc.sequencer.Loop = savedLoop

-- Overdub degrade: without sequencer.Overdub, Shift + record logs once and harms nothing.
local savedOverdub = mock.mpc.sequencer.Overdub
mock.mpc.sequencer.Overdub = nil
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 10, 127)
assert_eq(lastLog(), "LaunchpadProMK3: overdub unavailable: sequencer.Overdub missing", "overdub degrade")
L.HandleMIDICC(0, 10, 0)
L.HandleMIDICC(0, 90, 0)
mock.mpc.sequencer.Overdub = savedOverdub

L.HandleMIDICC(0, 90, 127)
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
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 90, 0)

L.OnUnload()
_G.print = realPrint
print("test-buttons: PASS")
