-- tests/test-pad-modes.lua: MPC pads mode (CC 94) and track mute mode (CC 96).
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

-- Dark means the LED was never re-sent since the last mock.reset() (diff cache skips
-- black-on-black) or was sent black.
local function assert_dark(idx, msg)
	local l = mock.leds[idx]
	if l ~= nil and (l[1] ~= 0 or l[2] ~= 0 or l[3] ~= 0) then
		error(msg .. ": expected pad " .. idx .. " dark, got " .. l[1] .. "," .. l[2] .. "," .. l[3])
	end
end

-- Grid notes of the two pad modes: pads mode = bottom-left 4x4 quadrant,
-- mute mode = the bottom two rows.
local PAD_NOTES = { 11, 12, 13, 14, 21, 22, 23, 24, 31, 32, 33, 34, 41, 42, 43, 44 }
local MUTE_NOTES = { 11, 12, 13, 14, 15, 16, 17, 18, 21, 22, 23, 24, 25, 26, 27, 28 }

L.OnLoad()

-- Both mode buttons are available (lighter grey), not active.
assert_eq(mock.leds[94][1], 60, "note button available")
assert_eq(mock.leds[96][1], 60, "custom button available")

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
L.HandleTimer() -- tick 3 (odd): no mirror refresh yet
assert_eq(mock.leds[11], nil, "mirror waits for the 100 ms refresh (no resend)")
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
L.HandleMIDICC(0, 94, 127) -- pads mode closes the tempo page
L.HandleMIDICC(0, 90, 0) -- release Shift
L.HandleMIDICC(0, 80, 127)
assert_eq(mock.count("SetBPM"), 1, "tempo page closed by pads mode")
assert_eq(mock.count("MoveUp"), 1, "up moves the window again")

-- Exit pads mode (CC 94 again): the notes return to the script, clips launch.
mock.reset()
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "pads exit unbinds the pads")
assert_eq(mock.count("AddNoteToScript"), 16, "pads exit restores the notes")
for i, note in ipairs(PAD_NOTES) do
	assert_eq(mock.find("AddNoteToScript")[i].args[2], note, "pads exit restored note " .. i)
end
assert_eq(mock.leds[94][1], 60, "note button back to available")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch restored after pads exit")

-- Track mute mode (CC 96): the bottom two rows toggle the mutes of tracks 0-15.
mock.reset()
L.HandleMIDICC(0, 96, 127)
assert_eq(mock.count("AddNoteToTrackMute"), 16, "16 mute pads bound")
for i, note in ipairs(MUTE_NOTES) do
	local add = mock.find("AddNoteToTrackMute")[i]
	assert_eq(add.args[2], note, "mute enter note " .. i)
	assert_eq(add.args[3], i - 1, "mute enter track index " .. i)
end
assert_eq(mock.leds[96][1], 127, "custom button white in mute mode")
assert_eq(mock.leds[11][2], 127, "track 0 shows its colour when unmuted")
assert_dark(21, "track 8 dark with 8 tracks")

-- Muted pads turn dim grey on the next timer repaint.
mock.tracks[0].Mute.value = true
L.HandleTimer()
assert_eq(mock.leds[11][1], 15, "muted pad grey red")
assert_eq(mock.leds[11][2], 15, "muted pad grey green")
assert_eq(mock.leds[11][3], 15, "muted pad grey blue")
mock.tracks[0].Mute.value = false
L.HandleTimer()
assert_eq(mock.leds[11][2], 127, "unmuted pad back to the track colour")

-- Tracks beyond SizeNormalTracks stay dark.
mock.setNormalTrackCount(5)
L.HandleTimer()
assert_eq(mock.leds[16][1], 0, "track 7 dark beyond SizeNormalTracks")
assert_eq(mock.leds[16][2], 0, "track 7 dark green")
mock.setNormalTrackCount(8)
L.HandleTimer()

-- Mutual exclusion: CC 94 from mute mode switches straight to pads mode.
mock.reset()
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("RemoveNoteToTrackMute"), 16, "CC 94 exits mute mode")
assert_eq(mock.count("AddNoteToMpcPad"), 16, "CC 94 enters pads mode")
assert_eq(mock.leds[94][1], 127, "note button white")
assert_eq(mock.leds[96][1], 60, "custom button back to available")
mock.reset()
L.HandleMIDICC(0, 96, 127)
assert_eq(mock.count("AddNoteToTrackMute"), 16, "mute mode re-entered")

-- CC 93 session exits any mode back to the clip grid.
mock.reset()
L.HandleMIDICC(0, 93, 127)
assert_eq(mock.count("RemoveNoteToTrackMute"), 16, "session exits mute mode")
assert_eq(mock.leds[96][1], 60, "custom button back to available")
L.HandleMIDINoteOn(0, 21, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch restored after session")

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

-- Degrade: without mappings.tracks.mutes the custom button stays off.
local mutesMapping = mock.dev.mappings.tracks.mutes
mock.dev.mappings.tracks.mutes = nil
mock.reset()
L.HandleMIDICC(0, 96, 127)
assert_eq(mock.leds[96][1], 0, "custom button off without mappings.tracks.mutes")
assert_eq(mock.count("AddNoteToTrackMute"), 0, "no mute binding without mappings.tracks.mutes")
mock.dev.mappings.tracks.mutes = mutesMapping

-- Unload while mute mode is active: the notes are handed back before unmapping.
L.HandleMIDICC(0, 96, 127)
mock.reset()
L.OnUnload()
assert_eq(mock.count("RemoveNoteToTrackMute"), 16, "unload exits mute mode")
assert_eq(mock.count("AddNoteToScript"), 16, "unload restores the notes")

print("test-pad-modes: PASS")
