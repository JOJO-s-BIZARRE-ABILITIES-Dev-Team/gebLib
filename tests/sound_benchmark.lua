local cbrIterations = tonumber(arg and arg[1]) or 1000
local fastIterations = tonumber(arg and arg[2]) or 200000
local cacheIterations = tonumber(arg and arg[3]) or 100000000
local sourcePath = (arg and arg[4]) or "lua/geblib/sound.lua"
local warmupLimit = tonumber(arg and arg[5]) or 1000

bit = require("bit")

local ffi = require("ffi")
ffi.cdef([[
typedef long long geblib_benchmark_counter;
int __stdcall QueryPerformanceCounter(geblib_benchmark_counter *value);
int __stdcall QueryPerformanceFrequency(geblib_benchmark_counter *value);
]])
local kernel32 = ffi.load("kernel32")
local frequency = ffi.new("geblib_benchmark_counter[1]")
local counter = ffi.new("geblib_benchmark_counter[1]")
assert(kernel32.QueryPerformanceFrequency(frequency) ~= 0)

function SysTime()
    assert(kernel32.QueryPerformanceCounter(counter) ~= 0)
    return tonumber(counter[0]) / tonumber(frequency[0])
end

function isnumber(value) return type(value) == "number" end
string.GetExtensionFromFilename = function(path)
    return string.match(path, "%.([^%.\\/]*)$")
end

local function le16(value)
    return string.char(value % 256, math.floor(value / 256) % 256)
end

local function le32(value)
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    )
end

local function be32(value)
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256
    )
end

local function wavChunk(name, payload)
    local padding = #payload % 2 == 1 and "\0" or ""
    return name .. le32(#payload) .. payload .. padding
end

local sampleRate = 44100
local byteRate = sampleRate * 2
local wavData = string.rep("\0", byteRate)
local wavBody = "WAVE"
    .. wavChunk("fmt ", le16(1) .. le16(1) .. le32(sampleRate) .. le32(byteRate) .. le16(2) .. le16(16))
    .. wavChunk("LIST", "INFO" .. string.rep("metadata", 8))
    .. wavChunk("data", wavData)
local wavFixture = "RIFF" .. le32(#wavBody) .. wavBody

local frameCount = 1000
local frameSamples = 1152
local frameSize = math.floor(frameSamples * 128 * 125 / sampleRate)
local mp3Header = string.char(0xff, 0xfb, 0x90, 0x00)
local cbrFrame = mp3Header .. string.rep("\0", frameSize - 4)
local cbrFixture = string.rep(cbrFrame, frameCount)
local xingPayload = string.rep("\0", 32) .. "Xing" .. be32(1) .. be32(frameCount)
local xingFrame = mp3Header .. xingPayload .. string.rep("\0", frameSize - 4 - #xingPayload)
local xingFixture = xingFrame .. string.rep(cbrFrame, frameCount - 1)

local operations = {
    read = 0,
    readByte = 0,
    seek = 0,
    skip = 0,
    tell = 0,
    size = 0,
    open = 0,
    asyncRead = 0,
}

local Buffer = {}
Buffer.__index = Buffer

function Buffer:Read(length)
    operations.read = operations.read + 1
    if self.position >= #self.data then return nil end
    local value = string.sub(self.data, self.position + 1, self.position + length)
    self.position = self.position + #value
    return value
end

function Buffer:ReadByte()
    operations.readByte = operations.readByte + 1
    local value = string.byte(self.data, self.position + 1)
    if value ~= nil then self.position = self.position + 1 end
    return value
end

function Buffer:Tell()
    operations.tell = operations.tell + 1
    return self.position
end

function Buffer:Seek(position)
    operations.seek = operations.seek + 1
    self.position = position
    return position
end

function Buffer:Skip(offset)
    operations.skip = operations.skip + 1
    self.position = self.position + offset
    return self.position
end

function Buffer:Size()
    operations.size = operations.size + 1
    return #self.data
end

function Buffer:Close() end

file = {}
local function fixtureForPath(path)
    if string.find(path, "xing", 1, true) then
        return xingFixture
    elseif string.GetExtensionFromFilename(path) == "mp3" then
        return cbrFixture
    else
        return wavFixture
    end
end

function file.Open(path, mode, realm)
    assert(mode == "rb", "sound benchmark requires binary reads")
    assert(realm == "GAME", "sound benchmark requires the GAME filesystem")
    operations.open = operations.open + 1
    return setmetatable({data = fixtureForPath(path), position = 0}, Buffer)
end

FSASYNC_OK = 0
function file.AsyncRead(path, realm, callback)
    assert(realm == "GAME", "sound benchmark requires the GAME filesystem")
    operations.asyncRead = operations.asyncRead + 1
    callback(path, realm, FSASYNC_OK, fixtureForPath(path))
end

function SoundDuration(path)
    error("unexpected native SoundDuration fallback for " .. tostring(path))
end

SERVER = true
CLIENT = false
local thinkCallbacks = {}
hook = {
    Add = function(event, name, callback)
        assert(event == "Think")
        thinkCallbacks[name] = callback
    end,
    Remove = function(event, name)
        assert(event == "Think")
        thinkCallbacks[name] = nil
    end,
}

gebLib = {}
if sourcePath == "-" then
    assert(load(io.read("*a"), "@lua/geblib/sound.lua"))()
else
    dofile(sourcePath)
end

local expectedMP3Duration = frameCount * frameSamples / sampleRate
assert(math.abs(gebLib.SoundDuration("correctness-cbr.mp3") - expectedMP3Duration) < 0.000001)
assert(math.abs(gebLib.SoundDuration("correctness-xing.mp3") - expectedMP3Duration) < 0.000001)
assert(gebLib.SoundDuration("correctness.wav") == 1)

local function operationSnapshot()
    local snapshot = {}
    for name, value in pairs(operations) do snapshot[name] = value end
    return snapshot
end

local function operationDelta(before)
    local parts = {}
    for _, name in ipairs({"open", "asyncRead", "read", "readByte", "seek", "skip", "tell", "size"}) do
        parts[#parts + 1] = name .. "=" .. (operations[name] - before[name])
    end
    return table.concat(parts, " ")
end

local function execute(iterations, callback, offset)
    local checksum = 0
    for index = 1, iterations do checksum = checksum + callback(index + offset) end
    return checksum
end

local function run(label, iterations, callback)
    local warmupIterations = math.min(iterations, warmupLimit)
    execute(warmupIterations, callback, -warmupIterations)
    collectgarbage("collect")
    local before = operationSnapshot()
    local started = os.clock()
    local checksum = execute(iterations, callback, 0)
    local elapsed = os.clock() - started
    print(string.format(
        "%-16s %9.3f ms  %10.0f calls/s  checksum=%.3f",
        label,
        elapsed * 1000,
        iterations / math.max(elapsed, 0.000001),
        checksum
    ))
    print("  " .. operationDelta(before))
    return elapsed
end

for index = 1, 10 do
    gebLib.SoundDuration("warmup-cbr-" .. index .. ".mp3")
    gebLib.SoundDuration("warmup-xing-" .. index .. ".mp3")
    gebLib.SoundDuration("warmup-wav-" .. index .. ".wav")
end

local cachedPath = "cached.mp3"
local cachedDuration = gebLib.SoundDuration(cachedPath)

print(string.format(
    "gebLib.SoundDuration local Lua benchmark, %d frames per MP3",
    frameCount
))
local synchronousCBRElapsed = run("cold CBR MP3", cbrIterations, function(index)
    return gebLib.SoundDuration("cold-cbr-" .. index .. ".mp3")
end)
run("cold Xing MP3", fastIterations, function(index)
    return gebLib.SoundDuration("cold-xing-" .. index .. ".mp3")
end)
run("cold WAV", fastIterations, function(index)
    return gebLib.SoundDuration("cold-wav-" .. index .. ".wav")
end)
run("hot cache", cacheIterations, function()
    return gebLib.SoundDuration(cachedPath)
end)

assert(gebLib.SoundDuration(cachedPath) == cachedDuration)

local function runAsyncCBR(label, iterations, prefix)
    local completed = 0
    local checksum = 0
    local before = operationSnapshot()
    local started = SysTime()
    for index = 1, iterations do
        assert(gebLib.SoundDurationAsync(prefix .. index .. ".mp3", function(duration)
            completed = completed + 1
            checksum = checksum + duration
        end))
    end
    local submitted = SysTime()
    assert(completed == 0, "uncached server callbacks must not run during submission")

    local ticks = 0
    local maximumTick = 0
    while completed < iterations do
        local think = thinkCallbacks["gebLib.SoundDurationAsync"]
        assert(think, "async duration queue stopped before completion")
        local tickStarted = SysTime()
        think()
        local tickElapsed = SysTime() - tickStarted
        maximumTick = math.max(maximumTick, tickElapsed)
        ticks = ticks + 1
        assert(ticks <= iterations * 10, "async duration queue did not complete")
    end

    local elapsed = SysTime() - started
    assert(math.abs(checksum - expectedMP3Duration * iterations) < 0.0001)
    print(string.format(
        "%-16s %9.3f ms total  %7.3f ms submit  %7.3f ms max tick  %d ticks",
        label,
        elapsed * 1000,
        (submitted - started) * 1000,
        maximumTick * 1000,
        ticks
    ))
    print("  " .. operationDelta(before))
    return elapsed, maximumTick
end

runAsyncCBR("async warmup", math.min(cbrIterations, 100), "warmup-async-cbr-")
collectgarbage("collect")
local asyncCBRElapsed, asyncMaximumTick = runAsyncCBR("async CBR MP3", cbrIterations, "async-cbr-")
print(string.format(
    "async comparison: %.2fx lower maximum blocking slice; %.2fx total CPU cost",
    synchronousCBRElapsed / math.max(asyncMaximumTick, 0.000001),
    asyncCBRElapsed / math.max(synchronousCBRElapsed, 0.000001)
))

local pendingChannels = {}
local pendingChannelHead = 1
local pendingChannelTail = 0
local channelRequests = 0
local activeChannels = 0
local maximumActiveChannels = 0
local stoppedChannels = 0

SERVER = false
CLIENT = true
sound = {}
function sound.PlayFile(path, flags, callback)
    assert(flags == "noplay noblock")
    channelRequests = channelRequests + 1
    activeChannels = activeChannels + 1
    maximumActiveChannels = math.max(maximumActiveChannels, activeChannels)
    pendingChannelTail = pendingChannelTail + 1
    pendingChannels[pendingChannelTail] = {path = path, callback = callback}
end

local function resolveNextChannel()
    local request = pendingChannels[pendingChannelHead]
    assert(request, "expected a pending audio-channel request")
    pendingChannels[pendingChannelHead] = nil
    pendingChannelHead = pendingChannelHead + 1
    activeChannels = activeChannels - 1
    request.callback({
        GetLength = function() return expectedMP3Duration end,
        Stop = function() stoppedChannels = stoppedChannels + 1 end,
    })
end

gebLib = {}
if sourcePath == "-" then
    error("client queue benchmark requires a source path")
else
    dofile(sourcePath)
end

local clientCompleted = 0
local clientChecksum = 0
local clientStarted = SysTime()
for index = 1, cbrIterations do
    assert(gebLib.SoundDurationAsync("client-cbr-" .. index .. ".mp3", function(duration)
        clientCompleted = clientCompleted + 1
        clientChecksum = clientChecksum + duration
    end))
end
local clientSubmitted = SysTime()
assert(channelRequests == math.min(cbrIterations, 2), "client queue exceeded its startup limit")

local maximumClientCallback = 0
while clientCompleted < cbrIterations do
    local callbackStarted = SysTime()
    resolveNextChannel()
    maximumClientCallback = math.max(maximumClientCallback, SysTime() - callbackStarted)
end
local clientElapsed = SysTime() - clientStarted
assert(channelRequests == cbrIterations)
assert(maximumActiveChannels == math.min(cbrIterations, 2))
assert(stoppedChannels == cbrIterations)
assert(math.abs(clientChecksum - expectedMP3Duration * cbrIterations) < 0.0001)

local duplicateCallbacks = 0
assert(gebLib.SoundDurationAsync("client-duplicate.mp3", function() duplicateCallbacks = duplicateCallbacks + 1 end))
assert(gebLib.SoundDurationAsync("client-duplicate.mp3", function() duplicateCallbacks = duplicateCallbacks + 1 end))
local requestsBeforeDuplicateResolution = channelRequests
resolveNextChannel()
assert(duplicateCallbacks == 2)
assert(channelRequests == requestsBeforeDuplicateResolution)
assert(gebLib.SoundDurationAsync("client-duplicate.mp3", function() duplicateCallbacks = duplicateCallbacks + 1 end))
assert(duplicateCallbacks == 3, "cached async duration should invoke its callback immediately")
assert(channelRequests == requestsBeforeDuplicateResolution)

print(string.format(
    "client queue Lua %9.3f ms total  %7.3f ms submit  %7.3f ms max callback  %d max active",
    clientElapsed * 1000,
    (clientSubmitted - clientStarted) * 1000,
    maximumClientCallback * 1000,
    maximumActiveChannels
))
