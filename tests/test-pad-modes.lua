-- tests/test-pad-modes.lua: MPC pads mode (CC 94).
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
-- notes STAY script-bound now: the script binding consumes them from the host's
-- MIDI-input feed (device report: pads double-fed a track listening on our port)
assert_eq(mock.count("RemoveNoteToScript"), 0, "notes stay bound to the script")
for i, note in ipairs(PAD_NOTES) do
	local add = mock.find("AddNoteToMpcPad")[i]
	assert_eq(add.args[1], 0, "pads enter channel " .. i)
	assert_eq(add.args[2], note, "pads enter note " .. i)
	assert_eq(add.args[3], i - 1, "pads enter pad index " .. i)
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
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "exit releases the pad bindings")
assert_eq(mock.count("AddNoteToScript"), 0, "script bindings were never removed")
assert_eq(mock.leds[94][1], 60, "note button back to available")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch restored after pads exit")

-- CC 96 is a stub (mutes live on CC 2 hold).
mock.reset()
L.HandleMIDICC(0, 96, 127)
assert_eq(mock.count("AddNoteToTrackMute"), 0, "no mute binding on CC 96")
assert_eq(mock.count("InsertRowAndCapture"), 0, "CC 96 does not capture (capture removed)")
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
assert_eq(mock.count("AddNoteToScript"), 0, "unload does not re-add (notes were never unbound)")
assert_eq(mock.count("RemoveNoteToScript"), 64, "unload unmaps the grid notes")

-- CC 95 (chord) is the keys page: pads mode from the grid, track-type aware.
-- Drum track (the mock default): plain kit play — Pad Perform is NEVER engaged
-- (its chord transform remaps a kit's pads and most go silent), and the press
-- opens no dialog.
mock.reset()
L.HandleMIDICC(0, 94, 127) -- enter pads mode (note button)
L.HandleMIDICC(0, 93, 127) -- session -> back out (clean slate)
mock.reset()
L.HandleMIDICC(0, 95, 127) -- chord -> keys page (drum track)
assert_eq(mock.count("AddNoteToMpcPad"), 16, "keys page enters pads mode (quadrant)")
assert_eq(mock.count("padPerform.Press"), 0, "no Pad Perform on a drum track")
assert_eq(mock.count("CloseCurrentPopup"), 0, "no dialog opened")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 0, "grid plays the kit, not clips")
L.HandleMIDICC(0, 95, 127) -- chord again: leave
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "keys page exits pads mode")
assert_eq(mock.count("padPerform.Press"), 0, "drum-track keys never touches Pad Perform")
assert_eq(mock.count("main.Press"), 2, "main pressed on keys enter (pad view) and exit")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip launch restored after keys exit")

-- Melodic track (Plugin): Pad Perform chords, every toggle press deferred two
-- ticks past the Main-screen transition (immediate presses get swallowed).
mock.mpc.tracks.currentTrack.Type:set("Plugin")
mock.reset()
local function tick2()
	L.HandleTimer()
	L.HandleTimer() -- the deferred padPerform press lands
end
L.HandleMIDICC(0, 95, 127) -- keys -> pads mode + Pad Perform
tick2()
assert_eq(mock.count("padPerform.Press"), 1, "melodic keys engages Pad Perform (deferred)")
assert_eq(mock.count("CloseCurrentPopup"), 0, "the Pad Perform page STAYS OPEN on enter (it is the feature's UI)")
-- repeated cycles: each entry must engage again
L.HandleMIDICC(0, 95, 127) -- leave
tick2()
assert_eq(mock.count("padPerform.Press"), 2, "exit toggles off (deferred)")
L.HandleMIDICC(0, 95, 127) -- enter AGAIN
tick2()
assert_eq(mock.count("padPerform.Press"), 3, "second entry engages Pad Perform again")
L.HandleMIDICC(0, 95, 127) -- leave
tick2()
assert_eq(mock.count("padPerform.Press"), 4, "second exit toggles off")
assert_eq(mock.count("main.Press"), 4, "main on every enter+exit")

-- THE DEVICE RULE: the page stays open only while keys owns AND the track is
-- melodic. Switching to a drum track while it is open drops the chords.
L.HandleMIDICC(0, 95, 127) -- enter keys (melodic)
tick2()
local closedBefore = mock.count("CloseCurrentPopup")
mock.setPopup("Pad Perform")
L.HandleTimer() -- still melodic -> stays open
assert_eq(mock.count("CloseCurrentPopup"), closedBefore, "page stays open on a melodic track")
mock.mpc.tracks.currentTrack.Type:set("Drum")
L.HandleTimer() -- demotion
assert_eq(mock.count("CloseCurrentPopup"), closedBefore + 1, "page closed on the drum switch")
assert_eq(L.STATE().keysPage, true, "keys page still owns (kit play)")
L.HandleMIDICC(0, 95, 127) -- leave for the sections below
tick2()
mock.setPopup("No Popup")
-- with the dialog closed, the surface stays live
L.HandleMIDICC(0, 93, 127) -- session works after the keys round trip
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip grid works after the keys round trip")
-- a dialog we did NOT open is never dismissed
mock.setPopup("New Project")
mock.reset()
L.HandleMIDICC(0, 95, 127)
assert_eq(mock.count("CloseCurrentPopup"), 0, "foreign dialogs are never closed")
assert_eq(mock.mpc.engineMode.GetCurrentPopup(), "New Project", "New Project dialog stays")
mock.setPopup("No Popup")
mock.mpc.tracks.currentTrack.Type:set("Drum")

-- ASYNC dialog (device report): the dialog opens a beat AFTER the exit press.
mock.mpc.tracks.currentTrack.Type:set("Plugin")
mock.reset()
L.HandleMIDICC(0, 95, 127) -- keys -> chords
tick2()
L.HandleMIDICC(0, 95, 127) -- leave
tick2()
mock.setPopup("Pad Perform") -- the dialog lands late
L.HandleTimer() -- watcher tick: inside the window
assert_eq(mock.mpc.engineMode.GetCurrentPopup(), "No Popup", "late dialog closed by the watcher")
assert_eq(mock.count("TriggerClip"), 0, "still in the keys-exit state")

-- PROACTIVE SWEEP: a stuck Pad Perform (popup open, flags clear) is swept by
-- any mode switch; the clean path presses nothing.
mock.setPopup("Pad Perform")
mock.reset()
L.HandleMIDICC(0, 93, 127) -- session
assert_eq(mock.count("CloseCurrentPopup"), 1, "session sweeps the stuck dialog")
assert_eq(mock.count("padPerform.Press"), 1, "session toggles the stuck mode off")
assert_eq(mock.mpc.engineMode.GetCurrentPopup(), "No Popup", "popup cleared")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), 1, "clip grid alive after the sweep")
-- note (drums) sweep
mock.setPopup("Pad Perform")
mock.reset()
L.HandleMIDICC(0, 94, 127)
assert_eq(mock.count("CloseCurrentPopup"), 1, "note sweeps the stuck dialog")
-- clean path: no popup, no flags -> no extra presses
mock.reset()
L.HandleMIDICC(0, 93, 127)
assert_eq(mock.count("padPerform.Press"), 0, "clean path presses nothing")
mock.mpc.tracks.currentTrack.Type:set("Drum")

-- Exiting pads mode (CC 93 session) no longer touches pad utilities.
mock.reset()
L.HandleMIDICC(0, 94, 127) -- enter pads mode
L.HandleMIDICC(0, 93, 127) -- session -> clip mode
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "session exits pads mode")
assert_eq(mock.count("noteRepeat.Press"), 0, "no utility presses on exit")
assert_eq(mock.count("keyboardControl.Press"), 0, "no page press on exit")
assert_eq(mock.count("padPerform.Press"), 0, "no padPerform press on exit")

-- Outside pads mode CC 95 opens the keys page (drum track: no Pad Perform).
mock.reset()
L.HandleMIDICC(0, 95, 127)
assert_eq(mock.count("AddNoteToMpcPad"), 16, "keys page from clip mode")
assert_eq(mock.count("padPerform.Press"), 0, "no Pad Perform on a drum track")
L.HandleMIDICC(0, 95, 127) -- leave again

-- Track type fixes the layout: drum tracks toggle drum <-> clip grid (2-state).
mock.reset()
L.HandleMIDICC(0, 94, 127) -- enter pads mode (drum track)
assert_eq(mock.count("AddNoteToMpcPad"), 16, "drum layout for a drum track")
mock.reset()
L.HandleMIDICC(0, 94, 127) -- exit (single tap, never chromatic)
assert_eq(mock.count("AddNoteToVirtualPad"), 0, "no chromatic on a drum track")
assert_eq(mock.count("RemoveNoteToMpcPad"), 16, "exit releases the pad bindings")
assert_eq(mock.count("AddNoteToScript"), 0, "script bindings were never removed")
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
assert_eq(mock.count("AddNoteToScript"), 0, "script bindings were never removed")
assert_eq(mock.count("bank1.Press"), 1, "leaving 64-pads resets the pad bank")
assert_eq(mock.count("AddNoteToMpcPad"), 0, "64-pads exit never binds drums")
mock.mpc.tracks.currentTrack.Type.value = "Drum"

print("test-pad-modes: PASS")
