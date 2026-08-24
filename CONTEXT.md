# gebLib

gebLib is a small Garry's Mod Lua library for recurring gameplay needs that should remain easy to read and use.

## Language

**Status Effect Definition**:
A named, reusable description of status-effect callbacks and tick timing.

**Applied Status Effect**:
The duration, level, source, and timing state of one Status Effect Definition on one living entity.

**Cinematic Camera**:
A player-focused frame timeline that controls view presentation.

**Transient Visual**:
A client-only debris model or decal with a finite lifetime.

**Debris Wave**:
A controllable Transient Visual that emits ordered debris steps over time from one shared frame scheduler.

**Frame Dispatcher**:
The internal mutation-safe frame loop shared by independently owned Cinematic Cameras and Debris Waves.

**Transient Visual Plan**:
An owned, normalized set of settings prepared once before a Transient Visual is emitted.

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
- A **Transient Visual** exists only on the client that creates it.
- A **Debris Wave** owns its emission progress and may be paused, resumed, or cancelled independently.
- The **Frame Dispatcher** advances lifecycles without owning their domain rules.
- A **Debris Wave** executes one **Transient Visual Plan** that cannot be changed through its caller's settings table.
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
