---
name: simple-code
description: Keep code changes simple and proportionate to current requirements. Use when implementing, refactoring, debugging, reviewing code, or planning code architecture, especially around abstractions, state ownership, lifecycle, and concurrency. Does not require a separate architecture exercise for small edits.
---

# Simple code

Choose the simplest design that satisfies the current behavior and necessary correctness guarantees. Optimize for how easily the next developer can understand and change the complete flow, not for minimum line count or maximum extensibility.

## Before changing code

- Identify the required behavior and relevant existing conventions. Separate explicit requirements, demonstrated defects, and assumptions.
- Start with the existing components and the framework's standard APIs. Add a layer only when a concrete responsibility or invariant cannot reasonably live there.
- For substantial changes to responsibilities or concurrency, briefly describe who owns state, work, and cleanup, and why any new abstraction is needed. Keep this proportional to the task; it is not an additional approval gate.

## Design constraints

- Implement current requirements. Do not add extension points, modes, policies, configuration, or generic infrastructure for hypothetical future consumers.
- Before adding a coordinator, manager, wrapper, queue, interface, or state machine, identify the concrete problem it solves and why a simpler option is insufficient. A name such as "clean architecture" or "testability" alone is not a justification.
- Prefer the language, framework, and platform's standard mechanisms for lifecycle, execution, and resource ownership. Customize them only for a demonstrated need; testing convenience alone need not enlarge the production API.
- Give state, work, and resources explicit owners with appropriate lifetimes. Work that must outlive its caller belongs to an owner with that lifetime; the caller should not manage the owner's internal cleanup protocol.
- Keep dependency quirks, synchronization, stale-result checks, and recovery inside the component responsible for them. Expose meaningful operations and outcomes without forcing callers to understand internal bookkeeping.
- Give each mutable fact a clear source of truth. Derive values where practical, and update related state together when separate updates would violate an invariant.
- Prefer explicit domain steps and ordinary control flow over generic execution frameworks and boolean mode switches. Extract a component when it gives a coherent responsibility a clear home, not merely to shorten a file.
- A little duplication is acceptable when an abstraction would couple different behaviors. Do not require wrappers for every primitive, an interface for every class, or arbitrary limits on fields and method length.

## Preserve behavior while simplifying

- Keep failure handling proportional to the failed operation. Distinguish a caller stopping its wait, an operation failing, and shared state becoming invalid. Do not escalate a local or temporary failure into unrelated state changes or system-wide recovery without a concrete contract requiring it.
- When asynchronous or concurrent work is involved, preserve necessary ordering and ownership guarantees. A caller stopping its wait may leave the underlying operation running. A lock or a shorter implementation is not sufficient if late completion can still change shared state; explain the relevant interleaving and contain the protection at the appropriate boundary.
- Question both missing safeguards and overly broad safeguards. Use a realistic scenario, an API contract, or evidence from the code to justify each one; do not build infrastructure for every imaginable failure.
- Preserve established behavior and public contracts. When mirroring or replacing another implementation, verify behavioral differences before introducing new workflows, retries, or recovery policies.

## Before finishing

- Re-read the complete changed flow. Remove redundant state, forwarding layers, duplicate ownership, unnecessary public parameters, and abstractions that no longer earn their cost.
- Ask whether an existing component or standard API can replace custom machinery while retaining the required behavior. Make justified simplifications within the requested scope; leave unrelated code alone.
- Test observable requirements and important failure interleavings. Passing tests do not validate the product decision they encode; reconsider tests that merely preserve an overcomplicated or harmful behavior. Follow required repository checks and scale additional validation to risk.
- Report material simplifications and explain any non-obvious complexity that remains. Do not produce a ceremonial checklist for a small change or claim runtime verification from static review.

## Applying this preference with other guidance

This skill records the user's preference for simple, maintainable implementations. When generic design guidance recommends additional layers or mechanical wrappers, apply it only where it solves a concrete problem. Preserve explicit task requirements, repository contracts, necessary safety properties, and higher-priority instructions. Never remove a necessary guarantee merely to reduce code size.
