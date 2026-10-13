#!/usr/bin/env bash
# Run one Codex review round from the repo root, detached from the agent's Bash timeout.
#
# Usage: run-codex-review.sh <out-dir> <round> <prompt-file>
# Writes <out-dir>/round<N>.json (findings), .log (Codex chatter), .model, .exit, then .done.
# Tries the models in CODEX_REVIEW_MODELS in order; moves on only when a model is unavailable.
set -u
out=$1 n=$2 prompt=$3
here=$(cd "$(dirname "$0")" && pwd)
models=${CODEX_REVIEW_MODELS:-"gpt-6.1-sol gpt-6-astra"}
effort=${CODEX_REVIEW_EFFORT:-high}
base="$out/round$n"

rm -f "$base.done" "$base.json" "$base.exit"
rc=1
trap 'echo "$rc" > "$base.exit"; touch "$base.done"' EXIT
trap 'rc=143; exit' TERM INT

for m in $models; do
  echo "$m" > "$base.model"
  codex exec -s read-only --ephemeral -m "$m" -c model_reasoning_effort="$effort" \
    --output-schema "$here/../references/findings.schema.json" -o "$base.json" - \
    < "$prompt" > "$base.log" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && break
  grep -qiE "model is not supported|model_not_found|unknown model|does not exist" "$base.log" || break
done
