# Modularization

Official guidance: [Guide to Android app modularization](https://developer.android.com/topic/modularization)
and [Modularization patterns](https://developer.android.com/topic/modularization/patterns).
Module taxonomy and the `api`/`impl` split are Now in Android practice (`NIA-1`, `NIA-2`), not official.

## Modularize when there is a problem to solve

Modules buy build-time parallelism, enforced boundaries, ownership lines and dynamic delivery.
They cost Gradle configuration, cross-module navigation plumbing, DI wiring and a real chance of
worse build times if the graph is wrong. A single-module app with clean `data`/`ui` packages
satisfies every **SR** rule. Split when one of these is true, not before:

- The build is slow enough that people notice, and the graph would actually parallelise.
- Separate teams need ownership boundaries that reviews alone are not holding.
- You ship different binaries (phone / Wear / TV / Auto) or use Play Feature Delivery.
- Package-level boundaries are being violated repeatedly and `internal` cannot help across one module.

## The two properties to optimise

**Low coupling** — a change in one module has minimal impact on others; modules know nothing of
each other's internals. **High cohesion** — everything in a module belongs to one functional
domain. Book code and payment code do not share a module.

If two modules constantly need each other's internals, they are one system. If two halves of a
module never interact, they are two modules.

## Module types (official)

| Type | Contains | Depends on |
|---|---|---|
| **Data** | repository (public), data sources + models (`internal`) | other data/common modules |
| **Feature** | one user journey: screens, ViewModels, feature navigation | data modules, common modules |
| **App** | entry point, root navigation, DI setup | feature modules |
| **Common / core** | design system, UI widgets, network client, analytics, utils | other common modules only |
| **Test** | shared fakes, fixtures, integration tests | whatever it tests |

A data module's public API is its repository. Everything else is `internal` — that is how
`LAYER-3` becomes compiler-enforced rather than aspirational.

A feature is a screen or a tightly related series of screens: usually one bottom-bar destination,
one sign-up flow, one checkout flow.

## Dependency rules

- Imports flow inward: `:app` → `:feature:*` → `:core:*`. Never outward.
- Core modules never depend on feature or app modules.
- Feature modules never depend on each other's implementations.
- If two features need the same logic, it belongs in a core or data module.

## Naming (`NIA-1`)

Gradle path mirrors the taxonomy: `:core:<name>`, `:feature:<name>`, `:app`.

Typical core set: `:core:model` (shared models), `:core:data` (repositories),
`:core:database` (Room), `:core:network` (Retrofit/Ktor), `:core:datastore`,
`:core:designsystem` (theme + Material components), `:core:ui` (composites that know data models),
`:core:common` (dispatchers, `Result`), `:core:testing` (fakes, rules).

Keep `:core:designsystem` free of data models; `:core:ui` is where composites that know about
domain types live. Mixing them is the most common reason a design system stops being reusable.

## Cross-feature navigation (`NIA-2`)

The problem: feature A must navigate to feature B without depending on B's implementation.

```
:feature:profile:api    // navigation key only — a serializable route type
:feature:profile:impl   // screens, ViewModels; registers the destination
:app                    // depends on every :impl, assembles the nav graph
```

`:feature:search:impl` depends on `:feature:profile:api` and navigates with the key. It never
sees `:feature:profile:impl`. An `api` module must not depend on another feature.

This is ceremony. Below a handful of teams, a shared `:core:navigation` module holding route types
gives most of the benefit for a fraction of the cost.

## Gradle configuration (`NIA-5`)

Shared configuration goes into convention plugins under `build-logic`, applied by id:

```kotlin
plugins {
    alias(libs.plugins.myapp.android.library)
    alias(libs.plugins.myapp.android.library.compose)
    alias(libs.plugins.myapp.hilt)
}
```

Not `subprojects {}` / `allprojects {}` blocks — they defeat configuration caching and couple every
module to the root build. Versions live in `gradle/libs.versions.toml`.

## Common mistakes

- Modules split by layer across the whole app (`:data`, `:domain`, `:ui`) instead of by domain —
  every feature change touches every module and nothing parallelises.
- One module per screen — graph overhead with no cohesion benefit.
- A `:core:common` that becomes a dumping ground everything depends on, serialising the build.
- Public data sources, which quietly re-enables `LAYER-3` violations across module lines.
- `api` dependencies where `implementation` would do, leaking transitive graphs.
