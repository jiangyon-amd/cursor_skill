#!/usr/bin/env bash
# Prove Atlassian access end to end, in the order that actually isolates faults:
#   reachability -> credentials -> MCP registration
#
# Never prints the token. Exits non-zero on the first hard failure.
set -uo pipefail

ENV_FILE="${ATLASSIAN_ENV_FILE:-$HOME/.atlassian.env}"
RC=0

fail() { echo "FAIL: $*" >&2; RC=1; }
ok()   { echo "ok:   $*"; }
warn() { echo "warn: $*" >&2; }

# --- env file ---------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  fail "credentials file not found: $ENV_FILE"
  exit 1
fi
ok "env file: $ENV_FILE"

PERMS="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || echo '?')"
if [[ "$PERMS" != "600" ]]; then
  warn "env file mode is $PERMS, expected 600 — run: chmod 600 $ENV_FILE"
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${JIRA_URL:=}"
[[ -n "$JIRA_URL" ]] || { fail "JIRA_URL not set in $ENV_FILE"; exit 1; }
JIRA_URL="${JIRA_URL%/}"

if [[ "$JIRA_URL" == *".atlassian.net"* ]]; then
  DEPLOYMENT=cloud; API=3
else
  DEPLOYMENT=server; API=2
fi
ok "deployment: $DEPLOYMENT ($JIRA_URL, /rest/api/$API)"

# --- credential shape -------------------------------------------------------
if [[ "$DEPLOYMENT" == "cloud" ]]; then
  [[ -n "${JIRA_USERNAME:-}" ]]  || fail "JIRA_USERNAME (account email) not set — required for cloud Basic auth"
  [[ -n "${JIRA_API_TOKEN:-}" ]] || fail "JIRA_API_TOKEN not set"
  if [[ -n "${JIRA_PERSONAL_TOKEN:-}" ]]; then
    warn "JIRA_PERSONAL_TOKEN is set on a cloud site; that is Server/DC auth and will be ignored"
  fi
  AUTH=(-u "${JIRA_USERNAME:-}:${JIRA_API_TOKEN:-}")
  ok "account email: ${JIRA_USERNAME:-<unset>}"
else
  [[ -n "${JIRA_PERSONAL_TOKEN:-}" ]] || fail "JIRA_PERSONAL_TOKEN not set — required for Server/DC"
  if [[ -n "${JIRA_API_TOKEN:-}" ]]; then
    warn "JIRA_API_TOKEN is set on a Server/DC site; that is cloud auth and will be ignored"
  fi
  AUTH=(-H "Authorization: Bearer ${JIRA_PERSONAL_TOKEN:-}")
fi
[[ "$RC" -eq 0 ]] || exit 1

# --- 1. reachability (no credentials) ---------------------------------------
CODE="$(curl -s -m 20 -o /dev/null -w '%{http_code}' "$JIRA_URL/rest/api/$API/serverInfo" || echo 000)"
case "$CODE" in
  000) fail "cannot reach $JIRA_URL (network/proxy/VPN). Credentials not yet tested."; exit 1 ;;
  200|401|403) ok "site reachable (serverInfo -> HTTP $CODE)" ;;
  *)   warn "serverInfo returned HTTP $CODE; continuing" ;;
esac

# --- 2. credentials ---------------------------------------------------------
BODY="$(mktemp)"; HDRS="$(mktemp)"
trap 'rm -f "$BODY" "$HDRS"' EXIT
CODE="$(curl -s -m 30 -D "$HDRS" -o "$BODY" -w '%{http_code}' \
  "${AUTH[@]}" -H 'Accept: application/json' \
  "$JIRA_URL/rest/api/$API/myself" || echo 000)"

if [[ "$CODE" == "200" ]]; then
  WHO="$(python3 - "$BODY" <<'PY' 2>/dev/null || echo '?'
import json, sys
d = json.load(open(sys.argv[1]))
who = d.get("displayName") or "?"
ident = d.get("emailAddress") or d.get("name") or d.get("accountId") or "?"
print(f"{who} <{ident}>")
PY
)"
  ok "jira auth: HTTP 200 — $WHO"
else
  fail "jira auth: HTTP $CODE"
  if grep -qi 'AUTHENTICATED_FAILED' "$HDRS"; then
    echo "      x-seraph-loginreason: AUTHENTICATED_FAILED — the credential pair was rejected." >&2
    echo "      This is NOT a permissions problem. One of:" >&2
    if [[ "$DEPLOYMENT" == "cloud" ]]; then
      echo "        - wrong account email (confirm at id.atlassian.com/manage-profile/profile-and-visibility)" >&2
      echo "        - token revoked or mistyped" >&2
      echo "        - token was created 'with scopes'; those do not work against the site URL." >&2
      echo "          Create a CLASSIC token at id.atlassian.com/manage-profile/security/api-tokens" >&2
    else
      echo "        - PAT revoked/expired, or it belongs to a different Atlassian instance" >&2
    fi
  fi
  exit 1
fi

# --- 3. confluence (optional) -----------------------------------------------
if [[ -n "${CONFLUENCE_URL:-}" ]]; then
  CURL="${CONFLUENCE_URL%/}"
  if [[ "$DEPLOYMENT" == "cloud" && "$CURL" != */wiki ]]; then
    warn "CONFLUENCE_URL lacks the /wiki suffix; cloud Confluence lives at <site>/wiki"
  fi
  if [[ "$DEPLOYMENT" == "cloud" ]]; then
    CAUTH=(-u "${CONFLUENCE_USERNAME:-$JIRA_USERNAME}:${CONFLUENCE_API_TOKEN:-$JIRA_API_TOKEN}")
  else
    CAUTH=(-H "Authorization: Bearer ${CONFLUENCE_PERSONAL_TOKEN:-$JIRA_PERSONAL_TOKEN}")
  fi
  CODE="$(curl -s -m 30 -o /dev/null -w '%{http_code}' "${CAUTH[@]}" \
    -H 'Accept: application/json' "$CURL/rest/api/space?limit=1" || echo 000)"
  if [[ "$CODE" == "200" ]]; then
    ok "confluence auth: HTTP 200 ($CURL)"
  else
    warn "confluence auth: HTTP $CODE ($CURL) — jira still works; check the URL and /wiki suffix"
  fi
else
  warn "CONFLUENCE_URL not set; skipping confluence check"
fi

# --- 4. tooling + registration ----------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
command -v uvx >/dev/null 2>&1 && ok "uvx: found" || fail "uvx: not found (pipx install uv)"

LAUNCHER="${ATLASSIAN_MCP_LAUNCHER:-$HOME/.claude/mcp-atlassian-launch.sh}"
[[ -x "$LAUNCHER" ]] && ok "launcher: $LAUNCHER" || warn "launcher not executable: $LAUNCHER"

if command -v claude >/dev/null 2>&1; then
  if claude mcp list 2>/dev/null | grep -q 'mcp-atlassian'; then
    ok "mcp server registered (note: 'Connected' does NOT imply valid credentials)"
  else
    warn "mcp-atlassian not registered with the claude CLI"
  fi
fi

# --- config hygiene ---------------------------------------------------------
if [[ -f "$HOME/.claude.json" ]] && grep -qE 'JIRA_API_TOKEN|JIRA_PERSONAL_TOKEN|CONFLUENCE_API_TOKEN' "$HOME/.claude.json"; then
  fail "a token appears to be stored in ~/.claude.json — move it to $ENV_FILE and re-register with the launcher"
fi

echo
[[ "$RC" -eq 0 ]] && echo "healthcheck passed" || echo "healthcheck failed" >&2
exit "$RC"
