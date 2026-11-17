-- tests/mock-mpc.lua: a minimal MPC 3.10.1 API mock for the controller script.
-- Records every call; decodes the LPP3 LED sysex into M.leds[index] = {r,g,b}.
local M = { calls = {}, leds = {} }

local function record(name, ...)
  M.calls[#M.calls + 1] = { name = name, args = { ... } }
end
M.record = record

local function prop(v)
  local p = { value = v, listeners = {} }
  function p:listen(fn, name)
    self.listeners[#self.listeners + 1] = fn
  end
  function p:stopListening(name)
    self.listeners = {}
  end
  function p:set(v)
    self.value = v
    for _, fn in ipairs(self.listeners) do fn(v) end
  end
  return p
end
M.prop = prop

-- clip matrix
local clips = {}
M.clips = clips
local clipMatrix = {
  HasClip = function(gc, gr) return clips[gc] and clips[gc][gr] ~= nil end,
  ClipIsPlaying = function(gc, gr) return clips[gc] and clips[gc][gr] == "playing" end,
  ClipIsRecording = function(gc, gr) return clips[gc] and clips[gc][gr] == "recording" end,
  ClipIsStopped = function(gc, gr) return clips[gc] and clips[gc][gr] == "stopped" end,
  GetClipColour = function(gc, gr) return 0xFF0000 end,
  StopAllClips = function() record("StopAllClips") end,
}

-- tracks
local tracks = {}
for i = 0, 7 do
  local t = {
    RecArm = prop(false),
    Mute = prop(false),
    Solo = prop(false),
    Colour = prop(0x00FF00),
    Name = prop("Track " .. i),
    Volume = prop(0.5),
    Pan = prop(0.5),
    Sends1 = prop(0),
    Sends2 = prop(0),
    Sends3 = prop(0),
    Sends4 = prop(0),
  }
  t.SetRecArm = function(v) record("SetRecArm", i, v); t.RecArm:set(v) end
  t.SetMute = function(v) record("SetMute", i, v); t.Mute:set(v) end
  t.SetSolo = function(v) record("SetSolo", i, v); t.Solo:set(v) end
  tracks[i] = t
end

-- sequencer
local sequencer = {
  Play = function() record("Play") end,
  TogglePlay = function() record("TogglePlay") end,
  Stop = function() record("Stop") end,
  Record = function() record("Record") end,
  IsPlaying = function() return false end,
  Playing = prop(false),
  RecordState = prop(false),
  OverdubState = prop(false),
  SetMetronomeEnabled = function(v) record("SetMetronomeEnabled", v) end,
  MetronomeEnabled = prop(false),
}

-- command manager
local commandManager = {
  Undo = function() record("Undo") end,
  Redo = function() record("Redo") end,
}

-- aperture + clip properties
local clipProperties = {}
for c = 0, 7 do
  clipProperties[c] = {}
  for r = 0, 7 do
    clipProperties[c][r] = { Colour = prop(0xFF0000), State = prop(2), Selected = prop(false) }
  end
end

local sceneProperties = {}
for r = 0, 7 do sceneProperties[r] = { State = prop(2) } end

local originCol = 0
local aperture = {
  SetColumns = function(n) record("SetColumns", n) end,
  SetRows = function(n) record("SetRows", n) end,
  SetLabel = function(s) record("SetLabel", s) end,
  SetFollowsTUI = function(b) record("SetFollowsTUI", b) end,
  Show = function() record("Show") end,
  Hide = function() record("Hide") end,
  TriggerClip = function(c, r) record("TriggerClip", c, r) end,
  TriggerRow = function(r) record("TriggerRow", r) end,
  StopClipsOnTrack = function(c) record("StopClipsOnTrack", c) end,
  SelectClip = function(c, r) record("SelectClip", c, r) end,
  SelectTrack = function(i) record("SelectTrack", i) end,
  MoveLeft = function(n) originCol = originCol - n; record("MoveLeft", n) end,
  MoveRight = function(n) originCol = originCol + n; record("MoveRight", n) end,
  MoveUp = function(n) record("MoveUp", n) end,
  MoveDown = function(n) record("MoveDown", n) end,
  ToGlobalColumn = function(c) return c + originCol end,
  ToGlobalRow = function(r) return r end,
  ToLocalColumn = function(i) return i - originCol end,
  ToLocalRow = function(i) return i end,
  clipProperties = clipProperties,
  sceneProperties = sceneProperties,
}

-- mappings
local mappings = {
  script = {
    AddNoteToScript = function(ch, n) record("AddNoteToScript", ch, n) end,
    AddCCToScript = function(ch, cc) record("AddCCToScript", ch, cc) end,
    RemoveNoteToScript = function(ch, n) record("RemoveNoteToScript", ch, n) end,
    RemoveCCToScript = function(ch, cc) record("RemoveCCToScript", ch, cc) end,
    SetHandleSysex = function(b) record("SetHandleSysex", b) end,
  },
}

-- midi out
local midiOut = {
  SendMIDINoteOn = function(ch, n, v, p) record("SendMIDINoteOn", ch, n, v, p) end,
  SendMIDICC = function(ch, cc, v, p) record("SendMIDICC", ch, cc, v, p) end,
  SendMIDISysex = function(bytes, p)
    record("SendMIDISysex", bytes, p)
    -- decode the LPP3 LED sysex payload: 00 20 29 02 0E 03 <specs>
    if bytes:sub(1, 6) == string.char(0x00, 0x20, 0x29, 0x02, 0x0E, 0x03) then
      local i = 7
      while i <= #bytes do
        local typ = bytes:byte(i)
        local idx = bytes:byte(i + 1)
        if typ == 3 then
          M.leds[idx] = { bytes:byte(i + 2), bytes:byte(i + 3), bytes:byte(i + 4) }
          i = i + 5
        elseif typ == 0 or typ == 2 then
          M.leds[idx] = { typ, bytes:byte(i + 2) }
          i = i + 3
        elseif typ == 1 then
          M.leds[idx] = { typ, bytes:byte(i + 2), bytes:byte(i + 3) }
          i = i + 4
        else
          break
        end
      end
    end
  end,
}

-- timer
local timer = {
  Start = function(ms) record("timer.Start", ms) end,
  Stop = function() record("timer.Stop") end,
}

-- assemble
local mpc = {
  clipMatrix = clipMatrix,
  tracks = { normalTracks = tracks, currentTrack = { Index = prop(0) } },
  sequencer = sequencer,
  commandManager = commandManager,
  controlSurface = { pads = { Tap = function() end, Press = function() end, Release = function() end } },
  ui = { ShowTUIFeedback = function(s) record("ShowTUIFeedback", s) end },
  engineMode = { CurrentMode = prop("clip") },
}

local dev = {
  clipMatrixAperture = aperture,
  clipProperties = clipProperties,
  mappings = mappings,
  midiOut = midiOut,
  timer = timer,
}

M.mpc = mpc
M.dev = dev
M.aperture = aperture
M.clipProperties = clipProperties
M.tracks = tracks
M.sequencer = sequencer
M.commandManager = commandManager
M.midiOut = midiOut
M.timer = timer

function M.reset()
  M.calls = {}
  M.leds = {}
end

function M.find(name)
  local out = {}
  for _, c in ipairs(M.calls) do
    if c.name == name then out[#out + 1] = c end
  end
  return out
end

function M.count(name)
  return #M.find(name)
end

return M
