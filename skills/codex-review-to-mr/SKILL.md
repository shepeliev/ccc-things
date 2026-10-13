---
name: codex-review-to-mr
description: Use when a development branch is finished and its tests pass — in particular when superpowers:finishing-a-development-branch reaches its merge / PR / keep menu — or when the user asks for a Codex review loop before a merge request or pull request.
argument-hint: "[base branch; default: the branch's fork point]"
---

# codex-review-to-mr

This skill takes a finished branch to a ready merge request. Codex reviews the branch. You check
each finding, fix the real ones, and ask Codex again. Then you open the MR and tell the user.

It replaces Steps 4-5 of superpowers:finishing-a-development-branch. Do not show that menu.

**REQUIRED SUB-SKILL:** superpowers:receiving-code-review for the triage in step 3.

## 1. Prepare

1. Confirm the full test suite passed on HEAD (finishing Step 1). If not, run it. Stop on red.
   "Full" means the project's done bar (AGENTS.md / CLAUDE.md), not only the unit tests.
2. Commit or stop: `git status --porcelain` must be empty. Do not stash the user's work.
3. Find the base (the plan, the conversation, or the upstream). Run `git fetch origin`.
   Set `MERGE_BASE=$(git merge-base origin/<base> HEAD)`.
4. Set `OUT="$(git rev-parse --absolute-git-dir)/codex-review"` and create it. It stays out of
   the commits and is separate for each worktree.
5. Find the spec and the plan of this work (`docs/**/specs`, `docs/**/plans`, the paths that
   brainstorming and writing-plans gave). Write the goal in 1-3 sentences.

## 2. Run a Codex round

1. Write `$OUT/round<N>-prompt.md` from `references/prompt-template.md` in this skill's directory. Fill every
   `{{…}}`. For round 1, `{{EARLIER_ROUNDS}}` is "None." From round 2, list each earlier finding
   with its id, title, and your verdict: fixed (commit sha) or rejected (one-line reason).
2. Start it detached. A round takes 5-20 minutes, more than the Bash timeout:
   ```bash
   nohup <this skill's directory>/scripts/run-codex-review.sh "$OUT" <N> "$OUT/round<N>-prompt.md" >/dev/null 2>&1 &
   ```
   Run it from the repo root. The script tries `gpt-6.1-sol`, then `gpt-6-astra`, at `high` effort.
   It moves to the next model only when a model is unavailable.
3. Wait with one Monitor (`timeout_ms` 1800000). Re-arm it when it expires:
   ```bash
   until [ -f "$OUT/round<N>.done" ]; do sleep 20; done; echo "round <N> exit=$(cat "$OUT/round<N>.exit") model=$(cat "$OUT/round<N>.model")"
   ```
4. If `exit` is not 0, read the tail of `round<N>.log`. Retry once for a transient error. Then
   stop and report. Do not open the MR without a review.

## 3. Triage every finding

Read `round<N>.json`. Give each finding exactly one verdict:

| Verdict | Condition | Action |
|---|---|---|
| REAL | You traced the trigger through the real callers and it happens | Fix it |
| NOT REACHABLE | No real caller, input, or state order reaches it | Reject, give the reason |
| WRONG | The code already handles it, or Codex misread the code | Reject, cite the line |
| OUT OF SCOPE | Real, but in code the branch did not touch or make reachable | List it in the MR as a follow-up |

Rules:

- Open the file at the line. Trace the trigger yourself. Codex's confidence is not evidence.
- Use the project's tests and tools to prove a doubtful case (a failing test, a quick probe).
- A REAL finding gets a failing test first when the behaviour is testable
  (superpowers:test-driven-development).
- A spec deviation is REAL unless the user approved it in this conversation.

## 4. Fix and repeat

1. Fix the REAL findings. Follow the user's and the project's rules for who writes the code.
2. Run the full test suite. Stop on red that you cannot fix.
3. Commit: `fix: address codex review round <N>` (or the project's commit convention).
4. Append the round to `$OUT/review-log.md`: model, each finding, verdict, commit.
5. Start the next round (step 2).

Stop the loop when one of these is true:

- Codex returns `clean`, or every finding of the round is NOT REACHABLE, WRONG, or OUT OF SCOPE.
- Round 5 is done. Its fixes get no further Codex round; say so in the MR.

## 5. Screenshots, if the change is visual

The change is visual if the diff changes what a user sees: UI code (Compose, SwiftUI, views,
layouts, web components, styles), strings on screen, icons, or images.

Find the screenshot tool in this order. Use the first that works:

1. Project instructions and project skills (AGENTS.md, CLAUDE.md, a `ui-parity`, `roborazzi` or
   `run` skill).
2. Screenshot tests in the build: Roborazzi, Paparazzi, Compose Preview Screenshot Testing,
   swift-snapshot-testing, Playwright or Storybook snapshots.
3. The running app: `adb exec-out screencap -p`, `xcrun simctl io booted screenshot` (or the
   iOS Simulator tool), browser screenshots for web.

Do not add test code after the last Codex round. If a changed screen has no screenshot test,
capture it from the running app (item 3).

Capture every changed screen after the change. Capture the base too when the tool does it cheaply
(Roborazzi compare images, a base-branch run). Put the files in `$OUT/screenshots/`.

If no tool works, stop before the MR. Tell the user which tools fit this project, recommend one,
and wait for the answer.

## 6. Open the MR

1. Push: `git push -u origin <branch>`. Never force-push without the user.
2. Title: the project's convention. With squash merges, use a conventional commit subject.
3. Description, in this order: Summary (goal and spec link), Changes, Tests (commands and
   results), Screenshots, Codex review, Follow-ups (OUT OF SCOPE findings).
   Codex review = a table (round, model, findings, fixed, rejected) and each rejected finding with
   its one-line reason.
4. Create it with the forge of `origin`:
   - GitLab: `glab mr create --source-branch <branch> --target-branch <base> --title … --description …`.
     Upload each screenshot first:
     `curl -sf -H "PRIVATE-TOKEN: $(glab config get token --host <host>)" -F "file=@<png>" https://<host>/api/v4/projects/<url-encoded path>/uploads`.
     Put the returned `markdown` in the description. `glab api -F file=@` returns 400.
     If `glab` is not authenticated, use another GitLab client you have (a GitLab MCP server),
     then tell the user to run `glab auth login`.
   - GitHub: `gh pr create --base <base> --title … --body-file …`. GitHub has no upload API: push
     the images to an orphan branch `pr-assets/<branch>` and link their `?raw=true` URLs. Then
     bind the PR with the ccd_pr tools if they are available.
5. Do not merge and do not arm auto-merge. That is the user's decision.

## 7. Tell the user

1. Send `PushNotification`: `MR ready: <url> — Codex <rounds> rounds, <fixed> fixed, <rejected> rejected`.
   If the tool is not available, the reply in item 2 is the notice.
2. In the reply, give the MR link, the rounds table, the rejected findings with reasons, the
   follow-ups, and the screenshots. Keep the worktree.

## Common mistakes

| Mistake | Correct action |
|---|---|
| `codex exec review --base X "prompt"` | It rejects a prompt with `--base`. Use `scripts/run-codex-review.sh`. |
| Run Codex in the foreground Bash call | The Bash timeout kills it. Use nohup and a Monitor. |
| Fix every finding Codex gives | Trace each one. Reject what no real path reaches. |
| Reject a finding with "unlikely" | Name the reason: no caller, guarded at line X, or input never reaches it. |
| Leave rejected findings out of the next prompt | Codex reports them again. List them with reasons. |
| Round 6 because round 5 found something | The limit is 5. Report the unreviewed fixes in the MR. |
| Open the MR with no screenshots for a UI change | Find a tool, or ask the user. |
