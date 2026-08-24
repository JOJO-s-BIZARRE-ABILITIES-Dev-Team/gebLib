local Player = FindMetaTable("Player")
local unpackArguments = unpack or table.unpack

local chatMessage = gebLib.Net.ToClient("geblib.chat", {
    gebLib.Net.Array(gebLib.Net.OneOf({
        gebLib.Net.String(1024),
        gebLib.Net.Color,
    }), 32),
})

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
        chat.AddText(unpackArguments(normalizeArguments(arguments)))
        return
    end

    if not IsValid(self) then return end
    chatMessage:Send(self, arguments)
end

if CLIENT then
    chatMessage:Receive(function(arguments)
        chat.AddText(unpackArguments(normalizeArguments(arguments)))
    end)
end
