#!/usr/bin/env bash
# Install and register the mcp-atlassian MCP server without ever placing a
# secret in agent config or in argv.
#
# The token is read from stdin (or $ATLASSIAN_API_TOKEN), never from a flag,
# so it cannot leak through `ps` or shell history.
set -euo pipefail

ENV_FILE="${ATLASSIAN_ENV_FILE:-$HOME/.atlassian.env}"
LAUNCHER="${ATLASSIAN_MCP_LAUNCHER:-$HOME/.claude/mcp-atlassian-launch.sh}"
SERVER_NAME="mcp-atlassian"
SCOPE="user"
DEPLOYMENT="cloud"
SITE=""
EMAIL=""
CONFLUENCE_URL=""
READ_ONLY=0
REGISTER=1

usage() {
  cat <<'USAGE'
Usage: setup_atlassian_mcp.sh --site URL [options]

Required:
  --site URL             Jira base URL, e.g. https://amd.atlassian.net
                         or https://jira.xilinx.com
  --email ADDR           Atlassian account email (cloud deployments only)

Options:
  --deployment cloud|server   Auth scheme. Default: inferred from --site
                              (*.atlassian.net => cloud, else server)
  --confluence-url URL        Default: <site>/wiki for cloud, unset for server
  --server-name NAME          MCP server name. Default: mcp-atlassian
  --scope user|local|project  claude mcp add scope. Default: user
  --read-only                 Register with write tools disabled
  --env-file PATH             Default: ~/.atlassian.env
  --no-register               Write env file + launcher, skip `claude mcp add`
  -h, --help                  This message

The API token is read from $ATLASSIAN_API_TOKEN if set, otherwise prompted for
with echo disabled, otherwise read from stdin when stdin is a pipe. It is never
accepted as a command-line argument.

Examples:
  setup_atlassian_mcp.sh --site https://amd.atlassian.net --email you@amd.com
  pass show atlassian | setup_atlassian_mcp.sh --site https://amd.atlassian.net --email you@amd.com
USAGE
}

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site) SITE="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --deployment) DEPLOYMENT="${2:-}"; shift 2 ;;
    --confluence-url) CONFLUENCE_URL="${2:-}"; shift 2 ;;
    --server-name) SERVER_NAME="${2:-}"; shift 2 ;;
    --scope) SCOPE="${2:-}"; shift 2 ;;
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --read-only) READ_ONLY=1; shift ;;
    --no-register) REGISTER=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --token|--api-token|--jira-api-token)
      die "refusing a token on the command line; it leaks via ps and shell history. Use stdin or \$ATLASSIAN_API_TOKEN." ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n "$SITE" ]] || { usage >&2; die "--site is required"; }
SITE="${SITE%/}"

# Infer deployment from the host unless the caller was explicit.
if [[ "$DEPLOYMENT" == "cloud" && "$SITE" != *".atlassian.net"* ]]; then
  DEPLOYMENT="server"
  echo "note: $SITE is not *.atlassian.net; assuming Server/Data Center (PAT auth)." >&2
  echo "      pass --deployment cloud to override." >&2
fi
[[ "$DEPLOYMENT" == "cloud" || "$DEPLOYMENT" == "server" ]] \
  || die "--deployment must be 'cloud' or 'server'"

if [[ "$DEPLOYMENT" == "cloud" ]]; then
  [[ -n "$EMAIL" ]] || die "--email is required for cloud deployments (Basic auth is email:token)"
  [[ "$EMAIL" == *"@"* ]] || die "--email does not look like an address: $EMAIL"
  [[ -n "$CONFLUENCE_URL" ]] || CONFLUENCE_URL="${SITE}/wiki"
fi

# --- 1. token ---------------------------------------------------------------
TOKEN="${ATLASSIAN_API_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  if [[ -t 0 ]]; then
    if [[ "$DEPLOYMENT" == "cloud" ]]; then
      echo "Create a CLASSIC API token (not 'with scopes') at:" >&2
      echo "  https://id.atlassian.com/manage-profile/security/api-tokens" >&2
    else
      echo "Create a Personal Access Token from your avatar > Profile > Personal Access Tokens" >&2
    fi
    read -r -s -p "Atlassian API token (input hidden): " TOKEN
    echo >&2
  else
    read -r TOKEN || true
  fi
fi
TOKEN="${TOKEN%%[[:space:]]}"
[[ -n "$TOKEN" ]] || die "no token supplied"

# --- 2. uvx -----------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uvx >/dev/null 2>&1; then
  echo "uvx not found; installing uv..." >&2
  if command -v pipx >/dev/null 2>&1; then
    pipx install uv >&2
  elif command -v pip3 >/dev/null 2>&1; then
    pip3 install --user uv >&2
  else
    die "neither pipx nor pip3 available; install uv manually (https://docs.astral.sh/uv/)"
  fi
  command -v uvx >/dev/null 2>&1 || die "uv installed but uvx still not on PATH"
fi

# --- 3. env file ------------------------------------------------------------
mkdir -p "$(dirname "$ENV_FILE")"
umask 077
if [[ "$DEPLOYMENT" == "cloud" ]]; then
  cat > "$ENV_FILE" <<EOF
# Atlassian Cloud credentials. Mode 600. Never commit; never copy into ~/.claude.json.
JIRA_URL=${SITE}
JIRA_USERNAME=${EMAIL}
JIRA_API_TOKEN=${TOKEN}

CONFLUENCE_URL=${CONFLUENCE_URL}
CONFLUENCE_USERNAME=${EMAIL}
CONFLUENCE_API_TOKEN=${TOKEN}
EOF
else
  {
    echo "# Atlassian Server/Data Center credentials. Mode 600. Never commit."
    echo "JIRA_URL=${SITE}"
    echo "JIRA_PERSONAL_TOKEN=${TOKEN}"
    if [[ -n "$CONFLUENCE_URL" ]]; then
      echo
      echo "CONFLUENCE_URL=${CONFLUENCE_URL}"
      echo "CONFLUENCE_PERSONAL_TOKEN=${TOKEN}"
    fi
  } > "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
unset TOKEN
echo "wrote $ENV_FILE (mode 600)" >&2

# --- 4. launcher ------------------------------------------------------------
mkdir -p "$(dirname "$LAUNCHER")"
SRC_LAUNCHER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mcp-atlassian-launch.sh"
if [[ -f "$SRC_LAUNCHER" ]]; then
  install -m 755 "$SRC_LAUNCHER" "$LAUNCHER"
else
  die "launcher template not found next to this script: $SRC_LAUNCHER"
fi
echo "installed launcher $LAUNCHER" >&2

# --- 5. register ------------------------------------------------------------
if [[ "$REGISTER" -eq 1 ]]; then
  if ! command -v claude >/dev/null 2>&1; then
    echo "warning: 'claude' not on PATH; skipping registration." >&2
    echo "         For Cursor, add this to your MCP config:" >&2
    echo "         {\"command\": \"$LAUNCHER\", \"args\": []}" >&2
  else
    claude mcp remove --scope "$SCOPE" "$SERVER_NAME" >/dev/null 2>&1 || true
    if [[ "$READ_ONLY" -eq 1 ]]; then
      claude mcp add "$SERVER_NAME" --scope "$SCOPE" -- "$LAUNCHER" --read-only
    else
      claude mcp add "$SERVER_NAME" --scope "$SCOPE" -- "$LAUNCHER"
    fi
    echo "registered MCP server '$SERVER_NAME' (scope: $SCOPE)" >&2
  fi
fi

# --- 6. verify --------------------------------------------------------------
HC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/healthcheck.sh"
if [[ -x "$HC" || -f "$HC" ]]; then
  echo >&2
  ATLASSIAN_ENV_FILE="$ENV_FILE" bash "$HC"
fi

cat >&2 <<EOF

Next: restart your agent session. MCP servers are launched at session start, so
the Atlassian tools are registered but not callable until you relaunch 'claude'
(or reload the Cursor window).
EOF
