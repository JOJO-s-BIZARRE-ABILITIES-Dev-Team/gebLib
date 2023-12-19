gebLib_utils = {}

if CLIENT then
    gebLib__DebrisList = {} // table where we store existing debris
end
--------------------------
local MPLY = FindMetaTable("Player")
local MENT = FindMetaTable("Entity")
--------------------------
local error             = error
local Vector            = Vector
local Angle             = Angle
local stringmatch       = string.match
local TableToJSON       = util.TableToJSON
local JSONToTable       = util.JSONToTable
local Compress          = util.Compress
local Decompress        = util.Decompress
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
local netSend           = net.Send
local netBroadcast      = net.Broadcast
local TraceLine         = util.TraceLine
local TraceHull         = util.TraceHull
local tableInsert       = table.insert
local tableMerge        = table.Merge
local IsValid           = IsValid
local istable           = istable
local isstring          = isstring
local IsEntity          = IsEntity
local mathFloor         = math.floor
local type              = type
local pairs             = pairs
local ipairs            = ipairs
local unpack            = unpack
--------------------------
if SERVER then
    util.AddNetworkString("gebLib.cl.utils.ChatAddText")
    util.AddNetworkString("gebLib.cl.utils.PlayAnim")
    util.AddNetworkString("gebLib.cl.utils.PlayAnim.Action")
end
--------------------------
/////////////////////////
// PLAYER FUNCTIONS
/////////////////////////
--------------------------
function MPLY:gebLib_ChatAddText( ... )
    if CLIENT then return end
    local args = { ... }

    local json = TableToJSON( args )
    local data = Compress( json )
    local bytes = #data

    netStart( "gebLib.cl.utils.ChatAddText" )
        netWriteUInt( bytes, 16 )
        netWriteData( data, bytes )
    netSend( self )
end

if CLIENT then
    netReceive("gebLib.cl.utils.ChatAddText", function()
        local bytes = netReadUInt(16)
        local data = netReadData(bytes)

        local json = Decompress(data)
        local args = JSONToTable(json)

        for k, v in ipairs( args ) do
            if isstring(v) then
                args[ k ] = language.GetPhrase( v )   
            end
        end

        chat.AddText( unpack( args ) )
    end)
end

function MPLY:gebLib_PlaySequence( slot, sequence, cycle, autokill )
    -- if CLIENT and !IsFirstTimePredicted() then return end

    cycle = cycle or 0
    autokill = autokill or true
    if isstring( sequence ) then
        sequence = self:LookupSequence( sequence )
    end

    self:AddVCDSequenceToGestureSlot( slot, sequence, cycle, autokill )

    if SERVER then
        netStart( "gebLib.cl.utils.PlayAnim" )
            netWriteUInt( self:EntIndex(), 6 )
            netWriteUInt( slot, 3 )
            netWriteUInt( sequence, 16 )
            netWriteFloat( cycle )
            netWriteBool( autokill )
        netBroadcast()
    end
end

function MPLY:gebLib_PlayAction( slot, sequence, playback )
    -- if CLIENT and !IsFirstTimePredicted() then return end

    playback = playback or 1
    if isstring( sequence ) then
        sequence = self:LookupSequence( sequence )
    end

    self:AddVCDSequenceToGestureSlot( slot, sequence, 0, true )
    self:SetLayerPlaybackRate( 0, playback )

    if SERVER then
        net.Start( "gebLib.cl.utils.PlayAnim.Action" )
            net.WriteUInt( self:EntIndex(), 6 )
            net.WriteUInt( slot, 3 )
            net.WriteUInt( sequence, 10 )
            net.WriteFloat( playback )
        net.Broadcast()
    end
end

if CLIENT then
    netReceive("gebLib.cl.utils.PlayAnim", function() 
        local ply = Entity( net.ReadUInt( 6 ) )
        if LocalPlayer() == ply then return end
        
        local slot = netReadUInt( 3 )
        local anim = netReadUInt( 10 )
        local cycle = netReadFloat()
        local autokill = netReadBool()

        ply:AddVCDSequenceToGestureSlot( slot, anim, cycle, autokill )
    end)

    netReceive("gebLib.cl.utils.PlayAnim.Action", function() 
        local ply = Entity( net.ReadUInt( 6 ) )
        if LocalPlayer() == ply then return end
        
        local anim = netReadUInt( 10 )
        local playback = netReadFloat()

        ply:AddVCDSequenceToGestureSlot( 0, anim, 0, true )
        ply:SetLayerPlaybackRate( 0, playback )
    end)
end
//
--------------------------
/////////////////////////
// ENTITY FUNCTIONS
/////////////////////////
--------------------------
function MENT:gebLib_IsPerson()
    return self:IsPlayer() or self:IsNPC() or self:IsNextBot()
end
/////////////////////////
function MENT:gebLib_Alive()
    if not self:IsValid() then return end
    if !self:gebLib_IsPerson() then return false end

    if !self:IsPlayer() and self:Health() > 0 then
        return true
    elseif self:IsPlayer() and self:Alive() then
        return true
    end
    return false
end
/////////////////////////
function MENT:gebLib_IsLookingAt(vec, minDiff)
    minDiff = minDiff or 0.90

	local lookVector = self:GetForward()

	if self:IsPlayer() then
		lookVector = self:GetAimVector()
	end

    local diff = vec - self:GetPos()
	return lookVector:Dot(diff) / diff:Length() >= minDiff
end
/////////////////////////
function MENT:gebLib_CheckSides( mult, filterEnts )
	mult = mult or 1
	local stand = NULL

	local pos = self:GetPos()
    //
    local toFilter = {}
    if IsEntity( filterEnts ) then
        tableInsert( toFilter, filterEnts )
    elseif istable( filterEnts ) then
        tableMerge( toFilter, filterEnts )
    else
        return error( "#2 argument needs to be a table or an entity!" )
    end
    //
	local traceData = {
		start = pos,
		endpos = pos - self:GetUp() * mult,
		filter = toFilter,
		mask = MASK_SOLID
	}

	local trace = TraceLine(traceData) --Down

	if trace.Hit then return trace end

	traceData.endpos = pos + self:GetUp() * mult --Up
	trace = TraceLine(traceData)

	if trace.Hit then return trace end

	traceData.endpos = pos + self:GetRight() * mult --Right
	trace = TraceLine(traceData)

	if trace.Hit then return trace end

	traceData.endpos = pos - self:GetRight() * mult ---Left
	trace = TraceLine(traceData)

	if trace.Hit then return trace end

	traceData.endpos = pos + self:GetForward() * mult --Front
	trace = TraceLine(traceData)

	if trace.Hit then return trace end

	traceData.endpos = pos - self:GetForward() * mult --Back
	trace = TraceLine(traceData)

	if trace.Hit then return trace end

	return false
end
/////////////////////////
--TODO: Should change, but currently the most accurate
local mins = Vector(-18, -18, 0)
local maxs = Vector(18, 18, 73)
/////////////////////////
function MENT:gebLib_PositionEmpty(pos, filter)
	filter = filter or self
    return not TraceHull({start = pos, endpos = pos, mins = mins, maxs = maxs, filter = filter}, self).Hit
end
/////////////////////////
function MENT:gebLib_FindEmptyPosition(pos, distance, step, filter )
    if self:gebLib_PositionEmpty(pos) then
        return pos
    end
    for j = step, distance, step do
        for i = -1 ,1, 2 do
            local offset = j*i
			local xPos = Vector(offset, 0, 0)
            if self:gebLib_PositionEmpty(pos + xPos, filter) then
                return pos + xPos
            end
			local yPos = Vector(0, offset, 0)
            if self:gebLib_PositionEmpty(pos + yPos, filter) then
                return pos + yPos
            end
			local zPos = Vector(0, 0, offset)
            if self:gebLib_PositionEmpty(pos + zPos, filter) then
                return pos + zPos
            end
        end
    end
    
    return pos
end
/////////////////////////
function MENT:gebLib_GetBoneHitBox(bone)
    if isstring(bone) then
        bone = self:LookupBone(bone)
    end

    local numHitBoxSets = self:GetHitboxSetCount()
    
    for hboxset = 0, numHitBoxSets - 1 do
        local numHitBoxes = self:GetHitBoxCount( hboxset )
          
        for hitbox = 0, numHitBoxes - 1 do
            local hBone = self:GetHitBoxBone(hitbox, hboxset)

            if hBone == bone then
                return self:GetHitBoxBounds(hitbox, hboxset)
            end
        end
    end
end
/////////////////////////
function gebLib_utils.IsNormalized(vector)
	return mathFloor( vector:LengthSqr() + 0.5 ) == 1
end
/////////////////////////
function gebLib_utils.MatchFromTable(table, toMatch)
	for _, v in ipairs(table) do
		if stringmatch(toMatch, v) then
			return true
		end
	end
	 
	return false
end
/////////////////////////
function gebLib_utils.TableEquals(tbl1, tbl2)
	if tbl1 == tbl2 then
		return true
	elseif type(tbl1) == "table" and type(tbl2) == "table" then
		for key1, value1 in pairs(tbl1) do
			local value2 = tbl2[key1]
			if value2 == nil then
				-- avoid the type call for missing keys in tbl2 by directly comparing with nil
				return false
			elseif value1 ~= value2 then
				if type(value1) == "table" and type(value2) == "table" then
					if not table.Equals(value1, value2) then
						return false
					end
				else
					return false
				end
			end
		end
		-- check for missing keys in tbl1
		for key2, _ in pairs(tbl2) do
			if tbl1[key2] == nil then
				return false
			end
		end
		return true
	end
	return false
end
/////////////////////////
--Technique to make projectiles aim where your crosshair is
function gebLib_utils.GetPerfectProjectileTrajectory( posOfProjectile, shootPos, normal, filterEnts ) // By Denderino
    local tr = util.TraceLine( {
        start = shootPos,
        endpos = shootPos + normal * 100000000,
        filter = filterEnts,
        mask = MASK_SHOT_HULL
    } )
    
    local result = normal
    if tr.Hit then
        result = ( tr.HitPos - posOfProjectile )  
    end
    return result 
end
/////////////////////////
// Debris
/////////////////////////
if CLIENT then

    function gebLib_utils.CreateDebris( modelPath, isProp, lifeTime )
        local debris
        if isProp then
            debris = ents.CreateClientProp( modelPath )
        else
            debris = ClientsideModel( modelPath )
        end
        //
        local index = table.insert( gebLib__DebrisList, debris )
        local finalLifeTime = lifeTime or 10

        debris.TableIndex   = index
        debris.LifeTime     = CurTime() + finalLifeTime

        local hookNameThink = "gebLib.Debris.Think."  .. tostring( index )
        hook.Add( "Think", hookNameThink, function( )
            if !IsValid( debris ) then hook.Remove( "Think", hookNameThink ) return end

            if CurTime() > debris.LifeTime then
                gebLib_utils.RemoveDebris( debris )
            end
        end)

        local hookNameRender = "gebLib.Debris.PostDrawTranslucent."  .. tostring( index )
        hook.Add( "PostDrawTranslucentRenderables", hookNameRender, function( )
            if !IsValid( debris ) then hook.Remove( "PostDrawTranslucentRenderables", hookNameRender ) return end
            if bDrawingSkybox or bDraw3DSkybox then return end

            if CurTime() > debris.LifeTime - 1 then
                if !debris:GetNoDraw() then
                    debris:SetNoDraw( true )
                end

                local blend = Lerp( math.abs( debris.LifeTime - CurTime() - 1 ) / 1, 1, 0 )
                
                render.SetBlend( blend )
                debris:DrawModel()
                render.SetBlend( 1 )
            end
        end)
        //
        return debris
    end

    function gebLib_utils.RemoveDebris( debris )
        gebLib__DebrisList[ debris.TableIndex ] = nil

        debris:Remove()
    end

end
/////////////////////////
// Vars
/////////////////////////
gebLib_tickrateMultiplier = math.Round( 66.66 * engine.TickInterval(), 2 )

/////////////////////////
// BLACKLISTS
////////////////////////
gebLib.Blacklist = {}
gebLib.Blacklist.KnockbackEntities = {
    ["npc_strider"] = true,
    ["func_door_rotating"] = true,
    ["func_door"] = true,
}
