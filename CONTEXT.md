# gebLib

gebLib is a small Garry's Mod Lua library for recurring gameplay needs that should remain easy to read and use.

## Language

**Status Effect Definition**:
A named, reusable description of status-effect callbacks and tick timing.

**Applied Status Effect**:
The duration, level, source, and timing state of one Status Effect Definition on one living entity.

**Action**:
An entity-owned timed sequence of callbacks.

**Animation**:
An entity sequence with frame callbacks and playback control.

**Cinematic Camera**:
A player-focused frame timeline that controls view presentation.

**Transient Visual**:
A client-only debris model or decal with a finite lifetime.

## Relationships

- A **Status Effect Definition** may produce one **Applied Status Effect** per living entity.
- An **Applied Status Effect** belongs to exactly one living entity.
- An **Action**, **Animation**, and **Cinematic Camera** each own their lifecycle independently.
- A **Transient Visual** exists only on the client that creates it.

## Example dialogue

> **Dev:** "What happens when poison is applied twice?"
> **Domain expert:** "The entity still has one Applied Status Effect. A stronger level replaces it, while the same level keeps the later expiration time."

## Flagged ambiguities

- "Effect" previously meant both the reusable definition and its mutable runtime copy. Use **Status Effect Definition** and **Applied Status Effect**.
- "Action" means the timed callback object. A player gesture in slot 1 is called an action animation.
