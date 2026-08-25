# Version file presets

Each preset defines a detection `pattern` (POSIX ERE; capture group 1 = the
current version — pass verbatim as the doctor's `--version-pattern`) and the
edit rule for the bump step. Apply edits with a plain Edit of the matched line
(first match only).

| Preset | File | Pattern | Bumped line |
|---|---|---|---|
| `package-json` | package.json | `"version"[[:space:]]*:[[:space:]]*"([^"]+)"` | `"version": "{version}"` |
| `csproj` | *.csproj | `<Version>([^<]+)</Version>` | `<Version>{version}</Version>` |
| `pyproject` | pyproject.toml | `^version[[:space:]]*=[[:space:]]*"([^"]+)"` | `version = "{version}"` |
| `cargo-toml` | Cargo.toml | `^version[[:space:]]*=[[:space:]]*"([^"]+)"` | `version = "{version}"` |
| `plain` | VERSION | `^([0-9A-Za-z.+-]+)$` | `{version}` |

Notes:
- The doctor and probes match the FIRST occurrence in the file. For
  package.json the top-level `version` is first in practice; a jsonpath-aware
  engine is deliberately out of scope for v1 (documented limitation).
- `pyproject`/`cargo-toml` share a pattern; the `^` anchor keeps table
  headers like `[package]` from matching. If a repo has both `[project]` and
  `[tool.poetry]` versions, point `path` at the file and accept first-match,
  or use a raw `pattern` tightened for that repo.
- Multiple files are supported — one `versionFiles[]` entry each; the bump
  step must update ALL of them in the same commit, and the probes verify all.
- Custom entries: `{ "path": "app/build.gradle", "pattern": "versionName[[:space:]]+\"([^\"]+)\"", "replace": "versionName \"{version}\"" }`.
