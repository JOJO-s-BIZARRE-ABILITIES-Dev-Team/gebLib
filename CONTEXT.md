# gebLib

gebLib is a small Garry's Mod Lua library for recurring gameplay needs that should remain easy to read and use.

## Language

**Status Effect Definition**:
A named, reusable description of status-effect callbacks and tick timing.

**Applied Status Effect**:
The duration, level, source, and timing state of one Status Effect Definition on one living entity.

**Cinematic Camera**:
A player-focused frame timeline that controls view presentation.

**Camera Modifier**:
A named client callback that composes one part of the active player view in deterministic priority order.

**Bone Controller**:
A named client rule that contributes an additive target rotation to one player bone.

**Bone Matrix Modifier**:
A named client rule that owns one ordered transformation of an entity's built bone matrices.

**Player Replica**:
A clientside model that mirrors a player's appearance, animation pose, and optionally captured bone matrices.

**Replica Trail**:
A bounded client-owned history of Player Replica poses with capture cadence and expiration.

**Camera Impulse**:
A short collection of numeric camera values with per-value exponential decay.

**Visual Batch**:
A reusable client buffer that submits one beam or sprite render pass.

**Audio Session**:
A client-owned lifecycle for one sound patch or asynchronous file channel.

**Combat Contact**:
A normalized trace or target-selection result used by damage and force policy.

**Transient Visual**:
A client-only debris model or decal with a finite lifetime.

**Debris Wave**:
A controllable Transient Visual that emits ordered debris steps over time from one shared frame scheduler.

**Frame Dispatcher**:
The internal mutation-safe frame loop shared by independently owned Cinematic Cameras and Debris Waves.

**Transient Visual Plan**:
An owned, normalized set of settings prepared once before a Transient Visual is emitted.

**Projected Decal Animation**:
A registered texture sequence projected onto world or entity geometry through a bounded reusable material pool.

**Particle Emitter Lease**:
A keyed request for a shared client particle emitter that gebLib retires after its particles and idle window are exhausted.

**Surface Description**:
An immutable cached view of a Source surface property's normalized material and common impact sounds.

**Impact Frame**:
A short clientside post-process sequence selected from a registered preset and optionally anchored to entities or a world position.

**Network Message**:
A named, directional packet with one shared ordered schema and one receiving callback.

**Network Codec**:
A bounded rule that validates, writes, reads, and measures one Network Message field.

**Network Batch**:
An opt-in group of queued records for one server-to-client Network Message and recipient.

**Network Profile**:
Opt-in observations about packet and record size, frequency, recipients, repeated payloads, and field ranges used to advise developers about possible optimizations.

## Relationships

- A **Status Effect Definition** may produce one **Applied Status Effect** per living entity.
- An **Applied Status Effect** belongs to exactly one living entity.
- A **Cinematic Camera** owns its lifecycle independently.
- A **Cinematic Camera** contributes its view through a high-priority **Camera Modifier**.
- Multiple **Camera Modifiers** compose one view from lower to higher priority.
- Multiple **Bone Controllers** may contribute additive rotations to the same player bone.
- Multiple **Bone Matrix Modifiers** compose by priority, while only the highest active modifier in a named channel runs.
- A **Player Replica** mirrors a valid source player but owns its own position and drawing lifecycle.
- A **Replica Trail** owns a bounded pool of pose snapshots for one source entity.
- A **Camera Impulse** belongs to one Camera Modifier adapter and expires after its values decay.
- A **Visual Batch** owns reusable positions and colors, while its caller owns geometry and style.
- An **Audio Session** owns cancellation, retry, playback, fades, and cleanup for one active sound.
- A **Combat Contact** records geometry; the addon still owns target eligibility, tuning, and attack sequencing.
- A **Transient Visual** exists only on the client that creates it.
- A **Debris Wave** owns its emission progress and may be paused, resumed, or cancelled independently.
- The **Frame Dispatcher** advances lifecycles without owning their domain rules.
- A **Debris Wave** executes one **Transient Visual Plan** that cannot be changed through its caller's settings table.
- A **Projected Decal Animation** owns its material pool and cancels stale frame timers when a pool slot is reused.
- A **Particle Emitter Lease** is owned by its key and may be acquired repeatedly by one visual stream.
- A **Surface Description** belongs to one Source surface property identifier.
- An **Impact Frame** executes one owned snapshot of a registered preset and sequence.
- A **Network Message** is either server-to-client or client-to-server.
- A **Network Message** owns an ordered list of **Network Codecs**.
- A **Network Batch** belongs to one batch-enabled Network Message and preserves record order.
- A **Network Profile** observes traffic without changing a Network Message schema.

## Example dialogue

> **Dev:** "What happens when poison is applied twice?"
> **Domain expert:** "The entity still has one Applied Status Effect. A stronger level replaces it, while the same level keeps the later expiration time."

## Flagged ambiguities

- "Effect" previously meant both the reusable definition and its mutable runtime copy. Use **Status Effect Definition** and **Applied Status Effect**.
- A player gesture in slot 1 is called an action animation.
