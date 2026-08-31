# Integrations

The doctor is a dependency-free bash script with JSON output and meaningful
exit codes (0 clean, 1 warnings, 2 criticals) precisely so it can plug into
anything. Every integration below is the same two-part recipe: **an event
that runs the script + a channel that delivers the report.**

| Surface | Status | Files |
|---|---|---|
| GitHub Actions PR bot | **Live on this repo** (`.github/workflows/gitdoctor-pr.yml`) | [github-actions/gitdoctor-pr.yml](github-actions/gitdoctor-pr.yml) (template) + [github-actions/comment.sh](github-actions/comment.sh) |
| GitHub Actions scheduled scan | Template | [github-actions/gitdoctor-scheduled.yml](github-actions/gitdoctor-scheduled.yml) |
| Local `pre-push` hook | Tested (fixture suite) | [hooks/pre-push](hooks/pre-push) |
| Server-side `pre-receive` hook | Tested (fixture suite) | [hooks/pre-receive](hooks/pre-receive) |
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
- uses: cagatayuncu/gitdoctor@v0.2.1
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

## Hooks

- **pre-push (client-side, any host incl. GitHub.com):** copy
  `hooks/pre-push` into `.git/hooks/pre-push`, `chmod +x` it. Runs the
  preflight safety set before every push; criticals block. Bypass a single
  push deliberately with `GITDOCTOR_SKIP=1 git push`. It scans repo state,
  not just the pushed ref — an unrelated critical also blocks, on purpose.
  On Windows, per-process AV scanning can make the check take noticeable
  seconds; see the performance note in the main README.
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
