local Net = gebLib.Net
local TOKEN = Net.String(32)

local Ready = Net.ToServer("geblib.selftest.ready", {TOKEN}, {rate = 1, burst = 1})
local Ack = Net.ToServer("geblib.selftest.ack", {
    TOKEN,
    Net.String(32),
    Net.Bool,
    Net.String(256),
}, {rate = false})
local RateProbe = Net.ToServer("geblib.selftest.rate", {TOKEN, Net.UInt(4)}, {rate = 1, burst = 2})
local MalformedProbe = Net.ToServer("geblib.selftest.malformed", {TOKEN, Net.UInt(16)}, {
    rate = 4,
    burst = 4,
})

local Payload = Net.ToClient("geblib.selftest.payload", {
    TOKEN,
    Net.Bool,
    Net.UInt(10),
    Net.Int(8),
    Net.Range(-5, 5),
    Net.Float,
    Net.Double,
    Net.String(32),
    Net.Entity,
    Net.Player,
    Net.Vector,
    Net.Normal,
    Net.Angle,
    Net.Color,
    Net.Optional(Net.UInt(8)),
    Net.Optional(Net.UInt(8)),
    Net.Array(Net.UInt(4), 4),
    Net.Array(Net.UInt(4), 4),
    Net.OneOf({Net.String(16), Net.Color}),
    Net.OneOf({Net.String(16), Net.Color}),
})
local BroadcastProbe = Net.ToClient("geblib.selftest.broadcast", {TOKEN})
local BatchProbe = Net.ToClient("geblib.selftest.batch", {TOKEN, Net.UInt(6)}, {batch = 4})
local BeginClientProbes = Net.ToClient("geblib.selftest.begin_client", {TOKEN})
local Result = Net.ToClient("geblib.selftest.result", {TOKEN, Net.Bool, Net.String(256)})
local UnreliableProbe = Net.ToClient("geblib.selftest.unreliable", {TOKEN}, {unreliable = true})

local function selfTestEnabled()
    return gebLib.DebugMode and gebLib.DebugMode()
end

if SERVER then
    local runs = setmetatable({}, {__mode = "k"})

    local function allowed(player)
        if game.SinglePlayer() then return true end
        return player.IsListenServerHost and player:IsListenServerHost()
    end

    local function finish(state, success, detail)
        timer.Remove(state.timerName)
        runs[state.player] = nil
        detail = tostring(detail):sub(1, 256)

        local status = success and "PASS" or "FAIL"
        print("[gebLib.Net self-test] " .. status .. ": " .. detail)
        if IsValid(state.player) then Result:Send(state.player, state.token, success, detail) end
    end

    local function expect(state, stage)
        state.stage = stage
        timer.Create(state.timerName, 5, 1, function()
            if runs[state.player] == state and state.stage == stage then
                finish(state, false, stage .. " timed out")
            end
        end)
    end

    local function start(player, token)
        local previous = runs[player]
        if previous then finish(previous, false, "restarted") end

        local state = {
            player = player,
            token = token,
            timerName = "gebLib.Net.SelfTest." .. player:UserID(),
            rateCount = 0,
            malformedCount = 0,
        }
        runs[player] = state

        if not isfunction(Net.FlushBatches) or not isfunction(Net.ResetProfile)
            or not isfunction(Net.ReportProfile) or not UnreliableProbe.Unreliable then
            finish(state, false, "public net API is incomplete")
            return
        end

        expect(state, "payload")
        Payload:Send(
            player,
            token,
            true,
            777,
            -42,
            3,
            12.5,
            9876.125,
            "gebLib\0net",
            player,
            player,
            Vector(123.25, -45.5, 8),
            Vector(0, 0, 1),
            Angle(12.5, -90, 33.25),
            Color(10, 20, 30, 40),
            nil,
            200,
            {1, 7, 15},
            {},
            "union",
            Color(50, 60, 70, 80)
        )
    end

    Ready:Receive(function(player, token)
        if not selfTestEnabled() or not allowed(player) then return end
        start(player, token)
    end)

    RateProbe:Receive(function(player, token)
        local state = runs[player]
        if state and state.token == token and state.stage == "client probes" then
            state.rateCount = state.rateCount + 1
        end
    end)

    MalformedProbe:Receive(function(player, token)
        local state = runs[player]
        if state and state.token == token then state.malformedCount = state.malformedCount + 1 end
    end)

    Ack:Receive(function(player, token, phase, success, detail)
        local state = runs[player]
        if not state or state.token ~= token or state.stage ~= phase then return end
        if not success then
            finish(state, false, phase .. ": " .. detail)
            return
        end

        if phase == "payload" then
            expect(state, "broadcast")
            BroadcastProbe:Broadcast(token)
        elseif phase == "broadcast" then
            expect(state, "target batch")
            BatchProbe:Queue(player, token, 1)
            BatchProbe:Queue(player, token, 2)
            BatchProbe:Queue(player, token, 3)
        elseif phase == "target batch" then
            expect(state, "broadcast batch")
            BatchProbe:QueueBroadcast(token, 21)
            BatchProbe:QueueBroadcast(token, 22)
            if Net.FlushBatches() < 1 then
                finish(state, false, "explicit batch flush sent nothing")
            end
        elseif phase == "broadcast batch" then
            state.stage = "client probes"
            RateProbe.RateStates[player] = nil
            expect(state, "client probes")
            BeginClientProbes:Send(player, token)
        elseif phase == "client probes" then
            if state.rateCount ~= 2 then
                finish(state, false, "rate limiter accepted " .. state.rateCount .. " of 3 packets")
            elseif state.malformedCount ~= 0 then
                finish(state, false, "malformed payload reached its handler")
            else
                finish(
                    state,
                    true,
                    "all codecs, directions, batching, validation, and rate limiting passed"
                )
            end
        end
    end)
else
    local activeToken
    local batches
    local automaticStarted = false

    local function sendAck(phase, failures)
        Ack:Send(activeToken, phase, #failures == 0, table.concat(failures, ", "))
    end

    local function check(failures, condition, label)
        if not condition then failures[#failures + 1] = label end
    end

    local function approximate(value, expected, tolerance)
        return isnumber(value) and math.abs(value - expected) <= tolerance
    end

    Payload:Receive(function(
        token,
        boolValue,
        unsigned,
        signed,
        ranged,
        floatValue,
        doubleValue,
        text,
        entity,
        playerValue,
        vector,
        normal,
        angle,
        color,
        optionalMissing,
        optionalPresent,
        populated,
        empty,
        unionText,
        unionColor
    )
        if token ~= activeToken then return end

        local failures = {}
        check(failures, boolValue == true, "Bool")
        check(failures, unsigned == 777, "UInt")
        check(failures, signed == -42, "Int")
        check(failures, ranged == 3, "Range")
        check(failures, approximate(floatValue, 12.5, 0.0001), "Float")
        check(failures, approximate(doubleValue, 9876.125, 0.000001), "Double")
        check(failures, text == "gebLib\0net", "String")
        check(failures, entity == LocalPlayer(), "Entity")
        check(failures, playerValue == LocalPlayer(), "Player")
        check(
            failures,
            isvector(vector) and approximate(vector.x, 123.25, 0.05)
                and approximate(vector.y, -45.5, 0.05) and approximate(vector.z, 8, 0.05),
            "Vector"
        )
        check(
            failures,
            isvector(normal) and approximate(normal.x, 0, 0.001)
                and approximate(normal.y, 0, 0.001) and approximate(normal.z, 1, 0.001),
            "Normal"
        )
        check(
            failures,
            isangle(angle) and approximate(angle.p, 12.5, 0.1)
                and approximate(angle.y, -90, 0.1) and approximate(angle.r, 33.25, 0.1),
            "Angle"
        )
        check(
            failures,
            IsColor(color) and color.r == 10 and color.g == 20 and color.b == 30 and color.a == 40,
            "Color"
        )
        check(failures, optionalMissing == nil and optionalPresent == 200, "Optional")
        check(
            failures,
            istable(populated) and #populated == 3 and populated[1] == 1
                and populated[2] == 7 and populated[3] == 15,
            "Array populated"
        )
        check(failures, istable(empty) and #empty == 0, "Array empty")
        check(failures, unionText == "union", "OneOf string")
        check(
            failures,
            IsColor(unionColor) and unionColor.r == 50 and unionColor.g == 60
                and unionColor.b == 70 and unionColor.a == 80,
            "OneOf color"
        )
        sendAck("payload", failures)
    end)

    BroadcastProbe:Receive(function(token)
        if token == activeToken then sendAck("broadcast", {}) end
    end)

    BatchProbe:Receive(function(token, value)
        if token ~= activeToken then return end

        local target = value < 20 and batches.target or batches.broadcast
        target[#target + 1] = value

        if #batches.target == 3 and not batches.targetAcknowledged then
            batches.targetAcknowledged = true
            local failures = {}
            check(
                failures,
                batches.target[1] == 1 and batches.target[2] == 2 and batches.target[3] == 3,
                "target batch order"
            )
            sendAck("target batch", failures)
        elseif #batches.broadcast == 2 and not batches.broadcastAcknowledged then
            batches.broadcastAcknowledged = true
            local failures = {}
            check(
                failures,
                batches.broadcast[1] == 21 and batches.broadcast[2] == 22,
                "broadcast batch order"
            )
            sendAck("broadcast batch", failures)
        end
    end)

    BeginClientProbes:Receive(function(token)
        if token ~= activeToken then return end

        RateProbe:Send(token, 1)
        RateProbe:Send(token, 2)
        RateProbe:Send(token, 3)

        net.Start("geblib.selftest.malformed")
        net.SendToServer()

        sendAck("client probes", {})
    end)

    Result:Receive(function(token, success, detail)
        if token ~= activeToken then return end
        print("[gebLib.Net self-test] " .. (success and "PASS" or "FAIL") .. ": " .. detail)
    end)

    local function start(force)
        if automaticStarted and not force then return end
        automaticStarted = true

        if not selfTestEnabled() then
            print("[gebLib.Net self-test] run geblib_developer_debugmode 1, then geblib_net_selftest")
            return
        end

        local player = LocalPlayer()
        if not IsValid(player) then
            print("[gebLib.Net self-test] LocalPlayer is not ready")
            return
        end

        activeToken = util.CRC(tostring(SysTime()) .. ":" .. player:SteamID64())
        batches = {target = {}, broadcast = {}}
        print("[gebLib.Net self-test] running")
        Ready:Send(activeToken)
    end

    hook.Add("gebLib.PlayerFullyConnected", "gebLib.Net.SelfTest", function()
        timer.Simple(1, function()
            if selfTestEnabled() then start(false) end
        end)
    end)

    concommand.Add("geblib_net_selftest", function() start(true) end)

    timer.Simple(0, function()
        if selfTestEnabled() and IsValid(LocalPlayer()) then start(false) end
    end)
end
