local function createNetworkProfile(Net, helpers)
    local Profile = {}
    local bitsForUnsigned = helpers.bitsForUnsigned
    local bitsForSigned = helpers.bitsForSigned
    local isInteger = helpers.isInteger
    local isTable = helpers.isTable

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

    local active = profileConVar and profileConVar.GetBool and profileConVar:GetBool() or false

    function Profile.Enabled()
        return active
    end

    function Profile.Now()
        if SysTime then return SysTime() end
        if RealTime then return RealTime() end
        if CurTime then return CurTime() end
        return os.clock()
    end

    local function profilePrint(...)
        print("[gebLib.Net]", ...)
    end

    if SERVER and cvars and cvars.AddChangeCallback then
        if cvars.RemoveChangeCallback then
            cvars.RemoveChangeCallback("geblib_net_profile", "gebLib.Net.Profile")
        end
        cvars.AddChangeCallback("geblib_net_profile", function(_, _, value)
            local numeric = tonumber(value)
            active = numeric and numeric ~= 0 or value == "true"
        end, "gebLib.Net.Profile")
    end

    local function getMessageStats(message)
        local profile = Net._Profile
        local stats = profile.messages[message.Name]
        if not stats then
            stats = {
                message = message,
                count = 0,
                records = 0,
                totalBits = 0,
                totalWireBits = 0,
                totalRecipients = 0,
                repeated = 0,
                malformed = 0,
                rateLimited = 0,
                fields = {},
            }
            profile.messages[message.Name] = stats
        else
            stats.records = stats.records or stats.count or 0
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
        if isvector and isvector(value) then return "vector:" .. tostring(value) end
        if isangle and isangle(value) then return "angle:" .. tostring(value) end
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
        stats.firstAt = stats.firstAt or Profile.Now()

        if codec.Kind == "uint" or codec.Kind == "int" or codec.Kind == "range"
            or codec.Kind == "float" or codec.Kind == "double" then
            stats.minimum = stats.minimum == nil and value or math.min(stats.minimum, value)
            stats.maximum = stats.maximum == nil and value or math.max(stats.maximum, value)
            stats.sum = (stats.sum or 0) + value
            if isInteger(value) then stats.integers = (stats.integers or 0) + 1 end
            if value >= 0 then stats.nonNegative = (stats.nonNegative or 0) + 1 end
        elseif codec.Kind == "string" or codec.Kind == "array" then
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
        elseif codec.Kind == "entity" and value.IsPlayer and value:IsPlayer() then
            stats.players = (stats.players or 0) + 1
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
            local bits = stats.nonNegative == stats.count and bitsForUnsigned(stats.maximum)
                or bitsForSigned(stats.minimum, stats.maximum)
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
        if Profile.Now() - fieldStats.firstAt < 30 then return end

        local suggestion, savedBits = fieldSuggestion(codec, fieldStats)
        if not suggestion or savedBits < 2 then return end

        fieldStats.warned = true
        local elapsed = math.max(Profile.Now() - Net._Profile.startedAt, 0.001)
        local recordsPerMinute = fieldStats.count / elapsed * 60
        local recipients = messageStats.count > 0
            and messageStats.totalRecipients / messageStats.count or 1
        local savedKiB = savedBits * recordsPerMinute * recipients / 8192

        profilePrint(
            messageStats.message.Name .. " field #" .. fieldIndex .. " (" .. codec.Signature .. "): "
                .. suggestion .. ". Estimated saving: " .. string.format("%.2f", savedKiB) .. " KiB/min."
        )
    end

    function Profile.RecordPacket(message, bits, recipients, records)
        if not active or not SERVER then return end

        local profile = Net._Profile
        local now = Profile.Now()
        profile.startedAt = profile.startedAt or now

        local stats = getMessageStats(message)
        stats.count = stats.count + 1
        stats.records = stats.records + #records
        stats.totalBits = stats.totalBits + bits
        stats.totalRecipients = stats.totalRecipients + recipients
        stats.totalWireBits = stats.totalWireBits + bits * recipients

        for recordIndex = 1, #records do
            local values = records[recordIndex]
            local fingerprints = {}
            for index = 1, values.n do
                local codec = message.Fields[index].codec
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
    end

    function Profile.RecordDrop(message, kind)
        if not active or not SERVER then return end
        local profile = Net._Profile
        profile.startedAt = profile.startedAt or Profile.Now()
        local stats = getMessageStats(message)
        stats[kind] = stats[kind] + 1
    end

    function Profile.Reset()
        Net._Profile = {messages = {}}
        profilePrint("profile reset")
    end

    function Profile.Report()
        local profile = Net._Profile
        local elapsed = profile.startedAt and math.max(Profile.Now() - profile.startedAt, 0.001) or 0
        local messages = {}
        for _, stats in pairs(profile.messages) do messages[#messages + 1] = stats end
        table.sort(messages, function(left, right) return left.totalWireBits > right.totalWireBits end)

        profilePrint(
            "profile report: " .. #messages .. " messages over "
                .. string.format("%.1f", elapsed) .. " seconds"
        )

        for _, stats in ipairs(messages) do
            local kib = stats.totalWireBits / 8192
            local rate = elapsed > 0 and stats.count / elapsed or 0
            local averageBits = stats.count > 0 and stats.totalBits / stats.count or 0
            local repeated = stats.records > 0 and stats.repeated / stats.records * 100 or 0
            local recipients = stats.count > 0 and stats.totalRecipients / stats.count or 0
            local recordText = stats.records ~= stats.count and ", " .. stats.records .. " records" or ""

            profilePrint(
                stats.message.Name .. ": " .. stats.count .. " packets" .. recordText .. ", "
                    .. string.format("%.2f", rate) .. "/s, "
                    .. string.format("%.1f", averageBits) .. " bits average, "
                    .. string.format("%.1f", recipients) .. " recipients average, "
                    .. string.format("%.2f", kib) .. " KiB total, "
                    .. string.format("%.1f", repeated) .. "% consecutive repeats, "
                    .. stats.rateLimited .. " rate-limited, " .. stats.malformed .. " malformed"
            )

            if not stats.message.BatchMaximum and stats.count >= 64 and rate >= 20 and averageBits <= 256 then
                profilePrint("    suggestion: high-rate small packets; consider opt-in batching")
            end
            if stats.records >= 64 and repeated >= 25 then
                profilePrint("    suggestion: repeated payloads; avoid sending unchanged state")
            end

            for index, fieldStats in ipairs(stats.fields) do
                local codec = stats.message.Fields[index].codec
                local suggestion = fieldSuggestion(codec, fieldStats)
                profilePrint(
                    "  field #" .. index .. " (" .. codec.Signature .. "): "
                        .. fieldSummary(codec, fieldStats)
                )
                if suggestion then profilePrint("    suggestion: " .. suggestion) end
            end
        end
    end

    Net.ResetProfile = Profile.Reset
    Net.ReportProfile = Profile.Report

    if SERVER and concommand and concommand.Add then
        concommand.Add("geblib_net_profile_report", function() Profile.Report() end)
        concommand.Add("geblib_net_profile_reset", function() Profile.Reset() end)
    end

    return Profile
end

return createNetworkProfile
