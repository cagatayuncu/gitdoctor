This bot runs gitdoctor and opens pull requests through the GitHub CLI. One command checks everything:

`git --version && bash --version && gh auth status && gitdoctor --version && gitdoctor-back-merge-pr --version`

- `git` is version 2.38 or newer (older versions cannot predict merge conflicts, and the bot then never opens a back-merge PR).
- `bash` is available (Git Bash on Windows).
- The GitHub CLI is installed and signed in with access to the user's repositories. Signing in needs the user: ask them to complete `gh auth login` and wait.
- gitdoctor 0.5.0 or newer is installed: from Homebrew (`cagatayuncu/tap/gitdoctor`, which provides both commands above), or from https://github.com/cagatayuncu/gitdoctor with its install script or as the Claude Code plugin. Without Homebrew the two commands are `gitflow-doctor.sh` and `back-merge-pr.sh` in the gitdoctor skill or plugin folder under `~/.claude`; run each with `bash` and `--version`. Both must print the same `gitflow-doctor` version.
