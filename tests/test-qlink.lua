-- tests/test-qlink.lua: Q-Link page (CC 7 device), driven by Twist on controlSurface.qlinks.
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

local function lastCall(name)
	local calls = mock.find(name)
	return calls[#calls]
end

local logs = {}
local realPrint = print
_G.print = function(...)
	logs[#logs + 1] = table.concat({ ... }, " ")
end
local function lastLog()
	return logs[#logs] or ""
end

local function touchesOf(i)
	local n = 0
	for _, t in ipairs(mock.find("Touch")) do
		if t.args[1] == i then
			n = n + 1
		end
	end
	return n
end

L.OnLoad()

-- Press CC 7 (device) to enter the Q-Link page; entering must not write any qlink.
L.HandleMIDICC(0, 7, 127)
assert_eq(mock.count("SetPosition"), 0, "no SetPosition on enter")
assert_eq(mock.count("Twist"), 0, "no Twist on enter")
assert_eq(mock.leds[7][1], 127, "device button white on qlink page")

-- Top pad in column 0: Q-Link 0 -> 127, one Twist(127) from position 0.
L.HandleMIDINoteOn(0, 81, 100)
local c = lastCall("Twist")
assert_eq(c.args[1], 0, "qlink 0")
assert_eq(c.args[2], 127, "qlink 0 delta 127")
assert_eq(mock.qlinks[0]:GetPosition(), 127, "qlink 0 position 127")
assert_eq(touchesOf(0), 2, "Touch before + after the twist burst")

-- Bottom pad in column 1: column-major order puts Q-Link 4 there -> 16 (1/8 of 127).
L.HandleMIDINoteOn(0, 12, 100)
c = lastCall("Twist")
assert_eq(c.args[1], 4, "qlink 4 in column 1")
assert_eq(c.args[2], 16, "qlink 4 delta 16")
assert_eq(mock.qlinks[4]:GetPosition(), 16, "qlink 4 position 16")

-- Up arrow switches to page 2 (display order slots 9-16: Q-Links 2,6,10,14,...); down goes back.
L.HandleMIDICC(0, 80, 127)
L.HandleMIDINoteOn(0, 81, 100)
c = lastCall("Twist")
assert_eq(c.args[1], 2, "qlink 2 on page 2")
assert_eq(c.args[2], 127, "qlink 2 delta 127")
assert_eq(mock.qlinks[2]:GetPosition(), 127, "qlink 2 position 127")
L.HandleMIDICC(0, 70, 127)
L.HandleMIDICC(0, 80, 127)

-- Shift+down nudges qlink 2 (last touched column) by -1; Shift+up nudges +1, no wrap past 127.
L.HandleMIDICC(0, 90, 127) -- shift on
L.HandleMIDICC(0, 70, 127) -- shift+down
c = lastCall("Twist")
assert_eq(c.args[1], 2, "qlink 2 nudge target")
assert_eq(c.args[2], -1, "nudge -1")
assert_eq(mock.qlinks[2]:GetPosition(), 126, "qlink 2 = 126")
L.HandleMIDICC(0, 80, 127) -- shift+up
assert_eq(mock.qlinks[2]:GetPosition(), 127, "qlink 2 back to 127")
L.HandleMIDICC(0, 80, 127) -- shift+up at 127 is skipped
assert_eq(mock.qlinks[2]:GetPosition(), 127, "no wrap past 127")
L.HandleMIDICC(0, 90, 0) -- shift off

-- Fallback: a qlink without Twist is driven with SetPosition.
L.HandleMIDICC(0, 70, 127) -- back to page 1
local savedTwist = mock.qlinks[4].Twist
mock.qlinks[4].Twist = nil
L.HandleMIDINoteOn(0, 12, 100) -- column 2 = qlink 4
c = lastCall("SetPosition")
assert_eq(c.args[1], 4, "fallback qlink 4")
assert_eq(c.args[2], 16, "fallback position 16")
mock.qlinks[4].Twist = savedTwist

-- Shift+CC 7 opens the tempo page and closes the Q-Link page (mutual exclusion):
-- a pad press must neither launch a clip nor touch a qlink.
L.HandleMIDICC(0, 90, 127)
L.HandleMIDICC(0, 7, 127) -- shift + device = tempo page
L.HandleMIDICC(0, 90, 0)
local twistCount = mock.count("Twist")
local clipCount = mock.count("TriggerClip")
L.HandleMIDINoteOn(0, 81, 100)
assert_eq(mock.count("Twist"), twistCount, "no twist on tempo page")
assert_eq(mock.count("TriggerClip"), clipCount, "no clip launch on tempo page")

-- CC 7 re-enters the Q-Link page (and closes the tempo page); pads drive qlinks again.
L.HandleMIDICC(0, 7, 127)
L.HandleMIDINoteOn(0, 21, 100)
c = lastCall("Twist")
assert_eq(c.args[1], 0, "qlink 0 after re-enter")
assert_eq(c.args[2], -95, "qlink 0 delta to 32")
assert_eq(mock.qlinks[0]:GetPosition(), 32, "qlink 0 = 32")

-- Press CC 7 twice to exit (page 2 first); a pad now launches a clip, button available.
L.HandleMIDICC(0, 7, 127)
L.HandleMIDICC(0, 7, 127)
L.HandleMIDINoteOn(0, 11, 100)
assert_eq(mock.count("TriggerClip"), clipCount + 1, "clip launch after exit")
assert_eq(mock.leds[7][1], 60, "device button available after exit")
assert_eq(mock.leds[7][2], 60, "device button available (green)")
assert_eq(mock.leds[7][3], 60, "device button available (blue)")

L.OnUnload()
-- Compaction: only assigned qlinks get columns, packed left with no gaps.
-- Only qlinks 0, 3, 5, 9 assigned -> page 1 columns are [0, 3, 5, 9], rest dark;
-- with <= 8 assigned a Device tap exits directly (no empty second page).
for i = 0, 15 do
	mock.setQlinkTarget(i, "")
end
mock.setQlinkTarget(0, "Kill EQ Low")
mock.setQlinkTarget(3, "Beat Repeat")
mock.setQlinkTarget(5, "Kill EQ Mid")
mock.setQlinkTarget(9, "Beat Repeat Delay")
mock.qlinks[0].SetPosition(127)
mock.qlinks[3].SetPosition(127)
mock.qlinks[5].SetPosition(127)
L.HandleMIDICC(0, 7, 127) -- enter: page 1 (paints the current positions)
-- column-major order of {0,3,5,9} is 0, 5, 9, 3
assert_eq(
	lastLog(),
	"LaunchpadProMK3: qlink page (4 assigned): 1=Kill EQ Low, 2=Kill EQ Mid, 3=Beat Repeat Delay, 4=Beat Repeat",
	"page-open map log (column-major order)"
)
assert_eq(mock.leds[11][2], 127, "column 1 = qlink 0 cyan")
assert_eq(mock.leds[12][1], 127, "column 2 = qlink 5 magenta r")
assert_eq(mock.leds[12][2], 0, "column 2 = qlink 5 magenta g")
assert_eq(mock.leds[13][1], 12, "column 3 = qlink 9 dim at position 0")
assert_eq(mock.leds[14][2], 127, "column 4 = qlink 3 cyan g")
assert_eq(mock.leds[15] and mock.leds[15][2] or 0, 0, "column 5 dark (only 4 assigned)")
assert_eq(mock.leds[18] and mock.leds[18][2] or 0, 0, "column 8 dark")
L.HandleMIDINoteOn(0, 82, 100) -- column 2 top pad drives qlink 5 to 127
assert_eq(mock.qlinks[5]:GetPosition(), 127, "compacted column 2 drives qlink 5")
L.HandleMIDINoteOn(0, 13, 100) -- column 3 bottom pad drives qlink 9 to 16
assert_eq(mock.qlinks[9]:GetPosition(), 16, "compacted column 3 drives qlink 9")
L.HandleMIDINoteOn(0, 18, 100) -- column 7 has no qlink: inert
L.HandleMIDICC(0, 7, 127) -- <= 8 assigned: Device tap exits directly
assert_eq(lastLog(), "LaunchpadProMK3: qlink page off", "device tap exits when page 2 would be empty")

-- Device tap cycles pages when more than 8 are assigned.
for i = 0, 15 do
	mock.setQlinkTarget(i, i % 2 == 0 and "Param " .. i or "")
end -- assigned: 0,2,4,6,8,10,12,14 (8) + need >8: also 1
mock.setQlinkTarget(1, "Param 1")
L.HandleMIDICC(0, 7, 127) -- enter: page 1
L.HandleMIDICC(0, 7, 127) -- tap again: page 2 (9 assigned)
assert_eq(lastLog(), "LaunchpadProMK3: qlink page 2", "device tap switches to page 2")
assert_eq(mock.leds[7][1], 127, "device button still white on page 2")
L.HandleMIDICC(0, 7, 127) -- tap again: exit
assert_eq(lastLog(), "LaunchpadProMK3: qlink page off", "third tap exits")
mock.reset()

-- Re-enter page 1 for colour + flip tests.
L.HandleMIDICC(0, 7, 127)
mock.reset()
-- bank colours on page 1 (column-major): column 1 = Q-Link 0 (cyan), column 2 = Q-Link 4 (magenta)
local pos0 = mock.qlinks[0]:GetPosition()
local pos4 = mock.qlinks[4]:GetPosition()
mock.qlinks[0].SetPosition(127)
mock.qlinks[4].SetPosition(127)
L.HandleMIDICC(0, 7, 127) -- -> page 2
L.HandleMIDICC(0, 7, 127) -- -> exit
L.HandleMIDICC(0, 7, 127) -- -> page 1 again (fresh paint)
assert_eq(mock.leds[81][2], 127, "qlink 0 top pad cyan g")
assert_eq(mock.leds[81][1], 0, "qlink 0 top pad cyan r")
assert_eq(mock.leds[82][1], 127, "qlink 4 top pad magenta r")
assert_eq(mock.leds[82][2], 0, "qlink 4 top pad magenta g")
mock.qlinks[0].SetPosition(pos0 or 0)
mock.qlinks[4].SetPosition(pos4 or 0)

-- Flip parameters: two value strings across a wide span -> presses round to extremes,
-- and the column shows a single lit extreme pad.
mock.setQlinkBinary(0)
L.HandleMIDINoteOn(0, 81, 100) -- column 1 = qlink 0 top pad -> 127 ("Kill")
L.HandleMIDINoteOn(0, 11, 100) -- column 1 = qlink 0 bottom pad -> 16 ("Thru")
local flipLogged = false
for _, l in ipairs(logs) do
	if l == "LaunchpadProMK3: qlink 0 flip parameter" then
		flipLogged = true
	end
end
assert_eq(flipLogged and true or false, true, "flip parameter learned")
L.HandleMIDINoteOn(0, 41, 100) -- column 1 middle pad, bottom half -> rounds to 0
assert_eq(mock.qlinks[0]:GetPosition(), 0, "flip press rounds to the min extreme")
L.HandleMIDINoteOn(0, 51, 100) -- column 1 middle pad, top half -> rounds to 127
assert_eq(mock.qlinks[0]:GetPosition(), 127, "flip press rounds to the max extreme")
-- display at the max extreme: only the top pad is lit (cyan = bank colour of qlink 2)
assert_eq(mock.leds[81][1], 0, "flip max extreme pad lit (cyan r=0)")
assert_eq(mock.leds[81][2], 127, "flip max extreme pad lit (cyan g)")
assert_eq(mock.leds[11][1], 12, "flip: bottom pad dim when at max")

_G.print = realPrint
print("test-qlink: PASS")
