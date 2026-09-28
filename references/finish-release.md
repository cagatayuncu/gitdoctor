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
   Any probe `warnings` about tag divergence → STOP, show the user, do not retag.
   **Conflict forecast**: the probe's `forecast` lists the paths each PENDING
   leg would conflict on (`main`, `backMerge`; feature probes: `develop`).
   Show a non-empty forecast to the user BEFORE any merge. Recommended fix
   (fix-recipes.md#flow-branch-behind-main): merge main into the branch and
   let the branch's author resolve there, then re-run finish — the legs then
   merge clean. Continue into a forecast conflict only on the user's say-so.
   A probe warning that a LOWER hotfix is still open is informational: tell
   the user, proceed if they want this one first.
3. Resolve merge mode for main and for develop separately (SKILL.md
   § Merge-mode resolution).
4. `finish --abort` is only legal while `merged-to-main` is still false:
   close the PR if one was opened (`gh pr close <n>`), keep the branch, done.
   After merged-to-main, the only way out is forward — resume.

5. Render the message templates once (references/config.md § messages;
   defaults `Release {version}` / `Back-merge release {version}` /
   `Release {version}`): `{branch}` = `release/X.Y.Z`, `{tag}` = `vX.Y.Z`,
   `{version}` = `X.Y.Z`, `{type}` = `release`. Every `<messages.*>` below is
   the rendered string.

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
git merge --no-ff release/X.Y.Z -m "<messages.mergeToMain>"
```
Do NOT push yet — step 3+4 push main and the tag atomically. If `verify.main`
is configured, run § Verify on this merged main NOW, before tagging.

**PR mode** (main protected):
1. Reuse or create the PR:
   `gh pr list --head release/X.Y.Z --base main --state open --json number`
   → else `gh pr create --base main --head release/X.Y.Z --title "<messages.mergeToMain>" --body "<changelog section>"`
2. `gh pr checks <n> --watch --fail-fast` — on red: report the failing
   checks and stop (offer `gh pr merge <n> --auto` only if the user wants
   merge-on-green; the finish stays resumable either way).
3. `gh pr merge <n> --merge --delete-branch` (method per resolution; pass
   `--squash`/`--rebase` accordingly). `--admin` only on explicit user flag.

## 3. tag-exists

**Local mode**: `git tag -a vX.Y.Z -m "<messages.tag>"` on the merge commit
(HEAD of main after step 2).

**PR mode**: never tag a local sha — the merge happened on GitHub:
```bash
SHA=$(gh pr view <n> --json mergeCommit --jq .mergeCommit.oid)
git fetch origin main
git merge-base --is-ancestor "$SHA" origin/main   # verify before tagging
git tag -a vX.Y.Z "$SHA" -m "<messages.tag>"
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

A push from somewhere else in the meantime (a GUI "finish", a teammate) is
safe to meet: if origin already has exactly these commits the push is a no-op
and the re-probe shows the step done; if origin moved to OTHER commits, git
rejects the non-fast-forward push — stop, re-probe, never `--force`. Finish
from one tool in one session; do not split a finish between a GUI and this
flow (a half-done GUI finish is what the probe walk exists to repair).

## Verify (local-mode legs, when `verify` is configured)

A clean merge is not working code — two sides can merge textually and still
break the build. `verify.main` runs on the merged main before the tag is
created and pushed (step 2 → 3); `verify.develop` runs on the merged
back-merge target before its push (step 5). PR mode leaves this to CI.

1. **Read the commands from `origin/<main>`**, not from the branch being
   finished: `git show origin/<main>:.gitflow.json`. A branch must never be
   able to change what runs on the finisher's machine. First use in a
   session: show every `run` (and its `sideEffects` note) to the user and get
   a yes.
2. Run each entry from the repo root with a `timeoutMinutes` budget
   (default 15): `bash -o pipefail -c '<run>'` — `pipefail` so a pipe cannot
   hide a failing exit code. Windows Git Bash rewrites `/switch` arguments into
   paths (MSBuild `/t:Build` silently builds nothing): prefer dash switches
   (`-t:Build -m`) or prefix `MSYS2_ARG_CONV_EXCL='*'`.
3. If an entry has `expect` (a path glob that the run must create or update),
   check it: some tools exit 0 without doing the work.
4. Any failure → do NOT tag or push. Report the command, its exit code and
   the last lines of output. The merge exists only locally; after the user
   fixes the branch, undo it with `git reset --hard origin/<main>` (confirm
   first — it discards the unpushed merge commit) and re-run finish.
5. After a pass, tell the user what `sideEffects` may have touched (e.g. a
   build that rewrites an ignored local config).

## 5. back-merged (target: develop)

Merge **the tag** (`backmerge.strategy: merge-tag`, default) so main becomes
an ancestor of develop.

Develop unprotected:
```bash
git switch develop
git merge --ff-only origin/develop
git merge --no-ff vX.Y.Z -m "<messages.backMerge>"
# verify.develop configured → § Verify here, before the push
git push origin develop
```
Develop protected: carrier branch + PR:
```bash
git switch -c backmerge/release-X.Y.Z vX.Y.Z
git push -u origin backmerge/release-X.Y.Z
gh pr create --base develop --head backmerge/release-X.Y.Z --title "<messages.backMerge>" --fill
# checks → merge with the MERGE method if allowed; squash-only repos: see below
# after merge: delete the carrier branch (--delete-branch)
```

### Back-merge conflicts

Predict first: the probe's `forecast.backMerge` (before the tag exists it
stands the branch in for the tag); once tagged, re-check with
`git merge-tree --write-tree --name-only origin/develop vX.Y.Z`
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
- **Proposed resolution with evidence** (any leg, source files included): when
  a conflict is a union of two independent edits (one side deleted a comment,
  the other added lines next to it), you may PROPOSE the resolution: write
  it, `git add` it, then run
  `bash <skill-dir>/scripts/gitflow-doctor.sh --offline --merge-proof`.
  Per conflicted file it reports `oursPlusTheirChange` (resolved = ours +
  exactly their hunks), `theirsPlusOurChange` (the mirror), `markers`,
  `eolPreserved`, `bomPreserved` and a `validator` hint (`xml`/`json`/`yaml`:
  parse the staged file with it). Show the user the two diffs behind the
  first two fields (`git diff --cached HEAD -- <f>`, `git diff --cached
  MERGE_HEAD -- <f>`) and the verdict. Commit ONLY on the user's explicit yes;
  otherwise abort as above. `verdict:"consistent"` is evidence, not a licence
  — the user still decides. Diffs of generated content go through temporary
  files: on Git Bash `git diff --no-index <(...) <(...)` fails (git.exe cannot
  open `/proc/<pid>/fd`).
- **Same conflict twice** (`backmerge.strategy: merge-branch` replays the main
  leg's conflict on develop; `merge-tag` usually does not, because the tag
  already carries the resolution): run BOTH legs with
  `git -c rerere.enabled=true merge ...` and `git -c rerere.enabled=true commit`
  so the first resolution is recorded and replayed. A replayed resolution is
  still re-proved with `--merge-proof` and confirmed; `.git/rr-cache` stays in
  the repo — mention it.
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
