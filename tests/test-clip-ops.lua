-- tests/test-clip-ops.lua: left-column clear/duplicate via clipMatrix.DeleteClip/CopyClip.
package.path = "./tests/?.lua;" .. package.path
local mock = require("mock-mpc")
_G.mpc = mock.mpc
_G.dev = mock.dev
_G.LaunchpadProMK3 = mock.dev
dofile("script/LaunchpadProMK3.lua")
local L = LaunchpadProMK3

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end
end

L.OnLoad()

-- clear (CC 60) arms, then a clip pad deletes that clip. The API row is
-- 7 - visual row (the API counts from the bottom).
L.HandleMIDICC(0, 60, 127)
L.HandleMIDINoteOn(0, 11, 100) -- col 0, visual row 7 -> API row 0
assert_eq(mock.count("DeleteClip"), 1, "clear -> DeleteClip")
assert_eq(mock.find("DeleteClip")[1].args[1], 0, "DeleteClip col")
assert_eq(mock.find("DeleteClip")[1].args[2], 0, "DeleteClip row")
assert_eq(mock.count("CopyClip"), 0, "clear does not copy")

-- The clear op stays armed: a second pad deletes another clip.
L.HandleMIDINoteOn(0, 12, 100) -- col 1, visual row 7 -> API row 0
assert_eq(mock.count("DeleteClip"), 2, "second clear -> DeleteClip")
assert_eq(mock.find("DeleteClip")[2].args[1], 1, "second DeleteClip col")

-- duplicate (CC 50) arms, origin pad then target pad copies.
L.HandleMIDICC(0, 50, 127)
L.HandleMIDINoteOn(0, 11, 100) -- origin col 0, visual row 7 -> API row 0
assert_eq(mock.count("CopyClip"), 0, "origin does not copy yet")
L.HandleMIDINoteOn(0, 12, 100) -- target col 1, visual row 7 -> API row 0
assert_eq(mock.count("CopyClip"), 1, "duplicate -> CopyClip")
local a = mock.find("CopyClip")[1].args
assert_eq(a[1], 0, "CopyClip from col")
assert_eq(a[2], 0, "CopyClip from row")
assert_eq(a[3], 1, "CopyClip to col")
assert_eq(a[4], 0, "CopyClip to row")
assert_eq(mock.count("DeleteClip"), 2, "duplicate does not delete")

-- The duplicate op stays armed: another origin/target pair copies again.
L.HandleMIDINoteOn(0, 13, 100) -- origin col 2
L.HandleMIDINoteOn(0, 14, 100) -- target col 3
assert_eq(mock.count("CopyClip"), 2, "second duplicate -> CopyClip")
assert_eq(mock.find("CopyClip")[2].args[1], 2, "second CopyClip from col")
assert_eq(mock.find("CopyClip")[2].args[3], 3, "second CopyClip to col")

-- quantize (CC 40) stays a stub: no clip calls.
L.HandleMIDICC(0, 40, 127)
assert_eq(mock.count("CopyClip"), 2, "quantize does not copy")
assert_eq(mock.count("DeleteClip"), 2, "quantize does not delete")

L.OnUnload()

-- degrade: clipMatrix.DeleteClip/CopyClip nil -> no crash, log.
mock.mpc.clipMatrix.DeleteClip = nil
mock.mpc.clipMatrix.CopyClip = nil
mock.reset()
local logs = {}
local realPrint = print
_G.print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
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
    if line:find(needle, 1, true) then return true end
  end
  return false
end
assert(logged("DeleteClip(0,0)"), "clear logs DeleteClip")
assert(logged("CopyClip(0,0 -> 1,0)"), "duplicate logs CopyClip")
assert(logged("quantize: TODO"), "quantize TODO")
assert_eq(mock.count("DeleteClip"), 0, "degrade: no DeleteClip")
assert_eq(mock.count("CopyClip"), 0, "degrade: no CopyClip")

print("test-clip-ops: PASS")
