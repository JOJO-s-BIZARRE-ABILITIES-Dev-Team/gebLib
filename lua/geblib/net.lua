local Net = gebLib.Net or {}
gebLib.Net = Net

local unpackValues = unpack or table.unpack
local MAX_PAYLOAD_BITS = 60 * 1024 * 8
local MESSAGE_NAME_PATTERN = "^[a-z0-9][a-z0-9%._]*$"
local TO_CLIENT = "client"
local TO_SERVER = "server"

local Message = {}
Message.__index = Message

Net._Messages = Net._Messages or {}
Net._Profile = Net._Profile or {messages = {}}
Net._PendingBatchMessages = {}

local function fail(message, level)
    error("[gebLib.Net] " .. message, (level or 1) + 1)
end

local function isNumber(value)
    return isnumber and isnumber(value) or type(value) == "number"
end

local function isString(value)
    return isstring and isstring(value) or type(value) == "string"
end

local function isTable(value)
    return istable and istable(value) or type(value) == "table"
end

local function isFunction(value)
    return isfunction and isfunction(value) or type(value) == "function"
end

local function isBoolean(value)
    return isbool and isbool(value) or type(value) == "boolean"
end

local function isFinite(value)
    return isNumber(value) and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value)
    return isFinite(value) and value % 1 == 0
end

local function bitsForUnsigned(maximum)
    local bits = 1

    while maximum >= 2 ^ bits and bits < 32 do
        bits = bits + 1
    end

    return bits
end

local function bitsForSigned(minimum, maximum)
    for bits = 3, 32 do
        local limit = 2 ^ (bits - 1)
        if minimum >= -limit and maximum <= limit - 1 then
            return bits
        end
    end

    return 32
end

local function makeCodec(definition)
    definition._gebLibNetCodec = true
    return setmetatable({}, {
        __index = definition,
        __newindex = function()
            fail("Network Codecs are immutable after creation", 3)
        end,
        __metatable = false,
    })
end

local function assertCodec(codec, context)
    if not isTable(codec) or codec._gebLibNetCodec ~= true then
        fail((context or "value") .. " must be a gebLib.Net codec", 2)
    end
end

local function simpleCodec(kind, signature, bits, accepts, writer, reader, minimumBits)
    return makeCodec({
        Kind = kind,
        Signature = signature,
        MinBits = minimumBits or bits,
        MaxBits = bits,
        Accepts = accepts,
        NeedsReadValidation = kind == "float" or kind == "double"
            or kind == "entity" or kind == "player",
        Validate = function(self, value, path)
            if not self.Accepts(value) then
                fail(path .. " must be " .. self.Signature, 2)
            end
        end,
        Write = function(_, value)
            writer(value)
        end,
        ReadUnchecked = reader,
        Read = reader,
    })
end

Net.Bool = simpleCodec(
    "bool",
    "Bool",
    1,
    isBoolean,
    function(value) net.WriteBool(value) end,
    function() return net.ReadBool() end
)

Net.Float = simpleCodec(
    "float",
    "Float",
    32,
    isFinite,
    function(value) net.WriteFloat(value) end,
    function() return net.ReadFloat() end
)

Net.Double = simpleCodec(
    "double",
    "Double",
    64,
    isFinite,
    function(value) net.WriteDouble(value) end,
    function() return net.ReadDouble() end
)

Net.Entity = simpleCodec(
    "entity",
    "Entity",
    MAX_EDICT_BITS or 13,
    function(value) return IsValid and IsValid(value) end,
    function(value) net.WriteEntity(value) end,
    function() return net.ReadEntity() end
)

Net.Player = simpleCodec(
    "player",
    "Player",
    MAX_PLAYER_BITS or 8,
    function(value)
        return IsValid and IsValid(value) and value.IsPlayer and value:IsPlayer()
    end,
    function(value) net.WritePlayer(value) end,
    function() return net.ReadPlayer() end
)

Net.Vector = simpleCodec(
    "vector",
    "Vector",
    69,
    function(value) return isvector and isvector(value) end,
    function(value) net.WriteVector(value) end,
    function() return net.ReadVector() end,
    3
)

Net.Normal = simpleCodec(
    "normal",
    "Normal",
    27,
    function(value)
        if not isvector or not isvector(value) then return false end
        if not value.Length then return true end
        return math.abs(value:Length() - 1) <= 0.001
    end,
    function(value) net.WriteNormal(value) end,
    function() return net.ReadNormal() end,
    3
)

Net.Angle = simpleCodec(
    "angle",
    "Angle",
    48,
    function(value) return isangle and isangle(value) end,
    function(value) net.WriteAngle(value) end,
    function() return net.ReadAngle() end
)

Net.Color = simpleCodec(
    "color",
    "Color",
    32,
    function(value) return IsColor and IsColor(value) end,
    function(value) net.WriteColor(value) end,
    function() return net.ReadColor() end
)

function Net.UInt(bits)
    if not isInteger(bits) or bits < 1 or bits > 32 then
        fail("UInt bits must be an integer from 1 to 32", 2)
    end

    local maximum = 2 ^ bits - 1

    return makeCodec({
        Kind = "uint",
        Bits = bits,
        Maximum = maximum,
        Signature = "UInt(" .. bits .. ")",
        MinBits = bits,
        MaxBits = bits,
        Accepts = function(value)
            return isInteger(value) and value >= 0 and value <= maximum
        end,
        NeedsReadValidation = false,
        Validate = function(self, value, path)
            if not self.Accepts(value) then
                fail(path .. " must be an integer from 0 to " .. maximum, 2)
            end
        end,
        Write = function(_, value) net.WriteUInt(value, bits) end,
        ReadUnchecked = function() return net.ReadUInt(bits) end,
        Read = function() return net.ReadUInt(bits) end,
    })
end

function Net.Int(bits)
    if not isInteger(bits) or bits < 3 or bits > 32 then
        fail("Int bits must be an integer from 3 to 32", 2)
    end

    local limit = 2 ^ (bits - 1)
    local minimum = -limit
    local maximum = limit - 1

    return makeCodec({
        Kind = "int",
        Bits = bits,
        Minimum = minimum,
        Maximum = maximum,
        Signature = "Int(" .. bits .. ")",
        MinBits = bits,
        MaxBits = bits,
        Accepts = function(value)
            return isInteger(value) and value >= minimum and value <= maximum
        end,
        NeedsReadValidation = false,
        Validate = function(self, value, path)
            if not self.Accepts(value) then
                fail(path .. " must be an integer from " .. minimum .. " to " .. maximum, 2)
            end
        end,
        Write = function(_, value) net.WriteInt(value, bits) end,
        ReadUnchecked = function() return net.ReadInt(bits) end,
        Read = function() return net.ReadInt(bits) end,
    })
end

function Net.Range(minimum, maximum)
    if not isInteger(minimum) or not isInteger(maximum) or maximum <= minimum then
        fail("Range bounds must be different integers in ascending order", 2)
    end

    local span = maximum - minimum
    if span > 4294967295 then
        fail("Range cannot contain more than 2^32 values", 2)
    end

    local bits = bitsForUnsigned(span)

    return makeCodec({
        Kind = "range",
        Bits = bits,
        Minimum = minimum,
        Maximum = maximum,
        Signature = "Range(" .. minimum .. "," .. maximum .. ")",
        MinBits = bits,
        MaxBits = bits,
        Accepts = function(value)
            return isInteger(value) and value >= minimum and value <= maximum
        end,
        NeedsReadValidation = false,
        Validate = function(self, value, path)
            if not self.Accepts(value) then
                fail(path .. " must be an integer from " .. minimum .. " to " .. maximum, 2)
            end
        end,
        Write = function(_, value) net.WriteUInt(value - minimum, bits) end,
        ReadUnchecked = function() return net.ReadUInt(bits) + minimum end,
        Read = function() return net.ReadUInt(bits) + minimum end,
    })
end

function Net.String(maxBytes)
    if not isInteger(maxBytes) or maxBytes < 1 or maxBytes > 65535 then
        fail("String maximum must be an integer from 1 to 65535 bytes", 2)
    end

    local lengthBits = bitsForUnsigned(maxBytes)

    return makeCodec({
        Kind = "string",
        LengthBits = lengthBits,
        Maximum = maxBytes,
        Signature = "String(" .. maxBytes .. ")",
        MinBits = lengthBits,
        MaxBits = lengthBits + maxBytes * 8,
        Accepts = function(value)
            return isString(value) and #value <= maxBytes
        end,
        NeedsReadValidation = false,
        Validate = function(self, value, path)
            if not isString(value) then
                fail(path .. " must be a string", 2)
            end

            if #value > maxBytes then
                fail(path .. " exceeds its " .. maxBytes .. " byte limit", 2)
            end
        end,
        Write = function(_, value)
            net.WriteUInt(#value, lengthBits)
            if #value > 0 then net.WriteData(value, #value) end
        end,
        Read = function()
            local length = net.ReadUInt(lengthBits)
            if length > maxBytes then error("string length exceeds schema", 0) end
            if length == 0 then return "" end
            return net.ReadData(length)
        end,
    })
end

function Net.Optional(inner)
    assertCodec(inner, "Optional codec")

    return makeCodec({
        Kind = "optional",
        Inner = inner,
        Signature = "Optional(" .. inner.Signature .. ")",
        MinBits = 1,
        MaxBits = 1 + inner.MaxBits,
        Accepts = function(value)
            return value == nil or inner.Accepts(value)
        end,
        NeedsReadValidation = inner.NeedsReadValidation == true,
        Validate = function(_, value, path)
            if value ~= nil then inner:Validate(value, path) end
        end,
        Write = function(_, value)
            net.WriteBool(value ~= nil)
            if value ~= nil then inner:Write(value) end
        end,
        Read = function()
            if not net.ReadBool() then return nil end
            return inner:Read()
        end,
    })
end

local function arrayLength(value)
    if not isTable(value) then return nil end

    local length = #value
    for key in pairs(value) do
        if not isInteger(key) or key < 1 or key > length then return nil end
    end

    return length
end

function Net.Array(inner, maxCount)
    assertCodec(inner, "Array codec")

    if inner.Kind == "optional" then
        fail("Array elements cannot be Optional because Lua arrays cannot preserve nil entries", 2)
    end

    if not isInteger(maxCount) or maxCount < 1 or maxCount > 65535 then
        fail("Array maximum must be an integer from 1 to 65535", 2)
    end

    local countBits = bitsForUnsigned(maxCount)

    return makeCodec({
        Kind = "array",
        Inner = inner,
        CountBits = countBits,
        Maximum = maxCount,
        Signature = "Array(" .. inner.Signature .. "," .. maxCount .. ")",
        MinBits = countBits,
        MaxBits = countBits + inner.MaxBits * maxCount,
        Accepts = function(value)
            local length = arrayLength(value)
            if not length or length > maxCount then return false end

            for index = 1, length do
                if not inner.Accepts(value[index]) then return false end
            end

            return true
        end,
        NeedsReadValidation = inner.NeedsReadValidation == true,
        Validate = function(_, value, path)
            local length = arrayLength(value)
            if not length then fail(path .. " must be a sequential array", 2) end
            if length > maxCount then fail(path .. " exceeds its " .. maxCount .. " item limit", 2) end

            for index = 1, length do
                inner:Validate(value[index], path .. "[" .. index .. "]")
            end
        end,
        Write = function(_, value)
            net.WriteUInt(#value, countBits)
            for index = 1, #value do inner:Write(value[index]) end
        end,
        Read = function()
            local length = net.ReadUInt(countBits)
            if length > maxCount then error("array length exceeds schema", 0) end

            local values = {}
            for index = 1, length do values[index] = inner:Read() end
            return values
        end,
    })
end

function Net.OneOf(choices)
    if not isTable(choices) or #choices < 2 or #choices > 256 then
        fail("OneOf requires an array of 2 to 256 codecs", 2)
    end

    local maximumBits = 0
    local needsReadValidation = false
    local signatures = {}

    for index, choice in ipairs(choices) do
        assertCodec(choice, "OneOf choice #" .. index)
        maximumBits = math.max(maximumBits, choice.MaxBits)
        needsReadValidation = needsReadValidation or choice.NeedsReadValidation == true
        signatures[index] = choice.Signature
    end

    local tagBits = bitsForUnsigned(#choices - 1)

    local function findChoice(value)
        for index, choice in ipairs(choices) do
            if choice.Accepts(value) then return index, choice end
        end
    end

    return makeCodec({
        Kind = "oneof",
        Choices = choices,
        TagBits = tagBits,
        Signature = "OneOf(" .. table.concat(signatures, ",") .. ")",
        MinBits = tagBits,
        MaxBits = tagBits + maximumBits,
        Accepts = function(value) return findChoice(value) ~= nil end,
        NeedsReadValidation = needsReadValidation,
        Validate = function(_, value, path)
            if not findChoice(value) then
                fail(path .. " does not match any allowed codec", 2)
            end
        end,
        Write = function(_, value)
            local index, choice = findChoice(value)
            net.WriteUInt(index - 1, tagBits)
            choice:Write(value)
        end,
        Read = function()
            local index = net.ReadUInt(tagBits) + 1
            local choice = choices[index]
            if not choice then error("unknown OneOf tag", 0) end
            return choice:Read()
        end,
    })
end

local loadInternal = include or function(path)
    return assert(loadfile("lua/" .. path))()
end

local createNetworkProfile = loadInternal("geblib/net_profile.lua")
local NetworkProfile = createNetworkProfile(Net, {
    bitsForUnsigned = bitsForUnsigned,
    bitsForSigned = bitsForSigned,
    isInteger = isInteger,
    isTable = isTable,
})
local profileEnabled = NetworkProfile.Enabled
local profileNow = NetworkProfile.Now
local recordPacket = NetworkProfile.RecordPacket
local recordDrop = NetworkProfile.RecordDrop

local function compileSchema(name, schema)
    if not isTable(schema) then fail("message schema must be an array", 3) end

    local length = #schema
    for key in pairs(schema) do
        if not isInteger(key) or key < 1 or key > length then
            fail("message schema must be a sequential array", 3)
        end
    end

    local signatures = {}
    local fields = {}
    local ownedSchema = {}
    local minimumBits = 0
    local maximumBits = 0
    local fixedSize = true

    for index = 1, length do
        local codec = schema[index]
        assertCodec(codec, "schema field #" .. index)
        local label = name .. " field #" .. index
        signatures[index] = codec.Signature
        ownedSchema[index] = codec
        fields[index] = {
            codec = codec,
            label = label,
            validate = codec.Validate,
            write = codec.Write,
            read = codec.Read,
            readUnchecked = codec.ReadUnchecked,
            validateRead = codec.NeedsReadValidation and codec.Validate or false,
            minimumBits = codec.MinBits,
            maximumBits = codec.MaxBits,
        }
        minimumBits = minimumBits + codec.MinBits
        maximumBits = maximumBits + codec.MaxBits
        if codec.MinBits ~= codec.MaxBits or not codec.ReadUnchecked then fixedSize = false end
    end

    if maximumBits > MAX_PAYLOAD_BITS then
        fail("message schema can exceed the 60 KiB safety limit", 3)
    end

    return {
        signature = table.concat(signatures, ";"),
        count = length,
        fields = fields,
        schema = ownedSchema,
        minimumBits = minimumBits,
        maximumBits = maximumBits,
        fixedSize = fixedSize,
    }
end

local function validateOptions(direction, options)
    options = options or {}
    if not isTable(options) then fail("message options must be a table", 3) end

    for key in pairs(options) do
        if key ~= "unreliable" and key ~= "rate" and key ~= "burst" and key ~= "batch" then
            fail("unknown message option " .. tostring(key), 3)
        end
    end

    local unreliable = options.unreliable or false
    if not isBoolean(unreliable) then fail("unreliable must be a boolean", 3) end

    local batch
    if options.batch ~= nil and options.batch ~= false then
        if not isInteger(options.batch) or options.batch < 2 or options.batch > 256 then
            fail("batch must be an integer from 2 to 256", 3)
        end
        batch = options.batch
    end

    if direction == TO_CLIENT then
        if options.rate ~= nil or options.burst ~= nil then
            fail("rate and burst are only valid for client-to-server messages", 3)
        end
        return unreliable, nil, nil, batch
    end

    if batch then fail("batch is only valid for server-to-client messages", 3) end

    if options.rate == nil then
        fail("client-to-server messages must set rate or rate = false", 3)
    end

    if options.rate == false then
        if options.burst ~= nil then fail("burst requires a numeric rate", 3) end
        return unreliable, false, false, nil
    end

    if not isFinite(options.rate) or options.rate <= 0 then
        fail("rate must be a positive number or false", 3)
    end

    local burst = options.burst or options.rate
    if not isFinite(burst) or burst < 1 then fail("burst must be at least 1", 3) end

    return unreliable, options.rate, burst, nil
end

local function messageSignature(direction, schemaSignature, unreliable, rate, burst, batch)
    local parts = {
        direction,
        schemaSignature,
        unreliable and "unreliable" or "reliable",
        tostring(rate),
        tostring(burst),
    }
    if batch then parts[#parts + 1] = "batch:" .. batch end
    return table.concat(parts, "|")
end

local function valuesFromArguments(message, offset, ...)
    local values = {n = message.FieldCount}
    for index = 1, values.n do values[index] = select(index + offset, ...) end
    return values
end

local function validateArguments(message, offset, ...)
    local received = select("#", ...) - offset
    local expected = message.FieldCount

    if received ~= expected then
        fail(message.Name .. " expects " .. expected .. " values, got " .. received, 3)
    end

    for index = 1, expected do
        local field = message.Fields[index]
        field.validate(field.codec, select(index + offset, ...), field.label)
    end
end

local function writeArguments(message, offset, ...)
    for index = 1, message.FieldCount do
        local field = message.Fields[index]
        field.write(field.codec, select(index + offset, ...))
    end
end

local function writeValues(message, values)
    for index = 1, message.FieldCount do
        local field = message.Fields[index]
        field.write(field.codec, values[index])
    end
end

local function validateValues(message, values)
    for index = 1, message.FieldCount do
        local field = message.Fields[index]
        field.validate(field.codec, values[index], field.label)
    end
end

local function startMessage(message, offset, ...)
    validateArguments(message, offset, ...)
    net.Start(message.Name, message.Unreliable)
    if message.BatchMaximum then net.WriteUInt(0, message.BatchBits) end
    writeArguments(message, offset, ...)
end

local function writtenBits()
    if not net.BytesWritten then return 0 end
    local _, bits = net.BytesWritten()
    return bits or 0
end

local function recipientCount(recipients)
    if recipients and recipients.GetPlayers then
        local players = recipients:GetPlayers()
        return players and #players or 0
    end

    if isTable(recipients) then
        local count = 0
        for key, value in pairs(recipients) do
            local candidate = isNumber(key) and value or key
            if IsValid and IsValid(candidate) and candidate.IsPlayer and candidate:IsPlayer() then
                count = count + 1
            end
        end
        return count
    end

    return 1
end

local BROADCAST_BATCH = {}

local function flushBatchGroup(message, group)
    local records = group.records
    if #records == 0 then return false end

    for index = 1, #records do validateValues(message, records[index]) end

    net.Start(message.Name, message.Unreliable)
    net.WriteUInt(#records - 1, message.BatchBits)
    for index = 1, #records do writeValues(message, records[index]) end

    if profileEnabled() then
        local recipients
        if group.broadcast then
            recipients = player and player.GetCount and player.GetCount() or 1
        else
            recipients = recipientCount(group.recipients)
        end
        recordPacket(message, writtenBits(), recipients, records)
    end

    if group.broadcast then
        net.Broadcast()
    else
        net.Send(group.recipients)
    end

    return true
end

local function flushMessageBatches(message)
    local pending = message.PendingBatches
    if not pending then return 0 end

    message.PendingBatches = {}
    Net._PendingBatchMessages[message] = nil
    local flushed = 0
    for _, group in pairs(pending) do
        if flushBatchGroup(message, group) then flushed = flushed + 1 end
    end
    return flushed
end

function Net.FlushBatches()
    if not SERVER then return 0 end

    local pending = Net._PendingBatchMessages
    Net._PendingBatchMessages = {}
    local flushed = 0
    for message in pairs(pending) do
        flushed = flushed + flushMessageBatches(message)
    end
    return flushed
end

if SERVER and hook and hook.Add then
    hook.Add("Tick", "gebLib.Net.FlushBatches", Net.FlushBatches)
end

local function queueMessage(message, recipients, broadcast, offset, ...)
    if not message.BatchMaximum then
        fail(message.Name .. " must set the batch option before using Queue", 3)
    end

    validateArguments(message, offset, ...)
    local values = valuesFromArguments(message, offset, ...)
    local key = broadcast and BROADCAST_BATCH or recipients
    local pending = message.PendingBatches
    local group = pending[key]

    if not group then
        group = {recipients = recipients, broadcast = broadcast, records = {}}
        pending[key] = group
        Net._PendingBatchMessages[message] = true
    end

    group.records[#group.records + 1] = values
    if #group.records >= message.BatchMaximum then
        pending[key] = nil
        flushBatchGroup(message, group)
        if not next(pending) then Net._PendingBatchMessages[message] = nil end
    end
end

function Message:Send(...)
    if self.Direction == TO_CLIENT then
        if not SERVER then fail(self.Name .. " can only be sent by the server", 2) end

        local recipients = select(1, ...)
        if recipients == nil then fail(self.Name .. " requires recipients; use Broadcast for everyone", 2) end

        if self.BatchMaximum then flushMessageBatches(self) end
        startMessage(self, 1, ...)
        if profileEnabled() then
            recordPacket(self, writtenBits(), recipientCount(recipients), {
                valuesFromArguments(self, 1, ...),
            })
        end
        net.Send(recipients)
        return
    end

    if not CLIENT then fail(self.Name .. " can only be sent by a client", 2) end

    startMessage(self, 0, ...)
    net.SendToServer()
end

function Message:Broadcast(...)
    if self.Direction ~= TO_CLIENT then fail(self.Name .. " is not a server-to-client message", 2) end
    if not SERVER then fail(self.Name .. " can only be broadcast by the server", 2) end

    if self.BatchMaximum then flushMessageBatches(self) end
    startMessage(self, 0, ...)
    if profileEnabled() then
        local count = player and player.GetCount and player.GetCount() or 1
        recordPacket(self, writtenBits(), count, {
            valuesFromArguments(self, 0, ...),
        })
    end
    net.Broadcast()
end

function Message:Queue(recipients, ...)
    if self.Direction ~= TO_CLIENT then fail(self.Name .. " is not a server-to-client message", 2) end
    if not SERVER then fail(self.Name .. " can only be queued by the server", 2) end
    if recipients == nil then fail(self.Name .. " requires recipients; use QueueBroadcast for everyone", 2) end
    queueMessage(self, recipients, false, 0, ...)
end

function Message:QueueBroadcast(...)
    if self.Direction ~= TO_CLIENT then fail(self.Name .. " is not a server-to-client message", 2) end
    if not SERVER then fail(self.Name .. " can only be queued by the server", 2) end
    queueMessage(self, nil, true, 0, ...)
end

function Message:Receive(callback)
    if not isFunction(callback) then fail(self.Name .. " receiver must be a function", 2) end

    if self.Direction == TO_CLIENT and not CLIENT then
        fail(self.Name .. " receiver belongs on the client", 2)
    elseif self.Direction == TO_SERVER and not SERVER then
        fail(self.Name .. " receiver belongs on the server", 2)
    end

    self.Handler = callback
end

local function rateAllowed(message, sender)
    if message.Rate == false then return true end

    local now = profileNow()
    local state = message.RateStates[sender]

    if not state then
        state = {tokens = message.Burst, last = now}
        message.RateStates[sender] = state
    else
        local elapsed = math.max(0, now - state.last)
        state.tokens = math.min(message.Burst, state.tokens + elapsed * message.Rate)
        state.last = now
    end

    if state.tokens < 1 then return false end
    state.tokens = state.tokens - 1
    return true
end

local function debugDrop(message, reason)
    if gebLib.DebugMode and gebLib.DebugMode() then
        gebLib.PrintDebug(message.Name .. " dropped: " .. reason)
    end
end

local function currentBitsLeft(context)
    if not context.boundsReliable or not net.BytesLeft then return nil end
    local _, bits = net.BytesLeft()
    return bits
end

local function decodeRecord(message, unchecked, context)
    local values = {n = message.FieldCount}

    for index = 1, message.FieldCount do
        local field = message.Fields[index]
        local codec = field.codec
        local reader = unchecked and field.readUnchecked or field.read
        local before = currentBitsLeft(context)
        if context.boundsReliable and before < field.minimumBits then error("truncated packet", 0) end
        local value = reader(codec)
        local after = currentBitsLeft(context)

        if context.boundsReliable then
            if before == nil or after == nil or after > before then
                context.boundsReliable = false
            else
                local consumed = before - after
                if consumed < field.minimumBits or consumed > field.maximumBits then
                    context.boundsReliable = false
                end
            end
        end

        local validate = field.validateRead
        if validate then validate(codec, value, message.FieldLabels[index]) end
        values[index] = value
    end

    return values
end

local function decodeMessage(message, length)
    local context = {boundsReliable = false}
    local count = 1
    if message.BatchMaximum then
        count = net.ReadUInt(message.BatchBits) + 1
        if count > message.BatchMaximum then error("batch count exceeds schema", 0) end

        local minimum = message.BatchBits + message.RecordMinBits * count
        local maximum = message.BatchBits + message.RecordMaxBits * count
        if length < minimum or length > maximum then error("batch size does not match schema", 0) end
    end

    local fixedLength = message.RecordFixedSize
        and length == (message.BatchBits or 0) + message.RecordMaxBits * count
    if not fixedLength and net.BytesLeft then
        local _, bits = net.BytesLeft()
        context.boundsReliable = bits ~= nil and bits == length
    end

    local records = {}
    for index = 1, count do records[index] = decodeRecord(message, fixedLength, context) end

    if not fixedLength and context.boundsReliable and net.BytesLeft then
        local _, bits = net.BytesLeft()
        if bits and bits > 0 then error("packet contains trailing data", 0) end
    end

    return records
end

local function receiveMessage(message, length, sender)
    if message.Direction == TO_SERVER then
        if not IsValid or not IsValid(sender) or not sender.IsPlayer or not sender:IsPlayer() then
            recordDrop(message, "malformed")
            debugDrop(message, "missing client sender")
            return
        end

        if not rateAllowed(message, sender) then
            recordDrop(message, "rateLimited")
            debugDrop(message, "rate limit exceeded")
            return
        end
    end

    if length < message.MinBits or length > message.MaxBits then
        recordDrop(message, "malformed")
        debugDrop(message, "payload size does not match schema")
        return
    end

    local ok, records = pcall(decodeMessage, message, length)
    if not ok then
        recordDrop(message, "malformed")
        debugDrop(message, tostring(records))
        return
    end

    if SERVER and message.Direction == TO_SERVER and profileEnabled() then
        recordPacket(message, length + 24, 1, records)
    end

    if not message.Handler then return end

    for index = 1, #records do
        local values = records[index]
        if message.Direction == TO_SERVER then
            message.Handler(sender, unpackValues(values, 1, values.n))
        else
            message.Handler(unpackValues(values, 1, values.n))
        end
    end
end

local function installReceiver(message)
    local receiving = message.Direction == TO_CLIENT and CLIENT or message.Direction == TO_SERVER and SERVER
    if not receiving then return end

    net.Receive(message.Name, function(length, sender)
        receiveMessage(message, length, sender)
    end)
end

local function defineMessage(direction, name, schema, options)
    if not isString(name) or #name < 1 or #name > 64 or not name:match(MESSAGE_NAME_PATTERN)
        or not name:find(".", 1, true) or name:sub(-1) == "." or name:find("..", 1, true) then
        fail("message names must be 1 to 64 lowercase namespaced characters", 3)
    end

    local compiled = compileSchema(name, schema)
    local unreliable, rate, burst, batchMaximum = validateOptions(direction, options)
    local batchBits = batchMaximum and bitsForUnsigned(batchMaximum - 1) or nil
    local minimumBits = compiled.minimumBits + (batchBits or 0)
    local maximumBits = compiled.maximumBits
    if batchMaximum then maximumBits = maximumBits * batchMaximum + batchBits end
    if maximumBits > MAX_PAYLOAD_BITS then
        fail("batched message schema can exceed the 60 KiB safety limit", 3)
    end

    local signature = messageSignature(
        direction,
        compiled.signature,
        unreliable,
        rate,
        burst,
        batchMaximum
    )
    local existing = Net._Messages[name]

    local function applyCompiled(message)
        message.Schema = compiled.schema
        message.Fields = compiled.fields
        message.FieldCount = compiled.count
        message.FieldLabels = {}
        for index = 1, compiled.count do message.FieldLabels[index] = compiled.fields[index].label end
        message.RecordMinBits = compiled.minimumBits
        message.RecordMaxBits = compiled.maximumBits
        message.RecordFixedSize = compiled.fixedSize
        message.MinBits = minimumBits
        message.MaxBits = maximumBits
        message.BatchMaximum = batchMaximum
        message.BatchBits = batchBits
        message.PendingBatches = {}
        Net._PendingBatchMessages[message] = nil
    end

    if existing then
        if existing.Signature ~= signature then
            fail("message " .. name .. " was already defined with a different contract", 3)
        end

        applyCompiled(existing)
        setmetatable(existing, Message)
        installReceiver(existing)
        return existing
    end

    local message = setmetatable({
        Name = name,
        Direction = direction,
        Signature = signature,
        Unreliable = unreliable,
        Rate = rate,
        Burst = burst,
        RateStates = setmetatable({}, {__mode = "k"}),
    }, Message)

    applyCompiled(message)

    Net._Messages[name] = message

    if SERVER then util.AddNetworkString(name) end
    installReceiver(message)
    return message
end

function Net.ToClient(name, schema, options)
    return defineMessage(TO_CLIENT, name, schema, options)
end

function Net.ToServer(name, schema, options)
    return defineMessage(TO_SERVER, name, schema, options)
end
