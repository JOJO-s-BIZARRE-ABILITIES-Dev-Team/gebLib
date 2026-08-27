local Example = gebLibExample
if not Example then return end

local aimBone = CreateClientConVar("geblib_example_aim_bone", "0", true, false)
local blockPose = CreateClientConVar("geblib_example_block_pose", "0", true, false)
local trailEnabled = CreateClientConVar("geblib_example_trail", "0", true, false)

local cameraChannel = gebLib.CameraImpulses.Create(
    "geblib.example.camera.impact",
    200,
    function(player, view, channel)
        view.angles.p = view.angles.p + channel:Get("pitch")
        view.angles.r = view.angles.r + channel:Get("roll")
        view.origin = view.origin + view.angles:Right() * channel:Get("side")
        return math.abs(channel:Get("pitch")) > 0.001
            or math.abs(channel:Get("roll")) > 0.001
            or math.abs(channel:Get("side")) > 0.001
    end
)

local fovUntil = 0
gebLib.CameraModifiers.Register("geblib.example.camera.fov", 100, function(player, view)
    local remaining = fovUntil - RealTime()
    if remaining <= 0 then return false end

    view.fov = view.fov - remaining * 8
    return true
end)

function Example.KickCamera(position, strength)
    local scale = math.Clamp(strength / 180, 0.5, 2)
    cameraChannel:PushAt(
        position,
        1400,
        {pitch = -2.5 * scale, roll = 1.4 * scale, side = 1.2 * scale},
        {pitch = 9, roll = 11, side = 14},
        LocalPlayer(),
        "add"
    )
    fovUntil = RealTime() + 0.12
end

gebLib.BoneControllers.Register("geblib.example.aim", {
    Bone = "ValveBiped.Bip01_Spine2",
    Speed = Angle(120, 180, 180),
    ResetImmediately = false,
    IsActive = function(player)
        return aimBone:GetBool() and player == LocalPlayer() and player:Alive()
    end,
    GetTarget = function(player)
        return math.Clamp(player:EyeAngles().p * 0.35, -25, 25), 0, 0
    end,
})

gebLib.BoneMatrixModifiers.Register("geblib.example.block", {
    Priority = 50,
    Channel = "geblib.example.upper_body",
    IsActive = function(entity)
        return blockPose:GetBool() and entity == LocalPlayer() and entity:Alive()
    end,
    Apply = function(entity)
        local bone = entity:LookupBone("ValveBiped.Bip01_L_UpperArm")
        if not bone then return end

        local matrix = entity:GetBoneMatrix(bone)
        if not matrix then return end

        matrix:Rotate(Angle(-15, 0, -30))
        entity:SetBoneMatrix(bone, matrix)
    end,
})

local function trackLocalPlayer()
    local player = LocalPlayer()
    if IsValid(player) then
        gebLib.BoneMatrixModifiers.Track(player, "geblib.example")
    end
end

hook.Add("InitPostEntity", "gebLibExample.TrackBones", trackLocalPlayer)
timer.Simple(0, trackLocalPlayer)

local trail
hook.Add("Think", "gebLibExample.ReplicaTrail", function()
    local player = LocalPlayer()
    if not trailEnabled:GetBool() or not IsValid(player) or not player:Alive() then
        if trail then trail:ClearSnapshots() end
        return
    end

    if not trail or not trail:IsValid() then
        if trail then trail:Remove() end
        trail = gebLib.ReplicaTrail.New(player, {
            mode = "sequence",
            interval = 0.06,
            lifetime = 0.35,
            limit = 8,
            shadows = false,
            appearance = function(replica)
                replica:SetColor(Color(120, 200, 255))
                replica:SetRenderMode(RENDERMODE_TRANSALPHA)
            end,
        })
    end

    trail:Capture(RealTime())
end)

hook.Add("PostDrawTranslucentRenderables", "gebLibExample.DrawReplicaTrail", function()
    if not trail or not trailEnabled:GetBool() then return end

    trail:Draw(RealTime(), function(replica, progress)
        render.SetBlend((1 - progress) * 0.3)
        replica:DrawModel()
        render.SetBlend(1)
    end)
end)

local music = gebLib.Audio.New()
hook.Add("Think", "gebLibExample.Audio", function()
    music:Update(RealTime())
end)

concommand.Add("geblib_example_music", function()
    if music:IsPlaying() then
        music:Stop(0.25)
        return
    end

    local path = "sound/music/hl2_song14.mp3"
    music:PlayFile(path, "noplay noblock", {
        volume = 0.35,
        onReady = function()
            local duration = gebLib.SoundDuration(path)
            if duration > 0 then music:ScheduleRestart(duration, RealTime()) end
        end,
        onFailure = function()
            chat.AddText(Color(255, 180, 120), "Example music is not mounted")
        end,
    })
end)

local activeCamera
concommand.Add("geblib_example_camera", function()
    if activeCamera and activeCamera.Playing then activeCamera:Stop() end

    local player = LocalPlayer()
    if not IsValid(player) or not player:Alive() then return end

    local camera = gebLib.Camera.New("geblib.example.orbit", player, 60, 180, true, true)
    activeCamera = camera
    camera:AddEvent(0, 180, function(viewer)
        local focus = viewer:WorldSpaceCenter()
        local yaw = camera.CurFrame * 2
        local offset = Angle(12, yaw, 0):Forward() * -130 + vector_up * 35
        local position = focus + offset
        return position, (focus - position):Angle(), 72
    end)
    camera:SetEnd(function(finished)
        if activeCamera == finished then activeCamera = nil end
    end)
    camera:Play()
end)

concommand.Add("geblib_example_power", function(_, _, arguments)
    local power = math.Clamp(math.floor(tonumber(arguments[1]) or 1), 1, 4)
    Example.SelectPowerMessage:Send(power)
end)

hook.Add("ShutDown", "gebLibExample.PresentationCleanup", function()
    gebLib.CameraImpulses.Remove("geblib.example.camera.impact")
    gebLib.CameraModifiers.Remove("geblib.example.camera.fov")
    gebLib.BoneControllers.Remove("geblib.example.aim")

    local player = LocalPlayer()
    if IsValid(player) then
        gebLib.BoneMatrixModifiers.Untrack(player, "geblib.example")
    end
    gebLib.BoneMatrixModifiers.Remove("geblib.example.block")

    if trail then trail:Remove() end
    if activeCamera and activeCamera.Playing then activeCamera:Stop() end
    music:Remove()
end)
