# Testing the architecture

Scope here is architecture-relevant testing only. For test infrastructure — runners, Robolectric,
CI wiring, screenshot tests — use the official `testing-setup` skill.

## What to test (`TEST-1`)

Unless the app is a hello-world, cover at minimum:

- **ViewModels**, including the Flows they expose.
- **Data layer** — repositories and data sources.
- **UI navigation**, as CI regression tests.

Good architecture is what makes this cheap: a ViewModel with no `Context` (`VM-1`) is a plain JVM
unit test, and a repository behind an interface (`DI-1`) is replaceable by a fake in one line.
If a unit test needs Robolectric or an emulator, that is usually an architecture finding, not a
testing one.

## Fakes, not mocks (`TEST-2`)

```kotlin
class FakeNewsRepository : NewsRepository {                 // NAME-4: Fake prefix
    private val news = MutableStateFlow(emptyList<News>())
    var refreshCount = 0
        private set

    override fun getNewsStream(): Flow<List<News>> = news
    override suspend fun refresh() { refreshCount++ }

    fun emit(items: List<News>) { news.value = items }      // test-only control surface
}
```

A fake is a real implementation of the interface with a simplified backing store. It survives
refactors that break every `whenever(...).thenReturn(...)` line, and it documents the contract.
Reach for a mocking framework only for third-party interfaces you cannot reasonably implement.

Put shared fakes in `:core:testing` (or a `testFixtures` source set) so feature tests reuse them.

## Testing StateFlow (`TEST-3`)

`WhileSubscribed` state only produces while something collects. Assert on `.value` with a
collector running:

```kotlin
@get:Rule val mainDispatcherRule = MainDispatcherRule()

@Test
fun `uiState emits success when news arrives`() = runTest {
    val repository = FakeNewsRepository()
    val viewModel = NewsViewModel(repository)

    backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect() }

    assertEquals(NewsUiState.Loading, viewModel.uiState.value)
    repository.emit(listOf(testNews))
    assertEquals(NewsUiState.Success(listOf(testNews)), viewModel.uiState.value)
}
```

`MainDispatcherRule` swaps `Dispatchers.Main` for a test dispatcher — needed because
`viewModelScope` runs on `Main`:

```kotlin
class MainDispatcherRule(
    private val dispatcher: TestDispatcher = UnconfinedTestDispatcher(),
) : TestWatcher() {
    override fun starting(description: Description) = Dispatchers.setMain(dispatcher)
    override fun finished(description: Description) = Dispatchers.resetMain()
}
```

Turbine (`NIA-6`) is an alternative when you need to assert on a *sequence* of emissions:

```kotlin
viewModel.uiState.test {
    assertEquals(NewsUiState.Loading, awaitItem())
    repository.emit(listOf(testNews))
    assertEquals(NewsUiState.Success(listOf(testNews)), awaitItem())
}
```

## Injecting dispatchers

Hardcoded `Dispatchers.IO` inside a data source cannot be controlled from a test. Inject it
(qualified, as in `@Dispatcher(IO)`) and pass the test dispatcher in. This is a `DI-1` consequence,
and the most common reason data-layer tests turn flaky.

## Testing the UI half

Because the screen composable is stateless (see `layers.md`), UI tests drive it directly with a
constructed `UiState` and lambdas — no ViewModel, no repository, no DI graph:

```kotlin
composeTestRule.setContent {
    NewsScreen(uiState = NewsUiState.Success(listOf(testNews)), onRefresh = {})
}
```

If a screen cannot be tested this way, the route/screen split (`UI-1`) is missing.
