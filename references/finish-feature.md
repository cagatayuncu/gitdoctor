# Finish: feature/<name>

Merges the feature into develop and deletes the branch. No tag, no back-merge,
no version. Probe:

```bash
bash <skill-dir>/scripts/gitflow-doctor.sh --probe finish-feature --branch feature/<name> [config flags]
```

Steps: `merged-to-develop` → `remote-branch-deleted` → `local-branch-deleted`.
Skip done steps; re-probe after each mutation.

## merged-to-develop

**Local mode** (develop unprotected):
```bash
git switch feature/<name>
git pull --ff-only origin feature/<name>    # if a remote copy exists
git switch develop
git merge --ff-only origin/develop
git merge --no-ff feature/<name> -m "Merge feature/<name> into develop"
git push origin develop
```
Conflicts: features may conflict with develop in source files — resolve
interactively with the user (never silently), or abort cleanly and suggest
rebasing the feature first (`git rebase origin/develop feature/<name>`).

**PR mode** (develop protected):
1. `git push -u origin feature/<name>`
2. Reuse or create:
   `gh pr list --head feature/<name> --base develop --state open --json number`
   → else `gh pr create --base develop --head feature/<name> --fill`
3. `gh pr checks <n> --watch --fail-fast` — red: report and stop (offer
   `gh pr merge <n> --auto`); the finish resumes later.
4. `gh pr merge <n> --merge --delete-branch` (method per repo resolution).
5. `git fetch origin --prune && git switch develop && git merge --ff-only origin/develop`

## Branch deletion

- Remote: `--delete-branch` above, or `git push origin --delete feature/<name>`.
- Local: `git branch -d feature/<name>`; if it refuses (squash/rebase merge),
  verify `gh pr view <n> --json state --jq .state` = `MERGED`, then `-D`.
  Never `-D` on ancestry-unverified, gh-unverified branches.

## Post-flight

Re-probe: all three steps done (`merged-to-develop` shows `via:"branch-gone"`
once refs are deleted — that is expected). Report the merge (PR link or merge
commit) and the branch cleanup.
