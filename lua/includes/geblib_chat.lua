local Player = FindMetaTable("Player")

local messageName = "gebLib.Chat"

local function normalizeArguments(arguments)
    for index, value in ipairs(arguments) do
        if isstring(value) then
            arguments[index] = language.GetPhrase(value)
        elseif istable(value) and isnumber(value.r) and isnumber(value.g) and isnumber(value.b) then
            arguments[index] = Color(value.r, value.g, value.b, value.a or 255)
        end
    end

    return arguments
end

function Player:gebLib_ChatAddText(...)
    local arguments = {...}

    if CLIENT then
        chat.AddText(unpack(normalizeArguments(arguments)))
        return
    end

    if not IsValid(self) then return end

    net.Start(messageName)
    net.WriteTable(arguments)
    net.Send(self)
end

if SERVER then
    util.AddNetworkString(messageName)
else
    net.Receive(messageName, function()
        local arguments = net.ReadTable()
        if not istable(arguments) then return end
        chat.AddText(unpack(normalizeArguments(arguments)))
    end)
end
