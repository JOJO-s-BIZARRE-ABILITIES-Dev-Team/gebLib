# Visuals and debris

Except for `gebLib.Surface`, this page describes client-only APIs. Visual creation is local to the client that calls it. Network the gameplay event, not generated particles or debris entities.

## Choosing an effect

| Need | Use |
| --- | --- |
| One temporary model or client prop | `CreateDebris` |
| Hundreds of cheap fragments | `CreateDebrisBurst` |
| Expanding ring and distortion | `CreateShockwave` |
| Surface-aware mixed impact | `CreateImpactDebris` |
| Static crater chunks only | `CreateSurfaceCrater` |
| Spray, droplets, mist, splashes, and ripples | `CreateWaterDebris` |
| Ordered ground eruption | `CreateDebrisWave` |
| Projected texture on world or entity geometry | `ProjectDecal` or `ProjectAnimatedDecal` |
| Small oriented clientside decal entity | `CreateDecal` |

## Debris lifecycle

### Configuration

| Value | Default | Meaning |
| --- | --- | --- |
| `gebLib.Visuals.MaxDebris` | 512 | Maximum active entity debris. Set before creation. Static batch pieces are tracked separately. |
| `gebLib.Visuals.RetireSettledPhysics` | `true` | Whether sleeping physical debris may retire its physics and enter static batches. Prefer `SetDebrisPhysicsRetirement`. |
| `gebLib.Visuals.StaticBatchingDefault` | `true` | Initial static batching state. Prefer `SetDebrisStaticBatching` at runtime. |
| `gebLib.Visuals.RockDebrisModels` | Bundled model array | Compatibility view of the rock model family. |

### `CreateDebris`

```lua
local entity = gebLib.Visuals.CreateDebris(
    modelPath,
    clientProp,
    lifetime,
    ignoreLimit,
    material,
    animateGrowth
)
```

Returns a clientside entity or `NULL`.

| Argument | Default | Meaning |
| --- | --- | --- |
| `modelPath` | Required | Model passed to the engine factory. |
| `clientProp` | `false` | `true` uses `ents.CreateClientProp`; otherwise `ClientsideModel`. |
| `lifetime` | 10 | Non-negative seconds. The final second uses native fade. |
| `ignoreLimit` | `false` | Allows this item to exceed `MaxDebris`. Use only for a bounded effect that owns its count. |
| `material` | None | Optional material override string. |
| `animateGrowth` | `true` for models | Render-only models interpolate from scale 0 for 0.25 seconds. Physical props do not. |

When at the limit, normal creation removes the tracked entity that would expire next.

### Runtime functions

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.Visuals.RemoveDebris(entity)` | Nothing | Untracks and removes one debris entity. |
| `gebLib.Visuals.GetDebrisCount()` | Number | Counts active entities, active static pieces, and queued static pieces. |
| `gebLib.Visuals.ClearDebris()` | Nothing | Removes all entity debris and static batches. |
| `gebLib.Visuals.RefreshDebrisPhysics(entity)` | Nothing | Refreshes diagnostic state after a caller changes a tracked prop's physics. |
| `gebLib.Visuals.SetDebrisPhysicsRetirement(enabled)` | Boolean | Enables retirement of settled tracked props. |
| `gebLib.Visuals.SetDebrisRenderEnabled(enabled)` | Boolean | Shows or hides entity debris. Intended for profiling comparisons. |
| `gebLib.Visuals.SetDebrisPhysicsEnabled(enabled)` | Boolean | Enables or freezes tracked debris physics. Intended for profiling comparisons. |
| `gebLib.Visuals.GetDebrisRuntimeState()` | Table | Returns `retirement`, `render`, `physics`, `trackedPhysics`, `scanBudget`, `scanInterval`, and `targetSweepTime`. |

### Static batches

Static chunks from impacts and eligible waves share spatial meshes and cached lighting. Settled physical chunks can be promoted while keeping their expiration and shadow policy.

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.Visuals.SetDebrisStaticBatching(enabled)` | Boolean | Sets the active batching state. Disabling flushes queued static pieces and clears promotion work. Existing built batches remain until expiry or clear. |
| `gebLib.Visuals.GetDebrisBatchState()` | Table | Returns `enabled`, `batches`, `pieces`, `pendingPromotions`, `pendingPieces`, `lightingCells`, and `promotionBudget`. |
| `gebLib.Visuals.ClearDebrisBatches()` | Nothing | Destroys meshes and clears pending work. |
| `gebLib.Visuals.QueueRetiredDebris(entity)` | Boolean | Advanced: queues an eligible tracked physical entity for promotion. Normal debris retirement calls this automatically. |

## Particle debris bursts

```lua
local emitted = gebLib.Visuals.CreateDebrisBurst(material, position, count, options)
```

Returns the number of particles created. It uses one emitter for the call unless `options.emitter` supplies a valid existing emitter.

### Numeric options

For `lifetime`, `size`, `endSize`, `speed`, and `alpha`, a fixed value may be replaced with `nameMin` and `nameMax`. Supplying only one bound uses it for both. Reversed bounds are corrected.

| Option | Default | Meaning |
| --- | --- | --- |
| `lifetime` | 5 | Particle lifetime, minimum 0.01. |
| `size` | 4 | Start size, minimum 0. |
| `endSize` | Same sampled start size | End size. |
| `speed` | 250 | Random velocity scale, minimum 0. |
| `alpha` | Input color alpha or 255 | Start alpha, clamped to 255. |
| `spin` | 180 degrees/sec | Maximum random roll delta. |
| `spread` | 1 | Random velocity spread around `direction`. |
| `bounce` | 0.35 | Collision bounce. |
| `collideChance` | 1 | Per-particle collision chance from 0 through 1. |
| `airResistance` | Engine default | Optional non-negative value. |
| `length` | Disabled | Start trail length. |
| `endLength` | `length` | End trail length. |
| `maxActiveParticles` | Unlimited | Caps this call against particles already active on the emitter. |

### Value options

| Option | Default | Meaning |
| --- | --- | --- |
| `velocity` | None | Added to each generated velocity. |
| `direction` | Random sphere | Direction multiplied by sampled speed. Supply a normalized vector for predictable speed. |
| `gravity` | `Vector(0, 0, -600)` | Particle gravity. |
| `color` | `color_white` | RGB and default alpha. |
| `collide` | `true` | Enables particle collision. |
| `lighting` | `false` | Enables particle lighting. |
| `emitter` | New emitter | Existing emitter to reuse. gebLib does not finish a supplied emitter. |
| `use3D` | `false` | Passed when gebLib creates the emitter. |

For the highest particle throughput, use `collide = false`.

## Shockwaves

```lua
local emitted = gebLib.Visuals.CreateShockwave(position, normal, radius, lifetime, options)
```

Returns 0, 1, or 2 engine particles. Radius must be greater than 0. Lifetime defaults to 0.4 and is clamped to at least 0.01.

| Option | Default | Meaning |
| --- | --- | --- |
| `offset` | 5 | Distance along the normalized surface normal. |
| `startRadius` | 0 | Initial ring radius. |
| `material` | `particle/particle_ring_wave_additive` | Ring material. |
| `color` | `color_white` | Ring color. |
| `alpha` | Color alpha or 200 | Ring start alpha. |
| `lighting` | `false` | Ring lighting. |
| `distortion` | `true` | Adds a second distortion particle. |
| `distortionMaterial` | `particle/warp1_warp` | Distortion material. |
| `distortionScale` | 1 | Distortion end radius multiplier. |
| `distortionAlpha` | 255 | Distortion start alpha. |

## Water debris

```lua
local emitted = gebLib.Visuals.CreateWaterDebris(position, normal, strength, options)
```

Returns the combined number of particles and engine effects created. `strength` defaults to 1 and is clamped to at least 1.

| Option | Default | Meaning |
| --- | --- | --- |
| `particleCount` or `count` | `strength * 1.25` | Total spray, droplet, and mist budget. `particleCount` wins. |
| `particles` | `true` | `false` disables all three particle layers. |
| `direction` | Surface normal | Main emission direction. |
| `velocity` | None | Added to particle velocity. |
| `speed` | `strength * 2.2`, clamped 180 through 1100 | Base spray speed. |
| `spread` | 0.7 | Spray spread. |
| `dropletSpread` | 0.95 | Droplet spread. |
| `mistSpread` | 1.15 | Mist spread. |
| `gravity` | `Vector(0, 0, -850)` | Spray and droplet gravity. |
| `scale` | `strength / 90`, clamped 0.6 through 8 | Engine splash effect scale. |
| `particleScale` | 1, clamped 0.25 through 32 | Multiplies particle sizes only. |
| `radius` | `strength * 0.12`, minimum 2 | Random splash placement radius. |
| `color` | Pale water blue | Spray and droplet color. |
| `mistColor` | Pale translucent mist | Mist color. |
| `sprayMaterial` | `effects/splash4` | Spray material. |
| `dropletMaterial` | `particle/water/waterdrop_001a` | Droplet material. |
| `mistMaterial` | `particle/particle_smokegrenade` | Mist material. |
| `mist` or `smoke` | `true` | `false` disables mist. |
| `effects` | `true` | Enables `watersplash`, `gunshotsplash`, and `waterripple` effects. |
| `splashCount` | `strength / 85 + 1.5`, clamped 1 through 8 | Surface splash positions. |
| `gunshotSplashes` | `true` | Adds one `gunshotsplash` at each splash position. |
| `rippleCount` | Half splash count, clamped 1 through 4 | Ripple count. |
| `ripples` | `true` | Enables ripples. |

## Surface-aware impacts

```lua
local emitted, smoke = gebLib.Visuals.CreateImpactDebris(position, normal, strength, options)
```

Returns a count and the optional smoke particle system. Strength defaults to 1 and is clamped to at least 1. If material is `MAT_SLOSH`, the call routes to `CreateWaterDebris` and returns only its count.

Flesh and eggshell materials produce no debris.

### Composition

| Option | Default | Meaning |
| --- | --- | --- |
| `count` | `strength * 0.5` | Total requested composition before explicit layer counts. |
| `modelCount` | Derived, capped by `modelLimit` | Static surface chunk count. |
| `propCount` | Derived, capped by `propLimit` | Physical chunk count. |
| `particleCount` | Remaining count | Cheap particle fragment count. |
| `modelLimit` | 16 | Default cap used only when `modelCount` is absent. |
| `propLimit` | 12 | Default cap used only when `propCount` is absent. |
| `craters` | `true` | `false` disables static chunks. |
| `props` | `true` | `false` disables physical chunks. |
| `particles` | `true` | `false` disables particle fragments. |
| `smoke` | `true` | Enables the bundled debris smoke system. |
| `smokeCount` | `count * 0.3`, clamped 1 through 96 | Controls smoke density. |

Explicit counts are not clamped by `modelLimit` or `propLimit`. Keep them bounded.

### Material and placement

| Option | Default | Meaning |
| --- | --- | --- |
| `material` | `MAT_CONCRETE` or detected water | Source `MAT_*` value. |
| `detectWater` | `true` | When material is absent, checks the impact point for water. |
| `surface` | `true` | Samples the impacted texture for model material. |
| `hitTexture` | Trace sample | Known hit texture path to avoid another lookup. |
| `direction` | Zero vector | Source attack direction mixed with the normal. |
| `radius` | `strength / 3`, minimum 1 | Static chunk spread. |
| `pathDivisor` | Minimum of loop count and strength | Controls forward step distance. |
| `validatePlacement` | `true` | Uses hull, line, and contents checks for static pieces. |
| `flags` | None | Compatibility: value 2 keeps the static placement center at the origin. |
| `propAtOrigin` | `false` | Places every physical chunk at the impact origin. |

### Appearance and physics

| Option | Default | Meaning |
| --- | --- | --- |
| `modelScale` | 1 | Multiplies random static chunk scale. |
| `propScale` | Engine model scale | Fixed physical chunk scale. |
| `lifetime` | 5 | Static lifetime. |
| `propLifetime` | `lifetime` | Physical lifetime. |
| `shadows` | `true` | Chunk shadow policy. |
| `preserveCount` | `false` | Allows chunks from this impact to exceed `MaxDebris`. |
| `propSpeed` | 1000 | Random physical velocity scale. |
| `propVelocity` | Zero vector | Added to random physical velocity. |
| `smokeColor` | Material color | Bundled smoke tint. |

`CreateImpactDebris` uses static batching when enabled. Physical chunks are marked for promotion after two sleep confirmations.

### Impact lookup helpers

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.Visuals.GetDebrisSurfaceMaterial(position, normal, hitTexture, materialType)` | Material name, normalized material type | Samples a texture-backed vertex-lit material. |
| `gebLib.Visuals.GetImpactDebrisModel(materialType)` | Model path | Chooses a random model from the normalized material family. |
| `gebLib.Visuals.GetImpactPhysicsMaterial(materialType)` | String | Maps the material to Source physics material. |

## Surface craters

```lua
local emitted = gebLib.Visuals.CreateSurfaceCrater(position, normal, size, options)
```

This is a constrained `CreateImpactDebris` call with no props, particles, smoke, or water effects. Size defaults to 140.

| Option | Default | Meaning |
| --- | --- | --- |
| `count` | `size / 12`, clamped 1 through 16 | Static chunk count. |
| `radius` | `size / 3` | Placement radius. |
| `modelScale` | 0.65 | Static model scale multiplier. |
| `material`, `hitTexture`, `surface`, `lifetime`, `shadows`, `preserveCount`, `validatePlacement` | Impact defaults | Passed through to the impact system. |

## Debris waves

```lua
local wave = gebLib.Visuals.CreateDebrisWave(options)
```

Returns a wave object or `nil` when the plan has no work. Settings are copied when the wave is created.

### Timeline and path

| Option | Default | Meaning |
| --- | --- | --- |
| `origin` | `vector_origin` | Start position. Step 1 begins one `distanceStep` away. |
| `direction` | `Vector(1, 0, 0)` | Normalized forward direction. |
| `spreadAxis` | Perpendicular to direction and up | Normalized lateral axis. |
| `count` | 1 | Number of ordered steps. |
| `delay` | 0 | Delay before step 1. |
| `interval` | 0.01 | Seconds between due steps. 0 makes every step immediately due. |
| `maxStepsPerFrame` | 12 | Catch-up work cap per rendered frame. |
| `distanceStep` | 35 | Forward distance per step. May be negative. |
| `spread` | 0 | Random half-width along `spreadAxis`. |
| `integerSpread` | `false` | Uses integer random lateral offsets. |
| `lifetime` | 5 | Lifetime for model and prop debris. |
| `preserveCount` | `false` | Allows wave pieces to exceed `MaxDebris`. |

### Surface setup

| Option | Default | Meaning |
| --- | --- | --- |
| `material` | Sampled or none | Material override for debris models. |
| `materialType` | `MAT_CONCRETE` | Initial Source material family. |
| `surface` | None | Optional `{position, normal, hitTexture, materialType}` sampled once for the wave. |
| `modelPath` | Material-family model | String or `function(wave, step, physical, materialType)` returning a model path. |
| `floor` | Disabled | Per-step ground trace configuration. Without it, every projected position is accepted as supplied. |

`floor` fields:

| Field | Default | Meaning |
| --- | --- | --- |
| `startHeight` | 64 | Trace start above the projected step. |
| `depth` | 256 | Trace depth below the projected step. |
| `offset` | 1 | Final offset along the surface normal. |
| `minNormalZ` | 0.2 | Minimum upward normal dot. |
| `mask` | `MASK_SOLID | MASK_WATER` | Explicit trace mask. |
| `water` | `true` | Includes water in the default mask. |
| `filter` | None | Engine trace filter. |
| `collisionGroup` | None | Engine trace collision group. |
| `ignoreWorld` | `false` | Engine `ignoreworld`. |
| `rejectSky` | `true` | Skips sky hits. |
| `rejectNoDraw` | `true` | Skips nodraw hits. |
| `colorFallback` | `true` | Tints entity-path debris with `render.GetSurfaceColor` when no usable texture exists. |

Skipped floor steps still run their indexed event and `onStep`, with a `nil` position.

### Model and prop layers

Set `model = false` or `prop = false` to disable a layer. Otherwise each field is an option table:

| Field | Layers | Default | Meaning |
| --- | --- | --- | --- |
| `offset` | Both | Zero vector | Added to accepted position. |
| `angles` | Both | `AngleRand()` | Fixed Angle or `function(wave, step)` returning an Angle. |
| `scaleMin` | Both | 1 | Minimum random model scale. |
| `scaleMax` | Both | `scaleMin` | Maximum random model scale. |
| `shadows` | Both | `true` | Static batch and retired-prop shadow policy. |
| `setup` | Both | None | `function(wave, entity, step)`. A custom setup keeps the entity path. |
| `collisionGroup` | Prop | `COLLISION_GROUP_DEBRIS` | Client prop collision group. |
| `spawn` | Prop | `true` | Calls `Spawn`. |
| `activate` | Prop | `true` | Calls `Activate`. |
| `velocity` | Prop | Zero vector | Initial physics velocity. |
| `velocityJitter` | Prop | 0 | Adds `VectorRand() * value`. |
| `angularVelocity` | Prop | None | Number for random magnitude or a Vector. |
| `physicsMaterial` | Prop | Sampled material mapping | Physics material override. |

Model pieces without a setup or fallback color enter the static batch queue. Props without those customizations may enter a batch after settling.

### Water steps

When a floor trace resolves to `MAT_SLOSH`, solid layers are skipped and `CreateWaterDebris` is called. Set `water = false` to suppress it. Otherwise `water` accepts every water-debris option plus:

| Field | Default | Meaning |
| --- | --- | --- |
| `strength` | 22 | Per-step water strength. |

### Events and callbacks

| Option | Callback arguments | Meaning |
| --- | --- | --- |
| `events[step]` | `(wave, step)` | Runs for that index, including skipped steps. |
| `onStart` | `(wave)` | Runs once when delay ends. |
| `onStep` | `(wave, step, position, floorTrace)` | Runs after each step. Position is `nil` when rejected. |
| `onComplete` | `(wave)` | Runs once after the last processed step. |
| `onCancel` | `(wave)` | Runs once when cancelled or a callback fails. |

### Wave methods

| Method | Returns | Meaning |
| --- | --- | --- |
| `wave:IsActive()` | Boolean | Whether it can still emit. |
| `wave:GetProgress()` | Number | Processed-step fraction from 0 through 1. |
| `wave:GetSpawnedCount()` | Number | Total model, prop, particle, and engine-effect count reported by steps. |
| `wave:GetSkippedCount()` | Number | Floor-rejected step count. |
| `wave:Pause()` | Wave | Freezes the schedule. |
| `wave:Resume()` | Wave | Shifts start time by the paused duration. |
| `wave:Cancel()` | Nothing | Stops and runs `onCancel`. |

## Projected decals

### Static projection

```lua
local ok = gebLib.Visuals.ProjectDecal(material, entity, position, normal, scale, color)
```

`material` may be a material path or `IMaterial`. `entity` may be the world or a valid entity. Scale defaults to 1 and color to white. Returns `false` for an invalid surface, normal, or material.

### Animated projection

```lua
gebLib.Visuals.RegisterProjectedDecalAnimation("myaddon.crack", {
    texture = "decals/myaddon_crack_anim",
    frameCount = 7,
    duration = 0.2,
    poolSize = 16,
})

gebLib.Visuals.ProjectAnimatedDecal(
    "myaddon.crack",
    hitEntity,
    hitPosition,
    hitNormal,
    1,
    color_white
)
```

The definition requires a VTF texture path. Defaults are 1 frame, 0.2 seconds, and 16 reusable material slots. Reusing a slot cancels its stale timers. The final frame is projected permanently through Source decals. Moving entities are converted through local space before that final projection.

### Clientside decal entity

```lua
local decal = gebLib.Visuals.CreateDecal(materialPath, position, angles, size, lifetime)
```

Returns `geblib_decal` or `NULL`. Defaults are zero position and angles, size 32, and lifetime 3 seconds. This entity draws an oriented quad and removes itself after its lifetime.

The returned entity supports:

| Method | Meaning |
| --- | --- |
| `decal:SetDecal(materialPath)` | Replaces the drawn material. |
| `decal:SetDecalSize(size)` | Sets the absolute half-size and render bounds. |
| `decal:GetDecalSize()` | Returns the current half-size. |
| `decal:SetLifeTime(expiration)` | Sets an absolute `CurTime()` expiration. |
| `decal:GetLifeTime()` | Returns the absolute expiration. |
| `decal:DoAnimation(enabled, speed)` | Grows from zero toward the current size, or cancels growth. Defaults to enabled and speed 18. |

## Shared particle emitters

```lua
local emitter = gebLib.Visuals.AcquireParticleEmitter(key, position, use3D, idleTime)
```

The same key returns the same valid emitter and updates its position. Changing `use3D` replaces the old emitter. `idleTime` defaults to 1 second. After the idle window and when no particles remain, gebLib finishes the emitter.

| Function | Returns | Meaning |
| --- | --- | --- |
| `AcquireParticleEmitter(key, position, use3D, idleTime)` | Emitter or `nil` | Acquires or refreshes a keyed emitter. |
| `ReleaseParticleEmitter(key)` | Boolean | Finishes and removes one key immediately. |
| `ClearParticleEmitters()` | Nothing | Finishes every keyed emitter. Also runs on shutdown. |

## Surface helpers

`gebLib.Surface` loads on both realms. Its returned model arrays and description tables are cached. Treat them as immutable.

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.Surface.TouchesWater(position, normal)` | Boolean | Checks contents at the position and 4 units behind the normal. |
| `gebLib.Surface.NormalizeMaterial(materialType)` | `MAT_*` | Maps tile/default to concrete, grass to dirt, bloody flesh to flesh, and grate/computer to metal. |
| `gebLib.Surface.Describe(surfaceProp)` | Description | Cached surface data with `surfaceProp`, `material`, and common impact, strain, break, and bullet sounds. |
| `gebLib.Surface.Models(materialType)` | Model array | Metal, antlion, or rock family. |
| `gebLib.Surface.PhysicsMaterial(materialType)` | String | `metal`, `flesh`, `dirt`, or `concrete`. |
| `gebLib.Surface.Color(materialType)` | Color-like table | Default effect tint. |
| `gebLib.Surface.MaterialAt(position, normal, hitTexture, materialType, allowTrace)` | Material name, normalized type | Builds and caches a vertex-lit material from the surface texture. `allowTrace = false` disables fallback tracing. |
| `gebLib.Surface.Model(materialType)` | Model path | Random model from the normalized family. |

Public model lists are `gebLib.Surface.RockModels` and `gebLib.Surface.AllModels`.

## Debris profiler

The profiler is client-only and follows `geblib_developer_debugmode`. With debug mode disabled, it records nothing and installs no profiling frame hook.

| Lua function | Console command | Meaning |
| --- | --- | --- |
| `gebLib.Visuals.ResetDebrisProfile()` | `geblib_debris_profile_reset` | Clear samples. |
| `gebLib.Visuals.ReportDebrisProfile()` | `geblib_debris_profile_report` | Print the report. |
| `gebLib.Visuals.SetDebrisInitializationComparison(enabled)` | `geblib_debris_profile_compare_init 0|1` | Alternate legacy and optimized prop initialization for normalized comparison. |
| `gebLib.Visuals.IsDebrisProfileActive()` | None | Read profiler state. |
| `gebLib.Visuals.SetDebrisPhysicsRetirement(enabled)` | `geblib_debris_profile_retire_physics 0|1` | Compare settled-physics retirement. |
| `gebLib.Visuals.SetDebrisStaticBatching(enabled)` | `geblib_debris_profile_batch_static 0|1` | Compare static batching. |
| `gebLib.Visuals.SetDebrisRenderEnabled(enabled)` | `geblib_debris_profile_render 0|1` | Hide or show debris rendering. |
| `gebLib.Visuals.SetDebrisPhysicsEnabled(enabled)` | `geblib_debris_profile_physics 0|1` | Freeze or enable debris physics. |

Profiler output proves only the observed client session. It does not establish player-visible quality or hardware-wide performance.
