# codex-review-to-mr

Take a finished branch to a ready merge request, with OpenAI Codex as the reviewer and Claude as
the judge of what Codex finds.

It is built for the end of a [superpowers](https://github.com/obra/superpowers) cycle
(brainstorm → spec → plan → execution). Where `finishing-a-development-branch` would ask
"merge, PR, or keep?", this skill takes over:

1. Codex reviews `git diff <merge-base>...HEAD` with a custom prompt: the goal, the spec and plan,
   what to look for, and a **reachability rule** — every finding must name the real caller and
   input that trigger it.
2. Claude traces each finding through the code and gives it one verdict: REAL (fixed, test first),
   NOT REACHABLE or WRONG (rejected with a reason), or OUT OF SCOPE (a follow-up in the MR).
3. Rejected findings go back into the next round's prompt, so Codex does not raise them again.
   The loop stops at a clean round, a round with nothing real, or after 5 rounds.
4. For a visual change, Claude takes screenshots with the project's own tool (Roborazzi,
   Paparazzi, snapshot tests, Playwright, `adb`, `simctl`). With no tool, it stops and proposes one.
5. It pushes, opens the GitLab MR or GitHub PR with the review table in the description, and
   sends a push notification. It does not merge.

## Requirements

- Claude Code (the skill uses its `Monitor` and `PushNotification` tools).
- [Codex CLI](https://github.com/openai/codex), signed in. Models: `gpt-6.1-sol`, falling back to
  `gpt-6-astra`, at `high` effort. Override with `CODEX_REVIEW_MODELS="m1 m2"` and
  `CODEX_REVIEW_EFFORT=…`.
- `glab` for GitLab or `gh` for GitHub.

## Making it automatic

A skill cannot change another skill's menu, so add this rule to your user instructions
(`~/.claude/CLAUDE.md` or a file in `~/.claude/rules/`):

```markdown
## Finishing a branch: Codex review loop, then MR

When superpowers:finishing-a-development-branch passes its test step and reaches "Present Options",
do not show the menu. Invoke the `codex-review-to-mr` skill instead. It runs the Codex review
loop, opens the merge request, and notifies the user. This applies in every project.

Show the original menu only in these cases:

- The user asked in this conversation to merge locally, to keep the branch, or to skip the review.
- `origin` has no GitLab or GitHub remote.
```

Without the rule, invoke it by hand: `/codex-review-to-mr [base-branch]`.

## Files

- `scripts/run-codex-review.sh` runs one round detached from the agent's shell timeout and writes
  `round<N>.json`, `.log`, `.model`, `.exit`, `.done` under `<git-dir>/codex-review/`.
- `references/prompt-template.md` is the review prompt with `{{…}}` placeholders.
- `references/findings.schema.json` is the JSON schema Codex must answer in (`--output-schema`).

A round on a ~800-line diff took about 3.5 minutes and 145k Codex tokens.
