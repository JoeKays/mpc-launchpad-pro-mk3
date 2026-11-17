-----------------------------------------------------------------------------------------------
-- LaunchpadProMK3.lua
-- Novation Launchpad Pro MK3 as a controller surface for Akai MPC 3.10.1 (Gen2, MPC Live III).
--
-- Programmer mode. The LPP3 sends grid pads as notes 11-88 (bottom-left first) and the edge
-- buttons as CCs. LEDs are driven by MPC state (property listeners + a 250 ms timer), never by
-- the button press alone.
--
-- Mapping (user-supplied, authoritative):
--   grid notes 11-88     8x8 clip window: launch (TriggerClip); Shift+pad = select (SelectClip)
--   bottom row CC 1-8    scene launch (TriggerRow 0-7)
--   track buttons CC 101-108
--                        101 record arm / Shift undo
--                        102 mute       / Shift redo
--                        103 solo       / Shift click (metronome)
--                        104 volume     (stub)
--                        105 pan        (stub)
--                        106 sends      / Shift tap tempo
--                        107 device     / Shift tempo
--                        108 stop clip  / Shift swing
--   right column CC 19-89 + 99
--                        99 novation logo (status/home; Shift = probe mode)
--                        89 patterns, 79 steps, 69 pattern settings,
--                        59 velocity, 49 probability, 39 mutation, 29 micro step, 19 print to clip
--   top row CC 90-98     90 shift, 91 <, 92 >, 93 session, 94 note, 95 chord,
--                        96 custom, 97 sequencer, 98 projects/save
--   left column CC 10-80 10 record/capture midi, 20 play, 30 fixed length,
--                        40 quantize/record quantize, 50 duplicate/double, 60 clear,
--                        70 down, 80 up
--
-- LED protocol: F0 00 20 29 02 0E 03 <spec>... F7; spec = <type> <index> <data>.
--   type 0 = static palette (1 byte), 1 = flashing (2 bytes), 2 = pulsing (1 byte),
--   type 3 = RGB (3 bytes, 0-127). SendMIDISysex takes the payload without F0/F7.
--
-- Degrade, never break: every optional API is guarded; a missing feature disables its surface.
-----------------------------------------------------------------------------------------------

local deviceName = "LaunchpadProMK3" -- must match the file name
local port = 0 -- the one LPP3 output (order of output= lines in the .ini)
local dev = LaunchpadProMK3

-- LPP3 Programmer-mode layout
local GRID_NOTE0 = 11 -- notes 11-88, bottom-left first
local GRID_COLS, GRID_ROWS = 8, 8
local TOP = {
	shift = 90,
	left = 91,
	right = 92,
	session = 93,
	note = 94,
	chord = 95,
	custom = 96,
	sequencer = 97,
	save = 98,
}
local RIGHT = {
	logo = 99,
	patterns = 89,
	steps = 79,
	patternSettings = 69,
	velocity = 59,
	probability = 49,
	mutation = 39,
	microStep = 29,
	printToClip = 19,
}
local LEFT = { record = 10, play = 20, fixedLength = 30, quantize = 40, duplicate = 50, clear = 60, down = 70, up = 80 }
local TRACK = {
	recArm = 1,
	mute = 2,
	solo = 3,
	volume = 4,
	pan = 5,
	sends = 6,
	device = 7,
	stopClip = 8,
}
local TRACK_FN = {
	[TRACK.recArm] = "recArm",
	[TRACK.mute] = "mute",
	[TRACK.solo] = "solo",
	[TRACK.volume] = "volume",
	[TRACK.pan] = "pan",
	[TRACK.sends] = "sends",
	[TRACK.device] = "device",
	[TRACK.stopClip] = "stopClip",
}
local SCENE = { 89, 79, 69, 59, 49, 39, 29, 19 }

-- Clip state enum (order confirmed by the stock MPK script and mpc-3-ce Gen1 enum)
local S = {
	NoSlot = 0,
	Empty = 1,
	Ready = 2,
	WillPlay = 3,
	Playing = 4,
	WillStopPlaying = 5,
	WillRecord = 6,
	Recording = 7,
	WillStopRecording = 8,
	WillOverdub = 9,
	Overdubbing = 10,
	WillStopOverdubbing = 11,
}

-- LED colours (RGB 0-127)
local C = {
	off = { 0, 0, 0 },
	dim = { 12, 12, 12 },
	white = { 127, 127, 127 },
	green = { 0, 127, 0 },
	red = { 127, 0, 0 },
	orange = { 127, 60, 0 },
	blue = { 0, 60, 127 },
	cyan = { 0, 127, 127 },
	magenta = { 127, 0, 127 },
	yellow = { 127, 127, 0 },
}

-- State
local aperture, clipProps
local shift = false
local mode = "clip" -- clip / transport / track / probe
local originCol, originRow = 0, 0
local padCache = {} -- LED index -> "r,g,b" last sent
local ledSpecs = {} -- accumulated specs for the current flush
local ticks = 0
local blinkOn = false
local probeMode = false
local heldFunction = nil
local adjustMode = nil -- nil / "volume" / "pan" / "sends" (menu mode)
local adjustSend = 1 -- 1..4, the active send in sends mode
local adjustCol = 0 -- last grid column touched in the menu (for up/down nudges)
local clipOp = nil -- nil / "duplicate" / "clear"
local clipOrigin = nil -- {col, row} for duplicate
local priorLayout, priorPage = nil, nil
local programmerEntered = false
local layoutQuerySent = false
local lastLog = {}

-----------------------------------------------------------------------------------------------
-- Utilities
-----------------------------------------------------------------------------------------------

local function log(msg)
	pcall(function()
		print(deviceName .. ": " .. tostring(msg))
	end)
end

local function logOnce(key, msg)
	if lastLog[key] then
		return
	end
	lastLog[key] = true
	log(msg)
end

local function call(f, ...)
	if type(f) ~= "function" then
		return nil
	end
	local ok, r = pcall(f, ...)
	if ok then
		return r
	end
	return nil
end

local function propValue(obj, name)
	local p = obj and obj[name]
	if p == nil then
		return nil
	end
	local ok, v = pcall(function()
		return p.value
	end)
	if ok then
		return v
	end
	return nil
end

local function clamp01(v)
	v = tonumber(v) or 0
	if v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

local function trackAt(idx)
	return mpc.tracks and mpc.tracks.normalTracks and mpc.tracks.normalTracks[idx]
end

local function adjustPropName()
	if adjustMode == "volume" then
		return "Volume"
	elseif adjustMode == "pan" then
		return "Pan"
	elseif adjustMode == "sends" then
		return "Send" .. adjustSend
	end
	return nil
end

local function argb(c)
	c = tonumber(c) or 0
	return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
end

local function scale7(v)
	v = tonumber(v) or 0
	if v < 0 then
		v = 0
	elseif v > 255 then
		v = 255
	end
	return math.floor(v * 127 / 255)
end

local function rgbKey(r, g, b)
	return r .. "," .. g .. "," .. b
end

-- Global matrix position of a window cell
local function globalPos(col, row)
	if aperture then
		local gc = call(aperture.ToGlobalColumn, col)
		local gr = call(aperture.ToGlobalRow, row)
		if type(gc) == "number" and type(gr) == "number" then
			return gc, gr
		end
	end
	return col + (originCol or 0), row + (originRow or 0)
end

-- Clip status: 0 = no clip, 1 = stopped, 2 = playing/recording, 3 = queued
local function clipStatus(col, row)
	local m = mpc.clipMatrix
	if not (m and m.HasClip) then
		return 0
	end
	local gc, gr = globalPos(col, row)
	local has = call(m.HasClip, gc, gr)
	if not has then
		return 0, gc, gr
	end
	if call(m.ClipIsPlaying, gc, gr) or call(m.ClipIsRecording, gc, gr) then
		return 2, gc, gr
	end
	if call(m.ClipIsStopped, gc, gr) then
		return 1, gc, gr
	end
	return 3, gc, gr
end

local function clipColour(col, row)
	local p = clipProps and clipProps[col] and clipProps[col][row]
	local c = propValue(p, "Colour")
	if type(c) == "number" and c ~= 0 then
		return c
	end
	local m = mpc.clipMatrix
	if m and m.GetClipColour then
		local gc, gr = globalPos(col, row)
		local v = call(m.GetClipColour, gc, gr)
		if type(v) == "number" then
			return v
		end
	end
	return 0x808080
end

-----------------------------------------------------------------------------------------------
-- LED output
-----------------------------------------------------------------------------------------------

local function addSpec(spec)
	ledSpecs[#ledSpecs + 1] = spec
end

local function ledRGB(index, r, g, b)
	index = tonumber(index)
	if not index then
		return
	end
	r, g, b = math.floor(tonumber(r) or 0), math.floor(tonumber(g) or 0), math.floor(tonumber(b) or 0)
	if r < 0 then
		r = 0
	elseif r > 127 then
		r = 127
	end
	if g < 0 then
		g = 0
	elseif g > 127 then
		g = 127
	end
	if b < 0 then
		b = 0
	elseif b > 127 then
		b = 127
	end
	local key = rgbKey(r, g, b)
	if padCache[index] == key then
		return
	end
	padCache[index] = key
	addSpec(string.char(3, index % 128, r, g, b))
end

local function ledOff(index)
	ledRGB(index, 0, 0, 0)
end

local function flushLEDs()
	if #ledSpecs == 0 then
		return
	end
	local header = string.char(0x00, 0x20, 0x29, 0x02, 0x0E, 0x03)
	-- one message per flush; the LPP3 accepts up to 106 specs
	local ok = pcall(function()
		dev.midiOut.SendMIDISysex(header .. table.concat(ledSpecs), port)
	end)
	if not ok then
		logOnce("sysex", "SendMIDISysex failed")
	end
	ledSpecs = {}
end

-- LPP3 layout control: enter Programmer mode (0x11) and restore the prior layout.
local function sendLayout(layout, page)
	local ok = pcall(function()
		dev.midiOut.SendMIDISysex(string.char(0x00, 0x20, 0x29, 0x02, 0x0E, 0x00, layout, page, 0x00), port)
	end)
	if not ok then
		logOnce("layout", "layout sysex failed")
	end
end

local function queryLayout()
	local ok = pcall(function()
		dev.midiOut.SendMIDISysex(string.char(0x00, 0x20, 0x29, 0x02, 0x0E, 0x00), port)
	end)
	if not ok then
		logOnce("layoutq", "layout query failed")
	end
end

-----------------------------------------------------------------------------------------------
-- Painting
-----------------------------------------------------------------------------------------------

local function paintAdjustGrid()
	local colour = C.cyan
	if adjustMode == "pan" then
		colour = C.magenta
	elseif adjustMode == "sends" then
		colour = C.yellow
	end
	local name = adjustPropName()
	for col = 0, GRID_COLS - 1 do
		local gc = globalPos(col, 0)
		local t = trackAt(gc)
		if t then
			local value = propValue(t, name) or 0
			if type(value) ~= "number" then
				value = 0
			end
			local litCount = math.floor(value * GRID_ROWS + 0.5)
			for row = 0, GRID_ROWS - 1 do
				local idx = 10 * (8 - row) + col + 1
				local fromBottom = 7 - row
				if fromBottom < litCount then
					ledRGB(idx, colour[1], colour[2], colour[3])
				else
					ledRGB(idx, C.dim[1], C.dim[2], C.dim[3])
				end
			end
		else
			for row = 0, GRID_ROWS - 1 do
				ledOff(10 * (8 - row) + col + 1)
			end
		end
	end
end

local function paintGrid()
	if adjustMode then
		paintAdjustGrid()
		return
	end
	for row = 0, GRID_ROWS - 1 do
		for col = 0, GRID_COLS - 1 do
			local idx = 10 * (8 - row) + col + 1
			local status = clipStatus(col, row)
			if status == 0 then
				ledOff(idx)
			else
				local c = clipColour(col, row)
				local r, g, b = argb(c)
				local k = 1.0
				if status == 1 then
					k = 0.18
				elseif status == 3 then
					k = blinkOn and 0.9 or 0.18
				elseif status == 2 then
					k = 0.95
				end
				ledRGB(idx, scale7(r * k), scale7(g * k), scale7(b * k))
			end
		end
	end
end

local function paintScene()
	for row = 0, 7 do
		local idx = SCENE[row + 1]
		local state = nil
		if aperture and aperture.sceneProperties and aperture.sceneProperties[row] then
			state = propValue(aperture.sceneProperties[row], "State")
		end
		if state == S.Playing or state == S.Recording then
			ledRGB(idx, C.green[1], C.green[2], C.green[3])
		elseif state == S.WillPlay or state == S.WillRecord then
			ledRGB(
				idx,
				blinkOn and C.green[1] or C.dim[1],
				blinkOn and C.green[2] or C.dim[2],
				blinkOn and C.green[3] or C.dim[3]
			)
		else
			ledRGB(idx, C.dim[1], C.dim[2], C.dim[3])
		end
	end
end

local function paintTrack()
	-- CC 1-8: function buttons; the held or adjusted one bright, others dim.
	local function fnColour(fn)
		if heldFunction == fn or adjustMode == fn then
			return C.white
		else
			return C.dim
		end
	end
	local arm = fnColour("recArm")
	local mute = fnColour("mute")
	local solo = fnColour("solo")
	local volume = fnColour("volume")
	local pan = fnColour("pan")
	local sends = fnColour("sends")
	ledRGB(TRACK.recArm, arm[1], arm[2], arm[3])
	ledRGB(TRACK.mute, mute[1], mute[2], mute[3])
	ledRGB(TRACK.solo, solo[1], solo[2], solo[3])
	ledRGB(TRACK.volume, volume[1], volume[2], volume[3])
	ledRGB(TRACK.pan, pan[1], pan[2], pan[3])
	ledRGB(TRACK.sends, sends[1], sends[2], sends[3])
	ledRGB(TRACK.device, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(TRACK.stopClip, C.dim[1], C.dim[2], C.dim[3])
	-- CC 101-108: track buttons. Show the held function's state per track, or the track colour.
	for col = 0, 7 do
		local gc = globalPos(col, 0)
		local t = mpc.tracks and mpc.tracks.normalTracks and mpc.tracks.normalTracks[gc]
		local r, g, b = C.dim[1], C.dim[2], C.dim[3]
		if t then
			if heldFunction == "mute" then
				if propValue(t, "Mute") then
					r, g, b = C.orange[1], C.orange[2], C.orange[3]
				end
			elseif heldFunction == "solo" then
				if propValue(t, "Solo") then
					r, g, b = C.yellow[1], C.yellow[2], C.yellow[3]
				end
			elseif heldFunction == "recArm" then
				if propValue(t, "RecArm") then
					r, g, b = C.red[1], C.red[2], C.red[3]
				end
			else
				local c = propValue(t, "Colour")
				if type(c) == "number" then
					local cr, cg, cb = argb(c)
					r, g, b = scale7(cr * 0.3), scale7(cg * 0.3), scale7(cb * 0.3)
				end
			end
		end
		if t then
			ledRGB(101 + col, r, g, b)
		else
			ledOff(101 + col)
		end
	end
end

local function paintTop()
	local function modeColour(m)
		if mode == m then
			return C.white
		else
			return C.dim
		end
	end
	local session = modeColour("clip")
	local sequencer = modeColour("step")
	local note = modeColour("note")
	local chord = modeColour("chord")
	local custom = modeColour("custom")
	ledRGB(TOP.session, session[1], session[2], session[3])
	ledRGB(TOP.sequencer, sequencer[1], sequencer[2], sequencer[3])
	ledRGB(TOP.note, note[1], note[2], note[3])
	ledRGB(TOP.chord, chord[1], chord[2], chord[3])
	ledRGB(TOP.custom, custom[1], custom[2], custom[3])
	ledRGB(TOP.left, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(TOP.right, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(TOP.save, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(
		TOP.shift,
		shift and C.white[1] or C.dim[1],
		shift and C.white[2] or C.dim[2],
		shift and C.white[3] or C.dim[3]
	)
end

local function paintLeft()
	local sq = mpc.sequencer
	local playing = sq and call(sq.IsPlaying) or propValue(sq, "Playing")
	local recording = propValue(sq, "RecordState")
	local overdub = propValue(sq, "OverdubState")
	local rec = recording or overdub
	ledRGB(
		LEFT.play,
		playing and C.green[1] or C.dim[1],
		playing and C.green[2] or C.dim[2],
		playing and C.green[3] or C.dim[3]
	)
	ledRGB(LEFT.record, rec and C.red[1] or C.dim[1], rec and C.red[2] or C.dim[2], rec and C.red[3] or C.dim[3])
	ledRGB(LEFT.fixedLength, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(LEFT.quantize, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(LEFT.duplicate, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(LEFT.clear, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(LEFT.down, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(LEFT.up, C.dim[1], C.dim[2], C.dim[3])
end

local function paintRight()
	-- the right column CC 19-89 is the scene row (painted by paintScene);
	-- only the Novation logo (CC 99) is painted here.
	ledRGB(
		RIGHT.logo,
		probeMode and C.cyan[1] or C.dim[1],
		probeMode and C.cyan[2] or C.dim[2],
		probeMode and C.cyan[3] or C.dim[3]
	)
end

local function paintAll()
	paintGrid()
	paintScene()
	paintTrack()
	paintTop()
	paintLeft()
	paintRight()
	flushLEDs()
end

-----------------------------------------------------------------------------------------------
-- Listeners
-----------------------------------------------------------------------------------------------

local listeners = {}

local function listen(prop, fn)
	if prop and type(prop.listen) == "function" then
		local ok = pcall(function()
			prop:listen(fn, deviceName)
		end)
		if ok then
			listeners[#listeners + 1] = prop
		end
	end
end

local function listenAll()
	if clipProps then
		for col = 0, GRID_COLS - 1 do
			for row = 0, GRID_ROWS - 1 do
				local p = clipProps[col] and clipProps[col][row]
				if p then
					listen(p.Colour, function()
						paintGrid()
						flushLEDs()
					end)
					listen(p.State, function()
						paintGrid()
						flushLEDs()
					end)
				end
			end
		end
	end
	if aperture and aperture.sceneProperties then
		for row = 0, 7 do
			local p = aperture.sceneProperties[row]
			if p then
				listen(p.State, function()
					paintScene()
					flushLEDs()
				end)
			end
		end
	end
	local tracks = mpc.tracks and mpc.tracks.normalTracks
	if tracks then
		for i = 0, 7 do
			local t = tracks[i]
			if t then
				listen(t.Mute, function()
					paintTrack()
					flushLEDs()
				end)
				listen(t.Solo, function()
					paintTrack()
					flushLEDs()
				end)
				listen(t.RecArm, function()
					paintTrack()
					flushLEDs()
				end)
			end
		end
	end
	local sq = mpc.sequencer
	if sq then
		listen(sq.Playing, function()
			paintLeft()
			flushLEDs()
		end)
		listen(sq.RecordState, function()
			paintLeft()
			flushLEDs()
		end)
		listen(sq.OverdubState, function()
			paintLeft()
			flushLEDs()
		end)
	end
end

local function removeListeners()
	for _, prop in ipairs(listeners) do
		if prop and type(prop.stopListening) == "function" then
			pcall(function()
				prop:stopListening(deviceName)
			end)
		end
	end
	listeners = {}
end

-----------------------------------------------------------------------------------------------
-- Actions
-----------------------------------------------------------------------------------------------

local function setMode(m)
	mode = m
	log("mode -> " .. m)
	paintAll()
end

local function doClip(col, row)
	if not aperture then
		return
	end
	if shift then
		call(aperture.SelectClip, col, row)
		log(string.format("SelectClip(%d,%d)", col, row))
	else
		call(aperture.SelectClip, col, row)
		call(aperture.TriggerClip, col, row)
		log(string.format("TriggerClip(%d,%d)", col, row))
	end
end

local function doScene(row)
	if not aperture then
		return
	end
	call(aperture.TriggerRow, row)
	log("TriggerRow(" .. row .. ")")
end

-- Shift + right-column button: the label functions (patterns/steps/...).
local function handleRightLabel(row)
	if row == 0 then
		setMode("clip")
	elseif row == 1 then
		setMode("step")
	elseif row == 2 then
		setMode("track")
	else
		log("page " .. row .. ": TODO")
	end
end

-- Apply a held function (mute/solo/recArm/...) to a specific track index.
local function applyFunction(fn, idx)
	local t = mpc.tracks and mpc.tracks.normalTracks and mpc.tracks.normalTracks[idx]
	if not t then
		logOnce("track", "no track " .. tostring(idx))
		return
	end
	if fn == "recArm" then
		local v = propValue(t, "RecArm")
		call(t.SetRecArm, not v)
		log("SetRecArm(" .. tostring(not v) .. ") track " .. idx)
	elseif fn == "mute" then
		local v = propValue(t, "Mute")
		call(t.SetMute, not v)
		log("SetMute(" .. tostring(not v) .. ") track " .. idx)
	elseif fn == "solo" then
		local v = propValue(t, "Solo")
		call(t.SetSolo, not v)
		log("SetSolo(" .. tostring(not v) .. ") track " .. idx)
	elseif fn == "stopClip" then
		call(aperture and aperture.StopClipsOnTrack, idx)
		log("StopClipsOnTrack(" .. idx .. ")")
	else
		log(fn .. ": unsupported track function " .. idx)
	end
end

-- Select a track (bottom-row CC 1-8 without a held function).
local function selectTrack(idx)
	if aperture then
		call(aperture.SelectTrack, idx)
		log("SelectTrack(" .. idx .. ")")
	end
end

-- Write a track property (Volume/Pan/Send1-4) through its .value, guarded.
local function setTrackValue(idx, name, v)
	local t = trackAt(idx)
	if not t then
		logOnce("track", "no track " .. tostring(idx))
		return
	end
	local p = t[name]
	if p == nil then
		logOnce("prop" .. name, name .. " MISSING on track " .. tostring(idx))
		return
	end
	local value = clamp01(v)
	local ok = pcall(function()
		p.value = value
	end)
	if not ok then
		logOnce("set" .. name, "set " .. name .. " failed on track " .. tostring(idx))
		return
	end
	log(string.format("%s track %d = %.3f", name, idx, value))
end

local function nudgeAdjust(delta)
	if not adjustMode then
		return
	end
	local gc = globalPos(adjustCol, 0)
	local name = adjustPropName()
	if not name then
		return
	end
	local cur = propValue(trackAt(gc), name)
	if type(cur) ~= "number" then
		cur = 0
	end
	setTrackValue(gc, name, cur + delta)
	paintAll()
end

local function enterAdjust(newMode)
	adjustMode = newMode
	adjustCol = 0
	if newMode == "sends" then
		adjustSend = 1
	end
	log("menu " .. newMode)
	paintAll()
end

local function exitAdjust()
	if adjustMode then
		adjustMode = nil
		log("menu off")
		paintAll()
	end
end

local function handleAdjustPad(col, row)
	if not adjustMode then
		return
	end
	local value = (GRID_ROWS - row) / GRID_ROWS
	adjustCol = col
	local gc = globalPos(col, 0)
	local name = adjustPropName()
	if name then
		setTrackValue(gc, name, value)
		paintAll()
	end
end

-- Shift + a function button: the shift function (undo/redo/click/tap/tempo/swing).
-- Shift is checked before the held-function state, so these run even while another
-- function button is held; the held function is left untouched.
local function doShiftFunction(fn)
	if fn == "recArm" then
		local cm = mpc.commandManager
		if cm and type(cm.Undo) == "function" then
			call(cm.Undo)
			log("Undo")
		else
			logOnce("undo", "Undo unavailable: commandManager.Undo missing")
		end
	elseif fn == "mute" then
		local cm = mpc.commandManager
		if cm and type(cm.Redo) == "function" then
			call(cm.Redo)
			log("Redo")
		else
			logOnce("redo", "Redo unavailable: commandManager.Redo missing")
		end
	elseif fn == "solo" then
		local sq = mpc.sequencer
		local me = propValue(sq, "MetronomeEnabled")
		if sq and type(sq.SetMetronomeEnabled) == "function" then
			call(sq.SetMetronomeEnabled, not me)
			log("Metronome " .. tostring(not me))
		else
			logOnce("metronome", "metronome unavailable: sequencer.SetMetronomeEnabled missing")
		end
	elseif fn == "sends" then
		log("tap tempo: TODO")
	elseif fn == "device" then
		log("tempo: TODO")
	elseif fn == "stopClip" then
		log("swing: TODO")
	else
		log(fn .. " shift: TODO")
	end
end

local function doTransport(fn)
	local sq = mpc.sequencer
	if fn == "play" then
		local playing = sq and call(sq.IsPlaying) or propValue(sq, "Playing")
		if playing then
			call(sq and sq.Stop)
			log("Stop")
		else
			call(sq and sq.Play)
			log("Play")
		end
	elseif fn == "record" then
		call(sq and sq.Record)
		log("Record")
	end
end

local function moveWindow(dir, n)
	if not aperture then
		return
	end
	local fn = ({ left = "MoveLeft", right = "MoveRight", up = "MoveUp", down = "MoveDown" })[dir]
	if fn then
		call(aperture[fn], n)
		log(fn .. "(" .. n .. ")")
		padCache = {}
		paintAll()
	end
end

local function probe(note, cc, value)
	log(string.format("PROBE note=%s cc=%s value=%s", tostring(note), tostring(cc), tostring(value)))
	if note then
		ledRGB(note, C.white[1], C.white[2], C.white[3])
	end
	if cc then
		ledRGB(cc, C.white[1], C.white[2], C.white[3])
	end
	flushLEDs()
end

-----------------------------------------------------------------------------------------------
-- Input handlers
-----------------------------------------------------------------------------------------------

local function noteIndex(note)
	if note >= GRID_NOTE0 and note <= GRID_NOTE0 + 77 then
		local i = note - GRID_NOTE0
		local padRow = math.floor(i / 10)
		local col = i % 10
		if col < 8 and padRow < 8 then
			return col, 7 - padRow -- col, MPC row (0 = top)
		end
	end
	return nil
end

function LaunchpadProMK3.HandleMIDINoteOn(channel, note, velocity)
	if channel ~= 0 then
		return
	end
	if probeMode then
		probe(note, nil, velocity)
		return
	end
	local col, row = noteIndex(note)
	if col then
		if velocity > 0 then
			if clipOp == "clear" then
				call(mpc.clipMatrix and mpc.clipMatrix.DeleteClip, col, row)
				log(string.format("DeleteClip(%d,%d)", col, row))
				clipOp = nil
				paintAll()
			elseif clipOp == "duplicate" then
				if clipOrigin == nil then
					clipOrigin = { col, row }
					log(string.format("duplicate origin (%d,%d)", col, row))
				else
					call(mpc.clipMatrix and mpc.clipMatrix.CopyClip, clipOrigin[1], clipOrigin[2], col, row)
					log(string.format("CopyClip(%d,%d -> %d,%d)", clipOrigin[1], clipOrigin[2], col, row))
					clipOp = nil
					clipOrigin = nil
					paintAll()
				end
			elseif adjustMode then
				handleAdjustPad(col, row)
			else
				doClip(col, row)
			end
		end
		return
	end
end

function LaunchpadProMK3.HandleMIDINoteOff(_channel, _note, _velocity)
	-- LPP3 sends Note On with velocity 0 for Note Off; nothing to do here
end

function LaunchpadProMK3.HandleMIDICC(channel, cc, value)
	if channel ~= 0 then
		return
	end
	if probeMode then
		probe(nil, cc, value)
		return
	end
	if value == 0 then
		if cc == TOP.shift then
			shift = false
			paintTop()
			flushLEDs()
		end
		local fn = TRACK_FN[cc]
		-- only the button that is actually held clears the hold; releasing a
		-- shift-function button must not drop a function held from before Shift
		if fn and fn == heldFunction then
			heldFunction = nil
			paintTrack()
			flushLEDs()
		end
		return
	end
	if cc == TOP.shift then
		shift = true
		paintTop()
		flushLEDs()
		return
	end
	if cc == RIGHT.logo then
		if shift then
			probeMode = not probeMode
			log("probe mode " .. tostring(probeMode))
			paintRight()
			flushLEDs()
		else
			log("status: mode=" .. mode .. " shift=" .. tostring(shift))
		end
		return
	end
	if cc == TOP.session then
		setMode("clip")
		return
	end
	if cc == TOP.sequencer then
		setMode("step")
		return
	end
	for row = 0, 7 do
		if cc == SCENE[row + 1] then
			if shift then
				handleRightLabel(row)
			else
				doScene(row)
			end
			return
		end
	end
	if cc == TOP.left then
		moveWindow("left", shift and 8 or 1)
		return
	end
	if cc == TOP.right then
		moveWindow("right", shift and 8 or 1)
		return
	end
	if adjustMode and (cc == LEFT.up or cc == LEFT.down) then
		nudgeAdjust(cc == LEFT.up and 1 / 8 or -1 / 8)
		return
	end
	if cc == LEFT.up then
		moveWindow("up", shift and 8 or 1)
		return
	end
	if cc == LEFT.down then
		moveWindow("down", shift and 8 or 1)
		return
	end
	if cc == LEFT.play then
		doTransport("play")
		return
	end
	if cc == LEFT.record then
		doTransport("record")
		return
	end
	if cc == LEFT.quantize then
		log("quantize: TODO (no clip-quantize API in the 3.10.1 contract)")
		return
	end
	if cc == LEFT.duplicate then
		clipOp = "duplicate"
		clipOrigin = nil
		log("clip op duplicate armed: press origin pad, then target pad")
		paintAll()
		return
	end
	if cc == LEFT.clear then
		clipOp = "clear"
		clipOrigin = nil
		log("clip op clear armed: press the clip pad")
		paintAll()
		return
	end
	if cc == TOP.save then
		log("save: TODO")
		return
	end
	local fn = TRACK_FN[cc]
	if fn then
		if shift then
			if fn == "sends" and adjustMode == "sends" then
				adjustSend = (adjustSend % 4) + 1
				log("send " .. adjustSend)
				paintAll()
			else
				doShiftFunction(fn)
				paintTrack()
				flushLEDs()
			end
		elseif fn == "volume" or fn == "pan" or fn == "sends" then
			if adjustMode == fn then
				exitAdjust()
			else
				enterAdjust(fn)
			end
		else
			heldFunction = fn
			adjustMode = nil
			log("hold " .. fn)
			paintAll()
		end
		return
	end
	if cc >= 101 and cc <= 108 then
		local col = cc - 101
		local gc = globalPos(col, 0)
		if heldFunction then
			applyFunction(heldFunction, gc)
		else
			selectTrack(gc)
		end
		return
	end
	log("unmapped CC " .. cc .. " value " .. value)
end

function LaunchpadProMK3.HandleMIDISysex(bytes)
	if type(bytes) ~= "string" then
		return
	end
	-- strip F0/F7 if the host passes them
	if bytes:byte(1) == 0xF0 then
		bytes = bytes:sub(2)
	end
	if bytes:byte(-1) == 0xF7 then
		bytes = bytes:sub(1, -2)
	end
	-- select layout: 00 20 29 02 0E 00 <layout> <page> 00
	if bytes:sub(1, 6) == string.char(0x00, 0x20, 0x29, 0x02, 0x0E, 0x00) and #bytes >= 9 then
		local layout = bytes:byte(7)
		local page = bytes:byte(8)
		if priorLayout == nil and layout ~= 0x11 then
			priorLayout, priorPage = layout, page
			log(string.format("prior layout 0x%02x page %d", layout, page))
		end
	end
end

-----------------------------------------------------------------------------------------------
-- Timer
-----------------------------------------------------------------------------------------------

function LaunchpadProMK3.HandleTimer()
	ticks = ticks + 1
	blinkOn = not blinkOn
	if layoutQuerySent and not programmerEntered and ticks >= 1 then
		sendLayout(0x11, 0)
		programmerEntered = true
		log("programmer mode")
	end
	if aperture and not clipProps then
		-- window position fallback, whichever getter this firmware has
		for _, n in ipairs({ "GetOriginX", "GetColumn", "GetX" }) do
			local v = call(aperture[n])
			if type(v) == "number" then
				originCol = v
				break
			end
		end
		for _, n in ipairs({ "GetOriginY", "GetRow", "GetY" }) do
			local v = call(aperture[n])
			if type(v) == "number" then
				originRow = v
				break
			end
		end
	end
	if ticks % 8 == 0 then
		padCache = {}
	end -- resend everything every 2 s
	paintAll()
end

-----------------------------------------------------------------------------------------------
-- Load / unload
-----------------------------------------------------------------------------------------------

function LaunchpadProMK3.OnLoad()
	adjustMode = nil
	adjustSend = 1
	clipOp = nil
	clipOrigin = nil
	aperture = dev.clipMatrixAperture or (mpc.clipMatrix and mpc.clipMatrix.clipMatrixAperture)
	clipProps = (aperture and aperture.clipProperties)
		or dev.clipProperties
		or (mpc.clipMatrix and mpc.clipMatrix.clipProperties)
	if aperture then
		call(aperture.SetColumns, 8)
		call(aperture.SetRows, 8)
		call(aperture.SetLabel, "LPP3")
		call(aperture.SetFollowsTUI, false)
		call(aperture.Show)
		log("aperture ok")
	else
		logOnce("noaperture", "aperture MISSING: clip surface disabled")
	end
	if clipProps then
		log("clipProperties ok")
	else
		logOnce("noclips", "clipProperties MISSING")
	end

	-- register the LPP3 controls with the script
	local m = dev.mappings and dev.mappings.script
	if m then
		for padRow = 0, 7 do
			for col = 0, 7 do
				call(m.AddNoteToScript, 0, 10 * (padRow + 1) + col + 1)
			end
		end
		local ccs = {
			1,
			2,
			3,
			4,
			5,
			6,
			7,
			8,
			10,
			19,
			20,
			29,
			30,
			39,
			40,
			49,
			50,
			59,
			60,
			69,
			70,
			79,
			80,
			89,
			90,
			91,
			92,
			93,
			94,
			95,
			96,
			97,
			98,
			99,
			101,
			102,
			103,
			104,
			105,
			106,
			107,
			108,
		}
		for _, cc in ipairs(ccs) do
			call(m.AddCCToScript, 0, cc)
		end
		call(m.SetHandleSysex, true)
	end

	queryLayout()
	layoutQuerySent = true

	listenAll()
	paintAll()
	call(dev.timer and dev.timer.Start, 250)
	log("loaded")
end

function LaunchpadProMK3.OnUnload()
	call(dev.timer and dev.timer.Stop)
	removeListeners()
	adjustMode = nil
	adjustSend = 1
	clipOp = nil
	clipOrigin = nil
	if programmerEntered then
		sendLayout(priorLayout or 0x04, priorPage or 0x00)
		log("restored layout")
	end
	local m = dev.mappings and dev.mappings.script
	if m then
		for padRow = 0, 7 do
			for col = 0, 7 do
				call(m.RemoveNoteToScript, 0, 10 * (padRow + 1) + col + 1)
			end
		end
		local ccs = {
			1,
			2,
			3,
			4,
			5,
			6,
			7,
			8,
			10,
			19,
			20,
			29,
			30,
			39,
			40,
			49,
			50,
			59,
			60,
			69,
			70,
			79,
			80,
			89,
			90,
			91,
			92,
			93,
			94,
			95,
			96,
			97,
			98,
			99,
			101,
			102,
			103,
			104,
			105,
			106,
			107,
			108,
		}
		for _, cc in ipairs(ccs) do
			call(m.RemoveCCToScript, 0, cc)
		end
	end
	-- dark the surface
	for padRow = 0, 7 do
		for col = 0, 7 do
			ledOff(10 * (padRow + 1) + col + 1)
		end
	end
	for _, cc in ipairs({
		1,
		2,
		3,
		4,
		5,
		6,
		7,
		8,
		10,
		19,
		20,
		29,
		30,
		39,
		40,
		49,
		50,
		59,
		60,
		69,
		70,
		79,
		80,
		89,
		90,
		91,
		92,
		93,
		94,
		95,
		96,
		97,
		98,
		99,
		101,
		102,
		103,
		104,
		105,
		106,
		107,
		108,
	}) do
		ledOff(cc)
	end
	flushLEDs()
	if aperture then
		call(aperture.Hide)
	end
	log("unloaded")
end
