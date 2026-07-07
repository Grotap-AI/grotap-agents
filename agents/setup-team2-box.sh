#!/bin/bash
# Onboard a Team 2 (open-model) fleet box — mirrors agent-04 baseline, minus claude CLI.
# Run as root on the box: ssh agent-NN "bash -s" < onboard_team2_box.sh
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq git tmux curl jq unzip python3-pip python3-venv pipx \
  apt-transport-https ca-certificates gnupg >/dev/null

# Node 22 (matches agent-04)
if ! command -v node >/dev/null || [[ "$(node --version)" != v22* ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
  apt-get install -y -qq nodejs >/dev/null
fi

# Doppler CLI
if ! command -v doppler >/dev/null; then
  curl -sLf --retry 3 https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key \
    | gpg --dearmor -o /usr/share/keyrings/doppler-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" \
    > /etc/apt/sources.list.d/doppler-cli.list
  apt-get update -qq && apt-get install -y -qq doppler >/dev/null
fi

# agent user + layout (mirrors agent-04)
id agent >/dev/null 2>&1 || useradd -m -s /bin/bash agent
mkdir -p /home/agent/bin /home/agent/worktrees

# Git credential helper — Doppler-backed, never a static token (GLOBAL.md rule)
cat > /home/agent/bin/git-credential-doppler <<'EOS'
#!/bin/sh
# git credential helper — env GITHUB_TOKEN first, then Doppler. Self-sufficient:
# safe to persist in .gitconfig (no dependency on the caller's environment).
tok="${GITHUB_TOKEN:-}"
[ -z "$tok" ] && tok="$(doppler secrets get GITHUB_TOKEN --project grotap --config prd --plain 2>/dev/null)"
echo username=x-access-token
echo "password=$tok"
EOS
chmod +x /home/agent/bin/git-credential-doppler
chown -R agent:agent /home/agent
su - agent -c "git config --global credential.helper '/home/agent/bin/git-credential-doppler' && git config --global user.name 'Grotap Agent' && git config --global user.email 'agents@grotap.com'"

# aider — Team 2 open-model runtime (pipx, isolated venv)
su - agent -c "pipx install aider-chat >/dev/null 2>&1 || pipx upgrade aider-chat >/dev/null 2>&1; pipx ensurepath >/dev/null 2>&1" \
  || echo "WARN: aider install failed (retry later)"

echo "BASE-OK $(hostname): node=$(node --version) doppler=$(doppler --version 2>/dev/null) aider=$(su - agent -c 'aider --version 2>/dev/null || echo pending')"
