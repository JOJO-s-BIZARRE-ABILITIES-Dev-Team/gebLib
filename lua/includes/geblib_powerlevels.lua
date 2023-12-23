-------------------------------------------------------------------
--Powerlevels are used for power scaling
--You can add a power level to your SWEP 
-------------------------------------------------------------------

--------------------------
local MPLY = FindMetaTable("Player")
local MENT = FindMetaTable("Entity")
--------------------------
local netStart          = net.Start
local netReceive        = net.Receive
local netWriteData      = net.WriteData
local netReadData       = net.ReadData
local netWriteUInt      = net.WriteUInt
local netReadUInt       = net.ReadUInt
local netWriteFloat     = net.WriteFloat
local netReadFloat      = net.ReadFloat
local netWriteBool      = net.WriteBool
local netReadBool       = net.ReadBool
local netWriteEntity    = net.WriteEntity
local netReadEntity     = net.ReadEntity
local netSend           = net.Send
local netBroadcast      = net.Broadcast
--------------------------
if SERVER then
    util.AddNetworkString("gebLib.cl.powerlevel.SetPowerLevel")
end
--------------------------

function MENT:gebLib_SetPowerLevel( powerLevel )
    powerLevel = math.Clamp( powerLevel, 0, math.huge )

    if SERVER then
        netStart( "gebLib.cl.powerlevel.SetPowerLevel" )
            netWriteEntity( self )
            netWriteFloat( powerLevel )
        netBroadcast()
    end

    self.gebLib_PowerLevel = powerLevel
end

if CLIENT then
    netReceive("gebLib.cl.powerlevel.SetPowerLevel", function()
        local entity = netReadEntity()
        local powerLevel = netReadFloat()

        powerLevel = math.Clamp( powerLevel, 0, math.huge )

        entity.gebLib_PowerLevel = powerLevel
    end)
end

function MENT:gebLib_GetPowerLevel()
    return self.gebLib_PowerLevel or 0
end