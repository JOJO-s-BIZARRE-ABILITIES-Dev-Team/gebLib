# Impact frames

Impact frames are client-only, short fullscreen compositions. An addon registers authored exposures and a preset, then plays it with world or entity anchors.

gebLib ships the renderer and materials, not a default preset. Register names in client autorun before calling `Play`.

## Complete example

```lua
gebLib.ImpactFrames.RegisterSequence("myaddon.heavy", {
    {
        Weight = 1,
        SceneMix = 0.05,
        Posterize = 1,
        EdgeStrength = 4,
        EtchStrength = 0.7,
        Radial = 0.4,
        Smear = 0.25,
        Texture = "radial",
        TextureAlpha = 0.85,
        LineDensity = 1,
        LineAlpha = 0.9,
        ContactCore = true,
        Star = true,
        AttackerMaskStrength = 0.8,
        VictimMaskStrength = 1,
    },
    {
        Weight = 0.7,
        SceneMix = 0.45,
        EdgeStrength = 1.5,
        Texture = "fragments",
        TextureAlpha = 0.5,
        LineDensity = 0.35,
        LineAlpha = 0.45,
        FadeOut = true,
    },
})

gebLib.ImpactFrames.RegisterPreset("myaddon.heavy", {
    Sequence = "myaddon.heavy",
    Duration = 0.18,
    Intensity = 1.2,
    Priority = 100,
    Channel = "myaddon.combat",
    Paper = Color(224, 244, 250),
    Ink = Color(10, 29, 43),
})

local id = gebLib.ImpactFrames.Play("myaddon.heavy", {
    AnchorPosition = hitPosition,
    WorldDirection = attackDirection,
    SubjectEntity = attacker,
    TargetEntity = victim,
})
```

## Registration

### `RegisterSequence`

```lua
gebLib.ImpactFrames.RegisterSequence(name, exposures)
```

`name` must be non-empty and `exposures` must be a non-empty sequential array. The array and each exposure table are copied. Register again to replace future playback. Active instances keep their own copy.

### `RegisterPreset`

```lua
gebLib.ImpactFrames.RegisterPreset(name, options)
```

The preset table is copied. Set `Sequence` to a registered sequence name or an inline exposure array. If absent, the preset name is used as the sequence name.

`gebLib.ImpactFrames.Sequences` and `gebLib.ImpactFrames.Presets` expose the registries for inspection. Use registration functions for changes.

## Playback

```lua
local id = gebLib.ImpactFrames.Play(presetName, overrides)
```

Returns a numeric instance ID or `nil` when the user disabled impact frames or a stronger instance blocks the selected channel.

Passing a table as the first argument uses it as overrides and selects a preset named `default`.

### Preset and override fields

| Field | Default | Meaning |
| --- | --- | --- |
| `Sequence` | Preset name | Registered name or inline exposure array. |
| `Duration` | 0.16 | Total seconds, minimum 0.05. |
| `Intensity` | 1 | Global scale, clamped 0.25 through 3. |
| `LineCount` | 72 | Base procedural line count, clamped 12 through 180. Each exposure scales it with `LineDensity`. |
| `FocusX` | 0.5 | Normalized fallback screen focus, clamped -0.25 through 1.25. |
| `FocusY` | 0.5 | Normalized fallback screen focus, clamped -0.25 through 1.25. |
| `Rotation` | 0 | Fallback direction and texture rotation in degrees. |
| `FrameJitter` | 1 | Per-exposure composition jitter, clamped 0 through 3. |
| `Paper` | Pale blue | Default background color. |
| `Ink` | Dark blue | Default effect color. |
| `Seed` | Derived from instance ID | Deterministic procedural art seed. |
| `Priority` | 0 | Selection priority within the channel. |
| `Channel` | `fullscreen_impact` | Replacement and blocking group. |
| `Force` | `false` | Allows this instance to replace a higher-priority instance in its channel. |
| `OnFinish(id)` | None | Runs on natural completion, replacement, `Stop`, or `StopAll`. |

### Anchoring and direction

The renderer chooses focus in this order:

1. Valid `AnchorEntity`, optionally using `AnchorBone` and then adding `AnchorOffset`.
2. `AnchorPosition`.
3. `WorldPosition`.
4. `FocusX` and `FocusY`.

If `WorldDirection` and a world anchor project to the screen, their projected line controls the composition direction. Otherwise `Rotation` is used.

| Field | Meaning |
| --- | --- |
| `AnchorEntity` | Moving entity used for screen focus. |
| `AnchorBone` | Bone index passed to `GetBonePosition`. |
| `AnchorOffset` | World-space offset added after resolving the entity or bone. |
| `AnchorPosition` | Fixed world position. |
| `WorldPosition` | Compatibility fixed world position used after `AnchorPosition`. |
| `WorldDirection` | World vector projected into screen direction. |

### Entity masks

| Field | Meaning |
| --- | --- |
| `SubjectEntity` | Primary attacker or subject mask entity. |
| `SubjectEntities` | Extra subject entities. Invalid entries, the world, and duplicates are ignored. |
| `TargetEntity` | Primary victim or target mask entity. |
| `TargetEntities` | Extra target entities. |

Each exposure decides whether and how strongly these masks are rendered.

## Channels and priority

Without `Force`, playback returns `nil` when an active instance in the same channel has a strictly higher priority. Otherwise every active instance in that channel is replaced. Equal priority replaces the older instance.

Only one dominant instance is drawn each frame across all channels. Highest priority wins, then newest start time. Lower-priority instances continue aging and may finish without becoming visible.

Use separate channels for ownership and interruption rules, not to layer several fullscreen effects.

## Exposure timeline

Each exposure receives a share of total duration from its `Weight`, default 1 and minimum 0.01. Exposures run in array order. `FadeOut = true` applies smoothstep fading across that exposure.

### Post-process fields

| Field | Default | Meaning |
| --- | --- | --- |
| `Weight` | 1 | Relative timeline duration. |
| `FadeOut` | `false` | Smoothly reduces this exposure to zero. |
| `SceneMix` | 0 | Amount of original scene preserved. 0 favors the paper and ink treatment; 1 preserves the scene. |
| `Posterize` | 0 | Posterized high-contrast treatment. |
| `EdgeStrength` | 0 | Screen edge emphasis. |
| `EtchStrength` | 0 | Etched line treatment, clamped to 1 by the shader. |
| `Radial` | 0 | Radial distortion around the focus. |
| `Smear` | 0 | Directional smear along the composition direction. |
| `Paper` | Instance paper | Exposure background override. |
| `Ink` | Instance ink | Exposure effect override. |

The custom shader uses all fields. If unavailable or disabled, gebLib falls back to color modification, Sobel edges, paper fill, masks, and overlay art. Radial, smear, etch, and scene processing are reduced in the fallback.

### Entity-mask fields

| Field | Default | Meaning |
| --- | --- | --- |
| `MaskStrength` | 0 | Legacy default for both subject and target masks. |
| `AttackerMaskStrength` | `MaskStrength` | Subject mask opacity multiplier. |
| `VictimMaskStrength` | `MaskStrength` | Target mask opacity multiplier. |
| `AttackerColor` | Exposure ink | Subject mask color. |
| `VictimColor` | Exposure ink | Target mask color. |

Mask entities are rendered into reusable full-screen targets. Invalid entities are skipped.

### Texture overlay fields

| Field | Default | Meaning |
| --- | --- | --- |
| `Texture` | None | Built-in key: `radial`, `slashes`, or `fragments`. |
| `TextureAlpha` | 0 | Overlay opacity multiplier. |
| `TextureScale` | 1.05 | Full-screen texture scale. |
| `TextureRotation` | 0 | Extra degrees added to direction, preset rotation, and seeded jitter. |
| `TextureColor` | Exposure ink | Texture tint. |

### Procedural speed-line fields

| Field | Default | Meaning |
| --- | --- | --- |
| `LineDensity` | 0 | Multiplies preset `LineCount` and `Intensity`. 0 disables lines. |
| `LineAlpha` | 0 | Line opacity multiplier. |
| `LineColor` | Exposure ink | Line color. |
| `DirectionBias` | 0.65 | Fraction of lines biased along the impact direction, clamped 0 through 1. |
| `Expansion` | 1 | Radial length scale. |

The generated line layout is stable for the instance seed.

### Contact core fields

| Field | Default | Meaning |
| --- | --- | --- |
| `ContactCore` | `false` | Enables the asymmetric central spear and wedges. |
| `CoreAlpha` | 1 | Core opacity multiplier. |
| `CoreScale` | 0.14 | Core size relative to screen height. |
| `CoreOuterColor` | Exposure ink | Outer spear and most wedges. |
| `CoreColor` | White | Inner spear and crossing line. |
| `CoreNegativeColor` | Exposure paper | Alternating negative wedges. |

### Energy ribbon fields

| Field | Default | Meaning |
| --- | --- | --- |
| `EnergyRibbons` | `false` | Enables six traveling ribbons. |
| `RibbonIntensity` | 1 | Ribbon width multiplier. |
| `RibbonOuterColor` | Orange | Outer ribbon color. |
| `RibbonCoreColor` | Warm white | Inner ribbon color. |

Ribbons travel across the exposure using its local progress.

### Contact star fields

| Field | Default | Meaning |
| --- | --- | --- |
| `Star` | `false` | Enables the central star and cross rays. |
| `StarAlpha` | 1 | Star opacity multiplier. |
| `StarScale` | 0.15 | Star size relative to screen height. |
| `StarColor` | White | Star color. |
| `StarSpikes` | 18, minimum 8 | Procedural spike count. |

## Lifecycle functions

| Function | Returns | Meaning |
| --- | --- | --- |
| `gebLib.ImpactFrames.Play(presetName, overrides)` | ID or `nil` | Creates an instance. |
| `gebLib.ImpactFrames.Stop(id)` | Nothing | Stops one ID if active and runs `OnFinish`. |
| `gebLib.ImpactFrames.StopAll()` | Nothing | Stops every instance and runs each callback. |
| `gebLib.ImpactFrames.GetActiveCount()` | Number | Expires finished instances, removes idle hooks, and returns the count. |
| `gebLib.ImpactFrames.IsShaderAvailable()` | Boolean | Reports current custom-shader availability. |

Natural completion waits until the duration has elapsed and the final exposure has rendered, or rendering has stalled for more than 0.15 seconds. `OnFinish` runs once.

## User controls

| ConVar | Default | Meaning |
| --- | --- | --- |
| `geblib_impact_frames` | 1 | Archived client preference for the complete system. `Play` returns `nil` when disabled. |
| `geblib_impact_frames_shader` | 1 | Archived client preference for the custom shader. Fallback rendering remains active. |

Respect a `nil` playback ID. It is a normal result when the user disables the effect or priority rejects the request.
