# Finish: hotfix/X.Y.Z

Same skeleton as finish-release.md — read that first. Probe:

```bash
bash <skill-dir>/scripts/gitflow-doctor.sh --probe finish-hotfix \
  --branch hotfix/X.Y.Z --version X.Y.Z [config flags]
```

Differences from a release finish:

## Back-merge target selection

The probe's `back-merged` step names the target. A `release/*` branch counts
as **open** only while it still has something to ship: its `vX.Y.Z` tag does
not exist yet, or its tip is not yet in main. A branch whose version is already
tagged and merged into main is a leftover from a completed finish — the probe
ignores it here (and says so in the step `detail`), while the doctor keeps
reporting it as `orphaned-release-branch` for cleanup.
- **Zero open release branches** → develop (exactly like a release finish).
- **Exactly one open `release/*`** → that release branch. The hotfix must
  flow into the pending release, which carries it to develop at its own
  finish. Merge the tag into the release branch (local merge if unprotected —
  release branches normally are; otherwise carrier-branch PR).
- **Multiple open releases** → probe reports `target:"ambiguous"`: STOP and
  ask the user which release takes the back-merge (the doctor already flagged
  multiple-release-branches).

If a release is later **aborted** after absorbing a hotfix back-merge, the
hotfix commits vanish from develop's future — the doctor's
`missing-back-merge` catches exactly this on the next run and prescribes the
main→develop repair. Rule: cleanup after any release abort is doctor-driven —
run the doctor immediately after aborting a release.

## Version guard (also applied at start)

Hotfix version must be `> latest tag on main` and `< any open release's
version`. Violation → warn: the hotfix collides with the pending release line
(e.g. release/1.3.0 open, latest v1.2.5 → hotfix is 1.2.6, not 1.3.x).

## Urgency affordance

CI wait blocking a production fix: `finish --admin` maps to
`gh pr merge --admin`. Only on the user's explicit flag — never suggest it as
the default path.

## Everything else

Version bump, PR-vs-local main leg, tag placement (`mergeCommit.oid` in PR
mode), atomic push in local mode, conflict policy, branch deletion rules,
`gh release create` — identical to finish-release.md steps 1-8.
