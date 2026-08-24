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

local function requireBits(amount)
    if not net.BytesLeft then return end

    local _, bits = net.BytesLeft()
    if bits ~= nil and bits < amount then
        error("truncated packet", 0)
    end
end

local function makeCodec(definition)
    definition._gebLibNetCodec = true
    return definition
end

local function assertCodec(codec, context)
    if not isTable(codec) or codec._gebLibNetCodec ~= true then
        fail((context or "value") .. " must be a gebLib.Net codec", 2)
    end
end

local function simpleCodec(kind, signature, bits, accepts, writer, reader)
    return makeCodec({
        Kind = kind,
        Signature = signature,
        MinBits = bits,
        MaxBits = bits,
        Accepts = accepts,
        Validate = function(self, value, path)
            if not self.Accepts(value) then
                fail(path .. " must be " .. self.Signature, 2)
            end
        end,
        Write = function(_, value)
            writer(value)
        end,
        Read = function(self)
            requireBits(self.MinBits)
            return reader()
        end,
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
    function() return net.ReadVector() end
)
Net.Vector.MinBits = 3

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
    function() return net.ReadNormal() end
)
Net.Normal.MinBits = 3

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
        Validate = function(self, value, path)
            if not self.Accepts(value) then
                fail(path .. " must be an integer from 0 to " .. maximum, 2)
            end
        end,
        Write = function(_, value) net.WriteUInt(value, bits) end,
        Read = function()
            requireBits(bits)
            return net.ReadUInt(bits)
        end,
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
        Validate = function(self, value, path)
            if not self.Accepts(value) then
                fail(path .. " must be an integer from " .. minimum .. " to " .. maximum, 2)
            end
        end,
        Write = function(_, value) net.WriteInt(value, bits) end,
        Read = function()
            requireBits(bits)
            return net.ReadInt(bits)
        end,
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
        Validate = function(self, value, path)
            if not self.Accepts(value) then
                fail(path .. " must be an integer from " .. minimum .. " to " .. maximum, 2)
            end
        end,
        Write = function(_, value) net.WriteUInt(value - minimum, bits) end,
        Read = function()
            requireBits(bits)
            return net.ReadUInt(bits) + minimum
        end,
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
            requireBits(lengthBits)
            local length = net.ReadUInt(lengthBits)
            if length > maxBytes then error("string length exceeds schema", 0) end
            requireBits(length * 8)
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
        Validate = function(_, value, path)
            if value ~= nil then inner:Validate(value, path) end
        end,
        Write = function(_, value)
            net.WriteBool(value ~= nil)
            if value ~= nil then inner:Write(value) end
        end,
        Read = function()
            requireBits(1)
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
            requireBits(countBits)
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
    local signatures = {}

    for index, choice in ipairs(choices) do
        assertCodec(choice, "OneOf choice #" .. index)
        maximumBits = math.max(maximumBits, choice.MaxBits)
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
            requireBits(tagBits)
            local index = net.ReadUInt(tagBits) + 1
            local choice = choices[index]
            if not choice then error("unknown OneOf tag", 0) end
            return choice:Read()
        end,
    })
end

local profileConVar
if SERVER and GetConVar then profileConVar = GetConVar("geblib_net_profile") end
if SERVER and not profileConVar and CreateConVar then
    profileConVar = CreateConVar(
        "geblib_net_profile",
        "0",
        {FCVAR_ARCHIVE or 0},
        "Profile gebLib network messages"
    )
end

local function profileEnabled()
    return profileConVar and profileConVar.GetBool and profileConVar:GetBool()
end

local function profileNow()
    if SysTime then return SysTime() end
    if RealTime then return RealTime() end
    if CurTime then return CurTime() end
    return os.clock()
end

local function profilePrint(...)
    print("[gebLib.Net]", ...)
end

local function getMessageStats(message)
    local profile = Net._Profile
    local stats = profile.messages[message.Name]

    if not stats then
        stats = {
            message = message,
            count = 0,
            totalBits = 0,
            totalWireBits = 0,
            totalRecipients = 0,
            repeated = 0,
            malformed = 0,
            rateLimited = 0,
            fields = {},
        }
        profile.messages[message.Name] = stats
    end

    return stats
end

local function fingerprint(value, depth)
    if depth > 2 then return tostring(value) end
    if value == nil then return "nil" end

    if IsValid and IsValid(value) and value.EntIndex then
        return "entity:" .. value:EntIndex()
    end

    if IsColor and IsColor(value) then
        return table.concat({"color", value.r, value.g, value.b, value.a}, ":")
    end

    if isvector and isvector(value) then
        return "vector:" .. tostring(value)
    end

    if isangle and isangle(value) then
        return "angle:" .. tostring(value)
    end

    if isTable(value) then
        local parts = {"["}
        for index = 1, #value do
            parts[#parts + 1] = fingerprint(value[index], depth + 1)
            parts[#parts + 1] = ","
        end
        parts[#parts + 1] = "]"
        return table.concat(parts)
    end

    return type(value) .. ":" .. tostring(value)
end

local function observeField(stats, codec, value)
    stats.count = (stats.count or 0) + 1
    stats.firstAt = stats.firstAt or profileNow()

    if codec.Kind == "uint" or codec.Kind == "int" or codec.Kind == "range"
        or codec.Kind == "float" or codec.Kind == "double" then
        stats.minimum = stats.minimum == nil and value or math.min(stats.minimum, value)
        stats.maximum = stats.maximum == nil and value or math.max(stats.maximum, value)
        stats.sum = (stats.sum or 0) + value
        if isInteger(value) then stats.integers = (stats.integers or 0) + 1 end
        if value >= 0 then stats.nonNegative = (stats.nonNegative or 0) + 1 end
    elseif codec.Kind == "string" then
        local length = #value
        stats.minimum = stats.minimum == nil and length or math.min(stats.minimum, length)
        stats.maximum = stats.maximum == nil and length or math.max(stats.maximum, length)
        stats.sum = (stats.sum or 0) + length
    elseif codec.Kind == "array" then
        local length = #value
        stats.minimum = stats.minimum == nil and length or math.min(stats.minimum, length)
        stats.maximum = stats.maximum == nil and length or math.max(stats.maximum, length)
        stats.sum = (stats.sum or 0) + length
    elseif codec.Kind == "optional" then
        if value ~= nil then stats.present = (stats.present or 0) + 1 end
    elseif codec.Kind == "vector" then
        if value.Length and math.abs(value:Length() - 1) <= 0.001 then
            stats.normalized = (stats.normalized or 0) + 1
        end
    elseif codec.Kind == "entity" then
        if value.IsPlayer and value:IsPlayer() then
            stats.players = (stats.players or 0) + 1
        end
    end
end

local function fieldSuggestion(codec, stats)
    if not stats or not stats.count or stats.count == 0 then return end

    if codec.Kind == "uint" then
        local required = bitsForUnsigned(stats.maximum)
        local suggested = math.min(codec.Bits, required + 1)
        if codec.Bits - suggested >= 2 then
            return "observed " .. stats.minimum .. ".." .. stats.maximum
                .. "; consider UInt(" .. suggested .. ") after confirming the domain maximum",
                codec.Bits - suggested
        end
    elseif codec.Kind == "int" then
        local required = bitsForSigned(stats.minimum, stats.maximum)
        local suggested = math.min(codec.Bits, required + 1)
        if codec.Bits - suggested >= 2 then
            return "observed " .. stats.minimum .. ".." .. stats.maximum
                .. "; consider Int(" .. suggested .. ") after confirming the domain bounds",
                codec.Bits - suggested
        end
    elseif codec.Kind == "string" or codec.Kind == "array" then
        local currentBits = codec.LengthBits or codec.CountBits
        local conservativeMaximum = math.min(codec.Maximum, math.max(1, stats.maximum * 2))
        local suggestedBits = bitsForUnsigned(conservativeMaximum)
        if currentBits - suggestedBits >= 2 then
            local label = codec.Kind == "string" and "String" or "Array"
            return "observed maximum " .. stats.maximum .. "; consider a smaller " .. label
                .. " limit after confirming the domain maximum",
                currentBits - suggestedBits
        end
    elseif codec.Kind == "vector" and stats.normalized == stats.count then
        return "all observed vectors were normalized; consider Normal", codec.MaxBits - Net.Normal.MaxBits
    elseif codec.Kind == "entity" and stats.players == stats.count then
        return "all observed entities were players; consider Player", codec.MaxBits - Net.Player.MaxBits
    elseif codec.Kind == "float" and stats.integers == stats.count then
        local bits
        if stats.nonNegative == stats.count then
            bits = bitsForUnsigned(stats.maximum)
        else
            bits = bitsForSigned(stats.minimum, stats.maximum)
        end

        if 32 - bits >= 2 then
            return "all observed values were integers in " .. stats.minimum .. ".." .. stats.maximum
                .. "; consider UInt, Int, or Range if fractions are impossible",
                32 - bits
        end
    end
end

local function fieldSummary(codec, stats)
    if not stats or not stats.count or stats.count == 0 then return "no samples" end

    if codec.Kind == "uint" or codec.Kind == "int" or codec.Kind == "range"
        or codec.Kind == "float" or codec.Kind == "double" then
        return "observed " .. stats.minimum .. ".." .. stats.maximum
            .. ", average " .. string.format("%.2f", stats.sum / stats.count)
    elseif codec.Kind == "string" then
        return "observed " .. stats.minimum .. ".." .. stats.maximum
            .. " bytes, average " .. string.format("%.2f", stats.sum / stats.count)
    elseif codec.Kind == "array" then
        return "observed " .. stats.minimum .. ".." .. stats.maximum
            .. " items, average " .. string.format("%.2f", stats.sum / stats.count)
    elseif codec.Kind == "optional" then
        return string.format("present in %.1f%% of packets", (stats.present or 0) / stats.count * 100)
    elseif codec.Kind == "vector" then
        return string.format("normalized in %.1f%% of packets", (stats.normalized or 0) / stats.count * 100)
    elseif codec.Kind == "entity" then
        return string.format("players in %.1f%% of packets", (stats.players or 0) / stats.count * 100)
    end

    return stats.count .. " samples"
end

local function maybeWarn(messageStats, fieldIndex, codec, fieldStats)
    if fieldStats.warned or fieldStats.count < 256 then return end
    if profileNow() - fieldStats.firstAt < 30 then return end

    local suggestion, savedBits = fieldSuggestion(codec, fieldStats)
    if not suggestion or savedBits < 2 then return end

    fieldStats.warned = true
    local elapsed = math.max(profileNow() - Net._Profile.startedAt, 0.001)
    local packetsPerMinute = messageStats.count / elapsed * 60
    local recipients = messageStats.count > 0 and messageStats.totalRecipients / messageStats.count or 1
    local savedKiB = savedBits * packetsPerMinute * recipients / 8192

    profilePrint(
        messageStats.message.Name .. " field #" .. fieldIndex .. " (" .. codec.Signature .. "): "
            .. suggestion .. ". Estimated saving: " .. string.format("%.2f", savedKiB) .. " KiB/min."
    )
end

local function recordMessage(message, bits, recipients, values)
    if not profileEnabled() or not SERVER then return end

    local profile = Net._Profile
    local now = profileNow()
    profile.startedAt = profile.startedAt or now

    local stats = getMessageStats(message)
    stats.count = stats.count + 1
    stats.totalBits = stats.totalBits + bits
    stats.totalRecipients = stats.totalRecipients + recipients
    stats.totalWireBits = stats.totalWireBits + bits * recipients

    local fingerprints = {}
    for index = 1, values.n do
        local codec = message.Schema[index]
        local fieldStats = stats.fields[index]
        if not fieldStats then
            fieldStats = {}
            stats.fields[index] = fieldStats
        end

        observeField(fieldStats, codec, values[index])
        fingerprints[index] = fingerprint(values[index], 0)
        maybeWarn(stats, index, codec, fieldStats)
    end

    local currentFingerprint = table.concat(fingerprints, "|")
    if currentFingerprint == stats.lastFingerprint then stats.repeated = stats.repeated + 1 end
    stats.lastFingerprint = currentFingerprint
end

local function recordDrop(message, kind)
    if not profileEnabled() or not SERVER then return end

    local profile = Net._Profile
    profile.startedAt = profile.startedAt or profileNow()
    local stats = getMessageStats(message)
    stats[kind] = stats[kind] + 1
end

function Net.ResetProfile()
    Net._Profile = {messages = {}}
    profilePrint("profile reset")
end

function Net.ReportProfile()
    local profile = Net._Profile
    local now = profileNow()
    local elapsed = profile.startedAt and math.max(now - profile.startedAt, 0.001) or 0
    local messages = {}

    for _, stats in pairs(profile.messages) do messages[#messages + 1] = stats end
    table.sort(messages, function(left, right) return left.totalWireBits > right.totalWireBits end)

    profilePrint("profile report: " .. #messages .. " messages over " .. string.format("%.1f", elapsed) .. " seconds")

    for _, stats in ipairs(messages) do
        local kib = stats.totalWireBits / 8192
        local rate = elapsed > 0 and stats.count / elapsed or 0
        local averageBits = stats.count > 0 and stats.totalBits / stats.count or 0
        local repeated = stats.count > 0 and stats.repeated / stats.count * 100 or 0

        profilePrint(
            stats.message.Name .. ": " .. stats.count .. " packets, "
                .. string.format("%.2f", rate) .. "/s, "
                .. string.format("%.1f", averageBits) .. " bits average, "
                .. string.format("%.2f", kib) .. " KiB total, "
                .. string.format("%.1f", repeated) .. "% consecutive repeats, "
                .. stats.rateLimited .. " rate-limited, " .. stats.malformed .. " malformed"
        )

        for index, fieldStats in ipairs(stats.fields) do
            local codec = stats.message.Schema[index]
            local suggestion = fieldSuggestion(codec, fieldStats)
            profilePrint("  field #" .. index .. " (" .. codec.Signature .. "): " .. fieldSummary(codec, fieldStats))
            if suggestion then
                profilePrint("    suggestion: " .. suggestion)
            end
        end
    end
end

if SERVER and concommand and concommand.Add then
    concommand.Add("geblib_net_profile_report", function() Net.ReportProfile() end)
    concommand.Add("geblib_net_profile_reset", function() Net.ResetProfile() end)
end

local function validateSchema(schema)
    if not isTable(schema) then fail("message schema must be an array", 3) end

    local length = #schema
    for key in pairs(schema) do
        if not isInteger(key) or key < 1 or key > length then
            fail("message schema must be a sequential array", 3)
        end
    end

    local signatures = {}
    local maximumBits = 0

    for index = 1, length do
        local codec = schema[index]
        assertCodec(codec, "schema field #" .. index)
        signatures[index] = codec.Signature
        maximumBits = maximumBits + codec.MaxBits
    end

    if maximumBits > MAX_PAYLOAD_BITS then
        fail("message schema can exceed the 60 KiB safety limit", 3)
    end

    return table.concat(signatures, ";"), maximumBits
end

local function validateOptions(direction, options)
    options = options or {}
    if not isTable(options) then fail("message options must be a table", 3) end

    for key in pairs(options) do
        if key ~= "unreliable" and key ~= "rate" and key ~= "burst" then
            fail("unknown message option " .. tostring(key), 3)
        end
    end

    local unreliable = options.unreliable or false
    if not isBoolean(unreliable) then fail("unreliable must be a boolean", 3) end

    if direction == TO_CLIENT then
        if options.rate ~= nil or options.burst ~= nil then
            fail("rate and burst are only valid for client-to-server messages", 3)
        end
        return unreliable, nil, nil
    end

    if options.rate == nil then
        fail("client-to-server messages must set rate or rate = false", 3)
    end

    if options.rate == false then
        if options.burst ~= nil then fail("burst requires a numeric rate", 3) end
        return unreliable, false, false
    end

    if not isFinite(options.rate) or options.rate <= 0 then
        fail("rate must be a positive number or false", 3)
    end

    local burst = options.burst or options.rate
    if not isFinite(burst) or burst < 1 then fail("burst must be at least 1", 3) end

    return unreliable, options.rate, burst
end

local function messageSignature(direction, schemaSignature, unreliable, rate, burst)
    return table.concat({
        direction,
        schemaSignature,
        unreliable and "unreliable" or "reliable",
        tostring(rate),
        tostring(burst),
    }, "|")
end

local function valuesFromArguments(message, offset, ...)
    local values = {n = #message.Schema}
    for index = 1, values.n do values[index] = select(index + offset, ...) end
    return values
end

local function validateArguments(message, offset, ...)
    local received = select("#", ...) - offset
    local expected = #message.Schema

    if received ~= expected then
        fail(message.Name .. " expects " .. expected .. " values, got " .. received, 3)
    end

    for index, codec in ipairs(message.Schema) do
        codec:Validate(select(index + offset, ...), message.Name .. " field #" .. index)
    end
end

local function writeArguments(message, offset, ...)
    for index, codec in ipairs(message.Schema) do
        codec:Write(select(index + offset, ...))
    end
end

local function startMessage(message, offset, ...)
    validateArguments(message, offset, ...)
    net.Start(message.Name, message.Unreliable)

    local ok, writeError = pcall(writeArguments, message, offset, ...)

    if not ok then
        if net.Abort then net.Abort() end
        fail(message.Name .. " could not be encoded: " .. tostring(writeError), 3)
    end
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

function Message:Send(...)
    if self.Direction == TO_CLIENT then
        if not SERVER then fail(self.Name .. " can only be sent by the server", 2) end

        local recipients = select(1, ...)
        if recipients == nil then fail(self.Name .. " requires recipients; use Broadcast for everyone", 2) end

        startMessage(self, 1, ...)
        if profileEnabled() then
            recordMessage(self, writtenBits(), recipientCount(recipients), valuesFromArguments(self, 1, ...))
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

    startMessage(self, 0, ...)
    if profileEnabled() then
        local count = player and player.GetCount and player.GetCount() or 1
        recordMessage(self, writtenBits(), count, valuesFromArguments(self, 0, ...))
    end
    net.Broadcast()
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

local function decodeMessage(message)
    local values = {n = #message.Schema}

    for index, codec in ipairs(message.Schema) do
        local value = codec:Read()
        codec:Validate(value, message.Name .. " field #" .. index)
        values[index] = value
    end

    if net.BytesLeft then
        local _, bits = net.BytesLeft()
        if bits and bits > 0 then error("packet contains trailing data", 0) end
    end

    return values
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

    if length > message.MaxBits then
        recordDrop(message, "malformed")
        debugDrop(message, "payload exceeds schema")
        return
    end

    local ok, values = pcall(decodeMessage, message)
    if not ok then
        recordDrop(message, "malformed")
        debugDrop(message, tostring(values))
        return
    end

    if SERVER and message.Direction == TO_SERVER and profileEnabled() then
        recordMessage(message, length + 24, 1, values)
    end

    if not message.Handler then return end

    if message.Direction == TO_SERVER then
        message.Handler(sender, unpackValues(values, 1, values.n))
    else
        message.Handler(unpackValues(values, 1, values.n))
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

    local schemaSignature, maximumBits = validateSchema(schema)
    local unreliable, rate, burst = validateOptions(direction, options)
    local signature = messageSignature(direction, schemaSignature, unreliable, rate, burst)
    local existing = Net._Messages[name]

    if existing then
        if existing.Signature ~= signature then
            fail("message " .. name .. " was already defined with a different contract", 3)
        end

        existing.Schema = schema
        existing.MaxBits = maximumBits
        setmetatable(existing, Message)
        installReceiver(existing)
        return existing
    end

    local message = setmetatable({
        Name = name,
        Direction = direction,
        Schema = schema,
        Signature = signature,
        MaxBits = maximumBits,
        Unreliable = unreliable,
        Rate = rate,
        Burst = burst,
        RateStates = setmetatable({}, {__mode = "k"}),
    }, Message)

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
