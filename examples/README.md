# Examples

The example tree is a small development addon. It is inert while it remains under `examples/`.

To try it, copy `examples/lua` into a separate addon such as:

```text
garrysmod/addons/geblib_example/lua/
```

Keep gebLib installed separately. Do not move these files into gebLib's live `lua` directory unless you want the example commands and hooks on every session.

## Files

| File | Covers |
| --- | --- |
| `lua/autorun/geblib_example_shared.lua` | Readiness, typed messages, codecs, immutable status definitions, math, and shared state. |
| `lua/autorun/server/geblib_example_server.lua` | Server validation, traces, contacts, damage, knockback, status application, chat, player animation, entity helpers, and connection hooks. |
| `lua/autorun/client/geblib_example_presentation.lua` | Camera modifiers, impulses, bone controllers, bone matrices, replicas, trails, audio sessions, and cinematic cameras. |
| `lua/autorun/client/geblib_example_visuals.lua` | Surface helpers, debris, particles, shockwaves, water routing, waves, decals, emitters, impact frames, render batches, and drawing. |

The [API reference](../docs/api-reference.md), [visual reference](../docs/visuals.md), and [impact-frame reference](../docs/impact-frames.md) cover every option and method. The examples choose a small useful subset instead of setting every default explicitly.

## Commands

Run these in a development session:

| Command | Realm | Result |
| --- | --- | --- |
| `geblib_example_power 1` through `4` | Client | Sends a rate-limited ability selection to the server. |
| `geblib_example_strike` | Player console | Traces forward, applies damage and force, applies the example status, and broadcasts presentation data. |
| `geblib_example_action` | Player console | Plays a model-dependent gesture sequence. |
| `geblib_example_camera` | Client | Plays a three-second orbit camera. |
| `geblib_example_music` | Client | Toggles a local streamed audio session. |
| `geblib_example_wave` | Client | Creates a controllable ground-traced debris wave at the aimed point. Running it again cancels the previous wave. |

Client toggles:

| ConVar | Meaning |
| --- | --- |
| `geblib_example_aim_bone 0|1` | Additive spine aiming through one shared bone controller. |
| `geblib_example_block_pose 0|1` | Ordered bone-matrix pose. |
| `geblib_example_trail 0|1` | Sequence replica trail. |
| `geblib_example_batches 0|1` | Beam and sprite batch sample. |
| `geblib_example_hud 0|1` | Circular drawing helpers and text. |

## Cleanup pattern

Every client registration has a stable name. The presentation example removes hooks, channels, controllers, tracking, trails, audio, cameras, and emitters during shutdown. Use the same ownership pattern in an addon reload or weapon removal path.

## What still needs an in-game check

Syntax and library tests cannot prove that a chosen sequence exists on every player model, that an impact scale looks right, that an audio file is mounted, or that an effect meets a frame-rate target. Treat those as player-visible acceptance checks.
