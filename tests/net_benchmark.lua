local iterations = tonumber(arg and arg[1]) or 2000000
local sentPackets = 0
local writtenBits = 0

function isnumber(value) return type(value) == "number" end
function isstring(value) return type(value) == "string" end
function istable(value) return type(value) == "table" end
function isfunction(value) return type(value) == "function" end
function isbool(value) return type(value) == "boolean" end

SERVER = true
CLIENT = false
FCVAR_ARCHIVE = 1

gebLib = {}
util = {AddNetworkString = function() end}
player = {GetCount = function() return 1 end}
concommand = {Add = function() end}

function GetConVar() return nil end
function CreateConVar()
    return {GetBool = function() return false end}
end

net = {}
function net.Start() writtenBits = 0 end
function net.WriteUInt(_, bits) writtenBits = writtenBits + bits end
function net.WriteBool() writtenBits = writtenBits + 1 end
function net.WriteFloat() writtenBits = writtenBits + 32 end
function net.BytesWritten() return math.ceil((writtenBits + 24) / 8), writtenBits + 24 end
function net.Broadcast() sentPackets = sentPackets + 1 end
function net.Receive() end

dofile("lua/geblib/net.lua")

local message = gebLib.Net.ToClient("benchmark.update", {
    gebLib.Net.UInt(10),
    gebLib.Net.Bool,
    gebLib.Net.Float,
})

local function directSend(index)
    net.Start("benchmark.direct")
    net.WriteUInt(index % 1024, 10)
    net.WriteBool(index % 2 == 0)
    net.WriteFloat(index * 0.01)
    net.Broadcast()
end

local function schemaSend(index)
    message:Broadcast(index % 1024, index % 2 == 0, index * 0.01)
end

local function run(label, callback)
    collectgarbage("collect")
    sentPackets = 0
    local started = os.clock()
    for index = 1, iterations do callback(index) end
    local elapsed = os.clock() - started
    print(string.format(
        "%-12s %8.3f ms  %8.0f sends/s  %d packets",
        label,
        elapsed * 1000,
        iterations / math.max(elapsed, 0.000001),
        sentPackets
    ))
    return elapsed
end

for index = 1, 10000 do
    directSend(index)
    schemaSend(index)
end

print("gebLib.Net local Lua benchmark, " .. iterations .. " sends")
local direct = run("direct net", directSend)
local schema = run("gebLib.Net", schemaSend)
print(string.format("wrapper CPU ratio: %.2fx", schema / math.max(direct, 0.000001)))
