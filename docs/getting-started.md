# Getting started

gebLib is loaded by `lua/autorun/000_geblib_v2.lua`. The filename is retained for upgrade compatibility even though the current library major version is 3.

## Installation

Keep gebLib as its own addon:

```text
garrysmod/
  addons/
    gebLib/
      lua/
      materials/
      models/
      particles/
      shaders/
```

Do not copy individual library modules into another addon. The bootstrap sends client files, includes modules in dependency order, precaches bundled effects, then sets `gebLib.Loaded = true`.

## Realms

The reference marks APIs as:

- **Shared**: defined on the server and client. Calling an engine operation may still have realm-specific effects.
- **Server**: callable only on the server.
- **Client**: callable only on the client.

Put shared definitions in `lua/autorun`, server behavior in `lua/autorun/server`, and presentation in `lua/autorun/client`. Garry's Mod loads those folders after shared autorun files, so gebLib is normally ready by then.

## Waiting for gebLib

Another shared autorun file may load before or after gebLib. Use the readiness flag and hook together:

```lua
local initialized = false
local hookId = "MyAddon.GebLibReady"

local function initialize(lib)
    if initialized then return end
    initialized = true
    hook.Remove("gebLib.Loaded", hookId)

    print("Using gebLib " .. lib.Version)
end

if gebLib and gebLib.Loaded then
    initialize(gebLib)
else
    hook.Add("gebLib.Loaded", hookId, initialize)
end
```

Do not return a value from a readiness callback. Garry's Mod stops dispatching a hook after a non-`nil` return.

## Naming

Use stable, addon-prefixed names for registrations:

```lua
"myaddon.poison"
"myaddon.hit.v1"
"myaddon.camera.recoil"
"myaddon.pose.block"
```

Network message names must be lowercase, contain a namespace separator, and stay at or below 64 characters. Change the message name when a released schema changes.

## Ownership and cleanup

gebLib copies network schemas, codecs, status-effect definitions, impact-frame sequences, presets, and active visual settings where the contract says it owns them. Mutating the source table later is not a supported way to update active work.

Long-lived client features should remove what they register:

```lua
hook.Add("ShutDown", "MyAddon.Cleanup", function()
    gebLib.CameraImpulses.Remove("myaddon.camera.recoil")
    gebLib.BoneControllers.Remove("myaddon.aim")
    gebLib.BoneMatrixModifiers.Untrack(LocalPlayer(), "myaddon")
end)
```

Owned objects also expose direct cleanup:

- `camera:Stop()`
- `trail:Remove()`
- `session:Remove()`
- `wave:Cancel()`
- `gebLib.ImpactFrames.Stop(id)`
- `gebLib.Visuals.ReleaseParticleEmitter(key)`

## Error boundaries

Callback-driven lifecycle systems contain callback errors and clean up their owned state. This includes status effects, network receivers, cinematic cameras, and debris waves. Registration errors and invalid direct arguments still raise immediately so bad contracts are found during development.

## Security boundary

Typed networking validates packet shape, bounds, and rate limits. It does not decide whether a player may perform an action. Server receivers must still validate permissions, ownership, distance, cooldowns, and current gameplay state.

## Where to go next

- Use the [API reference](api-reference.md) for signatures and return values.
- Use [Visuals and debris](visuals.md) for visual option defaults.
- Use [Impact frames](impact-frames.md) for authored fullscreen effects.
- Copy the [examples](../examples/README.md) into a development addon to try the systems in game.
