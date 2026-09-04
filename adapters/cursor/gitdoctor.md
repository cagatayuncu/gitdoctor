# /gitdoctor — Git Flow operations

You are executing the gitdoctor skill. The full playbook lives next to this
command file:

1. Read `gitdoctor-skill/SKILL.md` (installed alongside this command under
   `.cursor/commands/` — or use the repo copy if this is the gitdoctor
   repo itself). Follow its command routing for the user's arguments
   (`init` | `start feature|release|hotfix` | `finish` | `doctor` | `sync` |
   `status` | `cleanup` | `explain <check-id>` | `baseline`).
2. The deterministic checker is `gitdoctor-skill/scripts/gitflow-doctor.sh` —
   run it with bash (Git Bash on Windows). You perform every mutation
   yourself, gated on its JSON output, exactly as SKILL.md prescribes.
3. Detailed choreographies: `gitdoctor-skill/references/*.md`.

Arguments after `/gitdoctor` are the subcommand, e.g.:
`/gitdoctor start release` or `/gitdoctor doctor`.
