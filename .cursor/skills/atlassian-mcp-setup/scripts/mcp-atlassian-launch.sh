#!/usr/bin/env bash
# Launcher for the mcp-atlassian MCP server.
#
# Credentials live in ~/.atlassian.env (mode 600), NOT in ~/.claude.json, so the
# agent config stays safe to share and rotating a token touches one 600 file.
#
# Installed by setup_atlassian_mcp.sh to ~/.claude/mcp-atlassian-launch.sh and
# referenced from the MCP config as the bare command. Extra args (e.g.
# --read-only) are forwarded to mcp-atlassian.
set -euo pipefail

ENV_FILE="${ATLASSIAN_ENV_FILE:-$HOME/.atlassian.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "mcp-atlassian: credentials file not found: $ENV_FILE" >&2
  echo "mcp-atlassian: run setup_atlassian_mcp.sh, or create it by hand." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${JIRA_URL:-}" && -z "${CONFLUENCE_URL:-}" ]]; then
  echo "mcp-atlassian: neither JIRA_URL nor CONFLUENCE_URL set in $ENV_FILE" >&2
  exit 1
fi

# MCP servers inherit a minimal environment, not an interactive shell's PATH,
# so uvx from `pipx install uv` would otherwise be missing.
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uvx >/dev/null 2>&1; then
  echo "mcp-atlassian: uvx not found on PATH ($PATH)" >&2
  echo "mcp-atlassian: install it with 'pipx install uv'" >&2
  exit 1
fi

exec uvx mcp-atlassian "$@"
