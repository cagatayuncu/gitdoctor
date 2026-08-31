# Changelog

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
