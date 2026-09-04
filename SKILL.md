---
name: gitdoctor
description: "One-command Git Flow operations with anomaly detection and safe tagging (gitdoctor). Use this skill whenever the user wants to start or finish a feature/release/hotfix branch, cut or tag a release, run a git-flow health check (doctor), fix branch misalignment (missing back-merge, wrong base, diverged branches), clean up stale branches, or asks about git flow, gitflow, release/hotfix flow, back-merge, branch protection aware merging, SemVer tagging, or CHANGELOG/GitHub Release creation. Triggers: 'gitflow', 'git flow', 'start release', 'finish release', 'hotfix', 'release aç', 'release bitir', 'tagle', 'branch temizle', 'doctor', 'sync branches'."
---

# GitFlow

Single-command Git Flow operations for classic git-flow repositories
(`main` + `develop` + `feature/*` + `release/x.y.z` + `hotfix/x.y.z`,
tags `vX.Y.Z` on main).

## Architecture: who does what

- `scripts/gitflow-doctor.sh` (relative to this skill's directory) is the ONLY
  executable. It performs reads plus at most one cache mutation
  (`git fetch origin --prune --tags`). It emits JSON findings and probe walks.
- YOU (the agent) perform every mutation — merge, tag, push, `gh pr`,
  `gh release` — by following the references, gated on doctor/probe JSON.
  Never mutate without the gate that the flow prescribes.
- Speak to the user in the user's language; run all commands as written here.

## Command routing

| User intent | Do this |
|---|---|
| `gitdoctor init` / "set this repo up" | references/start-and-init.md § Init |
| `gitdoctor start feature <name>` | references/start-and-init.md § Start feature |
| `gitdoctor start release [version]` | references/start-and-init.md § Start release |
| `gitdoctor start hotfix [version]` | references/start-and-init.md § Start hotfix |
| `gitdoctor finish` (auto-detect branch type) | references/finish-feature.md / finish-release.md / finish-hotfix.md |
| `gitdoctor doctor` / "check the repo" | Run the doctor (below), report findings with recipes |
| `gitdoctor sync` | Fetch + fast-forward main/develop (below) |
| `gitdoctor status` | Status dashboard (below) |
| `gitdoctor cleanup` | Stale-branch cleanup (below) |
| `gitdoctor explain <check-id>` | `bash <skill-dir>/scripts/gitflow-doctor.sh --explain <check-id>` — print the recipe verbatim |
| `gitdoctor baseline` | Adopt today's findings as ignore entries (below) |

On `finish` with no arguments: read the current branch. `feature/*` →
finish-feature; `release/*` → finish-release; `hotfix/*` → finish-hotfix;
`main`/`develop` → error, tell the user to switch to a flow branch.

## Running the doctor

```bash
bash <skill-dir>/scripts/gitflow-doctor.sh --format json [flags]
```

- Read `.gitflow.json` at the repo root yourself (you are the JSON parser) and
  pass everything as flags: `--main`, `--develop`, `--tag-prefix`,
  `--feature-prefix`, `--release-prefix`, `--hotfix-prefix`,
  `--backmerge-prefix`, `--stale-days`, `--scan-depth`, `--max-releases`,
  `--merge-mode`, `--ignore-branches`, `--ignore-tags`, `--ignore-shas`,
  `--ignore-findings`, `--allow-prerelease`, and one
  `--version-file <path> --version-pattern <ERE>` pair per configured version
  file (pattern = POSIX ERE, capture group 1 is the version), plus
  `--changelog <changelog.file>` unless `changelog.enabled` is false (default:
  enabled, `CHANGELOG.md`), `--no-github-release` when `release.githubRelease`
  is false, `--require-signed-tags` when `release.signedTags` is true. Config
  schema: references/config.md. No config file → pass nothing, defaults apply.
- `--format json` is your contract. When the user wants to *see* the report,
  run it again with `--format text` (terminal) or `--format markdown` (PR
  descriptions, issues) and show that output verbatim instead of retyping
  findings. `--format sarif` feeds code scanning; `--format baseline` feeds the
  Baseline flow. `--list-checks` prints every id; `--explain <id>` a recipe.
  Probes always emit JSON.
- Exit codes: 0 clean/info, 1 warnings, 2 criticals, 4 usage error.
- Findings carry `fix.commands` and `fix.recipeRef` into
  references/fix-recipes.md. Report each finding briefly; offer the recipe.
  Never auto-apply a fix without telling the user what and why.
- `confidence` below `high` (or `status:"skipped"`) → phrase tentatively and
  say what would make the check authoritative (e.g. gh auth, unshallow).

## Preflight (before ANY mutation command)

Run the doctor focused on the fast safety set:

```bash
bash <skill-dir>/scripts/gitflow-doctor.sh --format json --checks dirty-worktree,detached-head,operation-in-progress,sync-behind,sync-ahead,sync-diverged,multiple-release-branches,wrong-base-feature,wrong-base-hotfix,orphaned-release-branch,orphaned-hotfix-branch,release-version-collision,tag-sha-mismatch [config flags]
```

- Any `critical` → STOP and surface it, except findings the flow itself
  repairs: `orphaned-release-branch`/`orphaned-hotfix-branch` when finishing
  that very branch (that IS the resume case).
- `dirty-worktree` warning → ask the user: stash, commit, or abort.
- Never proceed over `tag-sha-mismatch` or `sync-diverged`. Never force-push
  shared branches or tags. Ever.

## Merge-mode resolution (per target branch)

`mergeMode` in `.gitflow.json`: `auto` (default) | `pr` | `local`.
For `auto`, the doctor's `repo.mergeMode.resolved` tells you per branch:
`pr` (protected), `local` (unprotected), `unknown` (no gh — treat as `local`
but expect pushes to protected branches to be rejected; explain if they are).
A release finish may be `pr` toward main and `local` toward develop.

PR merge method: `pr.mergeMethod` config `auto` = first allowed of
merge → squash → rebase from
`gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`.

## Idempotent finish (probe walk)

Finish NEVER trusts memory of prior runs. Every finish invocation starts with:

```bash
bash <skill-dir>/scripts/gitflow-doctor.sh --probe finish-release --branch release/1.2.0 --version 1.2.0 [config flags]
```

(`finish-hotfix`, `finish-feature` likewise; feature takes no `--version`.)
Steps report `done:true/false` with evidence. Skip done steps, execute the
first pending one, re-probe after each mutation. Details per flow in the
finish references. Probe `warnings` are STOP signals (tag divergence).
`--dry-run` from the user → see Dry-run contract below.

## Dry-run contract

When the user passes `--dry-run`: execute read-only commands normally (doctor,
probes, `git log/diff`, `gh pr list/view`, `gh repo view`) and for every
mutating command print the exact argv prefixed `DRY-RUN:` instead of running
it. The mutating set is exactly:

`git merge`, `git tag`, `git push` (all forms), `git branch -d/-D/-m`,
`git switch -c`, `git commit`, `git stash`, `gh pr create/merge/edit/close`,
`gh release create/edit/delete`, `gh repo edit`, `gh api -X PUT/POST/PATCH/DELETE`.

## Sync

1. Preflight (skip sync-* self-checks' fix offers if user just wants sync).
2. `git fetch origin --prune --tags`
3. For main and develop: if behind only → `git switch <b> && git merge --ff-only origin/<b>`.
   If ahead or diverged → report, do not touch (see fix-recipes).
4. If the user's current branch tracks origin and is behind → offer the same.

## Status

Run the full doctor once, then present: current branch + type, ahead/behind
for main/develop, open flow branches, latest tag, suggested next version
(references/start-and-init.md § Version suggestion), open PRs
(`gh pr list --state open` when gh available), and any findings.

## Cleanup

Run the doctor focused on `branch-stale-merged,branch-stale-inactive,branch-unrecognized`.
Present candidates grouped by method/confidence. Delete ONLY after explicit
user confirmation, branch by branch or "all merged":
- `method:"ancestry"` → `git push origin --delete <b>` then `git branch -d <b>`
- `method:"gh-pr"` or `"content-equivalent"` → same but `git branch -D <b>`
  (squash merges make `-d` refuse; the method IS the verification).
- `branch-stale-inactive` → never delete without asking; offer finish/revive.

## Baseline

For adopting gitdoctor on a repo with historic noise: silence today's findings
one by one, keep tomorrow's loud.

1. Full doctor run with `--format baseline [config flags]` (include the current
   `--ignore-findings` so existing entries are kept). Output:
   `{"doctor":{"ignoreFindings":[...]}}` — one `id:key` per current finding
   (key = the branch, tag, sha, file or PR it names); a finding without a key
   contributes the bare id and silences that whole check.
2. Show the user the NEW entries and what each one hides; drop the ones they
   would rather fix. Never baseline `sync-diverged`, `tag-sha-mismatch`,
   `operation-in-progress` or `wrong-base-hotfix` — those are stop signals.
3. Write the merged list into `.gitflow.json` → `doctor.ignoreFindings`
   (create the file with `"$schema"` per references/config.md if missing),
   re-run the doctor to confirm the entries now report `skipped` /
   `config-ignored`, and commit via the resolved merge mode.

## Safety rails (non-negotiable)

1. Never force-push `main`, `develop`, or any tag. `--force-with-lease` is
   allowed only on the user's own feature branch after a rebase they asked for.
2. Never resolve source-file merge conflicts silently — walk the user through
   (policy: references/finish-release.md § Back-merge conflicts).
3. Never leave a merge half-done: every exit path commits or aborts
   (`operation-in-progress` is the backstop).
4. Never let `gh release create` create the tag — tag first, push, then
   release (Releases API tags are lightweight).
5. Tags in PR mode go on `gh pr view <n> --json mergeCommit` — never on a
   local sha.
6. `finish --admin` (`gh pr merge --admin`) only when the user explicitly
   passes it.
7. Destructive commands (branch deletion beyond the flow's own branch,
   tag deletion) require explicit user confirmation.

## References

- references/start-and-init.md — init, start flows, version suggestion
- references/finish-release.md — release finish (PR + local), tagging, back-merge, conflicts, resume
- references/finish-hotfix.md — hotfix finish + open-release back-merge rule
- references/finish-feature.md — feature finish
- references/fix-recipes.md — every doctor finding, one recipe each
- references/config.md — .gitflow.json schema
- references/version-files.md — version-file preset patterns
