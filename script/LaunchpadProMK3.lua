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
--                        107 device (Q-Link page) / Shift tempo
--                        108 stop clip  / Shift swing
--   right column CC 19-89 + 99
--                        99 novation logo (status/home; Shift = probe mode)
--                        89 patterns, 79 steps, 69 pattern settings,
--                        59 velocity, 49 probability, 39 mutation, 29 micro step, 19 print to clip
--   top row CC 90-98     90 shift, 91 < (Shift = track prev), 92 > (Shift = track next),
--                        93 session (clip grid), 94 note = MPC pads mode (Shift = preset prev),
--                        95 chord (Shift = preset next), 96 custom = track mute mode,
--                        97 sequencer, 98 projects/save
--   left column CC 10-80 10 record (Shift = overdub), 20 play (Shift = loop toggle),
--                        30 fixed length (Shift = automation filter cycle),
--                        40 quantize (Shift = quantiser toggle), 50 duplicate/double, 60 clear,
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
	available = { 60, 60, 60 },
	white = { 127, 127, 127 },
	green = { 0, 127, 0 },
	red = { 127, 0, 0 },
	orange = { 127, 60, 0 },
	blue = { 0, 60, 127 },
	cyan = { 0, 127, 127 },
	magenta = { 127, 0, 127 },
	yellow = { 127, 127, 0 },
}

-- Volume fader steps, bottom (row 7) to top (row 0), in dB.
-- -inf is sent as a very low dB so the MPC shows -inf.
local VOLUME_DB = { [7] = -100, [6] = -30, [5] = -20, [4] = -9, [3] = -3, [2] = 0, [1] = 3, [0] = 6 }

-- One colour per send so Send 1-4 are distinguishable.
local SEND_COLOURS = { C.yellow, C.green, C.blue, C.orange }

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
local lastPadCol, lastPadRow, lastPadTick = nil, nil, -100
local clipOp = nil -- nil / "duplicate" / "clear"
local clipOrigin = nil -- {col, row} for duplicate
local tempoMode = false -- Shift+CC7 tempo page: up/down change BPM
local tempoHold = nil -- LEFT.up / LEFT.down while held (auto-repeat)
local tempoHoldTicks = 0 -- ticks since the tempo button was pressed
local swingMode = false -- Shift+CC8 swing page: up/down change swing
local swingHold = nil -- LEFT.up / LEFT.down while held (auto-repeat)
local swingHoldTicks = 0 -- ticks since the swing button was pressed
local qlinkMode = false -- CC7 device page: Q-Link faders (Twist-driven)
local qlinkPage = 0 -- 0 = Q-Links 0-7, 1 = Q-Links 8-15
local qlinkCol = 0 -- last grid column touched (for Shift+up/down nudges)
local followMode = false -- optional grid-follows-current-track; Shift+CC 93 toggles
local padsMode = false -- CC94 MPC pads mode: the grid quadrant mirrors mpc.controlSurface.pads
local padsColourCache = {} -- pad index -> ARGB int last sent (diff-only mirror)
local padUtility = "off" -- CC 95 cycles the MPC's pad utilities: note repeat -> full level -> off
local padsLayout = "drum" -- CC 94 mode layout: drum (4x4 bank A) or chromatic (virtual pads)
local padsBaseNote = 48 -- chromatic layout root note (up/down arrows shift it by an octave)
local boundPadNotes = {} -- grid notes currently routed away from the script
local chromaticVirtualPad -- forward declaration (defined with the pad-mode helpers)
local tapTicks = {} -- recent tap-tempo tick timestamps (50 ms per tick)
local nativeTap = false -- Shift held + CC 6 routed to the MPC's Tap Tempo control
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

-- Nearest volume-fader row (0 = top, 7 = bottom) for a dB value.
local function dbToRow(db)
	db = tonumber(db)
	if db == nil or db <= -60 then
		return 7
	elseif db <= -25 then
		return 6
	elseif db <= -14.5 then
		return 5
	elseif db <= -6 then
		return 4
	elseif db <= -1.5 then
		return 3
	elseif db <= 1.5 then
		return 2
	elseif db <= 4.5 then
		return 1
	end
	return 0
end

-- MPC volume fader curve, measured on 3.10.1: dB = 40*log10(gain) + 6.
-- Inverse: gain = 10^((dB - 6) / 40); -inf is gain 0.
local function dbToGain(db)
	db = tonumber(db)
	if db == nil or db <= -60 then
		return 0
	end
	return 10 ^ ((db - 6) / 40)
end

local function gainToDb(gain)
	gain = tonumber(gain)
	if gain == nil or gain <= 0 then
		return -100
	end
	return 40 * math.log(gain, 10) + 6
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

-- Page colour for the active fader menu (also used by the up/down arrows).
local function adjustColour()
	if adjustMode == "pan" then
		return C.magenta
	elseif adjustMode == "sends" then
		return SEND_COLOURS[adjustSend] or C.yellow
	end
	return C.cyan
end

-- Pad mode availability: the mode button lights only when its mappings exist;
-- otherwise it stays off and the surface keeps today's behaviour.

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

-- Tempo page: a 7-segment display scaled to the grid. A 3-digit BPM uses
-- 2-column digits with 1-column gaps; a 2-digit BPM uses 4-column digits with
-- no gaps, so the number is as large as the grid allows.
local SEGMENTS = {
	["0"] = { a = true, b = true, c = true, d = true, e = true, f = true, g = false },
	["1"] = { a = false, b = true, c = true, d = false, e = false, f = false, g = false },
	["2"] = { a = true, b = true, c = false, d = true, e = true, f = false, g = true },
	["3"] = { a = true, b = true, c = true, d = true, e = false, f = false, g = true },
	["4"] = { a = false, b = true, c = true, d = false, e = false, f = true, g = true },
	["5"] = { a = true, b = false, c = true, d = true, e = false, f = true, g = true },
	["6"] = { a = true, b = false, c = true, d = true, e = true, f = true, g = true },
	["7"] = { a = true, b = true, c = true, d = false, e = false, f = false, g = false },
	["8"] = { a = true, b = true, c = true, d = true, e = true, f = true, g = true },
	["9"] = { a = true, b = true, c = true, d = true, e = false, f = true, g = true },
}

local function tempoPad(col, row, colour)
	if col >= 0 and col < GRID_COLS and row >= 0 and row < GRID_ROWS then
		ledRGB(10 * (8 - row) + col + 1, colour[1], colour[2], colour[3])
	end
end

-- Draw one 7-segment digit in the box (x0, y0) .. (x0+w-1, y0+h-1).
local function drawDigit(ch, x0, y0, w, h, colour)
	local seg = SEGMENTS[ch]
	if not seg then
		return
	end
	local mid = math.floor(h / 2)
	if seg.a then
		for c = 0, w - 1 do
			tempoPad(x0 + c, y0, colour)
		end
	end
	if seg.d then
		for c = 0, w - 1 do
			tempoPad(x0 + c, y0 + h - 1, colour)
		end
	end
	if seg.g then
		for c = 0, w - 1 do
			tempoPad(x0 + c, y0 + mid, colour)
		end
	end
	if seg.f then
		for r = 0, mid do
			tempoPad(x0, y0 + r, colour)
		end
	end
	if seg.b then
		for r = 0, mid do
			tempoPad(x0 + w - 1, y0 + r, colour)
		end
	end
	if seg.e then
		for r = mid, h - 1 do
			tempoPad(x0, y0 + r, colour)
		end
	end
	if seg.c then
		for r = mid, h - 1 do
			tempoPad(x0 + w - 1, y0 + r, colour)
		end
	end
end

local function paintNumberGrid(value)
	value = math.max(0, math.min(999, math.floor(value)))
	for row = 0, GRID_ROWS - 1 do
		for col = 0, GRID_COLS - 1 do
			ledOff(10 * (8 - row) + col + 1)
		end
	end
	-- Left-aligned, no gaps. The hundreds digit is narrow (1 column for a
	-- leading 1, 2 columns otherwise) so the tens and ones digits get the rest
	-- of the width and show more detail.
	local text
	local widths = {}
	if value >= 100 then
		text = string.format("%3d", value)
		widths[1] = (text:sub(1, 1) == "1") and 1 or 2
		local remaining = GRID_COLS - widths[1]
		widths[2] = math.floor(remaining / 2)
		widths[3] = remaining - widths[2]
	else
		text = string.format("%2d", value)
		widths[1] = 4
		widths[2] = 4
	end
	-- colour by position from the right: ones white (brightest), tens orange,
	-- hundreds blue. Blue/orange/white differ in both hue and luminance, so the
	-- digits stay distinct for red-green colourblindness (the common type).
	local colours = { C.white, C.orange, C.blue }
	local x0 = 0
	for i = 1, #text do
		drawDigit(text:sub(i, i), x0, 0, widths[i], GRID_ROWS, colours[#text - i + 1])
		x0 = x0 + widths[i]
	end
end

local function paintTempoGrid()
	local bpm = math.floor(call(mpc.sequencer and mpc.sequencer.GetBPM) or 120)
	paintNumberGrid(bpm)
end

local function paintSwingGrid()
	local q = mpc.sequencer and mpc.sequencer.quantiser
	-- MPC swing: 50% = straight, 75% = max; clamp the display into the range
	local swing = math.floor(call(q and q.GetSwing) or 50)
	paintNumberGrid(math.max(50, math.min(75, swing)))
end

local function paintAdjustGrid()
	local colour = C.cyan
	if adjustMode == "pan" then
		colour = C.magenta
	elseif adjustMode == "sends" then
		colour = SEND_COLOURS[adjustSend] or C.yellow
	end
	local name = adjustPropName()
	local trackCount = call(mpc.tracks and mpc.tracks.SizeNormalTracks) or GRID_COLS
	for col = 0, GRID_COLS - 1 do
		local gc = globalPos(col, 0)
		local t = trackAt(gc)
		if t and gc < trackCount then
			local litCount
			if adjustMode == "volume" then
				-- dB fader: -inf = no pads, +6 dB = all 8 pads
				local gain = propValue(t, "Volume")
				local db = gainToDb(gain)
				local row = dbToRow(db)
				litCount = (db <= -60) and 0 or (GRID_ROWS - row)
			else
				local value = propValue(t, name) or 0
				if type(value) ~= "number" then
					value = 0
				end
				litCount = math.floor(value * GRID_ROWS + 0.5)
			end
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

-----------------------------------------------------------------------------------------------
-- Q-Link page (CC 7 device). SetPosition updates the ValueString but does not reach the
-- MPC edit-mode value on 3.10.1, so changes are driven with Twist (rotate by delta) instead.
-----------------------------------------------------------------------------------------------

local paintAll -- forward declaration (defined below)

local function qlinkAt(i)
	local cs = mpc.controlSurface
	local ql = cs and cs.qlinks
	if not ql then
		return nil
	end
	return ql[i]
end

local function qlinkCount()
	local cs = mpc.controlSurface
	local ql = cs and cs.qlinks
	if not ql then
		return 0
	end
	return call(ql.GetNumQLinks) or 0
end

local function qlinkPosition(i)
	local q = qlinkAt(i)
	if not q then
		return 0
	end
	return call(q.GetPosition) or 0
end

-- Touch() signature is unknown on 3.10.1: try it with no args, ignore any error.
local function touchQlink(q)
	if q and type(q.Touch) == "function" then
		pcall(q.Touch)
	end
end

-- Drive qlink i to pos: Twist(target - GetPosition()), clamped to +-127, repeated at most
-- twice to absorb the GetPosition lag; falls back to SetPosition when Twist is missing.
local qlinkTargetLogged = {} -- page-open diagnosis: one line per qlink
-- The 16 Q-Links are the MPC's four Q-Link banks (4 knobs each); each bank gets its
-- own fader colour so the groups are visually distinct on the grid.
local QLINK_BANK_COLOURS = { C.cyan, C.magenta, C.yellow, C.blue }
-- Flip/binary params (e.g. Kill EQ Thru/Kill) show the same value string for many
-- positions and only two strings overall; once learned, presses round to 0/127 and
-- the column shows a single lit extreme pad instead of a fill.
local qlinkFlip = {}
local qlinkSeenStrings = {} -- i -> set of distinct value strings observed
local qlinkSeenPos = {} -- i -> { min = , max = }

local function qlinkTargetName(i)
	local q = qlinkAt(i)
	local name = call(q and q.GetTargetName)
	if type(name) ~= "string" then
		name = propValue(q, "TargetName")
	end
	return type(name) == "string" and name or ""
end

-- Drive qlink i to pos. Twist is primary (a real knob rotation); SetValue (the target's
-- un-normalised value) is the second attempt when Twist does not move the target;
-- SetPosition only syncs the knob position display and is the last resort.
local function setQlinkPosition(i, pos)
	local q = qlinkAt(i)
	if not q then
		return
	end
	if not qlinkTargetLogged[i] then
		qlinkTargetLogged[i] = true
		log(string.format("qlink %d target '%s'", i, qlinkTargetName(i)))
	end
	local before = call(q.GetValueString)
	local posBefore = call(q.GetPosition) or 0
	touchQlink(q)
	if type(q.Twist) == "function" then
		for _ = 1, 2 do
			local delta = pos - (call(q.GetPosition) or 0)
			if delta == 0 then
				break
			end
			if delta > 127 then
				delta = 127
			elseif delta < -127 then
				delta = -127
			end
			call(q.Twist, delta)
		end
	end
	local afterTwist = call(q.GetValueString)
	if afterTwist == before and type(q.SetValue) == "function" then
		-- Twist did not change the target value: try the target value directly.
		-- GetValue() is the current un-normalised value; scale by the position change.
		local v = call(q.GetValue)
		if type(v) == "number" and posBefore ~= 0 then
			call(q.SetValue, v * pos / posBefore)
		end
		call(q.SetPosition, pos)
	elseif type(q.SetPosition) == "function" then
		call(q.SetPosition, pos) -- keep the knob position in sync with the target
	end
	touchQlink(q)
	local str = tostring(call(q.GetValueString) or "")
	log(string.format("qlink %d = %d (%s)", i, pos, str))
	-- flip learning: remember distinct value strings and the position span; two distinct
	-- strings across a wide span means the parameter is binary (round to extremes)
	if str ~= "" then
		local seen = qlinkSeenStrings[i]
		if not seen then
			seen = {}
			qlinkSeenStrings[i] = seen
		end
		seen[str] = true
		local span = qlinkSeenPos[i]
		if not span then
			span = { min = pos, max = pos }
			qlinkSeenPos[i] = span
		else
			if pos < span.min then
				span.min = pos
			end
			if pos > span.max then
				span.max = pos
			end
		end
		local n = 0
		for _ in pairs(seen) do
			n = n + 1
		end
		if n == 2 and span.max - span.min >= 48 and not qlinkFlip[i] then
			qlinkFlip[i] = true
			log(string.format("qlink %d flip parameter", i))
		end
	end
end

-- A qlink with an empty target name is unassigned in the current Q-Link mode: its
-- column stays fully dark so the grid only shows faders that control something.
local function qlinkAssigned(i)
	return qlinkTargetName(i) ~= ""
end

local function qlinkColour(i)
	return QLINK_BANK_COLOURS[math.floor(i / 4) + 1] or C.cyan
end

-- Columns show only the ASSIGNED Q-Links, compacted left-to-right with no gaps
-- (unassigned slots would leave dark columns in between). The order follows the
-- MPC's Q-Link screen, which lists the 16 slots column-major with each bank/page
-- running in reverse index order: its page 1 is Q-Links 12,8,4,0, page 2 is 13,9,5,1,
-- page 3 is 14,10,6,2, page 4 is 15,11,7,3 (device-verified twice over: the Kill EQ
-- page lives at 0,4,8,12 and the Beat Repeat page at 1,5,9,13, each reading newest
-- slot first on the screen). Page 1 of the Launchpad grid shows
-- the first 8 assigned Q-Links in this order, page 2 the rest.
local QLINK_PAGE_GROUPS = {
	[0] = { { 12, 8, 4, 0 }, { 13, 9, 5, 1 } }, -- MPC pages 1+2
	[1] = { { 14, 10, 6, 2 }, { 15, 11, 7, 3 } }, -- MPC pages 3+4
}
local qlinkColumnMap = {}

-- Fixed slot positions: columns 1-4 are ALWAYS the MPC's page 1 slots (12,8,4,0) and
-- columns 5-8 its page 2 slots (13,9,5,1), one column per slot — no compaction, no
-- sliding. An unassigned slot keeps its column as a dark gap exactly where the MPC
-- screen shows it (device-verified: the user's page 1 reads unmapped, High, Mid, Low).
local function buildQlinkColumnMap(page)
	qlinkColumnMap = {}
	local count = qlinkCount()
	local groups = QLINK_PAGE_GROUPS[page or qlinkPage] or QLINK_PAGE_GROUPS[0]
	for g = 1, 2 do
		for rank, i in ipairs(groups[g]) do
			if i < count and qlinkAssigned(i) then
				qlinkColumnMap[4 * (g - 1) + rank - 1] = i
			end
		end
	end
end

local function qlinkForColumn(col)
	return qlinkColumnMap[col]
end

local function qlinkPageHasContent(page)
	local count = qlinkCount()
	for _, group in ipairs(QLINK_PAGE_GROUPS[page]) do
		for _, i in ipairs(group) do
			if i < count and qlinkAssigned(i) then
				return true
			end
		end
	end
	return false
end

local function paintQlinkGrid()
	buildQlinkColumnMap()
	for col = 0, GRID_COLS - 1 do
		local i = qlinkForColumn(col)
		local assigned = i ~= nil
		local pos = assigned and qlinkPosition(i) or 0
		local colour = qlinkColour(i or 0)
		local litCount = math.floor(pos / 127 * GRID_ROWS + 0.5)
		for row = 0, GRID_ROWS - 1 do
			local idx = 10 * (8 - row) + col + 1
			local fromBottom = 7 - row
			if not assigned then
				ledOff(idx)
			elseif qlinkFlip[i] then
				-- binary parameter: only the matching extreme pad is lit (top = max)
				if (pos >= 64 and row == 0) or (pos < 64 and row == GRID_ROWS - 1) then
					ledRGB(idx, colour[1], colour[2], colour[3])
				else
					ledRGB(idx, C.dim[1], C.dim[2], C.dim[3])
				end
			elseif fromBottom < litCount then
				ledRGB(idx, colour[1], colour[2], colour[3])
			else
				ledRGB(idx, C.dim[1], C.dim[2], C.dim[3])
			end
		end
	end
end

local function handleQlinkPad(col, row)
	buildQlinkColumnMap()
	local i = qlinkForColumn(col)
	if i == nil then
		return
	end
	local target
	if qlinkFlip[i] then
		-- binary parameter: bottom half of the column = min extreme, top half = max
		target = (row < GRID_ROWS / 2) and 127 or 0
	else
		target = math.floor((GRID_ROWS - row) / GRID_ROWS * 127 + 0.5)
	end
	setQlinkPosition(i, target)
	qlinkCol = col
	paintAll()
end

local function nudgeQlink(delta)
	buildQlinkColumnMap()
	local i = qlinkForColumn(qlinkCol)
	local q = qlinkAt(i)
	if not q or type(q.Twist) ~= "function" or i >= qlinkCount() then
		return
	end
	local pos = qlinkPosition(i)
	if pos + delta < 0 or pos + delta > 127 then
		return
	end
	call(q.Twist, delta)
	log(string.format("qlink %d = %d (%s)", i, pos + delta, tostring(call(q.GetValueString) or "")))
	paintAll()
end

local function enterQlink()
	local cs = mpc.controlSurface
	if not (cs and cs.qlinks) then
		logOnce("noqlinks", "qlink page unavailable: controlSurface.qlinks missing")
		return
	end
	adjustMode = nil
	tempoMode = false
	swingMode = false
	qlinkMode = true
	qlinkPage = 0
	qlinkCol = 0
	qlinkTargetLogged = {}
	qlinkFlip = {}
	qlinkSeenStrings = {}
	qlinkSeenPos = {}
	buildQlinkColumnMap(0)
	local map = {}
	local assignedCount = 0
	for c = 0, GRID_COLS - 1 do
		local i = qlinkColumnMap[c]
		if i then
			assignedCount = assignedCount + 1
			map[#map + 1] = (c + 1) .. "=" .. qlinkTargetName(i)
		else
			map[#map + 1] = (c + 1) .. "=-"
		end
	end
	log("qlink page (" .. assignedCount .. " assigned): " .. table.concat(map, ", "))
	paintAll()
end
local function exitQlink()
	qlinkMode = false
	log("qlink page off")
	paintAll()
end

-- Clip states that blink: the MPK's fast set (transitions); other states > 3
-- (playing/recording/overdubbing) blink slowly. RGB pads have no blink channel
-- in the sysex we use, so blinking repaints the pad dim on the timer phase:
-- fast = the 2 Hz blinkOn, slow = 1 Hz via ticks.
local CLIP_BLINK_FAST = { [3] = true, [5] = true, [6] = true, [8] = true, [9] = true, [11] = true }

local function blinkPhase(fast)
	if fast then
		return blinkOn
	end
	return ticks % 10 < 5
end

-- One clip slot from its live property State (MPK semantics, device-verified):
-- < 2 empty, 2 = stopped (the clip's Colour, alpha ignored), 3-5 = playing or
-- queued (green), >= 6 = recording (red). Selected empty slots light dim white
-- (ring substitute). Returns false when the slot has no State property, so the
-- caller falls back to polling clipMatrix for that pad.
local function paintClipSlot(col, row)
	local p = clipProps and clipProps[col] and clipProps[col][row]
	local state = tonumber(propValue(p, "State"))
	if state == nil then
		return false
	end
	local idx = 10 * (8 - row) + col + 1
	if state < 2 then
		if propValue(p, "Selected") == true then
			ledRGB(idx, C.available[1], C.available[2], C.available[3])
		else
			ledOff(idx)
		end
		return true
	end
	local r, g, b
	if state >= 6 then
		r, g, b = C.red[1], C.red[2], C.red[3]
	elseif state >= 3 then
		r, g, b = C.green[1], C.green[2], C.green[3]
	else
		r, g, b = argb(clipColour(col, row))
	end
	if state >= 3 and not blinkPhase(CLIP_BLINK_FAST[state]) then
		r, g, b = scale7(r * 0.18), scale7(g * 0.18), scale7(b * 0.18)
	end
	ledRGB(idx, r, g, b)
	return true
end

-- Pads mode grid: the bottom-left 4x4 quadrant mirrors mpc.controlSurface.pads[i].Colour
-- (ARGB int, alpha ignored); the rest of the grid is dark. poll=true re-reads the pad
-- colours; padsColourCache keeps the last ARGB per pad so only diffs are sent.
-- Chromatic layout LEDs: blue note grid, C notes full blue and the rest a dim blue
-- tint, so the octave shape is visible without any white (no MPC pad colours exist
-- for virtual pads).
local function paintChromaticGrid()
	for padRow = 0, 7 do
		for col = 0, 7 do
			local idx = 10 * (padRow + 1) + col + 1
			if chromaticVirtualPad(padRow, col) % 12 == 0 then
				ledRGB(idx, C.blue[1], C.blue[2], C.blue[3])
			else
				ledRGB(idx, 0, 15, 30)
			end
		end
	end
end

local function paintPadsGrid(poll)
	if padsLayout == "chromatic" then
		paintChromaticGrid()
		return
	end
	local quadrant = {}
	for i = 0, 15 do
		quadrant[10 * (math.floor(i / 4) + 1) + (i % 4) + 1] = true
	end
	-- the rest of the grid stays dark; the quadrant pads are painted below
	for row = 0, GRID_ROWS - 1 do
		for col = 0, GRID_COLS - 1 do
			local idx = 10 * (8 - row) + col + 1
			if not quadrant[idx] then
				ledOff(idx)
			end
		end
	end
	local pads = mpc.controlSurface and mpc.controlSurface.pads
	for i = 0, 15 do
		local idx = 10 * (math.floor(i / 4) + 1) + (i % 4) + 1
		if poll then
			local p = pads and pads[i]
			local v = call(p and p.GetColour)
			if type(v) ~= "number" then
				v = propValue(p, "Colour")
			end
			if v ~= padsColourCache[i] then
				padsColourCache[i] = v
				local r, g, b = argb(v)
				ledRGB(idx, scale7(r), scale7(g), scale7(b))
			end
		elseif type(padsColourCache[i]) == "number" then
			local r, g, b = argb(padsColourCache[i])
			ledRGB(idx, scale7(r), scale7(g), scale7(b))
		end
	end
end

local function paintGrid()
	if padsMode then
		-- mirror refresh every 2 ticks (100 ms); between refreshes repaint from the cache
		paintPadsGrid(ticks % 2 == 0)
		return
	end
	if tempoMode then
		paintTempoGrid()
		return
	end
	if swingMode then
		paintSwingGrid()
		return
	end
	if qlinkMode then
		paintQlinkGrid()
		return
	end
	if adjustMode then
		paintAdjustGrid()
		return
	end
	for row = 0, GRID_ROWS - 1 do
		for col = 0, GRID_COLS - 1 do
			local idx = 10 * (8 - row) + col + 1
			if not (clipProps and paintClipSlot(col, row)) then
				-- polling fallback: clipProperties missing or a slot without State
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
	local function fnAvailable(fn)
		if fn == "device" then
			local cs = mpc.controlSurface
			return (cs and cs.qlinks ~= nil) or (mpc.sequencer ~= nil and mpc.sequencer.SetBPM ~= nil)
		elseif fn == "stopClip" then
			return aperture ~= nil and aperture.StopClipsOnTrack ~= nil
		end
		return mpc.tracks ~= nil
	end
	local function fnColour(fn)
		if
			heldFunction == fn
			or adjustMode == fn
			or (fn == "device" and (tempoMode or qlinkMode))
			or (fn == "stopClip" and swingMode)
		then
			return C.white
		elseif fnAvailable(fn) then
			return C.available
		else
			return C.off
		end
	end
	local arm = fnColour("recArm")
	local mute = fnColour("mute")
	local solo = fnColour("solo")
	local volume = fnColour("volume")
	local pan = fnColour("pan")
	local sends = fnColour("sends")
	local device = fnColour("device")
	local stopClip = fnColour("stopClip")
	ledRGB(TRACK.recArm, arm[1], arm[2], arm[3])
	ledRGB(TRACK.mute, mute[1], mute[2], mute[3])
	ledRGB(TRACK.solo, solo[1], solo[2], solo[3])
	ledRGB(TRACK.volume, volume[1], volume[2], volume[3])
	ledRGB(TRACK.pan, pan[1], pan[2], pan[3])
	ledRGB(TRACK.sends, sends[1], sends[2], sends[3])
	ledRGB(TRACK.device, device[1], device[2], device[3])
	ledRGB(TRACK.stopClip, stopClip[1], stopClip[2], stopClip[3])
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

local padUtilityAvailable -- forward declaration (defined with the pad-mode helpers)
local padsLayoutAvailable -- forward declaration (defined with the pad-mode helpers)

local function paintTop()
	local function modeColour(m)
		if mode == m then
			return C.white
		else
			return C.dim
		end
	end
	-- session shows cyan while grid-follow is enabled so the toggle state is visible
	local session = followMode and C.cyan or modeColour("clip")
	local sequencer = modeColour("step")
	local note = C.off
	if padsMode then
		note = (padsLayout == "chromatic") and C.cyan or C.white
	elseif padsLayoutAvailable() then
		note = C.available
	end
	local chord = C.off
	if padsMode and padUtility ~= "off" then
		chord = C.white
	elseif padsMode and padUtilityAvailable() then
		chord = C.available
	end
	local custom = C.off -- stub (mutes live on the CC 2 hold-function)
	ledRGB(TOP.session, session[1], session[2], session[3])
	ledRGB(TOP.sequencer, sequencer[1], sequencer[2], sequencer[3])
	ledRGB(TOP.note, note[1], note[2], note[3])
	ledRGB(TOP.chord, chord[1], chord[2], chord[3])
	ledRGB(TOP.custom, custom[1], custom[2], custom[3])
	ledRGB(TOP.left, C.dim[1], C.dim[2], C.dim[3])
	ledRGB(TOP.right, C.dim[1], C.dim[2], C.dim[3])
	local saveAvailable = mpc.controlSurface ~= nil and mpc.controlSurface.save ~= nil
	ledRGB(
		TOP.save,
		saveAvailable and C.available[1] or C.dim[1],
		saveAvailable and C.available[2] or C.dim[2],
		saveAvailable and C.available[3] or C.dim[3]
	)
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
	local loop = propValue(sq, "Loop")
	-- play: green while playing, orange while loop is enabled, dim otherwise
	if playing then
		ledRGB(LEFT.play, C.green[1], C.green[2], C.green[3])
	elseif loop then
		ledRGB(LEFT.play, C.orange[1], C.orange[2], C.orange[3])
	else
		ledRGB(LEFT.play, C.dim[1], C.dim[2], C.dim[3])
	end
	-- record: red while recording, orange while overdubbing, dim otherwise
	if recording then
		ledRGB(LEFT.record, C.red[1], C.red[2], C.red[3])
	elseif overdub then
		ledRGB(LEFT.record, C.orange[1], C.orange[2], C.orange[3])
	else
		ledRGB(LEFT.record, C.dim[1], C.dim[2], C.dim[3])
	end
	ledOff(LEFT.fixedLength)
	local quantizeAvailable = mpc.controlSurface ~= nil and mpc.controlSurface.quantizeApply ~= nil
	ledRGB(
		LEFT.quantize,
		quantizeAvailable and C.white[1] or C.off[1],
		quantizeAvailable and C.white[2] or C.off[2],
		quantizeAvailable and C.white[3] or C.off[3]
	)
	local nudgeOn = adjustMode ~= nil or tempoMode or swingMode or qlinkMode
	local pageColour = tempoMode and C.white
		or (swingMode and C.yellow or (qlinkMode and qlinkColour(qlinkForColumn(0) or 0) or adjustColour()))
	ledRGB(LEFT.duplicate, C.white[1], C.white[2], C.white[3])
	ledRGB(LEFT.clear, C.white[1], C.white[2], C.white[3])
	ledRGB(
		LEFT.down,
		nudgeOn and pageColour[1] or C.white[1],
		nudgeOn and pageColour[2] or C.white[2],
		nudgeOn and pageColour[3] or C.white[3]
	)
	ledRGB(
		LEFT.up,
		nudgeOn and pageColour[1] or C.white[1],
		nudgeOn and pageColour[2] or C.white[2],
		nudgeOn and pageColour[3] or C.white[3]
	)
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

paintAll = function()
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

local listeners = {} -- every property listened to; stopped by removeListeners
local gridListeners = {} -- the current window's clip slots; rebound on window moves

local function listen(prop, fn, store)
	if prop and type(prop.listen) == "function" then
		local ok = pcall(function()
			prop:listen(fn, deviceName)
		end)
		if ok then
			local target = store or listeners
			target[#target + 1] = prop
		end
	end
end

-- Wrap a repaint so a failing listener callback can never break MPC's dispatch.
local function repaintFn(fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			logOnce("listenererror", "listener error: " .. tostring(err))
		end
	end
end

local function stopProps(props)
	for _, prop in ipairs(props) do
		if prop and type(prop.stopListening) == "function" then
			pcall(function()
				prop:stopListening(deviceName)
			end)
		end
	end
end

-- (Re-)register the 8x8 slot listeners: Colour/State/Selected -> full grid
-- repaint (MPK-style, so blink phases stay in sync). The aperture's
-- clipProperties follow the window, so every window move rebinds.
local function listenGrid()
	stopProps(gridListeners)
	gridListeners = {}
	if not clipProps then
		return
	end
	for col = 0, GRID_COLS - 1 do
		for row = 0, GRID_ROWS - 1 do
			local p = clipProps[col] and clipProps[col][row]
			if p then
				local repaint = repaintFn(function()
					paintGrid()
					flushLEDs()
				end)
				listen(p.Colour, repaint, gridListeners)
				listen(p.State, repaint, gridListeners)
				listen(p.Selected, repaint, gridListeners)
			end
		end
	end
end

-- Follow MPC's current track: move the aperture window to that track's column
-- (Master matrix for the master track), then rebind the slot listeners for the
-- new window and repaint. The track row (CC 101-108) selects MPC's current
-- track, so the grid follows track selection too.
local function followCurrentTrack(index)
	if followMode and aperture and type(index) == "number" then
		local normalCount = call(mpc.tracks and mpc.tracks.SizeNormalTracks) or 0
		if index >= normalCount then
			call(aperture.SetActiveMatrix, "Master")
			call(aperture.MoveToColumn, index - normalCount)
		else
			call(aperture.SetActiveMatrix, "Normal")
			call(aperture.MoveToColumn, index)
		end
		log("follow current track " .. tostring(index))
	end
	listenGrid()
	padCache = {}
	paintAll()
end

local function listenAll()
	if aperture and aperture.sceneProperties then
		for row = 0, 7 do
			local p = aperture.sceneProperties[row]
			if p then
				listen(
					p.State,
					repaintFn(function()
						paintScene()
						flushLEDs()
					end)
				)
			end
		end
	end
	local tracks = mpc.tracks and mpc.tracks.normalTracks
	if tracks then
		for i = 0, 7 do
			local t = tracks[i]
			if t then
				local repaint = repaintFn(function()
					paintTrack()
					flushLEDs()
				end)
				listen(t.Mute, repaint)
				listen(t.Solo, repaint)
				listen(t.RecArm, repaint)
			end
		end
	end
	local sq = mpc.sequencer
	if sq then
		local repaint = repaintFn(function()
			paintLeft()
			flushLEDs()
		end)
		listen(sq.Playing, repaint)
		listen(sq.RecordState, repaint)
		listen(sq.OverdubState, repaint)
		listen(sq.Loop, repaint)
	end
	local ct = mpc.tracks and mpc.tracks.currentTrack
	if ct then
		listen(
			ct.Index,
			repaintFn(function(newIndex)
				followCurrentTrack(newIndex)
			end)
		)
	end
	-- align the window with the current track (also registers the slot listeners)
	followCurrentTrack(propValue(ct, "Index"))
end

local function removeListeners()
	stopProps(gridListeners)
	gridListeners = {}
	stopProps(listeners)
	listeners = {}
end

-----------------------------------------------------------------------------------------------
-- Actions
-----------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------------
-- Pad modes (CC 94 MPC pads / CC 96 track mute)
-----------------------------------------------------------------------------------------------

-- The pad modes own the grid, so the grid-hungry states (fader menus, tempo/swing pages,
-- armed clip ops) close when one opens.
local function closeGridStates()
	adjustMode = nil
	tempoMode = false
	swingMode = false
	tempoHold = nil
	swingHold = nil
	clipOp = nil
	clipOrigin = nil
	lastPadCol, lastPadRow, lastPadTick = nil, nil, -100
end

-- Grid note of a pads-mode pad: padIndex 0-15 -> the bottom-left 4x4 quadrant.
local function padsModeNote(i)
	return 10 * (math.floor(i / 4) + 1) + (i % 4) + 1
end

-- Exit pads mode: hand the 16 notes back to the script (the caller repaints the clip grid).
-- The MPC's pad utilities are toggled by pressing the control-surface buttons; CC 95
-- cycles them while MPC Pads mode owns the grid. keyboardControl is deliberately NOT
-- in the cycle: it opens the MPC's Keyboard page (on-screen keyboard + settings)
-- rather than silently toggling a pad mode.
local PAD_UTILITY_BUTTONS = { noteRepeat = "noteRepeat", fullLevel = "fullLevel" }

local function pressSurfaceButton(name)
	local b = mpc.controlSurface and mpc.controlSurface[name]
	if b and type(b.Press) == "function" then
		call(b.Press)
		call(b.Release)
		return true
	end
	return false
end

padUtilityAvailable = function()
	local cs = mpc.controlSurface
	if not (cs and cs.noteRepeat and cs.fullLevel) then
		return false
	end
	return true
end

padsLayoutAvailable = function()
	local pads = dev.mappings and dev.mappings.pads
	if not pads then
		return false
	end
	if padsLayout == "chromatic" then
		return type(pads.AddNoteToVirtualPad) == "function"
	end
	return type(pads.AddNoteToMpcPad) == "function"
end

local function clearPadUtility()
	if padUtility ~= "off" then
		pressSurfaceButton(PAD_UTILITY_BUTTONS[padUtility])
		padUtility = "off"
	end
end

local function cyclePadUtility()
	if not padsMode then
		logOnce("padutility", "pad modes: enter MPC pads mode (CC 94) first")
		return
	end
	if not padUtilityAvailable() then
		logOnce("padutility", "pad modes unavailable: controlSurface buttons missing")
		return
	end
	if padUtility == "off" then
		pressSurfaceButton("noteRepeat")
		padUtility = "noteRepeat"
	elseif padUtility == "noteRepeat" then
		pressSurfaceButton("noteRepeat") -- off
		pressSurfaceButton("fullLevel")
		padUtility = "fullLevel"
	else
		pressSurfaceButton("fullLevel") -- off
		padUtility = "off"
	end
	log("pad utility: " .. padUtility)
	paintTop()
	flushLEDs()
end

local function exitPadsMode()
	if not padsMode then
		return
	end
	padsMode = false
	clearPadUtility()
	local m = dev.mappings and dev.mappings.script
	local pads = dev.mappings and dev.mappings.pads
	for _, b in ipairs(boundPadNotes) do
		if b.pad then
			call(pads and pads.RemoveNoteToMpcPad, 0, b.note, b.pad)
		else
			call(pads and pads.RemoveNoteToVirtualPad, 0, b.note)
		end
		call(m and m.AddNoteToScript, 0, b.note)
	end
	boundPadNotes = {}
	padsColourCache = {}
	if padsLayout == "chromatic" then
		-- virtual pads live beyond the physical 16; using them can leave the MPC's pad
		-- engine on an out-of-range bank where every track's pads are dark and silent
		-- (they still show MIDI activity). Return the pad bank to A on the way out.
		if pressSurfaceButton("bank1") then
			log("pad bank reset (bank 1)")
		else
			logOnce("bankreset", "pad bank reset unavailable: controlSurface.bank1 missing")
		end
	end
	log("pads mode off")
end

-- Enter pads mode: route the 16 quadrant notes to the MPC pads (hardware-routed; they no
-- longer reach HandleMIDINoteOn). Missing mappings degrade: the mode stays off.
-- Chromatic layout: the whole grid, rows a perfect 4th apart (5 semitones), driven
-- through virtual pads (AddNoteToVirtualPad) because AddNoteToMpcPad only reaches
-- bank A (16 pads, device-verified). The root note shifts by octaves with the
-- up/down arrows while the mode is open.
-- Virtual pad N sounds as MIDI note 36+N (pad 1 = note 36, the MPC pad-note map),
-- so the pad index for a sounding note is note - 36; the base note is a real MIDI
-- note (default 48 = C3). Device-verified: the old direct mapping sounded an octave
-- and a half too high.
chromaticVirtualPad = function(padRow, col)
	local note = padsBaseNote + padRow * 5 + col
	return note - 36
end

local function enterPadsMode()
	local m = dev.mappings and dev.mappings.script
	local pads = dev.mappings and dev.mappings.pads
	if not (m and pads and m.RemoveNoteToScript) then
		logOnce("padsmode", "pads mode unavailable: mappings.pads missing")
		return
	end
	if padsLayout == "chromatic" and type(pads.AddNoteToVirtualPad) ~= "function" then
		logOnce("padschromatic", "chromatic layout unavailable: AddNoteToVirtualPad missing")
		return
	end
	if padsLayout == "drum" and type(pads.AddNoteToMpcPad) ~= "function" then
		logOnce("padsmode", "pads mode unavailable: AddNoteToMpcPad missing")
		return
	end
	padsMode = true
	padsColourCache = {}
	boundPadNotes = {}
	if padsLayout == "drum" then
		-- The MPC only lights its pad grid on pad-capable screens (Main, program
		-- editors); on other pages (Keyboard settings, Q-Link, step seq, browser) the
		-- pads report black and the mirror would go dark. Return the MPC to its Main
		-- screen so the grid lights up (guarded; logged once if unavailable).
		if pressSurfaceButton("main") then
			log("pad view: main screen")
		else
			logOnce("padview", "pad view reset unavailable: controlSurface.main missing")
		end
	end
	if padsLayout == "chromatic" then
		for padRow = 0, 7 do
			for col = 0, 7 do
				local note = 10 * (padRow + 1) + col + 1
				call(m.RemoveNoteToScript, 0, note)
				call(pads.AddNoteToVirtualPad, 0, note, chromaticVirtualPad(padRow, col))
				boundPadNotes[#boundPadNotes + 1] = { note = note }
			end
		end
	else
		for i = 0, 15 do
			local note = padsModeNote(i)
			call(m.RemoveNoteToScript, 0, note)
			call(pads.AddNoteToMpcPad, 0, note, i)
			boundPadNotes[#boundPadNotes + 1] = { note = note, pad = i }
		end
	end
	log("pads mode on (" .. padsLayout .. ", base " .. (padsLayout == "chromatic" and padsBaseNote or "drum") .. ")")
end

-- Pick the first layout from the current track's Type: pad-based programs (Drum)
-- get the drum layout, melodic programs (Plugin/Keygroup/MIDI) get chromatic.
local function firstLayoutForTrack()
	local t = mpc.tracks and mpc.tracks.currentTrack
	local trackType = propValue(t, "Type")
	if type(trackType) == "string" and trackType ~= "" and trackType ~= "Drum" then
		return "chromatic", trackType
	end
	return "drum", trackType
end

-- Tapping Note iterates: clip grid -> layout (chosen from the track type) ->
-- the other layout -> clip grid.
local function togglePadsMode()
	if not padsMode then
		local layout, trackType = firstLayoutForTrack()
		padsLayout = layout
		log("track type " .. tostring(trackType or "?") .. " -> " .. layout)
		closeGridStates()
		enterPadsMode()
		if padsMode then
			paintPadsGrid(true) -- immediate mirror, independent of the tick parity
		end
		return
	end
	-- in-mode taps: first switch to the other layout, the next tap exits
	if padsLayout == firstLayoutForTrack() then
		padsLayout = (padsLayout == "drum") and "chromatic" or "drum"
		exitPadsMode()
		enterPadsMode()
		return
	end
	exitPadsMode()
	paintAll()
end

local function setMode(m)
	exitPadsMode() -- another mode (CC 93 session, CC 97, ...) always returns to the clip grid
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

-- Write a track's VolumeDB directly (dB), falling back to the linear Volume
-- property if VolumeDB is read-only on this firmware.
local function setTrackVolumeDB(idx, db)
	local t = trackAt(idx)
	if not t then
		logOnce("track", "no track " .. tostring(idx))
		return
	end
	local p = t.VolumeDB
	if p ~= nil then
		local ok = pcall(function()
			p.value = db
		end)
		if ok then
			log(string.format("VolumeDB track %d = %s", idx, tostring(db)))
			return
		end
	end
	-- fallback: invert the MPC fader curve (dB = 40*log10(gain) + 6)
	setTrackValue(idx, "Volume", dbToGain(db))
end

local function changeTempo(delta)
	local sq = mpc.sequencer
	local bpm = call(sq and sq.GetBPM) or 120
	bpm = math.max(20, math.min(300, math.floor(bpm + delta + 0.5)))
	call(sq and sq.SetBPM, bpm)
	log("tempo: " .. bpm .. " BPM")
	paintGrid()
	paintLeft()
	flushLEDs()
end

local function changeSwing(delta)
	local q = mpc.sequencer and mpc.sequencer.quantiser
	-- MPC swing: 50% = straight, > 50 delays every other step; 75% is the max
	local swing = call(q and q.GetSwing) or 50
	swing = math.max(50, math.min(75, math.floor(swing + delta + 0.5)))
	call(q and q.SetSwing, swing)
	log("swing: " .. swing .. "%")
	paintGrid()
	paintLeft()
	flushLEDs()
end

local function doQuantize()
	local cs = mpc.controlSurface
	local qa = cs and cs.quantizeApply
	if qa and type(qa.Press) == "function" then
		call(qa.Press)
		call(qa.Release)
		log("quantize applied")
	else
		logOnce("quantize", "quantize unavailable: controlSurface.quantizeApply missing")
	end
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
	if adjustMode == "volume" then
		local db = gainToDb(propValue(trackAt(gc), "Volume"))
		local row = dbToRow(db)
		if delta > 0 then
			row = math.max(0, row - 1)
		else
			row = math.min(GRID_ROWS - 1, row + 1)
		end
		setTrackVolumeDB(gc, VOLUME_DB[row])
		paintAll()
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
	exitPadsMode() -- the fader menus need the whole grid
	tempoMode = false
	swingMode = false
	qlinkMode = false
	adjustMode = newMode
	adjustCol = 0
	lastPadCol, lastPadRow, lastPadTick = nil, nil, -100
	if newMode == "sends" then
		adjustSend = 1
	end
	log("menu " .. newMode)
	paintAll()
end

local function exitAdjust()
	if adjustMode then
		adjustMode = nil
		lastPadCol, lastPadRow, lastPadTick = nil, nil, -100
		log("menu off")
		paintAll()
	end
end

local function handleAdjustPad(col, row)
	if not adjustMode then
		return
	end
	local gc = globalPos(col, 0)
	if adjustMode == "volume" then
		setTrackVolumeDB(gc, VOLUME_DB[row])
		lastPadCol, lastPadRow, lastPadTick = col, row, ticks
		adjustCol = col
		paintAll()
		return
	end
	local value = (GRID_ROWS - row) / GRID_ROWS
	-- double-tapping the bottom pad reaches the true minimum (0.0)
	if col == lastPadCol and row == lastPadRow and ticks - lastPadTick <= 2 then
		if row == GRID_ROWS - 1 then
			value = 0
		end
	end
	lastPadCol, lastPadRow, lastPadTick = col, row, ticks
	adjustCol = col
	local name = adjustPropName()
	if name then
		setTrackValue(gc, name, value)
		paintAll()
	end
end

-- Shift + a function button: the shift function (undo/redo/click/tap/tempo/swing).
-- Shift is checked before the held-function state, so these run even while another
-- function button is held; the held function is left untouched.
-- Tap tempo: use dev.timer.Now() (ms, high resolution) and average the last
-- few tap intervals. Falls back to the 50 ms timer tick if Now() is missing.
local function doTapTempo()
	local now = call(dev.timer and dev.timer.Now)
	local useMs = type(now) == "number"
	if not useMs then
		now = ticks
	end
	local function diff(a, b)
		local d = a - b
		if useMs and d < 0 then
			d = d + 4294967296 -- 32-bit wrap
		end
		return d
	end
	-- a gap longer than 2 s starts a new tap sequence
	if #tapTicks > 0 and diff(now, tapTicks[#tapTicks]) > (useMs and 2000 or 40) then
		tapTicks = {}
	end
	tapTicks[#tapTicks + 1] = now
	if #tapTicks > 5 then
		table.remove(tapTicks, 1)
	end
	if #tapTicks < 2 then
		log("tap tempo: first tap")
		return
	end
	local total = 0
	for i = 2, #tapTicks do
		total = total + diff(tapTicks[i], tapTicks[i - 1])
	end
	local avg = total / (#tapTicks - 1)
	local bpm = (useMs and 60000 or 1200) / avg
	bpm = math.max(20, math.min(300, bpm))
	bpm = math.floor(bpm + 0.5) -- MPC BPM is an integer
	local sq = mpc.sequencer
	if sq and type(sq.SetBPM) == "function" then
		call(sq.SetBPM, bpm)
		log(string.format("tap tempo: %d BPM (%.1f ms)", bpm, avg))
	else
		logOnce("tapbpm", "tap tempo unavailable: sequencer.SetBPM missing")
	end
end

-- While Shift is held, CC 6 is handed to the MPC's own Tap Tempo control
-- (RemoveCCToScript + AddCCToControl, the stock MPK mini IV pattern); on Shift
-- release it is routed back to the script for the sends menu. Without the
-- controlSurface mapping the doTapTempo() averager stays the fallback.
local function updateTapTempoRouting(held)
	local m = dev.mappings and dev.mappings.script
	local cs = dev.mappings and dev.mappings.controlSurface
	if held and cs and type(cs.AddCCToControl) == "function" and type(cs.RemoveCCToControl) == "function" then
		local ok = pcall(function()
			m.RemoveCCToScript(0, TRACK.sends)
			cs.AddCCToControl(0, TRACK.sends, "Tap Tempo")
		end)
		if ok then
			nativeTap = true
			logOnce("tapnative", "tap tempo: native")
			return
		end
	end
	if nativeTap then
		call(cs and cs.RemoveCCToControl, 0, TRACK.sends)
		call(m and m.AddCCToScript, 0, TRACK.sends)
		nativeTap = false
	elseif held then
		-- a failed bind may have left CC 6 unregistered: keep it on the script
		call(m and m.AddCCToScript, 0, TRACK.sends)
	end
	if held then
		logOnce("tapmanual", "tap tempo: manual fallback")
	end
end

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
		-- CC 6 is routed to the MPC's native Tap Tempo while Shift is held;
		-- this manual averager only runs when that binding is unavailable
		if not nativeTap then
			doTapTempo()
		end
	elseif fn == "device" then
		exitPadsMode() -- the tempo page needs the whole grid
		adjustMode = nil
		swingMode = false
		qlinkMode = false
		tempoMode = not tempoMode
		tempoHold = nil
		if tempoMode then
			log("tempo page: " .. tostring(call(mpc.sequencer and mpc.sequencer.GetBPM)) .. " BPM")
		else
			log("tempo page off")
		end
		paintAll()
		flushLEDs()
	elseif fn == "stopClip" then
		exitPadsMode() -- the swing page needs the whole grid
		adjustMode = nil
		tempoMode = false
		qlinkMode = false
		tempoHold = nil
		swingMode = not swingMode
		swingHold = nil
		if swingMode then
			log(
				"swing page: "
					.. tostring(call(mpc.sequencer and mpc.sequencer.quantiser and mpc.sequencer.quantiser.GetSwing))
					.. "%"
			)
		else
			log("swing page off")
		end
		paintAll()
		flushLEDs()
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

-- Shift + play (CC 20): loop on/off (Loop is a userdata property with .value).
local function doLoopToggle()
	local sq = mpc.sequencer
	local loop = propValue(sq, "Loop")
	if not sq or sq.Loop == nil then
		logOnce("loop", "loop unavailable: sequencer.Loop missing")
		return
	end
	local ok = pcall(function()
		sq.Loop.value = not loop
	end)
	if not ok then
		logOnce("loopwrite", "loop unavailable: sequencer.Loop.value not writable")
		return
	end
	log("loop: " .. (loop and "off" or "on"))
end

-- Shift + record (CC 10): overdub (a plain sequencer function).
local function doOverdub()
	local sq = mpc.sequencer
	if not (sq and type(sq.Overdub) == "function") then
		logOnce("overdub", "overdub unavailable: sequencer.Overdub missing")
		return
	end
	call(sq.Overdub)
	log("overdub")
end

-- Shift + fixed length (CC 30): cycle the global automation filter type.
local function doAutomationFilterCycle()
	local pr = mpc.project
	if not (pr and type(pr.AdvanceGlobalAutomationFilterType) == "function") then
		logOnce("autofilter", "automation filter unavailable: project.AdvanceGlobalAutomationFilterType missing")
		return
	end
	call(pr.AdvanceGlobalAutomationFilterType)
	log("automation filter: cycled")
end

-- Shift + < / > (CC 91/92): MPC's current track previous/next.
local function doTrackNav(forward)
	local ct = mpc.tracks and mpc.tracks.currentTrack
	local f = forward and "Next" or "Previous"
	if not (ct and type(ct[f]) == "function") then
		logOnce("tracknav", "track nav unavailable: currentTrack." .. f .. " missing")
		return
	end
	call(ct[f])
	log("track: " .. (forward and "next" or "prev"))
end

-- Shift + note/chord (CC 94/95): previous/next plugin preset on the current
-- track (present on track objects in 3.10.1).
local function doPluginPreset(forward)
	local ct = mpc.tracks and mpc.tracks.currentTrack
	local f = forward and "NextPluginPreset" or "PrevPluginPreset"
	if not (ct and type(ct[f]) == "function") then
		logOnce("preset", "preset unavailable: currentTrack." .. f .. " missing")
		return
	end
	call(ct[f])
	log("preset: " .. (forward and "next" or "prev"))
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
		listenGrid() -- the slot properties follow the window: rebind, then repaint
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
		if padsMode then
			return -- a pad mode owns the grid; the unbound pads stay inert
		end
		if velocity > 0 then
			if heldFunction == "stopClip" then
				local gc = globalPos(col, 0)
				call(aperture and aperture.StopClipsOnTrack, gc)
				log("StopClipsOnTrack(" .. gc .. ")")
				paintAll()
			elseif clipOp == "clear" then
				local gc, gr = globalPos(col, row)
				call(mpc.clipMatrix and mpc.clipMatrix.DeleteClip, gc, gr)
				log(string.format("DeleteClip(%d,%d)", gc, gr))
				paintAll()
			elseif clipOp == "duplicate" then
				local gc, gr = globalPos(col, row)
				if clipOrigin == nil then
					clipOrigin = { gc, gr }
					log(string.format("duplicate origin (%d,%d)", gc, gr))
				else
					call(mpc.clipMatrix and mpc.clipMatrix.CopyClip, clipOrigin[1], clipOrigin[2], gc, gr)
					log(string.format("CopyClip(%d,%d -> %d,%d)", clipOrigin[1], clipOrigin[2], gc, gr))
					-- keep the origin so one source can be copied to many targets
					-- while the duplicate button is held
					paintAll()
				end
			elseif adjustMode then
				handleAdjustPad(col, row)
			elseif qlinkMode then
				handleQlinkPad(col, row)
			elseif not tempoMode and not swingMode then
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
			updateTapTempoRouting(false)
			paintTop()
			flushLEDs()
		end
		-- clip ops are hold-to-arm: releasing clear/duplicate disarms them
		if cc == LEFT.clear or cc == LEFT.duplicate then
			clipOp = nil
			clipOrigin = nil
			paintAll()
			flushLEDs()
		end
		-- releasing the tempo up/down button stops the auto-repeat
		if cc == LEFT.up or cc == LEFT.down then
			tempoHold = nil
			swingHold = nil
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
		updateTapTempoRouting(true)
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
		if shift then
			followMode = not followMode
			log("follow: " .. (followMode and "on" or "off"))
			if followMode then
				followCurrentTrack(propValue(mpc.tracks and mpc.tracks.currentTrack, "Index"))
			else
				paintTop()
				flushLEDs()
			end
			return
		end
		setMode("clip")
		return
	end
	if cc == TOP.sequencer then
		if shift then
			if pressSurfaceButton("stepSeqNext") then
				log("step seq: next")
			else
				logOnce("stepseqnext", "step seq next unavailable: controlSurface.stepSeqNext missing")
			end
		elseif pressSurfaceButton("stepSeq") then
			setMode("step")
			log("step seq view")
		else
			logOnce("stepseq", "step seq unavailable: controlSurface.stepSeq missing")
		end
		return
	end
	if shift and cc == TOP.note then
		doPluginPreset(false)
		return
	end
	if shift and cc == TOP.chord then
		doPluginPreset(true)
		return
	end
	if cc == TOP.chord then
		cyclePadUtility()
		return
	end
	if cc == TOP.note then
		togglePadsMode()
		paintAll()
		return
	end
	if padsMode and padsLayout == "chromatic" and (cc == LEFT.up or cc == LEFT.down) then
		local delta = (cc == LEFT.up) and 12 or -12
		padsBaseNote = math.max(24, math.min(96, padsBaseNote + delta))
		exitPadsMode()
		enterPadsMode()
		paintAll()
		log("chromatic base " .. padsBaseNote)
		return
	end
	if cc == TOP.custom then
		logOnce("custom", "custom mode: TODO (mutes live on the CC 2 hold-function)")
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
		if shift then
			doTrackNav(false)
		else
			moveWindow("left", 1)
		end
		return
	end
	if cc == TOP.right then
		if shift then
			doTrackNav(true)
		else
			moveWindow("right", 1)
		end
		return
	end
	if tempoMode and (cc == LEFT.up or cc == LEFT.down) then
		tempoHold = cc
		tempoHoldTicks = 0
		changeTempo(cc == LEFT.up and 1 or -1)
		return
	end
	if swingMode and (cc == LEFT.up or cc == LEFT.down) then
		swingHold = cc
		swingHoldTicks = 0
		changeSwing(cc == LEFT.up and 1 or -1)
		return
	end
	if adjustMode and (cc == LEFT.up or cc == LEFT.down) then
		nudgeAdjust(cc == LEFT.up and 1 / 8 or -1 / 8)
		return
	end
	if qlinkMode and (cc == LEFT.up or cc == LEFT.down) then
		if shift then
			nudgeQlink(cc == LEFT.up and 1 or -1)
		elseif qlinkPage == 0 and qlinkPageHasContent(1) then
			qlinkPage = 1
			log("qlink page 2")
			paintAll()
		elseif qlinkPage == 1 then
			qlinkPage = 0
			log("qlink page 1")
			paintAll()
		end
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
		if shift then
			doLoopToggle()
		else
			doTransport("play")
		end
		return
	end
	if cc == LEFT.record then
		if shift then
			doOverdub()
		else
			doTransport("record")
		end
		return
	end
	if shift and cc == LEFT.fixedLength then
		doAutomationFilterCycle()
		return
	end
	if cc == LEFT.quantize then
		doQuantize()
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
		if shift then
			if pressSurfaceButton("save") then
				log("save")
			else
				logOnce("save", "save unavailable: controlSurface.save missing")
			end
		else
			log("projects: TODO")
		end
		return
	end
	local fn = TRACK_FN[cc]
	if fn then
		if shift then
			doShiftFunction(fn)
			paintTrack()
			flushLEDs()
		elseif fn == "sends" then
			if adjustMode == "sends" then
				adjustSend = (adjustSend % 4) + 1
				log("send " .. adjustSend)
				paintAll()
			else
				enterAdjust("sends")
			end
		elseif fn == "volume" or fn == "pan" then
			if adjustMode == fn then
				exitAdjust()
			else
				enterAdjust(fn)
			end
		elseif fn == "device" then
			if qlinkMode then
				if qlinkPage == 0 and qlinkPageHasContent(1) then
					qlinkPage = 1
					log("qlink page 2")
					paintAll()
				else
					exitQlink()
				end
			else
				enterQlink()
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
	-- device identity reply: 7E <dev> 06 02 <00 20 29 Novation> <family> <model> <version...>
	if
		bytes:byte(1) == 0x7E
		and bytes:byte(3) == 0x06
		and bytes:byte(4) == 0x02
		and bytes:sub(5, 7) == string.char(0x00, 0x20, 0x29)
	then
		local ver = {}
		for i = 12, math.min(14, #bytes) do
			ver[#ver + 1] = tostring(bytes:byte(i))
		end
		logOnce("firmware", "firmware: " .. (#ver > 0 and table.concat(ver, ".") or "unknown"))
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
	-- timer runs at 50 ms; blink at 2 Hz (every 5 ticks) and full repaint every 2 s
	if ticks % 5 == 0 then
		blinkOn = not blinkOn
	end
	-- tempo page: holding up/down repeats, accelerating after a short delay
	if tempoMode and tempoHold then
		tempoHoldTicks = tempoHoldTicks + 1
		local interval = tempoHoldTicks < 10 and 6 or (tempoHoldTicks < 20 and 3 or 1)
		if tempoHoldTicks % interval == 0 then
			changeTempo(tempoHold == LEFT.up and 1 or -1)
		end
	end
	-- swing page: holding up/down repeats, accelerating after a short delay
	if swingMode and swingHold then
		swingHoldTicks = swingHoldTicks + 1
		local interval = swingHoldTicks < 10 and 6 or (swingHoldTicks < 20 and 3 or 1)
		if swingHoldTicks % interval == 0 then
			changeSwing(swingHold == LEFT.up and 1 or -1)
		end
	end
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
	if ticks % 40 == 0 then
		padCache = {}
		if padsMode then
			padsColourCache = {} -- force a full quadrant resend every 2 s
		end
	end -- resend everything every 2 s
	paintAll()
end

-----------------------------------------------------------------------------------------------
-- Load / unload
-----------------------------------------------------------------------------------------------

function LaunchpadProMK3.OnLoad()
	adjustMode = nil
	adjustSend = 1
	tempoMode = false
	swingMode = false
	qlinkMode = false
	qlinkPage = 0
	qlinkCol = 0
	followMode = false
	padsMode = false
	padsLayout = "drum"
	padsBaseNote = 48
	padUtility = "off"
	padsColourCache = {}
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

	-- device inquiry (universal sysex F0 7E 7F 06 01 F7): ask the LPP3 for its
	-- firmware version; log-only, the reply is parsed in HandleMIDISysex
	local okProbe = pcall(function()
		dev.midiOut.SendMIDISysex(string.char(0x7E, 0x7F, 0x06, 0x01), port)
	end)
	if not okProbe then
		logOnce("fwprobe", "firmware probe failed")
	end

	listenAll()
	paintAll()
	call(dev.timer and dev.timer.Start, 50)
	log("loaded")
end

function LaunchpadProMK3.OnUnload()
	call(dev.timer and dev.timer.Stop)
	removeListeners()
	exitPadsMode() -- hand the pad-mode notes back to the script before unmapping
	padsMode = false
	padsColourCache = {}
	adjustMode = nil
	adjustSend = 1
	tempoMode = false
	swingMode = false
	qlinkMode = false
	qlinkPage = 0
	qlinkCol = 0
	clipOp = nil
	clipOrigin = nil
	if programmerEntered then
		sendLayout(priorLayout or 0x04, priorPage or 0x00)
		log("restored layout")
	end
	if nativeTap then
		-- Shift was held: hand CC 6 back so the removal below unregisters the
		-- routing OnLoad registered
		local cs = dev.mappings and dev.mappings.controlSurface
		call(cs and cs.RemoveCCToControl, 0, TRACK.sends)
		nativeTap = false
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
