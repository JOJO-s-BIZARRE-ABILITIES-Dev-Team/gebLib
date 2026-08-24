local now = 0
local profileEnabled = false
local commandCallbacks = {}

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assertContains(text, expected, message)
    if not text:find(expected, 1, true) then
        error((message or "text differs") .. ": expected to find " .. expected .. " in " .. text, 2)
    end
end

function isnumber(value) return type(value) == "number" end
function isstring(value) return type(value) == "string" end
function istable(value) return type(value) == "table" end
function isfunction(value) return type(value) == "function" end
function isbool(value) return type(value) == "boolean" end
function SysTime() return now end

local VectorMeta = {}
VectorMeta.__index = VectorMeta
function VectorMeta:Length()
    return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end

local function newVector(x, y, z)
    return setmetatable({kind = "vector", x = x, y = y, z = z}, VectorMeta)
end

local function newAngle(pitch, yaw, roll)
    return {kind = "angle", pitch = pitch, yaw = yaw, roll = roll}
end

local function newColor(red, green, blue, alpha)
    return {kind = "color", r = red, g = green, b = blue, a = alpha}
end

local function newEntity(index, playerEntity)
    local entity = {valid = true, index = index, player = playerEntity == true}
    function entity:IsPlayer() return self.player end
    function entity:EntIndex() return self.index end
    return entity
end

function isvector(value) return getmetatable(value) == VectorMeta end
function isangle(value) return type(value) == "table" and value.kind == "angle" end
function IsColor(value) return type(value) == "table" and value.kind == "color" end
function IsValid(value) return type(value) == "table" and value.valid == true end

local players = {
    newEntity(1, true),
    newEntity(2, true),
}

player = {
    GetCount = function() return #players end,
}

FCVAR_ARCHIVE = 1

function GetConVar() return nil end
function CreateConVar()
    return {GetBool = function() return profileEnabled end}
end

concommand = {}
function concommand.Add(name, callback)
    commandCallbacks[name] = callback
end

local function newNet()
    local state = {
        receivers = {},
        sent = {},
        current = nil,
        reading = nil,
        readIndex = 1,
        bitsLeft = 0,
    }

    local mock = {}

    local function write(kind, value, bits, extra)
        assert(state.current, "net.Start must be called before writing")
        state.current.tokens[#state.current.tokens + 1] = {
            kind = kind,
            value = value,
            bits = bits,
            extra = extra,
        }
        state.current.bits = state.current.bits + bits
    end

    local function read(kind, bits)
        local token = state.reading.tokens[state.readIndex]
        assert(token, "read past packet end")
        assertEqual(token.kind, kind, "wire type")
        if bits then assertEqual(token.bits, bits, "wire bit count") end
        state.readIndex = state.readIndex + 1
        state.bitsLeft = state.bitsLeft - token.bits
        return token.value
    end

    function mock.Start(name, unreliable)
        state.current = {name = name, unreliable = unreliable, tokens = {}, bits = 0}
    end

    function mock.Abort() state.current = nil end
    function mock.BytesWritten()
        if not state.current then return nil end
        local bits = state.current.bits + 24
        return math.ceil(bits / 8), bits
    end

    function mock.BytesLeft()
        if not state.reading then return nil end
        return math.ceil(state.bitsLeft / 8), state.bitsLeft
    end

    function mock.WriteBool(value) write("bool", value, 1) end
    function mock.ReadBool() return read("bool", 1) end
    function mock.WriteUInt(value, bits) write("uint", value, bits) end
    function mock.ReadUInt(bits) return read("uint", bits) end
    function mock.WriteInt(value, bits) write("int", value, bits) end
    function mock.ReadInt(bits) return read("int", bits) end
    function mock.WriteFloat(value) write("float", value, 32) end
    function mock.ReadFloat() return read("float", 32) end
    function mock.WriteDouble(value) write("double", value, 64) end
    function mock.ReadDouble() return read("double", 64) end
    function mock.WriteData(value, length) write("data", value, length * 8, length) end
    function mock.ReadData(length)
        local token = state.reading.tokens[state.readIndex]
        assertEqual(token.extra, length, "data length")
        return read("data", length * 8)
    end
    function mock.WriteEntity(value) write("entity", value, 13) end
    function mock.ReadEntity() return read("entity", 13) end
    function mock.WritePlayer(value) write("player", value, 8) end
    function mock.ReadPlayer() return read("player", 8) end
    function mock.WriteVector(value) write("vector", value, 69) end
    function mock.ReadVector() return read("vector", 69) end
    function mock.WriteNormal(value) write("normal", value, 27) end
    function mock.ReadNormal() return read("normal", 27) end
    function mock.WriteAngle(value) write("angle", value, 48) end
    function mock.ReadAngle() return read("angle", 48) end
    function mock.WriteColor(value) write("color", value, 32) end
    function mock.ReadColor() return read("color", 32) end

    local function finish(kind, recipients)
        assert(state.current, "no packet to send")
        state.current.kind = kind
        state.current.recipients = recipients
        state.sent[#state.sent + 1] = state.current
        state.current = nil
    end

    function mock.Send(recipients) finish("send", recipients) end
    function mock.Broadcast() finish("broadcast") end
    function mock.SendToServer() finish("server") end
    function mock.Receive(name, callback) state.receivers[name] = callback end

    function state:Deliver(packet, sender, length)
        self.reading = packet
        self.readIndex = 1
        self.bitsLeft = packet.bits
        local receiver = self.receivers[packet.name]
        assert(receiver, "missing receiver for " .. packet.name)
        receiver(length or packet.bits, sender)
        self.reading = nil
    end

    return mock, state
end

local function loadRealm(server, profiling)
    SERVER = server
    CLIENT = not server
    profileEnabled = profiling == true
    commandCallbacks = {}
    gebLib = {
        DebugMode = function() return false end,
        PrintDebug = function() end,
    }
    util = {AddNetworkString = function() end}
    net, netState = newNet()
    dofile("lua/geblib/net.lua")
    return gebLib.Net, netState
end

local entity = newEntity(20, false)
local direction = newVector(1, 0, 0)
local position = newVector(10, 20, 30)
local angle = newAngle(10, 20, 30)
local color = newColor(10, 20, 30, 40)

local function allCodecs(Net)
    return {
        Net.UInt(12),
        Net.Int(8),
        Net.Range(1, 64),
        Net.Bool,
        Net.Float,
        Net.Double,
        Net.String(64),
        Net.Entity,
        Net.Player,
        Net.Vector,
        Net.Normal,
        Net.Angle,
        Net.Color,
        Net.Optional(Net.UInt(8)),
        Net.Array(Net.UInt(4), 8),
        Net.OneOf({Net.String(16), Net.Color}),
    }
end

do
    local serverNet, serverState = loadRealm(true)
    local message = serverNet.ToClient("test.all_codecs", allCodecs(serverNet))

    message:Send(
        players[1],
        100,
        -20,
        64,
        true,
        1.5,
        123.25,
        "hello",
        entity,
        players[2],
        position,
        direction,
        angle,
        color,
        200,
        {1, 2, 3},
        "tag"
    )

    local packet = serverState.sent[1]
    assertEqual(packet.name, "test.all_codecs", "physical message name")
    assertEqual(packet.bits, 422, "schema should add no route or type metadata")

    local clientNet, clientState = loadRealm(false)
    local received
    clientNet.ToClient("test.all_codecs", allCodecs(clientNet)):Receive(function(...)
        received = {n = select("#", ...), ...}
    end)
    clientState:Deliver(packet)

    assertEqual(received.n, 16, "decoded value count")
    assertEqual(received[1], 100, "UInt round trip")
    assertEqual(received[2], -20, "Int round trip")
    assertEqual(received[3], 64, "Range round trip")
    assertEqual(received[7], "hello", "String round trip")
    assertEqual(received[8], entity, "Entity round trip")
    assertEqual(received[9], players[2], "Player round trip")
    assertEqual(received[14], 200, "Optional round trip")
    assertEqual(received[15][3], 3, "Array round trip")
    assertEqual(received[16], "tag", "OneOf round trip")

    local wrongRealm = pcall(function() message:Broadcast(1, 2, 3) end)
    assertEqual(wrongRealm, false, "client must not broadcast a server message")
end

do
    local Net = loadRealm(true)
    local message = Net.ToClient("test.validation", {Net.UInt(12)})
    local same = Net.ToClient("test.validation", {Net.UInt(12)})
    local valid = pcall(function() message:Broadcast(4095) end)
    local invalid = pcall(function() message:Broadcast(4096) end)
    local duplicate = pcall(function() Net.ToClient("test.validation", {Net.UInt(11)}) end)
    local missingRate = pcall(function() Net.ToServer("test.no_rate", {}) end)
    local invalidName = pcall(function() Net.ToClient("InvalidName", {}) end)

    assertEqual(same, message, "identical definitions should be idempotent")
    assertEqual(valid, true, "UInt upper bound")
    assertEqual(invalid, false, "UInt overflow should fail before sending")
    assertEqual(duplicate, false, "different duplicate contract should fail")
    assertEqual(missingRate, false, "client messages should require an explicit rate")
    assertEqual(invalidName, false, "message names should be lowercase and namespaced")
end

do
    local Net, state = loadRealm(true)
    Net.ToClient("test.animation_play", {
        Net.Player,
        Net.UInt(3),
        Net.UInt(16),
        Net.Float,
        Net.Bool,
        Net.Float,
    }):Broadcast(players[1], 1, 100, 0, true, 1)

    assertEqual(state.sent[1].bits, 92, "typed animation payload should use its exact field widths")
end

do
    local serverNet, serverState = loadRealm(true)
    local schema = {
        serverNet.UInt(32),
        serverNet.Int(32),
        serverNet.Range(-10, 10),
        serverNet.String(8),
        serverNet.Optional(serverNet.UInt(8)),
        serverNet.Array(serverNet.UInt(2), 4),
        serverNet.OneOf({serverNet.String(4), serverNet.Color}),
    }
    serverNet.ToClient("test.boundaries", schema):Send(
        players[1],
        4294967295,
        -2147483648,
        -10,
        "",
        nil,
        {},
        color
    )

    local packet = serverState.sent[1]
    assertEqual(packet.bits, 110, "boundary packet size")

    local clientNet, clientState = loadRealm(false)
    local received
    clientNet.ToClient("test.boundaries", {
        clientNet.UInt(32),
        clientNet.Int(32),
        clientNet.Range(-10, 10),
        clientNet.String(8),
        clientNet.Optional(clientNet.UInt(8)),
        clientNet.Array(clientNet.UInt(2), 4),
        clientNet.OneOf({clientNet.String(4), clientNet.Color}),
    }):Receive(function(...)
        received = {n = select("#", ...), ...}
    end)
    clientState:Deliver(packet)

    assertEqual(received.n, 7, "boundary value count")
    assertEqual(received[1], 4294967295, "UInt maximum")
    assertEqual(received[2], -2147483648, "Int minimum")
    assertEqual(received[3], -10, "Range minimum")
    assertEqual(received[4], "", "empty string")
    assertEqual(received[5], nil, "missing optional")
    assertEqual(#received[6], 0, "empty array")
    assertEqual(received[7], color, "alternate OneOf codec")
end

do
    local clientNet, clientState = loadRealm(false)
    local request = clientNet.ToServer("test.request", {clientNet.UInt(6)}, {rate = 2, burst = 2})
    request:Send(12)
    local packet = clientState.sent[1]

    local serverNet, serverState = loadRealm(true, true)
    local calls = 0
    local senderSeen
    serverNet.ToServer("test.request", {serverNet.UInt(6)}, {rate = 2, burst = 2}):Receive(function(sender, value)
        calls = calls + 1
        senderSeen = sender
        assertEqual(value, 12, "request value")
    end)

    now = 0
    serverState:Deliver(packet, players[1])
    serverState:Deliver(packet, players[1])
    serverState:Deliver(packet, players[1])
    assertEqual(calls, 2, "burst should cap immediate client messages")

    now = 0.5
    serverState:Deliver(packet, players[1])
    assertEqual(calls, 3, "rate should replenish tokens")
    assertEqual(senderSeen, players[1], "server receiver should get the sender")

    now = 1
    serverState:Deliver(packet, players[1], 1000)
    assertEqual(calls, 3, "oversized packet should not reach the handler")
end

do
    local Net = loadRealm(true, true)
    local message = Net.ToClient("test.profile", {Net.UInt(12)})
    local output = {}
    local originalPrint = print
    print = function(...)
        local parts = {}
        for index = 1, select("#", ...) do parts[index] = tostring(select(index, ...)) end
        output[#output + 1] = table.concat(parts, " ")
    end

    now = 0
    for index = 1, 256 do
        now = index * 0.125
        message:Broadcast(100)
    end
    Net.ReportProfile()
    print = originalPrint

    local joined = table.concat(output, "\n")
    assertContains(joined, "consider UInt(8)", "profiler bit-width advice")
    assertContains(joined, "256 packets", "profiler packet count")
    assertContains(joined, "average 100.00", "profiler field average")
    assertContains(joined, "consecutive repeats", "profiler duplicate traffic")
end

print("network: ok")
