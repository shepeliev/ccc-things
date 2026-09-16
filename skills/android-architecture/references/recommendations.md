# Android architecture rules

Every rule has a stable ID, a priority tag, and a mechanical fix. `arch-lint.sh` emits these IDs.

Priorities: **SR** strongly recommended (official) · **R** recommended (official) ·
**O** optional (official) · **NiA** Now in Android practice, not official — propose, don't impose.

Source for SR/R/O: [Recommendations for Android architecture](https://developer.android.com/topic/architecture/recommendations)
and the [Guide to app architecture](https://developer.android.com/topic/architecture).

---

## Layers

### LAYER-1 · SR · Use a clearly defined data layer
The data layer exposes application data and holds the bulk of business logic. Create repositories
even when a repository wraps a single data source. Small apps: a `data` package is enough.

### LAYER-2 · SR · Use a clearly defined UI layer
The UI layer displays data and is the point of user interaction. Small apps: a `ui` package.

### LAYER-3 · SR · Expose data only through repositories
Composables and ViewModels must not touch data sources directly — no Room DAO, Retrofit service,
`DataStore`, `SharedPreferences`, Firebase client, `LocationManager`, `BluetoothAdapter` or
connectivity provider above the data layer.

**Fix:** move the call into a data source, put a repository in front of it, inject the repository
into the ViewModel. Mark data sources `internal` so the boundary is enforced by the compiler.

### LAYER-4 · SR · Use coroutines and flows between layers
Streams as `Flow`, one-shot work as `suspend` functions. No `LiveData` in new code, no callbacks
across layer boundaries, no `runBlocking` in production code.

### LAYER-5 · R (big apps) · Use a domain layer
Add use cases when business logic that touches the data layer is reused across ViewModels, or when
one ViewModel's logic has grown unwieldy. **Not before.** A use case that only forwards one call to
one repository is noise.

---

## UI layer

### UI-1 · SR · Follow Unidirectional Data Flow
State flows down, events flow up. ViewModels expose state via the observer pattern and receive
actions as method calls.

**Fix:** replace UI-mutated shared state with a ViewModel method that updates `uiState`.

### UI-2 · SR · Use AAC ViewModels
Use `androidx.lifecycle.ViewModel` to hold business logic and expose UI state.

### UI-3 · SR · Collect state lifecycle-aware
Use `collectAsStateWithLifecycle()`, not `collectAsState()`, for Flows in composables.

```kotlin
val uiState by viewModel.uiState.collectAsStateWithLifecycle()
```

**Fix:** swap the call, add `androidx.lifecycle:lifecycle-runtime-compose`.

### UI-4 · SR · Do not send events from the ViewModel to the UI
No `Channel`, no `MutableSharedFlow` of one-shot events. Handle the event in the ViewModel and
express the result as a state change.

**Fix:** model the outcome in `uiState` (for example `snackbarMessage: String?` or a
`navigateTo: Destination?` field) plus a `fun onMessageShown()` the UI calls to clear it.

### UI-5 · SR · Use a single-activity application
Navigate with Navigation 3 between screens; deep-link into destinations. Multiple `Activity`
classes are a smell unless they are launcher/share/widget entry points.

### UI-6 · SR · Use Jetpack Compose
For new apps on phones, tablets, foldables and Wear OS. Existing View code is not a defect;
mixing new Views into a Compose codebase is.

---

## ViewModel

### VM-1 · SR · Keep ViewModels free of the Android lifecycle
No `Context`, `Activity`, `Resources`, `Application`, `View` or `Fragment` reference — as a
constructor parameter, a field, or a captured value.

**Fix:** move the dependency down (a repository that owns the `Context`) or up (resolve strings
and resources in the composable from a state field such as a string resource ID).

### VM-2 · SR · Use coroutines and flows
Receive data as `Flow`, perform actions in `suspend` functions launched in `viewModelScope`.
Never `GlobalScope`, never `runBlocking`.

### VM-3 · SR · ViewModels at screen level only
Screen-level composables, navigation destinations or graphs. Not inside reusable components.
For a complex composable that genuinely needs its own scope, use `rememberViewModelStoreOwner()`
to scope the ViewModel to that call site.

### VM-4 · SR · Plain state holder classes in reusable UI
Reusable components get a plain state holder class whose state can be hoisted and controlled
from outside.

### VM-5 · R · Do not use `AndroidViewModel`
Use `ViewModel`. Don't put `Application` in a ViewModel.

**Fix:** extend `ViewModel` and move the `Application`-dependent work into the UI or data layer.

### VM-6 · R · Expose a single `uiState`
One property, named `uiState`, typed `StateFlow<${Screen}UiState>`. For stream-backed state use
`stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initialValue)`. For simpler cases a
private `MutableStateFlow` exposed as an immutable `StateFlow` is fine. `${Screen}UiState` may be a
data class or a sealed class.

**Fix:** never expose `MutableStateFlow` or a `var` publicly — expose `.asStateFlow()`.

---

## Lifecycle

### LIFE-1 · SR · Lifecycle-aware effects, not `Activity` callbacks
Don't override `onResume`/`onPause`/`onStart`/`onStop` for app logic. Use `LifecycleStartEffect`,
`LifecycleResumeEffect`, `repeatOnLifecycle`, or `collectAsStateWithLifecycle`.

---

## Dependencies

### DI-1 · SR · Use dependency injection
Constructor injection wherever possible. No service locators reached through static singletons, no
`object` graphs constructed inside ViewModels.

### DI-2 · SR · Scope deliberately
Scope a type to a container when it holds mutable shared data or is expensive to create and widely
used. Everything else stays unscoped.

### DI-3 · R · Use Hilt
Use Hilt once the project has several screens with ViewModels, uses WorkManager, or scopes
ViewModels to the navigation back stack. Manual DI is correct for simple apps.

---

## Models

### MODEL-1 · R · A model per layer in complex apps
Network models map to domain/data models; DAO entities map to data classes; `UiState` holds what
the screen renders. In a small app, one shared model is fine — mapping layers you don't need is
cost without benefit.

---

## Testing

### TEST-1 · SR · Know what to test
At minimum: ViewModel unit tests including Flows, data layer unit tests for repositories and data
sources, and UI navigation tests as CI regression tests.

### TEST-2 · SR · Prefer fakes to mocks
Use hand-written fakes implementing the same interface. Mocking frameworks re-assert the
implementation you already wrote.

### TEST-3 · SR · Test StateFlows
Assert on `.value` where possible, and account for `WhileSubscribed` needing a collector.

---

## Naming (official, Optional)

- **NAME-1 · O** — methods are verb phrases: `makePayment()`.
- **NAME-2 · O** — properties are noun phrases: `inProgressTopicSelection`.
- **NAME-3 · O** — streams are `get{Model}Stream()`, plural for lists: `getAuthorsStream(): Flow<List<Author>>`.
- **NAME-4 · O** — implementations get meaningful names; `Default` prefix as fallback, `Fake` prefix for test doubles: `DefaultAuthorsRepository`, `FakeAuthorsRepository`.

---

## Now in Android practices (not official)

These come from the [Now in Android](https://github.com/android/nowinandroid) sample. They are
opinions, not rules. Propose them with a reason; drop them if the project disagrees.

### NIA-1 · NiA · Module taxonomy
`:app` (entry point, navigation host) → `:feature:*` (one user journey each) → `:core:*`
(`data`, `database`, `network`, `model`, `ui`, `designsystem`, `common`, `testing`).
Core never depends on feature or app. See `modularization.md`.

### NIA-2 · NiA · `api` / `impl` split for features
`:feature:x:api` exposes only navigation keys; `:feature:x:impl` holds UI, ViewModels and logic.
A feature's `impl` may depend on another feature's `api`, never on its `impl`. Worth the ceremony
only with multiple teams.

### NIA-3 · NiA · Offline-first data layer
Local storage is the single source of truth; the network is a synchronisation input, not a read
path. Reads always resolve from disk, so the UI works with no connection.

### NIA-4 · NiA · Wrap async results
A `Result`-style wrapper (`Loading` / `Success` / `Error`) at the repository or a `asResult()`
Flow operator, so `uiState` models error and loading explicitly instead of nullable fields.

### NIA-5 · NiA · Gradle convention plugins
Move shared Gradle configuration into `build-logic` convention plugins instead of duplicating or
using `subprojects {}`. Pays off from roughly five modules upward.

### NIA-6 · NiA · Turbine for Flow tests
`turbine` for asserting on Flow emissions, with a `MainDispatcherRule` swapping in a test
dispatcher.
