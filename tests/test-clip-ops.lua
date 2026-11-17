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

-- clear (CC 60) arms, then a clip pad deletes that clip.
L.HandleMIDICC(0, 60, 127)
L.HandleMIDINoteOn(0, 11, 100) -- col 0, row 7
assert_eq(mock.count("DeleteClip"), 1, "clear -> DeleteClip")
assert_eq(mock.find("DeleteClip")[1].args[1], 0, "DeleteClip col")
assert_eq(mock.find("DeleteClip")[1].args[2], 7, "DeleteClip row")
assert_eq(mock.count("CopyClip"), 0, "clear does not copy")

-- duplicate (CC 50) arms, origin pad then target pad copies.
L.HandleMIDICC(0, 50, 127)
L.HandleMIDINoteOn(0, 11, 100) -- origin col 0, row 7
assert_eq(mock.count("CopyClip"), 0, "origin does not copy yet")
L.HandleMIDINoteOn(0, 12, 100) -- target col 1, row 7
assert_eq(mock.count("CopyClip"), 1, "duplicate -> CopyClip")
local a = mock.find("CopyClip")[1].args
assert_eq(a[1], 0, "CopyClip from col")
assert_eq(a[2], 7, "CopyClip from row")
assert_eq(a[3], 1, "CopyClip to col")
assert_eq(a[4], 7, "CopyClip to row")
assert_eq(mock.count("DeleteClip"), 1, "duplicate does not delete")

-- quantize (CC 40) stays a stub: no clip calls.
L.HandleMIDICC(0, 40, 127)
assert_eq(mock.count("CopyClip"), 1, "quantize does not copy")
assert_eq(mock.count("DeleteClip"), 1, "quantize does not delete")

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
assert(logged("DeleteClip(0,7)"), "clear logs DeleteClip")
assert(logged("CopyClip(0,7 -> 1,7)"), "duplicate logs CopyClip")
assert(logged("quantize: TODO"), "quantize TODO")
assert_eq(mock.count("DeleteClip"), 0, "degrade: no DeleteClip")
assert_eq(mock.count("CopyClip"), 0, "degrade: no CopyClip")

print("test-clip-ops: PASS")
