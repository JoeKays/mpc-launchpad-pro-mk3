-- tests/test-pad-modes.lua: MPC pads mode (CC 94).
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

-- Grid notes of pads mode: the bottom-left 4x4 quadrant.
local PAD_NOTES = { 11, 12, 13, 14, 21, 22, 23, 24, 31, 32, 33, 34, 41, 42, 43, 44 }

L.OnLoad()

-- The note button is available (lighter grey); custom (CC 96) is a stub and stays off.
assert_eq(mock.leds[94][1], 60, "note button available")
assert_eq(mock.leds[96][1], 0, "custom button off (stub)")

-- Enter pads mode (CC 94): the 16 quadrant notes move from the script to the MPC pads.
-- A stopped clip sits under note 85 (grid col 4, MPC row 0) so the mode visibly darks it;
-- two timer ticks land the enter on an even tick.
mock.clips[4] = { [0] = "stopped" }
L.HandleTimer()
L.HandleTimer()
mock.reset()
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("AddNoteToMpcPad"), 16, "16 pads bound")
assert_eq(mock.count("RemoveNoteToScript"), 16, "16 notes unbound from the script")
for i, note in ipairs(PAD_NOTES) do
	local add = mock.find("AddNoteToMpcPad")[i]
	assert_eq(add.args[1], 0, "pads enter channel " .. i)
	assert_eq(add.args[2], note, "pads enter note " .. i)
	assert_eq(add.args[3], i - 1, "pads enter pad index " .. i)
	assert_eq(mock.find("RemoveNoteToScript")[i].args[2], note, "pads enter unbound note " .. i)
end
assert_eq(mock.leds[94][1], 127, "note button white in pads mode")
assert_eq(mock.leds[85][1], 0, "pad outside the quadrant went dark")

-- LED mirror: the refresh runs on even ticks (every 2 ticks = 100 ms).
mock.mpc.controlSurface.pads[0].Colour.value = 0x00FF0000 -- red
mock.mpc.controlSurface.pads[5].Colour.value = 0x11223344 -- alpha byte ignored
L.HandleTimer() -- tick 3 (odd): no mirror refresh yet (pad 0 stays dark from mode enter)
assert_eq(mock.leds[11] and mock.leds[11][1] or -1, 0, "mirror waits for the 100 ms refresh (no resend)")
L.HandleTimer() -- tick 4 (even): mirror refresh
assert_eq(mock.leds[11][1], 127, "pad 0 red mirrored")
assert_eq(mock.leds[22][1], 16, "pad 5 r scaled")
assert_eq(mock.leds[22][2], 25, "pad 5 g scaled")
assert_eq(mock.leds[22][3], 33, "pad 5 b scaled")

-- Diff-only sends: changing one pad resends only that pad.
mock.reset()
mock.mpc.controlSurface.pads[0].Colour.value = 0x0000FF00 -- green
L.HandleTimer() -- tick 3 (odd)
L.HandleTimer() -- tick 4 (even): only pad 0 changed
assert_eq(mock.leds[11][2], 127, "pad 0 now green")
assert_eq(mock.leds[22], nil, "unchanged pad 5 not resent (diff-only)")

-- Scene column and track row keep working; grid pads are inert in pads mode.
mock.reset()
L.HandleMIDICC(0, 89, 127)
assert_eq(mock.count("TriggerRow"), 1, "scene launch works in pads mode")
L.HandleMIDICC(0, 101, 127)
assert_eq(mock.count("SelectTrack"), 1, "track select works in pads mode")
L.HandleMIDINoteOn(0, 85, 100)
assert_eq(mock.count("TriggerClip"), 0, "grid pads inert in pads mode")

-- Mutual exclusion: opening the volume menu exits pads mode...
L.HandleMIDICC(0, 4, 127)
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "volume menu exits pads mode")
assert_eq(mock.leds[94][1], 60, "note button back to available")
local v0 = mock.tracks[0].Volume.value
L.HandleMIDICC(0, 80, 127)
assert_eq(mock.count("MoveUp"), 0, "up is a menu nudge while the menu is open")
assert(mock.tracks[0].Volume.value ~= v0, "menu nudge changed the volume")

-- ...and entering pads mode closes the volume menu.
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("AddNoteToMpcPad"), 16, "pads mode re-entered from the menu")
L.HandleMIDICC(0, 80, 127)
assert_eq(mock.count("MoveUp"), 1, "volume menu closed by pads mode (up moves the window)")

-- Mutual exclusion with the tempo page.
mock.reset()
L.HandleMIDICC(0, 90, 127) -- Shift
L.HandleMIDICC(0, 7, 127) -- tempo page exits pads mode
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "tempo page exits pads mode")
L.HandleMIDICC(0, 80, 127)
assert_eq(mock.count("SetBPM"), 1, "up changes BPM on the tempo page")
L.HandleMIDICC(0, 90, 0) -- release Shift (Shift+CC 94 is plugin preset prev, not mode toggle)
L.HandleMIDICC(0, 94, 127) -- pads mode closes the tempo page
L.HandleMIDICC(0, 80, 127)
assert_eq(mock.count("SetBPM"), 1, "tempo page closed by pads mode")
assert_eq(mock.count("MoveUp"), 1, "up moves the window again")

-- Exiting to the clip grid is one tap (the drum track never offers chromatic).
mock.reset()
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("AddNoteToVirtualPad"), 0, "no chromatic on a drum track")
assert_eq(mock.count("AddNoteToScript"), 16, "exit restores the drum notes")
assert_eq(mock.leds[94][1], 60, "note button back to available")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch restored after pads exit")

-- CC 96 is a stub again (mutes live on the CC 2 hold-function).
mock.reset()
L.HandleMIDICC(0, 96, 127)
assert_eq(mock.count("AddNoteToTrackMute"), 0, "no mute binding: CC 96 is a stub")
assert_eq(mock.leds[96] and mock.leds[96][1] or 0, 0, "custom button off (stub)")
L.HandleMIDINoteOn(0, 21, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch unaffected by CC 96")

-- Degrade: without mappings.pads the note button stays off and nothing breaks.
local padsMapping = mock.dev.mappings.pads
mock.dev.mappings.pads = nil
mock.reset()
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.leds[94][1], 0, "note button off without mappings.pads")
assert_eq(mock.count("AddNoteToMpcPad"), 0, "no pad binding without mappings.pads")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch still works after failed pads mode")
mock.dev.mappings.pads = padsMapping

-- Unload while pads mode is active: the notes are handed back before unmapping.
L.HandleMIDICC(0, 94, 127)
mock.reset()
L.OnUnload()
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "unload exits pads mode")
assert_eq(mock.count("AddNoteToScript"), 16, "unload restores the notes")

-- CC 95 cycles the MPC's pad utilities while MPC Pads mode is open: off -> note repeat -> full level -> off.
mock.reset()
L.HandleMIDICC(0, 94, 127) -- enter pads mode
L.HandleMIDICC(0, 95, 127) -- cycle: note repeat on
assert_eq(mock.count("noteRepeat.Press"), 1, "noteRepeat pressed")
assert_eq(mock.leds[95][1], 127, "chord button white while note repeat on")
L.HandleMIDICC(0, 95, 127) -- cycle: note repeat off, full level on
assert_eq(mock.count("noteRepeat.Press"), 2, "noteRepeat toggled off")
assert_eq(mock.count("fullLevel.Press"), 1, "fullLevel pressed")
L.HandleMIDICC(0, 95, 127) -- cycle: full level off
assert_eq(mock.count("fullLevel.Press"), 2, "fullLevel toggled off")
assert_eq(mock.leds[95] and mock.leds[95][1] or 0, 60, "chord button back to available")

-- Exiting pads mode (CC 93 session) clears the active utility and returns to the clip grid.
mock.reset()
L.HandleMIDICC(0, 95, 127) -- note repeat on again
assert_eq(mock.count("noteRepeat.Press"), 1, "note repeat on")
L.HandleMIDICC(0, 93, 127) -- session -> clip mode
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "session exits pads mode")
assert_eq(mock.count("noteRepeat.Press"), 2, "utility cleared on exit")
assert_eq(mock.leds[95] and mock.leds[95][1] or 0, 0, "chord button off outside pads mode")

-- Outside pads mode the cycle is a no-op with a log.
mock.reset()
L.HandleMIDICC(0, 95, 127)
assert_eq(mock.count("noteRepeat.Press"), 0, "no pad utility outside pads mode")

-- Track type fixes the layout: drum tracks toggle drum <-> clip grid (2-state).
mock.reset()
L.HandleMIDICC(0, 94, 127) -- enter pads mode (drum track)
assert_eq(mock.count("AddNoteToMpcPad"), 16, "drum layout for a drum track")
mock.reset()
L.HandleMIDICC(0, 94, 127) -- exit (single tap, never chromatic)
assert_eq(mock.count("AddNoteToVirtualPad"), 0, "no chromatic on a drum track")
assert_eq(mock.count("AddNoteToScript"), 16, "exit restores the drum notes")
assert_eq(mock.leds[94][1], 60, "note button back to available")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch restored after pads exit")

-- Melodic tracks toggle 64-pads <-> clip grid (2-state, row-major banks A-H).
mock.reset()
mock.mpc.tracks.currentTrack.Type.value = "Plugin"
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("AddNoteToMpcPad"), 0, "no drum binding on a plugin track")
assert_eq(mock.count("AddNoteToVirtualPad"), 64, "64 virtual pads bound")
local all = mock.find("AddNoteToVirtualPad")
assert_eq(all[1].args[3], 0, "bottom-left = pad 1 (bank A)")
assert_eq(all[8].args[3], 7, "bottom-right = pad 8 (bank A)")
assert_eq(all[9].args[3], 8, "second row starts bank B")
assert_eq(all[64].args[3], 63, "top-right = pad 64 (bank H)")
assert_eq(mock.leds[94][2], 127, "note button cyan in the 64-pads layout")
assert_eq(mock.leds[94][1], 0, "note button cyan r")

-- virtual pad colours light the whole grid (timer refresh paints)
mock.mpc.controlSurface.pads.virtual[0].Colour.value = 0x00FF0000
mock.mpc.controlSurface.pads.virtual[40].Colour.value = 0x0000FF00
L.HandleTimer()
L.HandleTimer()
assert_eq(mock.leds[12][3], 30, "uncoloured pad keeps the dim blue tint")
assert_eq(mock.leds[11][1], 127, "virtual pad 1 colour mirrored r")
assert_eq(mock.leds[11][2], 0, "virtual pad 1 colour mirrored g")
assert_eq(mock.leds[61][2], 127, "virtual pad 41 colour mirrored g (row 6)")
-- exit: single tap, restores all notes and resets the MPC pad bank
mock.reset()
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("RemoveNoteToVirtualPad"), 64, "exit unbinds the virtual pads")
assert_eq(mock.count("AddNoteToScript"), 64, "exit restores the notes")
assert_eq(mock.count("bank1.Press"), 1, "leaving 64-pads resets the pad bank")
assert_eq(mock.count("AddNoteToMpcPad"), 0, "64-pads exit never binds drums")
mock.mpc.tracks.currentTrack.Type.value = "Drum"

print("test-pad-modes: PASS")
