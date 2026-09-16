#!/bin/sh
# arch-lint.sh — grep-based Android architecture checks.
#
# Reports CANDIDATES, not verdicts. Every hit must be confirmed by reading the code.
# Rule IDs map to references/recommendations.md.
#
# Exit codes: 0 no error-severity findings, 1 error-severity findings present, 2 bad usage.

ROOT="."
FORMAT="text"
MIN_SEV="info"

usage() {
    cat <<'USAGE'
Usage: arch-lint.sh [--path DIR] [--format text|json] [--severity error|warn|info] [--list-rules]

  --path DIR        directory to scan (default: current directory)
  --format FORMAT   text (default) or json
  --severity LEVEL  minimum severity to report: error, warn, info (default: info)
  --list-rules      print the rules this script checks and exit

Findings are candidates produced by pattern matching. Confirm each one in the source
before reporting it. Rule IDs are documented in references/recommendations.md.
USAGE
}

list_rules() {
    cat <<'RULES'
error  LAYER-3  data-source type used above the data layer
error  UI-3     collectAsState() instead of collectAsStateWithLifecycle()
error  UI-4     one-shot event stream emitted from a ViewModel
error  VM-1     Context / Application / Resources held by a ViewModel
error  VM-2     GlobalScope used instead of viewModelScope
error  VM-6     mutable state exposed publicly from a ViewModel
warn   LAYER-4  runBlocking in production code
warn   LIFE-1   Activity lifecycle callback overridden (Compose projects)
warn   UI-5     more than one activity declared in a manifest
warn   VM-3     ViewModel obtained inside a reusable component
warn   VM-5     AndroidViewModel used instead of ViewModel
info   LAYER-4  LiveData in a codebase that should use Flow
info   TEST-2   mocking framework declared; prefer hand-written fakes
RULES
}

while [ $# -gt 0 ]; do
    case "$1" in
        --path)     ROOT="$2"; shift 2 ;;
        --path=*)   ROOT="${1#*=}"; shift ;;
        --format)   FORMAT="$2"; shift 2 ;;
        --format=*) FORMAT="${1#*=}"; shift ;;
        --severity) MIN_SEV="$2"; shift 2 ;;
        --severity=*) MIN_SEV="${1#*=}"; shift ;;
        --list-rules) list_rules; exit 0 ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "arch-lint: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
    esac
done

[ -d "$ROOT" ] || { echo "arch-lint: not a directory: $ROOT" >&2; exit 2; }
case "$FORMAT" in text|json) ;; *) echo "arch-lint: bad --format '$FORMAT'" >&2; exit 2 ;; esac
case "$MIN_SEV" in error|warn|info) ;; *) echo "arch-lint: bad --severity '$MIN_SEV'" >&2; exit 2 ;; esac

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM

FINDINGS="$TMP/findings.tsv"
: > "$FINDINGS"

PRUNE="! -path */build/* ! -path */.git/* ! -path */.gradle/* ! -path */generated/*"

# --- file sets ----------------------------------------------------------------

# Production Kotlin/Java sources: test source sets excluded.
# shellcheck disable=SC2086
find "$ROOT" -type f \( -name '*.kt' -o -name '*.java' \) $PRUNE \
    ! -path '*/src/test/*' ! -path '*/src/androidTest/*' ! -path '*/src/testFixtures/*' \
    ! -path '*/src/*Test/*' -print0 > "$TMP/main.z" 2>/dev/null

# ViewModels: by filename, plus anything that actually extends ViewModel.
# shellcheck disable=SC2086
find "$ROOT" -type f -name '*ViewModel*.kt' $PRUNE \
    ! -path '*/src/test/*' ! -path '*/src/androidTest/*' -print0 > "$TMP/vm.z" 2>/dev/null
if [ -s "$TMP/main.z" ]; then
    xargs -0 grep -lE ':[[:space:]]*(Android)?ViewModel[[:space:]]*\(' < "$TMP/main.z" 2>/dev/null \
        | tr '\n' '\0' >> "$TMP/vm.z"
fi
tr '\0' '\n' < "$TMP/vm.z" | sort -u | grep -v '^$' | tr '\n' '\0' > "$TMP/vm-uniq.z"
mv "$TMP/vm-uniq.z" "$TMP/vm.z"

# Composable sources, and the subset living in reusable-component packages.
if [ -s "$TMP/main.z" ]; then
    xargs -0 grep -lE '@Composable' < "$TMP/main.z" 2>/dev/null | tr '\n' '\0' > "$TMP/compose.z"
fi
[ -f "$TMP/compose.z" ] || : > "$TMP/compose.z"
tr '\0' '\n' < "$TMP/compose.z" \
    | grep -E '/(components?|designsystem|widgets?|common/ui)/' \
    | tr '\n' '\0' > "$TMP/reusable.z" 2>/dev/null
[ -f "$TMP/reusable.z" ] || : > "$TMP/reusable.z"

# Is Compose actually adopted, or is there a single experimental file? Rules that only make
# sense in a Compose codebase are gated on adoption, not on mere presence.
main_count=$(tr -dc '\0' < "$TMP/main.z" | wc -c | tr -d ' ')
compose_count=$(tr -dc '\0' < "$TMP/compose.z" | wc -c | tr -d ' ')
COMPOSE_ADOPTED=no
if [ "${compose_count:-0}" -ge 5 ] && [ "${main_count:-0}" -gt 0 ] &&
   [ $(( compose_count * 100 / main_count )) -ge 10 ]; then
    COMPOSE_ADOPTED=yes
fi

# --- helpers ------------------------------------------------------------------

# scan <file-set> <severity> <rule> <ere> <message>
scan() {
    set_file="$1"; sev="$2"; rule="$3"; pattern="$4"; msg="$5"
    [ -s "$set_file" ] || return 0
    xargs -0 grep -HnE "$pattern" < "$set_file" 2>/dev/null \
        | awk -v sev="$sev" -v rule="$rule" -v msg="$msg" -F: '
            NF >= 3 {
                file = $1; line = $2;
                printf "%s\t%s\t%s\t%s\t%s\n", sev, rule, file, line, msg
            }' >> "$FINDINGS"
    return 0
}

# --- rules --------------------------------------------------------------------

# LAYER-3 — data-source types reached from the UI layer.
DATA_SOURCE_IMPORTS='^[[:space:]]*import[[:space:]]+(androidx\.room|retrofit2|androidx\.datastore|okhttp3|io\.ktor\.client|com\.google\.firebase|android\.content\.SharedPreferences|android\.location\.LocationManager|android\.bluetooth|androidx\.sqlite)'
scan "$TMP/vm.z" error LAYER-3 "$DATA_SOURCE_IMPORTS" \
    "ViewModel reaches a data source directly; go through a repository"
scan "$TMP/compose.z" error LAYER-3 "$DATA_SOURCE_IMPORTS" \
    "composable reaches a data source directly; go through a repository"

# UI-3 — lifecycle-unaware state collection.
scan "$TMP/compose.z" error UI-3 'collectAsState[[:space:]]*\(' \
    "use collectAsStateWithLifecycle() instead of collectAsState()"

# UI-4 — one-shot events pushed from the ViewModel to the UI.
scan "$TMP/vm.z" error UI-4 '(Channel[[:space:]]*<|MutableSharedFlow[[:space:]]*<|\.receiveAsFlow\(|\.asSharedFlow\()' \
    "ViewModel emits events to the UI; model the outcome in uiState instead"

# VM-1 — Android lifecycle types inside a ViewModel.
scan "$TMP/vm.z" error VM-1 '(:[[:space:]]*(Context|Application|Resources|Activity|Fragment)([[:space:]]*[,)=]|[[:space:]]*$)|@ApplicationContext|@ActivityContext)' \
    "ViewModel holds an Android lifecycle type; move the dependency to the UI or data layer"

# VM-2 — coroutine scope misuse.
scan "$TMP/main.z" error VM-2 'GlobalScope[[:space:]]*\.' \
    "GlobalScope escapes lifecycle management; use viewModelScope or an injected scope"

# VM-6 — public mutable state.
scan "$TMP/vm.z" error VM-6 '^[[:space:]]*(public[[:space:]]+)?(val|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*Mutable(StateFlow|SharedFlow|LiveData)' \
    "mutable state exposed publicly breaks UDF (UI-1); expose .asStateFlow()"

# LAYER-4 — blocking calls and legacy stream types.
scan "$TMP/main.z" warn LAYER-4 'runBlocking[[:space:]]*[({]' \
    "runBlocking in production code; suspend the caller instead"
# LiveData is only worth flagging in a Compose codebase; in a Views app it is idiomatic.
if [ "$COMPOSE_ADOPTED" = yes ]; then
    scan "$TMP/main.z" info LAYER-4 '(^[[:space:]]*import[[:space:]]+androidx\.lifecycle\.(Mutable)?LiveData|:[[:space:]]*(Mutable)?LiveData[[:space:]]*<)' \
        "LiveData used for cross-layer communication; prefer Flow/StateFlow"
fi

# LIFE-1 — Activity lifecycle callbacks instead of lifecycle-aware effects.
# shellcheck disable=SC2086
find "$ROOT" -type f -name '*Activity.kt' $PRUNE ! -path '*/src/*Test/*' -print0 \
    > "$TMP/activity.z" 2>/dev/null
if [ -s "$TMP/activity.z" ]; then
    xargs -0 grep -lE 'setContent[[:space:]]*[({]' < "$TMP/activity.z" 2>/dev/null \
        | tr '\n' '\0' > "$TMP/compose-activity.z"
fi
[ -f "$TMP/compose-activity.z" ] || : > "$TMP/compose-activity.z"
scan "$TMP/compose-activity.z" warn LIFE-1 'override[[:space:]]+fun[[:space:]]+(onResume|onPause|onStart|onStop)[[:space:]]*\(' \
    "Compose host activity: use LifecycleStartEffect/LifecycleResumeEffect/repeatOnLifecycle"

# VM-3 — ViewModel pulled into a reusable component.
scan "$TMP/reusable.z" warn VM-3 '(hiltViewModel|viewModel)[[:space:]]*\(' \
    "reusable component obtains a ViewModel; hoist state or use a plain state holder (VM-4)"

# VM-5 — AndroidViewModel.
scan "$TMP/main.z" warn VM-5 ':[[:space:]]*AndroidViewModel[[:space:]]*\(' \
    "use ViewModel, not AndroidViewModel; move Application out of the ViewModel"

# UI-5 — more than one activity per manifest.
# shellcheck disable=SC2086
find "$ROOT" -type f -name 'AndroidManifest.xml' $PRUNE ! -path '*/src/*Test/*' -print0 \
    > "$TMP/manifests.z" 2>/dev/null
if [ -s "$TMP/manifests.z" ]; then
    tr '\0' '\n' < "$TMP/manifests.z" | while IFS= read -r manifest; do
        [ -n "$manifest" ] || continue
        count=$(grep -cE '<activity[[:space:]]' "$manifest" 2>/dev/null)
        case "$count" in ''|*[!0-9]*) count=0 ;; esac
        if [ "$count" -gt 1 ]; then
            line=$(grep -nE '<activity[[:space:]]' "$manifest" 2>/dev/null | sed -n '2p' | cut -d: -f1)
            printf 'warn\tUI-5\t%s\t%s\t%s\n' "$manifest" "${line:-1}" \
                "$count activities declared; prefer a single-activity app with Navigation" \
                >> "$FINDINGS"
        fi
    done
fi

# TEST-2 — mocking frameworks.
# shellcheck disable=SC2086
find "$ROOT" -type f \( -name 'build.gradle.kts' -o -name 'build.gradle' -o -name 'libs.versions.toml' \) \
    $PRUNE -print0 > "$TMP/gradle.z" 2>/dev/null
scan "$TMP/gradle.z" info TEST-2 '(mockito|mockk|io\.mockk)' \
    "mocking framework declared; prefer hand-written fakes for your own interfaces"

# --- output -------------------------------------------------------------------

sort -u "$FINDINGS" > "$TMP/sorted.tsv" && mv "$TMP/sorted.tsv" "$FINDINGS"

awk -F'\t' -v min="$MIN_SEV" -v fmt="$FORMAT" '
    function rank(s) { return s == "error" ? 3 : (s == "warn" ? 2 : 1) }
    function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    BEGIN { minr = rank(min); n = 0; errors = 0; if (fmt == "json") printf "{\"findings\":[" }
    rank($1) < minr { next }
    {
        n++
        if ($1 == "error") errors++
        if (fmt == "json") {
            printf "%s\n  {\"severity\":\"%s\",\"rule\":\"%s\",\"file\":\"%s\",\"line\":%s,\"message\":\"%s\"}",
                   (n > 1 ? "," : ""), $1, $2, esc($3), $4, esc($5)
        } else {
            printf "%s:%s: [%s] %s %s\n", $3, $4, toupper($1), $2, $5
        }
    }
    END {
        if (fmt == "json") {
            printf "%s],\"summary\":{\"total\":%d,\"errors\":%d}}\n", (n ? "\n" : ""), n, errors
        } else if (n == 0) {
            print "arch-lint: no findings at severity >= " min
        } else {
            printf "\narch-lint: %d finding(s), %d at error severity. Confirm each before reporting.\n", n, errors
        }
        exit (errors > 0 ? 1 : 0)
    }
' "$FINDINGS"
