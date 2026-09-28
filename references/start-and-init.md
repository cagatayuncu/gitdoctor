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
3. Write `.gitflow.json` (references/config.md) starting with
   `"$schema": "https://raw.githubusercontent.com/cagatayuncu/gitdoctor/main/schema/gitflow.schema.json"`
   (editor completion): detect version files — `package.json`, `*.csproj` with
   `<Version>`, `pyproject.toml`, `Cargo.toml`, `VERSION` — and write explicit
   `versionFiles` entries with presets.
   **Existing history → infer, then propose.** Run
   `bash <skill-dir>/scripts/gitflow-doctor.sh --conventions [--main <b>]`: it
   reads the newest 5 release/hotfix tags on main and reports `tagPrefix`,
   `tagType`, `messages` (`mergeToMain`, `backMerge`, `tag` as templates),
   `backmergeStrategy` and `versionScheme`, each by majority vote. Show them
   to the user as a proposed config block and write only what they accept.
   Keys missing from the output had no evidence — leave them at defaults.
   A `tagType` of `lightweight` is reported, not copied: recommend annotated
   tags going forward (doctor: tag-lightweight-release).
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
   strictly greater than `repo.versions.latestTag` by SemVer precedence
   (doctor: release-version-collision). Under `suffix-counter` a release must
   move the base: `2.0.0` sorts BELOW `2.0.0-hotfix.3`, so the next one is
   `2.1.0` (or `3.0.0`).
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
2. No version → suggest the doctor's `repo.versions.nextHotfix` (semver: patch
   bump of the latest tag; suffix-counter: same base, counter + 1 — both skip
   numbers already held by open hotfix branches). Guard: `> latest tag` and
   `< any open release version` (finish-hotfix.md § Version guard). The branch
   is `hotfix/<version>`, e.g. `hotfix/2.0.0-hotfix.13`.
3. ```bash
   git switch main && git merge --ff-only origin/main
   git switch -c hotfix/X.Y.Z
   git push -u origin hotfix/X.Y.Z
   ```

## Version suggestion (conventional commits)

Range: `git log --format='%s%n%b' <latest-tag>..origin/develop` (for hotfix:
no scan — take `repo.versions.nextHotfix`).

- Any `BREAKING CHANGE:` in a body, or a `type!:` subject → **major**
- else any `feat:`/`feat(scope):` subject → **minor**
- else → **patch**

Present as: current `vA.B.C` → suggested `vX.Y.Z` (reason: N feats, M fixes,
K breaking). The user can override. No tags yet → suggest `0.1.0` (or `1.0.0`
if the user says the API is stable).
