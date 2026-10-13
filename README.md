# ccc-things

Agent skills, installable with [`npx skills`](https://github.com/vercel-labs/skills). No plugin
install, no global setup — a skill can be committed straight into the project that needs it, and
every teammate gets it with `git pull`.

## Skills

| Skill | What it does |
|---|---|
| [`android-architecture`](skills/android-architecture) | Decide where Android code belongs, scaffold feature slices, and review Kotlin/Android code against the official Android architecture recommendations. Ships a dependency-free architecture linter. |
| [`codex-review-to-mr`](skills/codex-review-to-mr) | Finish a branch with a Codex review loop: Claude checks each finding against the real code, fixes the real ones, repeats up to 5 rounds, takes screenshots of visual changes, and opens the MR/PR. Claude Code only. |
| [`simple-code`](skills/simple-code) | Keep implementations, refactors, and reviews simple: justify abstractions, clarify ownership, and preserve correctness without unnecessary infrastructure. Applies across features and technology stacks. |

## Install

Into a project, committed alongside the code:

```bash
npx skills add shepeliev/ccc-things --skill android-architecture
```

For yourself, across every project:

```bash
npx skills add shepeliev/ccc-things --skill android-architecture -g
```

A local checkout works as a source too, which is handy while developing a skill:

```bash
npx skills add /path/to/ccc-things --skill android-architecture --agent '*' -y
```

Other useful commands: `npx skills list`, `npx skills update`, `npx skills remove`.

## What a project install looks like

```
<your-project>/
├── .agents/skills/android-architecture/     # the actual files
└── .claude/skills/android-architecture  ->  ../../.agents/skills/android-architecture
```

One copy, plus a symlink. That is not arbitrary — it is what each agent actually reads:

| Location | Claude Code | Codex |
|---|---|---|
| `.claude/skills/<name>/` | discovers | ignores |
| `.agents/skills/<name>/` | import only | discovers |
| `.codex/skills/<name>/` | ignores | discovers |

`.agents/` is the cross-agent location, so it holds the files and Claude Code gets a symlink to
them. Claude Code follows symlinks in `.claude/skills`, so both agents see one source of truth.
`npx skills` sets this up for you and covers 20+ other agents at the same time.

Commit both paths. On Windows, symlinks need developer mode or `core.symlinks=true` — use
`npx skills add … --copy` there to get two real directories instead.

## Layout

```
skills/<skill-name>/
├── SKILL.md        # entrypoint: name + description frontmatter, kept under 500 lines
├── references/     # detail loaded on demand, not up front
└── scripts/        # dependency-free helpers
```

Flat `skills/<name>/SKILL.md` is what `npx skills` discovers. Deliberately no root `SKILL.md` —
that would collapse the repo into a single skill and block adding siblings later.
