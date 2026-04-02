#!/usr/bin/env bash
set -euo pipefail

status=0

if command -v claude >/dev/null 2>&1; then
    echo "claude: found"
else
    echo "claude: missing"
    status=1
fi

if [ -n "${AMD_LLM_GATEWAY_KEY:-}" ]; then
    echo "AMD_LLM_GATEWAY_KEY: set"
else
    echo "AMD_LLM_GATEWAY_KEY: missing"
    status=1
fi

if [ -f "${HOME}/.claude/settings.json" ]; then
    echo "settings.json: found"
else
    echo "settings.json: missing"
    status=1
fi

exit "${status}"
