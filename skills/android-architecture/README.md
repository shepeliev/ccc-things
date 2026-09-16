# android-architecture

Decide where Android code belongs, scaffold feature slices, and review Kotlin/Android code against
the [official architecture recommendations](https://developer.android.com/topic/architecture/recommendations).

Google's official [`android` CLI](https://developer.android.com/studio/command-line) already ships
24 skills (`adaptive`, `navigation-3`, `testing-setup`, `android-profiler`, …) — this one fills the
gap they leave rather than duplicating them. `android skills find architecture` returns nothing.

## What it does beyond restating the docs

- **Reads the project first.** Detects module shape, Compose vs Views, DI style and existing
  conventions, then conforms to them. A consistent codebase beats an ideal one.
- **Gives a decision procedure**, not prose: a table mapping "code that does X" to the layer and
  type it belongs in, plus the two directional rules that catch most violations.
- **Refuses to gold-plate.** Explicit sizing guidance — use cases, `api`/`impl` module splits and
  per-layer mappers are defects in a five-screen app, and the skill says so.
- **Cites rules by ID.** Every recommendation has a stable ID and priority tag (`SR`/`R`/`O`
  official, `NiA` for Now in Android practice), so findings are traceable and opinions are
  labelled as opinions.
- **Ships a deterministic linter**, below.

Reference files, loaded on demand: `recommendations.md` (every rule + its fix), `layers.md`
(canonical code shapes), `modularization.md`, `testing.md`.

## arch-lint

```bash
scripts/arch-lint.sh --path <dir>
scripts/arch-lint.sh --format json --severity error
scripts/arch-lint.sh --list-rules
```

POSIX `sh` + `grep` + `awk`, no dependencies. Exit code `1` when error-severity findings exist, so
it can gate CI. Scans ~450 Kotlin files in about two seconds.

Rules: `LAYER-3`, `LAYER-4`, `UI-3`, `UI-4`, `UI-5`, `VM-1`, `VM-2`, `VM-3`, `VM-5`, `VM-6`,
`LIFE-1`, `TEST-2`.

Context-aware, to keep the noise down: test source sets and `build/` output are excluded; data-layer
code is allowed to import Room and Retrofit; `LIFE-1` only applies to activities that actually host
Compose content; the LiveData check only fires in codebases that have genuinely adopted Compose.

It reports **candidates, not verdicts** — grep cannot see context, so every hit needs confirming.
