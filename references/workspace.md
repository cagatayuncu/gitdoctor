# Workspace: several repos released in lockstep

Some products ship from several repos at once (backend + UIs, sometimes an
SDK) with the same version and the same hotfix branch name. The workspace flow
runs the single-repo flows side by side and adds the cross-repo checks. The
doctor stays single-repo per run; workspace mode only orchestrates reads.

## .gitflow-workspace.json

Lives outside the repos (a parent folder) or in one of them. Paths are
relative to the file.

```json
{
  "$schema": "https://raw.githubusercontent.com/cagatayuncu/gitdoctor/main/schema/gitflow-workspace.schema.json",
  "repos": [
    "../backend",
    "../management-ui",
    "../survey-ui",
    { "path": "../sdk-js", "optional": true }
  ],
  "pushPolicy": "all-verified"
}
```

- `optional: true`: the repo may be absent, or may lack the branch — it is
  reported as skipped, never as an error.
- `pushPolicy`: `all-verified` (default) — nothing is pushed anywhere until
  every repo is merged, tagged and verified locally; `per-repo` — each repo
  pushes as soon as its own legs pass.

**There is no cross-repo atomic push.** `all-verified` narrows the window, it
does not close it: if a push fails half-way, some repos are published and
some are not. Recovery is the normal probe walk per repo — every finish is
resumable — and the closing table shows exactly which repo is where.

## Status / preflight

```bash
bash <skill-dir>/scripts/gitflow-doctor.sh --workspace <file> [--branch hotfix/X] [--tag T]
```

JSON: `workspace.repos[]` with each repo's doctor `summary`, `main`,
`latestTag`; with `--branch`, `branch.present` and the embedded finish
`probe` (repo-level config fallback only — re-probe each repo with its full
config flags before mutating it); with `--tag`, the tag's `type`, `message`
template and `onMainTip`. `workspace.ready` is false while any required repo
is missing, any repo has a critical finding, or the tag drifts. Findings:
`workspace-repo-missing` (critical), `tag-convention-drift` (warning).

## Lockstep finish (`gitdoctor workspace finish <branch>`)

1. **Preflight all**: the workspace run above with `--branch`. Any
   `workspace-repo-missing` or critical → stop. Repos with
   `branch.present:false` are `skipped: no branch` for the rest of the flow.
2. **Forecast all**: show every repo's probe `forecast` before touching any
   of them. One repo forecast to conflict → offer to resolve on its branch
   first (fix-recipes.md#flow-branch-behind-main); do not start the others
   meanwhile unless the user says so.
3. **Local legs, repo by repo**: the single-repo finish (finish-release.md /
   finish-hotfix.md) up to — not including — any push: merge to main, § Verify,
   tag, back-merge, § Verify. PR mode repos: open the PRs, wait for green.
4. **Gate**: `all-verified` → continue only when every non-skipped repo passed
   step 3. Otherwise report the table and stop; nothing has been published.
5. **Push**, repo by repo (atomic main + tag inside each repo), then the
   back-merge pushes, then the GitHub Releases. Before the first push, run
   `--push-guard <main>,<develop>` in EVERY repo; one `safe:false` → push
   nowhere, report the table and stop (each repo keeps its own finish.lock:
   finish-release.md § Push guard and finish.lock).
6. **Consistency**: re-run with `--tag <tag>`; `tag-convention-drift` must be
   absent (same tag type, same message pattern, on main's tip everywhere).
7. **Branch deletion** per repo (the usual ancestry-verified rules).
8. **Closing table**:
   ```text
   repo            main      develop   tag              branch
   backend         8d8295b3  70152f97  2.0.0-hotfix.12  deleted
   management-ui   61f2e76c  9aa636e7  2.0.0-hotfix.12  deleted
   sdk-js          —         —         —                skipped: no branch
   ```
