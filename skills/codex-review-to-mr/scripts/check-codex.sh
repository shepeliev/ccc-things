#!/usr/bin/env bash
# Check that Codex can review this repository: the CLI is on PATH and its read-only sandbox can
# run commands here. Codex gets only the prompt and reads the branch itself with git and cat, so
# a sandbox that cannot run commands (bubblewrap under WSL) leaves it blind.
#
# Usage: check-codex.sh   (from inside the repository)
# Exit 0: use Codex. Exit 1, with the reason on stderr: use the other reviewer.
set -u

if ! command -v codex >/dev/null 2>&1; then
  echo "codex is not on PATH" >&2
  exit 1
fi
if ! root=$(git rev-parse --show-toplevel 2>/dev/null) || ! cd "$root"; then
  echo "not inside a git repository" >&2
  exit 1
fi
# The probe reads git state and a tracked file, as a review does. `codex sandbox` uses the same
# sandbox as `codex exec` (seatbelt on macOS, bubblewrap on Linux) and passes the exit code
# through. stderr is dropped: on macOS it carries harmless xcrun and DARWIN_USER_TEMP_DIR warnings.
# shellcheck disable=SC2016 # the sandboxed shell expands $(...), not this one
probe='git rev-parse --verify --quiet HEAD && head -c 1 "$(git -c core.quotePath=false ls-files | head -n 1)"'
if ! codex sandbox -- sh -c "$probe" >/dev/null 2>&1; then
  echo "the codex sandbox cannot run read-only commands here" >&2
  exit 1
fi
