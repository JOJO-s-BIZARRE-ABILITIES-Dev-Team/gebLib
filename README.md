# gebLib 2

gebLib is a small Garry's Mod Lua library for status effects, timed actions, animation events, cinematic cameras, and a few focused helpers.

## Loading and dependencies

gebLib uses `lua/autorun/000_geblib_v2.lua` so its shared bootstrap runs early in Garry's Mod's alphabetically sorted autorun phase. This is an early-loading measure, not an addon-level priority system.

Code in `autorun/server`, `autorun/client`, the active gamemode, weapons, entities, and effects loads after the shared autorun phase and can use gebLib directly.

Another shared autorun file should support either order:

```lua
local initialized = false
local hookId = "MyAddon.GebLibReady"

local function initialize(lib)
    if initialized then return end

    initialized = true
    hook.Remove("gebLib.Loaded", hookId)

    -- Safe to use lib here.
end

if gebLib and gebLib.Loaded then
    initialize(gebLib)
else
    hook.Add("gebLib.Loaded", hookId, initialize)
end
```

The bootstrap sets `gebLib.Loaded` only after every module has been included, then runs `gebLib.Loaded`. Readiness callbacks must not return a value because Garry's Mod stops dispatching a hook after a non-`nil` return.

Workshop Required Items can advertise and install gebLib, but do not control Lua execution order.

## Status effects

Register a definition once:

```lua
gebLib.StatusEffects.Register("poison", {
    interval = 1,

    onTick = function(target, effect)
        target:TakeDamage(2 * effect.level, effect.source, effect.inflictor)
    end,
})
```

Apply and inspect it through the entity:

```lua
target:gebLib_ApplyStatusEffect("poison", 10, 2, attacker, weapon)

local poison = target:gebLib_GetStatusEffect("poison")
print(poison.level, poison.expiresAt - CurTime())

target:gebLib_RemoveStatusEffect("poison")
```

Definitions support four optional callbacks:

```lua
{
    interval = 1,
    onApply = function(target, effect) end,
    onTick = function(target, effect) end,
    onReapply = function(target, effect, duration, level, source, inflictor) end,
    onRemove = function(target, effect, reason) end,
}
```

`interval` defaults to one second. The Applied Status Effect passed to callbacks contains `name`, `target`, `source`, `inflictor`, `level`, `appliedAt`, `expiresAt`, and `nextTickAt`.

`onReapply` returns `true` when it completely handles the reapplication. Otherwise gebLib uses these rules:

1. A stronger level replaces the active effect.
2. The same level keeps the later expiration time.
3. A weaker level is ignored.

`onRemove` receives a short reason such as `expired`, `death`, `replaced`, `cleared`, or `entity removed`.

Status effects are not automatically networked. Apply gameplay effects on the server. Send only the state a client UI actually needs.

## Timed actions

```lua
local action = gebLib.Action.New(player, 2)

action:AddEvent("damage", 0.5, function(current)
    current.Entity:TakeDamage(20)
end)

action:SetEnd(function(current)
    print("finished", current:GetIndex())
end)

action:Start()
```

An Action owns its Think hook and removes itself when it finishes. It also supports repetition, delayed starts, pause, resume, and time scaling.

The complete lifecycle is `Start`, `Pause`, `Resume`, and `Stop`. Use `SetInit` and `SetEnd` for timeline events at zero and at the configured duration, `OnStart` for the initial start, and `OnRemove` for final cleanup.

## Entity animations

```lua
local animation = gebLib.Animation.New(entity, "attack")

animation:AddEvent("hit", 12, function(current)
    print("hit frame", current:GetFrame())
end)

animation:SetEnd(function()
    print("animation finished")
end)

animation:Play()
```

## Player animation layers

```lua
player:gebLib_PlaySequence(slot, sequence, cycle, autokill, playback)
player:gebLib_PauseSequence(slot)
player:gebLib_ResumeSequence(slot, playback)
player:gebLib_StopSequence(slot)
```

Action-animation shortcuts use gesture slot 1:

```lua
player:gebLib_PlayAction(sequence, playback)
player:gebLib_PauseAction()
player:gebLib_ResumeAction(playback)
player:gebLib_StopAction()
```

The server synchronizes these operations through one feature-owned network message.

## Cinematic cameras

```lua
local camera = gebLib.Camera.New("intro", player, 60, 180)

camera:AddEvent(0, 180, function(viewer, position, angles)
    return position + Vector(0, 0, 40), angles
end)

camera:SetEnd(function()
    print("camera finished")
end)

camera:Play()
```

## Other helpers

```lua
player:gebLib_ChatAddText(Color(255, 200, 80), "Message")

local debris = gebLib.Visuals.CreateDebris("models/props_junk/wood_crate001a.mdl", true, 5)
local decal = gebLib.Visuals.CreateDecal("decals/scorch1", position, angles, 32, 3)

gebLib.Drawing.Circle(x, y, radius, color, progress)
gebLib.Drawing.CircularBar(x, y, progress, radius, thickness, angle, color)
gebLib.Drawing.TextWithShadow(text, font, x, y, color)

local duration = gebLib.SoundDuration("sound/example.mp3")
```

Entity helpers remain available for living-entity checks, looking direction, nearby collision checks, empty-position searches, bone hitboxes, and dissolving.

The focused helper methods are:

- `weapon:gebLib_IsCarried()`
- `player:gebLib_ValidAndAlive()`
- `entity:gebLib_IsPerson()`, `gebLib_IsProp()`, `gebLib_IsItem()`, and `gebLib_Alive()`
- `entity:gebLib_IsLookingAt(position, minimumDot)` and `gebLib_CheckSides(distance, filter)`
- `entity:gebLib_PositionEmpty(position, filter)` and `gebLib_FindEmptyPosition(position, distance, step, filter)`
- `entity:gebLib_GetBoneHitBox(bone)` and `gebLib_Dissolve(delay)`

## Connection hook

```lua
hook.Add("gebLib.PlayerFullyConnected", "MyAddon.InitializePlayer", function(player)
    -- Networking is safe here.
end)
```

## Breaking changes from v1

- `gebLib.Action.Create` is now `gebLib.Action.New`.
- `gebLib_animation` is now `gebLib.Animation`.
- `gebLib_Camera` is now `gebLib.Camera`.
- `gebLib_SoundDuration` is now `gebLib.SoundDuration`.
- `gebLib_statuseffects.New` and `entity:gebLib_AddStatusEffect` are replaced by `gebLib.StatusEffects.Register` and `entity:gebLib_ApplyStatusEffect`.
- `gebLib_StopAnim`, `gebLib_PauseAnim`, and `gebLib_ResumeAnim` are now the corresponding `Sequence` methods.
- `gebLib_PlayerFullyConnected` is now `gebLib.PlayerFullyConnected`.
- Status effects use registered definitions instead of copied class-like tables.
- Generic entity-field networking, Power Level, global entity/player caches, global blacklists, unfinished Derma controls, and unrelated utility helpers were removed.
- Debris and decals moved to `gebLib.Visuals`.
- Drawing helpers moved to `gebLib.Drawing`.

## Validation

Run the focused tests from the addon root:

```powershell
lua tests/bootstrap_test.lua
lua tests/status_effects_test.lua
lua tests/action_test.lua
```

All shipped Lua files use Lua 5.1-compatible syntax. They are checked with LuaJIT and `luac -p`.
