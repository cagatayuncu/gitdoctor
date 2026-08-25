# .gitflow.json

Optional, committed at the repo root. A missing file or bare `{}` equals all
defaults below. THE AGENT is the JSON parser: read this file and pass values
to the doctor as CLI flags (the doctor's built-in sed fallback covers only six
scalar keys for standalone human runs — see § Sed fallback).

```json
{
  "version": 1,
  "branches": { "main": "main", "develop": "develop", "mainAliases": ["main", "master"] },
  "prefixes": { "feature": "feature/", "release": "release/", "hotfix": "hotfix/", "backmerge": "backmerge/" },
  "tagPrefix": "v",
  "mergeMode": "auto",
  "pr": { "mergeMethod": "auto", "draft": false, "autoMergeOnCIWait": false, "ciTimeoutMinutes": 30 },
  "versionFiles": [ { "path": "package.json", "preset": "package-json" } ],
  "changelog": { "enabled": true, "file": "CHANGELOG.md", "convention": "conventional-commits" },
  "release": { "maxConcurrent": 1, "allowPrerelease": false, "githubRelease": true },
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
- **doctor.ignoreFindings**: entries `"check-id"` or `"check-id:sha"`.
  Suppressed findings still appear with `status:"skipped"`,
  `reason:"config-ignored"`.
- **github.defaultBranch**: what gh-default-branch-unexpected expects.

## Sed fallback (standalone doctor runs)

Without the agent, the doctor extracts exactly six scalar keys itself:
`"main"`, `"develop"`, `"tagPrefix"`, `"mergeMode"`, `"staleDays"`,
`"maxConcurrent"`. Constraint: each of those KEY NAMES must appear exactly
once in the file (the schema above satisfies this — `main`/`develop` appear
elsewhere only as values, never as keys). Everything else is agent-only.
