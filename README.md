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

## Networking

Define each message once in a shared file. The schema is the packet order used by both realms.

```lua
local Hit = gebLib.Net.ToClient("myaddon.hit", {
    gebLib.Net.Entity,
    gebLib.Net.UInt(12),
    gebLib.Net.Bool,
})
```

Send it from the server:

```lua
Hit:Send(player, target, damage, critical)
Hit:Broadcast(target, damage, critical)
```

Receive it on the client:

```lua
Hit:Receive(function(target, damage, critical)
    -- Handle the message.
end)
```

Client-to-server messages require an explicit per-player rate limit:

```lua
local SelectAbility = gebLib.Net.ToServer("myaddon.select_ability", {
    gebLib.Net.UInt(6),
}, {
    rate = 8,
    burst = 4,
})

if CLIENT then
    SelectAbility:Send(abilityId)
else
    SelectAbility:Receive(function(player, abilityId)
        -- Validate permissions and gameplay state here.
    end)
end
```

Use `rate = false` to make a deliberate exception. Structural decoding does not replace server-side permission or gameplay validation.

The available codecs are:

```lua
gebLib.Net.Bool
gebLib.Net.UInt(bits)
gebLib.Net.Int(bits)
gebLib.Net.Range(minimum, maximum)
gebLib.Net.Float
gebLib.Net.Double
gebLib.Net.String(maxBytes)
gebLib.Net.Entity
gebLib.Net.Player
gebLib.Net.Vector
gebLib.Net.Normal
gebLib.Net.Angle
gebLib.Net.Color
gebLib.Net.Optional(codec)
gebLib.Net.Array(codec, maxCount)
gebLib.Net.OneOf({codecA, codecB})
```

`Range` offsets a bounded integer range and derives the smallest unsigned width. `OneOf` writes a compact choice tag and uses the first codec that accepts the value, so put narrower overlapping codecs first.

Messages use their own native pooled names and contain no route strings, field names, or automatic type tags. Names must be lowercase, namespaced, and at most 64 characters. Change the name, such as from `myaddon.hit` to `myaddon.hit.v2`, when changing a released wire schema.

Use `unreliable = true` only when losing a packet is acceptable. Persistent entity state still belongs in `NetworkVar`, NW2 where appropriate, or a feature-owned snapshot protocol.

High-frequency server messages can opt into batching:

```lua
local Positions = gebLib.Net.ToClient("myaddon.positions", {
    gebLib.Net.Entity,
    gebLib.Net.Vector,
}, {
    unreliable = true,
    batch = 32,
})

Positions:Queue(player, entity, position)
Positions:QueueBroadcast(entity, position)
```

Queued records are grouped by message and recipient, then flushed once per server tick. Reaching the configured batch limit flushes that group immediately. The receiver callback still runs once per record in order. `Send` and `Broadcast` remain immediate and flush older queued records first.

Batching adds up to one tick of latency and a small count field. Use it only for bursts of small records. The maximum batch size is part of the wire contract, so both realms must define the same value.

### Network profiler

Enable profiling in a development session:

```text
geblib_net_profile 1
```

Print or reset the report:

```text
geblib_net_profile_report
geblib_net_profile_reset
```

The server records packet and record rates, encoded bits, recipient fan-out, repeated payloads, malformed packets, rate-limit drops, and observed field ranges. It can identify high-rate small packets that may benefit from batching and repeated unchanged state that should not be sent. After at least 256 field samples and 30 seconds, it can also suggest smaller integer widths, bounded strings or arrays, `Normal` instead of `Vector`, `Player` instead of `Entity`, or an integer codec instead of `Float`.

Profiler advice is based on observed traffic, not a proof of the domain limits. Confirm rare and future values before changing a released schema. Profiling is disabled by default, does not replace the global `net` functions, and never modifies a schema automatically.

### In-game network self-test

Enable development mode before entering a single-player or listen-server game:

```text
geblib_developer_debugmode 1
```

The network self-test starts automatically after the local player is fully connected. It round-trips every codec, both directions, targeted sends, broadcasts, automatic and explicit batch flushing, malformed-packet rejection, and per-player rate limiting. The client and server consoles print one `PASS` or `FAIL` result.

Run it again without reconnecting:

```text
geblib_net_selftest
```

The test does nothing while development mode is disabled. Only the single-player client or listen-server host can start it.

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

The server synchronizes these operations through four typed messages for play, pause, resume, and stop.

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
local emitted = gebLib.Visuals.CreateDebrisBurst("effects/fleck_cement1", position, 1200, {
    lifetime = 4,
    size = 3,
    speed = 350,
    collide = false,
})
local decal = gebLib.Visuals.CreateDecal("decals/scorch1", position, angles, 32, 3)

gebLib.Drawing.Circle(x, y, radius, color, progress)
gebLib.Drawing.CircularBar(x, y, progress, radius, thickness, angle, color)
gebLib.Drawing.TextWithShadow(text, font, x, y, color)

local duration = gebLib.SoundDuration("sound/example.mp3")
```

Debris is client-only and capped at 512 active entities by default. Creating another removes the debris that would expire next. Change `gebLib.Visuals.MaxDebris` before creating debris when a feature needs a different budget.

`CreateDebris` uses one shared event scheduler instead of a per-frame scan. Full-opacity debris stays on the engine draw path, then enters Lua only for its final one-second fade. Render-only `ClientsideModel` debris grows through engine interpolation. Physical client props skip animated scaling to avoid client trace errors.

Use `CreateDebrisBurst` for hundreds or thousands of cosmetic fragments. It creates one engine particle emitter instead of one entity per fragment and returns the number emitted. It accepts a material rather than a model. World collision is enabled by default; pass `collide = false` for the highest throughput. Optional settings are `lifetime`, `size`, `endSize`, `speed`, `spin`, `velocity`, `gravity`, `bounce`, `color`, `collide`, and `lighting`.

```lua
print(gebLib.Visuals.GetDebrisCount())
gebLib.Visuals.RemoveDebris(debris)
gebLib.Visuals.ClearDebris()
```

`gebLib_ChatAddText` accepts up to 32 string or color arguments. Each string is limited to 1024 bytes.

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
- Generic entity-field networking was replaced by typed `gebLib.Net` messages. Power Level, global entity/player caches, global blacklists, unfinished Derma controls, and unrelated utility helpers were removed.
- Debris and decals moved to `gebLib.Visuals`.
- Drawing helpers moved to `gebLib.Drawing`.

## Validation

Run the focused tests from the addon root:

```powershell
lua tests/bootstrap_test.lua
lua tests/net_test.lua
lua tests/network_features_test.lua
lua tests/status_effects_test.lua
lua tests/action_test.lua
lua tests/visuals_test.lua
```

All shipped Lua files use Lua 5.1-compatible syntax. They are checked with LuaJIT and `luac -p`.

Run the optional local CPU benchmark with `lua tests/net_benchmark.lua` or `luajit tests/net_benchmark.lua`. It compares schema sends against equivalent direct `net` calls in a Lua mock. It is useful for tracking wrapper overhead, but only an in-game benchmark can measure Source networking and real addon traffic.

Run `lua tests/visuals_benchmark.lua` or `luajit tests/visuals_benchmark.lua` to measure model-debris creation, idle overhead, full-opacity Lua render callbacks, fade scheduling, expiry, and particle-burst setup. It does not measure engine rendering, particle simulation, or physics cost.
