-- tests/test-clip-ops.lua: left-column clear/duplicate via clipMatrix.DeleteClip/CopyClip.
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

L.OnLoad()

-- clear (CC 60) is hold-to-arm: while held, each clip pad deletes that clip.
-- Clip ops use the global matrix position (same coords as HasClip/TriggerClip),
-- so the window origin is added. Note 11 is col 0, visual row 7 (bottom).
L.HandleMIDICC(0, 60, 127)
assert_eq(mock.leds[60][1], 127, "clear button lit while held")
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("DeleteClip"), 1, "clear -> DeleteClip")
assert_eq(mock.find("DeleteClip")[1].args[1], 0, "DeleteClip col")
assert_eq(mock.find("DeleteClip")[1].args[2], 7, "DeleteClip row")

-- Still held: a second pad deletes another clip.
L.HandleMIDINoteOn(0, 12, 100) -- col 1, visual row 7
assert_eq(mock.count("DeleteClip"), 2, "second clear -> DeleteClip")
assert_eq(mock.find("DeleteClip")[2].args[1], 1, "second DeleteClip col")
assert_eq(mock.find("DeleteClip")[2].args[2], 7, "second DeleteClip row")

-- Releasing clear disarms it: the next pad must not delete.
L.HandleMIDICC(0, 60, 0)
assert_eq(mock.leds[60][1], 127, "clear button available after release")
L.HandleMIDINoteOn(0, 13, 100)
assert_eq(mock.count("DeleteClip"), 2, "released clear does not delete")

-- duplicate (CC 50) is hold-to-arm: origin pad, then any number of targets.
L.HandleMIDICC(0, 50, 127)
assert_eq(mock.leds[50][1], 127, "duplicate button lit while held")
L.HandleMIDINoteOn(0, 11, 100) -- origin col 0, visual row 7
assert_eq(mock.count("CopyClip"), 0, "origin does not copy yet")
L.HandleMIDINoteOn(0, 12, 100) -- target col 1
assert_eq(mock.count("CopyClip"), 1, "duplicate -> CopyClip")
local a = mock.find("CopyClip")[1].args
assert_eq(a[1], 0, "CopyClip from col")
assert_eq(a[2], 7, "CopyClip from row")
assert_eq(a[3], 1, "CopyClip to col")
assert_eq(a[4], 7, "CopyClip to row")
assert_eq(mock.count("DeleteClip"), 2, "duplicate does not delete")

-- The origin persists while held: one source copies to more targets.
L.HandleMIDINoteOn(0, 13, 100) -- target col 2
L.HandleMIDINoteOn(0, 14, 100) -- target col 3
assert_eq(mock.count("CopyClip"), 3, "one source -> multiple targets")
assert_eq(mock.find("CopyClip")[2].args[1], 0, "second CopyClip from col")
assert_eq(mock.find("CopyClip")[2].args[3], 2, "second CopyClip to col")
assert_eq(mock.find("CopyClip")[3].args[1], 0, "third CopyClip from col")
assert_eq(mock.find("CopyClip")[3].args[3], 3, "third CopyClip to col")

-- Releasing duplicate disarms it: the next pad must not copy.
L.HandleMIDICC(0, 50, 0)
L.HandleMIDINoteOn(0, 15, 100)
assert_eq(mock.count("CopyClip"), 3, "released duplicate does not copy")

-- Scrolled window: clip ops must use the global row, not the window row.
mock.aperture.MoveUp(2) -- originRow = -2, so window row 7 = global row 5
L.HandleMIDICC(0, 60, 127)
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("DeleteClip"), 3, "scrolled clear -> DeleteClip")
assert_eq(mock.find("DeleteClip")[3].args[2], 5, "scrolled DeleteClip global row")
L.HandleMIDICC(0, 60, 0)
mock.aperture.MoveDown(2) -- restore originRow = 0

-- quantize (CC 40) stays a stub: no clip calls.
L.HandleMIDICC(0, 40, 127)
assert_eq(mock.count("CopyClip"), 3, "quantize does not copy")
assert_eq(mock.count("DeleteClip"), 3, "quantize does not delete")

L.OnUnload()

-- degrade: clipMatrix.DeleteClip/CopyClip nil -> no crash, log.
mock.mpc.clipMatrix.DeleteClip = nil
mock.mpc.clipMatrix.CopyClip = nil
mock.reset()
local logs = {}
local realPrint = print
_G.print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logs[#logs + 1] = table.concat(parts, " ")
end
dofile("script/LaunchpadProMK3.lua")
L = LaunchpadProMK3
L.OnLoad()
L.HandleMIDICC(0, 60, 127)
L.HandleMIDINoteOn(0, 11, 100)
L.HandleMIDICC(0, 50, 127)
L.HandleMIDINoteOn(0, 11, 100)
L.HandleMIDINoteOn(0, 12, 100)
L.HandleMIDICC(0, 40, 127)
L.OnUnload()
_G.print = realPrint

local function logged(needle)
	for _, line in ipairs(logs) do
		if line:find(needle, 1, true) then
			return true
		end
	end
	return false
end
assert(logged("DeleteClip(0,7)"), "clear logs DeleteClip")
assert(logged("CopyClip(0,7 -> 1,7)"), "duplicate logs CopyClip")
assert(logged("quantize applied"), "quantize applied")
assert_eq(mock.count("DeleteClip"), 0, "degrade: no DeleteClip")
assert_eq(mock.count("CopyClip"), 0, "degrade: no CopyClip")

print("test-clip-ops: PASS")
