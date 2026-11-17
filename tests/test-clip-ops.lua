-- tests/test-clip-ops.lua: left-column clear/duplicate via the virtual Force buttons.
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

-- clear (CC 60) presses Force DELETE
L.HandleMIDICC(0, 60, 127)
assert_eq(mock.count("force.delete.Press"), 1, "clear -> delete Press")
assert_eq(mock.count("force.delete.Release"), 1, "clear -> delete Release")
assert_eq(mock.count("force.copy.Press"), 0, "clear does not copy")

-- duplicate (CC 50) presses Force COPY
L.HandleMIDICC(0, 50, 127)
assert_eq(mock.count("force.copy.Press"), 1, "duplicate -> copy Press")
assert_eq(mock.count("force.copy.Release"), 1, "duplicate -> copy Release")
assert_eq(mock.count("force.delete.Press"), 1, "duplicate does not delete")

-- quantize (CC 40) stays a stub: no Force calls
L.HandleMIDICC(0, 40, 127)
assert_eq(mock.count("force.copy.Press"), 1, "quantize does not copy")
assert_eq(mock.count("force.delete.Press"), 1, "quantize does not delete")

L.OnUnload()

-- degrade: mpc.force nil -> clear/duplicate log a TODO naming the missing API, no crash
mock.mpc.force = nil
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
L.HandleMIDICC(0, 50, 127)
L.HandleMIDICC(0, 40, 127)
L.OnUnload()
_G.print = realPrint

local function logged(needle)
  for _, line in ipairs(logs) do
    if line:find(needle, 1, true) then return true end
  end
  return false
end
assert(logged("clear: TODO (mpc.force.delete unavailable)"), "clear TODO names the missing API")
assert(logged("duplicate: TODO (mpc.force.copy unavailable)"), "duplicate TODO names the missing API")
assert(logged("quantize: TODO"), "quantize TODO")
assert_eq(mock.count("force.copy.Press"), 0, "degrade: no copy Press")
assert_eq(mock.count("force.delete.Press"), 0, "degrade: no delete Press")

print("test-clip-ops: PASS")
