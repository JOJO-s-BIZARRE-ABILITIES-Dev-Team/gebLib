local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function isnumber(value) return type(value) == "number" end
function isstring(value) return type(value) == "string" end
function istable(value) return type(value) == "table" end
function IsValid(value) return type(value) == "table" and value.valid == true end
function IsFirstTimePredicted() return true end
function LocalPlayer() return localPlayer end
function Color(red, green, blue, alpha)
    return {color = true, r = red, g = green, b = blue, a = alpha}
end
function IsColor(value) return type(value) == "table" and value.color == true end

math.Clamp = math.Clamp or function(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local Player = {}
Player.__index = Player

function FindMetaTable(name)
    assertEqual(name, "Player", "metatable lookup")
    return Player
end

function Player:IsPlayer() return true end
function Player:LookupSequence() return -1 end
function Player:AddVCDSequenceToGestureSlot(slot, sequence, cycle, autokill)
    self.lastPlay = {slot, sequence, cycle, autokill}
end
function Player:SetLayerPlaybackRate(slot, playback)
    self.lastPlayback = {slot, playback}
end
function Player:SetLayerDuration(slot, duration)
    self.lastDuration = {slot, duration}
end
function Player:SetLayerCycle(slot, cycle)
    self.lastCycle = {slot, cycle}
end
function Player:SetLayerLooping(slot, looping)
    self.lastLooping = {slot, looping}
end

local function newPlayer()
    return setmetatable({valid = true}, Player)
end

local function newNetFacade()
    local definitions = {}
    local facade = {
        Player = "Player",
        Float = "Float",
        Bool = "Bool",
        Color = "Color",
    }

    function facade.UInt(bits) return "UInt(" .. bits .. ")" end
    function facade.String(maximum) return {kind = "String", maximum = maximum} end
    function facade.OneOf(choices) return {kind = "OneOf", choices = choices} end
    function facade.Array(codec, maximum) return {kind = "Array", codec = codec, maximum = maximum} end

    function facade.ToClient(name, schema)
        local message = {name = name, schema = schema, sent = {}, broadcasts = {}}
        definitions[name] = message

        function message:Send(...)
            self.sent[#self.sent + 1] = {n = select("#", ...), ...}
        end

        function message:Broadcast(...)
            self.broadcasts[#self.broadcasts + 1] = {n = select("#", ...), ...}
        end

        function message:Receive(callback)
            self.receiver = callback
        end

        return message
    end

    return facade, definitions
end

do
    SERVER = true
    CLIENT = false
    gebLib = {}
    gebLib.Net, definitions = newNetFacade()

    dofile("lua/geblib/chat.lua")
    dofile("lua/geblib/player_animation.lua")

    local player = newPlayer()
    local color = Color(255, 100, 50, 255)

    player:gebLib_ChatAddText(color, "message")
    local chatSend = definitions["geblib.chat"].sent[1]
    assertEqual(chatSend[1], player, "chat recipient")
    assertEqual(chatSend[2][1], color, "chat color")
    assertEqual(chatSend[2][2], "message", "chat text")

    assertEqual(player:gebLib_PlaySequence(2, 100, 0.25, true, 1.5), true, "play sequence")
    local play = definitions["geblib.player_animation.play"].broadcasts[1]
    assertEqual(play[1], player, "animation player")
    assertEqual(play[2], 2, "animation slot")
    assertEqual(play[3], 100, "animation sequence")
    assertEqual(play[4], 0.25, "animation cycle")
    assertEqual(play[6], 1.5, "animation playback")

    player:gebLib_PauseSequence(2)
    player:gebLib_ResumeSequence(2, 0.75)
    player:gebLib_StopSequence(2)
    assertEqual(#definitions["geblib.player_animation.pause"].broadcasts, 1, "pause packet")
    assertEqual(definitions["geblib.player_animation.resume"].broadcasts[1][3], 0.75, "resume packet")
    assertEqual(#definitions["geblib.player_animation.stop"].broadcasts, 1, "stop packet")
end

do
    SERVER = false
    CLIENT = true
    gebLib = {}
    gebLib.Net, definitions = newNetFacade()
    language = {GetPhrase = function(text) return "localized:" .. text end}

    local chatArguments
    chat = {AddText = function(...)
        chatArguments = {n = select("#", ...), ...}
    end}

    localPlayer = newPlayer()

    dofile("lua/geblib/chat.lua")
    dofile("lua/geblib/player_animation.lua")

    local remote = newPlayer()
    definitions["geblib.player_animation.play"].receiver(remote, 3, 101, 0.5, false, 2)
    assertEqual(remote.lastPlay[1], 3, "received play slot")
    assertEqual(remote.lastPlay[2], 101, "received play sequence")
    assertEqual(remote.lastPlayback[2], 2, "received play rate")

    definitions["geblib.player_animation.pause"].receiver(remote, 3)
    assertEqual(remote.lastPlayback[2], 0, "received pause")
    definitions["geblib.player_animation.resume"].receiver(remote, 3, 0.5)
    assertEqual(remote.lastPlayback[2], 0.5, "received resume")
    definitions["geblib.player_animation.stop"].receiver(remote, 3)
    assertEqual(remote.lastDuration[2], 0, "received stop")

    definitions["geblib.chat"].receiver({Color(1, 2, 3, 4), "phrase.key"})
    assertEqual(chatArguments.n, 2, "received chat argument count")
    assertEqual(chatArguments[2], "localized:phrase.key", "received chat localization")
end

print("network features: ok")
