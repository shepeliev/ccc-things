# Layer contracts and canonical shapes

Copy the *shape*, not the names. Match the project's existing package layout, DI style and
naming before reaching for anything here.

## Data layer

Responsibilities: own the data, decide where it comes from, resolve conflicts, expose it
immutably, hold business logic. It is the single source of truth (`LAYER-1`, `LAYER-3`).

### Data source — one per backing source, invisible outside the module

```kotlin
internal class NewsRemoteDataSource @Inject constructor(
    private val api: NewsApi,
    @Dispatcher(IO) private val ioDispatcher: CoroutineDispatcher,
) {
    suspend fun fetchNews(): List<NetworkNews> = withContext(ioDispatcher) { api.getNews() }
}

internal class NewsLocalDataSource @Inject constructor(private val dao: NewsDao) {
    fun getNewsStream(): Flow<List<NewsEntity>> = dao.observeAll()
    suspend fun upsert(news: List<NewsEntity>) = dao.upsertAll(news)
}
```

`internal` is what enforces `LAYER-3`. Without it the boundary is a convention nobody checks.

### Repository — the only type the layers above see

```kotlin
interface NewsRepository {
    fun getNewsStream(): Flow<List<News>>          // NAME-3: get{Model}Stream
    suspend fun refresh()
}

class DefaultNewsRepository @Inject constructor(   // NAME-4: Default prefix
    private val local: NewsLocalDataSource,
    private val remote: NewsRemoteDataSource,
) : NewsRepository {

    override fun getNewsStream(): Flow<List<News>> =
        local.getNewsStream().map { entities -> entities.map(NewsEntity::asDomain) }

    override suspend fun refresh() {
        local.upsert(remote.fetchNews().map(NetworkNews::asEntity))
    }
}
```

Reads resolve from local storage, the network only writes into it — that is `NIA-3`
offline-first. Streams out as `Flow`, actions as `suspend` (`LAYER-4`).

A repository wrapping a single data source with no added logic is still correct (`LAYER-1`);
a repository that only renames one method and is the *only* thing a ViewModel uses is worth
questioning in review.

## Domain layer — only when the reuse exists (`LAYER-5`)

One public operator function, named for what it does, no Android types:

```kotlin
class GetBookmarkedNewsUseCase @Inject constructor(
    private val newsRepository: NewsRepository,
    private val userDataRepository: UserDataRepository,
) {
    operator fun invoke(): Flow<List<News>> =
        combine(newsRepository.getNewsStream(), userDataRepository.bookmarksStream) { news, ids ->
            news.filter { it.id in ids }
        }
}
```

This one earns its place: it combines two repositories and more than one ViewModel needs it.
`class GetNewsUseCase(repo) { operator fun invoke() = repo.getNewsStream() }` does not.

## UI layer

### UI state — model the states the screen actually has

```kotlin
sealed interface NewsUiState {
    data object Loading : NewsUiState
    data class Success(val news: List<News>, val userMessage: String? = null) : NewsUiState
    data class Error(val retryable: Boolean) : NewsUiState
}
```

A data class with `isLoading`/`error`/`data` nullables is acceptable for simple screens, but
if three fields can never be set at once, a sealed interface is the honest model (`MODEL-1`).

### ViewModel

```kotlin
@HiltViewModel
class NewsViewModel @Inject constructor(
    private val newsRepository: NewsRepository,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    val uiState: StateFlow<NewsUiState> = newsRepository.getNewsStream()
        .map<List<News>, NewsUiState> { NewsUiState.Success(it) }
        .catch { emit(NewsUiState.Error(retryable = true)) }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = NewsUiState.Loading,
        )

    fun onRefresh() {
        viewModelScope.launch { newsRepository.refresh() }
    }
}
```

Checklist for every ViewModel: no `Context`/`Application`/`Resources` (`VM-1`), not
`AndroidViewModel` (`VM-5`), one `uiState` property (`VM-6`), `viewModelScope` only (`VM-2`),
screen-level (`VM-3`). Navigation arguments arrive through `SavedStateHandle`, not a `Context`.

For mutable local state instead of a stream:

```kotlin
private val _uiState = MutableStateFlow(EditorUiState())
val uiState: StateFlow<EditorUiState> = _uiState.asStateFlow()   // never expose the mutable one
```

### One-shot events are state, not events (`UI-4`)

```kotlin
// in the UiState
data class Success(val news: List<News>, val userMessage: String? = null)

// in the ViewModel
fun onMessageShown() { _uiState.update { it.copy(userMessage = null) } }

// in the composable
uiState.userMessage?.let { message ->
    LaunchedEffect(message) {
        snackbarHostState.showSnackbar(message)
        onMessageShown()
    }
}
```

This survives configuration changes and process death, which a `Channel` does not.

### Screen composable

```kotlin
@Composable
fun NewsRoute(viewModel: NewsViewModel = hiltViewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()   // UI-3
    NewsScreen(uiState = uiState, onRefresh = viewModel::onRefresh)  // UI-1: state down, events up
}

@Composable
fun NewsScreen(uiState: NewsUiState, onRefresh: () -> Unit) { /* stateless, previewable */ }
```

Split route (stateful, knows the ViewModel) from screen (stateless, takes state and lambdas).
The stateless half is what `@Preview` and UI tests use.

### Reusable components get plain state holders (`VM-4`)

```kotlin
@Stable
class SearchFieldState(initialQuery: String = "") {
    var query by mutableStateOf(initialQuery)
        private set
    fun onQueryChange(new: String) { query = new }
}

@Composable
fun rememberSearchFieldState(initialQuery: String = "") =
    remember { SearchFieldState(initialQuery) }
```

Never `hiltViewModel()` inside a component that more than one screen renders.

## Dependency injection (`DI-1`, `DI-3`)

```kotlin
@Module
@InstallIn(SingletonComponent::class)
abstract class DataModule {
    @Binds
    abstract fun bindsNewsRepository(impl: DefaultNewsRepository): NewsRepository
}
```

Bind the interface, inject the interface. That is what makes `TEST-2` fakes possible without a
mocking framework. Scope only what holds shared mutable state or is expensive (`DI-2`).

## Lifecycle work (`LIFE-1`)

```kotlin
LifecycleStartEffect(Unit) {
    locationProvider.start()
    onStopOrDispose { locationProvider.stop() }
}

LaunchedEffect(Unit) {
    lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) { /* async work while resumed */ }
}
```

Not `override fun onResume()` in the `Activity`.
