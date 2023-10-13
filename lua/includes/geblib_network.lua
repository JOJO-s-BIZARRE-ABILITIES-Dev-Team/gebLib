--This is a static net class made for easier networking
--Made by T0M

if SERVER then
    util.AddNetworkString("gebLib.cl.core.UpdateString")
    util.AddNetworkString("gebLib.cl.core.UpdateInt")
    util.AddNetworkString("gebLib.cl.core.UpdateUInt")
    util.AddNetworkString("gebLib.cl.core.UpdateFloat")
    util.AddNetworkString("gebLib.cl.core.UpdateBool")
    util.AddNetworkString("gebLib.cl.core.UpdateTable")
    util.AddNetworkString("gebLib.cl.core.UpdateVector")
    util.AddNetworkString("gebLib.cl.core.UpdateVectorNormal")
    util.AddNetworkString("gebLib.cl.core.UpdateAngle")
    util.AddNetworkString("gebLib.cl.core.UpdateColor")
    util.AddNetworkString("gebLib.cl.core.UpdateByIndex")
end

--Helper functions
local function NumberToBits(num)
    if num < 0 then
        num = math.abs(num + 1)
    end

    local bitsAmount = math.floor(math.log(num * 2, 2)) + 1

    if bitsAmount < 3 then
        bitsAmount = 3
    end

    return bitsAmount
end

--Used only for positive numbers, otherwise it will error
local function UnsignedNumberToBits(uNum)
    if uNum % 2 == 0 then
        uNum = uNum + 1
    end

    local bitsAmount = math.floor(math.log(uNum, 2)) + 1

    return bitsAmount
end

--Class

gebLib_net = {}
gebLib_net.__index = gebLib_net

function gebLib_net.UpdateEntityValue(entity, varName, valueToSet)
    if isstring(valueToSet) then
        gebLib_net.UpdateEntityString(entity, varName, valueToSet)
    elseif isnumber(valueToSet) then
        gebLib_net.UpdateEntityNumber(entity, varName, valueToSet)
    elseif isbool(valueToSet) then
        gebLib_net.UpdateEntityBool(entity, varName, valueToSet)
    elseif isvector(valueToSet) then
        gebLib_net.UpdateEntityVector(entity, varName, valueToSet)
    elseif isangle(valueToSet) then
        gebLib_net.UpdateEntityAngle(entity, varName, valueToSet)
    elseif IsColor(valueToSet) then
        gebLib_net.UpdateEntityColor(entity, varName, valueToSet)
    elseif istable(valueToSet) then
        gebLib_net.UpdateEntityTable(entity, varName, valueToSet)
    end
end

function gebLib_net.UpdateEntityString(entity, varName, stringToSet)
    net.Start("gebLib.cl.core.UpdateString")
    net.WriteString(stringToSet) --Has to be first!
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityTable(entity, varName, tableToSet)
    local json = util.TableToJSON(tableToSet)
    local compressedData = util.Compress(json)
    local bytesAmount = #compressedData

    net.Start("gebLib.cl.core.UpdateTable")
    net.WriteUInt(bytesAmount, 16)
    net.WriteData(compressedData, bytesAmount)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityColor(entity, varName, colorToSet)
    net.Start("gebLib.cl.core.UpdateColor")
    net.WriteColor(colorToSet, false)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityVector(entity, varName, vectorToSet)
    if gebLib_IsNormalized(vectorToSet) then
        gebLib_net.UpdateEntityNormalVector()
    else
        gebLib_net.UpdateEntityVectorSlow()
    end
end

function gebLib_net.UpdateEntityVectorSlow(entity, varName, vectorToSet)
    net.Start("gebLib.cl.core.UpdateVector")
    net.WriteVector(vectorToSet)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityNormalVector(entity, varName, vectorToSet)
    net.Start("gebLib.cl.core.UpdateVectorNormal")
    net.WriteNormal(vectorToSet)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityAngle(entity, varName, angleToSet)
    net.Start("gebLib.cl.core.UpdateAngle")
    net.WriteAngle(angleToSet)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityBool(entity, varName, boolToSet)
    net.Start("gebLib.cl.core.UpdateBool")
    net.WriteBool(boolToSet)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityByIndex(entity, varName, stringToSet)
    local varIndex = BA_VarsToIndexes[varName]
    local valueIndex = BA_StandsToIndexes[stringToSet]

    net.Start("gebLib.cl.core.UpdateByIndex")
    net.WriteEntity(entity)
    net.WriteUInt(varIndex, UnsignedNumberToBits(#BA_IndexesToVars)) --Need to get sequential version of the table, so I'll get the table with numerical keys
    net.WriteUInt(valueIndex, UnsignedNumberToBits(#BA_IndexesToStands)) --Need to get sequential version of the table, so I'll get the table with numerical keys
    net.Broadcast()    
end

function gebLib_net.UpdateEntityNumber(entity, varName, numberToSet)
    if numberToSet % 1 != 0 then
        gebLib_net.UpdateEntityFloat(entity, varName, numberToSet)
    elseif numberToSet > 0 then
        gebLib_net.UpdateEntityUInt(entity, varName, numberToSet)
    else
        gebLib_net.UpdateEntityInt(entity, varName, numberToSet)
    end
end

function gebLib_net.UpdateEntityInt(entity, varName, numberToSet, bitsAmount)
    if not bitsAmount then
        bitsAmount = NumberToBits(numberToSet)
    end

    net.Start("gebLib.cl.core.UpdateInt")
    net.WriteUInt(bitsAmount, 6)
    net.WriteInt(numberToSet, bitsAmount)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

--Used for non negative numbers for higher speed
function gebLib_net.UpdateEntityUInt(entity, varName, numberToSet, bitsAmount)
    if not bitsAmount then
        bitsAmount = UnsignedNumberToBits(numberToSet)
    end

    net.Start("gebLib.cl.core.UpdateUInt")
    net.WriteUInt(bitsAmount, 6)
    net.WriteUInt(numberToSet, bitsAmount)
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.Broadcast()
end

function gebLib_net.UpdateEntityFloat(entity, varName, numberToSet)
    net.Start("gebLib.cl.core.UpdateFloat")
    net.WriteEntity(entity)
    net.WriteString(varName)
    net.WriteFloat(numberToSet)
    net.Broadcast()
end

--Handling for clients
if CLIENT then
    local function DebugMessage(len, entity, varName, value)
        if BA_DebugMode() and gebLib_networkDebug() then
            BA_PrintDebug(tostring(LocalPlayer()) .. ": network message length: " .. len .. " bits, " .. "entity: " .. tostring(entity) .. ", variable name: " .. varName .. ", variable value: " ..tostring(value))
        end
    end

    local function SetEntityValue(value, len)
        local entity = net.ReadEntity()
        local varName = net.ReadString()
        DebugMessage(len, entity, varName, value)

        if not entity:IsValid() then
            error("gebLib Networking: Trying to update variable: " .. varName .. " to value: " .. tostring(value) .. " on entity that is nil, entity might not be loaded or does not exist on the client!")
        end

        entity[varName] = value
    end

    net.Receive("gebLib.cl.core.UpdateString", function(len)
        local text = net.ReadString()
        SetEntityValue(text, len)
    end)

    net.Receive("gebLib.cl.core.UpdateInt", function(len)
        local bitsAmount = net.ReadUInt(6)
        local value = net.ReadInt(bitsAmount)
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateUInt", function(len)
        local bitsAmount = net.ReadUInt(6)
        local value = net.ReadUInt(bitsAmount)
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateFloat", function(len)
        local value = net.ReadFloat()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateBool", function(len)
        local value = net.ReadBool()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateVector", function(len)
        local value = net.ReadVector()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateVectorNormal", function(len)
        local value = net.ReadNormal()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateAngle", function(len)
        local value = net.ReadAngle()
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateColor", function(len)
        local value = net.ReadColor(false)
        SetEntityValue(value, len)
    end)

    net.Receive("gebLib.cl.core.UpdateTable", function(len)
        local bytesAmount = net.ReadUInt(16)
        local value = util.JSONToTable(util.Decompress(net.ReadData(bytesAmount)))
        SetEntityValue(value, len)
    end)
end