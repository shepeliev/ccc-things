---
name: android-architecture
description: Decide where Android code belongs, scaffold feature slices, and review Kotlin/Android code against the official Android app architecture recommendations. Use when adding a screen, ViewModel, repository, use case or data source; when choosing package or Gradle module structure; when reviewing a diff or module for architecture problems; or when answering questions about UI/domain/data layers, UDF, UI state, StateFlow collection, single source of truth, dependency injection with Hilt, modularization, or MVVM/MVI in Android apps.
---

# Android app architecture

Apply the official Android architecture guidance to a *specific* codebase: place new code
correctly, keep existing code consistent, and flag real violations without gold-plating.

**Rule priorities.** Every rule in `references/recommendations.md` carries a tag:

| Tag | Meaning |
|---|---|
| `SR` | Strongly recommended — official. Treat as a defect when violated. |
| `R` | Recommended — official. Follow unless the project has a stated reason not to. |
| `O` | Optional — official. A convention; only enforce if the project already uses it. |
| `NiA` | Not in the official recommendations. Proven practice from [Now in Android](https://github.com/android/nowinandroid). Propose, never impose. |

Cite rules by ID (`VM-5`, `UI-3`, …) so findings are traceable.

## Step 0 — read the project first (never skip)

The project's existing architecture beats the ideal one. Consistency is worth more than
purity, and a half-migrated codebase is worse than either. Detect before you decide:

```bash
# Layer/module shape
find . -name build.gradle.kts -o -name build.gradle | grep -v /build/ | sort
find . -type d \( -name data -o -name domain -o -name ui \) -not -path '*/build/*' | head -20

# Toolkit and libraries actually in use
grep -rEl 'androidx\.compose' --include=*.kt . | head -3        # Compose vs Views
grep -rE 'dagger.hilt|koin|javax.inject' --include=*.kts --include=*.toml . | head
grep -rE 'navigation3|navigation-compose|Navigation\b' --include=*.toml . | head

# Existing conventions to copy
find . -name '*ViewModel.kt' -not -path '*/build/*' | head -5
find . -name '*Repository*.kt' -not -path '*/build/*' | head -5
```

Then state, in one line, what the project *is* (single- or multi-module, Compose or Views,
Hilt or manual DI, domain layer or not) before proposing anything.

If the project has no architecture yet, size it with **Choosing scale** below.

## Where does this code go?

| The code… | Belongs in | Notes |
|---|---|---|
| Talks to Room, Retrofit, DataStore, Firebase, sensors, Bluetooth, GPS | Data layer — a **data source** | One data source per backing source. `internal`/`private` to its module. |
| Decides *which* source wins, caches, refreshes, merges, resolves conflicts | Data layer — a **repository** | The only data-layer type other layers may see (`LAYER-3`). |
| Business logic reused by 2+ ViewModels, or logic that makes one ViewModel unwieldy | Domain layer — a **use case** | Only when the reuse exists *today* (`LAYER-5`). |
| Turns app data into what one screen shows; survives rotation | UI layer — a **ViewModel** exposing `uiState` | Screen-level only (`VM-3`, `VM-6`). |
| Holds state for a reusable component (a text field, a carousel) | A **plain state holder** class, hoisted | Never a ViewModel (`VM-4`). |
| Draws pixels, reacts to taps | UI layer — a **composable** | State down, events up (`UI-1`). |
| Formats a date, validates an email | The layer that needs it, or a shared util module | Not automatically a use case. |

Two directional rules follow from this and are worth checking on every change:

- **Nothing in the UI layer touches a data source directly** (`LAYER-3`). A ViewModel that
  imports `androidx.room`, `retrofit2`, `SharedPreferences` or a Firebase type is a defect.
- **Dependencies point inward**: app → feature → core/data. Never the reverse.

## Choosing scale (do not gold-plate)

| Project | Structure | Domain layer | DI |
|---|---|---|---|
| Up to ~5 screens, one developer | Single module, `data`/`ui` packages | No | Manual, or Hilt if already there |
| Growing, several flows | Single module or a few, package-per-feature | Only where logic is *already* shared | Hilt (`DI-3`) |
| Large, multiple teams | Gradle modules `:core:*` / `:feature:*` | Yes | Hilt + convention plugins |

Adding use cases, `api`/`impl` module splits or a mapper per layer to a five-screen app is a
defect of the opposite kind. Say so when you see it proposed.

Modularization details, module types and naming: `references/modularization.md`.

## Workflows

### A. Adding a feature

1. Run Step 0. Copy the project's conventions — naming, package layout, DI style, test style.
2. Build the slice bottom-up, stopping at the layers the project actually uses:
   data source → repository → (use case) → ViewModel → screen composable.
3. Follow the canonical shapes in `references/layers.md`. Non-negotiables:
   - Repository exposes `Flow` streams and `suspend` functions (`LAYER-4`).
   - ViewModel exposes one `uiState: StateFlow<XUiState>`; no `Context`, no `Application`,
     no `AndroidViewModel` (`VM-1`, `VM-5`, `VM-6`).
   - UI collects with `collectAsStateWithLifecycle()` (`UI-3`).
   - Events go *up* as method calls; the ViewModel answers with a state change, not an event
     stream back to the UI (`UI-4`).
   - Constructor injection everywhere (`DI-1`).
4. Add tests as you go: ViewModel state, repository behaviour, with **fakes, not mocks**
   (`TEST-1`, `TEST-2`, `TEST-3`). See `references/testing.md`.
5. Run `scripts/arch-lint.sh` over the touched module before handing the change back.

### B. Reviewing code or a diff

1. Run Step 0 — review against *this* project's architecture.
2. Run the linter for mechanical violations:
   ```bash
   "$SKILL_DIR"/scripts/arch-lint.sh --path <module-or-repo>
   ```
   (`$SKILL_DIR` is this skill's base directory.)
3. Triage every hit. The linter is grep-based: it finds candidates, you decide. Open the file
   and confirm before reporting. Dismiss hits in generated code, samples, and code the rule
   does not actually apply to.
4. Read past the linter for what grep cannot see:
   - Is the repository a real single source of truth, or a pass-through to one data source
     that the ViewModel could have called itself?
   - Does `uiState` model the states the screen has (loading/empty/error/content), or does it
     leak data-layer types and nullable soup (`MODEL-1`)?
   - Are use cases earning their place, or is each one a one-line delegate?
   - Is business logic sitting in a composable?
5. Report findings as `RULE-ID · severity · file:line · what breaks · the fix`, ordered by
   severity. Do not report style opinions as architecture defects.

### C. Fixing violations

Fix in this order, smallest blast radius first: `UI-3` → `VM-5`/`VM-1` → `UI-4` → `LAYER-3`.
Each has a mechanical fix in `references/recommendations.md`. Change one rule at a time and
keep tests green between steps; `LAYER-3` in particular usually means extracting a repository,
which touches DI wiring.

## arch-lint

Deterministic, dependency-free grep pass over Kotlin/Java sources. It reports candidates, not
verdicts — always confirm a hit by reading the code.

```bash
scripts/arch-lint.sh                        # current directory
scripts/arch-lint.sh --path app/src/main    # one module
scripts/arch-lint.sh --format json          # machine-readable
scripts/arch-lint.sh --severity error       # strongly-recommended violations only
```

Exit code is `1` when any `error` finding is present, so it can gate CI. Test sources are
excluded from the rules that do not apply to them.

## Looking things up

The official knowledge base is available offline through the Android CLI — prefer it over
recalling from memory:

```bash
android docs search "UI state production"
android docs fetch "kb://android/topic/architecture/ui-layer/state-production"
```

Related official skills, when the task moves past architecture: `navigation-3` (navigation),
`adaptive` (window sizes and form factors), `testing-setup` (test infrastructure),
`migrate-xml-views-to-jetpack-compose`, `android-profiler`.

## Reference files

- `references/recommendations.md` — every rule, with ID, priority, and the mechanical fix.
- `references/layers.md` — layer contracts and canonical code shapes.
- `references/modularization.md` — module types, naming and dependency rules.
- `references/testing.md` — testing the architecture: fakes, StateFlow, what to cover.
