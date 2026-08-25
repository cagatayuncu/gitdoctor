# Fix recipes

One recipe per doctor finding id. The doctor's `fix.recipeRef` points at the
anchor with the same name. Commands assume defaults (`main`, `develop`, tag
prefix `v`) — substitute the configured names.

General rules that override any recipe:
- Never force-push `main`, `develop`, or tags.
- Confirm with the user before deleting anything.
- After applying a recipe, re-run the doctor to confirm the finding cleared.

## env-not-a-repo
Not inside a git work tree. `cd` into the repository, or `git init` +
`git remote add origin <url>` for a new one, then `gitdoctor init`.

## env-no-origin
No `origin` remote. `git remote add origin <url>` (create the GitHub repo
first with `gh repo create` if needed).

## env-origin-not-github
Informational: gh-backed checks and PR-mode finishes are disabled; everything
runs in local merge mode. No action needed.

## env-gh-unavailable
`gh auth login` (or install gh). Until then GitHub checks report `skipped`
and merge-mode resolution falls back to `unknown` → treat as local.

## env-fetch-failed
`git fetch origin --prune --tags` failed (network/auth). Findings are based on
possibly stale remote-tracking refs — resolve connectivity and re-run before
trusting sync results.

## env-missing-main
The main branch does not exist locally or on origin. Run `gitdoctor init`
(references/start-and-init.md); if the repo uses `master`, set
`branches.main` in `.gitflow.json`.

## env-missing-develop
The develop branch does not exist. Run `gitdoctor init` — it creates `develop`
from `main` and pushes it.

## env-shallow-clone
`git fetch --unshallow origin`. Until then every ancestry-based finding
carries `confidence:"low"` — do not act on those without unshallowing.

## env-git-too-old
git < 2.38 lacks `git merge-tree --write-tree`: conflict prediction and
squash-detection (content-equivalence) are disabled. Upgrade git.

## dirty-worktree
Uncommitted changes block flow operations. Either commit them, or
`git stash push -u` (restore later with `git stash pop`). Never start or
finish a flow branch over a dirty tree.

## detached-head
`git switch <branch>`. If the user has commits made in detached state:
`git switch -c rescue/<name>` first so they are not lost.

## operation-in-progress
A merge/rebase/cherry-pick/revert/bisect is half-done. Either finish it
(resolve conflicts, `git <op> --continue`) or abort it (`git <op> --abort`,
`git bisect reset`). Nothing else is safe until the state is clean.

## sync-behind
```bash
git switch <branch>
git merge --ff-only origin/<branch>
```
If `--ff-only` refuses, the branch also has local commits → see sync-diverged.

## sync-ahead
Local commits never pushed. On `develop` this is usually just unpushed work →
`git push origin develop`. On `main` it is **critical**: it means a finish
half-completed or someone committed to main directly. Inspect
`git log origin/main..main` first; if the commits are a legitimate finish leg,
resume the finish; if they are accidents, cherry-pick them to the right branch
and `git reset --keep origin/main` (confirm with the user — this rewrites
local main only, never the remote).

## sync-diverged
Local and origin both moved. NEVER force-push. Inspect both sides:
```bash
git log --oneline --left-right <branch>...origin/<branch>
```
Then either rebase local-only commits onto origin
(`git rebase origin/<branch> <branch>`) or merge origin in. If the remote side
was force-pushed by someone else, stop and coordinate with the team.

## missing-back-merge
Commits on main (hotfixes/releases) never returned to develop — the next
release would silently revert them. Repair:
```bash
git switch develop
git merge --ff-only origin/develop
git merge --no-ff origin/main
git push origin develop
```
If `conflictsPredicted:true`, warn the user first and resolve per
references/finish-release.md § Back-merge conflicts.

Variant `back-merge-content-only` (info): the content already reached develop
via a squash — ancestry repair (the same merge, which will be a no-op
content-wise) is optional but makes future doctor runs exact.

## untagged-merge-on-main
A release/hotfix merge landed on main without a tag. Identify the version from
the merged branch name or CHANGELOG, then:
```bash
git tag -a vX.Y.Z <merge-sha> -m "Release X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z --title "X.Y.Z" --generate-notes   # optional
```

## direct-commit-on-main
Commits bypassed the flow. For each sha: verify it is in develop
(`git merge-base --is-ancestor <sha> origin/develop`) — if not, back-merge
(see missing-back-merge). Prevent recurrence with branch protection
(gh-protection-missing-main). Known exceptions can be silenced via
`doctor.ignoreShas` or `doctor.ignoreFindings: ["direct-commit-on-main:<sha>"]`.

## wrong-base-feature
The branch contains main-only commits (branched from main, or main merged in).
If the branch is still private to the user:
```bash
git rebase --onto origin/develop "$(git merge-base origin/main <branch>)" <branch>
git push --force-with-lease origin <branch>   # own feature branch only
```
Shared branch → recreate from develop and cherry-pick instead. If
`relatedFinding:missing-back-merge` is set, do that repair first — the branch
may become clean by itself.

## wrong-base-hotfix
CRITICAL: the hotfix carries unreleased develop work; finishing it would ship
that to production. Recreate:
```bash
git switch -c hotfix/X.Y.Z-rebased origin/main
git cherry-pick <fix commits only>
# then replace the branch:
git branch -D hotfix/X.Y.Z && git branch -m hotfix/X.Y.Z-rebased hotfix/X.Y.Z
git push -f origin hotfix/X.Y.Z   # only if the broken branch was already pushed and is not shared
```

## release-develop-drift
Informational: develop moved on while a release is open — classic git flow
expects this; the finish back-merge reconciles it. If
`conflictsPredicted:true`, preview the clash now:
`git merge-tree --write-tree --name-only origin/develop origin/release/X.Y.Z`
and plan the resolution before finish day.

## multiple-release-branches
Classic git flow allows one release at a time (config
`release.maxConcurrent`). Finish or abandon the older one first. Abandoning:
delete the branch, then run the doctor — it will flag anything that leaked.

## orphaned-release-branch
(Also emitted as `orphaned-hotfix-branch` for hotfix branches — same recipe.)
The tag exists but the branch was never cleaned up — an interrupted finish.
Run `gitdoctor finish` on that branch: the probe walk skips the done steps and
completes back-merge/deletion. If everything else is verified done:
```bash
git push origin --delete <branch> && git branch -d <branch>
```

## release-version-collision
The release branch targets a version ≤ the latest tag. Rename:
```bash
git branch -m release/OLD release/NEW
git push origin :release/OLD release/NEW
git push -u origin release/NEW
```

## version-file-tag-mismatch
The version file on main disagrees with the latest tag. Normal cause: a finish
that skipped the bump step. Align on the next finish, or hot-patch now via a
hotfix branch that only bumps the file.

## tag-not-on-main
A semver tag points at a commit not reachable from main — usually a finish
that tagged before the merge landed, or a tag on develop. Resume the finish
(`gitdoctor finish` probe walk). If the tag is simply wrong, delete and retag
the real release commit (confirm with the user; coordinate if pushed).

## non-semver-tag
Informational. Historic tags can stay (add to `doctor.ignoreTags`); wrong ones:
`git tag -d <tag> && git push origin :refs/tags/<tag>`.

## duplicate-tag-target
Two semver tags on one commit — usually a double-finish. Decide which is
canonical, delete the other (`git tag -d T && git push origin :refs/tags/T`),
and delete its GitHub release if one exists (`gh release delete T`).

## tag-prefix-collision
Both `v1.2.0` and `1.2.0` exist. Keep the prefixed one:
`git tag -d 1.2.0 && git push origin :refs/tags/1.2.0`.

## tag-lightweight-release
Lightweight release tags carry no author/date/message. Future tags: always
`git tag -a`. Recreating an existing one changes its sha — only do it if the
tag is recent and the team is warned (`git tag -d`, retag annotated,
`git push -f origin <tag>` — the one sanctioned tag force-push, explicit
user confirmation required).

## tag-unpushed
`git push origin <tag>` — an unpushed release tag means CI/teammates cannot
see the release.

## tag-sha-mismatch
CRITICAL: the same tag name points at different commits locally vs origin.
Someone retagged. STOP all finishes. Determine the correct target
(`git show <tag>`, `git ls-remote --tags origin <tag>`, ask the team), then
fix the WRONG side only — if local is wrong:
`git tag -d <tag> && git fetch origin tag <tag>`. Never resolve by force-push.

## branch-stale-merged
Merged but undeleted. `method:"ancestry"` →
`git push origin --delete <b> && git branch -d <b>`.
`method:"gh-pr"` or `"content-equivalent"` (squash merges) → same with
`git branch -D <b>` — the method IS the merge verification (`-d` would refuse
because ancestry does not show the squash).

## branch-stale-inactive
No commits for `staleDays`. Ask the owner: finish it, delete it, or revive it
(`git rebase origin/develop <b>`). Never auto-delete.

## branch-bad-version-name
Release/hotfix branch suffixes must be bare `X.Y.Z` (with
`release.allowPrerelease`, `X.Y.Z-suffix`). Rename:
`git branch -m <old> <prefix>/X.Y.Z && git push origin :<old> <prefix>/X.Y.Z`.

## branch-unrecognized
Branch matches no flow prefix. Rename into `feature/...`, or add a glob to
`doctor.ignoreBranches` if it is intentional infrastructure (e.g. `gh-pages`).

## gh-protection-missing-main
Recommend enabling protection (requires admin):
```bash
gh api -X PUT "repos/<owner>/<repo>/branches/main/protection" \
  -F required_pull_request_reviews.required_approving_review_count=1 \
  -F enforce_admins=true -F required_status_checks=null -F restrictions=null
```
With protection on, finishes toward main automatically use PR mode.

## gh-default-branch-unexpected
`gh repo edit --default-branch develop` — so new PRs target develop by
default. Skip if the team intentionally prefers main (set
`github.defaultBranch` in `.gitflow.json` to silence).

## gh-open-pr-wrong-base
A feature PR targets main. `gh pr edit <n> --base develop`.

## gh-squash-only-back-merge-limitation
Merge commits are disabled and develop is protected: main can never become an
ancestor of develop, so ancestry alignment is impossible — the doctor
permanently downgrades back-merge checking to content-equivalence. Either
allow merge commits (`gh repo edit --enable-merge-commit`) or exempt develop
from protection for back-merge PRs. Otherwise: no action, the degraded mode is
handled automatically.
