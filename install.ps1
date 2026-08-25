# Installs the GitFlow skill for Claude Code (user-level) and optionally the
# Cursor command adapter into a target repo.
#
#   ./install.ps1                      # Claude Code only (~/.claude/skills/gitdoctor)
#   ./install.ps1 -CursorRepo C:\path  # + .cursor/commands/gitdoctor.md in that repo
param(
  [string]$CursorRepo = ""
)
$ErrorActionPreference = "Stop"
$src = $PSScriptRoot

$skillDir = Join-Path $HOME ".claude\skills\gitdoctor"
New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
# clean before copy so files removed upstream do not linger (mirrors install.sh)
foreach ($sub in @("references", "scripts")) {
  $p = Join-Path $skillDir $sub
  if (Test-Path $p) { Remove-Item -Recurse -Force $p }
}
Copy-Item -Force (Join-Path $src "SKILL.md") $skillDir
Copy-Item -Recurse -Force (Join-Path $src "references") $skillDir
Copy-Item -Recurse -Force (Join-Path $src "scripts") $skillDir
Write-Host "Claude Code skill installed: $skillDir"

if ($CursorRepo -ne "") {
  if (-not (Test-Path $CursorRepo)) { throw "CursorRepo path not found: $CursorRepo" }
  $cmdDir = Join-Path $CursorRepo ".cursor\commands"
  New-Item -ItemType Directory -Force -Path $cmdDir | Out-Null
  Copy-Item -Force (Join-Path $src "adapters\cursor\gitdoctor.md") (Join-Path $cmdDir "gitdoctor.md")
  # the command references the skill payload side-by-side
  $payload = Join-Path $cmdDir "gitdoctor-skill"
  New-Item -ItemType Directory -Force -Path $payload | Out-Null
  foreach ($sub in @("references", "scripts")) {
    $p = Join-Path $payload $sub
    if (Test-Path $p) { Remove-Item -Recurse -Force $p }
  }
  Copy-Item -Force (Join-Path $src "SKILL.md") $payload
  Copy-Item -Recurse -Force (Join-Path $src "references") $payload
  Copy-Item -Recurse -Force (Join-Path $src "scripts") $payload
  Write-Host "Cursor command installed: $cmdDir\gitdoctor.md (+ gitdoctor-skill payload)"
}
