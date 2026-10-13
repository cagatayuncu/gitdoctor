# Integrations

The doctor is a dependency-free bash script with JSON output and meaningful
exit codes (0 clean, 1 warnings, 2 criticals) precisely so it can plug into
anything. Every integration below is the same two-part recipe: **an event
that runs the script + a channel that delivers the report.**

| Surface | Status | Files |
|---|---|---|
| GitHub Actions PR bot | **Live on this repo** (`.github/workflows/gitdoctor-pr.yml`) | [github-actions/gitdoctor-pr.yml](github-actions/gitdoctor-pr.yml) (template) + [github-actions/comment.sh](github-actions/comment.sh) |
| GitHub Actions scheduled scan | Template | [github-actions/gitdoctor-scheduled.yml](github-actions/gitdoctor-scheduled.yml) |
| GitHub Actions back-merge PR | Template + action input `back-merge-pr`, script tested (fixture suite) | [github-actions/gitdoctor-back-merge.yml](github-actions/gitdoctor-back-merge.yml) + [github-actions/back-merge-pr.sh](github-actions/back-merge-pr.sh) |
| Local `pre-push` hook | Tested (fixture suite) | [hooks/pre-push](hooks/pre-push) |
| Server-side `pre-receive` hook | Tested (fixture suite) | [hooks/pre-receive](hooks/pre-receive) |
| pre-commit framework | Hook definition, tested (fixture suite) | [.pre-commit-hooks.yaml](../.pre-commit-hooks.yaml) → [hooks/pre-push](hooks/pre-push) |
| GitHub code scanning (SARIF) | Action input `sarif-file` | [action.yml](../action.yml), `--format sarif` |
| Cron watcher (no CI at all) | Script | [watcher/gitdoctor-watch.sh](watcher/gitdoctor-watch.sh) |
| GitLab CI | **Draft, untested on a live instance** | [gitlab/.gitlab-ci.yml](gitlab/.gitlab-ci.yml) |
| Bitbucket Pipelines | **Draft, untested on a live workspace** | [bitbucket/bitbucket-pipelines.yml](bitbucket/bitbucket-pipelines.yml) |
| Gitea / Forgejo | Note below | — |
| AI-agent schedule | Note below | — |

## GitHub Actions PR bot

The repo root ships a composite action (`action.yml`), so the whole bot is
one `uses:` line — copy `github-actions/gitdoctor-pr.yml` into your repo as
`.github/workflows/gitdoctor-pr.yml`:

```yaml
- uses: cagatayuncu/gitdoctor@v0.4.1
  # inputs (optional): checks, skip, min-severity, comment, fail-on, github-token
```

Every PR gets one self-updating comment with the findings and fix commands;
critical findings turn the check red (`fail-on: warning` tightens that,
`fail-on: never` makes it report-only). Mark the `doctor` job as a
**required status check** in branch protection and the merge button locks
until the finding is resolved. This repo's own `.github/workflows/gitdoctor-pr.yml`
dogfoods the action via `uses: ./`.

Notes:
- `fetch-depth: 0` + the explicit branch fetch are required — ancestry checks
  need real history, a shallow default checkout would degrade every finding
  to low confidence.
- PR checkouts are a detached merge ref, so the workflow skips the
  `detached-head` check by design.
- Code scanning: add `sarif-file: gitdoctor.sarif` and the action also uploads
  the findings to GitHub code scanning (job needs
  `permissions: security-events: write`; free on public repos, GitHub Advanced
  Security on private ones). Alerts anchor on `.gitflow.json` and carry a
  `check-id:key` fingerprint, so one finding stays one alert across runs until
  it clears. Standalone: `gitflow-doctor.sh --format sarif`.

## Back-merge PR

`missing-back-merge` is the one critical a bot can fix without deciding
anything: the repair is a single merge whose outcome git can predict. Copy
`github-actions/gitdoctor-back-merge.yml` into `.github/workflows/` and, on
weekday mornings, the action opens ONE pull request `backmerge/main → develop`
when main has commits develop lacks. Only when every gate passes:

- ancestry is certain (`confidence: high` — a shallow checkout never qualifies);
- `git merge-tree` predicts no conflicts (a conflicting back-merge belongs in
  `/gitdoctor finish` or the recipe, where every resolution is proven);
- no open `release/*` already contains main's tip (the hotfix flow sends the
  fix to develop through that release, finish-hotfix.md);
- no back-merge PR into develop is open yet (one from `/gitdoctor finish` in
  PR mode counts; a fork's PR never does). An open `backmerge/main` PR is
  fast-forwarded to the new main instead.
- git on the runner is 2.38 or newer, and the check could run at all (a
  single-branch checkout without develop reports `skipped-unavailable` and an
  Actions warning, never a quiet "not needed").

The head is a carrier branch at main's tip, never `main` itself, so resolving
a conflict on GitHub can't write to main. The carrier is only ever
fast-forwarded: after "Update branch" on GitHub it is left alone, and a
leftover carrier with foreign commits stops the run with "delete it" rather
than being overwritten. Merging stays with a person: the PR asks for
**Create a merge commit**, since a squash leaves the ancestry gap
(`back-merge-content-only`). Closing the PR unmerged does not silence it —
the gap is still there, so the next run opens it again; disable the workflow
to pause it. The action reports the outcome as
`steps.<id>.outputs.back-merge` and `back-merge-pr` (the URL). The same
script runs anywhere with git + gh: `back-merge-pr.sh --dry-run` reports what
it would do and changes nothing.

Setup: the job needs `contents: write` + `pull-requests: write`, and the repo
must allow it (Settings → Actions → General → Workflow permissions → *Allow
GitHub Actions to create and approve pull requests*); without it the script
says so and leaves the carrier pushed for the next run. PRs opened with the
default `GITHUB_TOKEN` start no other workflows, so if develop requires status
checks, give `actions/checkout` and the action a PAT or GitHub App token.

## Hooks

- **pre-push (client-side, any host incl. GitHub.com):** copy
  `hooks/pre-push` into `.git/hooks/pre-push`, `chmod +x` it. Runs the
  preflight safety set before every push; criticals block. Bypass a single
  push deliberately with `GITDOCTOR_SKIP=1 git push`. It scans repo state,
  not just the pushed ref — an unrelated critical also blocks, on purpose.
  On Windows, per-process AV scanning can make the check take noticeable
  seconds; see the performance note in the main README.
- **pre-commit framework:** the repo root ships `.pre-commit-hooks.yaml`, so
  ```yaml
  repos:
    - repo: https://github.com/cagatayuncu/gitdoctor
      rev: v0.4.1
      hooks:
        - id: gitdoctor-preflight
  ```
  plus `pre-commit install --hook-type pre-push` gives the same gate with
  nothing to copy — the doctor ships inside the hook checkout and the hook
  finds it there first.
- **pre-receive (server-side, self-hosted only):** copy `hooks/pre-receive`
  into `<bare-repo>/hooks/pre-receive` on the server. The full doctor needs a
  work tree, so this hook enforces the push-time gates inline (wrong-base
  hotfix/release, branch naming) and rejects the push at the server.
  GitHub.com does not run pre-receive hooks; GitHub Enterprise Server, Gitea
  and self-managed GitLab do.

## Cron watcher

For repos with no CI: `watcher/gitdoctor-watch.sh <repo-dir> [--webhook <url>]`
from any machine's crontab. It fetches, scans, remembers the previous run
(`.git/gitdoctor-watch.state`), and notifies only on NEW criticals — to a
Slack-compatible webhook, or stdout (cron mail) without one.

## Gitea / Forgejo

Gitea Actions runs GitHub-Actions-format workflows: the PR template works
as-is on runners whose images ship `gh` and `jq`; otherwise replace the
comment step with a `curl` against the Gitea API (same shape as the GitLab
draft). The pre-receive hook works natively on Gitea servers.

## AI-agent schedule (zero infrastructure)

The skill itself is the integration: give Claude Code a scheduled task such as
"run /gitdoctor doctor on ~/work/api and ~/work/web every morning and message
me anything critical". No CI, no server — the agent runs the same script and
reads the same JSON.
