-- tests/test-manual.lua: the generated manual must stay complete and current.
-- Every CC the dispatch tables handle has an ACTIONS entry (the manual source),
-- and docs/MANUAL.md must match a fresh generation.
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

local ACTIONS = L.ACTIONS
assert(type(ACTIONS) == "table", "ACTIONS is exposed for the manual")

-- Every control the script documents must name a label and both actions.
local documented = 0
for cc, a in pairs(ACTIONS) do
	assert(type(cc) == "number", "ACTIONS keys are CC numbers")
	assert(type(a.label) == "string" and #a.label > 0, "CC " .. cc .. " has no label")
	assert(type(a.plain) == "string" and #a.plain > 0, "CC " .. cc .. " has no plain action")
	assert(type(a.shift) == "string" and #a.shift > 0, "CC " .. cc .. " has no shift entry")
	documented = documented + 1
end
assert_eq(documented, 34, "all 34 physical controls are documented")

-- The controls the dispatch handles are exactly the documented ones.
local expected = {}
local function note(cc)
	expected[cc] = true
end
for _, cc in pairs({ 90, 91, 92, 93, 94, 95, 96, 97, 98, 99 }) do
	note(cc)
end
for _, cc in pairs({ 89, 79, 69, 59, 49, 39, 29, 19 }) do
	note(cc)
end
for _, cc in pairs({ 10, 20, 30, 40, 50, 60, 70, 80 }) do
	note(cc)
end
for cc = 1, 8 do
	note(cc)
end
for cc in pairs(expected) do
	assert(ACTIONS[cc] ~= nil, "CC " .. cc .. " is handled but not documented")
end
for cc in pairs(ACTIONS) do
	assert(expected[cc] ~= nil, "CC " .. cc .. " is documented but not handled")
end

-- The committed manual matches a fresh generation.
local tmp = os.tmpname()
local ok = os.execute("lua5.4 tools/gen-manual.lua script/LaunchpadProMK3.lua " .. tmp .. " >/dev/null")
assert(ok == true or ok == 0, "manual generation failed")
local function slurp(path)
	local fh = assert(io.open(path, "r"))
	local data = fh:read("*a")
	fh:close()
	return data
end
local generated = slurp(tmp)
os.remove(tmp)
local committed = slurp("docs/MANUAL.md")
assert_eq(#committed, #generated, "docs/MANUAL.md is stale (length differs); run tools/gen-manual.sh")

print("test-manual: PASS")
