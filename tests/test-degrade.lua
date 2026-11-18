-- tests/test-degrade.lua: the script loads and runs with optional APIs removed.
package.path = "./tests/?.lua;" .. package.path
local mock = require("mock-mpc")
_G.mpc = mock.mpc
_G.dev = mock.dev
-- remove optional APIs
mock.dev.clipMatrixAperture = nil
mock.mpc.clipMatrix = nil
mock.mpc.sequencer = nil
mock.mpc.commandManager = nil
_G.LaunchpadProMK3 = mock.dev
dofile(os.getenv("LPP3_LUA") or "script/LaunchpadProMK3.lua")
local L = LaunchpadProMK3
L.OnLoad()
L.HandleMIDINoteOn(0, 11, 100)
L.HandleMIDICC(0, 101, 127)
L.HandleMIDICC(0, 20, 127)
L.HandleTimer()
L.OnUnload()
print("test-degrade: PASS")
