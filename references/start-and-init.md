# Init and start flows

## Init

Prepares a repo for git flow. Idempotent — re-running fixes what is missing.

1. Doctor first (full run). `env-not-a-repo`/`env-no-origin` → guide the user
   through `git init` / `gh repo create` / `git remote add origin`.
2. Ensure `develop` exists:
   ```bash
   git switch main && git pull --ff-only origin main
   git switch -c develop && git push -u origin develop
   ```
   (If only `master` exists, use it as main and record it in config.)
3. Write `.gitflow.json` (references/config.md): detect version files —
   `package.json`, `*.csproj` with `<Version>`, `pyproject.toml`, `Cargo.toml`,
   `VERSION` — and write explicit `versionFiles` entries with presets.
4. Append to `.gitattributes` (create if missing): `CHANGELOG.md merge=union`
   (use the configured changelog filename).
5. If no semver tag exists, offer an initial `v0.1.0` (or user's choice) on
   main: `git tag -a v0.1.0 -m "Initial version" && git push origin v0.1.0`.
6. Commit `.gitflow.json` + `.gitattributes` to develop (via the resolved
   merge mode — direct push if unprotected).
7. Recommendations (do not auto-apply): branch protection on main
   (fix-recipes.md#gh-protection-missing-main), default branch = develop
   (`gh repo edit --default-branch develop`).

## Start feature

```
gitflow start feature <name>
```
1. Preflight (SKILL.md). Name: reject names already containing the prefix
   twice; slugify spaces to `-`.
2. ```bash
   git fetch origin --prune
   git switch develop && git merge --ff-only origin/develop
   git switch -c feature/<name>
   git push -u origin feature/<name>   # publish immediately (team visibility)
   ```
   Solo repos may skip the push if the user prefers local-only branches.

## Start release

```
gitflow start release [X.Y.Z]
```
1. Preflight + refuse if open release count would exceed
   `release.maxConcurrent` (doctor: multiple-release-branches).
2. No version given → suggest one (§ Version suggestion) and confirm.
   Validate: bare `X.Y.Z` (prerelease only with `release.allowPrerelease`),
   strictly greater than the latest tag (doctor: release-version-collision).
3. ```bash
   git switch develop && git merge --ff-only origin/develop
   git switch -c release/X.Y.Z
   git push -u origin release/X.Y.Z
   ```
4. Offer to bump version files + start the changelog section NOW (it can also
   happen at finish step 1 — user's choice; doing it now makes the release
   branch reviewable).

## Start hotfix

```
gitflow start hotfix [X.Y.Z]
```
1. Preflight. Base is MAIN, never develop.
2. No version → suggest latest tag + patch bump. Guard: `> latest tag` and
   `< any open release version` (finish-hotfix.md § Version guard).
3. ```bash
   git switch main && git merge --ff-only origin/main
   git switch -c hotfix/X.Y.Z
   git push -u origin hotfix/X.Y.Z
   ```

## Version suggestion (conventional commits)

Range: `git log --format='%s%n%b' <latest-tag>..origin/develop` (for hotfix:
patch bump of the latest tag, no scan).

- Any `BREAKING CHANGE:` in a body, or a `type!:` subject → **major**
- else any `feat:`/`feat(scope):` subject → **minor**
- else → **patch**

Present as: current `vA.B.C` → suggested `vX.Y.Z` (reason: N feats, M fixes,
K breaking). The user can override. No tags yet → suggest `0.1.0` (or `1.0.0`
if the user says the API is stable).
