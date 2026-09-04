# verify.ps1 -- confirm the new PC matches the reference workstation.
# Read-only. Nothing here installs, logs in, or writes.
#
#   powershell -ExecutionPolicy Bypass -File C:\1Claude\scripts\newpc\verify.ps1
#
# ASCII only (PS 5.1 reads BOM-less UTF-8 as ANSI).

[CmdletBinding()]
param(
  [string]$Root = "C:\1Claude",
  [switch]$WithSideRepos,   # also require C:\2Claude, C:\7ClaudeMarketingAgents, C:\8Claude
  [switch]$WithAndroid      # also require the androidtools SDK
)

# Re-read PATH from the registry before checking anything. A shell opened as a
# tab in a Windows Terminal / VS Code that was ALREADY RUNNING before an install
# inherits the parent process's environment, not the registry -- so every tool
# reports MISSING even though it is installed and on the real PATH. Closing the
# tab does not help; only quitting the host app or rebooting does. Without this
# line the report is about the shell, not the machine.
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

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

Sect "Toolchain (reference versions from the source box DESKTOP1, re-captured 2026-09-04)"
Chk "git"        { (git --version) }                        "2.53"
Chk "node"       { (node --version) }                       "v24"
Chk "npm"        { (npm --version) }                        "11."
Chk "python"     { (python --version) }                     "3.12"
Chk "gh"         { (gh --version | Select-Object -First 1) } "2.87"
Chk "doppler"    { (doppler --version) }                    "v3.75"
Chk "java"       { (java -version 2>&1 | Select-Object -First 1) } "17.0"
Chk "ffmpeg"     { (ffmpeg -version | Select-Object -First 1) } "8.1"
Chk "claude"     { (claude --version) }                     "2.1"
Chk "codex"      { (codex --version) }                      "0.118"
Chk "railway"    { (railway --version) }                    "4.30"
# vercel and eas both write banners ("Vercel CLI x.y", "a newer eas-cli is available")
# to stderr, which PS 5.1 turns into a NativeCommandError in the caller. Pick the
# version line out of the combined stream instead of letting it leak.
Chk "vercel"     { (vercel --version 2>&1 | Select-String '^\d+\.' | Select-Object -First 1) } "50."
Chk "eas"        { (eas --version 2>&1 | Select-String 'eas-cli/' | Select-Object -First 1) }  "18."
Chk "terraform"  { (terraform --version | Select-Object -First 1) } "1.14"
Chk "gcloud"     { (gcloud --version 2>$null | Select-Object -First 1) } "Google Cloud SDK"
Write-Host "  [--]   ripgrep                    bundled with Claude Code (no standalone install on the source box)" -ForegroundColor DarkGray
Write-Host "  [--]   docker                     on the source box but NOT part of this build (WSL2 + 4 GB + always-on VM)" -ForegroundColor DarkGray

Sect "Git Bash (Claude Code needs it for the Bash tool AND the SessionStart hook)"
$bashGuess = @(
  $env:CLAUDE_CODE_GIT_BASH_PATH,
  (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
  (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe"),
  (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($bashGuess) {
  Write-Host ("  [ok]   {0,-26} {1}" -f "bash.exe", $bashGuess) -ForegroundColor Green; $pass++
  $cfg = Join-Path $env:USERPROFILE ".claude\settings.json"
  $pinned = ""
  if (Test-Path $cfg) {
    try { $pinned = (Get-Content $cfg -Raw | ConvertFrom-Json).env.CLAUDE_CODE_GIT_BASH_PATH } catch { $pinned = "" }
  }
  if ($pinned) { Write-Host ("  [ok]   {0,-26} {1}" -f "pinned in settings.json", $pinned) -ForegroundColor Green; $pass++ }
  else         { Write-Host ("  [warn] {0,-26} not pinned -- re-run setup.ps1 if Claude Code cannot find bash" -f "settings.json env") -ForegroundColor Yellow; $warn++ }
} else {
  Write-Host "  [FAIL] bash.exe not found -- install Git for Windows (winget install --id Git.Git --source winget)" -ForegroundColor Red; $fail++
}

Sect "Repos (all three must sit under $Root)"
Path1 (Join-Path $Root ".git")                    "grotap-agents"
Path1 (Join-Path $Root "platform\.git")           "grotap-platform"
Path1 (Join-Path $Root "grotap-landing\.git")     "grotap-landing"
Path1 (Join-Path $Root "CLAUDE.md")               "root CLAUDE.md"
Path1 (Join-Path $Root "agents\GLOBAL.md")        "agents/GLOBAL.md"
Path1 (Join-Path $Root ".claude-session-init.sh") "session init script"
Path1 (Join-Path $Root ".mcp.json")               "MCP config (checked in)"

if ($WithSideRepos) {
  Sect "Side folders (own machines only -- each is its own repo and secret boundary)"
  Path1 "C:\2Claude\.git"                "2Claude (corporate/legal)"
  Path1 "C:\7ClaudeMarketingAgents\.git" "7ClaudeMarketingAgents (marketing)"
  Path1 "C:\8Claude\.git"                "8Claude (back-office/finance)"

  # A PAT baked into a remote URL is a credential sitting in plaintext in .git/config,
  # readable by anything that can read the file and leaked by every 'git remote -v'.
  foreach ($sp in @("C:\2Claude", "C:\7ClaudeMarketingAgents", "C:\8Claude")) {
    if (Test-Path (Join-Path $sp ".git")) {
      $url = (git -C $sp remote get-url origin 2>$null)
      if ($url -match "github_pat_|ghp_|x-access-token:") {
        Write-Host ("  [FAIL] {0,-26} remote URL has an embedded token -- rotate it and reset the remote" -f (Split-Path $sp -Leaf)) -ForegroundColor Red
        $fail++
      } else {
        Write-Host ("  [ok]   {0,-26} remote URL carries no token (gh credential helper)" -f (Split-Path $sp -Leaf)) -ForegroundColor Green
        $pass++
      }
    }
  }
}

if ($WithAndroid) {
  Sect "Android build toolchain"
  Path1 (Join-Path $Root "androidtools\sdk\platform-tools") "platform-tools"
  Path1 (Join-Path $Root "androidtools\sdk\licenses")       "sdk licenses accepted"
  $ah = [Environment]::GetEnvironmentVariable("ANDROID_HOME", "User")
  if ($ah) { Write-Host ("  [ok]   {0,-26} {1}" -f "ANDROID_HOME", $ah) -ForegroundColor Green; $pass++ }
  else     { Write-Host ("  [FAIL] {0,-26} not set -- re-run setup.ps1 -WithAndroid" -f "ANDROID_HOME") -ForegroundColor Red; $fail++ }
}

Sect "Claude Code config"
$ch = Join-Path $env:USERPROFILE ".claude"
Path1 (Join-Path $ch "settings.json")  "user settings.json"
Path1 (Join-Path $ch "statusline.js")  "statusline.js"
Path1 (Join-Path $Root ".claude\settings.json")          "agents-repo settings"
Path1 (Join-Path $Root "platform\.claude\settings.json") "platform settings"
Path1 (Join-Path $Root "platform\.claude\agents\screenshot-verifier.md") "screenshot-verifier agent"
Path1 (Join-Path $Root "scripts\claudecode\session-start-hook.sh")       "SessionStart hook"
Path1 (Join-Path $ch "skills\neon-postgres\SKILL.md")                    "neon-postgres skill (user scope)"

# The statusline is a hook to an absolute path. Copy a settings.json between
# machines with different usernames and it silently points at a file that is not
# there -- statusline just goes blank, no error. Check the target actually exists.
$stCfg = Join-Path $ch "settings.json"
if (Test-Path $stCfg) {
  try {
    $sj = Get-Content $stCfg -Raw | ConvertFrom-Json
    if ($sj.model -eq "opus[1m]") { Write-Host ("  [ok]   {0,-26} {1}" -f "model", $sj.model) -ForegroundColor Green; $pass++ }
    else { Write-Host ("  [warn] {0,-26} {1}   (reference: opus[1m])" -f "model", $sj.model) -ForegroundColor Yellow; $warn++ }

    $slCmd = $sj.statusLine.command
    $slFile = ""
    if ($slCmd -match '"([^"]+statusline\.js)"') { $slFile = $Matches[1] }
    if ($slFile -and (Test-Path $slFile)) { Write-Host ("  [ok]   {0,-26} {1}" -f "statusline target", $slFile) -ForegroundColor Green; $pass++ }
    else { Write-Host ("  [FAIL] {0,-26} {1} -- wrong username in the path?" -f "statusline target", $slFile) -ForegroundColor Red; $fail++ }
  } catch {
    Write-Host "  [FAIL] settings.json is not valid JSON" -ForegroundColor Red; $fail++
  }
}

Sect "MCP servers"
if (Get-Command claude -ErrorAction SilentlyContinue) {
  $mcp = (claude mcp list 2>$null | Out-String)
  # chrome-devtools is USER scope (machine-local ~/.claude.json, not copied);
  # docs-langchain + playwright arrive with the clone via $Root\.mcp.json.
  foreach ($m in @("chrome-devtools")) {
    if ($mcp -match $m) { Write-Host ("  [ok]   {0,-26} user scope" -f $m) -ForegroundColor Green; $pass++ }
    else { Write-Host ("  [FAIL] {0,-26} not registered -- re-run setup.ps1" -f $m) -ForegroundColor Red; $fail++ }
  }
  Write-Host "  [--]   docs-langchain/playwright  project scope, arrive with the clone (confirm with /mcp in-session)" -ForegroundColor DarkGray
} else {
  Write-Host "  [FAIL] claude not on PATH" -ForegroundColor Red; $fail++
}

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
  foreach ($p in @("codex", "code-simplifier", "ui-ux-pro-max", "caveman")) {
    if ($pl -match $p) { Write-Host ("  [ok]   {0}" -f $p) -ForegroundColor Green; $pass++ }
    else               { Write-Host ("  [FAIL] {0} not installed" -f $p) -ForegroundColor Red; $fail++ }
  }
} else {
  Write-Host "  [FAIL] claude not on PATH" -ForegroundColor Red; $fail++
}

Sect "Claude memory (restored from the desktop export -- not in git, not reinstallable)"
# Reference counts from DESKTOP1 on 2026-09-04. The platform project is the one that
# matters: 431 files of accumulated lessons. A low count here means the import did not
# run, or ran before the project folder existed.
$refMemory = @{
  "C--1Claude-platform"      = 431
  "C--1Claude"               = 5
  "c--2Claude"               = 8
  "C--7ClaudeMarketingAgents" = 9
  "C--8Claude"               = 3
}
$projRoot = Join-Path $ch "projects"
foreach ($k in ($refMemory.Keys | Sort-Object)) {
  $mp = Join-Path $projRoot "$k\memory"
  if (Test-Path $mp) {
    $n = (Get-ChildItem $mp -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($n -ge $refMemory[$k]) {
      Write-Host ("  [ok]   {0,-26} {1} files" -f $k, $n) -ForegroundColor Green; $pass++
    } else {
      Write-Host ("  [warn] {0,-26} {1} files   (desktop had {2})" -f $k, $n, $refMemory[$k]) -ForegroundColor Yellow; $warn++
    }
  } else {
    Write-Host ("  [FAIL] {0,-26} no memory dir -- run memory-migrate.ps1 -Import" -f $k) -ForegroundColor Red; $fail++
  }
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
Write-Host "Last checks must be done inside a session: run 'claude' in C:\1Claude\platform and confirm" -ForegroundColor Cyan
Write-Host "  - the SessionStart banner prints '[bootstrap] repo: <sha> on master'" -ForegroundColor Cyan
Write-Host "  - the statusline reads 'Opus 5 | ctx N% [....] ~Nk/1000k'  (model is opus[1m])" -ForegroundColor Cyan
Write-Host "  - /mcp shows docs-langchain + playwright connected" -ForegroundColor Cyan
Write-Host "  - /plugin shows codex + code-simplifier + caveman enabled" -ForegroundColor Cyan
Write-Host "  - replies come back caveman-compressed (proves the caveman SessionStart hook fired)" -ForegroundColor Cyan
Write-Host "  - ask it 'what do you remember about the folder map' -- it should answer from memory" -ForegroundColor Cyan
Write-Host ""
