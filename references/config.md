# .gitflow.json

Optional, committed at the repo root. A missing file or bare `{}` equals all
defaults below. THE AGENT is the JSON parser: read this file and pass values
to the doctor as CLI flags (the doctor's built-in config fallback covers only a
few scalar keys for standalone runs — see § Config fallback).

```json
{
  "$schema": "https://raw.githubusercontent.com/cagatayuncu/gitdoctor/main/schema/gitflow.schema.json",
  "version": 1,
  "branches": { "main": "main", "develop": "develop", "mainAliases": ["main", "master"] },
  "prefixes": { "feature": "feature/", "release": "release/", "hotfix": "hotfix/", "backmerge": "backmerge/" },
  "tagPrefix": "v",
  "mergeMode": "auto",
  "pr": { "mergeMethod": "auto", "draft": false, "autoMergeOnCIWait": false, "ciTimeoutMinutes": 30 },
  "versionFiles": [ { "path": "package.json", "preset": "package-json" } ],
  "changelog": { "enabled": true, "file": "CHANGELOG.md", "convention": "conventional-commits" },
  "release": { "maxConcurrent": 1, "allowPrerelease": false, "githubRelease": true, "signedTags": false },
  "backmerge": { "strategy": "merge-tag", "conflictPolicy": { "versionFiles": "higher", "changelog": "union" } },
  "github": { "defaultBranch": "develop" },
  "doctor": { "staleDays": 30, "fetch": true, "scanDepth": 200,
              "ignoreBranches": ["dependabot/*", "renovate/*", "gh-pages"],
              "ignoreTags": [], "ignoreShas": [], "ignoreFindings": [] }
}
```

## Field → doctor flag mapping

| Config | Doctor flag |
|---|---|
| branches.main / branches.develop | `--main` / `--develop` |
| prefixes.* | `--feature-prefix` `--release-prefix` `--hotfix-prefix` `--backmerge-prefix` |
| tagPrefix | `--tag-prefix` (empty string allowed) |
| mergeMode | `--merge-mode auto\|pr\|local` |
| release.maxConcurrent | `--max-releases` |
| release.allowPrerelease | `--allow-prerelease` |
| release.githubRelease: false | `--no-github-release` (gh-release-missing-for-tag reports `skipped`) |
| release.signedTags: true | `--require-signed-tags` (enables tag-unsigned) |
| changelog.enabled (default true) / changelog.file | `--changelog <file>` (enables changelog-tag-mismatch; omit when disabled) |
| doctor.staleDays / scanDepth | `--stale-days` / `--scan-depth` |
| doctor.fetch: false | `--no-fetch` |
| doctor.ignoreBranches/Tags/Shas/Findings | `--ignore-branches` etc. (comma-joined) |
| versionFiles[] | one `--version-file <path> --version-pattern <ERE>` pair each |

## Field notes

- **branches.mainAliases**: agent-side only (no doctor flag). When
  `branches.main` is not explicitly set, the agent picks whichever alias
  exists in the repo and passes it as `--main`. The doctor's own fallback
  detection special-cases only the literal name `master`.
- **mergeMode**: `auto` resolves per TARGET branch from GitHub's protected
  bit (doctor output `repo.mergeMode.resolved`). `pr` forces PRs even on
  unprotected branches; `local` forces local merges (pushes to protected
  branches will simply be rejected by GitHub — explain, then switch to PR).
- **pr.mergeMethod**: `auto` = first allowed of merge → squash → rebase.
- **versionFiles[]**: `path` (repo-relative) plus either `preset`
  (references/version-files.md) or a raw `pattern` (POSIX ERE, capture group 1
  = current version) and `replace` (string with `{version}` placeholder).
- **backmerge.strategy**: `merge-tag` (default; guarantees main ⊂ develop) or
  `merge-branch` (nvie-literal: merge the release branch itself).
- **backmerge.conflictPolicy**: `versionFiles: "higher"` keeps the greater
  version on conflict; `changelog: "union"` keeps both sides' entries.
- **doctor.ignoreFindings**: entries `"check-id"` (the whole check) or
  `"check-id:key"` where key is what the finding names — its `key` field: the
  branch, tag, sha, file or PR number. Suppressed findings still appear with
  `status:"skipped"`, `reason:"config-ignored"`. `--format baseline` prints the
  entries that would silence the current scan (SKILL.md § Baseline).
- **$schema**: optional; points editors at
  [schema/gitflow.schema.json](../schema/gitflow.schema.json) for completion
  and validation. The doctor ignores it.
- **github.defaultBranch**: what gh-default-branch-unexpected expects.

## Config fallback (standalone doctor runs)

Without the agent, the doctor scans these scalar keys itself (pure bash, any
formatting, several keys per line): `"main"`,
`"develop"`, `"tagPrefix"`, `"mergeMode"`, `"staleDays"`, `"maxConcurrent"`,
`"githubRelease"`, `"signedTags"`, and the `"changelog"` block (`"enabled"`,
`"file"`; a block without `file` means `CHANGELOG.md`). Constraint: each of
those KEY NAMES must appear exactly once in the file (the schema above
satisfies this — `main`/`develop` appear elsewhere only as values, never as
keys). Everything else — version files, prefixes, ignore lists — is
agent-only; standalone runs (hooks, CI action) use the defaults for those.
