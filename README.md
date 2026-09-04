# gitdoctor

[![ci](https://github.com/cagatayuncu/gitdoctor/actions/workflows/ci.yml/badge.svg)](https://github.com/cagatayuncu/gitdoctor/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/cagatayuncu/gitdoctor)](https://github.com/cagatayuncu/gitdoctor/releases)
[![license](https://img.shields.io/github/license/cagatayuncu/gitdoctor)](LICENSE)

One-command Git Flow for AI coding agents (Claude Code, Cursor, and anything
that can follow a markdown playbook and run bash). Classic git-flow model:
`main` + `develop`, `feature/*`, `release/x.y.z`, `hotfix/x.y.z`, SemVer tags
on main.

**One command each:** start/finish feature, release and hotfix branches; scan
the repo for anomalies (doctor); verify alignment (main↔develop, local↔origin,
version file↔tag); SemVer tagging + CHANGELOG + GitHub Release; and
branch-protection-aware PR/local merging.

## What's inside

| Piece | Role |
|---|---|
| `SKILL.md` | Agent playbook: command routing, gates, dry-run contract, safety rails |
| `scripts/gitflow-doctor.sh` | The only executable: 46 read-only checks + finish probes; JSON, text, Markdown, SARIF or baseline out |
| `references/*.md` | Choreographies (finish release/hotfix/feature, init/start), fix recipes, config schema |
| `adapters/cursor/` | Cursor `/gitdoctor` command wrapper |
| `tests/` | Fixture-based suite: every check has a scratch-repo test; probes and read-only guarantees included |

Design principles:
- **Deterministic checks, agent-driven mutations.** The doctor never writes
  (one sanctioned `git fetch`); the agent performs merges/tags/pushes gated on
  the doctor's JSON.
- **Idempotent finish.** Every finish is a probe walk — rerun after any crash
  or CI wait and it continues from the first missing step. No state files as
  source of truth.
- **Squash-aware.** Content-equivalence via `git merge-tree` catches
  squash-merged branches that ancestry checks miss; gh (when available) is the
  authoritative tier.
- **Protection-aware.** `mergeMode: auto` resolves PR vs local merge per
  target branch from GitHub branch protection.

## Install

Requirements: git ≥ 2.38 recommended (≥ 2.30 works with degraded conflict
prediction), bash (Git Bash on Windows), optional `gh` (authenticated) for
PR mode + GitHub checks. No jq needed.

### Claude Code — as a plugin (recommended)

```
/plugin marketplace add cagatayuncu/claude-plugins
/plugin install gitdoctor@cagatayuncu
```

Then in any repo: `/gitdoctor doctor`, `/gitdoctor start release`,
`/gitdoctor finish`, …

### Claude Code — as a user-level skill

```bash
./install.sh            # or .\install.ps1 on Windows
```

Installs to `~/.claude/skills/gitdoctor/`. Same commands as above.

### Cursor

```bash
./install.sh --cursor-repo /path/to/your/repo
```

Adds `.cursor/commands/gitdoctor.md` (+ the skill payload) to that repo →
`/gitdoctor …` works in Cursor's chat.

## Commands

| Command | What it does |
|---|---|
| `/gitdoctor init` | Create develop, write `.gitflow.json`, changelog merge=union, protection advice |
| `/gitdoctor start feature <name>` | Preflight → branch from develop |
| `/gitdoctor start release [x.y.z]` | Version suggestion from conventional commits → branch from develop |
| `/gitdoctor start hotfix [x.y.z]` | Branch from main, collision guards |
| `/gitdoctor finish` | Detect branch type → merge (PR or local) + tag + GitHub Release + back-merge + cleanup; resumable |
| `/gitdoctor doctor` | Full anomaly/alignment scan with fix recipes |
| `/gitdoctor sync` | fetch --prune + fast-forward main/develop |
| `/gitdoctor status` | Branch, ahead/behind, open PRs, latest tag, next version |
| `/gitdoctor cleanup` | Merged/stale branch cleanup (confirmed) |
| `/gitdoctor explain <check-id>` | Print the fix recipe for one check (CLI: `--explain <id>`) |
| `/gitdoctor baseline` | Adopt today's findings as `doctor.ignoreFindings` entries — only new ones stay loud |

Add `--dry-run` to any mutating command: reads run, every mutation is printed
as `DRY-RUN: <argv>` instead of executed.

## Integrations

The doctor's JSON output + exit codes plug into anything: a **GitHub Actions
PR bot** (live on this repo — one self-updating comment per PR, criticals
block the merge), a scheduled scan that files an issue, client `pre-push` and
server `pre-receive` hooks (both covered by the fixture suite), a
[pre-commit](https://pre-commit.com) hook definition, SARIF output for GitHub
code scanning, a cron watcher for repos with no CI, and GitLab/Bitbucket
drafts. See [integrations/](integrations/README.md).

## The doctor

```bash
bash scripts/gitflow-doctor.sh --format json          # everything (agent contract)
bash scripts/gitflow-doctor.sh --format text          # for humans; also: markdown, sarif, baseline
bash scripts/gitflow-doctor.sh --checks missing-back-merge,tag-unpushed
bash scripts/gitflow-doctor.sh --explain missing-back-merge   # the fix recipe, in the terminal
bash scripts/gitflow-doctor.sh --list-checks
bash scripts/gitflow-doctor.sh --probe finish-release --branch release/1.2.0 --version 1.2.0
```

Exit codes: 0 clean, 1 warnings, 2 criticals, 4 usage error. 46 checks across environment,
worktree, local↔origin sync, git-flow topology (missing back-merge, wrong
base, orphaned/colliding releases), tags (unpushed, sha-mismatch, duplicates,
lightweight, unsigned), release bookkeeping (version files and changelog vs
the latest tag), branch hygiene (stale/squash-merged), and GitHub (protection
on main and develop, wrong-base PRs, squash-only limitations, tags without a
Release). Every finding names what it is about (`key`), so
`doctor.ignoreFindings` can silence one branch or tag instead of a whole check,
and `--format baseline` writes those entries for you. Full catalog with
recipes: [references/fix-recipes.md](references/fix-recipes.md).

Configuration: [.gitflow.json reference](references/config.md) — add
`"$schema": "https://raw.githubusercontent.com/cagatayuncu/gitdoctor/main/schema/gitflow.schema.json"`
for editor completion ([schema/gitflow.schema.json](schema/gitflow.schema.json)).

## Tests

```bash
bash tests/run-tests.sh            # all (JOBS=8 parallel by default)
bash tests/run-tests.sh t/doctor/T030-missing-back-merge.sh
```

Every check id has a fixture that creates the anomaly in a scratch repo
(fake `git init --bare` origin), asserts the finding, applies the recipe, and
asserts it clears. gh-dependent checks run against a canned-response `gh`
stub. CI runs the suite on ubuntu, macOS (bash 3.2) and windows (Git Bash)
plus shellcheck.

Note for Windows: per-process antivirus scanning can make git spawns slow;
excluding your repos directory and `git.exe` from real-time scanning speeds
up both the doctor and the tests dramatically.

## Not in v1 (deliberate)

`support/*` maintenance branches, rc/prerelease tags in the release flow,
monorepo multi-package versioning, GitLab/Bitbucket, jsonpath-precise version
file editing.
