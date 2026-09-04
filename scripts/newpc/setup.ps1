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
  [switch]$SkipApps,            # skip the workstation apps (Chrome, Bitwarden, Drive, ShareX,
                                #   terraform, gcloud, Chrome Remote Desktop) -- toolchain only
  [switch]$WithAndroid,         # ALSO build C:\1Claude\androidtools (~1 GB, Scan M APK builds)
  [switch]$WithSideRepos,       # ALSO clone C:\2Claude, C:\7ClaudeMarketingAgents, C:\8Claude
                                #   (owner's own second machine only -- 2Claude is corporate/legal)
  [string]$GitName,             # commit identity for every repo -- REQUIRED to set any
  [string]$GitEmail             #   e.g. -GitName "Mike G" -GitEmail "mike@example.com"
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
# Do this FIRST, before any Have() check: a shell opened as a tab in an
# already-running Windows Terminal / VS Code inherits that parent's stale
# environment rather than the registry, so previously-installed tools look
# absent and we would reinstall (or wrongly report) them.
Refresh-Path
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
    # Workstation apps -- also on the source box, and each one is load-bearing for
    # some task rather than decoration. Skippable with -SkipApps if you only want
    # the toolchain.
    if (-not $SkipApps) {
      $pkgs += @(
        @{ Id = "Google.Chrome";               Name = "Google Chrome (the chrome-devtools MCP drives THIS, and OAuth logins need it)" },
        @{ Id = "Bitwarden.Bitwarden";         Name = "Bitwarden (every login below comes out of here)" },
        @{ Id = "Google.GoogleDrive";          Name = "Google Drive (report/ledger delivery, memory-export handoff)" },
        @{ Id = "ShareX.ShareX";               Name = "ShareX (screenshots; source box also has paid Snagit -- install that yourself)" },
        @{ Id = "Hashicorp.Terraform";         Name = "Terraform (Hetzner fleet infra)" },
        @{ Id = "Google.CloudSDK";             Name = "Google Cloud SDK (gcloud)" },
        @{ Id = "Google.ChromeRemoteDesktop";  Name = "Chrome Remote Desktop (reach the desktop from the field)" }
      )
    }
    # --source winget is MANDATORY, not tidiness. On a box where the msstore
    # source has a bad cert, plain 'winget install' aborts every package with
    # 0x8A15005E / exit -1978335138 ("server certificate did not match"), even
    # though the package was found in the winget source. Pinning the source
    # skips msstore entirely and needs no elevation.
    # -1978335189 = 0x8A15002B (already installed, no applicable upgrade) = success.
    $okCodes = @(0, -1978335189)
    foreach ($p in $pkgs) {
      $installed = winget list --id $p.Id --exact --disable-interactivity 2>$null | Select-String -Pattern ([regex]::Escape($p.Id))
      if ($installed) {
        Ok "$($p.Name) -- already installed"
      } else {
        Info "installing $($p.Name) ..."
        winget install --id $p.Id --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($okCodes -contains $LASTEXITCODE) {
          Ok $p.Name
        } elseif ($LASTEXITCODE -eq -1978335138) {
          Failed "$($p.Name) -- winget source cert failure (0x8A15005E). Run 'winget source reset --force' in an ELEVATED shell, then re-run this script."
        } else {
          Failed "$($p.Name) (winget exit $LASTEXITCODE) -- try an elevated shell"
        }
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

# The other three top-level Claude folders. Each is its own repo and its own secret
# boundary (see the grotap-folder-map memory), which is why they are siblings of
# $Root and not subfolders. Opt-in: 2Claude is corporate/legal and must not land on
# someone else's machine just because they ran this script.
$sideRepos = @(
  @{ Slug = "Grotap1/qsbs-stacking-plan";       Path = "C:\2Claude";                 Note = "corporate/legal -- C-Corp, QSBS, trusts" },
  @{ Slug = "Grotap1/grotap-marketing-agents";  Path = "C:\7ClaudeMarketingAgents";  Note = "marketing -- Ayrshare, Doppler grotap-marketing" },
  @{ Slug = "Grotap1/grotap-expense-ledger";    Path = "C:\8Claude";                 Note = "back-office/finance -- ledgers, billing, inventory" }
)
if ($WithSideRepos) {
  foreach ($r in $sideRepos) {
    if (Test-Path (Join-Path $r.Path ".git")) {
      Ok "$($r.Slug) already at $($r.Path)"
    } else {
      Info "cloning $($r.Slug) -> $($r.Path) ($($r.Note))"
      if (Have "gh") { gh repo clone $r.Slug $r.Path } else { git clone "https://github.com/$($r.Slug).git" $r.Path }
      if (Test-Path (Join-Path $r.Path ".git")) { Ok $r.Slug } else { Failed "clone $($r.Slug) -- is 'gh auth login' done?" }
    }
  }
} else {
  Say "5b/8 Side folders (2Claude / 7ClaudeMarketingAgents / 8Claude) -- SKIPPED"
  Info "Pass -WithSideRepos to clone them. Owner's own machines only."
}

# Per-repo commit identity. .git/config is NOT part of a clone, so without this
# git refuses to commit at all. But NEVER default to the original owner's
# identity: this script is used to stand up machines for OTHER PEOPLE, and
# silently stamping someone else's name on their commits destroys attribution
# and is a pain to unpick after the fact. Require it explicitly.
if ($GitName -and $GitEmail) {
  $identityPaths = @($Root, (Join-Path $Root "platform"), (Join-Path $Root "grotap-landing"))
  if ($WithSideRepos) { $identityPaths += ($sideRepos | ForEach-Object { $_.Path }) }
  foreach ($p in $identityPaths) {
    if (Test-Path (Join-Path $p ".git")) {
      git -C $p config user.name  $GitName
      git -C $p config user.email $GitEmail
      Ok "identity $GitName <$GitEmail> -> $p"
    }
  }
} else {
  Warned "commit identity NOT set (no -GitName/-GitEmail). git will refuse to commit until you set it:"
  Info   "  git -C $Root config user.name  ""Your Name"""
  Info   "  git -C $Root config user.email ""you@example.com""   (repeat for platform + grotap-landing)"
}

# Git credential helper -> gh. Without it, git on Windows falls back to the
# wincredman store, which a non-interactive session cannot reach at all
# ("fatal: Unable to persist credentials with the 'wincredman' credential store").
#
# This CANNOT be set with 'git config' from PowerShell 5.1: the value contains
# embedded double quotes, PS 5.1 re-splits them, and git reports "wrong number of
# arguments, should be 2". It also cannot be written unescaped -- git's own config
# parser treats a bare " as a value delimiter and strips it, after which every
# fetch dies with "C:/Program: No such file or directory". The inner quotes must be
# backslash-escaped inside the outer quotes. Write the block to ~/.gitconfig by hand.
$ghExe = ""
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
if ($ghCmd) { $ghExe = $ghCmd.Source.Replace("\", "/") }
if ($ghExe) {
  $gitCfg  = Join-Path $env:USERPROFILE ".gitconfig"
  $existing = ""
  if (Test-Path $gitCfg) { $existing = (Get-Content $gitCfg -Raw) }
  if ($existing -match "gh\.exe.{0,4} auth git-credential") {
    Ok "git credential helper -> gh (already configured)"
  } else {
    if (Test-Path $gitCfg) { Copy-Item $gitCfg "$gitCfg.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force }

    # Preferred: let gh write it. It shells out itself, so PS 5.1 never sees the
    # quotes, and it produces exactly the form the source box has. Needs gh to be
    # authenticated already -- which stage 0 does before this script runs.
    gh auth setup-git 2>$null

    $got = (git config --global --get-all credential.https://github.com.helper | Where-Object { $_ } | Select-Object -Last 1)
    if ($got -notmatch "auth git-credential") {
      # Fallback: write the block ourselves, with the inner quotes escaped. Verified
      # 2026-09-04 to survive git's config parser and come back out intact.
      Warned "gh auth setup-git did not take (not logged in yet?) -- writing the block by hand"
      $block = @(
        "",
        "[credential ""https://github.com""]",
        ("`thelper = " + '"!\"' + $ghExe + '\" auth git-credential"'),
        "[credential ""https://gist.github.com""]",
        ("`thelper = " + '"!\"' + $ghExe + '\" auth git-credential"')
      )
      Add-Content -Path $gitCfg -Value $block -Encoding utf8
      $got = (git config --global --get-all credential.https://github.com.helper | Where-Object { $_ } | Select-Object -Last 1)
    }
    if ($got -match "auth git-credential") { Ok "git credential helper -> gh ($got)" }
    else { Failed "git credential helper not set -- run 'gh auth login' then 'gh auth setup-git'" }
  }
} else {
  Warned "gh not on PATH -- git credential helper not configured. Re-run after installing GitHub CLI."
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

# Claude Code needs Git Bash for its Bash tool, and it does not always find it
# on its own -- it then refuses to start with "set CLAUDE_CODE_GIT_BASH_PATH".
# Our SessionStart hook is bash -c '...', so PowerShell fallback is not enough.
# Pin the path whenever we can actually locate bash.exe.
$bashCandidates = @(
  (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
  (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe"),
  (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
)
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
  # <gitroot>\cmd\git.exe -> <gitroot>\bin\bash.exe
  $gitRoot = Split-Path (Split-Path $gitCmd.Source -Parent) -Parent
  $bashCandidates += (Join-Path $gitRoot "bin\bash.exe")
}
$bashPath = $bashCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($bashPath) {
  $obj = $body | ConvertFrom-Json
  $obj | Add-Member -NotePropertyName "env" -NotePropertyValue ([pscustomobject]@{ CLAUDE_CODE_GIT_BASH_PATH = $bashPath }) -Force
  $body = $obj | ConvertTo-Json -Depth 10
  Ok "Git Bash pinned: $bashPath"
} else {
  Warned "bash.exe not found -- Claude Code may refuse to start. Install Git for Windows, then re-run this script."
}

Set-Content -Path $stDst -Value $body -Encoding utf8
Ok "settings.json (model=opus[1m], light, fullscreen, bell hook, statusline, marketplaces)"

# User-scoped skills. On the source box ~/.claude/skills/neon-postgres is a symlink
# into ~/.agents/skills/ (where the caveman installer also drops its own skills).
# Symlinks need admin or Developer Mode on Windows, so copy the folder instead --
# Claude Code reads either. The caveman-* skills in ~/.agents come back with the
# plugin in phase 7; only neon-postgres is hand-placed and would otherwise be lost.
$skSrc = Join-Path $PSScriptRoot "claude-user\skills"
if (Test-Path $skSrc) {
  $skDst = Join-Path $claudeHome "skills"
  if (-not (Test-Path $skDst)) { New-Item -ItemType Directory -Path $skDst -Force | Out-Null }
  foreach ($s in (Get-ChildItem $skSrc -Directory)) {
    $t = Join-Path $skDst $s.Name
    if (Test-Path (Join-Path $t "SKILL.md")) { Ok "skill $($s.Name) already present" }
    else {
      Copy-Item $s.FullName $skDst -Recurse -Force
      Ok "skill $($s.Name)"
    }
  }
}

# User-scoped MCP server. Project MCP servers arrive with the clone via .mcp.json,
# but chrome-devtools is registered at USER scope on the source box (it lives in
# ~/.claude.json, which is machine-local state we do not copy). Re-add it here.
# --browserUrl points at Chrome started with --remote-debugging-port=9222.
if (Have "claude") {
  $mcpList = (claude mcp list 2>$null | Out-String)
  if ($mcpList -match "chrome-devtools") {
    Ok "MCP chrome-devtools already registered"
  } else {
    claude mcp add --scope user chrome-devtools -- npx -y chrome-devtools-mcp@latest --browserUrl http://127.0.0.1:9222
    if ($LASTEXITCODE -eq 0) { Ok "MCP chrome-devtools (user scope)" } else { Failed "claude mcp add chrome-devtools" }
  }
} else {
  Warned "claude not on PATH -- chrome-devtools MCP not registered. Re-run this script after Claude Code installs."
}

# ------------------------------------------------------------ 7. plugins ----
Say "7/8 Plugins"
if (-not (Have "claude")) {
  Warned "claude not on PATH yet -- skipping. Re-run this script (or just this phase) after Claude Code is installed."
} else {
  claude plugin marketplace add openai/codex-plugin-cc
  claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
  claude plugin marketplace add JuliusBrussee/caveman
  Ok "marketplaces registered (openai-codex, ui-ux-pro-max-skill, caveman)"

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

  # caveman: user scope and ENABLED on the source box (settings.json turns it on).
  # It supplies the response-compression SessionStart hook plus the cavecrew agents
  # and caveman-* skills, which it installs into ~/.agents/skills/.
  #
  # HISTORY, so nobody reintroduces the workaround: on CLI 2.1.236 (Aug 2026) this
  # install died with "Validation errors: agents: Invalid input" because upstream's
  # manifest carried an 'agents' key the CLI rejected, and the fix was to hand-place
  # a pinned cache dir because 'plugin install' silently refreshes the marketplace
  # clone to HEAD first, undoing any pin. RE-TESTED 2026-09-04 on CLI 2.1.260 in a
  # throwaway CLAUDE_CONFIG_DIR: upstream HEAD (367fdb7f) no longer has that key and
  # a plain install succeeds. Both versions' SessionStart hook was run directly and
  # both emit the same 'level: full' ruleset. So: plain install, no pin.
  # (The source box is still pinned at a0109974, 543 commits behind. Harmless, but
  # it means the desktop and a fresh box are not byte-identical on this one plugin.)
  claude plugin install caveman@caveman --scope user
  if ($LASTEXITCODE -eq 0) {
    Ok "caveman installed at user scope (enabled by settings.json)"
  } else {
    Failed "caveman install -- if it says 'agents: Invalid input' the upstream manifest regressed; pin to a0109974ea3258a14aadaef1ed1f8ff2837d30d5"
  }
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
