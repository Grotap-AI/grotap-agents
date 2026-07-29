# verify.ps1 -- confirm the new PC matches the reference workstation.
# Read-only. Nothing here installs, logs in, or writes.
#
#   powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\verify.ps1
#
# ASCII only (PS 5.1 reads BOM-less UTF-8 as ANSI).

[CmdletBinding()]
param([string]$Root = "C:\1Claude")

$pass = 0; $fail = 0; $warn = 0

function Chk ([string]$label, [scriptblock]$test, [string]$expected = "") {
  $got = ""
  try { $got = (& $test) } catch { $got = "" }
  if ([string]::IsNullOrWhiteSpace($got)) {
    Write-Host ("  [FAIL] {0,-26} MISSING" -f $label) -ForegroundColor Red
    $script:fail++
  } else {
    $got = ($got -join " ").Trim()
    if ($expected -and ($got -notmatch [regex]::Escape($expected))) {
      Write-Host ("  [warn] {0,-26} {1}   (reference: {2})" -f $label, $got, $expected) -ForegroundColor Yellow
      $script:warn++
    } else {
      Write-Host ("  [ok]   {0,-26} {1}" -f $label, $got) -ForegroundColor Green
      $script:pass++
    }
  }
}
function Sect ([string]$m) { Write-Host ""; Write-Host "=== $m" -ForegroundColor Cyan }
function Path1 ([string]$p, [string]$label) {
  if (Test-Path $p) { Write-Host ("  [ok]   {0,-26} {1}" -f $label, $p) -ForegroundColor Green; $script:pass++ }
  else              { Write-Host ("  [FAIL] {0,-26} {1}" -f $label, $p) -ForegroundColor Red;   $script:fail++ }
}

Sect "Toolchain (reference versions from the source box, 2026-07-29)"
Chk "git"        { (git --version) }                        "2.53"
Chk "node"       { (node --version) }                       "v24"
Chk "npm"        { (npm --version) }                        "11."
Chk "python"     { (python --version) }                     "3.12"
Chk "gh"         { (gh --version | Select-Object -First 1) } "2.87"
Chk "doppler"    { (doppler --version) }                    "v3.75"
Chk "java"       { (java -version 2>&1 | Select-Object -First 1) } "17.0"
Chk "ffmpeg"     { (ffmpeg -version | Select-Object -First 1) }
Chk "claude"     { (claude --version) }
Chk "codex"      { (codex --version) }                      "0.118"
Chk "railway"    { (railway --version) }                    "4.30"
Chk "vercel"     { (vercel --version) }                     "50."
Chk "eas"        { (eas --version) }                        "18."
Write-Host "  [--]   ripgrep                    bundled with Claude Code (no standalone install on the source box)" -ForegroundColor DarkGray

Sect "Repos (all three must sit under $Root)"
Path1 (Join-Path $Root ".git")                    "grotap-agents"
Path1 (Join-Path $Root "platform\.git")           "grotap-platform"
Path1 (Join-Path $Root "grotap-landing\.git")     "grotap-landing"
Path1 (Join-Path $Root "CLAUDE.md")               "root CLAUDE.md"
Path1 (Join-Path $Root "agents\GLOBAL.md")        "agents/GLOBAL.md"
Path1 (Join-Path $Root ".claude-session-init.sh") "session init script"
Path1 (Join-Path $Root ".mcp.json")               "MCP config (checked in)"

Sect "Claude Code config"
$ch = Join-Path $env:USERPROFILE ".claude"
Path1 (Join-Path $ch "settings.json")  "user settings.json"
Path1 (Join-Path $ch "statusline.js")  "statusline.js"
Path1 (Join-Path $Root ".claude\settings.json")          "agents-repo settings"
Path1 (Join-Path $Root "platform\.claude\settings.json") "platform settings"
Path1 (Join-Path $Root "platform\.claude\agents\screenshot-verifier.md") "screenshot-verifier agent"
Path1 (Join-Path $Root "scripts\claudecode\session-start-hook.sh")       "SessionStart hook"

Sect "Playwright browsers"
$pw = Join-Path $env:LOCALAPPDATA "ms-playwright"
if (Test-Path $pw) {
  $b = (Get-ChildItem $pw -Directory | Where-Object { $_.Name -like "chromium*" } | Measure-Object).Count
  if ($b -gt 0) { Write-Host "  [ok]   chromium present in $pw" -ForegroundColor Green; $pass++ }
  else          { Write-Host "  [FAIL] no chromium in $pw -- run: npx playwright install" -ForegroundColor Red; $fail++ }
} else {
  Write-Host "  [FAIL] $pw missing -- run: npx playwright install" -ForegroundColor Red; $fail++
}

Sect "Plugins"
if (Get-Command claude -ErrorAction SilentlyContinue) {
  $pl = (claude plugin list 2>$null | Out-String)
  foreach ($p in @("codex", "code-simplifier", "ui-ux-pro-max")) {
    if ($pl -match $p) { Write-Host ("  [ok]   {0}" -f $p) -ForegroundColor Green; $pass++ }
    else               { Write-Host ("  [FAIL] {0} not installed" -f $p) -ForegroundColor Red; $fail++ }
  }
} else {
  Write-Host "  [FAIL] claude not on PATH" -ForegroundColor Red; $fail++
}

Sect "Logins (these are the ones only you can do)"
foreach ($c in @(
    @{ N = "gh";      C = { gh auth status } },
    @{ N = "railway"; C = { railway whoami } },
    @{ N = "vercel";  C = { vercel whoami } },
    @{ N = "doppler"; C = { doppler configure get token --plain } }
  )) {
  $out = ""
  try { $out = (& $c.C 2>$null | Out-String) } catch { $out = "" }
  if ([string]::IsNullOrWhiteSpace($out)) {
    Write-Host ("  [warn] {0,-10} not logged in" -f $c.N) -ForegroundColor Yellow; $warn++
  } else {
    Write-Host ("  [ok]   {0,-10} authenticated" -f $c.N) -ForegroundColor Green; $pass++
  }
}

Sect "End-to-end (needs doppler login + setup first)"
$platform = Join-Path $Root "platform"
if (Test-Path (Join-Path $platform "scripts\db.py")) {
  Push-Location $platform
  $sql = (doppler run -p grotap -c prd -- python scripts/db.py "select 1 as ok" 2>$null | Out-String)
  Pop-Location
  if ($sql -match "1") { Write-Host "  [ok]   Doppler -> Neon reachable" -ForegroundColor Green; $pass++ }
  else                 { Write-Host "  [warn] Doppler/Neon check did not return a row (log in + 'doppler setup' first)" -ForegroundColor Yellow; $warn++ }
} else {
  Write-Host "  [warn] platform\scripts\db.py missing -- clone grotap-platform" -ForegroundColor Yellow; $warn++
}

Write-Host ""
Write-Host ("RESULT: {0} ok, {1} warn, {2} FAIL" -f $pass, $warn, $fail) -ForegroundColor $(if ($fail -gt 0) { "Red" } else { "Green" })
Write-Host ""
Write-Host "Last check must be done inside a session: run 'claude' in C:\1Claude\platform and confirm" -ForegroundColor Cyan
Write-Host "  - the SessionStart banner prints '[bootstrap] repo: <sha> on master'" -ForegroundColor Cyan
Write-Host "  - the statusline reads 'Opus 5 | ctx N% [....] ~Nk/200k'" -ForegroundColor Cyan
Write-Host "  - /mcp shows docs-langchain + playwright connected" -ForegroundColor Cyan
Write-Host ""
