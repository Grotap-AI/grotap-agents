# setup.ps1 -- rebuild the grotap Claude Code workstation on a fresh Windows PC.
#
# Run AFTER stage 0 (see scripts/newpc/README.md): Claude Code + Git + gh installed,
# gh authenticated, and grotap-agents cloned to C:\1Claude.
#
#   cd C:\1Claude
#   powershell -ExecutionPolicy Bypass -File scripts\newpc\setup.ps1
#
# Idempotent: safe to re-run. Installs nothing that is already present.
# Windows PowerShell 5.1 compatible -- no '&&', no ternary, no null-coalescing.
# ASCII only on purpose: PS 5.1 reads BOM-less UTF-8 as ANSI and mangles non-ASCII.

[CmdletBinding()]
param(
  [string]$Root         = "C:\1Claude",
  [switch]$SkipWinget,          # skip the system package phase
  [switch]$SkipPython,          # skip pip install (slow)
  [switch]$SkipPlaywright,      # skip browser download (~500 MB)
  [switch]$WithAndroid          # ALSO build C:\1Claude\androidtools (~1 GB, Scan M APK builds)
)

$ErrorActionPreference = "Continue"
$script:Failures = @()

function Say    ([string]$m) { Write-Host ""; Write-Host "=== $m" -ForegroundColor Cyan }
function Ok     ([string]$m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Info   ([string]$m) { Write-Host "  [..]   $m" -ForegroundColor Gray }
function Warned ([string]$m) { Write-Host "  [warn] $m" -ForegroundColor Yellow }
function Failed ([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:Failures += $m }

function Refresh-Path {
  # winget-installed tools do not appear in this process's PATH until we re-read it.
  $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $user    = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = "$machine;$user"
}

function Have ([string]$exe) {
  $c = Get-Command $exe -ErrorAction SilentlyContinue
  return ($null -ne $c)
}

# ---------------------------------------------------------------- preflight --
Say "Preflight"
if (-not (Test-Path (Join-Path $PSScriptRoot "python-requirements.txt"))) {
  Failed "run this from the cloned repo: $Root\scripts\newpc\setup.ps1"
  exit 1
}
Info "PowerShell $($PSVersionTable.PSVersion)"
Info "Root       $Root"
if (-not (Test-Path $Root)) { Failed "$Root does not exist -- clone grotap-agents there first"; exit 1 }

# ------------------------------------------------------- 1. system packages --
if ($SkipWinget) {
  Say "1/8 System packages -- SKIPPED (-SkipWinget)"
} else {
  Say "1/8 System packages (winget)"
  if (-not (Have "winget")) {
    Failed "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
  } else {
    $pkgs = @(
      @{ Id = "Git.Git";                  Name = "Git for Windows (gives Claude Code its Bash tool)" },
      @{ Id = "OpenJS.NodeJS.LTS";        Name = "Node.js LTS" },
      @{ Id = "Python.Python.3.12";       Name = "Python 3.12 (NOT 3.13/3.14 -- native deps)" },
      @{ Id = "GitHub.cli";               Name = "GitHub CLI" },
      @{ Id = "Doppler.doppler";          Name = "Doppler CLI (all secrets live here)" },
      @{ Id = "Gyan.FFmpeg";              Name = "ffmpeg (marketing / video)" },
      @{ Id = "Microsoft.OpenJDK.17";     Name = "Microsoft OpenJDK 17" }
    )
    foreach ($p in $pkgs) {
      $installed = winget list --id $p.Id --exact --disable-interactivity 2>$null | Select-String -Pattern ([regex]::Escape($p.Id))
      if ($installed) {
        Ok "$($p.Name) -- already installed"
      } else {
        Info "installing $($p.Name) ..."
        winget install --id $p.Id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) { Ok $p.Name } else { Failed "$($p.Name) (winget exit $LASTEXITCODE) -- may need an elevated shell" }
      }
    }
    Refresh-Path
    # ripgrep is deliberately NOT installed: Claude Code ships its own copy and
    # puts it on the Bash tool's PATH. The source box has no standalone rg.
  }
}

# ------------------------------------------------------------ 2. npm global --
Say "2/8 Global npm packages"
if (-not (Have "npm")) {
  Failed "npm not on PATH -- open a NEW terminal (winget PATH changes need it) and re-run"
} else {
  $npmPkgs = @(
    "@openai/codex@0.118.0",   # required by the /codex:* pre-commit review gate
    "@railway/cli@4.30.5",
    "vercel@50.25.6",
    "eas-cli@18.1.0",          # Expo builds (Scan M / ScanTap mobile)
    "@playwright/cli@0.1.1",
    "uipro-cli@2.2.3"          # ui-ux-pro-max skill helper
  )
  foreach ($p in $npmPkgs) {
    Info "npm i -g $p"
    npm install -g $p --silent
    if ($LASTEXITCODE -eq 0) { Ok $p } else { Failed "npm install -g $p" }
  }
  Refresh-Path
}

# ------------------------------------------------- 3. playwright browsers ----
if ($SkipPlaywright) {
  Say "3/8 Playwright browsers -- SKIPPED (-SkipPlaywright)"
} else {
  Say "3/8 Playwright browsers (chromium/firefox/webkit -- needed by every screenshot + E2E task)"
  npx --yes playwright install
  if ($LASTEXITCODE -eq 0) { Ok "browsers installed" } else { Failed "npx playwright install" }
}

# ------------------------------------------------------------ 4. python -----
if ($SkipPython) {
  Say "4/8 Python packages -- SKIPPED (-SkipPython)"
} else {
  Say "4/8 Python packages (exact freeze of the working box, 113 pins)"
  $py = "python"
  if (Have "py") { $py = "py" }
  $reqs = Join-Path $PSScriptRoot "python-requirements.txt"
  if ($py -eq "py") {
    py -3.12 -m pip install --upgrade pip --quiet
    py -3.12 -m pip install -r $reqs
  } else {
    python -m pip install --upgrade pip --quiet
    python -m pip install -r $reqs
  }
  if ($LASTEXITCODE -eq 0) { Ok "python packages installed" } else { Failed "pip install -r python-requirements.txt" }
}

# ------------------------------------------------------------- 5. repos -----
Say "5/8 Repos"
$repos = @(
  @{ Slug = "Grotap-AI/grotap-platform"; Path = (Join-Path $Root "platform");        Note = "application code" },
  @{ Slug = "Grotap-AI/grotap-landing";  Path = (Join-Path $Root "grotap-landing");  Note = "marketing site" }
)
foreach ($r in $repos) {
  if (Test-Path (Join-Path $r.Path ".git")) {
    Ok "$($r.Slug) already at $($r.Path)"
  } else {
    Info "cloning $($r.Slug) -> $($r.Path) ($($r.Note))"
    if (Have "gh") { gh repo clone $r.Slug $r.Path } else { git clone "https://github.com/$($r.Slug).git" $r.Path }
    if (Test-Path (Join-Path $r.Path ".git")) { Ok $r.Slug } else { Failed "clone $($r.Slug) -- is 'gh auth login' done?" }
  }
}

# --------------------------------------------- 6. user-level Claude config --
Say "6/8 User-level Claude Code config (~/.claude)"
$claudeHome = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $claudeHome)) { New-Item -ItemType Directory -Path $claudeHome -Force | Out-Null }

# statusline.js
$slSrc = Join-Path $PSScriptRoot "claude-user\statusline.js"
$slDst = Join-Path $claudeHome  "statusline.js"
Copy-Item $slSrc $slDst -Force
Ok "statusline.js"

# settings.json -- back up anything already there, then template in the real home path
$stSrc = Join-Path $PSScriptRoot "claude-user\settings.json"
$stDst = Join-Path $claudeHome  "settings.json"
if (Test-Path $stDst) {
  $bak = "$stDst.bak"
  Copy-Item $stDst $bak -Force
  Warned "existing settings.json backed up to $bak"
}
$body = Get-Content $stSrc -Raw
$body = $body.Replace("__CLAUDE_HOME__", $claudeHome.Replace("\", "\\"))
Set-Content -Path $stDst -Value $body -Encoding utf8
Ok "settings.json (model=opus, light, fullscreen, bell hook, statusline, marketplaces)"

# ------------------------------------------------------------ 7. plugins ----
Say "7/8 Plugins"
if (-not (Have "claude")) {
  Warned "claude not on PATH yet -- skipping. Re-run this script (or just this phase) after Claude Code is installed."
} else {
  claude plugin marketplace add openai/codex-plugin-cc
  claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
  Ok "marketplaces registered (openai-codex, ui-ux-pro-max-skill)"

  # codex + code-simplifier are PROJECT-scoped to the platform repo on the source box
  $platform = Join-Path $Root "platform"
  if (Test-Path $platform) {
    Push-Location $platform
    claude plugin install codex@openai-codex --scope project
    claude plugin install code-simplifier@claude-plugins-official --scope project
    Pop-Location
    Ok "codex + code-simplifier installed (project scope: $platform)"
  } else {
    Warned "platform repo missing -- install codex/code-simplifier after it is cloned"
  }

  # ui-ux-pro-max: installed at USER scope but left DISABLED (the platform repo
  # carries its own copy at platform/.claude/skills/ui-ux-pro-max).
  claude plugin install ui-ux-pro-max@ui-ux-pro-max-skill --scope user
  Ok "ui-ux-pro-max installed at user scope (kept disabled by settings.json)"
}

# ------------------------------------------------------------ 8. android ----
if (-not $WithAndroid) {
  Say "8/8 Android build toolchain -- SKIPPED (pass -WithAndroid to build it)"
  Info "Only needed to build the Scan M APK locally. ~1 GB. See README.md section 'Android'."
} else {
  Say "8/8 Android build toolchain (C:\1Claude\androidtools)"
  $at  = Join-Path $Root "androidtools"
  $sdk = Join-Path $at "sdk"
  New-Item -ItemType Directory -Path $sdk -Force | Out-Null
  $cmdlineBin = Join-Path $sdk "cmdline-tools\latest\bin\sdkmanager.bat"
  if (-not (Test-Path $cmdlineBin)) {
    $zip = Join-Path $env:TEMP "android-cmdline-tools.zip"
    Info "downloading Android command-line tools ..."
    Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath (Join-Path $sdk "_tmp") -Force
    New-Item -ItemType Directory -Path (Join-Path $sdk "cmdline-tools") -Force | Out-Null
    # We only get here when sdkmanager.bat was missing, so an existing 'latest'
    # is a broken partial run. Clear it first: Move-Item -Force onto an existing
    # DIRECTORY nests (latest\cmdline-tools\bin\...) instead of replacing.
    $latest = Join-Path $sdk "cmdline-tools\latest"
    if (Test-Path $latest) { Remove-Item $latest -Recurse -Force }
    Move-Item (Join-Path $sdk "_tmp\cmdline-tools") $latest -Force
    Remove-Item (Join-Path $sdk "_tmp") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path $cmdlineBin) {
    $env:ANDROID_HOME     = $sdk
    $env:ANDROID_SDK_ROOT = $sdk
    # Same component set as the working box.
    $comps = @("platform-tools", "platforms;android-35", "build-tools;35.0.0", "build-tools;34.0.0", "ndk;26.1.10909125", "cmake;3.22.1")
    ("y`n" * 60) | & $cmdlineBin --licenses --sdk_root="$sdk"
    foreach ($c in $comps) {
      Info "sdkmanager $c"
      & $cmdlineBin --sdk_root="$sdk" $c
    }
    [Environment]::SetEnvironmentVariable("ANDROID_HOME", $sdk, "User")
    [Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", $sdk, "User")
    Ok "Android SDK at $sdk (ANDROID_HOME set for your user)"
    Info "JDK 17 comes from winget (Microsoft.OpenJDK.17); JAVA_HOME is set by that installer."
  } else {
    Failed "Android cmdline-tools -- download or unzip failed. Zip androidtools\ from the old PC instead (it is relocatable)."
  }
}

# ------------------------------------------------------------- summary ------
Say "Summary"
if ($script:Failures.Count -eq 0) {
  Ok "every phase completed"
} else {
  Write-Host "  $($script:Failures.Count) phase(s) failed:" -ForegroundColor Red
  foreach ($f in $script:Failures) { Write-Host "    - $f" -ForegroundColor Red }
}

Write-Host ""
Write-Host "REMAINING: interactive logins -- nothing above can do these for you." -ForegroundColor Yellow
Write-Host "  claude                 # then /login" -ForegroundColor Yellow
Write-Host "  gh auth login" -ForegroundColor Yellow
Write-Host "  doppler login          # then, in C:\1Claude\platform:  doppler setup -p grotap -c dev" -ForegroundColor Yellow
Write-Host "  codex login" -ForegroundColor Yellow
Write-Host "  railway login" -ForegroundColor Yellow
Write-Host "  vercel login" -ForegroundColor Yellow
Write-Host ""
Write-Host "  SSH fleet key: copy ~/.ssh/grotap_agents (+ .pub, config) by password manager or USB." -ForegroundColor Yellow
Write-Host "  NEVER through chat or a repo." -ForegroundColor Yellow
Write-Host ""
Write-Host "Then verify:  powershell -ExecutionPolicy Bypass -File $PSScriptRoot\verify.ps1" -ForegroundColor Cyan
Write-Host ""
