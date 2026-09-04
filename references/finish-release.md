# Finish: release/X.Y.Z

Merges the release into main, tags `vX.Y.Z`, publishes the GitHub Release,
back-merges into develop, deletes the branch. Idempotent: driven entirely by
the probe walk — safe to re-run after any interruption.

## 0. Gate

1. Preflight doctor (SKILL.md § Preflight). The version is fixed by the
   branch name — never re-ask.
2. Probe:
   ```bash
   bash <skill-dir>/scripts/gitflow-doctor.sh --probe finish-release \
     --branch release/X.Y.Z --version X.Y.Z [config flags incl. --version-file/--version-pattern]
   ```
   Any probe `warnings` (tag divergence) → STOP, show the user, do not retag.
3. Resolve merge mode for main and for develop separately (SKILL.md
   § Merge-mode resolution).
4. `finish --abort` is only legal while `merged-to-main` is still false:
   close the PR if one was opened (`gh pr close <n>`), keep the branch, done.
   After merged-to-main, the only way out is forward — resume.

Walk the steps below in order; SKIP any step the probe reports `done:true`.
Re-probe after each mutation.

## 1. version-bumped

If version files are configured and not at X.Y.Z on the branch:
1. `git switch release/X.Y.Z && git pull --ff-only origin release/X.Y.Z`
2. Apply each configured version file edit (references/version-files.md).
3. If `changelog.enabled`: generate the section (see § Changelog) and prepend
   it to the changelog file. `gitflow init` sets `merge=union` for it in
   `.gitattributes` — keep that.
4. `git commit -am "chore(release): X.Y.Z" && git push origin release/X.Y.Z`

## 2. merged-to-main

**Local mode** (main unprotected):
```bash
git switch main
git merge --ff-only origin/main
git merge --no-ff release/X.Y.Z -m "Release X.Y.Z"
```
Do NOT push yet — step 3+4 push main and the tag atomically.

**PR mode** (main protected):
1. Reuse or create the PR:
   `gh pr list --head release/X.Y.Z --base main --state open --json number`
   → else `gh pr create --base main --head release/X.Y.Z --title "Release X.Y.Z" --body "<changelog section>"`
2. `gh pr checks <n> --watch --fail-fast` — on red: report the failing
   checks and stop (offer `gh pr merge <n> --auto` only if the user wants
   merge-on-green; the finish stays resumable either way).
3. `gh pr merge <n> --merge --delete-branch` (method per resolution; pass
   `--squash`/`--rebase` accordingly). `--admin` only on explicit user flag.

## 3. tag-exists

**Local mode**: `git tag -a vX.Y.Z -m "Release X.Y.Z"` on the merge commit
(HEAD of main after step 2).

**PR mode**: never tag a local sha — the merge happened on GitHub:
```bash
SHA=$(gh pr view <n> --json mergeCommit --jq .mergeCommit.oid)
git fetch origin main
git merge-base --is-ancestor "$SHA" origin/main   # verify before tagging
git tag -a vX.Y.Z "$SHA" -m "Release X.Y.Z"
```
`mergeCommit.oid` is populated for all three merge methods (merge → merge
commit, squash → squash commit, rebase → last rebased commit).

If the probe said tag-exists but pointed elsewhere, you already stopped at
step 0 — never retag silently.

## 4. tag-pushed

**Local mode** (main not pushed yet): atomic — both land or neither:
```bash
git push --atomic origin main refs/tags/vX.Y.Z
```
**PR mode** (main already on GitHub): `git push origin vX.Y.Z`

## 5. back-merged (target: develop)

Merge **the tag** (`backmerge.strategy: merge-tag`, default) so main becomes
an ancestor of develop.

Develop unprotected:
```bash
git switch develop
git merge --ff-only origin/develop
git merge --no-ff vX.Y.Z -m "Back-merge release X.Y.Z"
git push origin develop
```
Develop protected: carrier branch + PR:
```bash
git switch -c backmerge/release-X.Y.Z vX.Y.Z
git push -u origin backmerge/release-X.Y.Z
gh pr create --base develop --head backmerge/release-X.Y.Z --title "Back-merge release X.Y.Z" --fill
# checks → merge with the MERGE method if allowed; squash-only repos: see below
# after merge: delete the carrier branch (--delete-branch)
```

### Back-merge conflicts

Predict first: `git merge-tree --write-tree --name-only origin/develop vX.Y.Z`
(exit 1 = conflicts; lines after the tree oid = paths). Tell the user before
merging. On conflict, resolve by file class:
- **Version files** (paths in `versionFiles`): policy `higher` — compare
  `git show :2:<path>` vs `:3:<path>` through the version pattern, keep the
  greater (develop may already carry a newer dev version), `git add`.
- **Changelog**: policy `union` — keep both sections (develop's entries +
  the new release section on top), `git add`. The `merge=union` gitattribute
  normally prevents this class entirely.
- **Source files**: NEVER auto-resolve. Interactive: walk the user through
  each conflict and commit with the default merge message. Non-interactive:
  `git merge --abort`, report, and instruct to re-run finish (it resumes at
  this step).
Never leave MERGE_HEAD behind — every exit commits or aborts.

### Squash-only + protected develop

Ancestry alignment is impossible (doctor: gh-squash-only-back-merge-limitation).
The back-merge PR gets squashed; treat the probe's `mode:"content"` result as
done. Branch deletion below needs the gh-verified `-D` rule.

## 6. remote-branch-deleted / local-branch-deleted

- Remote: `git push origin --delete release/X.Y.Z` (PR mode with
  `--delete-branch` already did it; ignore "not found").
- Local: `git branch -d release/X.Y.Z`. If `-d` refuses (squash/rebase merge):
  verify `gh pr view <n> --json state --jq .state` is `MERGED`, then
  `git branch -D release/X.Y.Z`. **`-D` only after gh confirms MERGED** (or
  the probe showed merged via tag/content evidence).

## 7. gh-release

Tag exists and is pushed FIRST (steps 3-4) — then:
```bash
gh release create vX.Y.Z --title "X.Y.Z" --notes-file <changelog-section-file>
```
gh reuses the existing annotated tag. Never let `gh release create` invent the
tag (Releases API tags are lightweight). Skip if `release.githubRelease` is
false or gh unavailable (report it as pending).

## 7b. homebrew-formula (only when `homebrew` is configured)

The probe adds a `homebrew-formula` step when `.gitflow.json` has
`homebrew.tap` + `homebrew.formula` (flags `--homebrew-tap`,
`--homebrew-formula`); `done` = the formula's `url` already points at
`vX.Y.Z.tar.gz`. Run this AFTER the tag is pushed (step 4) — the tarball is
served from the tag, and the sha must be computed from the real archive:

```bash
TAG=vX.Y.Z; TAP=<owner>/homebrew-tap; F=Formula/<name>.rb
SHA=$(curl -sL "https://github.com/<owner>/<repo>/archive/refs/tags/$TAG.tar.gz" | sha256sum | cut -d' ' -f1)
gh api -H "Accept: application/vnd.github.raw" "repos/$TAP/contents/$F" >"$TMP/formula.rb"
# edit exactly two lines: url -> new tag, sha256 -> $SHA (keep everything else)
BLOB=$(gh api "repos/$TAP/contents/$F" --jq .sha)
gh api -X PUT "repos/$TAP/contents/$F" -f message="chore: <name> X.Y.Z" \
  -f sha="$BLOB" -f content="$(base64 -w0 "$TMP/formula.rb")"
```

- Edit the two lines yourself (you are the editor): `url "...tags/vX.Y.Z.tar.gz"`
  and `sha256 "<64 hex>"`. If `desc` quotes a check count, refresh it from
  `--list-checks | wc -l`. Never touch `install`/`test` blocks.
- `sha256sum` exists on Linux and Git Bash; macOS uses `shasum -a 256`.
  `base64 -w0` is GNU; on macOS plain `base64` already emits one line.
- The PUT is one commit on the tap's default branch — no clone. A 409/422
  (protected branch) → create `bump/<name>-X.Y.Z` in the tap
  (`gh api -X POST repos/$TAP/git/refs -f ref=refs/heads/bump/... -f sha=<default-branch sha>`),
  PUT with `-f branch=bump/...`, then `gh pr create -R $TAP`.
- `--dry-run`: the `gh api -X PUT/POST` and `gh pr create` calls print as
  `DRY-RUN:`; the curl/sha and the raw GET run for real.
- Re-probe: `homebrew-formula` must flip to `done:true` (the raw read is
  eventually consistent; wait a few seconds before declaring it stuck).

## 8. Post-flight

Re-run the probe: every step `done:true` (gh-release excepted when skipped,
homebrew-formula absent when not configured).
Then a quick doctor (`--checks missing-back-merge,orphaned-release-branch,tag-unpushed,sync-ahead,homebrew-formula-stale`).
Report: version, tag sha, PR links, release URL, back-merge status.

## Changelog

Section = conventional-commit summary of `git log <prev-tag>..release/X.Y.Z`
(first parent), grouped: BREAKING CHANGES, Features (`feat:`), Fixes (`fix:`),
Other. Format:

```markdown
## X.Y.Z (YYYY-MM-DD)

### Breaking changes
- ...
### Features
- ...
### Fixes
- ...
```
Write it to a temp file for `--notes-file` and prepend the same section to the
changelog file in step 1.

## State journal (optional hints)

`.git/gitflow/last-finish.json` may store `{branch, version, pr, mergeMethod}`
to avoid re-prompting. It is a hint only — the probe is the source of truth.
Never commit it (it lives under `.git/`).
