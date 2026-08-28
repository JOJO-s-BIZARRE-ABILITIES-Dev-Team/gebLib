# API reference

This reference covers the supported public surface of gebLib 3.3.0. Names beginning with `_` are internal and are intentionally omitted.

## Core

### Values

| Value | Realm | Meaning |
| --- | --- | --- |
| `gebLib.Version` | Shared | Current version string. |
| `gebLib.Loaded` | Shared | `true` after every module for the current realm has loaded. |

### Functions

| Function | Realm | Returns | Meaning |
| --- | --- | --- | --- |
| `gebLib.DebugMode()` | Shared | Boolean | Reads `geblib_developer_debugmode`. |
| `gebLib.PrintDebug(...)` | Shared | Nothing | Prints with a `[gebLib]` prefix only while debug mode is enabled. |
| `gebLib.SoundDuration(path)` | Shared | Seconds | Reads and caches MP3 or WAV duration, falling back to `SoundDuration`. `path` is relative to the game filesystem. |
| `gebLib.SoundDurationAsync(path, callback)` | Shared | Boolean | Queues an exact duration lookup and calls `callback(duration)`. Cached callbacks run immediately. Client decoding has two channels in flight; server and fallback parsing is limited to 0.5 milliseconds per tick. |

### Hooks and console controls

| Name | Realm | Contract |
| --- | --- | --- |
| `gebLib.Loaded(lib)` | Shared | Runs after realm initialization. Do not return a value. |
| `gebLib.PlayerFullyConnected(player)` | Shared | Runs after the player has completed the full-update handshake on the server and after `InitPostEntity` on that client. |
| `geblib_developer_debugmode 0|1` | Shared | Archived, replicated developer logging switch. |

## Networking

Define each message in shared code with the same name, schema, and options on both realms.

### Message definitions

```lua
local message = gebLib.Net.ToClient(name, schema, options)
local message = gebLib.Net.ToServer(name, schema, options)
```

`schema` is a sequential array of codecs. Message names must be 1 to 64 lowercase characters, contain a `.`, start with a letter or digit, and use only letters, digits, `%`, `.`, and `_`. A name cannot end with `.`, contain `..`, or be redefined with a different contract.

Options:

| Option | Direction | Default | Meaning |
| --- | --- | --- | --- |
| `unreliable` | Both | `false` | Uses an unreliable Source net message. Lost packets must be acceptable. |
| `rate` | To server | Required | Accepted records per second per player, or `false` for an explicit unlimited message. |
| `burst` | To server | `rate` | Initial and maximum token count. Must be at least 1. |
| `batch` | To client | Disabled | Maximum records per packet, from 2 to 256. Enables `Queue` methods. |

The total possible payload must remain within 60 KiB. Registered codecs and compiled schemas are immutable.

### Message methods

| Method | Realm | Meaning |
| --- | --- | --- |
| `message:Send(recipients, ...)` | Server, to-client message | Sends immediately to one player, a player array, or a recipient filter. |
| `message:Send(...)` | Client, to-server message | Sends immediately to the server. |
| `message:Broadcast(...)` | Server, to-client message | Sends immediately to every player. |
| `message:Queue(recipients, ...)` | Server, batched to-client message | Queues one record for a recipient group. |
| `message:QueueBroadcast(...)` | Server, batched to-client message | Queues one record for every player. |
| `message:Receive(callback)` | Receiving realm | Installs the receiver. A to-server callback receives `player` first. |
| `gebLib.Net.FlushBatches()` | Server | Flushes all pending groups and returns the number of packets sent. Normally called by the library each tick. |

Immediate sends flush older queued records for that message first. A batch receiver is called once per record in original order.

### Codecs

| Codec | Accepted value | Wire contract |
| --- | --- | --- |
| `gebLib.Net.Bool` | Boolean | 1 bit. |
| `gebLib.Net.UInt(bits)` | Integer from 0 through `2^bits - 1` | `bits` is 1 through 32. |
| `gebLib.Net.Int(bits)` | Signed integer in the selected width | `bits` is 3 through 32. |
| `gebLib.Net.Range(min, max)` | Integer within inclusive bounds | Uses the smallest unsigned width for the offset. |
| `gebLib.Net.Float` | Finite number | 32-bit float. |
| `gebLib.Net.Double` | Finite number | 64-bit double. |
| `gebLib.Net.String(maxBytes)` | String within the byte limit | Limit is 1 through 65535 bytes. |
| `gebLib.Net.Entity` | Valid entity | Uses the engine entity codec. |
| `gebLib.Net.Player` | Valid player | Uses the narrower player codec. |
| `gebLib.Net.Vector` | Vector | General vector encoding. |
| `gebLib.Net.Normal` | Unit vector within 0.001 length tolerance | Compact normal encoding. |
| `gebLib.Net.Angle` | Angle | Engine angle encoding. |
| `gebLib.Net.Color` | Color | RGBA. |
| `gebLib.Net.Optional(codec)` | `nil` or an accepted inner value | Presence bit followed by the inner value. |
| `gebLib.Net.Array(codec, maxCount)` | Sequential array | Count plus repeated values. Optional elements are rejected. |
| `gebLib.Net.OneOf({codecs})` | First matching codec | Choice tag plus value. Accepts 2 through 256 choices. Put narrower overlapping codecs first. |

### Network profiler

The profiler is server-side and disabled by default.

| Command | Meaning |
| --- | --- |
| `geblib_net_profile 0|1` | Disable or enable observations. |
| `geblib_net_profile_report` | Print packet rates, sizes, fan-out, repeats, drops, and field advice. |
| `geblib_net_profile_reset` | Clear observations. |

Advice is based only on observed values. It does not prove future domain bounds.

## Status effects

### Definitions

```lua
gebLib.StatusEffects.Register(name, {
    interval = 1,
    onApply = function(target, effect) end,
    onTick = function(target, effect) end,
    onReapply = function(target, effect, duration, level, source, inflictor) end,
    onRemove = function(target, effect, reason) end,
})
```

`Register` copies the definition and returns an immutable view. `interval` defaults to 1 and may be 0. `onReapply` may return `true` to take complete ownership of the reapplication.

Without a handled `onReapply`, a stronger level replaces the effect, the same level keeps the later expiration, and a weaker level is ignored.

### Registry functions

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.StatusEffects.Register(name, definition)` | Definition view | Registers or replaces a definition. |
| `gebLib.StatusEffects.Get(name)` | Definition view or `nil` | Looks up a definition. |
| `gebLib.StatusEffects.Unregister(name)` | Nothing | Prevents future application. Existing applied effects keep their owned definition. |

### Entity methods

| Method | Returns | Meaning |
| --- | --- | --- |
| `entity:gebLib_ApplyStatusEffect(name, duration, level, source, inflictor)` | Applied effect or `nil` | Applies to a player, NPC, or NextBot. `duration` defaults to 0, `level` to 1, and `math.huge` never expires by time. |
| `entity:gebLib_RemoveStatusEffect(name, reason)` | Boolean | Removes one effect. |
| `entity:gebLib_GetStatusEffect(name)` | Applied effect or `nil` | Gets the live effect record. |
| `entity:gebLib_GetStatusEffects()` | Table | Returns a snapshot of the name map. Effect records inside it remain live. |
| `entity:gebLib_HasStatusEffect(name)` | Boolean | Tests for an applied effect. |
| `entity:gebLib_ClearStatusEffects(reason)` | Count | Removes every effect on the entity. |

An applied record contains `name`, `target`, `source`, `inflictor`, `level`, `appliedAt`, `expiresAt`, and `nextTickAt`. Callbacks may attach their own state to that record. Effects are removed on expiration, death, entity removal, replacement, explicit removal, or callback failure. Status effects are not networked automatically.

## Player animation

These shared player methods apply locally and broadcast server calls to clients. Gesture slots are integers from 0 through 7. Sequences may be numeric IDs or names.

| Method | Returns | Meaning |
| --- | --- | --- |
| `player:gebLib_PlaySequence(slot, sequence, cycle, autokill, playback)` | Boolean | Starts a gesture layer. Defaults: cycle 0, autokill `true`, playback 1. |
| `player:gebLib_StopSequence(slot)` | Boolean | Resets the layer. |
| `player:gebLib_PauseSequence(slot)` | Boolean | Sets playback to 0. |
| `player:gebLib_ResumeSequence(slot, playback)` | Boolean | Resumes, default playback 1. |
| `player:gebLib_PlayAction(sequence, playback)` | Boolean | Plays on action slot 1. |
| `player:gebLib_StopAction()` | Boolean | Stops slot 1. |
| `player:gebLib_PauseAction()` | Boolean | Pauses slot 1. |
| `player:gebLib_ResumeAction(playback)` | Boolean | Resumes slot 1. |

## Entity helpers

| Method | Realm | Returns | Meaning |
| --- | --- | --- | --- |
| `weapon:gebLib_IsCarried()` | Shared | Boolean | Tests for a valid owner. Compatibility helper. |
| `player:gebLib_ValidAndAlive()` | Shared | Boolean | Valid player and alive. Compatibility helper. |
| `entity:gebLib_IsPerson()` | Shared | Boolean | Player, NPC, or NextBot. |
| `entity:gebLib_IsProp()` | Shared | Boolean | Known physics, dynamic, clipped, multiplayer, or ragdoll prop class. |
| `entity:gebLib_IsItem()` | Shared | Boolean | Class begins with `item_`. |
| `entity:gebLib_Alive()` | Shared | Boolean | Valid living entity with health. |
| `entity:gebLib_IsLookingAt(position, minimumDot)` | Shared | Boolean | Dot-product facing test. Default minimum dot is 0.9. |
| `entity:gebLib_CheckSides(distance, filter)` | Shared | Trace or `false` | Checks down, up, right, left, forward, then back with `MASK_SOLID`. |
| `entity:gebLib_PositionEmpty(position, filter)` | Shared | Boolean | Tests the entity OBB at a position with `MASK_PLAYERSOLID`. |
| `entity:gebLib_FindEmptyPosition(position, distance, step, filter)` | Shared | Vector or `nil` | Searches six axes. Defaults: distance 128, step 16. |
| `entity:gebLib_GetBoneHitBox(bone)` | Shared | Mins and maxs, or `nil` | Accepts a bone index or name and searches all hitbox sets. |
| `entity:gebLib_Dissolve(delay)` | Server | Dissolver or `nil` | Creates an `env_entity_dissolver`. Delay defaults to 0. |

## Math helpers

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.Math.SmoothStep(value)` | Number | Clamped cubic smoothstep from 0 to 1. |
| `gebLib.Math.Horizontal(vector, output)` | Vector | Copies X and Y and sets Z to 0. Reuses `output` when supplied. |
| `gebLib.Math.SafeDirection(vector, fallback, output)` | Vector | Returns a normalized non-zero direction. Defaults to `vector_up`. |
| `gebLib.Math.DistanceFalloff(distance, radius, exponent)` | Number | Clamped `1 - distance / radius`, optionally raised to `exponent`. |

## Combat

All combat helpers are shared, but damage and physics policy normally belongs on the server.

### Contacts and traces

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.Combat.ContactFromTrace(trace, origin, direction)` | Contact or `nil` | Normalizes a non-sky hit. |
| `gebLib.Combat.TraceWater(origin, endPosition, direction, filter, mask)` | Contact or `nil` | Traces water and normalizes it as `MAT_SLOSH`. |
| `gebLib.Combat.TraceAttack(options)` | Chosen contact, solid contact, water contact, end position, raw trace | Performs a line or hull attack and optionally selects nearer water. |

`TraceAttack` options:

| Option | Default | Meaning |
| --- | --- | --- |
| `origin` | Required | Trace start. |
| `direction` | Required | Normalized safely. |
| `distance` | 0 | Non-negative length. |
| `attacker` | None | Default trace filter and contact exclusion. |
| `traceFilter` | `attacker` | Engine trace filter. |
| `mask` | `MASK_SHOT_HULL` | Main trace mask. |
| `mins`, `maxs` | None | Both enable `TraceHull`. |
| `refineRadius` | Disabled | Retraces across the hit normal to refine the same surface. |
| `refineMask` | `MASK_SHOT` | Refinement mask. |
| `water` | `false` | Also trace water. |
| `waterMask` | `MASK_WATER` | Water trace mask. |

A contact includes `Hit`, `HitSky`, `HitWorld`, `HitPos`, `HitNormal`, `Entity`, `MatType`, `SurfaceProps`, `SurfaceFlags`, `HitNoDraw`, `Direction`, `Distance`, `DistanceSqr`, and `Fraction`. Water contacts also include `IsWater`.

### Target collection

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.Combat.CollectCone(options)` | Contact array | Finds targets in a cone, optionally checking visibility. |
| `gebLib.Combat.ClosestToRay(contacts)` | Contact or `nil` | Chooses lowest lateral distance, then nearest forward distance. |
| `gebLib.Combat.CollectSphere(options)` | Result array | Finds targets in a sphere with falloff and optional visibility or forward-half filtering. |

Shared target options are `attacker`, `inflictor`, `filter(entity)`, `requireSolid` defaulting to `true`, `alivePlayers` defaulting to `true`, `traceFilter`, and `visibilityMask` defaulting to `MASK_SHOT`.

Cone options add `origin`, `direction`, `distance`, `dot`, `minimumForward`, `maximumForward`, and `visible` defaulting to `true`. Sphere options add `origin`, `radius`, `exponent`, `visible` defaulting to `false`, `visibilityOrigin`, `forward`, and `forwardOrigin`.

### Damage and force

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.Combat.DirectionalRadialForce(entity, origin, direction, amount, radius, minScale, maxScale)` | Vector | Blends 75 percent attack direction with 25 percent radial direction and applies distance falloff. |
| `gebLib.Combat.ApplyDamage(entity, options)` | `DamageInfo` or `nil` | Creates and applies engine damage. |
| `gebLib.Combat.ApplyKnockback(entity, force, options)` | Boolean | Uses entity velocity for living targets and physics force or velocity for props. |
| `gebLib.Combat.ApplyHit(entity, options)` | `DamageInfo` or `nil` | Applies damage, then optional knockback. |
| `gebLib.Combat.ApplyRadialImpact(options)` | Result array | Collects a sphere, scales damage and force, and applies them. |

`ApplyDamage` accepts `damage`, `attacker`, `inflictor`, `damageType`, `position`, `force`, and `suppressHostEvents`. `ApplyKnockback` accepts `playerLift`, `living`, `physicsForLiving`, `removeConstraints`, `restoreGravity`, `enableGravity`, and `physicsMode = "velocity"`. The removal and gravity options may be booleans or callbacks.

`ApplyRadialImpact` uses sphere collection options plus `damage`, `force`, `lift`, `damageType`, `canDamage(entity)`, `knockbackOptions`, `playerKnockbackOptions`, `playerVelocityDivisor`, and `playerVelocityCap`.

## Chat

`player:gebLib_ChatAddText(...)` is shared. On the server it sends to that player. On the client it calls `chat.AddText` directly. It accepts up to 32 strings or colors; strings are limited to 1024 bytes and pass through `language.GetPhrase`.

## Cinematic cameras

`gebLib.Camera` is shared. A server camera can run its think timeline, but view events and default presentation are client-only. Camera state is not automatically networked.

```lua
local camera = gebLib.Camera.New(name, player, fps, maxFrames, createFake, useDefaultHooks)
```

Defaults are 60 FPS, `createFake = true`, and `useDefaultHooks = true`. A negative `maxFrames` is treated as absent. If no maximum is supplied, the latest event end frame is used when playback begins.

| Method | Returns | Meaning |
| --- | --- | --- |
| `camera:RunCallback(callback, ...)` | Success plus callback returns | Runs a camera-owned callback through gebLib's error boundary. A failure stops the camera. Most addons can call their function directly and let camera events use this internally. |
| `camera:RunThink()` | Success plus callback returns | Runs the registered think callback while playing. Normally called by the camera lifecycle. |
| `camera:AddEvent(startFrame, endFrame, callback)` | Nothing | Adds or replaces an event at `startFrame`. Callback receives player, current position, angles, and FOV and may return replacements. |
| `camera:SetThink(callback)` | Nothing | Sets a per-frame callback receiving the camera. |
| `camera:SetEnd(callback)` | Nothing | Sets the cleanup callback receiving the camera. |
| `camera:Play(simulate)` | Boolean | Starts playback. Client non-simulated playback contributes a high-priority camera modifier. |
| `camera:Stop()` | Boolean | Stops, unregisters, restores `NoDraw`, removes the replica, and runs the end callback. |
| `camera:AddFakePlayerCopy()` | Boolean | Creates the clientside player replica immediately. |
| `camera:AddDefaultHooks()` | Nothing | Installs letterbox and HUD suppression when enabled. |
| `camera:RemoveDefaultHooks()` | Nothing | Removes presentation and camera modifier hooks. |
| `camera:GetTime(startFrame, endFrame, multiplier)` | Number | Remaps the current frame to a clamped 0 through 1 value. |
| `camera:FrameFirstTime(frame)` | Boolean | Returns `true` once when playback first reaches a frame. |
| `camera:IsValid()` | Boolean | Owner exists and is alive. |

`tostring(camera)` returns the camera name followed by its player identity.

## Client camera composition

### Camera modifiers

```lua
gebLib.CameraModifiers.Register(name, priority, function(player, view)
    view.origin = view.origin + Vector(0, 0, 4)
    return true
end)
```

Modifiers run from lower to higher numeric priority. Equal priorities sort by name. `view` contains `origin`, `angles`, `fov`, and `drawviewer`. Return exactly `true` when a view should be returned from `CalcView`.

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.CameraModifiers.Register(name, priority, apply)` | Nothing | Adds or replaces a modifier. |
| `gebLib.CameraModifiers.Remove(name)` | Boolean | Removes one modifier. |
| `gebLib.CameraModifiers.Clear()` | Nothing | Removes every modifier and the shared hook. |

### Camera impulses

```lua
local channel = gebLib.CameraImpulses.Create(name, priority, adapter)
```

The adapter receives `(player, view, channel)` and returns the same handled flag as a camera modifier.

| Method | Returns | Meaning |
| --- | --- | --- |
| `channel:Push(values, decayRates, combine, now)` | Nothing | Adds numeric values. `combine` is `"add"` or `"max"`; default decay is 6. |
| `channel:PushAt(position, radius, values, decayRates, viewer, combine, now)` | Boolean | Pushes values scaled by viewer distance. Defaults to `LocalPlayer()`. |
| `channel:Sustain(values, decayRates, now)` | Nothing | Refreshes keyed values that decay when no longer refreshed. |
| `channel:Sample(now)` | Table | Updates and returns the reused current-value table. |
| `channel:Get(key)` | Number | Gets a sampled value or 0. |
| `channel:Clear()` | Nothing | Clears transient and sustained values. |

`gebLib.CameraImpulses.Remove(name)` returns whether a channel existed. `gebLib.CameraImpulses.Clear()` removes all channels.

## Client bone composition

### Bone controllers

`gebLib.BoneControllers.Register(name, definition)` registers additive Euler rotation for one named player bone.

Definition fields:

| Field | Default | Meaning |
| --- | --- | --- |
| `Bone` | Required | Bone name. |
| `GetTarget(player)` | Required | Returns an Angle or pitch, yaw, roll numbers. |
| `IsActive(player)` | Always active | Controls whether the target is applied. |
| `Speed` | 180 | Number for all axes or Angle for per-axis approach speed. |
| `GetFrameTime(player)` | `FrameTime()` | Custom delta, clamped from 0 through 0.05. |
| `ResetImmediately` | `false` | Removes the contribution immediately when inactive. |

Functions are `Remove(name)`, `Clear(player)`, `Suspend(player)`, `Resume(player)`, `IsSuspended(player)`, and `CopyControlledTransforms(source, target)`. `Remove` returns a boolean. `Clear` restores gebLib-owned angle contributions.

### Bone matrix modifiers

```lua
gebLib.BoneMatrixModifiers.Register(name, {
    Priority = 100,
    Channel = "combat_pose",
    IsActive = function(entity) return true end,
    Apply = function(entity) end,
})
```

Modifiers run from lower to higher priority. In a named channel, only the highest active modifier runs. Equal priorities sort by name, making the later name the channel winner.

| Function | Returns | Meaning |
| --- | --- | --- |
| `Register(name, definition)` | Nothing | Adds or replaces a modifier. `Apply` is required. |
| `Remove(name)` | Boolean | Removes one definition. |
| `Track(entity, owner)` | Boolean | Adds an owner and installs one entity callback. |
| `Untrack(entity, owner)` | Boolean | Removes one owner; detaches after the final owner. |
| `ClearEntity(entity)` | Boolean | Detaches regardless of owners. |
| `Clear()` | Nothing | Detaches all entities and removes all definitions. |

## Player replicas and trails

### Player replicas

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.PlayerReplica.Create(source, renderGroup, shadows)` | Clientside model or `NULL` | Creates a hidden, paused replica and syncs appearance. |
| `SyncAppearance(replica, source)` | Boolean | Copies model, skin, color, scale, and bodygroups. |
| `SyncPose(replica, source)` | Boolean | Copies sequence, cycle, pose parameters, and controlled transforms. |
| `CaptureBoneMatrices(source, matrices)` | Matrix table, bone count | Reuses the optional table and captures valid named bones. |
| `ApplyBoneMatrices(replica, matrices, boneCount)` | Boolean | Applies a frozen capture. |

The caller owns the replica and must draw and remove it.

### Replica trails

```lua
local trail = gebLib.ReplicaTrail.New(source, options)
```

Options are `mode` (`"sequence"` or `"matrices"`), `interval` default 0.05, `lifetime` default 0.4, `limit` default 12, `renderGroup`, `shadows`, `appearanceInterval` default 0.25, and `appearance(replica, source)`.

| Method | Returns | Meaning |
| --- | --- | --- |
| `trail:SyncAppearance(now, force)` | Boolean | Refreshes the shared sequence replica on its cadence. |
| `trail:IsValid()` | Boolean | Checks source and shared replica. |
| `trail:GetCount(now)` | Number | Optionally expires first, then counts active snapshots. |
| `trail:Capture(now, position, angles)` | Snapshot or `nil` | Captures if the cadence permits. `now` is required. |
| `trail:Expire(now)` | Nothing | Deactivates old snapshots. |
| `trail:Refresh(now)` | Nothing | Resets active snapshot ages. |
| `trail:ClearSnapshots()` | Nothing | Deactivates all snapshots without destroying the pool. |
| `trail:GetSnapshots(now, output)` | Sorted array | Returns oldest to newest, reusing `output` when supplied. |
| `trail:ForEach(now, callback)` | Nothing | Callback receives snapshot, age progress, index, and count. |
| `trail:DrawSnapshot(snapshot, position, angles, callback)` | Boolean | Draws one pose. Callback receives replica and snapshot. |
| `trail:Draw(now, callback)` | Nothing | Draws all. Callback receives replica, progress, index, count, and snapshot. |
| `trail:Remove()` | Nothing | Removes replicas and releases the source. |

## Client audio sessions

```lua
local session = gebLib.Audio.New()
```

| Method | Returns | Meaning |
| --- | --- | --- |
| `session:PlayPatch(owner, path, options)` | Boolean | Plays a `CSoundPatch`. Options: `volume` default 1 and `pitch` default 100. |
| `session:PlayFile(path, flags, options)` | Boolean | Requests a file channel. Defaults flags to `"noplay noblock"`. |
| `session:IsPlaying()` | Boolean | Includes an asynchronous request in progress. |
| `session:Stop(fadeTime)` | Boolean | Cancels stale requests and stops or fades the active handle. |
| `session:Restart()` | Boolean | Restarts the current handle. |
| `session:ScheduleRestart(interval, now)` | Nothing | Schedules repeated restarts. |
| `session:Update(now)` | Boolean | Performs a due restart. Call from an owning hook. |
| `session:SetVolume(volume, duration)` | Boolean | Fades patches; file channels set immediately. |
| `session:SetPitch(pitch, duration)` | Boolean | Fades patches or sets file playback rate. |
| `session:Remove()` | Nothing | Stops and unregisters the session. |

`PlayFile` options are `retryDelay` default 1, `volume`, `pitch`, `looping`, `play` default `true`, `onReady(channel)`, and `onFailure()`. `gebLib.Audio.StopAll()` stops every registered session and also runs during shutdown.

## Client drawing

| Function | Meaning |
| --- | --- |
| `gebLib.Drawing.Circle(x, y, radius, color, progress, angle, segments)` | Draws a filled circle or percentage wedge. Defaults: progress 100, angle 180, segments 100. `x` and `y` are the top-left of its bounding square. |
| `gebLib.Drawing.CircularBar(x, y, progress, radius, thickness, angle, color)` | Uses stencil drawing to create a ring. `x` and `y` are its center. |
| `gebLib.Drawing.TextWithShadow(text, font, x, y, color, horizontalAlign, verticalAlign, shadowColor)` | Draws a 1.5-pixel shadow, then text, and returns `draw.SimpleText` results. |

## Client visual batches

`gebLib.Visuals.BeamBatch.New(material)` creates a reusable beam buffer.

| Method | Meaning |
| --- | --- |
| `batch:AddUnpacked(x, y, z, width, textureCoordinate, color)` | Adds one copied beam point and returns the batch. |
| `batch:Add(position, width, textureCoordinate, color)` | Vector form of `AddUnpacked`. |
| `batch:BreakUnpacked(x, y, z)` | Inserts zero-width transparent points so the next path is disconnected. |
| `batch:Break(position)` | Vector form of `BreakUnpacked`. |
| `batch:AddSegment(startPosition, endPosition, width, color)` | Adds one disconnected segment with texture coordinates 0 and 1. |
| `batch:Reset()` | Clears the active count and returns the batch. |
| `batch:Flush(material)` | Draws with the optional material override, resets, and returns whether at least two points were present. |

`gebLib.Visuals.SpriteBatch.New(material)` creates a reusable sprite buffer.

| Method | Meaning |
| --- | --- |
| `batch:AddUnpacked(x, y, z, width, height, color)` | Adds one copied sprite and returns the batch. Height defaults to width. |
| `batch:Add(position, width, height, color)` | Vector form of `AddUnpacked`. |
| `batch:Reset()` | Clears the active count and returns the batch. |
| `batch:Flush(material)` | Draws with the optional material override, resets, and returns whether anything was present. |

Call batch methods only inside appropriate render hooks. The batch owns copied positions and colors, so the caller may reuse input objects after adding them.

## Visuals, surfaces, and impact frames

The visual API is large enough to keep its option tables separate:

- [Visuals and debris](visuals.md)
- [Impact frames](impact-frames.md)

Those pages include every public constructor, runtime control, profiler control, surface helper, and lifecycle method.
