This bot runs gitdoctor and opens pull requests through the GitHub CLI.

- `git` is version 2.38 or newer (older versions cannot predict merge conflicts, and the bot then never opens a back-merge PR); confirm with `git --version`.
- `bash` is available (Git Bash on Windows); confirm with `bash --version`.
- The GitHub CLI is installed and signed in with access to the user's repositories; confirm with `gh auth status`. Signing in needs the user: ask them to complete `gh auth login` and wait.
- gitdoctor 0.5.0 or newer is installed, from Homebrew (`cagatayuncu/tap/gitdoctor`) or from https://github.com/cagatayuncu/gitdoctor with its install script or as the Claude Code plugin. Confirm that the doctor answers `--help` and that the back-merge tool beside it answers `--help` too (`gitdoctor-back-merge-pr --help` with Homebrew, `back-merge-pr.sh --help` otherwise).
