local function installNetworkCodecs(Net)
    local codecDefinitions = setmetatable({}, {__mode = "k"})

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
        local codec = setmetatable({}, {
            __index = definition,
            __newindex = function()
                fail("Network Codecs are immutable after creation", 3)
            end,
            __metatable = false,
        })
        codecDefinitions[codec] = definition
        return codec
    end
    
    local function assertCodec(codec, context)
        local definition = isTable(codec) and codecDefinitions[codec] or nil
        if not definition then
            fail((context or "value") .. " must be a gebLib.Net codec", 2)
        end
        return definition
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

    return {
        Assert = assertCodec,
        BitsForUnsigned = bitsForUnsigned,
        BitsForSigned = bitsForSigned,
        IsNumber = isNumber,
        IsString = isString,
        IsTable = isTable,
        IsFunction = isFunction,
        IsBoolean = isBoolean,
        IsFinite = isFinite,
        IsInteger = isInteger,
    }
end

return installNetworkCodecs

