# Changelog

## 0.2.1 (2026-08-30)

### Fixes
- Action metadata for GitHub Marketplace validation: unique listing name
  ("gitdoctor - Git Flow health gate") and a description under 125 characters.
  The `uses: cagatayuncu/gitdoctor@<tag>` path is unchanged.

## 0.2.0 (2026-08-30)

Distribution release: one-line PR bot, plugin packaging, hooks.

### Features
- Composite GitHub Action at the repo root: the PR bot becomes a single
  `uses: cagatayuncu/gitdoctor@v0.2.0` line (inputs: checks, skip,
  min-severity, comment, fail-on, github-token; dogfooded on this repo's own PRs)
- Claude Code plugin manifest (`.claude-plugin/plugin.json`); installable via
  the `cagatayuncu/claude-plugins` marketplace
- Integration layer: client `pre-push` and server `pre-receive` hooks (both
  fixture-tested), cron watcher for CI-less repos, scheduled-scan template,
  GitLab CI and Bitbucket Pipelines drafts
- Test suite grown to 45 scenarios (hook gates exercised over real pushes)

### Fixes
- PR bot polish from its first live run: report written outside the worktree,
  GitHub-side checks get a token, deliberate SC2016 silenced
- LF checkout forced for extensionless hook files and stub fixtures

### Docs
- MIT license, README badges and topics, plugin install instructions,
  check count corrected to the mechanical 42

## 0.1.0 (2026-08-30)

First public release.

### Features
- Read-only doctor with 42 checks across environment, worktree, local/origin
  sync, git-flow topology (missing back-merge, wrong-base branches, orphaned
  releases), tags and branch hygiene — each finding paired with a fix recipe
- Probe-driven, resumable finish flows for feature/release/hotfix (evidence:
  ancestry → gh PR → content-equivalence → tag → branch-gone)
- Branch-protection-aware merge modes resolved per target branch (PR vs local)
- Squash-merge awareness via merge-tree content equivalence
- GitHub Actions PR bot: one self-updating findings comment per PR, criticals
  gate the check; reusable template + scheduled-scan template
- Client pre-push and server pre-receive hooks (both fixture-tested), cron
  watcher for CI-less repos, GitLab CI and Bitbucket Pipelines drafts
- Agent playbooks for Claude Code (skill) and Cursor (command adapter)

### Fixes
- capture/capture_all kept data arriving without a trailing newline
  (version-file reads); shellcheck findings from the first CI runs; PR bot
  writes its report outside the worktree and authenticates GitHub-side checks

### Docs
- English README with integration guide; fix-recipe catalog; config schema
